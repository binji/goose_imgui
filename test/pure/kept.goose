// What the player chose stays chosen however long a widget is hidden, past
// the sweep of what hasn't been recorded for a while, no GPU: a table's sort
// and its columns' widths, the thumb a range slider moves by the keys, how
// far back a console is in its history. And a range slider's lower thumb
// can be taken by the keys alone.
import std;
import vec;
import gfx;
import gfx2d from "../../../goose_gfx2d";
import imgui from "../..";

var shown = true;
var sort: i64 = -1;
var descending = false;
var from: f64 = 20.0;
var to: f64 = 60.0;
var lines = imgui::Log { .. };
var cmd: u8[>..] = [];
var pos = float2 { -100.0, -100.0 };
var down = false;

fn ui() {
    guard shown;
    imgui::box(imgui::column().gap(8).padding(10)) {
        let info = imgui::table("t", ["A", "B", "C"], 3, imgui::Table { .. }, imgui::column().size(300, 120)) { k, c =>
            imgui::text("x");
        };
        sort = info.sort;
        descending = info.descending;
        imgui::range_slider("Range", from, to, 0, 100, 1, imgui::row().width(300));
        imgui::console("con", lines, cmd, imgui::column().size(300, 120));
    };
}
fn frame_with(p: imgui::Pointer, nav: imgui::NavInput) {
    imgui::frame(imgui::Input { pointer: p, nav: nav, viewport: float2 { 640.0, 480.0 }, .. }, 1.0 / 60.0) { ui(); };
}
fn step() { frame_with(imgui::Pointer { pos: pos, down: down, .. }, imgui::NavInput { .. }); }
fn press() {
    down = true;
    frame_with(imgui::Pointer { pos: pos, down: true, pressed: true, clicks: 1, .. }, imgui::NavInput { .. });
}
fn release() {
    down = false;
    frame_with(imgui::Pointer { pos: pos, released: true, .. }, imgui::NavInput { .. });
}
fn nav(n: imgui::NavInput) { frame_with(imgui::Pointer { pos: pos, .. }, n); }
fn center(i: imgui::Id) -> float2 {
    let r = imgui::rect_of(i);
    float2 { r.x + r.w * 0.5, r.y + r.h * 0.5 }
}
fn hide() {
    shown = false;
    for k in 200 { step(); }
    shown = true;
    step();
    step();
}
fn header(c: i64) -> imgui::Id { imgui::sub_id(imgui::id("t"), c) }
fn report(what: const u8[:]) {
    print(what, ": sort ", sort, " descending ", descending, ", first column ", imgui::rect_of(header(0)).w,
          ", range ", from, " ", to, ", command \"", cmd, "\"");
}

fn main() {
    imgui::log(imgui::console_history, "one");
    imgui::log(imgui::console_history, "two");
    imgui::log(imgui::console_history, "three");
    step();
    step();
    report("to start");

    // Sorted by its second column, descending.
    pos = center(header(1));
    step();
    press();
    release();
    step();
    press();
    release();
    step();
    // Its first column wider.
    pos = center(imgui::sub_id(header(0), "grip"));
    step();
    press();
    pos.x += 30.0;
    step();
    release();
    pos = float2 { -100.0, -100.0 };
    step();
    step();

    // The lower thumb, from the keys alone; one step down.
    let track = imgui::sub_id(imgui::id("Range"), "track");
    imgui::focus(track, true);
    step();
    nav(imgui::NavInput { accept: true, .. });
    nav(imgui::NavInput { left: true, .. });

    // One back in the history.
    let input = imgui::sub_id(imgui::id("con"), "input");
    imgui::focus(input, true);
    step();
    nav(imgui::NavInput { up: true, .. });
    report("chosen");

    hide();
    report("hidden and shown");

    imgui::focus(track, true);
    step();
    nav(imgui::NavInput { left: true, .. });
    imgui::focus(input, true);
    step();
    nav(imgui::NavInput { up: true, .. });
    report("left and up");
}
