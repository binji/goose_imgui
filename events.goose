// What happened in the interface, for a game's UI sounds: a frame's list
// of events, read after the frame. imgui plays nothing itself.
//
//   imgui::frame() { ui(); };
//   for e in imgui::ui_events() {
//       if e.kind == imgui::UI_HOVER || e.kind == imgui::UI_FOCUS { play(tick); }
//       else if e.kind == imgui::UI_ACTIVATE { play(if e.class == imgui::TAB { swish } else { click }); }
//       else if e.kind == imgui::UI_DENIED { play(buzz); }
//   }
//
// Hovers, focus, presses, activations and denials come from interact, so
// a program's own widgets have them too; it can add its own with ui_event.

namespace imgui;

import std;
import math;

let UI_HOVER: u8 = 1;       // the pointer came onto an enabled widget (by moving, not by the widget coming to it)
let UI_FOCUS: u8 = 2;       // navigation showed the focus on a widget (keys or a pad; a click focuses quietly)
let UI_PRESS: u8 = 3;       // the pointer went down on it
let UI_ACTIVATE: u8 = 4;    // clicked, or accepted while focused
let UI_CHANGE: u8 = 5;      // a value moved without an activation: a slider's tick, tabs switched by the shoulders
let UI_OPEN: u8 = 6;        // a popup, menu, dropdown or modal opened
let UI_CLOSE: u8 = 7;       // and closed: by cancel, a press outside, the program, or no longer recorded
let UI_DENIED: u8 = 8;      // the pointer went down on a disabled widget
let UI_BACK: u8 = 9;        // cancel with nothing open to close it: the program's "back"

// An event: what happened, to which widget (or popup), and its class.
struct UiEvent {
    kind: u8 = 0,
    id: u64 = 0,
    class: StyleClass = StyleClass { 0 },
}

// This frame's, so far (and any from between frames), and the last frame's.
var ui_log: UiEvent[>..<] = [];
var ui_last: UiEvent[>..<] = [];

// The last frame's events, in the order they happened: read after frame().
fn ui_events() -> const UiEvent[:] { ui_last }

// An event of the program's own widget.
fn ui_event(kind: u8, i: Id, class: StyleClass = StyleClass { 0 }) { ui_event(kind, i.v, class); }
fn ui_event(kind: u8, id: u64, class: StyleClass) { ui_log.push(UiEvent { kind, id, class }); }

// An event kind's name, for logging: "hover", "focus" … ("own" past UI_BACK).
fn ui_event_name(kind: u8) -> const u8[:] {
    let names = ["none", "hover", "focus", "press", "activate", "change", "open", "close", "denied", "back"];
    if kind < names.len { names[kind as i64] } else { "own" }
}

// The frame's events published, at its end.
fn publish_ui_events() {
    ui_last.clear();
    for e in ui_log { ui_last.push(e); }
    ui_log.clear();
}

// The class an open popup of `kind` is drawn in.
fn popup_class(kind: i64) -> StyleClass {
    if kind == POPUP_MENU { MENU } else if kind == POPUP_MODAL { MODAL } else { POPUP }
}

// A value moving in ticks of `tick` from lo: which tick it is in.
fn tick_of(v: f64, lo: f64, tick: f64) -> i64 { floor((v - lo) / tick + 1.0e-9) as i64 }
