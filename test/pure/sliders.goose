// Sliders change their values only when the player moves them, no GPU.
// Shown, even between steps or out of range, a value is left alone and
// nothing reports a change; held still, one reports only the frame it moved.
// The f32 and whole-number kinds, slider_angle, a range, a knob and a drag
// number, whose values go through an f64 and back.
import std;
import vec;
import math;
import gfx;
import gfx2d from "../../../goose_gfx2d";
import imgui from "../..";

var f: f32 = 0.15;          // between steps
var d: f64 = 0.15;
var over: f64 = 5.0;        // past hi
var whole: i32 = 200;
var v: f32 = 0.15;
var angle: f64 = -120.0 * PI / 180.0;
var from: f64 = 30.5;
var to: f64 = 200.0;
var kn: f32 = 0.33;
var dn: f32 = 0.1;
var trues: i64[10] = [0; 10];
var pos = float2 { -100.0, -100.0 };
var down = false;

fn ui() {
    imgui::box(imgui::column().gap(4).padding(10)) {
        if imgui::slider("f", f, 0, 1, 0.1) { trues[0]++; }
        if imgui::slider("d", d, 0, 1, 0.1) { trues[1]++; }
        if imgui::slider("over", over, 0, 1, 0.0) { trues[2]++; }
        if imgui::slider("whole", whole, 0, 100) { trues[3]++; }
        if imgui::vslider("v", v, 0, 1, 0.1, imgui::column().height(60)) { trues[4]++; }
        if imgui::slider_angle("angle", angle) { trues[5]++; }
        if imgui::range_slider("range", from, to, 0, 100, 1, imgui::row().width(300)) { trues[6]++; }
        if imgui::knob("knob", kn, 0, 1, 0.25) { trues[7]++; }
        if imgui::drag_number("drag", dn) { trues[8]++; }
    };
}
fn frame_with(p: imgui::Pointer, nav: imgui::NavInput) {
    imgui::frame(imgui::Input { pointer: p, nav: nav, viewport: float2 { 640.0, 680.0 }, .. }, 1.0 / 60.0) { ui(); };
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
fn track(label: const u8[:]) -> imgui::Id { imgui::sub_id(imgui::id(label), "track") }
fn center(i: imgui::Id) -> float2 {
    let r = imgui::rect_of(i);
    float2 { r.x + r.w * 0.5, r.y + r.h * 0.5 }
}
fn report(what: const u8[:]) {
    print(what, ":");
    print("  values ", f, " ", d, " ", over, " ", whole, " ", v, " ", round(angle * 180.0 / PI), " ", from, " ", to, " ", kn, " ", dn);
    var line: u8[>..] = [];
    for t in trues { format(line, t, " "); }
    print("  true ", line);
    trues = [0; 10];
}
// Pressed on `i` and held still for a while.
fn hold(i: imgui::Id, what: const u8[:]) {
    pos = center(i);
    step();
    press();
    for k in 20 { step(); }
    release();
    pos = float2 { -100.0, -100.0 };
    step();
    report(what);
}

fn main() {
    for k in 30 { step(); }
    report("shown");

    hold(track("f"), "f32 held");
    hold(track("d"), "f64 held");
    hold(track("v"), "standing held");
    hold(track("angle"), "angle held");
    hold(track("range"), "range held");

    // Dragged, then held still.
    pos = center(imgui::id("drag"));
    step();
    press();
    pos.x += 20.0;
    step();
    for k in 20 { step(); }
    release();
    pos = float2 { -100.0, -100.0 };
    step();
    report("drag number dragged, held");

    // Past hi, a key steps it from hi.
    imgui::focus(track("whole"), true);
    step();
    frame_with(imgui::Pointer { pos: pos, .. }, imgui::NavInput { left: true, .. });
    imgui::focus(track("over"), true);
    step();
    frame_with(imgui::Pointer { pos: pos, .. }, imgui::NavInput { left: true, .. });
    report("past hi, left");
}
