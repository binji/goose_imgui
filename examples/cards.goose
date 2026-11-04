// A card battler's table: a hand of cards fanned (each turned, and hit where
// it is drawn), the one under the pointer rising to the front; played, a
// card leaves and the rest glide and turn to their new places. The energy
// is an orb filled to its level (a canvas clipped to a circle); the enemy's
// health has a trail that shows what a card took; End turn is a slanted
// button. Drag a card onto the enemy to play it, or click it.
//
//   goose examples/cards.goose [-- --frames 90 --screenshot cards.png]
import std;
import vec;
import math;
import gfx;
import gfx2d from "../../goose_gfx2d";
import imgui from "..";
import .common;

let INK = 0xF4EFE6;
let SHADE = 0x07060A;
let NAMES = ["Strike", "Ember", "Ward", "Strike", "Mend"];
let COSTS = [1, 2, 1, 1, 1];
let DAMAGE = [6, 12, 0, 6, 0];
let BLOCK = [0, 0, 5, 0, 0];
let HEAL = [0, 0, 0, 0, 6];
let RULES = ["Deal 6 damage.", "Deal 12 damage.", "Gain 5 block.", "Deal 6 damage.", "Heal 6."];
let COLORS = [0xC8484F, 0xE2702C, 0x3D7DE0, 0xC8484F, 0x2EAE6A];
let MAX_ENERGY = 3;

struct Hit { key: i64, amount: i64, born: f64 }
let CARD = 1;                   // what drag and drop carries: a card's place in the hand

var hand: i64[>..] = [];            // the cards held, by index into the tables
var energy = 3;
var enemy_hp: f64 = 60.0;
var player_hp: f64 = 60.0;
var armor = 0;
var hits: Hit[>..] = [];
var next_hit = 0;

fn rgb(c: i64) -> gfx2d::Color { gfx2d::rgb(c) }
fn rgba(c: i64, a: f64) -> gfx2d::Color { gfx2d::rgba(c, a) }
fn f2(x: f64, y: f64) -> float2 { float2 { x as f32, y as f32 } }

fn new_turn() {
    hand.clear();
    for k in NAMES.len { hand.push(k); }
    energy = MAX_ENERGY;
}

fn play(slot: i64, t: f64) {
    let c = hand[slot];
    guard COSTS[c] <= energy;
    energy -= COSTS[c];
    if DAMAGE[c] > 0 {
        enemy_hp -= DAMAGE[c];
        hits.push(Hit { next_hit, DAMAGE[c], t });
        next_hit++;
        if enemy_hp <= 0.0 { enemy_hp = 60.0; }
    }
    armor += BLOCK[c];
    player_hp = min(player_hp + HEAL[c], 60.0);
    remove_at(hand, slot);
}

fn end_turn() {
    // The enemy strikes for 9, less the block.
    player_hp = max(player_hp - max(9 - armor, 0), 1.0);
    armor = 0;
    new_turn();
}

// A meter's fill in a color of its own.
fn bar(c: gfx2d::Color) -> imgui::StyleClass {
    imgui::add_class(imgui::style_set(imgui::Style { bg: c, radius: imgui::radii(3.0) }))
}

// Where the k-th of n cards goes in the hand: along an arc, turned out from
// its middle.
fn fan(k: i64, n: i64) -> float2, f64 {
    let f = k - (n - 1) * 0.5;
    return f2(320.0 + f * 96.0, 190.0 + f * f * 7.0), f * 0.11;
}

// The energy orb: a sphere clipped to a circle, filled to the level with a
// moving wave, and how much there is.
fn orb(level: f64, t: f64) {
    imgui::canvas("orb", imgui::column().size(96, 96)) { size =>
        let c = size * 0.5;
        let r = 40.0;
        imgui::fill_circle(c.x, c.y, r + 5.0, rgb(0x2A1E14));
        imgui::fill_circle(c.x, c.y, r, rgb(0x120E16));
        imgui::clip_circle(c.x, c.y, r) {
            let top = c.y + r - 2.0 * r * level;
            var wave: float2[>..] = [];
            for k in 25 {
                let x = c.x - r + 2.0 * r * k / 24.0;
                wave.push(f2(x, top + sin(t * 3.0 + k * 0.5) * 3.0));
            }
            wave.push(f2(c.x + r, c.y + r));
            wave.push(f2(c.x - r, c.y + r));
            imgui::fill_polygon(wave, rgb(0xF0A030));
            imgui::fill_circle(c.x - 12.0, c.y - 14.0, 10, rgba(0xFFFFFF, 0.18));
        };
        imgui::stroke_circle(c.x, c.y, r + 2.5, 3, rgb(0xC08A3A));
    };
}

