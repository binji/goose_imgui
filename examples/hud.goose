// A game's HUD over a scene: the player's health (in segments, with a trail
// that shows what a hit took) and stamina; a compass; a minimap; the quest
// tracked; a hotbar with a cooldown; bars and names over the enemies;
// damage numbers that float up; a marker at the screen's edge for a quest
// target that is off screen; the region's name as it is entered; and the
// controls. Click the ground to ping it.
//
// It is made from what imgui has now. Where a game's HUD wants something
// imgui lacks, a comment names the item of docs/future_work.md that would
// do it ("future work: notices"), and the code works around it.
//
//   goose examples/hud.goose [-- --frames 90 --screenshot hud.png]
import std;
import vec;
import math;
import gfx;
import gfx2d from "../../goose_gfx2d";
import imgui from "..";
import .common;

struct Enemy { name: u8[..16] = [], home: float2, pos: float2 = float2 { 0.0, 0.0 }, hp: f64, max_hp: f64 }
struct Damage { key: i64, pos: float2, amount: i64, born: f64 }
struct Ping { pos: float2, born: f64 }

var enemies: Enemy[>..] = [];
var damage: Damage[>..] = [];
var next_damage = 0;
var pings: Ping[>..] = [];
var rocks: float4[>..] = [];        // x, y, radius, shade
var swing_at = 0.0;
var seed = rng { 7 };

let SHRINE = float2 { 980.0, -560.0 };
let INK = 0xF1EDE4;
let HP_RED = 0xE0455A;
let GOLD = 0xF2B53C;
let SLOTS = [0x9C5BE0, 0xE0455A, 0x3D7DE0, 0x2EBE7A, 0xF2B53C, 0xE8E4DA];
let COUNTS = [1, 3, 12, 0, 5, 1];

fn f2(x: f64, y: f64) -> float2 { float2 { x as f32, y as f32 } }
fn rgb(c: i64) -> gfx2d::Color { gfx2d::rgb(c) }
fn rgba(c: i64, a: f64) -> gfx2d::Color { gfx2d::rgba(c, a) }

// The player walks an ellipse; the camera follows.
fn player_at(t: f64) -> float2 { f2(cos(t * 0.3) * 300.0, sin(t * 0.3) * 180.0) }
// Degrees clockwise from north (up), the way a compass reads.
fn heading_at(t: f64) -> f64 {
    let d = player_at(t + 0.05) - player_at(t);
    bearing(d)
}
fn bearing(d: float2) -> f64 {
    let b = atan2(d.x, -d.y) * 180.0 / PI;
    if b < 0.0 { b + 360.0 } else { b }
}
// From a to b the short way round, -180 to 180.
fn turn(a: f64, b: f64) -> f64 {
    var d = b - a;
    while d > 180.0 { d -= 360.0; }
    while d < -180.0 { d += 360.0; }
    d
}

fn setup() {
    let names = ["Ash Wraith", "Cinder Hound", "Ash Wraith", "Ember Imp", "Cinder Hound", "Ember Imp"];
    let homes = [f2(260, 120), f2(-200, 260), f2(-340, -60), f2(120, -230), f2(380, -120), f2(-60, 90)];
    for n, k in names {
        let hp = 60.0 + 20.0 * (k % 3);
        var e = Enemy { home: homes[k], hp: hp, max_hp: hp, .. };
        format(e.name, n);
        enemies.push(e);
    }
    for k in 70 {
        rocks.push(float4 { (rand_flt(seed) * 2400.0 - 1200.0) as f32, (rand_flt(seed) * 1600.0 - 800.0) as f32,
                            (6.0 + rand_flt(seed) * 22.0) as f32, rand_flt(seed) as f32 });
    }
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
    damage.push(Damage { next_damage, enemies[best].pos + f2(rand_flt(seed) * 30.0 - 15.0, 0.0), amount, t });
    next_damage++;
}

