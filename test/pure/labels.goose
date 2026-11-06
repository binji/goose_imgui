// Labels and IDs, no GPU: "##" is part of the ID, "###" and what follows it
// the whole of it, so the text before them can change. A button whose count
// changes between its press and its release is still clicked and focused; a
// window whose title changes keeps its place and answers to "###" alone.
import std;
import vec;
import gfx;
import gfx2d from "../../../goose_gfx2d";
import imgui from "../..";

var count = 3;
var clicks = 0;
var pos = float2 { -100.0, -100.0 };
var down = false;

fn ui() {
    imgui::box(imgui::column().padding(10)) {
        if imgui::button(str("Clear (", count, ")###clear")) { clicks++; }
    };
    imgui::window(str("Score ", count, "###score"), imgui::column().absolute(200, 50).size(160, 90)) {
        imgui::text("body");
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

fn main() {
    print("text: \"", imgui::label_text("Clear (3)###clear"), "\" \"", imgui::label_text("Play##dlc"), "\" \"",
          imgui::label_text("###only"), "\"");
    print("### same: ", imgui::id("A###k").v == imgui::id("B###k").v, " ", imgui::id("A###k").v == imgui::id("###k").v);
    print("### apart: ", imgui::id("A###k").v != imgui::id("A###j").v);
    print("## apart: ", imgui::id("A##k").v != imgui::id("B##k").v);
    print("sub_id: ", imgui::sub_id(imgui::id("p"), "A###k").v == imgui::sub_id(imgui::id("p"), "B###k").v);

    step();
    step();
    let b = imgui::id("###clear");
    let r = imgui::rect_of(b);
    print("found by ###: ", r.w > 0.0);
    pos = float2 { r.x + r.w * 0.5, r.y + r.h * 0.5 };
    imgui::focus(b, false);
    step();
    press();
    count = 2;          // the text changes while it is held
    step();
    release();
    step();
    print("clicked ", clicks, ", focused ", imgui::is_focused(b));

    let before = imgui::window_rect("###score");
    print("window before: ", before.x, " ", before.y);
    count = 1;
    step();
    step();
    let after = imgui::window_rect("###score");
    print("window after: ", after.x, " ", after.y);
    imgui::collapse_window("###score", true);
    step();
    print("collapsed by ###: ", imgui::is_window_collapsed("Score 7###score"));
}