// A card's face: its name, its picture, its rules, its cost in a diamond
// (a square turned).
fn card_face(c: i64) {
    imgui::box(imgui::column().grow().padding(12, 26, 12, 12).gap(8).align(imgui::CENTER)
                 .radius(10).border(3, rgb(0xE8D8B0))
                 .bg(gfx2d::lighten(rgb(COLORS[c]), 0.12), gfx2d::darken(rgb(COLORS[c]), 0.45))) {
        imgui::text(NAMES[c], imgui::column().text_size(17).ink(rgb(INK)).text_shadow(rgba(SHADE, 0.7)));
        imgui::panel(imgui::column().size(70, 60).radius(6).bg(rgba(0xFFFFFF, 0.18)));
        imgui::text(RULES[c], imgui::column().text_size(13).ink(rgb(INK)).wrap().grow_w().justify(imgui::CENTER));
    };
    imgui::box(imgui::stack().size(30, 30).place(imgui::START, imgui::START).offset(-8, -8)) {
        imgui::panel(imgui::column().size(26, 26).radius(4).bg(rgb(0xF0A030)).border(2, rgb(0x2A1E14))
                     .place(imgui::CENTER, imgui::CENTER).rotate(PI * 0.25));
        imgui::textf(imgui::column().text_size(16).ink(rgb(0x2A1E14)).place(imgui::CENTER, imgui::CENTER))
            { out => format(out, COSTS[c]); };
    };
}

