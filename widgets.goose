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
// The interaction of the last widget recorded: for a widget that returns
// only its value, such as selectable, to give to tooltip or context_menu.
fn last_item() -> Interaction { last_interaction }

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
    let off = d.bits & DISABLED != 0;
    let td = clickable(column().skin(SLIDER_THUMB).with_bits(CAPTURE_X)).height(thumb.y).grow_w()
             .min_w(line.x).disabled(off);
    let it = interact(track_id, td);
    let span = if hi > lo { hi - lo } else { 1.0 };
    let start: f64 = v;
    var value = clamp(start, min(lo, hi), max(lo, hi));
    let st = state_of(track_id.v);
    let w = max(st.rect.w - thumb.x, 1.0);
    let moved = it.held || it.nav.x != 0;
    if it.held {
        let f = clamp((it.pointer.x * (st.rect.w / max(it.rect.w, 1.0)) - thumb.x * 0.5) / w, 0.0, 1.0);
        value = lo + f * span;
    }
    if it.nav.x != 0 {
        let by = if step > 0.0 { step } else { span / 20.0 };
        value = clamp(value + it.nav.x * by, min(lo, hi), max(lo, hi));
    }
    // Only what the player does changes it: a value just shown is left as
    // it is, out of range or between steps.
    if moved {
        if step > 0.0 { value = lo + round((value - lo) / step) * step; }
        value = clamp(value, min(lo, hi), max(lo, hi));
    }
    let changed = moved && value != start;
    // A tick a step, or a twentieth of the way along without one.
    let tick = if step > 0.0 { step } else { span / 20.0 };
    if changed && tick_of(value, lo, tick) != tick_of(clamp(start, min(lo, hi), max(lo, hi)), lo, tick) {
        ui_event(UI_CHANGE, track_id.v, SLIDER_THUMB);
    }
    if changed { v = value; }
    let f = ((value - lo) / span) as f32;
    let shown_label = label_text(label);
    box(i, d.align(CENTER).gap(12)) {
        if shown_label.len > 0 { text(shown_label); }
        // The track: what takes the pointer, as tall as the thumb; its line,
        // filled to the value; the thumb on it.
        box(track_id, td.skin(NONE).look(look_of(it))) {
            let lw = st.rect.w;
            let y = (thumb.y - line.y) * 0.5;
            panel(column().skin(SLIDER_TRACK).disabled(off).absolute(thumb.x * 0.5, y).size(max(lw - thumb.x, 0.0), line.y));
            panel(column().skin(SLIDER_FILL).disabled(off).absolute(thumb.x * 0.5, y).size(max(lw - thumb.x, 0.0) * f, line.y));
            panel(column().skin(SLIDER_THUMB).look(look_of(it, false, off)).absolute(w * f, 0).size(thumb.x, thumb.y));
        };
    };
    changed
}
fn slider(label: const u8[:], v: f32&, lo: f64, hi: f64, step: f64 = 0.0) -> bool {
    var x: f64 = v;
    let changed = slider(label, x, lo, hi, step, row());
    let y = x as f32;
    let moved = changed && y != v;
    if moved { v = y; }
    moved
}
fn slider(label: const u8[:], v: i64&, lo: i64, hi: i64) -> bool {
    var x: f64 = v;
    let changed = slider(label, x, lo, hi, 1.0, row());
    let y = round(x) as i64;
    let moved = changed && y != v;
    if moved { v = y; }
    moved
}
fn slider(label: const u8[:], v: i32&, lo: i64, hi: i64) -> bool {
    var x: f64 = v;
    let changed = slider(label, x, lo, hi, 1.0, row());
    let y = round(x) as i32;
    let moved = changed && y != v;
    if moved { v = y; }
    moved
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

// --- meters -------------------------------------------------------------------------------

// How a meter shows its value.
struct Meter {
    vertical: bool = false,         // filled from the bottom
    segments: i32 = 1,              // cut into this many, METER's gap apart
    trail: Motion = Motion { .. },  // a drop leaves a trail that eases down by this; INSTANT: none
    thickness: f32 = 0.0,           // a radial meter's ring; 0: a sweep (a pie)
    // Its parts' classes: one meter red for health, another green for stamina.
    track_class: StyleClass = METER_TRACK,
    fill_class: StyleClass = METER_FILL,
    trail_class: StyleClass = METER_TRAIL,
}

// The trail behind a meter's value: eased down after a drop, up with a rise
// at once.
fn meter_trail(i: Id, value: f64, m: Meter) -> f64 {
    if is_instant(m.trail) { return value; }
    max(animate(sub_id(i, "trail"), value, m.trail), value)
}

// A bar filled to `value` (0 to 1), for health, stamina or a boss: in
// segments, upright, and trailed as `m` says. Its look is METER's (the gap)
// and its parts' classes' (METER_TRACK, METER_FILL and METER_TRAIL unless
// `m` says others); it is 160 by 8 (8 by 160 upright) unless `d` sizes it.
//   imgui::meter("hp", hp / max_hp, imgui::row().width(220), imgui::Meter { segments: 5, trail: imgui::tween(0.5).delay(0.4) });
fn meter(label: const u8[:], value: f64) { meter(label, value, row(), Meter { .. }); }
fn meter(label: const u8[:], value: f64, d: Desc) { meter(label, value, d, Meter { .. }); }
fn meter(label: const u8[:], value: f64, d: Desc, m: Meter) {
    let i = id(label);
    let v = clamp(value, 0.0, 1.0);
    let t = meter_trail(i, v, m);
    var md = d.skin(METER);
    md.lay.kind = if m.vertical { COLUMN } else { ROW };
    if md.dim.w.kind == SIZE_FIT { md = md.width(if m.vertical { 8.0 } else { 160.0 }); }
    if md.dim.h.kind == SIZE_FIT { md = md.height(if m.vertical { 160.0 } else { 8.0 }); }
    let n = max(m.segments, 1);
    box(i, md) {
        for k in n {
            // Upright, the first segment is at the bottom.
            let lo = (if m.vertical { n - 1 - k } else { k }) as f64 / n;
            fn part(x: f64) -> f64 { clamp((x - lo) * n, 0.0, 1.0) }
            box(k, stack().skin(m.track_class).grow().clip()) {
                let pv = part(v);
                for c, f in [m.trail_class, m.fill_class] {
                    let p = if f == 0 { part(t) } else { pv };
                    // A trail no longer than the fill would not show.
                    if p <= 0.0005 || (f == 0 && p <= pv + 0.0005) { continue; }
                    let pd = if m.vertical { column().width(pct(1.0)).height(pct(p)).place(START, END) }
                             else { column().width(pct(p)).height(pct(1.0)).place(START, START) };
                    panel(pd.skin(c));
                }
            };
        }
    };
}

// A meter round a circle, from the top, clockwise: a ring (m.thickness) or
// a sweep, for a cooldown over an icon or an ability's charge. Its colors
// are the backgrounds of its parts' classes; a ring's segments are METER's
// gap apart. 48 by 48 unless `d` sizes it.
fn radial_meter(label: const u8[:], value: f64) { radial_meter(label, value, column(), Meter { .. }); }
fn radial_meter(label: const u8[:], value: f64, d: Desc) { radial_meter(label, value, d, Meter { .. }); }
fn radial_meter(label: const u8[:], value: f64, d: Desc, m: Meter) {
    let i = id(label);
    let v = clamp(value, 0.0, 1.0);
    let t = meter_trail(i, v, m);
    var cd = d;
    if cd.dim.w.kind == SIZE_FIT { cd = cd.width(48); }
    if cd.dim.h.kind == SIZE_FIT { cd = cd.height(48); }
    let track = resolve_style(m.track_class, LookState { .. }).bg;
    let fill = resolve_style(m.fill_class, LookState { .. }).bg;
    let trail = resolve_style(m.trail_class, LookState { .. }).bg;
    let gap = resolve_style(METER, LookState { .. }).gap;
    let n = max(m.segments, 1);
    canvas(i, cd) { size =>
        let c = size * 0.5;
        let w: f64 = m.thickness;
        let r = max(min(c.x, c.y) - w * 0.5, 1.0);
        let top = -PI * 0.5;
        // Between segments, the gap as an angle on the ring.
        let ga = if n > 1 { gap / r } else { 0.0 };
        let seg = 2.0 * PI / n;
        for k in n {
            let a0 = top + k * seg + ga * 0.5;
            let a1 = top + (k + 1) * seg - ga * 0.5;
            fn upto(x: f64) -> f64 { min(a1, top + 2.0 * PI * x) }
            for c2, f in [track, trail, fill] {
                let e = if f == 0 { a1 } else { upto(if f == 1 { t } else { v }) };
                if e <= a0 { continue; }
                if w > 0.0 { stroke_arc(c.x, c.y, r, a0, e, w, c2); } else { fill_pie(c.x, c.y, r, a0, e, c2); }
            }
        }
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

// --- tabs ------------------------------------------------------------------------------------

struct TabsCtx { id: u64, bar: i32, body: i32, count: i64, selected: i64 }
var tabs_stack: TabsCtx[>..<] = [];

// A row of tabs and the selected one's content: the block records each
// tab(…) in order. A click, or accept, on a tab selects it; so do the
// shoulder buttons (tab_left, tab_right), if `shoulders`.
fn tabs<F>(label: const u8[:], selected: i64&, d: Desc = column(), shoulders: bool = true) {
    let i = id(label);
    var st = state_of(i.v);
    var sel = selected;
    // One of its tabs clicked this frame: known before any is recorded.
    for k in [clicked_id, accept_id] {
        if k != 0 {
            let ts = state_of(k);
            if ts.owner == i.v && ts.index >= 0 { sel = ts.index; }
        }
    }
    let count = st.index as i64;
    if shoulders && count > 0 {
        let was = sel;
        if input.nav.tab_left { sel = (sel + count - 1) % count; }
        if input.nav.tab_right { sel = (sel + 1) % count; }
        if sel != was { ui_event(UI_CHANGE, i.v, TAB); }
    }
    let at = nodes.len as i32;
    box(i, d.gap(0)) {
        let bar = nodes.len as i32;
        panel(row().skin(TAB_BAR));
        let body = nodes.len as i32;
        panel(column().skin(TAB_PANEL).grow());
        tabs_stack.push(TabsCtx { i.v, bar, body, 0, sel });
        F();
        let ctx = tabs_stack.pop();
        st.index = ctx.count as i32;
    };
    st.seen = frame_index;
    put_state(i.v, st);
    // Past its tabs, as a list that shrank leaves it: its last.
    if st.index > 0 { sel = clamp(sel, 0, st.index as i64 - 1); }
    selected = sel;
}

// A tab: its header in the bar; the block, its content, while selected.
fn tab<F>(label: const u8[:]) {
    guard tabs_stack.len > 0 else { misuse("tab: not inside tabs"); return; }
    let k = tabs_stack.len - 1;
    let ctx = tabs_stack[k];
    let index = ctx.count;
    tabs_stack[k].count = index + 1;
    let i = id(label);
    let on = index == ctx.selected;
    push_parent(ctx.bar, false);
    box(i, clickable(row().skin(TAB).center()).look(checked_look(on))) { text(label_text(label)); };
    close_node();
    var hs = state_of(i.v);
    hs.owner = ctx.id;
    hs.index = index as i32;
    put_state(i.v, hs);
    if on {
        push_parent(ctx.body, false);
        let m = class_transition(TAB_PANEL);
        // Spaced by TAB_PANEL's gap: the panel's style, its content's spacing.
        let g = class_style(TAB_PANEL).normal.gap;
        box(sub_id(i, "content"), column().grow().gap(g).enter(fade_in(m))) { F(); };
        close_node();
    }
}
