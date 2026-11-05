// An editor of a running scene, in the dense dev theme: windows docked
// around its viewport (drag a title over the dock to dock it, a tab out to
// float it, the lines between them to resize), and windows floating:
// by their titles, resized by their edges and corners, rolled up by their
// arrows or a double click, closed (and opened again from the View menu),
// fading and zooming as they hide and show, raised by a click. A tree of
// the scene's entities (right-click one for its menu), and an inspector of
// the one selected: property rows, number fields to drag or type in,
// collapsing headers, a color for each; a table of them, sorted by its
// headers, its rows selected by clicks (Ctrl and Shift for more); a plot
// of frame times and a histogram of them; a console that logs slow frames
// and selections, and takes commands (type help). The Layout menu saves
// where everything is to windows_layout.json, and loads it back.
//
//   goose examples/windows.goose [-- --theme dev-light|light|dark|game]
import std;
import vec;
import math;
import gfx;
import gfx2d from "../../goose_gfx2d";
import imgui from "..";
import .common;

let LAYOUT_FILE = "windows_layout.json";
var show_tweaks = true;
var show_stats = true;
var show_scene = true;
var show_inspector = true;
var show_entities = true;
var show_console = true;
var log = imgui::Log { .. };
var cmd: u8[>..] = [];
var picked: bool[7] = [false; 7];
var order: i64[7] = [0, 1, 2, 3, 4, 5, 6];
var speed: f64 = 1.0;
var spin: f64 = 0.4;
var count: i64 = 7;
var trails = true;
var paused = false;
var chosen = 0;
var t: f64 = 0.0;
var fps: f64 = 60.0;
var names = ["player", "enemy 1", "enemy 2", "enemy 3", "pickup", "door", "key"];
var hidden: bool[7] = [false; 7];
var offsets: float2[7] = [float2 { 0.0, 0.0 }; 7];
var radii: f64[7] = [12.0; 7];
var glow: f64[7] = [26.0; 7];
var colors: gfx2d::Color[7] = [gfx2d::rgb(0x4C8DF6); 7];
var frame_ms: f64[>..] = [];
var buckets: f64[8] = [0.0; 8];

fn scene() {
    imgui::canvas("scene", imgui::column().grow()) { size =>
        let c = float2 { size.x * 0.5, size.y * 0.55 };
        for k in count {
            if hidden[k] { continue; }
            let a = t * spin + k as f64 * 6.2832 / count as f64;
            let p = c + float2 { cos(a) as f32, sin(a) as f32 } * min(size.x, size.y) * 0.3 + offsets[k];
            if trails {
                imgui::fill_circle(p.x, p.y, radii[k] + glow[k] - 12.0, gfx2d::with_alpha(colors[k], colors[k].a * 0.15));
            }
            imgui::fill_circle(p.x, p.y, radii[k], colors[k]);
            if k == chosen { imgui::stroke_circle(p.x, p.y, radii[k] + 3.0, 2, gfx2d::rgb(0xF6C14C)); }
        }
    };
}

// An entity's row in the scene's tree: selected by a click, with a menu.
fn entity_row(k: i64) {
    let it = imgui::tree_leaf(names[k], chosen == k);
    if it.activated { chosen = k; }
    imgui::context_menu(it) {
        if imgui::menu_item("Select") { chosen = k; }
        imgui::menu_check("Hidden", hidden[k]);
    };
}

// The entities in `order`, sorted by column c: name, radius or hidden.
fn sort_entities(c: i64, descending: bool) {
    fn before(a: i64, b: i64) -> bool {
        let less = match c {
            0 => compare(names[a], names[b]) < 0,
            1 => radii[a] < radii[b],
            _ => !hidden[a] && hidden[b],
        };
        let more = match c {
            0 => compare(names[b], names[a]) < 0,
            1 => radii[b] < radii[a],
            _ => !hidden[b] && hidden[a],
        };
        if descending { more } else { less }
    }
    for k in 1..7 {
        var j = k;
        while j > 0 && before(order[j], order[j - 1]) {
            let t = order[j];
            order[j] = order[j - 1];
            order[j - 1] = t;
            j--;
        }
    }
}

