// Finding the way, over a scene: places marked where they are, or at the
// screen's edge with an arrow turned toward them when they are off it
// (edge_clamp); a compass strip with each place on it; a minimap that turns
// with the player, places past its rim held at it; and the place tracked,
// with how far it is. Click a marker to track its place.
//
//   goose examples/wayfinding.goose [-- --frames 90 --screenshot wayfinding.png]
import std;
import vec;
import math;
import gfx;
import gfx2d from "../../goose_gfx2d";
import imgui from "..";
import .common;
import .scene;

let NAMES = ["The Ember Shrine", "Hollow Camp", "Sunken Ruin", "Peddler's Cart"];
let GOALS = ["Light the brazier", "Rest by the fire", "Find the lost bell", "Trade for a lantern"];
let SPOTS = [float2 { 980.0, -560.0 }, float2 { -760.0, 340.0 }, float2 { 420.0, 760.0 }, float2 { 360.0, -60.0 }];
let COLORS = [0xF2B53C, 0x5BA8FF, 0xB18CFF, 0x5CD68A];

var tracking = 0;

// A place on the ground: a glow that breathes, and a stone in its color.
fn draw_world(cam: float2, view: float2, t: f64) {
    draw_ground(cam, view);
    let o = view * 0.5 - cam;
    for p, k in SPOTS {
        let s = p + o;
        gfx2d::circle(s.x, s.y, 42.0 + 6.0 * sin(t * 2.0 + k), rgba(COLORS[k], 0.12));
        gfx2d::circle(s.x, s.y, 16.0, rgb(0x5A5040));
        gfx2d::circle(s.x, s.y, 7.0, rgb(COLORS[k]));
    }
    draw_player(view, t);
}

// How far, in meters (four units to a meter).
fn meters(d: float2) -> i64 { round(length(d) / 4.0) as i64 }

