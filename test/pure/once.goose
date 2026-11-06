// A widget's interaction happens once a frame, however many times it is
// asked for, and goes by the class it is recorded with, no GPU. A number
// field and a split's handle, which keep state of their own, press once;
// a handle eases by its own class and names it in its events;
// an icon toggle shows that it is on.
import std;
import vec;
import gfx;
import gfx2d from "../../../goose_gfx2d";
import imgui from "../..";

var number: f64 = 5.0;
var on = false;
var handle_hover: f32 = 0.0;
var icon_checked: f32 = 0.0;
var pos = float2 { -100.0, -100.0 };
var down = false;

fn handle() -> imgui::Id { imgui::sub_id(imgui::id("sp"), 1) }

fn ui() {
    imgui::box(imgui::column().gap(8).padding(10)) {
        imgui::drag_number("Num", number);
        imgui::icon_toggle("Pick", imgui::ICON_CHECK, on);
        icon_checked = imgui::last_item().checked_t;
        imgui::split("sp", imgui::ROW, imgui::row().size(300, 60)) {
            imgui::pane("a") { imgui::text("a"); };
            imgui::pane("b") { imgui::text("b"); };
        };
        handle_hover = imgui::interact(handle(), imgui::column().skin(imgui::SPLITTER).hit()).hover_t;
    };
}
fn frame_with(p: imgui::Pointer) {
    imgui::frame(imgui::Input { pointer: p, viewport: float2 { 640.0, 480.0 }, .. }, 1.0 / 60.0) { ui(); };
}
fn step() { frame_with(imgui::Pointer { pos: pos, down: down, .. }); }
fn press() {
    down = true;
    frame_with(imgui::Pointer { pos: pos, down: true, pressed: true, clicks: 1, .. });
}
fn release() {
    down = false;
    frame_with(imgui::Pointer { pos: pos, released: true, .. });
}
fn center(i: imgui::Id) -> float2 {
    let r = imgui::rect_of(i);
    float2 { r.x + r.w * 0.5, r.y + r.h * 0.5 }
}
fn class_name(c: imgui::StyleClass) -> const u8[:] {
    if c == imgui::NUMBER { "NUMBER" } else if c == imgui::SPLITTER { "SPLITTER" }
    else if c == imgui::SCROLL_THUMB { "SCROLL_THUMB" } else if c == imgui::ICON_BUTTON { "ICON_BUTTON" }
    else if c == imgui::NONE { "NONE" } else { "other" }
}
fn show(what: const u8[:]) {
    var line: u8[>..] = [];
    for e in imgui::ui_events() {
        if line.len > 0 { line.append(", "); }
        format(line, imgui::ui_event_name(e.kind), " ", class_name(e.class));
    }
    print(what, ": ", line);
}

fn main() {
    for k in 3 { step(); }

    print("--- a number field");
    pos = center(imgui::id("Num"));
    step();
    press();
    show("press");
    release();
    show("release");

    print("--- a split's handle");
    pos = center(handle());
    step();
    show("onto it");
    print("hover after a frame: ", handle_hover > 0.0 && handle_hover < 1.0);
    for k in 60 { step(); }
    print("hover after a second: ", handle_hover);
    press();
    show("press");
    release();

    print("--- an icon toggle");
    pos = center(imgui::id("Pick"));
    step();
    press();
    release();
    for k in 30 { step(); }
    print("on ", on, ", checked ", icon_checked);
}