fn entities() {
    imgui::window("Entities", show_entities, imgui::column().size(330, 210).absolute(250, 360), imgui::WINDOW_NO_SCROLL) {
        let t = imgui::table("ents", ["Name", "Radius", "Color", "Hidden"], 7, picked, imgui::Table { .. },
                             imgui::column().grow()) { k, c =>
            let e = order[k];
            match c {
                0 => { imgui::text(names[e]); },
                1 => { imgui::textf(imgui::column()) { out => imgui::format_fixed(out, radii[e], 1); }; },
                2 => { imgui::color_swatch("swatch", colors[e], imgui::column().size(14, 14)); },
                _ => { imgui::checkbox("", hidden[e]); },
            }
        };
        if t.clicked >= 0 {
            imgui::select_row("ents", picked, t.clicked);
            chosen = order[t.clicked];
            imgui::logf(log, imgui::LOG_DEBUG) { out => format(out, "selected ", names[chosen]); };
        }
        if t.sort >= 0 { sort_entities(t.sort, t.descending); }
    };
}

// A console command: help, speed N, spin N, count N, pause, clear.
fn run_command() {
    let words = split(cmd, ' ');
    if words.len == 0 { return; }
    let w = words[0];
    let n, ok = parse_flt(if words.len > 1 { words[1] } else { "" });
    if w == "help" {
        imgui::log(log, "commands: speed N, spin N, count N (1-7), pause, clear");
    } else if w == "speed" && ok {
        speed = clamp(n, 0.0, 4.0);
        imgui::logf(log) { out => format(out, "speed ", speed); };
    } else if w == "spin" && ok {
        spin = clamp(n, 0.0, 2.0);
        imgui::logf(log) { out => format(out, "spin ", spin); };
    } else if w == "count" && ok {
        count = clamp(round(n) as i64, 1, 7);
        imgui::logf(log) { out => format(out, "count ", count); };
    } else if w == "pause" {
        paused = !paused;
        imgui::log(log, if paused { "paused" } else { "running" });
    } else if w == "clear" {
        imgui::log_clear(log);
    } else {
        imgui::logf(log, imgui::LOG_ERROR) { out => format(out, "unknown command: ", cmd); };
    }
    cmd.clear();
}

fn ui() {
    imgui::box(imgui::column().grow()) {
        imgui::menu_bar("bar") {
            imgui::menu("View") {
                imgui::menu_check("Tweaks", show_tweaks);
                imgui::menu_check("Stats", show_stats);
                imgui::menu_check("Scene", show_scene);
                imgui::menu_check("Inspector", show_inspector);
                imgui::menu_check("Entities", show_entities);
                imgui::menu_check("Console", show_console);
            };
            // The layout, in a file beside where it runs.
            imgui::menu("Layout") {
                if imgui::menu_item("Save") {
                    if imgui::save_layout(LAYOUT_FILE) { imgui::log(log, "layout saved to windows_layout.json"); }
                }
                if imgui::menu_item("Load") {
                    if imgui::load_layout(LAYOUT_FILE) {
                        show_tweaks = imgui::layout_open("Tweaks", show_tweaks);
                        show_stats = imgui::layout_open("Stats", show_stats);
                        show_scene = imgui::layout_open("Scene", show_scene);
                        show_inspector = imgui::layout_open("Inspector", show_inspector);
                        show_entities = imgui::layout_open("Entities", show_entities);
                        show_console = imgui::layout_open("Console", show_console);
                        imgui::log(log, "layout loaded");
                    } else {
                        imgui::log(log, "no layout in windows_layout.json", imgui::LOG_WARN);
                    }
                }
            };
        };
        // The windows dock here; the scene is in one of them.
        imgui::dock_space("dock", imgui::column().grow());
    };
    imgui::window("Viewport", imgui::column().padding(0), imgui::WINDOW_NO_SCROLL) { scene(); };
    imgui::window("Tweaks", show_tweaks, imgui::column().size(230, 170).absolute(220, 60)) {
        imgui::properties() {
            imgui::property("Speed") { imgui::slider("", speed, 0, 4, 0.1, imgui::row()); };
            imgui::property("Spin") { imgui::drag_number("", spin, imgui::Drag { lo: 0, hi: 2, decimals: 2 }); };
            imgui::property("Count") { imgui::input_number("", count, imgui::Drag { lo: 1, hi: 7 }); };
            imgui::property("Trails") { imgui::checkbox("", trails); };
            imgui::property("Paused") { imgui::checkbox("", paused); };
        };
    };
    imgui::window("Stats", show_stats, imgui::column().size(220, 210).absolute(470, 60)) {
        imgui::box(imgui::row().gap(8).align(imgui::CENTER)) {
            imgui::textf(imgui::column()) { out => format(out, "frame ", round(1000.0 / fps * 10.0) / 10.0, " ms"); };
            imgui::sparkline("spark", frame_ms, imgui::column().width(60));
        };
        imgui::plot_lines("##frame time", frame_ms, imgui::Plot { lo: 10, hi: 25, decimals: 1 });
        imgui::text("frame times", imgui::MUTED);
        imgui::plot_bars("##spread", buckets[..], imgui::Plot { decimals: 0 }, imgui::column().height(48));
    };
    imgui::window("Scene", show_scene, imgui::column().size(220, 260).absolute(16, 240)) {
        imgui::tree_node("World", false, true) {
            imgui::tree_node("Player", false, true) { entity_row(0); entity_row(6); };
            imgui::tree_node("Enemies", false, true) { for k in 1..4 { entity_row(k); } };
            imgui::tree_node("Props") { entity_row(4); entity_row(5); };
        };
    };
    entities();
    // Its log scrolls itself, so the window's body doesn't: the log fills it.
    imgui::window("Console", show_console, imgui::column().size(340, 220).absolute(610, 360), imgui::WINDOW_NO_SCROLL) {
        if imgui::console("console", log, cmd, imgui::column().grow()) { run_command(); }
    };
    imgui::window("Inspector", show_inspector, imgui::column().size(280, 290).absolute(664, 44)) {
        imgui::text(names[chosen], imgui::TITLE);
        imgui::collapsing("Transform", imgui::column(), true) {
            imgui::properties() {
                imgui::property("Offset") { imgui::drag_vec("", offsets[chosen]); };
                imgui::property("Radius") { imgui::drag_number("", radii[chosen], imgui::Drag { lo: 4, hi: 40, decimals: 1 }); };
                imgui::property("Color") { imgui::color_edit("", colors[chosen]); };
            };
        };
        imgui::collapsing("Render", imgui::column(), true) {
            imgui::properties() {
                imgui::property("Hidden") { imgui::checkbox("", hidden[chosen]); };
                imgui::property("Glow") { imgui::drag_number("", glow[chosen], imgui::Drag { lo: 12, hi: 60, decimals: 1 }); };
            };
        };
    };
}

