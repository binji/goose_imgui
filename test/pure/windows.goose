// Windows, driven by made-up input, no GPU: where they start, moved by
// their titles and kept on the screen, resized by their edges and corners
// (and no smaller than they can be), raised by a press, collapsed and
// opened, closed and opened again in front; a press over two windows
// reaching only the front one; a context menu on a right click.
import std;
import vec;
import math;
import gfx;
import gfx2d from "../../../goose_gfx2d";
import imgui from "../..";

var log: u8[>..] = [];
var show_log = true;
var chosen = 0;

fn ui() {
    imgui::text("main");
    imgui::window("Tools", imgui::column().size(200, 150).absolute(20, 20)) {
        if imgui::button("Under") { log.append("under;"); }
        for name, k in ["alpha", "beta"] {
            if imgui::selectable(name, chosen == k) { chosen = k; }
            imgui::context_menu(imgui::last_item()) {
                if imgui::menu_item("Rename") { format(log, "rename ", k, ";"); }
                if imgui::menu_item("Delete") { format(log, "delete ", k, ";"); }
            };
        }
    };
    imgui::window("Log", show_log, imgui::column().size(220, 160).absolute(60, 50)) {
        imgui::text("line one");
        if imgui::button("Clear") { log.append("clear;"); }
    };
    imgui::window("Info") { imgui::text("fits its text"); };
}

var pos = float2 { -100.0, -100.0 };

fn run_frame(p: imgui::Pointer) {
    imgui::frame(imgui::Input { pointer: p, viewport: float2 { 640.0, 480.0 }, .. }, 1.0 / 60.0) { ui(); };
}
fn step() { run_frame(imgui::Pointer { pos: pos, .. }); }
fn press(p: float2, clicks: i32 = 1) {
    pos = p;
    step();
    run_frame(imgui::Pointer { pos: pos, down: true, pressed: true, clicks: clicks, .. });
}
fn release() { run_frame(imgui::Pointer { pos: pos, released: true, .. }); step(); }
fn click_at(p: float2, clicks: i32 = 1) { press(p, clicks); release(); }
fn right_click_at(p: float2) {
    pos = p;
    step();
    run_frame(imgui::Pointer { pos: pos, secondary: true, .. });
    step();
}
// A drag from p by d, in a few moves.
fn drag(p: float2, d: float2) {
    press(p);
    for k in 1..5 {
        pos = p + d * (k as f32 / 4.0);
        run_frame(imgui::Pointer { pos: pos, down: true, .. });
    }
    release();
}
fn mid(r: gfx2d::Rect) -> float2 { float2 { r.x + r.w * 0.5, r.y + r.h * 0.5 } }
fn show(name: const u8[:]) {
    let r = imgui::window_rect(name);
    print("  ", name, ": ", round(r.x), " ", round(r.y), " ", round(r.w), " ", round(r.h),
          if imgui::is_window_collapsed(name) { " collapsed" } else { "" });
}
fn order() {
    var line: u8[>..] = [];
    for k in imgui::root_order {
        let r = imgui::roots[k as i64];
        if r.kind == imgui::ROOT_WINDOW {
            let n = imgui::nodes[r.node];
            // The title's text: the window's name.
            for m, i in imgui::nodes {
                if m.root == n.root && m.kind == imgui::NODE_TEXT {
                    format(line, imgui::node_text(i as i32), " ");
                    break;
                }
            }
        }
    }
    print("  back to front: ", line);
}
fn find(label: const u8[:]) -> imgui::Id {
    for n, i in imgui::nodes {
        if n.kind == imgui::NODE_TEXT && imgui::node_text(i as i32) == label {
            var p = n.parent;
            while p >= 0 && imgui::nodes[p].d.bits & imgui::HIT == 0 { p = imgui::nodes[p].parent; }
            if p >= 0 { return imgui::Id { imgui::nodes[p].id }; }
        }
    }
    print("no widget shows ", label);
    imgui::Id { 0 }
}
fn at(label: const u8[:]) -> float2 { mid(imgui::rect_of(find(label))) }
fn title_of(name: const u8[:]) -> float2 {
    let r = imgui::window_rect(name);
    float2 { r.x + r.w * 0.5, r.y + 8.0 }
}
fn shown(label: const u8[:]) -> bool {
    for n, i in imgui::nodes { if n.kind == imgui::NODE_TEXT && imgui::node_text(i as i32) == label { return true; } }
    false
}

