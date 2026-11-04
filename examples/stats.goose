// A run's summary, drawn on canvases inside the layout: a line chart of
// the score (hover it for the value at a moment), bars that grow in, an
// accuracy gauge that sweeps to its value, and a minimap of the rooms
// visited. Each canvas fills the card the grid gives it, at any window
// size.
//
//   goose examples/stats.goose [-- --theme dark|game] [-- --frames 90 --screenshot stats.png]
import std;
import vec;
import math;
import gfx;
import gfx2d from "../../goose_gfx2d";
import imgui from "..";
import .common;

var score: f64[>..] = [];
let KINDS = ["Slimes", "Bats", "Knights", "Golems", "Wraiths"];
let KILLS = [42, 27, 12, 5, 9];
let ROOMS = [[0, 0, 3, 2], [3, 0, 2, 3], [5, 1, 3, 2], [0, 2, 2, 3], [2, 3, 4, 2], [6, 3, 2, 3]];
let PATH = [[1, 1], [4, 1], [6, 2], [7, 4], [4, 4], [1, 3]];

fn card<F>(title: const u8[:]) {
    imgui::box(title, imgui::column().skin(imgui::PANEL).grow().gap(8)) {
        imgui::text(title, imgui::MUTED);
        F();
    };
}

fn main() {
    var r = rng { 3 };
    var s = 0.0;
    for k in 60 { s += rand_flt(r) * 30.0 + (if k % 17 == 16 { -60.0 } else { 4.0 }); score.push(max(s, 0.0)); }
    parse_args();
    if theme_name == "dark" { imgui::theme_dark(); }
    if theme_name == "game" { imgui::theme_game(); }
    run("imgui: stats", 960, 640, false) {
        let ink = imgui::class_style(imgui::LABEL).normal.ink;
        let accent = imgui::class_style(imgui::SLIDER_FILL).normal.bg;
        let faint = gfx2d::with_alpha(ink, 0.12);
        gfx2d::frame(imgui::screen_color()) {
            imgui::frame(frame_dt()) {
                imgui::box("page", imgui::column().grow().padding(24).gap(16)) {
                    imgui::text("Run complete", imgui::TITLE);
                    imgui::box("cards", imgui::grid([imgui::grow(3), imgui::grow(2)]).rows([imgui::grow(), imgui::grow()])
                                         .gap(16).grow()) {
                        card("Score") {
                            // A line chart: the area under it, its line, and
                            // under the pointer, the value there.
                            let it = imgui::canvas("score chart", imgui::column().grow().hit()) { size =>
                                var top = 1.0;
                                for v in score { top = max(top, v); }
                                let n = score.len;
                                fn px(k: i64) -> f64 { k * size.x / (n - 1) }
                                fn py(v: f64) -> f64 { size.y - 4.0 - v / top * (size.y - 24.0) }
                                for g in 1..4 {
                                    let y = size.y * g / 4.0;
                                    imgui::draw_line(0, y, size.x, y, 1, faint);
                                }
                                var area: float2[>..] = [];
                                area.push(float2 { 0.0, size.y });
                                var line: float2[>..] = [];
                                for v, k in score {
                                    let p = float2 { px(k) as f32, py(v) as f32 };
                                    area.push(p);
                                    line.push(p);
                                }
                                area.push(float2 { size.x, size.y });
                                imgui::fill_polygon(area, gfx2d::with_alpha(accent, 0.18));
                                imgui::stroke_polyline(line, 2.5, accent);
                            };
                            if it.hovered && it.rect.w > 0.0 {
                                let k = clamp(round(it.pointer.x / it.rect.w * (score.len - 1)) as i64, 0, score.len - 1);
                                imgui::tooltip(it) {
                                    imgui::textf(imgui::column()) { out => format(out, "Minute ", k, ": ", round(score[k])); };
                                };
                            }
                        };
                        card("Accuracy") {
                            imgui::canvas("gauge", imgui::column().grow()) { size =>
                                let acc = imgui::animate_from(imgui::id("accuracy"), 0.0, 0.73, imgui::tween(1.2, imgui::EASE_OUT_CUBIC));
                                let c = size * 0.5;
                                let rr = max(min(c.x, c.y) - 12.0, 4.0);
                                let a0 = PI * 0.75;
                                imgui::stroke_arc(c.x, c.y, rr, a0, a0 + PI * 1.5, 12, faint);
                                imgui::stroke_arc(c.x, c.y, rr, a0, a0 + PI * 1.5 * acc, 12, accent);
                                imgui::draw_text(c.x, c.y, str(round(acc * 100.0) as i64, "%"), 30, ink, gfx2d::ALIGN_CENTER,
                                                 gfx2d::BASELINE_MIDDLE);
                            };
                        };
                        card("Defeated") {
                            imgui::canvas("bars", imgui::column().grow()) { size =>
                                var most = 1;
                                for k in KILLS { most = max(most, k); }
                                let label_w = 80.0;
                                let row = size.y / KINDS.len;
                                for name, k in KINDS {
                                    // Each bar grows in, a little after the one above.
                                    let f = imgui::animate_from(imgui::id(k), 0.0, KILLS[k] / most as f64,
                                                                imgui::tween(0.8, imgui::EASE_OUT_CUBIC).delay(0.1 * k));
                                    let y = row * k + row * 0.2;
                                    let h = row * 0.6;
                                    imgui::draw_text(0, y + h * 0.5, name, 15, ink, gfx2d::ALIGN_LEFT, gfx2d::BASELINE_MIDDLE);
                                    let w = (size.x - label_w - 40.0) * f;
                                    imgui::fill_rect(label_w, y, w, h, 4, accent);
                                    imgui::draw_text(label_w + w + 6.0, y + h * 0.5, str(KILLS[k]), 14, ink,
                                                     gfx2d::ALIGN_LEFT, gfx2d::BASELINE_MIDDLE);
                                }
                            };
                        };
                        card("Map") {
                            imgui::canvas("map", imgui::column().grow().clip()) { size =>
                                let cell = min(size.x / 8.0, size.y / 6.0);
                                let ox = (size.x - cell * 8.0) * 0.5;
                                let oy = (size.y - cell * 6.0) * 0.5;
                                for room in ROOMS {
                                    imgui::fill_rect(ox + room[0] * cell + 2.0, oy + room[1] * cell + 2.0,
                                                     room[2] * cell - 4.0, room[3] * cell - 4.0, 4, faint);
                                }
                                var trail: float2[>..] = [];
                                for p in PATH { trail.push(float2 { (ox + (p[0] + 0.5) * cell) as f32, (oy + (p[1] + 0.5) * cell) as f32 }); }
                                imgui::stroke_polyline(trail, 2, gfx2d::with_alpha(accent, 0.7));
                                let last = trail[trail.len - 1];
                                let pulse = 0.5 + 0.5 * sin(imgui::time() * 4.0);
                                imgui::fill_circle(last.x, last.y, 6 + 4 * pulse, gfx2d::with_alpha(accent, 0.3));
                                imgui::fill_circle(last.x, last.y, 5, accent);
                            };
                        };
                    };
                    imgui::box(imgui::row().justify(imgui::END).grow_w().gap(8)) {
                        imgui::button("Retry");
                        imgui::button("Continue");
                    };
                };
            };
        };
    };
}
