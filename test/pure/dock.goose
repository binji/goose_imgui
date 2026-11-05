// Docking, driven by made-up input, no GPU: a layout made in code, each
// window's body in its leaf; tabs, one shown, another clicked to show;
// a button in a docked window; the handle between two leaves dragged; a tab
// dragged out, floating, still held; a floating window dragged by its title
// to a leaf's edge (the drop shown as it goes), docked beside it; a tab's
// close button; the last window of a leaf undocked, the leaf gone.
import std;
import vec;
import math;
import gfx;
import gfx2d from "../../../goose_gfx2d";
import imgui from "../..";

var log: u8[>..] = [];
var show_d = true;

fn ui() {
    imgui::dock_space("main", imgui::column().size(600, 400));
    imgui::window("A") { if imgui::button("Press") { log.append("pressed;"); } };
    imgui::window("B") { imgui::text("bee"); };
    imgui::window("C") { imgui::text("sea"); };
    imgui::window("D", show_d) { imgui::text("dee"); };
}

var at = float2 { -100.0, -100.0 };
fn run_frame(p: imgui::Pointer) { imgui::frame(imgui::Input { pointer: p, viewport: float2 { 800.0, 600.0 }, .. }, 1.0 / 60.0) { ui(); }; }
fn step() { run_frame(imgui::Pointer { pos: at, .. }); }
fn click_at(p: float2) {
    at = p;
    step();
    run_frame(imgui::Pointer { pos: at, down: true, pressed: true, clicks: 1, .. });
    run_frame(imgui::Pointer { pos: at, released: true, .. });
    step();
}
fn press(p: float2) {
    at = p;
    step();
    run_frame(imgui::Pointer { pos: at, down: true, pressed: true, clicks: 1, .. });
}
fn move_to(p: float2) {
    for k in 1..5 {
        at = at + (p - at) * (k as f32 / 4.0);
        run_frame(imgui::Pointer { pos: at, down: true, .. });
    }
    at = p;
    run_frame(imgui::Pointer { pos: at, down: true, .. });
}
fn release() { run_frame(imgui::Pointer { pos: at, released: true, .. }); step(); }
fn mid(r: gfx2d::Rect) -> float2 { float2 { r.x + r.w * 0.5, r.y + r.h * 0.5 } }
fn rect(name: const u8[:]) -> gfx2d::Rect { imgui::rect_of(imgui::id(name)) }
fn show(name: const u8[:]) {
    let r = rect(name);
    let shown = imgui::state_of(imgui::id(name).v).seen == imgui::frame_index;
    print("  ", name, if imgui::is_docked(name) { " docked" } else { " floating" },
          if shown { str(": ", round(r.x), " ", round(r.y), " ", round(r.w), " ", round(r.h)) } else { str(": not shown") });
}
fn all() { show("A"); show("B"); show("C"); show("D"); }
// A tab's label (its left, not its close button).
fn tab(name: const u8[:]) -> float2 {
    let r = imgui::rect_of(imgui::sub_id(imgui::id(name), "tab"));
    float2 { r.x + 8.0, r.y + r.h * 0.5 }
}

fn main() {
    // B first (the first fills the space, whatever its side); A on the left,
    // a quarter; C under B, 0.3; D a tab with B.
    imgui::dock_window("B", "main", imgui::DOCK_CENTER);
    imgui::dock_window("A", "main", imgui::DOCK_LEFT, 0.25);
    imgui::dock_window_with("C", "B", imgui::DOCK_BOTTOM, 0.3);
    imgui::dock_window_with("D", "B", imgui::DOCK_CENTER);
    for k in 3 { step(); }
    print("docked:");
    all();
    // B's tab clicked: B shown, D not.
    click_at(tab("B"));
    print("B's tab:");
    all();
    // A's button, docked.
    var bid = imgui::Id { 0 };
    for n, i in imgui::nodes { if n.kind == imgui::NODE_TEXT && imgui::node_text(i as i32) == "Press" { bid = imgui::Id { imgui::nodes[n.parent].id }; } }
    click_at(mid(imgui::rect_of(bid)));
    print("button in A: ", log);
    // The handle between A and the rest, 60 right.
    let ar = rect("A");
    press(float2 { ar.x + ar.w + 2.0, ar.y + 200.0 });
    move_to(float2 { ar.x + ar.w + 62.0, ar.y + 200.0 });
    release();
    print("handle right 60:");
    all();
    // D's tab dragged out, below the dock space: floating, held.
    click_at(tab("D"));
    press(tab("D"));
    move_to(float2 { 650.0, 480.0 });
    print("D's tab dragged out, held: ", imgui::is_docked("D") == false, ", active is D's title: ",
          imgui::active == imgui::sub_id(imgui::id("D"), "title").v);
    move_to(float2 { 700.0, 500.0 });
    release();
    print("let go:");
    all();
    // D by its title to A's left edge: the drop shown; let go, docked there.
    let dr = rect("D");
    press(float2 { dr.x + 60.0, dr.y + 8.0 });
    let a2 = rect("A");
    move_to(float2 { a2.x + 10.0, a2.y + a2.h * 0.5 });
    var preview = false;
    for r in imgui::roots { if r.kind == imgui::ROOT_TOOLTIP { preview = true; } }
    print("over A's left edge, the drop shown: ", preview);
    release();
    print("docked left of A:");
    all();
    // D's tab's close button: D closed.
    let cr = imgui::rect_of(imgui::sub_id(imgui::id("D"), "close"));
    click_at(mid(cr));
    print("D's close: open ", show_d);
    // C undocked: its leaf gone, B taking the room.
    imgui::undock_window("C");
    step();
    step();
    print("C undocked:");
    all();
}
