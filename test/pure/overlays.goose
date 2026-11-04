// Tabs, menus, dropdowns, popups, modals and tooltips, driven by made-up
// input, no GPU: what opens, what is chosen, what closes, where the focus
// goes, and that a modal keeps input from what is under it.
import std;
import vec;
import math;
import gfx;
import gfx2d from "../../../goose_gfx2d";
import imgui from "../..";

var tab = 0;
var quality = 1;
var log: u8[>..] = [];
var confirm = false;
var hidden_clicks = 0;
var grid_on = false;

fn ui() {
    imgui::box(imgui::column().grow()) { ui_parts(); };
    imgui::modal("confirm", confirm) {
        imgui::text("Reset everything?");
        imgui::box(imgui::row().gap(8)) {
            if imgui::button("Yes") { log.append("reset;"); confirm = false; }
            if imgui::button("No") { confirm = false; }
        };
    };
}

fn ui_parts() {
    imgui::menu_bar("bar") {
        imgui::menu("File") {
            if imgui::menu_item("New", "Ctrl+N") { log.append("new;"); }
            imgui::menu("Recent") {
                if imgui::menu_item("level1.map") { log.append("level1;"); }
            };
            if imgui::menu_item("Quit") { log.append("quit;"); }
        };
        imgui::menu("View") {
            imgui::menu_check("Grid", grid_on);
        };
    };
    imgui::box(imgui::column().gap(10).padding(10)) {
        imgui::tabs("tabs", tab, imgui::column().width(300)) {
            imgui::tab("Video") {
                imgui::dropdown("Quality", ["Low", "Medium", "High"], quality);
            };
            imgui::tab("Audio") { imgui::text("audio settings"); };
            imgui::tab("Keys") { imgui::text("key bindings"); };
        };
        let it = imgui::box("help", imgui::row().hit()) { imgui::text("(?)"); };
        imgui::tooltip(it, "Help text");
        if imgui::button("Hidden") { hidden_clicks++; }
        if imgui::button("Reset") { confirm = true; }
    };
}

var pos = float2 { -100.0, -100.0 };

fn run_frame(p: imgui::Pointer, n: imgui::NavInput, dt: f64) {
    imgui::frame(imgui::Input { pointer: p, nav: n, viewport: float2 { 640.0, 480.0 }, .. }, dt) { ui(); };
}
fn step() { run_frame(imgui::Pointer { pos: pos, .. }, imgui::NavInput { .. }, 1.0 / 60.0); }
fn wait(seconds: f64) { for k in round(seconds * 60.0) as i64 { step(); } }
var tracing = false;
fn click_at(p: float2) {
    pos = p;
    step();
    if tracing { print("  hover: hot ", imgui::hot, " popups ", imgui::popups.len); }
    run_frame(imgui::Pointer { pos: pos, down: true, pressed: true, clicks: 1, .. }, imgui::NavInput { .. }, 1.0 / 60.0);
    if tracing { print("  press: hot ", imgui::hot, " active ", imgui::active, " popups ", imgui::popups.len); }
    run_frame(imgui::Pointer { pos: pos, released: true, .. }, imgui::NavInput { .. }, 1.0 / 60.0);
    if tracing { print("  release: clicked ", imgui::clicked_id, " popups ", imgui::popups.len); }
    step();
    if tracing { print("  after: popups ", imgui::popups.len, " closing ", imgui::closing.len); }
}
fn nav(n: imgui::NavInput) { run_frame(imgui::Pointer { pos: pos, .. }, n, 1.0 / 60.0); step(); }
fn mid(r: gfx2d::Rect) -> float2 { float2 { r.x + r.w * 0.5, r.y + r.h * 0.5 } }
fn at(i: imgui::Id) -> float2 { mid(imgui::rect_of(i)) }
// The widget showing `label`: the nearest node taking input above the
// text, in this frame's tree.
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
fn open_popups() -> i64 { imgui::popups.len }
fn texts() {
    var line: u8[>..] = [];
    for n, i in imgui::nodes {
        if n.kind == imgui::NODE_TEXT && n.root > 0 { format(line, imgui::node_text(i as i32), "|"); }
    }
    print("  popup texts: ", line);
}

