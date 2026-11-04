// Widgets driven by made-up input, no GPU: hover, press and click; a
// checkbox, a toggle, radios and a slider changed by the pointer; focus
// moved and widgets used by navigation; what wants_pointer says, and
// what it says over a passthrough panel; a turned box hit where it is
// drawn; the focus cursor.
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
    // The thumb shows the slider's focus: its ring is drawn.
    for n in imgui::nodes { if n.d.vis.class.index == imgui::SLIDER_THUMB.index { print("thumb ringed: ", n.ring); } }
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

    // Shortcuts: Ctrl+Q pressed, as a chord in the input.
    var inp = imgui::Input { viewport: float2 { 640.0, 480.0 }, .. };
    inp.chords.push(imgui::Chord { 'q', imgui::MOD_CTRL });
    imgui::frame(inp, 1.0 / 60.0) {
        print("Ctrl+Q ", imgui::shortcut("Ctrl+Q"), ", Ctrl+Shift+Q ", imgui::shortcut("Ctrl+Shift+Q"),
              ", Ctrl+W ", imgui::shortcut("Ctrl+W"));
        ui();
    };

    // A HUD panel with a background takes the pointer, unless it is
    // passthrough; a button in a passthrough panel still takes it.
    fn hud(pass: bool, p: float2) {
        var d = imgui::column().size(200, 100).bg(gfx2d::rgb(0x202020)).padding(10).place(imgui::END, imgui::END);
        if pass { d = d.passthrough(); }
        for k in 2 {
            imgui::frame(imgui::Input { pointer: imgui::Pointer { pos: p, .. }, viewport: float2 { 640.0, 480.0 }, .. },
                         1.0 / 60.0) {
                imgui::box("hud", d) { imgui::button("Use"); };
            };
        }
    }
    for pass in [false, true] {
        hud(pass, float2 { 620.0, 470.0 });
        let on_panel = imgui::wants_pointer();
        hud(pass, float2 { 460.0, 400.0 });       // just inside the button, at the padding
        print("hud panel", if pass { ", passthrough" } else { "" }, ": over its background, wants pointer ",
              on_panel, "; over its button ", imgui::wants_pointer());
    }

    // A card turned an eighth (down to the right) is hit where it is
    // drawn, and not elsewhere in the box around it.
    fn card(p: float2) -> bool {
        var it = imgui::Interaction { .. };
        for k in 2 {
            imgui::frame(imgui::Input { pointer: imgui::Pointer { pos: p, .. }, viewport: float2 { 640.0, 480.0 }, .. },
                         1.0 / 60.0) {
                it = imgui::box("card", imgui::clickable(imgui::column().size(120, 20).bg(gfx2d::rgb(0x202020))
                                                         .place(imgui::CENTER, imgui::CENTER).rotate(PI * 0.25))) {};
            };
        }
        it.hovered
    }
    print("turned card: hovered where it is drawn ", card(float2 { 360.0, 280.0 }), ", in the box around it ",
          card(float2 { 360.0, 200.0 }));

    // The focus cursor: round the focused widget, FOCUS_CURSOR's
    // ring_offset (4) outside it, the widgets' rings not drawn; moved to the
    // next by its motion; off again, the ring is back.
    fn focus_rect() -> gfx2d::Rect {
        for n in imgui::nodes { if n.id == imgui::focused { return n.screen; } }
        gfx2d::Rect { 0.0, 0.0, 0.0, 0.0 }
    }
    fn rings() -> bool {
        for n in imgui::nodes { if n.ring { return true; } }
        false
    }
    fn cursor() -> gfx2d::Rect { imgui::nodes[imgui::cursor_node].rect }
    fn r4(r: gfx2d::Rect) -> u8[>..] { str(round(r.x), " ", round(r.y), " ", round(r.w), " ", round(r.h)) }
    imgui::set_focus_cursor(imgui::FOCUS_CURSOR, imgui::tween(0.2));
    imgui::focus(imgui::id("Play"), true);
    for k in 20 { nav(imgui::NavInput { .. }); }
    print("cursor: ", r4(cursor()), " round ", r4(focus_rect()), "; rings drawn ", rings());
    let was = cursor();
    nav(imgui::NavInput { down: true, .. });
    nav(imgui::NavInput { .. });
    let mid = cursor();
    for k in 20 { nav(imgui::NavInput { .. }); }
    let now = cursor();
    print("moving down: between ", mid.y > was.y && mid.y < now.y, "; then ", r4(now), " round ", r4(focus_rect()));
    imgui::set_focus_cursor(imgui::NONE, imgui::INSTANT);
    nav(imgui::NavInput { .. });
    print("off: cursor ", imgui::cursor_node >= 0, ", rings drawn ", rings());
}
