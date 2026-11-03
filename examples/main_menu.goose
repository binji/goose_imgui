// A title screen, in the game theme: the title drops in, the menu's
// buttons slide in one after another, and the arrow keys (or a pad, through
// nav_from_pad), Enter and Escape drive it. Options and Quit open modals.
//
//   goose examples/main_menu.goose [-- --frames 90 --screenshot menu.png]
import std;
import vec;
import math;
import gfx;
import gfx2d from "../../goose_gfx2d";
import imgui from "..";
import .common;

var options_open = false;
var quit_open = false;
var music: f64 = 0.8;
var sfx: f64 = 0.6;
var subtitles = true;
var toast_until = -1.0;
var toast_text: u8[>..] = [];

fn toast(s: const u8[:]) {
    toast_text.clear();
    toast_text.append(s);
    toast_until = imgui::time() + 2.0;
}

fn background(t: f64, w: f64, h: f64) {
    gfx2d::rect(0, 0, w, h, gfx2d::linear(0, 0, 0, h, gfx2d::rgb(0x0B1020), gfx2d::rgb(0x1B2B4F)));
    for k in 40 {
        let x = (k * 137.0 + t * (8.0 + k % 5 * 3.0)) % (w + 40.0) - 20.0;
        let y = h - (k * 53.0 % h) * 0.9;
        gfx2d::circle(x, y, 1.0 + k % 3, gfx2d::rgba(0xF6E7B8, 0.25 + 0.15 * sin(t + k)));
    }
    gfx2d::circle(w * 0.78, h * 0.22, 70, gfx2d::radial(w * 0.78, h * 0.22, 70, gfx2d::rgba(0xFFE7A0, 0.35),
                                                          gfx2d::rgba(0xFFE7A0, 0.0)));
}

fn main() {
    imgui::theme_game();
    let menu_in = imgui::spring(260, 22);
    run("imgui: main menu", 960, 600, false) {
        let size = gfx::screen_size();
        gfx2d::frame(gfx2d::BLACK) {
            background(imgui::time(), size.x, size.y);
            imgui::frame(frame_dt()) {
                imgui::box("screen", imgui::column().grow().padding(48).align(imgui::START)) {
                    imgui::text("SKYLARK", imgui::column().skin(imgui::TITLE).text_size(64)
                                             .enter(imgui::slide_in(0, -30, imgui::tween(0.6, imgui::EASE_OUT_BACK))));
                    imgui::text("a tale of wind and feathers", imgui::column().skin(imgui::MUTED)
                                             .enter(imgui::fade_in(imgui::tween(0.8)).delay(0.3)));
                    imgui::spacer(imgui::column().height(40));
                    imgui::nav_scope("main menu", imgui::NAV_WRAP) {
                        imgui::box("menu", imgui::column().gap(12).width(280).align(imgui::STRETCH)) {
                            let items = ["Continue", "New Game", "Options", "Credits", "Quit"];
                            for name, k in items {
                                let d = imgui::row().enter(imgui::slide_in(-60, 0, menu_in).delay(0.5 + k * 0.07))
                                                    .disabled(k == 0);
                                if k == 1 { imgui::default_focus(imgui::id(name)); }
                                if imgui::button(name, d) {
                                    if k == 1 { toast("A new journey begins"); }
                                    if k == 2 { options_open = true; }
                                    if k == 3 { toast("Made with Goose"); }
                                    if k == 4 { quit_open = true; }
                                }
                            }
                        };
                    };
                    imgui::spacer();
                    imgui::text("Arrows move · Enter selects · Escape backs out", imgui::column().skin(imgui::MUTED));
                };
                imgui::modal("options", options_open, imgui::column().width(420).gap(16)) {
                    imgui::text("Options", imgui::TITLE);
                    imgui::slider("Music", music, 0, 1, 0.05, imgui::row().grow_w());
                    imgui::slider("Effects", sfx, 0, 1, 0.05, imgui::row().grow_w());
                    imgui::checkbox("Subtitles", subtitles);
                    imgui::box(imgui::row().justify(imgui::END).grow_w()) {
                        if imgui::button("Done") { options_open = false; }
                    };
                };
                imgui::modal("quit", quit_open, imgui::column().gap(18).align(imgui::CENTER)) {
                    imgui::text("Leave the game?", imgui::TITLE);
                    imgui::box(imgui::row().gap(12)) {
                        if imgui::button("Stay") { quit_open = false; }
                        if imgui::button("Quit") { gfx::quit(); }
                    };
                };
                let t, alive = imgui::presence("toast", imgui::time() < toast_until, imgui::spring(300, 26));
                if alive {
                    imgui::box("toast", imgui::row().skin(imgui::TOOLTIP).padding(18, 10).place(imgui::CENTER, imgui::END)
                                          .offset(0, -96 + (1.0 - t) * 60).opacity(t)) {
                        imgui::text(toast_text);
                    };
                }
            };
        };
    };
}
