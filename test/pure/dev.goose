// Developers' widgets, no GPU: small things, each with its own little UI.
// A console brings back the line being typed; a log line ending in a newline
// is one line; lines_kept changed; a view scrolled back stays on its lines;
// format_fixed of NaN; a canvas's size less its class's padding; Enter after
// a number is dragged; a small move in a color picker; an i32 past its range;
// a knob's end lets the focus go; a console's and a row list's default sizes.
import std;
import vec;
import gfx;
import gfx2d from "../../../goose_gfx2d";
import imgui from "../..";

var mode = 0;
var lines = imgui::Log { .. };
var cmd: u8[>..] = [];
var given = float2 { 0.0, 0.0 };
var number: f64 = 5.0;
var color = gfx2d::rgbaf(0.03, 0.02, 0.02, 1.0);
var color_true = false;
var wide: i32 = 0;
var gain: f64 = 1.0;
var ring = imgui::Log { lines_kept: 20, .. };
var pos = float2 { -100.0, -100.0 };
var down = false;
var wheel = float2 { 0.0, 0.0 };

fn ui() {
    match mode {
        0 => { imgui::box(imgui::column().size(400, 300)) { imgui::console("con", lines, cmd, imgui::column().size(300, 200)); }; },
        1 => {
            imgui::box(imgui::column().padding(10).gap(8)) {
                imgui::canvas("c", imgui::column().skin(imgui::PANEL).size(100, 100)) { s => given = s; };
                imgui::drag_number("n", number);
                if imgui::color_picker("p", color) { color_true = true; }
                imgui::input_number("wide", wide, imgui::Drag { lo: 0, hi: 5.0e9, step: 3.0e9, .. });
            };
        },
        2 => {
            imgui::box(imgui::column().padding(10).gap(8)) {
                imgui::button("before");
                imgui::knob("k", gain, 0, 1);
            };
        },
        3 => {
            imgui::box("holder", imgui::column().size(300, 400)) {
                imgui::console("tall", lines, cmd);
                imgui::row_list("rows", 3, 20) { k => imgui::text("row"); };
            };
        },
        _ => { imgui::log_view("view", ring, imgui::column().size(300, 100)); },
    }
}
fn frame_with(p: imgui::Pointer, n: imgui::NavInput) {
    imgui::frame(imgui::Input { pointer: p, nav: n, viewport: float2 { 800.0, 600.0 }, .. }, 1.0 / 60.0) { ui(); };
}
fn step() { frame_with(imgui::Pointer { pos: pos, down: down, wheel: wheel, .. }, imgui::NavInput { .. }); }
fn nav(n: imgui::NavInput) { frame_with(imgui::Pointer { pos: pos, .. }, n); }
fn press() {
    down = true;
    frame_with(imgui::Pointer { pos: pos, down: true, pressed: true, clicks: 1, .. }, imgui::NavInput { .. });
}
fn release() {
    down = false;
    frame_with(imgui::Pointer { pos: pos, released: true, .. }, imgui::NavInput { .. });
}
fn center(i: imgui::Id) -> float2 {
    let r = imgui::rect_of(i);
    float2 { r.x + r.w * 0.5, r.y + r.h * 0.5 }
}

fn main() {
    print("--- a console's history");
    imgui::log(imgui::console_history, "older");
    step();
    step();
    cmd.append("spa");
    imgui::focus(imgui::sub_id(imgui::id("con"), "input"), true);
    step();
    nav(imgui::NavInput { up: true, .. });
    print("up: ", cmd[..]);
    nav(imgui::NavInput { down: true, .. });
    print("down: ", cmd[..]);
    imgui::blur();

    print("--- log lines");
    var l = imgui::Log { .. };
    imgui::log(l, "hello\n");
    print("hello\\n: ", imgui::log_count(l));
    imgui::log(l, "a\n\nb");
    print("a\\n\\nb: ", imgui::log_count(l));
    var small = imgui::Log { lines_kept: 8, .. };
    for k in 12 { imgui::log(small, str("line ", k)); }
    small.lines_kept = 3;
    print("lines_kept down: oldest still reads ", imgui::log_text(small, 0));
    imgui::log(small, "new");
    print("then one more: ", imgui::log_count(small), " lines, ", imgui::log_text(small, 0), " to ", imgui::log_text(small, 2));

    print("--- format_fixed");
    var t: u8[>..] = [];
    imgui::format_fixed(t, 0.0 / 0.0, 3);
    print("NaN isn't 0.000: ", !(t[..] == "0.000"));

    print("--- a canvas in a class with padding");
    mode = 1;
    step();
    step();
    step();
    print("given ", given.x, " ", given.y);

    print("--- enter after a drag");
    let nid = imgui::id("n");
    pos = center(nid);
    step();
    press();
    pos.x += 30.0;
    step();
    step();
    release();
    pos = float2 { -100.0, -100.0 };
    step();
    imgui::focus(nid, true);
    step();
    nav(imgui::NavInput { accept: true, .. });
    print("typing ", imgui::number_editing == nid.v);
    imgui::number_editing = 0;
    imgui::blur();
    step();

    print("--- a small move in a dark color");
    let was = color;
    color_true = false;
    imgui::focus(imgui::sub_id(imgui::id("p"), "sv"), true);
    step();
    nav(imgui::NavInput { right: true, .. });
    print("changed ", !(color == was), ", said so ", color_true);
    imgui::blur();

    print("--- an i32 past its range");
    imgui::focus(imgui::id("wide"), true);
    step();
    nav(imgui::NavInput { right: true, .. });
    print("wide ", wide);
    imgui::blur();

    print("--- a knob's end");
    mode = 2;
    step();
    step();
    let kid = imgui::sub_id(imgui::id("k"), "knob");
    imgui::focus(kid, true);
    step();
    step();
    nav(imgui::NavInput { up: true, .. });
    step();
    print("gain ", gain, ", left it ", !imgui::is_focused(kid));

    print("--- default sizes");
    mode = 3;
    for k in 300 { imgui::log(lines, "a line"); }
    for k in 3 { step(); }
    let tall = imgui::rect_of(imgui::id("holder"));
    imgui::id_scope(imgui::id("holder")) {
        print("console height under the box's ", imgui::rect_of(imgui::id("tall")).h < tall.h);
        print("row list width ", imgui::rect_of(imgui::id("rows")).w);
    };

    print("--- scrolled back, the ring full");
    mode = 4;
    for k in 40 { imgui::log(ring, str("line ", k)); }
    for k in 3 { step(); }
    pos = center(imgui::id("view"));
    step();
    wheel = float2 { 0.0, 2.0 };
    step();
    wheel = float2 { 0.0, 0.0 };
    for k in 30 { step(); }
    let pane = imgui::sub_id(imgui::id("view"), "pane");
    let line_h = imgui::class_style(imgui::LOG).normal.text_size * 1.4;
    let before = imgui::state_of(pane.v).scroll.y;
    for k in 5 { imgui::log(ring, "more"); }
    for k in 3 { step(); }
    let after = imgui::state_of(pane.v).scroll.y;
    print("moved up five lines with them: ", abs((before - after) - 5.0 * line_h) < 1.0);
}
