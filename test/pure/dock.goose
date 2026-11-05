// Docking, driven by made-up input, no GPU: a layout made in code, each
// window's body in its leaf; tabs, one shown, another clicked to show, one
// dragged past another to reorder them; a button in a docked window; the
// handle between two leaves dragged; a tab dragged out, floating, still
// held; a floating window dragged by its title over a leaf, its targets
// shown, let go off them (floating still) and on one (docked beside it,
// the area it takes shown first); a target by the space's outer edge; a
// tab bar too full, its list; a tab bar hidden and shown again; a tab's
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
    imgui::window("E") { imgui::text("ee"); };
    imgui::window("Fifth window") { imgui::text("ef"); };
    imgui::window("Sixth window") { imgui::text("gee"); };
    imgui::window("P", imgui::column().size(170, 120).absolute(620, 20)) { imgui::text("pea"); };
    imgui::window("Q", imgui::column().size(170, 120).absolute(620, 300)) { imgui::text("queue"); };
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
fn leaf_of(name: const u8[:]) -> i32 { imgui::window_state(imgui::id(name).v).dock }
fn tabs_of(name: const u8[:]) -> u8[>..] {
    var t: u8[>..] = [];
    let n = leaf_of(name);
    for w in imgui::dock_nodes[n].tabs { format(t, imgui::window_state(w).title[..], " "); }
    t
}
// The target on `side` of node n, while one is shown.
fn aim(n: i32, side: i64) -> float2 {
    for a in imgui::dock_aims { if a.target.node == n && a.target.side == side { return mid(a.at); } }
    print("no target");
    float2 { -100.0, -100.0 }
}
fn previewed() -> bool {
    for n in imgui::nodes { if n.d.vis.class.index == imgui::DOCK_PREVIEW.index { return true; } }
    false
}
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
    // B's tab dragged right, past D's middle: they change places.
    print("tabs: ", tabs_of("B"));
    press(tab("B"));
    move_to(tab("D") + float2 { 30.0, 0.0 });
    release();
    print("B dragged past D: ", tabs_of("B"), "; B still docked ", imgui::is_docked("B"));
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
    // D by its title over A: its targets shown, nothing previewed until
    // one is under the pointer; let go off them, D floats still.
    let dr = rect("D");
    press(float2 { dr.x + 60.0, dr.y + 8.0 });
    let a2 = rect("A");
    move_to(float2 { a2.x + 10.0, a2.y + 10.0 });
    print("over A: ", imgui::dock_aims.len, " targets (five on A, four by the edges); previewed ", previewed());
    release();
    print("let go off the targets: D docked ", imgui::is_docked("D"));
    // Again, onto A's left target: previewed, then docked.
    let dr2 = rect("D");
    press(float2 { dr2.x + 60.0, dr2.y + 8.0 });
    move_to(mid(rect("A")));
    move_to(aim(leaf_of("A"), imgui::DOCK_LEFT));
    print("on A's left target: previewed ", previewed());
    release();
    print("docked left of A:");
    all();
    // D's tab's close button: D closed, its tab gone; opened again, back.
    click_at(mid(imgui::rect_of(imgui::sub_id(imgui::id("D"), "close"))));
    step();
    print("D's close: open ", show_d, ", its tab shown ", imgui::state_of(imgui::sub_id(imgui::id("D"), "tab").v).seen == imgui::frame_index);
    show_d = true;
    step();
    step();
    print("opened again: docked ", imgui::is_docked("D"), ", shown ", imgui::state_of(imgui::id("D").v).seen == imgui::frame_index);
    // E, floating, onto the space's right edge: beside all of it.
    let er = rect("E");
    press(float2 { er.x + 30.0, er.y + 8.0 });
    move_to(mid(rect("B")));
    move_to(aim(imgui::dock_root(imgui::id("main").v), imgui::DOCK_RIGHT));
    release();
    let root = imgui::dock_nodes[imgui::dock_root(imgui::id("main").v)];
    print("E by the outer right edge: docked ", imgui::is_docked("E"), ", its leaf the root's right half ",
          root.b == leaf_of("E"), ", ", round(rect("E").w), " wide");
    // Two more with D, in its narrow leaf: the bar too full, its list.
    imgui::dock_window_with("Fifth window", "D", imgui::DOCK_CENTER);
    imgui::dock_window_with("Sixth window", "D", imgui::DOCK_CENTER);
    for k in 3 { step(); }
    let list = imgui::sub_id(imgui::id("main"), leaf_of("D") as i64 + 0x7AB5);
    print("a full bar: its list button ", imgui::rect_of(list).w > 0.0, "; shown: Sixth ",
          imgui::dock_nodes[leaf_of("D")].selected == imgui::id("Sixth window").v);
    click_at(mid(imgui::rect_of(list)));
    print("its list: open ", imgui::popups.len);
    var item = imgui::Id { 0 };
    for n, i in imgui::nodes { if n.kind == imgui::NODE_TEXT && imgui::node_text(i as i32) == "D" && n.root > 0 { item = imgui::Id { imgui::nodes[n.parent].id }; } }
    click_at(mid(imgui::rect_of(item)));
    print("D chosen from it: shown ", imgui::dock_nodes[leaf_of("D")].selected == imgui::id("D").v, ", open ", imgui::popups.len);
    // A's tab bar hidden from its tab's menu: A's body to the leaf's top; its
    // corner button shows the bar again.
    at = tab("A");
    step();
    run_frame(imgui::Pointer { pos: at, secondary: true, .. });
    step();
    var hide = imgui::Id { 0 };
    for n, i in imgui::nodes { if n.kind == imgui::NODE_TEXT && imgui::node_text(i as i32) == "Hide tab bar" { hide = imgui::Id { imgui::nodes[n.parent].id }; } }
    click_at(mid(imgui::rect_of(hide)));
    step();
    print("A's tab bar hidden: A at ", round(rect("A").y), ", tab shown ",
          imgui::state_of(imgui::sub_id(imgui::id("A"), "tab").v).seen == imgui::frame_index);
    click_at(mid(imgui::rect_of(imgui::sub_id(imgui::id("A"), "show tabs"))));
    step();
    print("its corner button: A at ", round(rect("A").y), ", tab shown ",
          imgui::state_of(imgui::sub_id(imgui::id("A"), "tab").v).seen == imgui::frame_index);
    // Q onto P's right target: the two in a floating dock where P was, side
    // by side, the dock titled by P.
    let pr = rect("P");
    let qr = rect("Q");
    press(float2 { qr.x + 40.0, qr.y + 8.0 });
    move_to(mid(pr));
    var right = float2 { -100.0, -100.0 };
    for a in imgui::dock_aims { if a.target.window == imgui::id("P").v && a.target.side == imgui::DOCK_RIGHT { right = mid(a.at); } }
    move_to(right);
    print("Q on P's right target: previewed ", previewed());
    release();
    step();
    let host = hash_combine(imgui::id("P").v, 0xD0C7);
    let hr = imgui::state_of(host).rect;
    print("a floating dock at ", round(hr.x), " ", round(hr.y), ", ", round(hr.w), " by ", round(hr.h), "; its title P ",
          imgui::window_state(host).title[..] == "P");
    show("P");
    show("Q");
    // It moves by its title, the two with it.
    press(float2 { hr.x + hr.w * 0.5, hr.y + 8.0 });
    move_to(float2 { hr.x + hr.w * 0.5 - 300.0, hr.y + 8.0 + 200.0 });
    release();
    step();
    print("the dock moved:");
    show("P");
    show("Q");
    // Its windows over it, over the program's dock space.
    var order: u8[>..] = [];
    for k in imgui::root_order {
        let r = imgui::roots[k as i64];
        if r.popup == host { order.append("dock "); }
        if r.popup == imgui::id("P").v { order.append("P "); }
        if r.popup == imgui::id("B").v { order.append("B "); }
    }
    print("  drawn: ", order);
    // Q's tab dragged out: floating again; P still in the dock.
    press(tab("Q"));
    move_to(float2 { 700.0, 560.0 });
    release();
    step();
    print("Q's tab dragged out:");
    show("P");
    show("Q");
    // C undocked: its leaf gone, B taking the room.
    imgui::undock_window("C");
    step();
    step();
    print("C undocked:");
    all();
}
