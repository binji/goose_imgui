// Layouts saved and loaded, driven by made-up input, no GPU: a layout of
// docked and floating windows, a collapsed one, a split and an open
// header saved; all of it changed; loaded again, as it was. The text,
// saved twice the same; bad layouts refused, nothing changed; a file
// written and read back; windows first shown after loading keeping the
// layout's order.
import std;
import vec;
import math;
import os;
import gfx;
import gfx2d from "../../../goose_gfx2d";
import imgui from "../..";

var shut_open = true;
var hide_cd = false;

fn ui() {
    imgui::box(imgui::column().size(800, 600)) {
        imgui::split("split", imgui::ROW, imgui::row().size(800, 80)) {
            imgui::pane("left", 0.3) { imgui::text("left"); };
            imgui::pane("right") { imgui::text("right"); };
        };
        imgui::dock_space("main", imgui::column().size(500, 400));
    };
    imgui::window("A") {
        imgui::collapsing("Section") { imgui::text("inside"); };
    };
    imgui::window("B") { imgui::text("bee"); };
    if !hide_cd {
        imgui::window("C", imgui::column().size(150, 100).absolute(560, 100)) { imgui::text("sea"); };
        imgui::window("D", imgui::column().size(150, 100).absolute(580, 300)) { imgui::text("dee"); };
    }
    imgui::window("Shut", shut_open, imgui::column().size(100, 60).absolute(600, 450)) { imgui::text("shut"); };
}

fn step() { imgui::frame(imgui::Input { viewport: float2 { 800.0, 600.0 }, .. }, 1.0 / 60.0) { ui(); }; }
fn steps(n: i64) { for k in n { step(); } }
fn r(t: const u8[:]) -> u8[>..] {
    let q = imgui::rect_of(imgui::id(t));
    str(round(q.x), " ", round(q.y), " ", round(q.w), " ", round(q.h))
}
fn shown(text: const u8[:]) -> bool {
    for n, i in imgui::nodes { if n.kind == imgui::NODE_TEXT && imgui::node_text(i as i32) == text { return true; } }
    false
}
fn front() -> u8[>..] {
    let w = imgui::window_order[imgui::window_order.len - 1];
    str(imgui::window_state(w).title[..])
}
fn report() {
    print("  A ", if imgui::is_docked("A") { "docked " } else { "floating " }, r("A"), "; B ", r("B"));
    print("  C ", r("C"), " collapsed ", imgui::is_window_collapsed("C"), "; D ", r("D"), "; in front ", front());
    print("  left pane ", round(imgui::rect_of(imgui::sub_id(imgui::id("split"), "left")).w), "; Section open ", shown("inside"));
}

