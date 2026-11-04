// An action game's HUD over a scene: the player's health (in segments, with
// a trail that shows what a hit took) and stamina; names and bars over the
// enemies, placed by their bottom center; damage numbers that rise and
// fade, outlined and shadowed; a hotbar with counts, a cooldown and gems
// turned into diamonds; the region's name as it is entered; and the
// controls. Click the ground to ping it: the player's panel and the hotbar
// take the pointer, the controls let it through.
//
// Where a game's HUD wants something imgui lacks, a comment names the item
// of docs/future_work.md that would do it ("future work: gamepads"), and the
// code works around it. See also wayfinding.goose (a compass, a minimap,
// markers) and cards.goose (a hand of cards).
//
//   goose examples/hud.goose [-- --frames 90 --screenshot hud.png]
import std;
import vec;
import math;
import gfx;
import gfx2d from "../../goose_gfx2d";
import imgui from "..";
import .common;
import .scene;

struct Enemy { name: u8[..16] = [], home: float2, pos: float2 = float2 { 0.0, 0.0 }, hp: f64, max_hp: f64 }
struct Ping { pos: float2, born: f64 }

var enemies: Enemy[>..] = [];
var pings: Ping[>..] = [];
var swing_at = 0.0;
var region_told = false;

// Notices: hits, each a damage number over where it landed, and the
// region's name as it is entered.
struct Hit { amount: i64, at: float2 }
var hits = imgui::Notices<Hit> { .. };
var banner = imgui::TextNotices { .. };
var seed = rng { 7 };

let HP_RED = 0xE0455A;
let SLOTS = [0x9C5BE0, 0xE0455A, 0x3D7DE0, 0x2EBE7A, 0xF2B53C, 0xE8E4DA];
let COUNTS = [1, 3, 12, 0, 5, 1];
let REGION = "ASHEN HOLLOW";

fn setup() {
    let names = ["Ash Wraith", "Cinder Hound", "Ash Wraith", "Ember Imp", "Cinder Hound", "Ember Imp"];
    let homes = [f2(260, 120), f2(-200, 260), f2(-340, -60), f2(120, -230), f2(380, -120), f2(-60, 90)];
    for n, k in names {
        let hp = 60.0 + 20.0 * (k % 3);
        var e = Enemy { home: homes[k], hp: hp, max_hp: hp, .. };
        format(e.name, n);
        enemies.push(e);
    }
    make_rocks(seed);
}

// The game's step: the enemies wander, and every so often the player hits
// the nearest one in reach.
fn step(t: f64, me: float2) {
    for k in enemies.len {
        enemies[k].pos = enemies[k].home + f2(sin(t * 0.7 + k) * 40.0, cos(t * 0.5 + k * 2.0) * 30.0);
    }
    guard t >= swing_at;
    swing_at = t + 0.55;
    var best = -1;
    var best_d = 340.0;
    for k in enemies.len {
        let d: f64 = length(enemies[k].pos - me);
        if d < best_d { best = k; best_d = d; }
    }
    guard best >= 0;
    let amount = 6 + rand_int(seed, 22);
    enemies[best].hp -= amount;
    if enemies[best].hp <= 0.0 { enemies[best].hp = enemies[best].max_hp; }
    // A notice, posted once: imgui keeps it and drops it when its time is up.
    imgui::notify(hits, Hit { amount, enemies[best].pos + f2(rand_flt(seed) * 30.0 - 15.0, 0.0) }, 0.6);
}

// The enemies and the pings, over the ground.
fn draw_world(cam: float2, view: float2, t: f64) {
    draw_ground(cam, view);
    let o = view * 0.5 - cam;
    for p in pings {
        let age = t - p.born;
        gfx2d::circle_outline(p.pos.x + o.x, p.pos.y + o.y, 8.0 + age * 40.0, 3.0, rgba(0x7FD3FF, max(1.0 - age / 1.5, 0.0)));
    }
    for k in enemies.len {
        let e = enemies[k];
        gfx2d::circle(e.pos.x + o.x + 2.0, e.pos.y + o.y + 4.0, 15.0, rgba(0x000000, 0.3));
        gfx2d::circle(e.pos.x + o.x, e.pos.y + o.y, 15.0, rgb(0x8A2E3A));
        gfx2d::circle(e.pos.x + o.x, e.pos.y + o.y - 3.0, 6.0, rgb(0xF2A0A8));
    }
    draw_player(view, t);
}

// The meters' looks, made in main: a red bar in segments whose trail eases
// down after a hit; one for the enemies, whole; stamina in green; and a
// cooldown, a dark sweep over a slot.
var health_bar = imgui::Meter { .. };
var enemy_bar = imgui::Meter { .. };
var stamina_bar = imgui::Meter { .. };
var cooldown = imgui::Meter { .. };