fn main() {
    new_turn();
    parse_args();
    imgui::theme_game();
    let red = bar(rgb(0xD8404A));
    let green = bar(rgb(0x3CC070));
    let trail = bar(rgba(INK, 0.7));
    let track = bar(rgba(0x000000, 0.5));
    let shown = imgui::tween(0.5, imgui::EASE_IN_OUT_CUBIC).delay(0.3);
    run("imgui: cards", 1100, 680) {
        let t = imgui::time();
        let ss = gfx::screen_size();
        gfx2d::frame(rgb(0x1B1420)) {
            // The table: a lit middle, darker toward the edges.
            gfx2d::rect(0, 0, ss.x, ss.y, gfx2d::radial(ss.x * 0.5, ss.y * 0.45, ss.x * 0.5, rgb(0x3A2A40), rgb(0x150F18)));
            imgui::frame(frame_dt()) {
                // The enemy, its health trailed, and what it means to do.
                // A card dropped on it is played; while one is over it, it
                // is ringed.
                let ed = imgui::column().align(imgui::CENTER).gap(8).padding(16).radius(16).hit()
                                        .place(imgui::CENTER, imgui::START).offset(0, 34);
                let on_enemy = imgui::drop_target(imgui::interact(imgui::id("enemy"), ed), CARD);
                if on_enemy.dropped { play(on_enemy.payload, t); }
                imgui::box("enemy", if on_enemy.over { ed.border(2, rgba(0xFFE08A, 0.8)).bg(rgba(0xFFE08A, 0.08)) } else { ed }) {
                    imgui::text("CINDER WARDEN", imgui::column().text_size(18).letter_spacing(6).ink(rgb(INK))
                                                   .text_shadow(rgba(SHADE, 0.8), 0, 2));
                    imgui::canvas("body", imgui::column().size(140, 140)) { size =>
                        let c = size * 0.5;
                        let bob = sin(t * 2.0) * 4.0;
                        // A shadow under it: a thick line with round ends.
                        imgui::draw_line(c.x - 40.0, c.y + 62.0, c.x + 40.0, c.y + 62.0, 14, rgba(0x000000, 0.3));
                        imgui::fill_circle(c.x, c.y + bob, 54, rgb(0x7A2E3A));
                        imgui::fill_circle(c.x - 18.0, c.y - 10.0 + bob, 9, rgb(0xFFD27A));
                        imgui::fill_circle(c.x + 18.0, c.y - 10.0 + bob, 9, rgb(0xFFD27A));
                    };
                    imgui::meter("hp", enemy_hp / 60.0, imgui::row().size(220, 12),
                                 imgui::Meter { trail: shown, track_class: track, fill_class: red, trail_class: trail, .. });
                    imgui::textf(imgui::column().text_size(13).ink(rgba(INK, 0.8))) { out =>
                        format(out, round(enemy_hp) as i64, " / 60, attacks for 9");
                    };
                };
                // What each card did to it, rising from it.
                var k = 0;
                while k < hits.len {
                    let h = hits[k];
                    let age = t - h.born;
                    if age > 0.9 { remove_at(hits, k); continue; }
                    imgui::box(imgui::id(str("hit", h.key)), imgui::stack().absolute(550.0 + (h.key % 3 - 1) * 30.0, 150.0 - age * 60.0)
                                                              .pivot(0.5, 1).opacity(1.0 - age * age / 0.81).isolate()) {
                        imgui::textf(imgui::column().text_size(34).ink(rgb(0xFFE08A)).text_outline(2, rgb(0x5A1A08))) { out =>
                            format(out, h.amount);
                        };
                    };
                    k++;
                }

                // Bottom left: energy, health and block.
                imgui::box("player", imgui::row().gap(16).align(imgui::CENTER).place(imgui::START, imgui::END).offset(30, -30)) {
                    imgui::box(imgui::stack()) {
                        orb(energy as f64 / MAX_ENERGY, t);
                        imgui::textf(imgui::column().text_size(24).ink(rgb(INK)).text_outline(2, rgb(SHADE))
                                       .place(imgui::CENTER, imgui::CENTER)) { out => format(out, energy, "/", MAX_ENERGY); };
                    };
                    imgui::box(imgui::column().gap(6)) {
                        imgui::text("Wren", imgui::column().text_size(16).ink(rgb(INK)));
                        imgui::meter("hp", player_hp / 60.0, imgui::row().size(130, 10),
                                     imgui::Meter { trail: shown, track_class: track, fill_class: green, trail_class: trail, .. });
                        imgui::textf(imgui::column().text_size(13).ink(rgba(INK, 0.75))) { out =>
                            format(out, round(player_hp) as i64, " / 60", if armor > 0 { "   block " } else { "" });
                            if armor > 0 { format(out, armor); }
                        };
                    };
                };

                // The hand. Each card's place in the fan takes the pointer and
                // glides (and turns) when the hand changes; the card drawn in
                // it rises when the pointer is on it, and that one is drawn
                // last, on top. A card is known by its own index, not its
                // place, so that the others keep theirs when one is played.
                imgui::box("hand", imgui::stack().size(640, 260).place(imgui::CENTER, imgui::END)) {
                    let n = hand.len;
                    fn spot(s: i64) -> imgui::Desc {
                        let at, angle = fan(s, n);
                        let a = imgui::animate(imgui::sub_id(imgui::id("turn"), hand[s]), angle, imgui::spring(300, 24));
                        imgui::clickable(imgui::column().size(130, 184).absolute(at.x, at.y + 40.0).pivot(0.5, 1)
                                         .rotate(a).glide(imgui::spring(300, 24)))
                    }
                    var top = -1;
                    for s in n { if imgui::interact(imgui::id(hand[s]), spot(s)).hovered { top = s; } }
                    var played = -1;
                    for j in n {
                        let s = if top < 0 || j < top { j } else if j == n - 1 { top } else { j + 1 };
                        let c = hand[s];
                        let up = imgui::animate(imgui::sub_id(imgui::id("lift"), c), if s == top { 34.0 } else { 0.0 },
                                                imgui::spring(400, 26));
                        let can = COSTS[c] <= energy;
                        // A card that can be paid for can be carried: its place
                        // in the hand then shows only its outline.
                        let carried = can && imgui::drag_source(imgui::interact(imgui::id(c), spot(s)), CARD, s);
                        let it = imgui::box(c, spot(s)) {
                            imgui::box(imgui::stack().grow().offset(0, -up).opacity(if carried { 0.2 } else if can { 1.0 } else { 0.55 })) {
                                card_face(c);
                            };
                        };
                        if it.clicked && can { played = s; }
                    }
                    if played >= 0 { play(played, t); }
                };
                // The card carried, under the pointer (not the frame it is
                // played, when it has left the hand).
                if imgui::dragging(CARD) && !on_enemy.dropped {
                    imgui::drag_ghost(imgui::stack().size(130, 184).scale(1.05)) { card_face(hand[imgui::drag_payload()]); };
                }

                // Bottom right: End turn, slanted.
                imgui::box("end", imgui::row().place(imgui::END, imgui::END).offset(-40, -50)) {
                    if imgui::button("End turn", imgui::row().skew(0.25).padding(22, 12)) { end_turn(); }
                };
            };
        };
    };
}