fn main() {
    step();
    step();
    print("start:");
    show("Tools");
    show("Log");
    show("Info");
    order();

    // Tools's button is under Log: a press there reaches Log, which comes
    // to the front anyway; on Tools's own part, Tools comes to the front.
    let under = at("Under");
    print("under at ", round(under.x), " ", round(under.y), ", in log: ",
          imgui::inside(imgui::window_rect("Log"), under));
    click_at(under);
    print("pressed over Under: log \"", log, "\"");
    order();
    click_at(float2 { 40.0, 140.0 });
    print("pressed Tools:");
    order();
    print("  front: ", imgui::front_window == imgui::id("Tools").v, "; wants pointer: ", imgui::wants_pointer());
    click_at(under);
    print("  now Under is in front: log \"", log, "\"");
    log.clear();

    // Moved by the title, and kept on the screen.
    drag(title_of("Tools"), float2 { 60.0, 40.0 });
    print("moved:");
    show("Tools");
    drag(title_of("Tools"), float2 { 900.0, 900.0 });
    print("dragged off the screen:");
    show("Tools");
    drag(title_of("Tools"), float2 { -900.0, -900.0 });
    show("Tools");

    // Resized: the bottom right corner out; the left edge out, the right
    // edge staying; the corner in, past the least size.
    let lr = imgui::window_rect("Log");
    pos = float2 { lr.x + lr.w - 1.0, lr.y + lr.h - 1.0 };
    step();
    print("grip cursor: ", imgui::cursor() == imgui::CURSOR_NWSE_RESIZE);
    drag(float2 { lr.x + lr.w - 1.0, lr.y + lr.h - 1.0 }, float2 { 40.0, 20.0 });
    print("resized:");
    show("Log");
    let lr2 = imgui::window_rect("Log");
    drag(float2 { lr2.x, lr2.y + lr2.h * 0.5 }, float2 { -30.0, 0.0 });
    show("Log");
    let lr3 = imgui::window_rect("Log");
    drag(float2 { lr3.x + lr3.w - 1.0, lr3.y + lr3.h - 1.0 }, float2 { -400.0, -400.0 });
    print("as small as it goes:");
    show("Log");
    let lr4 = imgui::window_rect("Log");
    drag(float2 { lr4.x + lr4.w - 1.0, lr4.y + lr4.h - 1.0 }, float2 { 150.0, 100.0 });
    show("Log");

    // Collapsed by its arrow: its title bar only, its content not recorded;
    // opened by a double click on its title.
    let arrow = imgui::rect_of(imgui::sub_id(imgui::id("Log"), "collapse"));
    click_at(mid(arrow));
    print("collapsed:");
    show("Log");
    print("  clear shown: ", shown("Clear"));
    click_at(title_of("Log"), 2);
    print("opened:");
    show("Log");
    print("  clear shown: ", shown("Clear"));

    // Closed, then opened again: where it was, in front.
    click_at(float2 { 10.0, 140.0 });
    order();
    click_at(mid(imgui::rect_of(imgui::sub_id(imgui::id("Log"), "close"))));
    print("closed: ", !show_log, "; log shown: ", shown("line one"));
    order();
    show_log = true;
    step();
    step();
    print("opened again:");
    show("Log");
    order();

    // The button in the Log window.
    click_at(at("Clear"));
    print("log: ", log);

    // A context menu: a right click on a row opens it at the pointer; an
    // item chosen closes it; a right click elsewhere closes it too.
    click_at(title_of("Tools"));
    let beta = at("beta");
    right_click_at(beta);
    print("menu open: ", imgui::popups.len, " rename at ", imgui::rect_of(find("Rename")).x >= beta.x);
    click_at(at("Delete"));
    print("chose: ", log, " open: ", imgui::popups.len);
    right_click_at(at("alpha"));
    print("menu open: ", imgui::popups.len);
    right_click_at(float2 { 600.0, 20.0 });
    print("right click outside: ", imgui::popups.len);
    // Drawn over the windows it was opened from.
    right_click_at(at("alpha"));
    let last = imgui::roots[imgui::root_order[imgui::root_order.len - 1] as i64];
    print("menu drawn last: ", last.kind == imgui::ROOT_POPUP);
}
