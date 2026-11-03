// Widgets driven by made-up input, no GPU: hover, press and click; a
// checkbox, a toggle, radios and a slider changed by the pointer; focus
// moved and widgets used by navigation; what wants_pointer says.
import std;
import vec;
import math;
import gfx;
import gfx2d from "../../../goose_gfx2d";
import imgui from "../..";

var clicks = 0;
var sound = false;
var vibrate = false;
var volume: f64 = 0.5;
var level = 0;

fn ui() {
    imgui::box(imgui::column().gap(8).padding(10)) {
        if imgui::button("Play") { clicks++; }
        imgui::checkbox("Sound", sound);
        imgui::toggle("Vibration", vibrate);
        imgui::slider("Volume", volume, 0, 1, 0.1, imgui::row().width(300));
        imgui::box(imgui::row().gap(12)) {
            imgui::radio("Easy", level, 0);
            imgui::radio("Hard", level, 1);
        };
    };
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
fn center(label: const u8[:]) -> float2 {
    let r = imgui::rect_of(imgui::id(label));
    float2 { r.x + r.w * 0.5, r.y + r.h * 0.5 }
}
// Where the first node of a class was drawn.
fn class_node(c: u16) -> gfx2d::Rect {
    for n in imgui::nodes { if n.d.vis.class.index == c { return n.screen; } }
    gfx2d::Rect { 0.0, 0.0, 0.0, 0.0 }
}
fn focused(label: const u8[:]) -> bool { imgui::is_focused(imgui::id(label)) }
fn show_focus() {
    for l in ["Play", "Sound", "Vibration", "Easy", "Hard"] {
        if focused(l) { print("focused: ", l); }
    }
    if imgui::is_focused(imgui::sub_id(imgui::id("Volume"), "track")) { print("focused: the volume slider"); }
}

fn main() {
    step();
    step();
    let play = imgui::rect_of(imgui::id("Play"));
    print("play: ", round(play.x), " ", round(play.y), " ", round(play.w), " ", round(play.h));
    print("over nothing, wants pointer: ", imgui::wants_pointer());

    // Hover, then a click: down on it, up on it.
    pos = center("Play");
    step();
    print("over play, wants pointer: ", imgui::wants_pointer());
    press();
    print("pressed: clicks ", clicks);
    release();
    print("released: clicks ", clicks);
    // Down on it, up elsewhere: no click.
    press();
    pos = float2 { 600.0, 400.0 };
    step();
    release();
    print("dragged off: clicks ", clicks);

    // A checkbox and a toggle, clicked anywhere on their row.
    pos = center("Sound");
    press();
    release();
    print("sound ", sound);
    pos = center("Vibration");
    press();
    release();
    press();
    release();
    print("vibration ", vibrate);

    // A part of a widget with a look of its own hits as the widget: the
    // toggle's track, not only its label.
    let track = class_node(imgui::TOGGLE.index);
    pos = float2 { track.x + track.w * 0.5, track.y + track.h * 0.5 };
    press();
    release();
    print("vibration, by its track: ", vibrate);

    // The slider: pressed at its left end, dragged to 70%, snapped to 0.1.
    let tr = imgui::rect_of(imgui::sub_id(imgui::id("Volume"), "track"));
    pos = float2 { tr.x + 2.0, tr.y + tr.h * 0.5 };
    press();
    print("volume at the left: ", volume);
    pos = float2 { tr.x + tr.w * 0.7, tr.y + tr.h * 0.5 };
    step();
    release();
    print("volume dragged: ", round(volume * 10.0) / 10.0);

    // Dragged by its thumb: pressed on it (at 70%), moved to 30%.
    let thumb = class_node(imgui::SLIDER_THUMB.index);
    pos = float2 { thumb.x + thumb.w * 0.5, thumb.y + thumb.h * 0.5 };
    press();
    pos = float2 { tr.x + tr.w * 0.3, tr.y + tr.h * 0.5 };
    step();
    release();
    print("volume dragged by the thumb: ", round(volume * 10.0) / 10.0);

    // Radios.
    pos = center("Hard");
    press();
    release();
    print("level ", level);

    // Navigation: down from nothing focuses the first; the directions move
    // to the nearest widget that way (up from Easy: the toggle above it, not
    // the slider off to the right); right on the slider changes it; accept
    // presses; Shift+Tab goes back in order.
    pos = float2 { 600.0, 400.0 };
    press();
    release();
    show_focus();
    nav(imgui::NavInput { down: true, .. });
    show_focus();
    nav(imgui::NavInput { down: true, .. });
    nav(imgui::NavInput { down: true, .. });
    nav(imgui::NavInput { down: true, .. });
    show_focus();
    nav(imgui::NavInput { right: true, .. });
    nav(imgui::NavInput { right: true, .. });
    print("volume by nav: ", round(volume * 10.0) / 10.0);
    show_focus();
    nav(imgui::NavInput { down: true, .. });
    show_focus();
    nav(imgui::NavInput { left: true, .. });
    show_focus();
    nav(imgui::NavInput { accept: true, .. });
    print("level ", level);
    nav(imgui::NavInput { up: true, .. });
    nav(imgui::NavInput { up: true, .. });
    show_focus();
    nav(imgui::NavInput { accept: true, .. });
    print("sound ", sound, ", vibration ", vibrate);
    nav(imgui::NavInput { prev: true, .. });
    show_focus();
    nav(imgui::NavInput { accept: true, .. });
    print("clicks ", clicks);
    // The pointer pressing elsewhere takes the focus away.
    pos = float2 { 600.0, 400.0 };
    press();
    release();
    show_focus();
    print("cancelled: ", imgui::cancelled());
    nav(imgui::NavInput { cancel: true, .. });
    print("cancelled: ", imgui::cancelled());
}
