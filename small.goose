// Small pieces: small and icon buttons, toolbars and status bars, links,
// bullets, a label and its value, a spinner; sliders standing up, in
// degrees, and with two ends; a knob.
//
//   imgui::toolbar("tools") {
//       if imgui::icon_button("Play", imgui::ICON_PLAY) { play(); }
//       imgui::icon_toggle("Pause", imgui::ICON_PAUSE, paused);
//       imgui::separator();
//       if imgui::small_button("Reset") { reset(); }
//   };
//   imgui::knob("Gain", gain, 0, 2);
//   imgui::status_bar("status") { imgui::text("ready"); imgui::spinner("busy"); };

namespace imgui;

import std;
import vec;
import math;
import gfx2d;

// --- buttons --------------------------------------------------------------------------------

// A button with less padding, for rows of them in dense tools.
fn small_button(label: const u8[:], d: Desc = row()) -> bool {
    let it = box(label, clickable(d.skin(SMALL_BUTTON)).center()) { text(label_text(label)); };
    it.activated
}

// A square button showing icon `kind`, flat until hovered. Its label is
// its ID, and what its tooltip says (if there is text before any "##").
fn icon_button(label: const u8[:], kind: i64, d: Desc = row()) -> bool {
    let it = box(label, clickable(d.skin(ICON_BUTTON)).center()) { button_icon(kind); };
    let tip = label_text(label);
    if tip.len > 0 { tooltip(it, tip); }
    it.activated
}
// An icon filling an icon button, inside its padding.
fn button_icon(kind: i64) {
    let s = class_style(ICON_BUTTON).normal;
    let side = max(s.min_size.x - s.padding.x - s.padding.z, s.text_size * 0.75);
    icon(kind, column().size(side, side));
}
// An icon button that is on or off: clicked, `v` changes; on, it shows
// checked. True the frame it changes.
fn icon_toggle(label: const u8[:], kind: i64, v: bool&, d: Desc = row()) -> bool {
    let i = id(label);
    let bd = clickable(d.skin(ICON_BUTTON)).center();
    let changed = interact(i, bd.look(checked_look(v))).activated;
    if changed { v = !v; }
    let it = box(i, bd.look(checked_look(v))) { button_icon(kind); };
    let tip = label_text(label);
    if tip.len > 0 { tooltip(it, tip); }
    changed
}

// --- bars ---------------------------------------------------------------------------------

// A row of tools across the top of a window: icon buttons, small
// buttons, separators (separator() stands up in it), toggles.
fn toolbar<F>(label: const u8[:], d: Desc = row()) {
    box(label, d.skin(TOOLBAR).align(CENTER).grow_w()) { F(); };
}
// A row of small, muted text along the bottom of a window: put it last
// in a column that fills the window (with WINDOW_NO_SCROLL, the content
// above it in a scroll that grows).
fn status_bar<F>(label: const u8[:], d: Desc = row()) {
    box(label, d.skin(STATUS_BAR).align(CENTER).grow_w()) { F(); };
}

// --- text -------------------------------------------------------------------------------------

// Text to click, in the accent, underlined while hovered or focused. True
// the frame it is clicked or accepted.
fn link(label: const u8[:], d: Desc = column()) -> bool {
    let i = id(label);
    let ld = clickable(d.skin(LINK)).gap(0);
    let it = interact(i, ld);
    box(i, ld) {
        text(label_text(label));
        panel(column().skin(LINK_LINE).grow_w().look(look_of(it)));
    };
    it.activated
}

// A dot, for a list's items.
fn bullet(d: Desc = column()) { panel(d.skin(BULLET).self_align(CENTER)); }
// A dot and text beside it.
fn bullet_text(s: const u8[:]) {
    box(row().align(CENTER).gap(class_style(BULLET).normal.min_size.x * 1.5)) {
        bullet();
        text(s);
    };
}

// A label, muted, and its value at the row's other end: a readout.
fn label_value(label: const u8[:], value: const u8[:], d: Desc = row()) {
    box(d.align(CENTER).grow_w().gap(8)) {
        text(label_text(label), MUTED);
        panel(row().grow_w());
        text(value);
    };
}

