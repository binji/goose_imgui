// Developer windows over a running scene, in the dense dev theme: dragged
// by their titles, resized by their edges and corners, rolled up by their
// arrows or a double click, closed (and opened again from the View menu),
// fading and zooming as they hide and show, raised by a click. A tree of
// the scene's entities (right-click one for its menu), and an inspector of
// the one selected: property rows, number fields to drag or type in,
// collapsing headers, a color for each; a table of them, sorted by its
// headers, its rows selected by clicks (Ctrl and Shift for more); a plot
// of frame times and a histogram of them.
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
var show_inspector = true;
var show_entities = true;
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
    imgui::window("Entities", show_entities, imgui::column().size(330, 210).absolute(250, 360)) {
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
        }
        if t.sort >= 0 { sort_entities(t.sort, t.descending); }
    };
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
            };
        };
        scene();
    };
    imgui::window("Tweaks", show_tweaks, imgui::column().size(250, 170).absolute(16, 44)) {
        imgui::properties() {
            imgui::property("Speed") { imgui::slider("", speed, 0, 4, 0.1, imgui::row()); };
            imgui::property("Spin") { imgui::drag_number("", spin, imgui::Drag { lo: 0, hi: 2, decimals: 2 }); };
            imgui::property("Count") { imgui::input_number("", count, imgui::Drag { lo: 1, hi: 7 }); };
            imgui::property("Trails") { imgui::checkbox("", trails); };
            imgui::property("Paused") { imgui::checkbox("", paused); };
        };
    };
    imgui::window("Stats", show_stats, imgui::column().size(240, 230).absolute(390, 44)) {
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
    if theme_name == "dev-light" { imgui::theme_dev_light(); }
    else if theme_name == "light" { imgui::theme_light(); }
    else if theme_name == "dark" { imgui::theme_dark(); }
    else if theme_name == "game" { imgui::theme_game(); }
    else { imgui::theme_dev(); }
    imgui::set_window_roll(imgui::tween(0.18, imgui::EASE_OUT_CUBIC));
    imgui::set_window_show(imgui::tween(0.15, imgui::EASE_OUT_CUBIC), 0.95);
    imgui::set_tree_roll(imgui::tween(0.15, imgui::EASE_OUT_CUBIC));
    run("imgui: windows", 960, 600) {
        let dt = frame_dt();
        if !paused { t += dt * speed; }
        if dt > 0.0 { fps = fps * 0.95 + (1.0 / dt) * 0.05; }
        // Frame times: the real ones, with a wobble so a fixed step shows something.
        let ms = dt * 1000.0 + sin(t * 3.1) * 2.5 + sin(t * 17.0) * 1.2;
        imgui::push_sample(frame_ms, ms, 120);
        let b = clamp(((ms - 12.0) / 1.5) as i64, 0, 7);
        buckets[b] += 1.0;
        gfx2d::frame(imgui::screen_color()) {
            imgui::frame(dt) { ui(); };
        };
    };
}