// The scene, under the HUD, in the UI's units: `cam` is at the center.
fn draw_world(cam: float2, view: float2, t: f64) {
    let o = view * 0.5 - cam;
    let grid = 80.0;
    let line = rgba(0xFFFFFF, 0.04);
    var x = floor(-o.x / grid) * grid;
    while x < -o.x + view.x { gfx2d::line(x + o.x, 0.0, x + o.x, view.y, 1.0, line); x += grid; }
    var y = floor(-o.y / grid) * grid;
    while y < -o.y + view.y { gfx2d::line(0.0, y + o.y, view.x, y + o.y, 1.0, line); y += grid; }
    for r in rocks {
        gfx2d::circle(r.x + o.x + 3.0, r.y + o.y + 4.0, r.z, rgba(0x000000, 0.25));
        gfx2d::circle(r.x + o.x, r.y + o.y, r.z, gfx2d::mix(rgb(0x3A4A3C), rgb(0x56604F), r.w));
    }
    let s = SHRINE + o;
    gfx2d::circle(s.x, s.y, 46.0 + 6.0 * sin(t * 2.0), rgba(GOLD, 0.12));
    gfx2d::circle(s.x, s.y, 18.0, rgb(0x6A5A40));
    gfx2d::circle(s.x, s.y, 8.0, rgb(GOLD));
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
    // The player: a disk, and a wedge pointing where it walks.
    let c = view * 0.5;
    let a = (heading_at(t) - 90.0) * PI / 180.0;
    gfx2d::circle(c.x + 2.0, c.y + 4.0, 16.0, rgba(0x000000, 0.3));
    gfx2d::circle(c.x, c.y, 16.0, rgb(0x3D7DE0));
    gfx2d::polygon([f2(c.x + cos(a) * 26.0, c.y + sin(a) * 26.0),
                    f2(c.x + cos(a + 2.5) * 14.0, c.y + sin(a + 2.5) * 14.0),
                    f2(c.x + cos(a - 2.5) * 14.0, c.y + sin(a - 2.5) * 14.0)], rgb(INK));
}

// A translucent panel for the HUD's corners.
fn hud_panel(d: imgui::Desc) -> imgui::Desc { d.bg(rgba(0x0B0F14, 0.62)).radius(10).padding(12) }

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

let REGION = "ASHEN HOLLOW";
let QUEST = "THE EMBER SHRINE";
// Text over the scene, shadowed to be read on any ground.
let SHADE = 0x05070A;