// An arc going round, for something under way. `label` is its ID.
fn spinner(label: const u8[:] = "##spinner", d: Desc = column()) {
    let s = class_style(SPINNER).normal;
    var cd = d;
    if cd.dim.w.kind == SIZE_FIT { cd = cd.width(s.min_size.x); }
    if cd.dim.h.kind == SIZE_FIT { cd = cd.height(s.min_size.y); }
    canvas(label, cd) { sz =>
        let r = min(sz.x, sz.y) * 0.5;
        let w = max(r * 0.22, 1.5);
        let cx = sz.x * 0.5;
        let cy = sz.y * 0.5;
        stroke_arc(cx, cy, r - w * 0.5, 0.0, 2.0 * PI, w, s.bg);
        // Round once every 0.8 seconds, its length breathing.
        let a = clock * 2.0 * PI / 0.8;
        let len = 1.2 + 0.9 * sin(clock * 2.6);
        stroke_arc(cx, cy, r - w * 0.5, a, a + len, w, s.ink);
    };
}

// --- sliders --------------------------------------------------------------------------------

// A slider standing up: lo at the bottom, hi at the top; up and down move
// it while focused. Its label under it. True the frame it changes.
fn vslider(label: const u8[:], v: f64&, lo: f64, hi: f64, step: f64 = 0.0, d: Desc = column()) -> bool {
    let i = id(label);
    let track_id = sub_id(i, "track");
    let thumb = class_style(SLIDER_THUMB).normal.min_size;
    let line = class_style(SLIDER_TRACK).normal.min_size;
    let td = clickable(column().skin(SLIDER_THUMB).with_bits(CAPTURE_Y)).width(thumb.x).grow_h().min_h(thumb.y * 3.0);
    let it = interact(track_id, td);
    let span = if hi > lo { hi - lo } else { 1.0 };
    let start: f64 = v;
    var value = clamp(start, min(lo, hi), max(lo, hi));
    let st = state_of(track_id.v);
    let h = max(st.rect.h - thumb.y, 1.0);
    let moved = it.held || it.nav.y != 0;
    if it.held {
        let f = 1.0 - clamp((it.pointer.y * (st.rect.h / max(it.rect.h, 1.0)) - thumb.y * 0.5) / h, 0.0, 1.0);
        value = lo + f * span;
    }
    if it.nav.y != 0 {
        let by = if step > 0.0 { step } else { span / 20.0 };
        value = clamp(value - it.nav.y * by, min(lo, hi), max(lo, hi));
    }
    // Only what the player does changes it: a value just shown is left as
    // it is, out of range or between steps.
    if moved {
        if step > 0.0 { value = lo + round((value - lo) / step) * step; }
        value = clamp(value, min(lo, hi), max(lo, hi));
    }
    let changed = moved && value != start;
    let tick = if step > 0.0 { step } else { span / 20.0 };
    if changed && tick_of(value, lo, tick) != tick_of(clamp(start, min(lo, hi), max(lo, hi)), lo, tick) {
        ui_event(UI_CHANGE, track_id.v, SLIDER_THUMB);
    }
    if changed { v = value; }
    let f = ((value - lo) / span) as f32;
    let shown_label = label_text(label);
    var bd = d.align(CENTER).gap(6);
    if bd.dim.h.kind == SIZE_FIT { bd = bd.height(line.x); }
    box(i, bd) {
        box(track_id, td.skin(NONE).look(look_of(it))) {
            let lh = st.rect.h;
            let x = (thumb.x - line.y) * 0.5;
            let len = max(lh - thumb.y, 0.0);
            panel(column().skin(SLIDER_TRACK).absolute(x, thumb.y * 0.5).size(line.y, len));
            panel(column().skin(SLIDER_FILL).absolute(x, thumb.y * 0.5 + len * (1.0 - f)).size(line.y, len * f));
            panel(column().skin(SLIDER_THUMB).look(look_of(it)).absolute(0, h * (1.0 - f)).size(thumb.x, thumb.y));
        };
        if shown_label.len > 0 { text(shown_label); }
    };
    changed
}
fn vslider(label: const u8[:], v: f32&, lo: f64, hi: f64, step: f64 = 0.0, d: Desc = column()) -> bool {
    var x: f64 = v;
    let changed = vslider(label, x, lo, hi, step, d);
    let y = x as f32;
    let moved = changed && y != v;
    if moved { v = y; }
    moved
}

