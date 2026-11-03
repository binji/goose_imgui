// Scroll panes, no GPU: the wheel scrolls (eased, clamped at the ends);
// focus moved by navigation scrolls it into view; the thumb drags it.
import std;
import vec;
import math;
import gfx;
import gfx2d from "../../../goose_gfx2d";
import imgui from "../..";

var pos = float2 { 50.0, 50.0 };

fn ui() {
    imgui::scroll("list", imgui::column().gap(0).width(200).height(100)) {
        for k in 20 {
            imgui::box(k, imgui::row().height(25).grow_w().focusable()) { imgui::textf(imgui::column()) { out => format(out, "row ", k); }; };
        }
    };
}
fn run(p: imgui::Pointer, n: imgui::NavInput) {
    imgui::frame(imgui::Input { pointer: p, nav: n, viewport: float2 { 400.0, 300.0 }, .. }, 1.0 / 60.0) { ui(); };
}
fn step() { run(imgui::Pointer { pos: pos, .. }, imgui::NavInput { .. }); }
fn settle() { for k in 40 { step(); } }
fn offset() -> f64 { round(imgui::state_of(imgui::id("list").v).scroll.y) }

fn main() {
    step();
    step();
    let st = imgui::state_of(imgui::id("list").v);
    print("content ", st.content.y, " view ", st.view.y);
    run(imgui::Pointer { pos: pos, wheel: float2 { 0.0, -2.0 }, .. }, imgui::NavInput { .. });
    step();
    print("wheel down two lines, a frame later: ", offset() > 0.0 && offset() < 96.0);
    settle();
    print("settled: ", offset());
    for k in 5 { run(imgui::Pointer { pos: pos, wheel: float2 { 0.0, -5.0 }, .. }, imgui::NavInput { .. }); }
    settle();
    print("past the end: ", offset());
    run(imgui::Pointer { pos: float2 { 300.0, 250.0 }, wheel: float2 { 0.0, 3.0 }, .. }, imgui::NavInput { .. });
    settle();
    print("wheel outside the pane: ", offset());
    // Navigation: from the top, down past the view scrolls along.
    pos = float2 { 300.0, 250.0 };
    run(imgui::Pointer { pos: pos, wheel: float2 { 0.0, 50.0 }, .. }, imgui::NavInput { .. });
    pos = float2 { 50.0, 50.0 };
    run(imgui::Pointer { pos: pos, wheel: float2 { 0.0, 50.0 }, .. }, imgui::NavInput { .. });
    pos = float2 { 300.0, 250.0 };
    settle();
    print("back at the top: ", offset());
    for k in 6 { run(imgui::Pointer { pos: pos, .. }, imgui::NavInput { down: true, .. }); step(); }
    settle();
    print("focused row 5, scrolled to: ", offset());
    for k in 6 { run(imgui::Pointer { pos: pos, .. }, imgui::NavInput { up: true, .. }); step(); }
    settle();
    print("back up to row 0: ", offset());
    // The thumb: dragged half the view down.
    let th = imgui::rect_of(imgui::sub_id(imgui::id("list"), "thumb y"));
    let at = float2 { th.x + th.w * 0.5, th.y + 4.0 };
    run(imgui::Pointer { pos: at, down: true, pressed: true, clicks: 1, .. }, imgui::NavInput { .. });
    run(imgui::Pointer { pos: at + float2 { 0.0, 25.0 }, down: true, .. }, imgui::NavInput { .. });
    run(imgui::Pointer { pos: at + float2 { 0.0, 25.0 }, down: true, .. }, imgui::NavInput { .. });
    print("thumb dragged 25 of a 100 view of 500: ", offset());
    run(imgui::Pointer { pos: at + float2 { 0.0, 25.0 }, released: true, .. }, imgui::NavInput { .. });
}
