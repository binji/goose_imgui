// Developers' widgets, driven by made-up input, no GPU: property rows lined
// up; a collapsing header; a tree opened and closed by its arrow, a double
// click and the keys, its open nodes kept while hidden; number fields
// dragged (finer with Shift), clamped, stepped by the keys and buttons,
// typed in (Enter keeps, Escape doesn't, a click elsewhere keeps); a
// vector's parts.
import std;
import vec;
import math;
import gfx;
import gfx2d from "../../../goose_gfx2d";
import imgui from "../..";

var speed: f64 = 1.0;
var count: i64 = 5;
var pos = float3 { 1.0, 2.0, 3.0 };
var lives: i64 = 3;
var chosen = -1;
var other: f64 = 0.0;

fn ui() {
    imgui::box(imgui::column().gap(6).padding(10).width(400)) {
        imgui::collapsing("Settings", imgui::column(), true) {
            imgui::properties() {
                imgui::property("Speed") { imgui::drag_number("", speed, imgui::Drag { lo: 0, hi: 10, decimals: 2 }); };
                imgui::property("Entity count") { imgui::drag_number("", count, imgui::Drag { lo: 0, hi: 100 }); };
                imgui::property("Position") { imgui::drag_vec("", pos); };
                imgui::property("Lives") { imgui::input_number("", lives, imgui::Drag { lo: 0, hi: 5 }); };
            };
        };
        imgui::collapsing("Hidden") {
            imgui::text("secret");
            imgui::properties() { imgui::property("A") { imgui::drag_number("", other); }; };
        };
        let w = imgui::tree_node("World", chosen == 0, true) {
            let p = imgui::tree_node("Player", chosen == 1) {
                imgui::tree_leaf("Sword", chosen == 2);
                imgui::tree_leaf("Shield", chosen == 3);
            };
            if p.activated { chosen = 1; }
            imgui::tree_leaf("Camera", chosen == 4);
        };
        if w.activated { chosen = 0; }
    };
}

var at = float2 { -100.0, -100.0 };
var mods: u8 = 0;

fn run_frame(p: imgui::Pointer, n: imgui::NavInput) {
    imgui::frame(imgui::Input { pointer: p, nav: n, mods: mods, viewport: float2 { 640.0, 640.0 }, .. }, 1.0 / 60.0) { ui(); };
}
fn step() { run_frame(imgui::Pointer { pos: at, .. }, imgui::NavInput { .. }); }
fn click_at(p: float2, clicks: i32 = 1) {
    at = p;
    step();
    run_frame(imgui::Pointer { pos: at, down: true, pressed: true, clicks: clicks, .. }, imgui::NavInput { .. });
    run_frame(imgui::Pointer { pos: at, released: true, .. }, imgui::NavInput { .. });
    step();
}
fn drag(p: float2, d: float2) {
    at = p;
    step();
    run_frame(imgui::Pointer { pos: at, down: true, pressed: true, clicks: 1, .. }, imgui::NavInput { .. });
    for k in 1..5 {
        at = p + d * (k as f32 / 4.0);
        run_frame(imgui::Pointer { pos: at, down: true, .. }, imgui::NavInput { .. });
    }
    run_frame(imgui::Pointer { pos: at, released: true, .. }, imgui::NavInput { .. });
    step();
}
fn nav(n: imgui::NavInput) { run_frame(imgui::Pointer { pos: at, .. }, n); step(); }
fn type_text(s: const u8[:], enter: bool) {
    var inp = imgui::Input { pointer: imgui::Pointer { pos: at, .. }, viewport: float2 { 640.0, 640.0 }, .. };
    for c in s { inp.text.push(c); }
    imgui::frame(inp, 1.0 / 60.0) { ui(); };
    if enter {
        var e = imgui::Input { pointer: imgui::Pointer { pos: at, .. }, viewport: float2 { 640.0, 640.0 }, .. };
        e.keys.push(imgui::EditKey { key: imgui::KEY_ENTER as u8, .. });
        e.nav.accept = true;
        imgui::frame(e, 1.0 / 60.0) { ui(); };
    }
    step();
}
fn mid(r: gfx2d::Rect) -> float2 { float2 { r.x + r.w * 0.5, r.y + r.h * 0.5 } }
// The widget showing `label`: the nearest node taking input above the text.
fn find(label: const u8[:]) -> imgui::Id {
    for n, i in imgui::nodes {
        if n.kind == imgui::NODE_TEXT && imgui::node_text(i as i32) == label {
            var p = n.parent;
            while p >= 0 && imgui::nodes[p].d.bits & imgui::HIT == 0 { p = imgui::nodes[p].parent; }
            if p >= 0 { return imgui::Id { imgui::nodes[p].id }; }
        }
    }
    imgui::Id { 0 }
}
fn shown(label: const u8[:]) -> bool { find(label).v != 0 || text_rect(label).w > 0.0 }
fn text_rect(label: const u8[:]) -> gfx2d::Rect {
    for n, i in imgui::nodes {
        if n.kind == imgui::NODE_TEXT && imgui::node_text(i as i32) == label { return n.rect; }
    }
    gfx2d::Rect { 0.0, 0.0, 0.0, 0.0 }
}
fn at_text(label: const u8[:]) -> float2 { mid(text_rect(label)) }
// The rect of the n-th node of NUMBER's class.
fn field(n: i64) -> gfx2d::Rect {
    var k = 0;
    for nd in imgui::nodes {
        if nd.d.vis.class.index == imgui::NUMBER.index {
            if k == n { return nd.rect; }
            k++;
        }
    }
    gfx2d::Rect { 0.0, 0.0, 0.0, 0.0 }
}
fn values() {
    print("  speed ", speed, ", count ", count, ", pos ", pos.x, " ", pos.y, " ", pos.z, ", lives ", lives);
}