// An angle, kept in radians, slid in whole degrees from lo_deg to hi_deg,
// its value shown beside it.
fn slider_angle(label: const u8[:], radians: f64&, lo_deg: f64 = -180.0, hi_deg: f64 = 180.0) -> bool {
    var deg = radians * 180.0 / PI;
    var changed = false;
    box(row().align(CENTER).gap(8)) {
        changed = slider(label, deg, lo_deg, hi_deg, 1.0, row());
        text(str(round(deg) as i64, " deg"), MUTED);
    };
    let r = deg * PI / 180.0;
    let moved = changed && r != radians;
    if moved { radians = r; }
    moved
}

// Which thumb a range slider moves by the keys: 0 `from`, 1 `to`. Kept
// however long the slider is hidden.
var range_thumbs = dictionary<u64, i32> {};

// A range from lo to hi: two thumbs, `from` and `to`, never crossing. A
// press takes the nearer thumb; left and right move the one taken last,
// and accept (Enter, A) changes which. True the frame either changes.
fn range_slider(label: const u8[:], from: f64&, to: f64&, lo: f64, hi: f64, step: f64 = 0.0, d: Desc = row()) -> bool {
    let i = id(label);
    let track_id = sub_id(i, "track");
    let thumb = class_style(SLIDER_THUMB).normal.min_size;
    let line = class_style(SLIDER_TRACK).normal.min_size;
    let td = clickable(column().skin(SLIDER_THUMB).with_bits(CAPTURE_X)).height(thumb.y).grow_w().min_w(line.x);
    let it = interact(track_id, td);
    let span = if hi > lo { hi - lo } else { 1.0 };
    let a0: f64 = from;
    let b0: f64 = to;
    var a = clamp(a0, min(lo, hi), max(lo, hi));
    var b = clamp(b0, min(lo, hi), max(lo, hi));
    if a > b { b = a; }
    let st = state_of(track_id.v);
    let w = max(st.rect.w - thumb.x, 1.0);
    var which: i32 = 1;
    let kept = range_thumbs.get(track_id.v);
    if kept { which = kept; }
    let at_pointer = clamp((it.pointer.x * (st.rect.w / max(it.rect.w, 1.0)) - thumb.x * 0.5) / w, 0.0, 1.0);
    if it.pressed {
        // The nearer thumb; on both (one value), the one the pointer is
        // past, so that they can be pulled apart.
        let fa = (a - lo) / span;
        let fb = (b - lo) / span;
        let p: f64 = at_pointer;
        which = if abs(p - fa) < abs(p - fb) || (fa == fb && p < fa) { 0 } else { 1 };
    }
    if accept_id == track_id.v { which = 1 - which; }
    range_thumbs.insert(track_id.v, which);
    let by = if step > 0.0 { step } else { span / 20.0 };
    // Only what the player does changes them: values just shown are left
    // as they are, out of range or between steps.
    let moved = it.held || it.nav.x != 0;
    if moved {
        var to_be: f64 = if which == 0 { a } else { b };
        if it.held { to_be = lo + at_pointer * span; }
        if it.nav.x != 0 { to_be = to_be + it.nav.x * by; }
        if step > 0.0 { to_be = lo + round((to_be - lo) / step) * step; }
        if which == 0 { a = clamp(to_be, min(lo, hi), b); } else { b = clamp(to_be, a, max(lo, hi)); }
    }
    let changed = moved && (a != a0 || b != b0);
    if changed { ui_event(UI_CHANGE, track_id.v, SLIDER_THUMB); }
    if changed {
        from = a;
        to = b;
    }
    let fa = ((a - lo) / span) as f32;
    let fb = ((b - lo) / span) as f32;
    let shown_label = label_text(label);
    box(i, d.align(CENTER).gap(12)) {
        if shown_label.len > 0 { text(shown_label); }
        box(track_id, td.skin(NONE).look(look_of(it))) {
            let lw = st.rect.w;
            let y = (thumb.y - line.y) * 0.5;
            let len = max(lw - thumb.x, 0.0);
            panel(column().skin(SLIDER_TRACK).absolute(thumb.x * 0.5, y).size(len, line.y));
            panel(column().skin(SLIDER_FILL).absolute(thumb.x * 0.5 + len * fa, y).size(len * (fb - fa), line.y));
            // The one taken last drawn over the other, and looking held.
            let held = look_of(it);
            let fo = if which == 0 { fb } else { fa };
            let ft = if which == 0 { fa } else { fb };
            panel(column().skin(SLIDER_THUMB).absolute(w * fo, 0).size(thumb.x, thumb.y));
            panel(column().skin(SLIDER_THUMB).look(held).absolute(w * ft, 0).size(thumb.x, thumb.y));
        };
    };
    changed
}

