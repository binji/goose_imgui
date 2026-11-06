// Keyed rich text and carrying, no GPU. A span is hit only where it can be
// seen: not under a modal, not scrolled out of its pane. A keyed text coming
// back counts as appearing. What is carried by navigation can be put down by
// a press, and by cancel_drag.
import std;
import vec;
import gfx;
import gfx2d from "../../../goose_gfx2d";
import imgui from "../..";

var mode = 0;
var shown = true;
var open = false;
var hovered = false;
var clicks = 0;
var dropped = -1;
var src_id = imgui::Id { 0 };
var pos = float2 { -100.0, -100.0 };
var down = false;

fn ui() {
    match mode {
        0 => {
            imgui::box(imgui::column().padding(10)) {
                if shown {
                    let hit = imgui::rich("Some [u=burn]Burn[/] here", imgui::column());
                    hovered = hit.is("burn");
                }
            };
            imgui::modal("m", open, imgui::column().absolute(0, 0)) { imgui::text("over it"); };
        },
        1 => {
            imgui::scroll("pane", imgui::column().size(200, 40)) {
                for k in 8 { imgui::text("line"); }
                let hit = imgui::rich("Some [u=burn]Burn[/] here", imgui::column());
                hovered = hit.is("burn");
            };
        },
        _ => {
            imgui::box(imgui::column().padding(10).gap(8)) {
                let src = imgui::clickable(imgui::column().size(60, 30));
                src_id = imgui::id("src");
                imgui::drag_source(imgui::interact(src_id, src), 1, 7);
                imgui::box("src", src) {};
                let dst = imgui::clickable(imgui::column().size(60, 30));
                let it = imgui::interact(imgui::id("dst"), dst);
                let d = imgui::drop_target(it, 1);
                if d.dropped { dropped = d.payload; }
                if it.clicked { clicks++; }
                imgui::box("dst", dst) {};
            };
        },
    }
}
fn frame_with(p: imgui::Pointer, n: imgui::NavInput) {
    imgui::frame(imgui::Input { pointer: p, nav: n, viewport: float2 { 640.0, 480.0 }, .. }, 1.0 / 60.0) { ui(); };
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
fn accept() { frame_with(imgui::Pointer { pos: pos, .. }, imgui::NavInput { accept: true, .. }); }
fn center(r: gfx2d::Rect) -> float2 { float2 { r.x + r.w * 0.5, r.y + r.h * 0.5 } }

fn main() {
    imgui::add_span("u", imgui::Span { underline: true, .. });
    print("--- under a modal");
    step();
    step();
    let span = imgui::span_boxes[0].rect;
    let node = imgui::span_boxes[0].node;
    pos = center(span);
    step();
    step();
    print("hovered ", hovered);
    open = true;
    step();
    step();
    print("under a modal ", hovered);
    open = false;
    step();
    step();

    print("--- coming back");
    let born = imgui::state_of(node).born;
    shown = false;
    for k in 10 { step(); }
    shown = true;
    step();
    print("counted as appearing ", imgui::state_of(node).born > born);

    print("--- scrolled out");
    mode = 1;
    step();
    step();
    step();
    let out = imgui::span_boxes[0].rect;
    pos = center(out);
    step();
    step();
    print("below its pane: at ", out.y > 40.0, ", hovered ", hovered);

    print("--- carried by navigation");
    mode = 2;
    pos = float2 { -100.0, -100.0 };
    step();
    step();
    imgui::focus(src_id, true);
    step();
    accept();
    step();
    print("carrying ", imgui::dragging(1));
    pos = center(imgui::rect_of(imgui::id("dst")));
    step();
    press();
    release();
    step();
    print("pressed on a target: carrying ", imgui::dragging(1), ", dropped ", dropped, ", clicked ", clicks);
    pos = float2 { -100.0, -100.0 };
    step();
    imgui::focus(src_id, true);
    step();
    accept();
    step();
    print("carrying ", imgui::dragging(1));
    imgui::cancel_drag();
    step();
    print("cancel_drag: carrying ", imgui::dragging(1));
}