fn bar_class(c: gfx2d::Color) -> imgui::StyleClass {
    imgui::add_class(imgui::style_set(imgui::Style { bg: c, radius: imgui::radii(2.0) }))
}
fn make_meters() {
    let track = bar_class(rgba(0x000000, 0.45));
    let trail = bar_class(rgba(INK, 0.75));
    let ease = imgui::tween(0.5, imgui::EASE_IN_OUT_CUBIC).delay(0.35);
    health_bar = imgui::Meter { segments: 5, trail: ease, track_class: track, fill_class: bar_class(rgb(HP_RED)),
                                trail_class: trail, .. };
    enemy_bar = health_bar;
    enemy_bar.segments = 1;
    stamina_bar = imgui::Meter { track_class: track, fill_class: bar_class(rgb(0x2EBE7A)), .. };
    cooldown = imgui::Meter { track_class: imgui::add_class(imgui::style_set(imgui::Style { .. })),
                              fill_class: bar_class(rgba(0x000000, 0.6)), .. };
}

fn main() {
    setup();
    make_meters();
    parse_args();
    run("imgui: hud", 1280, 720) {
        let t = imgui::time();
        let me = player_at(t);
        let view = view_size();
        let center = view * 0.5;
        fn to_screen(p: float2) -> float2 { p - me + center }
        step(t, me);
        gfx2d::frame(rgb(0x26332A)) {
            gfx2d::scale(imgui::ui_scale_of()) { draw_world(me, view, t); };
            imgui::frame(frame_dt()) {
                // A click on the ground, not on the HUD, pings it.
                if gfx::mouse_pressed(gfx::MOUSE_LEFT) && !imgui::wants_pointer() {
                    pings.push(Ping { imgui::pointer().pos - center + me, t });
                }
                var k = 0;
                while k < pings.len {
                    if t - pings[k].born > 1.5 { pings[k] = pings[pings.len - 1]; pings.pop(); } else { k++; }
                }

                // Over each enemy, its name and health, placed by their
                // bottom center just above it.
                for i in enemies.len {
                    let e = enemies[i];
                    let s = to_screen(e.pos);
                    if s.x < -60.0 || s.y < -60.0 || s.x > view.x + 60.0 || s.y > view.y + 60.0 { continue; }
                    imgui::box(i, imgui::column().absolute(s.x, s.y - 22.0).pivot(0.5, 1).align(imgui::CENTER).gap(3)) {
                        imgui::text(e.name, imgui::column().text_size(12).ink(rgb(INK)).text_shadow(rgba(SHADE, 0.8)));
                        imgui::meter("hp", e.hp / e.max_hp, imgui::row().size(56, 6), enemy_bar);
                    };
                }

                // Damage numbers rise, outlined and shadowed, and slide on
                // up as they fade out. Each is isolated, so that as it
                // fades its outline doesn't show through its glyphs.
                imgui::notices(hits, imgui::stack().grow()) { n =>
                    let age = n.age();
                    let s = to_screen(n.data.at);
                    let pop = 1.0 + 0.5 * max(1.0 - age * 8.0, 0.0);
                    imgui::box(n.id(), imgui::stack().absolute(s.x, s.y - 70.0 - age * 50.0).pivot(0.5, 0).scale(pop)
                                         .isolate().exit(imgui::slide_out(0, -15, imgui::tween(0.3, imgui::EASE_LINEAR)))) {
                        imgui::textf(imgui::column().text_size(22).ink(rgb(0xFFE08A)).place(imgui::CENTER, imgui::CENTER)
                                       .text_outline(1.4, rgb(0x5A2A08)).text_shadow(rgba(SHADE, 0.6), 0, 2)) { out =>
                            format(out, n.data.amount);
                        };
                    };
                };

                // The corners, kept clear of the screen's edges.
                imgui::box("corners", imgui::stack().grow().padding(20)) {
                    // Top left: the player.
                    imgui::box("player", hud_panel(imgui::row().gap(12).align(imgui::CENTER)).place(imgui::START, imgui::START)) {
                        imgui::panel(imgui::column().size(48, 48).radius(24).bg(rgb(0x6FA0F0), rgb(0x2E5DB0))
                                     .border(2, rgba(INK, 0.8)));
                        imgui::box(imgui::column().gap(6)) {
                            imgui::box(imgui::row().gap(8).align(imgui::END)) {
                                imgui::text("Wren", imgui::column().text_size(17).ink(rgb(INK)));
                                imgui::text("Lv 12", imgui::column().text_size(12).ink(rgba(INK, 0.6)));
                            };
                            let hp = 0.55 + 0.3 * sin(t * 0.8) * (if sin(t * 2.3) > 0.0 { 1.0 } else { 0.6 });
                            imgui::meter("health", hp, imgui::row().size(220, 12), health_bar);
                            imgui::meter("stamina", 0.5 + 0.5 * sin(t * 1.3), imgui::row().size(220, 5), stamina_bar);
                        };
                    };

                    // Bottom center: the hotbar. Slot 2's cooldown is a sweep
                    // of what is left, bigger than the slot, clipped by it.
                    imgui::box("hotbar", hud_panel(imgui::row().gap(8)).padding(8).place(imgui::CENTER, imgui::END)) {
                        for c, i in SLOTS {
                            let chosen = i == 0;
                            imgui::box(i, imgui::stack().size(56, 56).radius(8).bg(rgba(0xFFFFFF, if chosen { 0.16 } else { 0.06 }))
                                            .border(if chosen { 2.0 } else { 1.0 }, if chosen { rgb(GOLD) } else { rgba(INK, 0.15) }).clip()) {
                                // Round gems, and square ones turned into diamonds.
                                imgui::panel(imgui::column().size(26, 26).radius(if i % 2 == 0 { 13.0 } else { 4.0 })
                                             .bg(gfx2d::lighten(rgb(c), 0.2), rgb(c)).place(imgui::CENTER, imgui::CENTER)
                                             .rotate(if i % 2 == 0 { 0.0 } else { PI * 0.25 }));
                                imgui::textf(imgui::column().text_size(11).ink(rgba(INK, 0.7)).place(imgui::START, imgui::START)
                                               .padding(5, 3)) { out => format(out, i + 1); };
                                if COUNTS[i] > 1 {
                                    imgui::textf(imgui::column().text_size(12).ink(rgb(INK)).place(imgui::END, imgui::END)
                                                   .padding(5, 3)) { out => format(out, COUNTS[i]); };
                                }
                                if i == 1 {
                                    let left = 1.0 - (t / 4.0 - floor(t / 4.0));
                                    imgui::radial_meter("cooldown", left, imgui::column().size(80, 80)
                                                                .place(imgui::CENTER, imgui::CENTER), cooldown);
                                    imgui::textf(imgui::column().text_size(18).ink(rgb(INK)).place(imgui::CENTER, imgui::CENTER))
                                        { out => format(out, min(floor(left * 4.0) as i64 + 1, 4)); };
                                }
                                if COUNTS[i] == 0 {
                                    imgui::panel(imgui::column().grow().radius(8).bg(rgba(0x000000, 0.55)).place(imgui::START, imgui::START));
                                }
                            };
                        }
                    };

                    // Bottom right: the controls, passthrough, so a click on
                    // them reaches the ground. A pad would want its own
                    // glyphs here: future work: prompts for the device in
                    // use.
                    imgui::box("controls", imgui::row().gap(14).align(imgui::CENTER).place(imgui::END, imgui::END)
                                             .passthrough()) {
                        for pair in [["Click", "Ping"], ["Esc", "Quit"]] {
                            imgui::box(imgui::row().gap(6).align(imgui::CENTER)) {
                                imgui::box(imgui::row().bg(rgba(INK, 0.85)).radius(4).padding(6, 2)) {
                                    imgui::text(pair[0], imgui::column().text_size(12).ink(rgb(0x0B0F14)));
                                };
                                imgui::text(pair[1], imgui::column().text_size(13).ink(rgb(INK)));
                            };
                        }
                    };

                    // The region's name, for a few seconds after arriving:
                    // posted once, sliding in, its rule drawn out, and
                    // sinking as it fades.
                    if t > 0.4 && !region_told {
                        region_told = true;
                        imgui::notify(banner, REGION, 3.2);
                    }
                    imgui::notices(banner, imgui::column().place(imgui::CENTER, imgui::START).offset(0, 120)) { n =>
                        let m = imgui::tween(0.6, imgui::EASE_OUT_CUBIC);
                        imgui::box(n.id(), imgui::column().align(imgui::CENTER).gap(6)
                                             .enter(imgui::slide_in(0, 16, m)).exit(imgui::slide_out(0, 16, m))) {
                            imgui::text(n.text, imgui::column().text_size(34).letter_spacing(10).ink(rgb(INK))
                                                    .text_shadow(rgba(SHADE, 0.7), 0, 2));
                            let drawn = imgui::ease(imgui::EASE_OUT_CUBIC, min(n.age() / 0.6, 1.0));
                            imgui::panel(imgui::column().size(260 * drawn, 1).bg(rgba(INK, 0.6)));
                            imgui::text("The Cinder Reaches", imgui::column().text_size(14).ink(rgba(INK, 0.7)));
                        };
                    };
                };
            };
        };
    };
}
