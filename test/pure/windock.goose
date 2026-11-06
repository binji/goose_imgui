// Windows and docks, no GPU: small things, each with windows of its own.
// Collapsed before its first frame, a window still goes where its Desc says.
// A floating dock isn't taken over by a new pair where it was made. A press
// in a floating dock's body raises the dock. dock_window_with of two
// neighbors stays docked. A window docked before its space's first frame
// doesn't float for it. One edge dragged leaves the other axis alone, and
// stops at min_w. A WINDOW_NO_MOVE window shows no targets. DOCK_CENTER takes
// the biggest leaf. A loaded layout keeps each leaf's tab, and replaces panes.
import std;
import vec;
import gfx;
import gfx2d from "../../../goose_gfx2d";
import imgui from "../..";

var mode = 0;
var pos = float2 { -100.0, -100.0 };
var down = false;

fn ui() {
    match mode {
        0 => {
            imgui::window("Set first", imgui::column().absolute(16, 16).size(260, 180)) { imgui::text("x"); };
        },
        1 => {
            imgui::window("A", imgui::column().absolute(20, 20).size(160, 100)) { imgui::text("a"); };
            imgui::window("B", imgui::column().absolute(300, 20).size(160, 100)) { imgui::text("b"); };
            imgui::window("C", imgui::column().absolute(20, 200).size(160, 100)) { imgui::text("c"); };
        },
        2 => {
            imgui::dock_space("space", imgui::column().size(400, 300));
            imgui::window("D1") { imgui::text("d"); };
            imgui::window("D2") { imgui::text("e"); };
            imgui::window("D3") { imgui::text("f"); };
            imgui::window("D4") { imgui::text("g"); };
        },
        3 => {
            imgui::window("Fit", imgui::column().absolute(40, 40).min_w(200)) { imgui::text("some content"); };
            imgui::window("Fixed", imgui::column().absolute(40, 200).size(300, 120), imgui::WINDOW_NO_MOVE) { imgui::text("f"); };
            imgui::window("Other", imgui::column().absolute(400, 200).size(160, 120)) { imgui::text("o"); };
        },
        _ => {},
    }
}
fn frame_with(p: imgui::Pointer) {
    imgui::frame(imgui::Input { pointer: p, viewport: float2 { 800.0, 600.0 }, .. }, 1.0 / 60.0) { ui(); };
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
fn wid(title: const u8[:]) -> u64 { imgui::id(title).v }
fn front() -> u64 { imgui::window_order[imgui::window_order.len - 1] }
fn host_of(title: const u8[:]) -> u64 { imgui::dock_host_of(imgui::window_state(wid(title)).dock) }
fn leaf_of(title: const u8[:]) -> i32 { imgui::window_state(wid(title)).dock }

fn main() {
    print("--- collapsed first");
    imgui::collapse_window("Set first", true);
    step();
    step();
    let r = imgui::window_rect("Set first");
    print("at ", r.x, " ", r.y, ", width ", r.w, ", collapsed ", imgui::is_window_collapsed("Set first"));

    print("--- a floating dock");
    mode = 1;
    step();
    step();
    imgui::dock_window_with("B", "A", imgui::DOCK_CENTER);
    step();
    step();
    let first = host_of("B");
    print("in a dock ", first != 0);
    imgui::undock_window("A");
    imgui::set_window_rect("A", gfx2d::Rect { 500.0, 300.0, 160.0, 100.0 });
    step();
    step();
    let before = imgui::rect_of(imgui::Id { first });
    imgui::dock_window_with("C", "A", imgui::DOCK_CENTER);
    step();
    step();
    let after = imgui::rect_of(imgui::Id { first });
    print("a new dock ", host_of("C") != first, ", the first stayed ", before.x == after.x && before.y == after.y, ", B in it ", host_of("B") == first);

    print("--- a press in its body");
    imgui::raise_window("C");
    step();
    step();
    pos = float2 { after.x + after.w * 0.5, after.y + after.h * 0.5 };
    step();
    press();
    release();
    pos = float2 { -100.0, -100.0 };
    step();
    print("in front ", front() == first);

    print("--- neighbors");
    mode = 2;
    imgui::dock_window("D1", "space", imgui::DOCK_LEFT);
    imgui::dock_window("D2", "space", imgui::DOCK_RIGHT, 0.5);
    step();
    print("not floating for its first frame: ", imgui::state_of(wid("D1")).seen < 0);
    step();
    step();
    imgui::dock_window_with("D1", "D2", imgui::DOCK_LEFT);
    step();
    step();
    print("D1 docked ", imgui::is_docked("D1"), ", D2 docked ", imgui::is_docked("D2"));

    print("--- the biggest leaf");
    // Split 0.6 / 0.4, the 0.6 split in two: the 0.4 is the biggest.
    imgui::undock_window("D1");
    imgui::undock_window("D2");
    imgui::dock_window("D1", "space", imgui::DOCK_LEFT);
    imgui::dock_window("D2", "space", imgui::DOCK_RIGHT, 0.4);
    imgui::dock_window_with("D3", "D1", imgui::DOCK_TOP, 0.5);
    step();
    step();
    imgui::dock_window("D4", "space", imgui::DOCK_CENTER);
    print("with D2: ", leaf_of("D4") == leaf_of("D2"));

    print("--- a layout loaded");
    imgui::raise_window("D2");
    let leaf = leaf_of("D2");
    imgui::dock_nodes[leaf].selected = wid("D4");
    step();
    step();
    var text: u8[>..] = [];
    imgui::layout_json(text);
    let pane = imgui::id("not in it").v;
    imgui::set_pane_fraction(pane, 0.25);
    let ok, err = imgui::load_layout_json(text[..]);
    print("loaded ", ok, err);
    for k in 3 { step(); }
    print("its tab kept: ", imgui::dock_nodes[leaf_of("D2")].selected == wid("D4"));
    print("a pane not in it: ", imgui::pane_fraction(pane, 0.0));

    print("--- edges");
    mode = 3;
    step();
    step();
    step();
    // The right edge, dragged left, far.
    let edge = imgui::sub_id(imgui::id("Fit"), 1);
    let er = imgui::rect_of(edge);
    pos = float2 { er.x + er.w * 0.5, er.y + er.h * 0.5 };
    step();
    press();
    pos.x -= 300.0;
    step();
    release();
    step();
    let ws = imgui::window_state(wid("Fit"));
    print("stopped at min_w ", imgui::window_rect("Fit").w >= 200.0, ", height still its content's ", ws.size.y == 0.0);

    print("--- no move");
    let tb = imgui::window_rect("Fixed");
    pos = float2 { tb.x + 40.0, tb.y + 8.0 };
    step();
    press();
    pos = float2 { 480.0, 260.0 };
    step();
    step();
    print("targets ", imgui::dock_aims.len);
    release();
}