fn main() {
    parse_args();
    imgui::log(log, "type help for the commands");
    // An editor's layout to start with: the viewport in the middle, the
    // scene's tree on the left, the inspector on the right, the console and
    // the entities' table as tabs under the viewport. Tweaks and Stats float.
    imgui::dock_window("Viewport", "dock", imgui::DOCK_CENTER);
    imgui::dock_window("Scene", "dock", imgui::DOCK_LEFT, 0.2);
    imgui::dock_window("Inspector", "dock", imgui::DOCK_RIGHT, 0.27);
    imgui::dock_window_with("Console", "Viewport", imgui::DOCK_BOTTOM, 0.33);
    imgui::dock_window_with("Entities", "Console", imgui::DOCK_CENTER);
    if theme_name == "dev-light" { imgui::theme_dev_light(); }
    else if theme_name == "light" { imgui::theme_light(); }
    else if theme_name == "dark" { imgui::theme_dark(); }
    else if theme_name == "game" { imgui::theme_game(); }
    else { imgui::theme_dev(); }
    imgui::set_window_roll(imgui::tween(0.18, imgui::EASE_OUT_CUBIC));
    imgui::set_window_show(imgui::tween(0.15, imgui::EASE_OUT_CUBIC), 0.95);
    imgui::set_tree_roll(imgui::tween(0.15, imgui::EASE_OUT_CUBIC));
    imgui::set_tab_slide(imgui::tween(0.15, imgui::EASE_OUT_CUBIC));
    imgui::set_dock_preview(true, imgui::tween(0.12, imgui::EASE_OUT_CUBIC));
    run("imgui: windows", 960, 600) {
        let dt = frame_dt();
        if !paused { t += dt * speed; }
        if dt > 0.0 { fps = fps * 0.95 + (1.0 / dt) * 0.05; }
        // Frame times: the real ones, with a wobble so a fixed step shows something.
        let ms = dt * 1000.0 + sin(t * 3.1) * 2.5 + sin(t * 17.0) * 1.2;
        imgui::push_sample(frame_ms, ms, 120);
        if ms > 20.0 { imgui::logf(log, imgui::LOG_WARN) { out => format(out, "slow frame: ", round(ms * 10.0) / 10.0, " ms"); }; }
        let b = clamp(((ms - 12.0) / 1.5) as i64, 0, 7);
        buckets[b] += 1.0;
        gfx2d::frame(imgui::screen_color()) {
            imgui::frame(dt) { ui(); };
        };
    };
}
