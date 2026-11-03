// The widgets, each made of boxes, text and icons, and an interaction:
// what a program can write too. A widget's look is its classes' (BUTTON,
// CHECKBOX, SLIDER_TRACK, ...); the Desc a program passes sizes and places
// it, and can override its looks.
//
//   if imgui::button("Start") { … }
//   imgui::checkbox("Subtitles", subtitles);
//   imgui::toggle("Vibration", vibration);
//   imgui::radio("Easy", difficulty, 0); imgui::radio("Hard", difficulty, 1);
//   imgui::slider("Music", music, 0, 1);
//   imgui::progress(loaded);

namespace imgui;

import std;
import vec;
import math;
import gfx;
import gfx2d;

// The interaction of the widget `i` will be, recorded with Desc d: its
// hover, press, click and focus, as of this frame's input. A widget asks
// first, changes its value, then records its boxes (with the same ID and
// Desc) to look as the change makes it.
fn interact(i: Id, d: Desc) -> Interaction { interaction_for(i.v, d) }

// The bits a widget that takes clicks and focus has.
fn clickable(d: Desc) -> Desc { d.hit().focusable() }

// --- text --------------------------------------------------------------------------------

fn label(s: const u8[:]) { text(label_text(s)); }

// --- buttons ------------------------------------------------------------------------------

// A button: true the frame it is clicked or accepted.
fn button(label: const u8[:]) -> bool { button(label, row()) }
fn button(label: const u8[:], d: Desc) -> bool {
    let it = box(label, clickable(d.skin(BUTTON)).center()) { text(label_text(label)); };
    it.activated
}
// A button whose content the block records: an icon and a label, an image.
fn button_with<F>(label: const u8[:], d: Desc) -> bool {
    let it = box(label, clickable(d.skin(BUTTON))) { F(); };
    it.activated
}

// --- choices ----------------------------------------------------------------------------

fn checked_look(on: bool) -> LookState { LookState { checked: if on { 1.0 } else { 0.0 }, .. } }

// A checkbox and its label; true the frame it changes `v`.
fn checkbox(label: const u8[:], v: bool&) -> bool { checkbox(label, v, row()) }
fn checkbox(label: const u8[:], v: bool&, d: Desc) -> bool {
    let i = id(label);
    let rd = clickable(d.skin(CHOICE).align(CENTER));
    let it = interact(i, rd.look(checked_look(v)));
    let changed = it.activated;
    if changed { v = !v; }
    let look = look_of(it, false, rd.vis.state.disabled);
    box(i, rd.look(checked_look(v))) {
        var bl = look;
        bl.checked = it.checked_t;
        box(column().skin(CHECKBOX).look(bl).center()) {
            icon(ICON_CHECK, column().skin(CHECK)
                             .opacity(it.checked_t).scale(0.6 + 0.4 * it.checked_t)
                             .size(class_style(CHECKBOX).normal.min_size.x * 0.8,
                                   class_style(CHECKBOX).normal.min_size.y * 0.8));
        };
        if label_text(label).len > 0 { text(label_text(label)); }
    };
    changed
}

// A switch: a track and a knob that slides across it.
fn toggle(label: const u8[:], v: bool&) -> bool { toggle(label, v, row()) }
fn toggle(label: const u8[:], v: bool&, d: Desc) -> bool {
    let i = id(label);
    let rd = clickable(d.skin(CHOICE).align(CENTER));
    let it = interact(i, rd.look(checked_look(v)));
    let changed = it.activated;
    if changed { v = !v; }
    let look = look_of(it, false, rd.vis.state.disabled);
    box(i, rd.look(checked_look(v))) {
        if label_text(label).len > 0 { text(label_text(label), column().grow_w()); }
        let track = class_style(TOGGLE).normal.min_size;
        let knob = class_style(TOGGLE_KNOB).normal.min_size;
        let inset = (track.y - knob.y) * 0.5;
        var tl = look;
        tl.checked = it.checked_t;
        box(column().skin(TOGGLE).look(tl).size(track.x, track.y)) {
            panel(column().skin(TOGGLE_KNOB).size(knob.x, knob.y)
                  .absolute(inset + (track.x - knob.x - 2.0 * inset) * it.checked_t, inset));
        };
    };
    changed
}

// One of a set: `selected` becomes `value` when it is chosen.
fn radio(label: const u8[:], selected: i64&, value: i64) -> bool { radio(label, selected, value, row()) }
fn radio(label: const u8[:], selected: i64&, value: i64, d: Desc) -> bool {
    let i = id(label);
    let rd = clickable(d.skin(CHOICE).align(CENTER));
    let it = interact(i, rd.look(checked_look(selected == value)));
    let changed = it.activated && selected != value;
    if it.activated { selected = value; }
    let look = look_of(it, false, rd.vis.state.disabled);
    box(i, rd.look(checked_look(selected == value))) {
        var bl = look;
        bl.checked = it.checked_t;
        box(column().skin(RADIO).look(bl).center()) {
            let side = class_style(RADIO).normal.min_size.x * 0.5;
            panel(column().skin(RADIO_DOT).size(side, side).opacity(it.checked_t).scale(it.checked_t));
        };
        if label_text(label).len > 0 { text(label_text(label)); }
    };
    changed
}