// --- knobs ------------------------------------------------------------------------------------

// A value from lo to hi on a dial: dragged up or right to turn it up,
// down or left to turn it down (the whole range in 200 pixels); the arrows
// while focused. Its label under it. True the frame it changes.
fn knob(label: const u8[:], v: f64&, lo: f64, hi: f64, step: f64 = 0.0, d: Desc = column()) -> bool {
    let i = id(label);
    let kid = sub_id(i, "knob");
    let size = class_style(KNOB).normal.min_size;
    let kd = clickable(column().skin(KNOB).with_bits(CAPTURE_X | CAPTURE_Y)).size(size.x, size.y);
    let it = interact(kid, kd);
    let span = if hi > lo { hi - lo } else { 1.0 };
    let start: f64 = v;
    var value = clamp(start, min(lo, hi), max(lo, hi));
    var ks = state_of(kid.v);
    if it.pressed {
        ks.num = value;
        put_state(kid.v, ks);
    }
    let moved = (it.held && it.dragging) || it.nav.x != 0 || it.nav.y != 0;
    if it.held && it.dragging { value = ks.num + (it.drag.x - it.drag.y) * span / 200.0; }
    let by = if step > 0.0 { step } else { span / 20.0 };
    if it.nav.x != 0 || it.nav.y != 0 { value = value + (it.nav.x - it.nav.y) * by; }
    // Only what the player does changes it: a value just shown is left as
    // it is, out of range or between steps.
    if moved {
        if step > 0.0 { value = lo + round((value - lo) / step) * step; }
        value = clamp(value, min(lo, hi), max(lo, hi));
    }
    let changed = moved && value != start;
    if changed && tick_of(value, lo, by) != tick_of(clamp(start, min(lo, hi), max(lo, hi)), lo, by) {
        ui_event(UI_CHANGE, kid.v, KNOB);
    }
    if changed { v = value; }
    let f = (value - lo) / span;
    let track = class_style(SLIDER_TRACK).normal.bg;
    let fill = class_style(SLIDER_FILL).normal.bg;
    let face = class_style(SLIDER_THUMB).normal;
    let shown_label = label_text(label);
    box(i, d.align(CENTER).gap(4)) {
        canvas(kid, kd.look(look_of(it))) { sz =>
            let cx = sz.x * 0.5;
            let cy = sz.y * 0.5;
            let r = min(sz.x, sz.y) * 0.5;
            let w = max(r * 0.14, 2.0);
            // From the bottom left, round over the top, to the bottom right.
            let a0 = 0.75 * PI;
            let sweep = 1.5 * PI;
            let ra = r - w * 0.5;
            stroke_arc(cx, cy, ra, a0, a0 + sweep, w, track);
            if f > 0.0 { stroke_arc(cx, cy, ra, a0, a0 + sweep * f, w, fill); }
            let body = r - w - 3.0;
            fill_circle(cx, cy, body, face.bg);
            if face.border_width > 0.0 { stroke_circle(cx, cy, body, 1.0, face.border); }
            let a = a0 + sweep * f;
            draw_line(cx + cos(a) * body * 0.25, cy + sin(a) * body * 0.25, cx + cos(a) * body * 0.8,
                      cy + sin(a) * body * 0.8, max(w * 0.8, 2.0), face.border);
        };
        if shown_label.len > 0 { text(shown_label, MUTED); }
    };
    changed
}
fn knob(label: const u8[:], v: f32&, lo: f64, hi: f64, step: f64 = 0.0, d: Desc = column()) -> bool {
    var x: f64 = v;
    let changed = knob(label, x, lo, hi, step, d);
    let y = x as f32;
    let moved = changed && y != v;
    if moved { v = y; }
    moved
}
