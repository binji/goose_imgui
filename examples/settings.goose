// A settings screen: a menu bar, tabs (the shoulder buttons, or Q and E
// here, switch them), dropdowns, toggles, sliders, a name field, and a
// modal to confirm a reset.
//
//   goose examples/settings.goose [-- --dark] [-- --frames 60 --screenshot settings.png]
import std;
import vec;
import gfx;
import gfx2d from "../../goose_gfx2d";
import imgui from "..";
import .common;

var tab = 0;
var resolution = 2;
var window_mode = 0;
var vsync = true;
var brightness: f64 = 0.5;
var master: f64 = 0.8;
var music: f64 = 0.6;
var voices: f64 = 1.0;
var mute_unfocused = true;
var sensitivity: f64 = 1.0;
var invert = false;
var hold_to_aim = false;
var name: u8[>..] = [];
var color = 0;
var reset_open = false;
var show_fps = false;

fn main() {
    name.append("Wanderer");
    run("imgui: settings", 900, 620, false) {
        if dark { imgui::theme_dark(); }
        let bg = if dark { gfx2d::rgb(0x111318) } else { gfx2d::rgb(0xDDE2E8) };
        var inp = imgui::input_from_gfx();
        inp.nav.tab_left = inp.nav.tab_left || gfx::key_pressed("Q");
        inp.nav.tab_right = inp.nav.tab_right || gfx::key_pressed("E");
        gfx2d::frame(bg) {
            imgui::frame(inp, frame_dt()) {
                imgui::box(imgui::column().grow()) {
                    imgui::menu_bar("menu") {
                        imgui::menu("Game") {
                            if imgui::menu_item("Reset settings…") { reset_open = true; }
                            if imgui::menu_item("Quit", "Ctrl+Q") { gfx::quit(); }
                        };
                        imgui::menu("View") {
                            imgui::menu_check("Show FPS", show_fps);
                            imgui::menu("Theme") {
                                if imgui::menu_item("Light") { imgui::theme_light(); }
                                if imgui::menu_item("Dark") { imgui::theme_dark(); }
                                if imgui::menu_item("Game") { imgui::theme_game(); }
                            };
                        };
                    };
                    imgui::box(imgui::column().grow().padding(24).align(imgui::CENTER)) {
                        imgui::tabs("tabs", tab, imgui::column().width(560).height(420)) {
                            imgui::tab("Video") {
                                imgui::box(imgui::grid([imgui::px(160), imgui::grow()]).gap(14).align(imgui::CENTER).grow_w()) {
                                    imgui::text("Resolution");
                                    imgui::dropdown("resolution", ["1280 × 720", "1600 × 900", "1920 × 1080", "2560 × 1440"],
                                                    resolution, imgui::row().grow_w());
                                    imgui::text("Window");
                                    imgui::dropdown("window", ["Windowed", "Borderless", "Fullscreen"], window_mode,
                                                    imgui::row().grow_w());
                                    imgui::text("Brightness");
                                    imgui::slider("##brightness", brightness, 0, 1, 0.05, imgui::row().grow_w());
                                    imgui::text("Vertical sync");
                                    imgui::toggle("##vsync", vsync);
                                };
                            };
                            imgui::tab("Audio") {
                                imgui::box(imgui::grid([imgui::px(160), imgui::grow()]).gap(14).align(imgui::CENTER).grow_w()) {
                                    imgui::text("Master");
                                    imgui::slider("##master", master, 0, 1, 0.05, imgui::row().grow_w());
                                    imgui::text("Music");
                                    imgui::slider("##music", music, 0, 1, 0.05, imgui::row().grow_w());
                                    imgui::text("Voices");
                                    imgui::slider("##voices", voices, 0, 1, 0.05, imgui::row().grow_w());
                                };
                                imgui::checkbox("Mute when the window is in the background", mute_unfocused);
                            };
                            imgui::tab("Controls") {
                                imgui::slider("Sensitivity", sensitivity, 0.1, 3.0, 0.1, imgui::row().grow_w());
                                imgui::toggle("Invert Y axis", invert, imgui::row().grow_w());
                                imgui::toggle("Hold to aim", hold_to_aim, imgui::row().grow_w());
                            };
                            imgui::tab("Profile") {
                                imgui::text("Name", imgui::MUTED);
                                imgui::text_input("name", name, imgui::row().grow_w(), 24, "Your name");
                                imgui::text("Color", imgui::MUTED);
                                imgui::box(imgui::row().gap(16)) {
                                    for c, k in ["Red", "Green", "Blue"] { imgui::radio(c, color, k); }
                                };
                            };
                        };
                    };
                    if show_fps {
                        imgui::textf(imgui::column().skin(imgui::MUTED).place(imgui::END, imgui::END)) { out =>
                            format(out, round(1.0 / max(gfx::delta_time(), 0.0001)), " fps");
                        };
                    }
                };
                imgui::modal("reset", reset_open, imgui::column().gap(16).width(380)) {
                    imgui::text("Reset all settings?", imgui::TITLE);
                    imgui::text("Every setting goes back to how it was when the game was installed.",
                                imgui::column().wrap().grow_w());
                    imgui::box(imgui::row().gap(8).justify(imgui::END).grow_w()) {
                        if imgui::button("Cancel") { reset_open = false; }
                        if imgui::button("Reset") {
                            brightness = 0.5;
                            master = 0.8;
                            music = 0.6;
                            voices = 1.0;
                            reset_open = false;
                        }
                    };
                };
            };
        };
    };
}