fn main() {
    step();
    step();
    // Property rows: the labels in one column as wide as the widest, the
    // widgets after it, lined up.
    print("labels start at ", round(text_rect("Speed").x), " ", round(text_rect("Lives").x), "; widgets at ",
          round(field(0).x), " ", round(field(1).x), ", past the widest label: ", field(0).x > text_rect("Entity count").x + text_rect("Entity count").w);
    print("fields show: ", shown("1.00"), " ", shown("5"), " ", shown("3"));

    // A collapsing header: open at first, or closed; a click opens it.
    print("hidden shown: ", shown("secret"));
    click_at(at_text("Hidden"));
    print("clicked: ", shown("secret"), "; its short label's widget lined up with the others: ",
          round(field(6).x) == round(field(0).x));
    click_at(at_text("Hidden"));
    print("clicked again: ", shown("secret"));

    // Dragging: 50 pixels right at a 20th of the range (10 / 200) is 2.5;
    // with Shift, a tenth of that; past the end, clamped.
    drag(mid(field(0)), float2 { 50.0, 0.0 });
    values();
    mods = imgui::MOD_SHIFT;
    drag(mid(field(0)), float2 { 50.0, 0.0 });
    mods = 0;
    values();
    drag(mid(field(0)), float2 { 900.0, 0.0 });
    values();
    // Whole numbers: 0.5 a pixel (100 / 200), rounded.
    drag(mid(field(1)), float2 { -9.0, 0.0 });
    values();
    print("cursor over a field: ", imgui::cursor() == imgui::CURSOR_EW_RESIZE);

    // The keys: focused, Right steps it.
    imgui::focus(find(str(count)), true);
    step();
    nav(imgui::NavInput { right: true, .. });
    nav(imgui::NavInput { right: true, .. });
    values();

    // Typing: a click without a drag; Enter keeps it, clamped.
    click_at(mid(field(0)));
    print("editing: ", imgui::number_editing != 0, ", text \"", imgui::number_text[..], "\"");
    type_text("4.5", true);
    print("typed 4.5: editing ", imgui::number_editing != 0);
    values();
    click_at(mid(field(0)));
    type_text("7.256", false);
    nav(imgui::NavInput { cancel: true, .. });
    print("escaped: editing ", imgui::number_editing != 0);
    values();
    click_at(mid(field(0)));
    type_text("3.333", false);
    click_at(float2 { 600.0, 600.0 });
    print("clicked away: editing ", imgui::number_editing != 0);
    values();

    // A vector: its Y dragged, the others kept; tagged X Y Z.
    drag(mid(field(3)), float2 { 20.0, 0.0 });
    values();
    print("tags: ", shown("X"), " ", shown("Y"), " ", shown("Z"), " ", shown("W"));

    // Stepped by its buttons, within its range.
    let lr = field(5);
    let plus = float2 { lr.x + lr.w + 14.0, lr.y + lr.h * 0.5 };
    click_at(plus);
    click_at(plus);
    click_at(plus);
    values();

    // The tree: World open at first, Player closed; its arrow opens it; a
    // double click on its row closes it; a click selects.
    print("tree: world ", shown("World"), ", player ", shown("Player"), ", sword ", shown("Sword"));
    click_at(mid(imgui::rect_of(imgui::sub_id(find("Player"), "arrow"))));
    print("arrow: sword ", shown("Sword"), ", chosen ", chosen);
    print("  indented: ", text_rect("Sword").x > text_rect("Player").x, ", leaf lined up with a node: ",
          text_rect("Camera").x == text_rect("Player").x);
    click_at(at_text("Player"), 2);
    print("double click: sword ", shown("Sword"), ", chosen ", chosen);
    // The keys: Right opens, Left closes, Left again goes up to World.
    imgui::focus(find("Player"), true);
    step();
    nav(imgui::NavInput { right: true, .. });
    print("right: sword ", shown("Sword"));
    nav(imgui::NavInput { left: true, .. });
    print("left: sword ", shown("Sword"));
    nav(imgui::NavInput { left: true, .. });
    print("left again: on world ", imgui::is_focused(find("World")));
    // Open Player, close World for a long while: Player stays open inside.
    nav(imgui::NavInput { right: true, .. });
    click_at(mid(imgui::rect_of(imgui::sub_id(find("Player"), "arrow"))));
    click_at(mid(imgui::rect_of(imgui::sub_id(find("World"), "arrow"))));
    print("world closed: player ", shown("Player"));
    for k in 200 { step(); }
    click_at(mid(imgui::rect_of(imgui::sub_id(find("World"), "arrow"))));
    print("opened after 200 frames: sword ", shown("Sword"));
}
