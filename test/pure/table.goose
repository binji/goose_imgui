// Long lists and tables, driven by made-up input, no GPU: of 1,000 rows only
// those in view recorded, as the pane scrolls by the wheel and to its end;
// rows selected by a click, Ctrl and Shift; a table's columns sharing its
// width, one resized by its edge, the rest sharing what is left; sorting by
// a header, and the other way; a row clicked, selected and shown so.
import std;
import vec;
import math;
import gfx;
import gfx2d from "../../../goose_gfx2d";
import imgui from "../..";

var picked: bool[>..] = [];
var info = imgui::TableInfo { .. };
var names = ["ant", "bee", "cat", "dog", "eel", "fox", "gnu", "hen", "ibis", "jay"];
var order: i64[10] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];

fn ui() {
    imgui::box(imgui::row().gap(10).padding(10)) {
        imgui::scroll("long", imgui::column().size(200, 200)) {
            imgui::row_list("lines", 1000, 20) { k => imgui::textf(imgui::column()) { out => format(out, "line ", k); }; };
        };
        info = imgui::table("animals", ["Name", "Legs", "Notes"], 10, picked, imgui::Table { .. },
                            imgui::column().size(360, 200)) { k, c =>
            let a = order[k];
            if c == 0 { imgui::text(names[a]); }
            else if c == 1 { imgui::textf(imgui::column()) { out => format(out, a % 3 * 2); }; }
            else { imgui::text("..."); }
        };
        if info.clicked >= 0 { imgui::select_row("animals", picked, info.clicked); }
        if info.sorted {
            // By name, descending or not.
            for k in 10 { order[k] = if info.descending { 9 - k } else { k }; }
        }
    };
}

var at = float2 { -100.0, -100.0 };
var mods: u8 = 0;
fn run_frame(p: imgui::Pointer) {
    imgui::frame(imgui::Input { pointer: p, mods: mods, viewport: float2 { 640.0, 480.0 }, .. }, 1.0 / 60.0) { ui(); };
}
fn step() { run_frame(imgui::Pointer { pos: at, .. }); }
fn click_at(p: float2) {
    at = p;
    step();
    run_frame(imgui::Pointer { pos: at, down: true, pressed: true, clicks: 1, .. });
    run_frame(imgui::Pointer { pos: at, released: true, .. });
    step();
}
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
fn text_rect(s: const u8[:]) -> gfx2d::Rect {
    for n, i in imgui::nodes { if n.kind == imgui::NODE_TEXT && imgui::node_text(i as i32) == s { return n.rect; } }
    gfx2d::Rect { 0.0, 0.0, 0.0, 0.0 }
}
// The lines recorded: how many, the first and the last.
fn lines() {
    var count = 0;
    var lo = 100000;
    var hi = -1;
    for n, i in imgui::nodes {
        if n.kind != imgui::NODE_TEXT { continue; }
        let t = imgui::node_text(i as i32);
        if t.len > 5 && t[..5] == "line " {
            let v, ok = parse_int(t[5..]);
            if ok { count++; lo = min(lo, v); hi = max(hi, v); }
        }
    }
    print("  ", count, " lines recorded, ", lo, " to ", hi, "; content ",
          imgui::state_of(imgui::id("long").v).content.y);
}
// The name in the table's top row.
fn top_name() -> const u8[:] {
    var best = 1.0e9;
    var name: const u8[:] = "";
    for nm in names { let r = text_rect(nm); if r.w > 0.0 && r.y < best { best = r.y; name = nm; } }
    name
}
fn picks() -> u8[>..] {
    var t: u8[>..] = [];
    for p, k in picked { if p { format(t, k, " "); } }
    t
}
fn widths() -> u8[>..] {
    var t: u8[>..] = [];
    for c in 3 { format(t, round(imgui::rect_of(imgui::sub_id(imgui::id("animals"), c)).w), " "); }
    t
}

fn main() {
    for k in 10 { picked.push(false); }
    step();
    step();
    print("at the top:");
    lines();
    // The wheel: 10 lines' worth, eased; then to the end.
    at = mid(imgui::rect_of(imgui::id("long")));
    run_frame(imgui::Pointer { pos: at, wheel: float2 { 0.0, -5.0 }, .. });
    for k in 30 { step(); }
    print("scrolled by the wheel: ", imgui::state_of(imgui::id("long").v).scroll.y);
    lines();
    imgui::scroll_to("long", float2 { 0.0, 1.0e9 });
    for k in 60 { step(); }
    print("at the end: ", imgui::state_of(imgui::id("long").v).scroll.y);
    lines();

    // The table: three columns sharing its width.
    print("widths: ", widths());
    let edge = imgui::rect_of(imgui::sub_id(imgui::id("animals"), 0));
    drag(float2 { edge.x + edge.w - 2.0, edge.y + edge.h * 0.5 }, float2 { 40.0, 0.0 });
    print("the first dragged 40 wider: ", widths());
    print("cursor on an edge: ", imgui::cursor() == imgui::CURSOR_EW_RESIZE);

    // Sorting: Name, then Name the other way.
    click_at(mid(text_rect("Name")));
    print("sorted: by ", info.sort, ", descending ", info.descending, "; top row ", top_name());
    click_at(mid(text_rect("Name")));
    print("again: by ", info.sort, ", descending ", info.descending, "; top row ", top_name());
    click_at(mid(text_rect("Legs")));
    print("legs: by ", info.sort, ", descending ", info.descending);

    // Selecting rows: a click; Ctrl+click another; Shift+click a range.
    click_at(mid(text_rect("cat")));
    print("clicked cat: ", picks());
    mods = imgui::MOD_CTRL;
    click_at(mid(text_rect("fox")));
    print("ctrl fox: ", picks());
    click_at(mid(text_rect("cat")));
    print("ctrl cat again: ", picks());
    mods = imgui::MOD_SHIFT;
    click_at(mid(text_rect("bee")));
    print("shift bee (from cat, the anchor): ", picks());
    mods = 0;
    click_at(mid(text_rect("eel")));
    print("eel alone: ", picks());
    // A selected row looks it (once the others have eased out of it).
    for k in 20 { step(); }
    var checked = 0;
    for n in imgui::nodes {
        if n.d.vis.class.index == imgui::TABLE_ROW.index || n.d.vis.class.index == imgui::TABLE_ROW_ALT.index {
            if n.d.vis.state.checked > 0.5 { checked++; }
        }
    }
    print("rows shown selected: ", checked);
}