fn main() {
    imgui::dock_window("B", "main", imgui::DOCK_CENTER);
    imgui::dock_window("A", "main", imgui::DOCK_LEFT, 0.3);
    steps(3);
    // Changed from where they start, so that loading shows.
    imgui::collapse_window("C", true);
    imgui::raise_window("C");
    imgui::set_open(imgui::sub_id(imgui::sub_id(imgui::id("A"), "body"), "Section"), true);
    shut_open = false;
    steps(3);
    print("saved:");
    report();
    var text: u8[>..] = [];
    imgui::layout_json(text);
    var again: u8[>..] = [];
    imgui::layout_json(again);
    print("the same text twice: ", text[..] == again[..]);
    print(text);

    // All of it changed.
    imgui::undock_window("A");
    imgui::collapse_window("C", false);
    imgui::set_window_rect("C", gfx2d::Rect { 20.0, 500.0, 200.0, 80.0 });
    imgui::raise_window("D");
    imgui::set_open(imgui::sub_id(imgui::sub_id(imgui::id("A"), "body"), "Section"), false);
    imgui::set_pane_fraction(imgui::sub_id(imgui::id("split"), "left").v, 0.6);
    steps(3);
    print("changed:");
    report();

    let ok, err = imgui::load_layout_json(text[..]);
    print("loaded: ", ok, " ", err);
    steps(3);
    report();
    print("  Shut was open ", imgui::layout_open("Shut", true), "; one not in it ", imgui::layout_open("Nothing", true));

    // Bad layouts: refused, nothing changed.
    fn bad(t: const u8[:]) {
        let ok2, err2 = imgui::load_layout_json(t);
        print("refused ", !ok2, ": ", err2);
    }
    bad("{\"version\":1,\"windows\":[");
    bad("{\"version\":2}");
    bad("{\"version\":1,\"dock\":[{\"used\":true,\"space\":\"0000000000000001\",\"parent\":7}]}");
    bad("{\"version\":1,\"windows\":[{\"id\":\"xyz\"}]}");
    bad("{\"version\":1,\"dock\":[{\"used\":true,\"space\":\"0000000000000001\",\"parent\":-1,\"axis\":0,\"a\":0,\"b\":0}]}");
    // Trees that would abort or loop later on.
    let S = "\"space\":\"0000000000000001\"";
    fn node(rest: const u8[:]) -> u8[>..] { str("{\"used\":true,", S, ",", rest, "}") }
    fn dock(nodes: const u8[:]) -> u8[>..] { str("{\"version\":1,\"dock\":[", nodes, "]}") }
    let kid = node("\"parent\":0");
    let root = node("\"parent\":-1");
    // A leaf its parent doesn't list; a split's child that isn't used.
    bad(dock(str(node("\"parent\":-1,\"axis\":0,\"a\":1,\"b\":2"), ",", kid, ",", kid, ",", kid)));
    bad(dock(str(node("\"parent\":-1,\"axis\":0,\"a\":1,\"b\":2"), ",", kid, ",{\"used\":false}")));
    // Both sides the same child; a parent that isn't a split.
    bad(dock(str(node("\"parent\":-1,\"axis\":0,\"a\":1,\"b\":1"), ",", kid)));
    bad(dock(str(root, ",", kid)));
    // A loop, with nothing out of place but that.
    bad(dock(str(node("\"parent\":1,\"axis\":0,\"a\":1,\"b\":2"), ",",
                 node("\"parent\":0,\"axis\":0,\"a\":0,\"b\":3"), ",", kid, ",", node("\"parent\":1"))));
    // Two roots of a space; a split's ratio past its end.
    bad(dock(str(root, ",", root)));
    bad(dock(str(node("\"parent\":-1,\"axis\":0,\"ratio\":3,\"a\":1,\"b\":2"), ",", kid, ",", kid)));
    // Numbers too big for what holds them.
    bad(dock(node("\"parent\":99999999999")));
    bad(dock(node("\"parent\":-1,\"axis\":300")));
    // Tabs and windows that don't agree.
    let W = "\"id\":\"0000000000000002\"";
    bad(str("{\"version\":1,\"dock\":[", node("\"parent\":-1,\"tabs\":[\"0000000000000002\"]"), "]}"));
    bad(str("{\"version\":1,\"windows\":[{", W, ",\"dock\":0}],\"dock\":[", root, "]}"));
    bad(str("{\"version\":1,\"windows\":[{", W, ",\"dock\":0}],\"dock\":[",
            node("\"parent\":-1,\"tabs\":[\"0000000000000002\",\"0000000000000002\"]"), "]}"));
    steps(2);
    print("after them:");
    report();

    // A file.
    let path = "save_test_layout.json";
    print("saved to a file ", imgui::save_layout(path));
    imgui::undock_window("A");
    steps(2);
    print("read back ", imgui::load_layout(path), ", A docked ", imgui::is_docked("A"));
    delete_file(path);
    print("no file: ", imgui::load_layout(path));
    // A file that isn't a layout: false, as if there were none, and the
    // frames go on (misuse would abort at the end of the next one).
    if write_file(path, "{\"version\":2}") { print("not a layout: ", imgui::load_layout(path)); }
    delete_file(path);
    steps(2);
    // As a program starting: C and D not shown, D in front, the layout
    // loaded (C in front), then both shown, C recorded first: C stays in
    // front, not raised in the order they are first called.
    hide_cd = true;
    steps(3);
    imgui::raise_window("D");
    let ok3, err3 = imgui::load_layout_json(text[..]);
    hide_cd = false;
    steps(2);
    print("shown after loading: in front ", front(), " ", ok3, err3);
}