fn main() {
    step();
    step();
    // Menus: a click opens File; hovering View then switches to it; a
    // click outside closes it.
    click_at(at(find("File")));
    print("file open: ", open_popups());
    texts();
    pos = at(find("View"));
    step();
    step();
    print("view open: ", open_popups());
    texts();
    click_at(float2 { 600.0, 400.0 });
    print("closed: ", open_popups());
    // A submenu, opened by hovering, and an item in it chosen.
    click_at(at(find("File")));
    pos = at(find("Recent"));
    step();
    step();
    print("submenu: ", open_popups());
    click_at(at(find("level1.map")));
    print("chose: ", log, " open: ", open_popups());
    // By the keyboard: File opened, down to Recent; right opens the
    // submenu, left closes it and leaves the focus on Recent.
    click_at(float2 { 600.0, 400.0 });
    imgui::focus(find("File"), true);
    step();
    nav(imgui::NavInput { accept: true, .. });
    nav(imgui::NavInput { down: true, .. });
    print("on Recent: ", imgui::is_focused(find("Recent")), "; open ", open_popups());
    nav(imgui::NavInput { right: true, .. });
    step();
    print("right: open ", open_popups(), "; focus in the submenu: ", imgui::is_focused(find("level1.map")));
    nav(imgui::NavInput { left: true, .. });
    print("left: open ", open_popups(), "; back on Recent: ", imgui::is_focused(find("Recent")));
    // Left again, in the bar's menu itself: the menu before it, wrapping
    // around to View; then right, past the end, back to File.
    nav(imgui::NavInput { left: true, .. });
    step();
    texts();
    print("left: open ", open_popups(), "; focus on Grid: ", imgui::is_focused(find("Grid")));
    nav(imgui::NavInput { right: true, .. });
    step();
    print("right: open ", open_popups(), "; focus on New: ", imgui::is_focused(find("New")));
    nav(imgui::NavInput { cancel: true, .. });
    click_at(at(find("View")));
    click_at(at(find("Grid")));
    print("grid: ", grid_on);

    // Tabs: clicked, then moved by the shoulder buttons.
    click_at(at(find("Audio")));
    print("tab ", tab);
    nav(imgui::NavInput { tab_right: true, .. });
    print("tab ", tab);
    nav(imgui::NavInput { tab_right: true, .. });
    print("tab ", tab);

    // A dropdown: opened, an item chosen with the pointer, then with the
    // arrows and accept.
    click_at(at(find("Medium")));
    print("dropdown open: ", open_popups());
    texts();
    click_at(at(find("High")));
    print("quality ", quality, " open: ", open_popups());
    pos = float2 { 600.0, 400.0 };
    nav(imgui::NavInput { accept: true, .. });
    print("focused the dropdown, open: ", open_popups());
    nav(imgui::NavInput { up: true, .. });
    nav(imgui::NavInput { accept: true, .. });
    print("quality ", quality, " open: ", open_popups());
    // Cancel closes the open dropdown, and the focus goes back to it.
    nav(imgui::NavInput { accept: true, .. });
    print("open: ", open_popups());
    nav(imgui::NavInput { cancel: true, .. });
    print("cancelled, open: ", open_popups(), "; focus back: ", imgui::is_focused(find("Medium")));

    // A tooltip shows after the pointer rests.
    pos = at(find("(?)"));
    step();
    texts();
    wait(0.6);
    texts();
    pos = float2 { 600.0, 400.0 };
    wait(0.3);
    texts();

    // A modal: everything under it is inert; cancel closes it.
    click_at(at(find("Reset")));
    wait(0.3);
    print("modal open: ", open_popups(), " confirm ", confirm);
    let hidden = at(find("Hidden"));
    click_at(hidden);
    print("under the modal: clicks ", hidden_clicks, "; open: ", open_popups());
    nav(imgui::NavInput { cancel: true, .. });
    print("cancelled: confirm ", confirm, " open: ", open_popups());
    click_at(at(find("Reset")));
    wait(0.3);
    click_at(at(find("Yes")));
    print("yes: ", log, " confirm ", confirm);
    click_at(hidden);
    print("after: clicks ", hidden_clicks);
}
