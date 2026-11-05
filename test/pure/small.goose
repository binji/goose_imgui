// The small pieces, driven by made-up input, no GPU: an icon button, a
// toggle and a small button clicked; a link clicked and accepted; a knob
// dragged up and left, and stepped by the keys; a standing slider clicked
// near its top and stepped; a range's nearer thumb taken and dragged, not
// past the other, the keys moving the one taken and accept changing
// which; an angle in degrees; a label and value, bullets, a spinner.
import std;
import vec;
import math;
import gfx;
import gfx2d from "../../../goose_gfx2d";
import imgui from "../..";

var log: u8[>..] = [];
var paused = false;
var gain = 0.5;
var level = 0.0;
var from = 20.0;
var to = 60.0;
var angle = PI / 2.0;

fn ui() {
    imgui::box(imgui::column().gap(8).padding(8)) {
        imgui::toolbar("tools") {
            if imgui::icon_button("Play", imgui::ICON_PLAY) { log.append("play;"); }
            if imgui::icon_toggle("Pause", imgui::ICON_PAUSE, paused) { log.append("pause;"); }
            imgui::separator();
            if imgui::small_button("Reset") { log.append("reset;"); }
        };
        if imgui::link("Docs") { log.append("docs;"); }
        imgui::box(imgui::row().gap(20)) {
            imgui::knob("Gain", gain, 0, 1);
            imgui::vslider("Level", level, 0, 10, 1, imgui::column().height(120));
        };
        imgui::range_slider("Range", from, to, 0, 100, 1, imgui::row().width(300));
        imgui::slider_angle("Angle", angle, -180, 180);
        imgui::label_value("Entities", "128", imgui::row().width(200));
        imgui::bullet_text("a point");
        imgui::spinner("busy");
    };
}

var at = float2 { -100.0, -100.0 };
fn run_frame(p: imgui::Pointer, n: imgui::NavInput) {
    imgui::frame(imgui::Input { pointer: p, nav: n, viewport: float2 { 640.0, 480.0 }, .. }, 1.0 / 60.0) { ui(); };
}
fn step() { run_frame(imgui::Pointer { pos: at, .. }, imgui::NavInput { .. }); }
fn click_at(p: float2) {
    at = p;
    step();
    run_frame(imgui::Pointer { pos: at, down: true, pressed: true, clicks: 1, .. }, imgui::NavInput { .. });
    run_frame(imgui::Pointer { pos: at, released: true, .. }, imgui::NavInput { .. });
    step();
}
fn press(p: float2) {
    at = p;
    step();
    run_frame(imgui::Pointer { pos: at, down: true, pressed: true, clicks: 1, .. }, imgui::NavInput { .. });
}
fn move_to(p: float2) {
    for k in 1..5 {
        at = at + (p - at) * (k as f32 / 4.0);
        run_frame(imgui::Pointer { pos: at, down: true, .. }, imgui::NavInput { .. });
    }
    at = p;
    run_frame(imgui::Pointer { pos: at, down: true, .. }, imgui::NavInput { .. });
}
fn release() { run_frame(imgui::Pointer { pos: at, released: true, .. }, imgui::NavInput { .. }); step(); }
fn nav(n: imgui::NavInput) { run_frame(imgui::Pointer { pos: at, .. }, n); step(); }
fn mid(r: gfx2d::Rect) -> float2 { float2 { r.x + r.w * 0.5, r.y + r.h * 0.5 } }
fn rect(i: imgui::Id) -> gfx2d::Rect { imgui::rect_of(i) }
fn shown(text: const u8[:]) -> bool {
    for n, i in imgui::nodes { if n.kind == imgui::NODE_TEXT && imgui::node_text(i as i32) == text { return true; } }
    false
}
fn r2(v: f64) -> f64 { round(v * 100.0) / 100.0 }

