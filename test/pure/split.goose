// Splitters, driven by made-up input, no GPU: panes sharing a split's
// length, one with a fraction to start with; a handle dragged, moving the
// pane before it, or the one after if only that one has a fraction; a pane
// kept no smaller than its least; a column split inside a row split; the
// split resized, its panes keeping their fractions.
import std;
import vec;
import math;
import gfx;
import gfx2d from "../../../goose_gfx2d";
import imgui from "../..";

var width: f64 = 600.0;

fn ui() {
    imgui::box(imgui::column().size(width, 300)) {
        imgui::split("main", imgui::ROW, imgui::row().grow()) {
            imgui::pane("left", 0.25) { imgui::text("left"); };
            imgui::pane("middle") {
                imgui::split("stack", imgui::COLUMN, imgui::column().grow()) {
                    imgui::pane("top") { imgui::text("top"); };
                    imgui::pane("bottom", 0.3) { imgui::text("bottom"); };
                };
            };
            imgui::pane("right") { imgui::text("right"); };
        };
    };
}

var at = float2 { -100.0, -100.0 };
fn run_frame(p: imgui::Pointer) { imgui::frame(imgui::Input { pointer: p, viewport: float2 { 800.0, 600.0 }, .. }, 1.0 / 60.0) { ui(); }; }
fn step() { run_frame(imgui::Pointer { pos: at, .. }); }
fn drag(p: float2, d: float2) {
    at = p;
    step();
    run_frame(imgui::Pointer { pos: at, down: true, pressed: true, clicks: 1, .. });
    at = p + d;
    run_frame(imgui::Pointer { pos: at, down: true, .. });
    run_frame(imgui::Pointer { pos: at, released: true, .. });
    step();
}
fn mid(r: gfx2d::Rect) -> float2 { float2 { r.x + r.w * 0.5, r.y + r.h * 0.5 } }
// The panes' IDs: under their split's, and the inner split's under its pane's.
fn in_main(name: const u8[:]) -> imgui::Id { imgui::sub_id(imgui::id("main"), name) }
fn in_stack(name: const u8[:]) -> imgui::Id { imgui::sub_id(imgui::sub_id(in_main("middle"), "stack"), name) }
fn sizes() {
    let l = imgui::rect_of(in_main("left"));
    let m = imgui::rect_of(in_main("middle"));
    let r = imgui::rect_of(in_main("right"));
    let top = in_stack("top");
    let bottom = in_stack("bottom");
    print("  across: ", round(l.w), " ", round(m.w), " ", round(r.w), "; down: ", round(imgui::rect_of(top).h), " ",
          round(imgui::rect_of(bottom).h));
}
fn handle(k: i64) -> gfx2d::Rect { imgui::rect_of(imgui::sub_id(imgui::id("main"), k)) }

fn main() {
    step();
    step();
    step();
    // 600 across, two 5-pixel handles: left a quarter (150), the others
    // sharing the rest; 300 down: bottom 0.3 (90), top the rest.
    print("at first:");
    sizes();
    // The first handle 50 right: left (which has a fraction) grows.
    drag(mid(handle(1)), float2 { 50.0, 0.0 });
    print("first handle right 50:");
    sizes();
    print("  cursor on a handle: ", imgui::cursor() == imgui::CURSOR_EW_RESIZE);
    // The second, between two that share: the one before takes a fraction.
    drag(mid(handle(2)), float2 { 60.0, 0.0 });
    print("second handle right 60:");
    sizes();
    // Down: the handle between top and bottom (bottom has the fraction).
    let vh = imgui::sub_id(imgui::sub_id(in_main("middle"), "stack"), 1);
    drag(mid(imgui::rect_of(vh)), float2 { 0.0, -40.0 });
    print("down handle up 40:");
    sizes();
    // Too far: the pane no smaller than its least.
    drag(mid(handle(1)), float2 { -500.0, 0.0 });
    print("first handle far left:");
    sizes();
    // The split resized: its panes keep their fractions.
    width = 800.0;
    step();
    step();
    print("800 across:");
    sizes();
}