// A row that can be selected, in a list.
fn selectable(label: const u8[:], selected: bool) -> bool { selectable(label, selected, row()) }
fn selectable(label: const u8[:], selected: bool, d: Desc) -> bool {
    let it = box(label, clickable(d.skin(SELECTABLE).grow_w().align(CENTER)).look(checked_look(selected))) {
        text(label_text(label));
    };
    it.activated
}

// --- sliders ------------------------------------------------------------------------------

// A value from lo to hi, by `step` (0: any): dragged, clicked along, or
// moved by left and right while focused. True the frame it changes.
fn slider(label: const u8[:], v: f64&, lo: f64, hi: f64, step: f64 = 0.0) -> bool {
    slider(label, v, lo, hi, step, row())
}
fn slider(label: const u8[:], v: f64&, lo: f64, hi: f64, step: f64, d: Desc) -> bool {
    let i = id(label);
    let track_id = sub_id(i, "track");
    let thumb = class_style(SLIDER_THUMB).normal.min_size;
    let line = class_style(SLIDER_TRACK).normal.min_size;
    let td = clickable(column().skin(SLIDER_THUMB).with_bits(CAPTURE_X)).height(thumb.y).grow_w()
             .min_w(line.x);
    let it = interact(track_id, td);
    let span = if hi > lo { hi - lo } else { 1.0 };
    let start: f64 = v;
    var value = clamp(start, min(lo, hi), max(lo, hi));
    let st = state_of(track_id.v);
    let w = max(st.rect.w - thumb.x, 1.0);
    if it.held {
        let f = clamp((it.pointer.x * (st.rect.w / max(it.rect.w, 1.0)) - thumb.x * 0.5) / w, 0.0, 1.0);
        value = lo + f * span;
    }
    if it.nav.x != 0 {
        let by = if step > 0.0 { step } else { span / 20.0 };
        value = clamp(value + it.nav.x * by, min(lo, hi), max(lo, hi));
    }
    if step > 0.0 { value = lo + round((value - lo) / step) * step; }
    value = clamp(value, min(lo, hi), max(lo, hi));
    let changed = value != start;
    v = value;
    let f = ((value - lo) / span) as f32;
    let shown_label = label_text(label);
    box(i, d.align(CENTER).gap(12)) {
        if shown_label.len > 0 { text(shown_label); }
        // The track: what takes the pointer, as tall as the thumb; its line,
        // filled to the value; the thumb on it.
        box(track_id, td.skin(NONE).look(look_of(it))) {
            let lw = st.rect.w;
            let y = (thumb.y - line.y) * 0.5;
            panel(column().skin(SLIDER_TRACK).absolute(thumb.x * 0.5, y).size(max(lw - thumb.x, 0.0), line.y));
            panel(column().skin(SLIDER_FILL).absolute(thumb.x * 0.5, y).size(max(lw - thumb.x, 0.0) * f, line.y));
            panel(column().skin(SLIDER_THUMB).look(look_of(it)).absolute(w * f, 0).size(thumb.x, thumb.y));
        };
    };
    changed
}
fn slider(label: const u8[:], v: f32&, lo: f64, hi: f64, step: f64 = 0.0) -> bool {
    var x: f64 = v;
    let changed = slider(label, x, lo, hi, step, row());
    v = x as f32;
    changed
}
fn slider(label: const u8[:], v: i64&, lo: i64, hi: i64) -> bool {
    var x: f64 = v;
    let changed = slider(label, x, lo, hi, 1.0, row());
    v = round(x) as i64;
    changed
}
fn slider(label: const u8[:], v: i32&, lo: i64, hi: i64) -> bool {
    var x: f64 = v;
    let changed = slider(label, x, lo, hi, 1.0, row());
    v = round(x) as i32;
    changed
}

// --- progress -------------------------------------------------------------------------------

// A bar filled to `value` (0 to 1).
fn progress(value: f64) { progress(value, column().grow_w()); }
fn progress(value: f64, d: Desc) {
    let f = clamp(value, 0.0, 1.0);
    box(d.skin(PROGRESS_TRACK).clip()) {
        panel(column().skin(PROGRESS_FILL).width(pct(f)).grow_h());
    };
}

// --- separators --------------------------------------------------------------------------

// A line across a column, or up a row.
fn separator() {
    let p = top_parent();
    let across = p >= 0 && nodes[p].d.lay.kind == ROW;
    if across {
        panel(column().skin(SEPARATOR).width(1).self_align(STRETCH));
    } else {
        panel(column().skin(SEPARATOR).height(1).self_align(STRETCH));
    }
}