fn main() {
    step();
    step();
    let tools = imgui::id("tools");
    click_at(mid(rect(imgui::sub_id(tools, "Play"))));
    click_at(mid(rect(imgui::sub_id(tools, "Pause"))));
    click_at(mid(rect(imgui::sub_id(tools, "Reset"))));
    print("toolbar: ", log, " paused ", paused);
    click_at(mid(rect(imgui::sub_id(tools, "Pause"))));
    print("pause again: paused ", paused);
    log.clear();
    click_at(mid(rect(imgui::id("Docs"))));
    imgui::focus(imgui::id("Docs"), true);
    nav(imgui::NavInput { accept: true, .. });
    print("link clicked and accepted: ", log);
    imgui::blur();

    // The knob: up 50 pixels, a quarter of the range; left 100, half.
    let kid = imgui::sub_id(imgui::id("Gain"), "knob");
    press(mid(rect(kid)));
    move_to(at + float2 { 0.0, -50.0 });
    release();
    print("knob up 50: ", r2(gain));
    press(mid(rect(kid)));
    move_to(at + float2 { -100.0, 0.0 });
    release();
    print("knob left 100: ", r2(gain));
    imgui::focus(kid, true);
    nav(imgui::NavInput { up: true, .. });
    nav(imgui::NavInput { right: true, .. });
    print("knob up and right: ", r2(gain));
    imgui::blur();

    // The standing slider: clicked near its top, near hi; down, a step.
    let vt = rect(imgui::sub_id(imgui::id("Level"), "track"));
    let lv = rect(imgui::id("Level"));
    print("standing: ", round(vt.w), " by ", round(vt.h), ", taller than wide ", vt.h > vt.w, "; its label inside it ",
          vt.y + vt.h < lv.y + lv.h);
    click_at(float2 { vt.x + vt.w * 0.5, vt.y + 12.0 });
    print("clicked near its top: ", level);
    imgui::focus(imgui::sub_id(imgui::id("Level"), "track"), true);
    nav(imgui::NavInput { down: true, .. });
    print("down: ", level);
    imgui::blur();

    // The range: pressed near its lower thumb, which is dragged right, but
    // not past the upper one.
    let rt = rect(imgui::sub_id(imgui::id("Range"), "track"));
    let thumb = imgui::class_style(imgui::SLIDER_THUMB).normal.min_size.x;
    fn x_of(v: f64) -> f32 { rt.x + thumb * 0.5 + (rt.w - thumb) * (v / 100.0) as f32 }
    press(float2 { x_of(from) + 2.0, rt.y + rt.h * 0.5 });
    move_to(float2 { x_of(40.0), at.y });
    print("lower thumb to 40: ", from, " ", to);
    move_to(float2 { x_of(90.0), at.y });
    release();
    print("not past the upper: ", from, " ", to);
    press(float2 { x_of(95.0), rt.y + rt.h * 0.5 });
    move_to(float2 { x_of(80.0), at.y });
    release();
    print("the upper taken, to 80: ", from, " ", to);
    imgui::focus(imgui::sub_id(imgui::id("Range"), "track"), true);
    nav(imgui::NavInput { right: true, .. });
    print("right moves it: ", from, " ", to);
    nav(imgui::NavInput { accept: true, .. });
    nav(imgui::NavInput { left: true, .. });
    print("accept, then left moves the lower: ", from, " ", to);
    imgui::blur();

    // The angle: shown in degrees, kept in radians; a step right.
    print("angle shown: ", shown("90 deg"));
    imgui::focus(imgui::sub_id(imgui::id("Angle"), "track"), true);
    nav(imgui::NavInput { right: true, .. });
    print("a degree right: ", r2(angle * 180.0 / PI), " degrees, ", shown("91 deg"));
    imgui::blur();

    print("label and value: ", shown("Entities"), " ", shown("128"), "; bullet ", shown("a point"),
          "; spinner ", rect(imgui::id("busy")).w > 0.0);
}
