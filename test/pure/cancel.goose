// Cancel goes first to what is in hand, no GPU. A number being typed and a
// thing carried, in a modal: Escape ends them and leaves the modal, and the
// next one closes it. With nothing open, neither is the program's "back".
// A number field gone while it was typed in doesn't hold cancel. A drop by
// accept doesn't also activate what it lands on.
import std;
import vec;
import gfx;
import gfx2d from "../../../goose_gfx2d";
import imgui from "../..";

var open = true;
var in_modal = true;
var show_number = true;
var number: f64 = 5.0;
var carrying = false;
var dropped = -1;
var activated = 0;
var pos = float2 { -100.0, -100.0 };
var down = false;
// As recorded: IDs inside a modal are under its scope.
var num_id = imgui::Id { 0 };
var src_id = imgui::Id { 0 };
var dst_id = imgui::Id { 0 };

fn body() {
    num_id = imgui::id("Num");
    src_id = imgui::id("src");
    dst_id = imgui::id("dst");
    if show_number { imgui::drag_number("Num", number); }
    let src = imgui::clickable(imgui::column().size(60, 30));
    carrying = imgui::drag_source(imgui::interact(imgui::id("src"), src), 1, 7);
    imgui::box("src", src) {};
    let dst = imgui::clickable(imgui::column().size(60, 30));
    let it = imgui::interact(imgui::id("dst"), dst);
    let d = imgui::drop_target(it, 1);
    if d.dropped { dropped = d.payload; }
    if it.activated { activated++; }
    imgui::box("dst", dst) {};
}
fn ui() {
    if in_modal {
        imgui::modal("m", open, imgui::column()) { body(); };
    } else {
        imgui::box(imgui::column().gap(8).padding(10)) { body(); };
    }
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
fn escape() { frame_with(imgui::Pointer { pos: pos, down: down, .. }, imgui::NavInput { cancel: true, .. }); }
fn accept() { frame_with(imgui::Pointer { pos: pos, .. }, imgui::NavInput { accept: true, .. }); }
fn center(i: imgui::Id) -> float2 {
    let r = imgui::rect_of(i);
    float2 { r.x + r.w * 0.5, r.y + r.h * 0.5 }
}
fn typing() -> bool { imgui::is_focused(imgui::sub_id(num_id, "edit")) }
fn state(what: const u8[:]) {
    print(what, ": modal ", open, ", typing ", typing(), ", carrying ", carrying, ", back ", imgui::cancelled());
}
fn start_typing() {
    pos = center(num_id);
    step();
    press();
    release();
}
fn pick_up() {
    pos = center(src_id);
    step();
    press();
    pos.x += 12.0;
    step();
    step();
}
fn put_down() {
    down = false;
    step();
    step();
    pos = float2 { -100.0, -100.0 };
    step();
}

fn main() {
    step();
    step();
    start_typing();
    state("typing, in a modal");
    escape();           // the frame after it began
    state("escape");
    step();
    state("next frame");
    start_typing();
    step();
    step();
    state("typing again");
    escape();
    state("escape");
    escape();
    state("escape again");
    open = true;
    step();
    step();

    pick_up();
    state("carrying, in a modal");
    escape();
    state("escape");
    put_down();
    escape();
    state("escape again");
    open = true;
    step();
    step();

    // The field gone while it was typed in: nothing holds cancel.
    start_typing();
    show_number = false;
    step();
    step();
    escape();
    state("the field gone, escape");
    show_number = true;
    open = true;
    step();
    escape();
    step();
    open = true;
    step();
    step();

    // Nothing open: not the program's "back".
    in_modal = false;
    step();
    step();
    start_typing();
    escape();
    state("typing, no modal");
    escape();
    state("escape again");
    pick_up();
    escape();
    state("carrying, no modal");
    put_down();
    escape();
    state("escape again");

    // Carried by the keys, dropped by accept.
    imgui::focus(src_id, true);
    step();
    accept();
    step();
    print("picked up by accept: ", carrying);
    imgui::focus(dst_id, true);
    step();
    accept();
    step();
    print("dropped ", dropped, ", activated ", activated);
    accept();
    step();
    print("then accepted: activated ", activated);
}
