// The basic widgets in a settings panel: buttons, a checkbox, toggles,
// radios, sliders and a progress bar. Beside it, meters: a health bar in
// segments whose trail shows what a hit took (Hit and Heal), a boss's bar
// (Strike), upright bars, rings, and a cooldown swept over an ability
// (Cast). Tab, the arrows and Enter work too.
//
//   goose examples/widgets.goose [-- --theme dark|game] [-- --frames 60 --screenshot widgets.png]
import std;
import vec;
import math;
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
var health: f64 = 0.8;
var boss: f64 = 1.0;
var cast_at: f64 = -10.0;
let COOLDOWN = 3.0;

// A meter's fill in a color of its own, for a bar that isn't the theme's
// accent.
fn fill(c: i64) -> imgui::StyleClass {
    imgui::add_class(imgui::style_set(imgui::Style { bg: gfx2d::rgb(c), radius: imgui::radii(3.0) }))
}

fn meters(red: imgui::StyleClass, green: imgui::StyleClass, blue: imgui::StyleClass, gold: imgui::StyleClass,
          shade: imgui::StyleClass, clear: imgui::StyleClass) {
    let t = imgui::time();
    let trail = imgui::tween(0.45, imgui::EASE_IN_OUT_CUBIC).delay(0.35);
    imgui::box("meters", imgui::column().skin(imgui::PANEL).width(340).gap(14)) {
        imgui::text("Meters", imgui::TITLE);

        // Health in ten segments: a hit leaves a trail that eases down after
        // it; healing fills at once.
        imgui::text("Health: segments, and a trail", imgui::MUTED);
        imgui::meter("health", health, imgui::row().grow_w().height(12),
                     imgui::Meter { segments: 10, trail: trail, fill_class: red, .. });
        imgui::box(imgui::row().gap(8)) {
            if imgui::button("Hit") { health = max(health - 0.17, 0.0); }
            if imgui::button("Heal") { health = min(health + 0.25, 1.0); }
        };

        // A boss's bar: one long fill, taller, its trail slower.
        imgui::text("The Ember Warden", imgui::MUTED);
        imgui::box(imgui::row().gap(10).align(imgui::CENTER).grow_w()) {
            imgui::meter("boss", boss, imgui::row().grow_w().height(16),
                         imgui::Meter { trail: imgui::tween(0.8, imgui::EASE_IN_OUT_CUBIC).delay(0.5), fill_class: red, .. });
            // Defeated, it comes back whole.
            if imgui::button("Strike") { boss -= 0.09; if boss <= 0.0 { boss = 1.0; } }
        };
        imgui::separator();

        // Upright bars, filled from the bottom; and round ones.
        imgui::text("Upright and round", imgui::MUTED);
        imgui::box(imgui::row().gap(18).align(imgui::END)) {
            imgui::meter("stamina", 0.5 + 0.5 * sin(t * 1.3), imgui::column().size(10, 80),
                         imgui::Meter { vertical: true, fill_class: green, .. });
            imgui::meter("mana", 0.35, imgui::column().size(10, 80), imgui::Meter { vertical: true, fill_class: blue, .. });
            imgui::meter("xp", 0.72, imgui::column().size(10, 80),
                         imgui::Meter { vertical: true, segments: 4, fill_class: gold, .. });
            // A ring charging up, again and again.
            imgui::radial_meter("charge", t / 2.5 - floor(t / 2.5), imgui::column().size(56, 56),
                                imgui::Meter { thickness: 6.0, fill_class: gold, .. });
            // Health again, as a ring in five segments, trailed.
            imgui::radial_meter("health ring", health, imgui::column().size(56, 56),
                                imgui::Meter { segments: 5, trail: trail, thickness: 8.0, fill_class: red, .. });
            // An ability: what is left of its cooldown swept dark over it.
            let left = clamp(1.0 - (t - cast_at) / COOLDOWN, 0.0, 1.0);
            imgui::box("ability", imgui::stack().size(56, 56).radius(10).clip()
                                    .bg(gfx2d::rgb(0xF2B53C), gfx2d::rgb(0xC0701A))) {
                imgui::panel(imgui::column().size(22, 22).radius(11).bg(gfx2d::rgb(0xFFF3D6)).place(imgui::CENTER, imgui::CENTER));
                if left > 0.0 {
                    imgui::radial_meter("cooldown", left, imgui::column().size(80, 80).place(imgui::CENTER, imgui::CENTER),
                                        imgui::Meter { track_class: clear, fill_class: shade, .. });
                    imgui::textf(imgui::column().text_size(20).ink(gfx2d::WHITE).text_shadow(gfx2d::rgba(0x000000, 0.6))
                                   .place(imgui::CENTER, imgui::CENTER)) { out =>
                        format(out, min(floor(left * COOLDOWN) as i64 + 1, COOLDOWN as i64));
                    };
                }
            };
        };
        imgui::box(imgui::row().gap(8).justify(imgui::END).grow_w()) {
            let ready = t - cast_at >= COOLDOWN;
            if imgui::button("Cast", imgui::row().disabled(!ready)) { cast_at = t; }
        };
    };
}

fn main() {
    parse_args();
    if theme_name == "dark" { imgui::theme_dark(); }
    if theme_name == "game" { imgui::theme_game(); }
    let red = fill(0xE0455A);
    let green = fill(0x2EBE7A);
    let blue = fill(0x3D7DE0);
    let gold = fill(0xF2B53C);
    let shade = fill(0x000000);
    let clear = imgui::add_class(imgui::style_set(imgui::Style { .. }));
    var dark = imgui::class_style(shade);
    dark.normal.bg = gfx2d::rgba(0x000000, 0.6);
    imgui::set_class(shade, dark);
    run("imgui: widgets", 1120, 640, false) {
        let bg = imgui::screen_color();
        gfx2d::frame(bg) {
            imgui::frame(frame_dt()) {
                imgui::box(imgui::row().gap(24).align(imgui::START).place(imgui::CENTER, imgui::CENTER)) {
                    imgui::box("settings", imgui::column().skin(imgui::PANEL).width(420).gap(14)) {
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
                    meters(red, green, blue, gold, shade, clear);
                };
            };
        };
    };
}