fn main() {
    setup();
    make_meters();
    parse_args();
    run("imgui: hud", 1280, 720) {
        let t = imgui::time();
        let me = player_at(t);
        let heading = heading_at(t);
        let scale = gfx2d::current_scale() * imgui::ui_scale_of();
        let ss = gfx::screen_size();
        let view = f2(ss.x / scale, ss.y / scale);
        let center = view * 0.5;
        fn to_screen(p: float2) -> float2 { p - me + center }
        step(t, me);
        gfx2d::frame(rgb(0x26332A)) {
            gfx2d::scale(imgui::ui_scale_of()) { draw_world(me, view, t); };
            imgui::frame(frame_dt()) {
                // A click on the ground, not on the HUD, pings it. The
                // player's panel and the hotbar take the pointer; the
                // quest and the controls are passthrough, so a click on
                // them reaches the ground.
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

                // Damage numbers rise and fade, outlined and shadowed. Each
                // is isolated, so that as it fades its outline doesn't show
                // through its glyphs. The program keeps each until it is
                // done: future work: notices.
                k = 0;
                while k < damage.len {
                    let d = damage[k];
                    let age = t - d.born;
                    if age > 0.9 { damage[k] = damage[damage.len - 1]; damage.pop(); continue; }
                    let s = to_screen(d.pos);
                    let pop = 1.0 + 0.5 * max(1.0 - age * 8.0, 0.0);
                    imgui::box(imgui::id(str("dmg", d.key)), imgui::stack().absolute(s.x, s.y - 70.0 - age * 50.0).pivot(0.5, 0)
                                                              .opacity(1.0 - age * age / 0.81).scale(pop)
                                                              .isolate()) {
                        imgui::textf(imgui::column().text_size(22).ink(rgb(0xFFE08A)).place(imgui::CENTER, imgui::CENTER)
                                       .text_outline(1.4, rgb(0x5A2A08)).text_shadow(rgba(SHADE, 0.6), 0, 2)) { out =>
                            format(out, d.amount);
                        };
                    };
                    k++;
                }

                // The shrine: a marker over it on screen, or at the screen's
                // edge pointing to it. The arrow's points are turned by hand
                // (future work: rotation and skew).
                let dist = length(SHRINE - me) as f64;
                let at, ang, seen = imgui::edge_clamp(to_screen(SHRINE), 56);
                let off = !seen;
                // Placed by its top center, 20 above the point: the middle of
                // its 40-pixel ring.
                imgui::box("shrine marker", imgui::column().absolute(at.x, at.y - 20.0).pivot(0.5, 0).align(imgui::CENTER).gap(2)) {
                    imgui::canvas("arrow", imgui::column().size(40, 40)) { size =>
                        let c = size * 0.5;
                        imgui::fill_circle(c.x, c.y, 13, rgba(0x0B0F14, 0.7));
                        imgui::stroke_circle(c.x, c.y, 13, 2, rgb(GOLD));
                        imgui::fill_circle(c.x, c.y, 4, rgb(GOLD));
                        if off {
                            fn p(r: f64, da: f64) -> float2 { f2(c.x + cos(ang + da) * r, c.y + sin(ang + da) * r) }
                            imgui::fill_polygon([p(20, 0), p(14, 0.45), p(14, -0.45)], rgb(GOLD));
                        }
                    };
                    imgui::textf(imgui::column().text_size(12).ink(rgb(INK))) { out => format(out, round(dist / 4.0) as i64, " m"); };
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

                    // Top center: the compass, drawn on a canvas.
                    imgui::box("compass", imgui::column().align(imgui::CENTER).gap(2).place(imgui::CENTER, imgui::START)) {
                        imgui::canvas("strip", imgui::column().size(460, 34).bg(rgba(0x0B0F14, 0.5)).radius(6).clip()) { size =>
                            let span = 100.0;        // degrees each way
                            fn x_of(b: f64) -> f64 { size.x * 0.5 + turn(heading, b) / span * size.x * 0.5 }
                            let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
                            for n in 24 {
                                let b = n * 15.0;
                                if abs(turn(heading, b)) > span { continue; }
                                let x = x_of(b);
                                if n % 3 == 0 {
                                    let major = n % 6 == 0;
                                    imgui::draw_text(x, size.y * 0.5, names[n / 3], if major { 16.0 } else { 12.0 },
                                                     if major { rgb(INK) } else { rgba(INK, 0.7) },
                                                     gfx2d::ALIGN_CENTER, gfx2d::BASELINE_MIDDLE);
                                } else {
                                    imgui::draw_line(x, size.y - 9.0, x, size.y - 3.0, 1.5, rgba(INK, 0.4));
                                }
                            }
                            let q = bearing(SHRINE - me);
                            if abs(turn(heading, q)) <= span {
                                let x = x_of(q);
                                imgui::fill_polygon([f2(x, 3), f2(x + 5, 8), f2(x, 13), f2(x - 5, 8)], rgb(GOLD));
                            }
                            imgui::fill_polygon([f2(size.x * 0.5 - 6.0, size.y), f2(size.x * 0.5 + 6.0, size.y),
                                                 f2(size.x * 0.5, size.y - 7.0)], rgb(INK));
                        };
                        imgui::textf(imgui::column().text_size(12).ink(rgba(INK, 0.75))) { out =>
                            format(out, (round(heading) as i64) % 360);
                        };
                    };

                    // Top right: the minimap, and the quest under it.
                    imgui::box("right", imgui::column().gap(12).align(imgui::END).place(imgui::END, imgui::START)) {
                        // North stays up: a map that turns with the player
                        // needs a canvas transform (future work: rotation
                        // and skew).
                        imgui::canvas("minimap", imgui::column().size(170, 170).radius(85).clip().bg(rgba(0x0B0F14, 0.65))
                                                 .border(2, rgba(INK, 0.5))) { size =>
                            let c = size * 0.5;
                            let zoom = 0.14;
                            fn m(p: float2) -> float2 { c + (p - me) * zoom as f32 }
                            for r in rocks {
                                let q = m(f2(r.x, r.y));
                                imgui::fill_circle(q.x, q.y, max(r.z * zoom, 1.5), rgba(INK, 0.12));
                            }
                            for i in enemies.len {
                                let q = m(enemies[i].pos);
                                imgui::fill_circle(q.x, q.y, 3.5, rgb(HP_RED));
                            }
                            // The shrine, held at the rim if it is further.
                            var q = m(SHRINE) - c;
                            let lq = length(q) as f64;
                            if lq > 74.0 { q = q * (74.0 / lq) as f32; }
                            imgui::fill_polygon([f2(c.x + q.x, c.y + q.y - 6.0), f2(c.x + q.x + 6.0, c.y + q.y),
                                                 f2(c.x + q.x, c.y + q.y + 6.0), f2(c.x + q.x - 6.0, c.y + q.y)], rgb(GOLD));
                            let a = (heading - 90.0) * PI / 180.0;
                            fn p(r: f64, da: f64) -> float2 { f2(c.x + cos(a + da) * r, c.y + sin(a + da) * r) }
                            imgui::fill_polygon([p(9, 0), p(7, 2.4), p(7, -2.4)], rgb(0x7FD3FF));
                        };
                        imgui::box("quest", hud_panel(imgui::column().gap(4).align(imgui::END)).passthrough()) {
                            imgui::text(QUEST, imgui::column().text_size(12).letter_spacing(3).ink(rgb(GOLD)));
                            imgui::text("Light the brazier at the shrine", imgui::column().text_size(14).ink(rgb(INK)));
                            imgui::textf(imgui::column().text_size(12).ink(rgba(INK, 0.6))) { out =>
                                format(out, round(dist / 4.0) as i64, " m away");
                            };
                        };
                    };

                    // Bottom center: the hotbar. Slot 2's cooldown is a sweep
                    // of what is left, bigger than the slot, clipped by it.
                    imgui::box("hotbar", hud_panel(imgui::row().gap(8)).padding(8).place(imgui::CENTER, imgui::END)) {
                        for c, i in SLOTS {
                            let chosen = i == 0;
                            imgui::box(i, imgui::stack().size(56, 56).radius(8).bg(rgba(0xFFFFFF, if chosen { 0.16 } else { 0.06 }))
                                            .border(if chosen { 2.0 } else { 1.0 }, if chosen { rgb(GOLD) } else { rgba(INK, 0.15) }).clip()) {
                                imgui::panel(imgui::column().size(28, 28).radius(if i % 2 == 0 { 14.0 } else { 6.0 })
                                             .bg(gfx2d::lighten(rgb(c), 0.2), rgb(c)).place(imgui::CENTER, imgui::CENTER));
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

                    // Bottom right: the controls. A pad would want its own
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

                    // The region's name, for a few seconds after arriving. It
                    // is drawn while it fades out by the program keeping it:
                    // future work: exit transitions, and notices.
                    let bt, alive = imgui::presence("region", t > 0.4 && t < 3.6, imgui::tween(0.6, imgui::EASE_OUT_CUBIC));
                    if alive {
                        imgui::box("region", imgui::column().align(imgui::CENTER).gap(6).place(imgui::CENTER, imgui::START)
                                               .offset(0, 120 + (1.0 - bt) * 16.0).opacity(bt)) {
                            imgui::text(REGION, imgui::column().text_size(34).letter_spacing(10).ink(rgb(INK))
                                                    .text_shadow(rgba(SHADE, 0.7), 0, 2));
                            imgui::panel(imgui::column().size(260 * bt, 1).bg(rgba(INK, 0.6)));
                            imgui::text("The Cinder Reaches", imgui::column().text_size(14).ink(rgba(INK, 0.7)));
                        };
                    }
                };
            };
        };
    };
}
