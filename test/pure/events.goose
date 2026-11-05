// UI events for sounds, no GPU: a hover as the pointer moves onto a
// widget, once, and none for a widget that comes under a still pointer;
// a press and an activation; a denial on a disabled button; focus shown
// by navigation, not by a click; a slider's ticks, by its steps and by
// twentieths without; tabs switched by the shoulders; a popup opened and
// closed, by cancel and by a press outside; back, with nothing to close;
// a program's own event; nothing in a frame where nothing happens.
import std;
import vec;
import math;
import gfx;
import gfx2d from "../../../goose_gfx2d";
import imgui from "../..";

var volume: f64 = 0.5;
var steps: f64 = 0.0;
var sound = false;
var tab = 0;
var swapped = false;

fn ui() {
    imgui::box(imgui::column().gap(8).padding(10)) {
        if imgui::button("Options") { imgui::open_popup_below(imgui::id("options")); }
        imgui::button(if swapped { "Swap B" } else { "Swap A" });
        imgui::button("Locked", imgui::row().disabled(true));
        imgui::checkbox("Sound", sound);
        imgui::slider("Volume", volume, 0, 1, 0.0, imgui::row().width(300));
        imgui::slider("Steps", steps, 0, 1, 0.25, imgui::row().width(300));
        imgui::tabs("tabs", tab) {
            imgui::tab("One") { imgui::text("one"); };
            imgui::tab("Two") { imgui::text("two"); };
        };
    };
    imgui::popup("options") { imgui::button("Inside"); };
}

var pos = float2 { -100.0, -100.0 };
var down = false;

fn frame_with(p: imgui::Pointer, nav: imgui::NavInput) {
    imgui::frame(imgui::Input { pointer: p, nav: nav, viewport: float2 { 640.0, 480.0 }, .. }, 1.0 / 60.0) { ui(); };
}
fn step() { frame_with(imgui::Pointer { pos: pos, down: down, .. }, imgui::NavInput { .. }); }
fn press() {
    down = true;
    frame_with(imgui::Pointer { pos: pos, down: true, pressed: true, clicks: 1, .. }, imgui::NavInput { .. });
}
fn release() {
    down = false;
    frame_with(imgui::Pointer { pos: pos, released: true, .. }, imgui::NavInput { .. });
}
fn nav(n: imgui::NavInput) { frame_with(imgui::Pointer { pos: pos, .. }, n); }
fn center(i: imgui::Id) -> float2 {
    let r = imgui::rect_of(i);
    float2 { r.x + r.w * 0.5, r.y + r.h * 0.5 }
}
fn center(label: const u8[:]) -> float2 { center(imgui::id(label)) }

fn who(id: u64) -> u8[>..] {
    for l in ["Options", "Swap A", "Swap B", "Locked", "Sound", "One", "Two", "Inside", "options", "tabs"] {
        if imgui::id(l).v == id { return str(l); }
    }
    for l in ["Volume", "Steps"] { if imgui::sub_id(imgui::id(l), "track").v == id { return str(l); } }
    if id == 0 { str("-") } else { str("?") }
}
fn class_name(c: imgui::StyleClass) -> const u8[:] {
    if c == imgui::BUTTON { "BUTTON" } else if c == imgui::CHOICE { "CHOICE" }
    else if c == imgui::SLIDER_THUMB { "SLIDER_THUMB" } else if c == imgui::TAB { "TAB" }
    else if c == imgui::POPUP { "POPUP" } else if c == imgui::NONE { "NONE" } else { "other" }
}
fn show(what: const u8[:]) {
    var line: u8[>..] = [];
    for e in imgui::ui_events() {
        if line.len > 0 { line.append(", "); }
        format(line, imgui::ui_event_name(e.kind), " ", who(e.id), " ", class_name(e.class));
    }
    if line.len == 0 { line.append("none"); }
    print(what, ": ", line);
}

fn main() {
    step();
    step();
    show("nothing happening");

    pos = center("Options");
    step();
    show("onto Options");
    step();
    show("still on it");
    pos.x += 3.0;
    step();
    show("moved on it");
    press();
    show("press");
    release();
    show("release");
    step();
    show("next frame");

    // Outside it: the popup closes.
    pos = float2 { 600.0, 460.0 };
    press();
    show("press outside");
    release();

    // A button that comes under a still pointer: no hover.
    pos = center("Swap A");
    step();
    show("onto Swap A");
    swapped = true;
    step();
    step();
    show("Swap B under the still pointer");

    pos = center("Locked");
    step();
    show("onto Locked");
    press();
    show("press on Locked");
    release();

    // A click focuses quietly; navigation shows it.
    pos = center("Sound");
    step();
    press();
    release();
    show("Sound clicked");
    nav(imgui::NavInput { down: true, .. });
    show("down");
    nav(imgui::NavInput { .. });
    show("then nothing");

    // Ticks: Volume (no step) a tick a twentieth; Steps a tick a step.
    nav(imgui::NavInput { right: true, .. });
    show("right on Volume");
    let vt = imgui::rect_of(imgui::sub_id(imgui::id("Volume"), "track"));
    pos = float2 { vt.x + vt.w * 0.5, vt.y + vt.h * 0.5 };
    step();
    press();
    var ticks = 0;
    for k in 30 {
        pos.x += 3.0;
        step();
        for e in imgui::ui_events() { if e.kind == imgui::UI_CHANGE { ticks++; } }
    }
    release();
    print("Volume dragged 90 px (", round(vt.w), " wide): ", ticks, " ticks, now ", round(volume * 100.0) / 100.0);
    nav(imgui::NavInput { down: true, .. });
    nav(imgui::NavInput { right: true, .. });
    show("right on Steps");
    nav(imgui::NavInput { right: true, .. });
    show("right on Steps again");

    nav(imgui::NavInput { tab_right: true, .. });
    show("shoulder right");
    nav(imgui::NavInput { tab_right: true, .. });
    show("shoulder right, back to One");

    // Cancel: closes the popup; with none open, back.
    imgui::open_popup(imgui::id("options"));
    step();
    show("opened by the program");
    nav(imgui::NavInput { cancel: true, .. });
    show("cancel");
    nav(imgui::NavInput { cancel: true, .. });
    show("cancel again");

    imgui::ui_event(77, imgui::id("Sound"), imgui::CHOICE);
    step();
    show("the program's own");
    step();
    show("and nothing");
}