fn main() {
    var seed = rng { 11 };
    make_rocks(seed);
    parse_args();
    run("imgui: wayfinding", 1280, 720) {
        let t = imgui::time();
        let me = player_at(t);
        let heading = heading_at(t);
        let view = view_size();
        let center = view * 0.5;
        fn to_screen(p: float2) -> float2 { p - me + center }
        gfx2d::frame(rgb(0x26332A)) {
            gfx2d::scale(imgui::ui_scale_of()) { draw_world(me, view, t); };
            imgui::frame(frame_dt()) {
                // A marker for each place. On screen: its name and distance
                // over a diamond (a square turned), placed by their bottom
                // center just above it. Off screen: a ring at the screen's
                // edge, toward the place, with an arrow turned to point.
                for k in NAMES.len {
                    let at, ang, seen = imgui::edge_clamp(to_screen(SPOTS[k]), 48);
                    let c = rgb(COLORS[k]);
                    let d = if seen { imgui::column().absolute(at.x, at.y - 22.0).pivot(0.5, 1) }
                            else { imgui::column().absolute(at.x, at.y - 20.0).pivot(0.5, 0) };
                    let it = imgui::box(k, imgui::clickable(d.align(imgui::CENTER).gap(3)
                                                            .opacity(if k == tracking { 1.0 } else { 0.7 }))) {
                        if seen {
                            imgui::text(NAMES[k], imgui::column().text_size(13).ink(rgb(INK)).text_outline(1, rgb(SHADE)));
                            imgui::textf(imgui::column().text_size(12).ink(c).text_outline(1, rgb(SHADE))) { out =>
                                format(out, meters(SPOTS[k] - me), " m");
                            };
                            imgui::panel(imgui::column().size(14, 14).bg(c).border(2, rgba(INK, 0.9)).rotate(PI * 0.25));
                        } else {
                            imgui::canvas("arrow", imgui::column().size(40, 40)) { size =>
                                let m = size * 0.5;
                                imgui::fill_circle(m.x, m.y, 12, rgba(0x0B0F14, 0.75));
                                imgui::stroke_circle(m.x, m.y, 12, 2, c);
                                imgui::rotate(ang, m.x, m.y) {
                                    imgui::fill_polygon([f2(m.x + 20.0, m.y), f2(m.x + 13.0, m.y + 6.0), f2(m.x + 13.0, m.y - 6.0)], c);
                                };
                            };
                            imgui::textf(imgui::column().text_size(12).ink(rgb(INK)).text_outline(1, rgb(SHADE))) { out =>
                                format(out, meters(SPOTS[k] - me), " m");
                            };
                        }
                    };
                    if it.activated { tracking = k; }
                }

                imgui::box("corners", imgui::stack().grow().padding(20)) {
                    // Top center: the compass, each place on it in its color,
                    // the one tracked bigger.
                    imgui::box("compass", imgui::column().align(imgui::CENTER).gap(2).place(imgui::CENTER, imgui::START)) {
                        imgui::canvas("strip", imgui::column().size(460, 34).bg(rgba(0x0B0F14, 0.5)).radius(6).clip()) { size =>
                            let span = 100.0;        // degrees each way
                            fn x_of(b: f64) -> f64 { size.x * 0.5 + turn(heading, b) / span * size.x * 0.5 }
                            let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
                            for n in 24 {
                                let b = n * 15.0;
                                if abs(turn(heading, b)) > span { continue; }
                                let x = x_of(b);
                                if n % 3 == 0 {
                                    let major = n % 6 == 0;
                                    imgui::draw_text(x, size.y * 0.5, dirs[n / 3], if major { 16.0 } else { 12.0 },
                                                     if major { rgb(INK) } else { rgba(INK, 0.7) },
                                                     gfx2d::ALIGN_CENTER, gfx2d::BASELINE_MIDDLE);
                                } else {
                                    imgui::draw_line(x, size.y - 9.0, x, size.y - 3.0, 1.5, rgba(INK, 0.4));
                                }
                            }
                            for p, k in SPOTS {
                                let q = bearing(p - me);
                                if abs(turn(heading, q)) > span { continue; }
                                let x = x_of(q);
                                let r = if k == tracking { 6.0 } else { 4.0 };
                                imgui::fill_polygon([f2(x, 8.0 - r), f2(x + r, 8.0), f2(x, 8.0 + r), f2(x - r, 8.0)], rgb(COLORS[k]));
                            }
                            imgui::fill_polygon([f2(size.x * 0.5 - 6.0, size.y), f2(size.x * 0.5 + 6.0, size.y),
                                                 f2(size.x * 0.5, size.y - 7.0)], rgb(INK));
                        };
                        imgui::textf(imgui::column().text_size(12).ink(rgba(INK, 0.75))) { out =>
                            format(out, (round(heading) as i64) % 360);
                        };
                    };

                    // Top right: the minimap, and the place tracked under it.
                    imgui::box("right", imgui::column().gap(12).align(imgui::END).place(imgui::END, imgui::START)) {
                        // The way the player walks is up: the map turns
                        // under the arrow.
                        imgui::canvas("minimap", imgui::column().size(170, 170).radius(85).clip().bg(rgba(0x0B0F14, 0.65))
                                                 .border(2, rgba(INK, 0.5))) { size =>
                            let c = size * 0.5;
                            let zoom = 0.14;
                            fn m(p: float2) -> float2 { c + (p - me) * zoom as f32 }
                            imgui::rotate(-heading * PI / 180.0, c.x, c.y) {
                                for r in rocks {
                                    let q = m(f2(r.x, r.y));
                                    imgui::fill_circle(q.x, q.y, max(r.z * zoom, 1.5), rgba(INK, 0.12));
                                }
                                // Each place, held at the rim if it is further.
                                for p, k in SPOTS {
                                    var q = m(p) - c;
                                    let lq = length(q) as f64;
                                    if lq > 74.0 { q = q * (74.0 / lq) as f32; }
                                    let r = if k == tracking { 6.0 } else { 4.0 };
                                    imgui::fill_polygon([f2(c.x + q.x, c.y + q.y - r), f2(c.x + q.x + r, c.y + q.y),
                                                         f2(c.x + q.x, c.y + q.y + r), f2(c.x + q.x - r, c.y + q.y)],
                                                        rgb(COLORS[k]));
                                }
                            };
                            imgui::fill_polygon([f2(c.x, c.y - 9.0), f2(c.x + 6.0, c.y + 6.0), f2(c.x - 6.0, c.y + 6.0)],
                                                rgb(0x7FD3FF));
                        };
                        imgui::box("quest", hud_panel(imgui::column().gap(4).align(imgui::END)).passthrough()) {
                            imgui::text("TRACKING", imgui::column().text_size(11).letter_spacing(3).ink(rgba(INK, 0.6)));
                            imgui::text(NAMES[tracking], imgui::column().text_size(15).ink(rgb(COLORS[tracking])));
                            imgui::text(GOALS[tracking], imgui::column().text_size(14).ink(rgb(INK)));
                            imgui::textf(imgui::column().text_size(12).ink(rgba(INK, 0.6))) { out =>
                                format(out, meters(SPOTS[tracking] - me), " m away");
                            };
                        };
                    };

                    imgui::box("hint", hud_panel(imgui::row()).padding(10, 6).place(imgui::END, imgui::END).passthrough()) {
                        imgui::text("Click a marker to track its place", imgui::column().text_size(13).ink(rgba(INK, 0.8)));
                    };
                };
            };
        };
    };
}
