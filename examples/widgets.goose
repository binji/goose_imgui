// The basic widgets in a settings panel: buttons, a checkbox, toggles,
// radios, sliders and a progress bar. Tab, the arrows and Enter work too.
//
//   goose examples/widgets.goose [-- --dark] [-- --frames 60 --screenshot widgets.png]
import std;
import vec;
import gfx;
import gfx2d from "../../goose_gfx2d";
import imgui from "..";
import .common;

var music: f64 = 0.7;
var effects: f64 = 0.45;
var subtitles = true;
var vibration = false;
var invert_y = false;
var difficulty = 1;
var fov: i64 = 90;
var saved = 0;

fn main() {
    run("imgui: widgets", 720, 560, false) {
        if dark { imgui::theme_dark(); }
        let bg = if dark { gfx2d::rgb(0x111318) } else { gfx2d::rgb(0xE9ECEF) };
        gfx2d::frame(bg) {
            imgui::frame(frame_dt()) {
                imgui::box("settings", imgui::column().skin(imgui::PANEL).width(420).gap(14)
                                         .place(imgui::CENTER, imgui::CENTER)) {
                    imgui::text("Settings", imgui::TITLE);
                    imgui::text("Audio", imgui::MUTED);
                    imgui::slider("Music", music, 0, 1, 0.05, imgui::row().grow_w());
                    imgui::slider("Effects", effects, 0, 1, 0.05, imgui::row().grow_w());
                    imgui::checkbox("Subtitles", subtitles);
                    imgui::separator();
                    imgui::text("Controls", imgui::MUTED);
                    imgui::toggle("Vibration", vibration, imgui::row().grow_w());
                    imgui::toggle("Invert Y axis", invert_y, imgui::row().grow_w());
                    imgui::slider("Field of view", fov, 60, 120);
                    imgui::separator();
                    imgui::text("Difficulty", imgui::MUTED);
                    imgui::box(imgui::row().gap(16)) {
                        imgui::radio("Story", difficulty, 0);
                        imgui::radio("Normal", difficulty, 1);
                        imgui::radio("Brutal", difficulty, 2);
                    };
                    imgui::progress(effects);
                    imgui::box(imgui::row().gap(8).justify(imgui::END).grow_w()) {
                        if imgui::button("Defaults") {
                            music = 0.7;
                            effects = 0.45;
                        }
                        if imgui::button("Save") { saved++; }
                    };
                };
            };
        };
    };
}
