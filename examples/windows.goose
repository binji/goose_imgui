// Developer windows over a running scene, in the dense dev theme: dragged
// by their titles, resized by their edges and corners, collapsed by their
// arrows or a double click, closed (and opened again from the View menu),
// raised by a click. Right-click an entity for its menu.
//
//   goose examples/windows.goose [-- --theme dev-light|light|dark|game]
import std;
import vec;
import math;
import gfx;
import gfx2d from "../../goose_gfx2d";
import imgui from "..";
import .common;

var show_tweaks = true;
var show_stats = true;
var show_scene = true;
var speed: f64 = 1.0;
var spin: f64 = 0.4;
var count: i64 = 7;
var trails = true;
var paused = false;
var chosen = 0;
var t: f64 = 0.0;
var fps: f64 = 60.0;
var names = ["player", "camera", "sun", "enemy 1", "enemy 2", "pickup", "door"];
var hidden: bool[7] = [false; 7];

fn scene() {
    imgui::canvas("scene", imgui::column().grow()) { size =>
        let c = float2 { size.x * 0.5, size.y * 0.55 };
        for k in count {
            let a = t * spin + k as f64 * 6.2832 / count as f64;
            let p = c + float2 { cos(a) as f32, sin(a) as f32 } * min(size.x, size.y) * 0.3;
            if trails {
                imgui::fill_circle(p.x, p.y, 26, gfx2d::rgba(0x4C8DF6, 0.15));
            }
            imgui::fill_circle(p.x, p.y, 12, if k == chosen { gfx2d::rgb(0xF6C14C) } else { gfx2d::rgb(0x4C8DF6) });
        }
    };
}

fn ui() {
    imgui::box(imgui::column().grow()) {
        imgui::menu_bar("bar") {
            imgui::menu("View") {
                imgui::menu_check("Tweaks", show_tweaks);
                imgui::menu_check("Stats", show_stats);
                imgui::menu_check("Scene", show_scene);
            };
        };
        scene();
    };
    imgui::window("Tweaks", show_tweaks, imgui::column().size(240, 190).absolute(16, 44)) {
        imgui::slider("Speed", speed, 0, 4, 0.1, imgui::row().grow_w());
        imgui::slider("Spin", spin, 0, 2, 0.05, imgui::row().grow_w());
        imgui::slider("Count", count, 1, 7);
        imgui::checkbox("Trails", trails);
        imgui::checkbox("Paused", paused);
    };
    imgui::window("Stats", show_stats, imgui::column().absolute(640, 44)) {
        imgui::textf(imgui::column()) { out => format(out, "frame time ", round(1000.0 / fps * 10.0) / 10.0, " ms"); };
        imgui::textf(imgui::column()) { out => format(out, "entities ", count); };
        imgui::progress(t * 0.2 - floor(t * 0.2), imgui::row().width(160));
    };
    imgui::window("Scene", show_scene, imgui::column().size(200, 240).absolute(16, 260)) {
        for name, k in names {
            if imgui::selectable(name, chosen == k) { chosen = k; }
            imgui::context_menu(imgui::last_item()) {
                if imgui::menu_item("Select") { chosen = k; }
                imgui::menu_check("Hidden", hidden[k]);
            };
        }
    };
}

fn main() {
    parse_args();
    if theme_name == "dev-light" { imgui::theme_dev_light(); }
    else if theme_name == "light" { imgui::theme_light(); }
    else if theme_name == "dark" { imgui::theme_dark(); }
    else if theme_name == "game" { imgui::theme_game(); }
    else { imgui::theme_dev(); }
    run("imgui: windows", 960, 600) {
        let dt = frame_dt();
        if !paused { t += dt * speed; }
        if dt > 0.0 { fps = fps * 0.95 + (1.0 / dt) * 0.05; }
        gfx2d::frame(imgui::screen_color()) {
            imgui::frame(dt) { ui(); };
        };
    };
}
