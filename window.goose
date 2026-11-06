// Windows: panels moved by their title bars, resized by their edges and
// corners, collapsed to their title bars and closed. They are roots of
// their own, drawn over the main tree and under popups, back to front in
// the order they were last pressed. Where each is, its size and whether it
// is collapsed are kept, and its body scrolls. Collapsing can roll the
// body up into the title bar, and opening roll it down (set_window_roll).
//
//   imgui::window("Stats", show_stats, imgui::column().size(260, 180)) {
//       imgui::textf(imgui::column()) { out => format(out, "fps ", fps); };
//       imgui::checkbox("Wireframe", wireframe);
//   };

namespace imgui;

import std;
import vec;
import math;
import dictionary;
import gfx;
import gfx2d;

// window()'s flags.
let WINDOW_NO_TITLE = 1;        // no title bar: not moved, collapsed or closed by the pointer
let WINDOW_NO_RESIZE = 2;
let WINDOW_NO_MOVE = 4;
let WINDOW_NO_COLLAPSE = 8;
let WINDOW_NO_SCROLL = 16;      // the body clips, but doesn't scroll

struct WindowState {
    pos: float2 = float2 { 0.0, 0.0 },          // its top left
    size: float2 = float2 { 0.0, 0.0 },         // 0 on an axis: its content's size
    collapsed: bool = false,
    grab: float2 = float2 { 0.0, 0.0 },         // where it was, and how big, when a drag began
    grab_size: float2 = float2 { 0.0, 0.0 },
    open_h: f32 = 0.0,                          // its height when last fully open: what a roll runs over
    dock: i32 = -1,                             // the dock node it is in (dock.goose); -1: floating
    called: i64 = -1,                           // the frame window() was last called for it
    closable: bool = false,                     // it has a close button: so does its tab, docked
    host: bool = false,                         // a floating dock: imgui's window holding a dock space
    unplaced: bool = false,                     // known only by a setting: its Desc still says where it goes
    title: u8[..48] = [],                       // its title, for its tab
}

// A window's own state lives here, not in its ID's WidgetState, which is
// dropped when the window isn't recorded for a while: a window closed and
// opened again comes back where it was.
var windows = dictionary<u64, WindowState> {};
var window_order: u64[>..<] = [];   // every window seen, back to front
var front_window: u64 = 0;          // the front one of those drawn last frame
var hot_window: u64 = 0;            // the one the pointer is over
var wanted_cursor: i64 = 0;         // the pointer's shape the frame asks for (CURSOR_*)

// The pointer's shapes the UI asks for, numbered as gfx's are where it has
// them (gfx v1 doesn't yet): a program with them passes cursor() on.
let CURSOR_DEFAULT = 0;
let CURSOR_NWSE_RESIZE = 5;         // a top left or bottom right corner
let CURSOR_NESW_RESIZE = 6;
let CURSOR_EW_RESIZE = 7;
let CURSOR_NS_RESIZE = 8;
// The shape the pointer should have, from the last frame: over a grip, its
// arrows.
fn cursor() -> i64 { wanted_cursor }

fn window_state(id: u64) -> WindowState {
    let s = windows.get(id);
    if s { return s; }
    WindowState { .. }
}

fn begin_windows() { wanted_cursor = CURSOR_DEFAULT; }

// How windows roll up as they collapse, and down as they open: INSTANT
// (the default) not at all; a tween or spring, the body rolling into the
// title bar and out of it, cut off at its bottom edge.
var window_roll = INSTANT;
fn set_window_roll(m: Motion) { window_roll = m; }

// How windows show and hide: `e` played as one appears (opened, or first
// recorded), `x` on a copy of it as it goes (closed, or no longer
// recorded), in its place among the windows. Instant by default.
var window_enter = Enter { .. };
var window_exit = Exit { .. };
fn set_window_show(e: Enter, x: Exit) {
    window_enter = e;
    window_exit = x;
}
// Fading, and growing from `zoom` of its size as it shows, shrinking to it
// as it hides.
fn set_window_show(m: Motion, zoom: f64 = 0.95) { set_window_show(pop_in(zoom, m), pop_out(zoom, m)); }

// Window `id` put in front of the others.
fn raise_window_id(raised: u64) {
    // One in a floating dock goes with its dock.
    let held = dock_host_of(window_state(raised).dock);
    let id = if held != 0 { held } else { raised };
    var found = false;
    var k = 0;
    while k < window_order.len {
        if window_order[k] == id { found = true; }
        if found && k + 1 < window_order.len { window_order[k] = window_order[k + 1]; }
        k++;
    }
    if found { window_order[window_order.len - 1] = id; } else { window_order.push(id); }
}
fn in_window_order(id: u64) -> bool {
    for w in window_order { if w == id { return true; } }
    false
}
fn raise_window(title: const u8[:]) { raise_window_id(id(title).v); }

// Where window `title` was drawn last frame.
fn window_rect(title: const u8[:]) -> gfx2d::Rect { state_of(id(title).v).screen }
// Window `title` moved and sized: a size of 0 on an axis is its content's.
fn set_window_rect(title: const u8[:], r: gfx2d::Rect) {
    let i = id(title).v;
    var w = window_state(i);
    if !windows.contains(i) { window_order.push(i); }
    w.pos = float2 { r.x, r.y };
    w.size = float2 { r.w, r.h };
    windows.insert(i, w);
}
fn collapse_window(title: const u8[:], on: bool) {
    let i = id(title).v;
    var w = window_state(i);
    if !windows.contains(i) {
        window_order.push(i);
        w.unplaced = true;
    }
    w.collapsed = on;
    windows.insert(i, w);
}
fn is_window_collapsed(title: const u8[:]) -> bool { window_state(id(title).v).collapsed }

// The direction grip g resizes: -1 moves the left or top edge, 1 the
// right or bottom one.
fn grip_dir(g: i64) -> int2 {
    match g {
        0 => int2 { -1, 0 },
        1 => int2 { 1, 0 },
        2 => int2 { 0, -1 },
        3 => int2 { 0, 1 },
        4 => int2 { -1, -1 },
        5 => int2 { 1, -1 },
        6 => int2 { -1, 1 },
        _ => int2 { 1, 1 },
    }
}
fn grip_cursor(d: int2) -> i64 {
    if d.x != 0 && d.y != 0 { return if d.x == d.y { CURSOR_NWSE_RESIZE } else { CURSOR_NESW_RESIZE }; }
    if d.x != 0 { CURSOR_EW_RESIZE } else { CURSOR_NS_RESIZE }
}
// Where grip g is on a frame of `size`, `t` thick: astride its edge, the
// corners twice as long.
fn grip_rect(g: i64, size: float2, t: f32) -> gfx2d::Rect {
    let h = t * 0.5;
    let c = t * 2.0;
    let w = size.x;
    let ht = size.y;
    match g {
        0 => gfx2d::Rect { -h, c, t, max(ht - 2.0 * c, 0.0) },
        1 => gfx2d::Rect { w - h, c, t, max(ht - 2.0 * c, 0.0) },
        2 => gfx2d::Rect { c, -h, max(w - 2.0 * c, 0.0), t },
        3 => gfx2d::Rect { c, ht - h, max(w - 2.0 * c, 0.0), t },
        4 => gfx2d::Rect { -h, -h, c, c },
        5 => gfx2d::Rect { w - c + h, -h, c, c },
        6 => gfx2d::Rect { -h, ht - c + h, c, c },
        _ => gfx2d::Rect { w - c + h, ht - c + h, c, c },
    }
}

// A window, its content recorded by the block (unless it is collapsed).
// `d` is its body's: a column, its gap, padding and alignment; its size,
// if in pixels, is the window's to start with (else the content's), and
// its absolute(x, y) where the window starts (else a little below and to
// the right of the last new one).
fn window<F>(title: const u8[:], d: Desc = column(), flags: i64 = 0) {
    var open = true;
    window_with(id(title), title, open, false, d, flags) { F(); };
}
// With a close button, which sets `open` false. Nothing is recorded while
// it is false.
fn window<F>(title: const u8[:], open: bool&, d: Desc = column(), flags: i64 = 0) {
    guard open;
    window_with(id(title), title, open, true, d, flags) { F(); };
}

fn window_with<F>(wid: Id, title: const u8[:], open: bool&, closable: bool, d: Desc, flags: i64) {
    var w = window_state(wid.v);
    let known = windows.contains(wid.v) && !w.unplaced;
    w.unplaced = false;
    let last_st = state_of(wid.v);
    let last = last_st.rect;
    let never_called = w.called < 0;
    w.called = frame_index;
    w.closable = closable;
    w.title.clear();
    for c in label_text(title) { if w.title.len < w.title.cap { w.title.push(c); } }
    windows.insert(wid.v, w);
    // Docked in a floating dock: that window recorded first (once a frame);
    // the frame it first is, it isn't laid out yet, so this one waits.
    if w.dock >= 0 && dock_host_of(w.dock) != 0 {
        record_host(dock_host_of(w.dock));
        // Which may have undocked it (its tab dragged out), or moved it.
        w = window_state(wid.v);
        if w.dock >= 0 && !dock_shown(w.dock) { return; }
    }
    // Docked, in a dock space being shown: its body in its node, if its tab
    // is the one selected (dock.goose).
    if w.dock >= 0 && dock_shown(w.dock) {
        docked_window(wid, open, d, flags) { F(); };
        return;
    }
    if !known {
        let k = (window_order.len % 8) as f32;
        w.pos = if d.lay.absolute { d.lay.at } else { float2 { viewport.x + 24.0 + 28.0 * k, viewport.y + 24.0 + 28.0 * k } };
        w.size = float2 { if d.dim.w.kind == SIZE_PX { d.dim.w.value } else { 0.0 },
                          if d.dim.h.kind == SIZE_PX { d.dim.h.value } else { 0.0 } };
        raise_window_id(wid.v);
    } else if last_st.seen < frame_index - 1 && !(never_called && in_window_order(wid.v)) {
        // Opened again: in front. (Not one a layout loaded, which keeps its
        // place.)
        raise_window_id(wid.v);
    }
    let has_title = flags & WINDOW_NO_TITLE == 0;
    let can_collapse = has_title && flags & WINDOW_NO_COLLAPSE == 0;
    let title_id = sub_id(wid, "title");
    let collapse_id = sub_id(wid, "collapse");
    let close_id = sub_id(wid, "close");
    let bar_d = row().skin(WINDOW_TITLE).grow_w().align(CENTER).hit().look(checked_look(front_window == wid.v));
    let button_d = clickable(row().skin(WINDOW_BUTTON)).nav_skip();

    // The title bar: dragged, it moves the window; double-clicked, or its
    // arrow clicked, it collapses or opens it.
    // On a dock target, the area it would take (drawn there, if the dock
    // preview is the window).
    var aimed = false;
    var into_tab = false;
    var aim = gfx2d::Rect { 0.0, 0.0, 0.0, 0.0 };
    if has_title {
        let tb = interaction_for(title_id.v, bar_d);
        if tb.pressed { w.grab = w.pos; }
        if tb.held && tb.dragging && flags & WINDOW_NO_MOVE == 0 { w.pos = w.grab + tb.drag; }
        // Dragged over a dock space: where it would go shown; let go
        // there, docked.
        // (A floating dock isn't docked itself: its windows are, one by one.)
        if tb.held && tb.dragging && !w.host && flags & WINDOW_NO_MOVE == 0 {
            let t = dock_preview(input.pointer.pos, wid.v);
            if t.node >= 0 || t.window != 0 { aimed = true; aim = t.rect; }
            // On a tab bar: into its tab there, fading as its tab shows.
            if t.bar && dock_guest_frame == frame_index {
                let r = t.rect;
                aim = gfx2d::Rect { r.x + 4.0 + t.left, r.y, t.width, tab_height() };
                into_tab = true;
            }
        }
        // Only after a drag: a click on a title over another window's
        // target doesn't dock it.
        if tb.released && last_st.laid && !w.host && w.pos != w.grab {
            let t = dock_target_at(input.pointer.pos, wid.v);
            if t.window != 0 {
                // Onto a floating window: the two in a floating dock.
                windows.insert(wid.v, w);
                dock_into_window(wid.v, t.window, t.side, t.ratio);
                return;
            }
            if t.node >= 0 {
                // Recorded docked this frame, not skipping one (which would
                // play its hiding).
                windows.insert(wid.v, w);
                dock_into(wid.v, t.node, t.side, t.ratio, t.index);
                if t.bar { tab_arrive(wid.v, t.left); }
                docked_window(wid, open, d, flags) { F(); };
                return;
            }
        }
        if tb.double_clicked && can_collapse { w.collapsed = !w.collapsed; }
        if can_collapse && interaction_for(collapse_id.v, button_d).activated { w.collapsed = !w.collapsed; }
        if closable && interaction_for(close_id.v, button_d).activated { open = false; }
    }
    if !open {
        windows.insert(wid.v, w);
        return;
    }

    // How far open it is, from 0 (rolled up) to 1. A roll runs over the
    // body's height when it was last open; without one, there is no roll.
    let title_h = if has_title { state_of(title_id.v).rect.h } else { 0.0 };
    var roll = clamp(animate(sub_id(wid, "roll"), if w.collapsed { 0.0 } else { 1.0 }, window_roll), 0.0, 1.0) as f32;
    let full_h = if w.size.y > 0.0 { w.size.y } else { w.open_h };
    let body_full = full_h - title_h;
    if body_full <= 0.0 { roll = if w.collapsed { 0.0 } else { 1.0 }; }
    if roll < 0.0005 { roll = 0.0; }
    if roll > 0.9995 { roll = 1.0; }
    let rolling = roll > 0.0 && roll < 1.0;
    if !w.collapsed && roll == 1.0 && last_st.laid { w.open_h = last.h; }

    // The grips: an edge dragged moves it, the opposite one staying put.
    let resizable = flags & WINDOW_NO_RESIZE == 0 && !w.collapsed && roll == 1.0 && last_st.laid;
    let least = float2 { max(max(title_h * 3.0, 96.0), d.dim.w.lo), max(title_h + 32.0, d.dim.h.lo) };
    if resizable {
        for g in 8 {
            let it = interaction_for(sub_id(wid, g).v, column().skin(RESIZE_GRIP).hit());
            let dir = grip_dir(g);
            if it.pressed {
                w.grab = w.pos;
                w.grab_size = float2 { last.w, last.h };
            }
            if it.held {
                // Only the axes this grip moves: the other stays as it is,
                // its content's size if that's what it was.
                var size = w.size;
                var pos = w.pos;
                for a in 2 {
                    let s = if a == 0 { dir.x } else { dir.y };
                    if s == 0 { continue; }
                    let len = max(ax(w.grab_size, a) + ax(it.drag, a) * s as f32, ax(least, a));
                    set_ax(size, a, len);
                    if s < 0 { set_ax(pos, a, ax(w.grab, a) + ax(w.grab_size, a) - len); }
                }
                w.size = size;
                w.pos = pos;
            }
            if it.hovered || it.held { wanted_cursor = grip_cursor(dir); }
        }
    }
    // On the screen: as much of it as fits.
    if last_st.laid {
        w.pos.x = clamp(w.pos.x, viewport.x, max(viewport.x + viewport.w - last.w, viewport.x));
        w.pos.y = clamp(w.pos.y, viewport.y, max(viewport.y + viewport.h - last.h, viewport.y));
    }
    windows.insert(wid.v, w);

    // The frame: its kept size, or its content's; collapsed, its title
    // bar's height and its width as it was; rolling, as much of its body
    // as has rolled out.
    var fd = column().skin(WINDOW).keep().enter(window_enter).exit(window_exit);
    // Showing, drawn in a layer, so that its parts don't show through each
    // other as it fades (a copy hiding is too).
    let m = window_enter.motion;
    if !is_instant(m) && (!last_st.laid || last_st.seen < frame_index - 1 || enter_progress(m, last_st.entered) < 1.0) {
        fd = fd.isolate();
    }
    if w.size.x > 0.0 { fd = fd.width(w.size.x); } else if w.collapsed && last.w > 0.0 { fd = fd.width(last.w); }
    if rolling { fd = fd.height(title_h + roll * body_full); }
    else if w.size.y > 0.0 && !w.collapsed { fd = fd.height(w.size.y); }
    fd.dim.w.lo = d.dim.w.lo;
    fd.dim.w.hi = d.dim.w.hi;
    if !w.collapsed && !rolling {
        fd.dim.h.lo = d.dim.h.lo;
        fd.dim.h.hi = d.dim.h.hi;
    }
    // Drawn where a dock target would put it, while on one: moving there
    // and back by the preview's motion. (Its kept place and size stay.)
    var at = w.pos;
    if dock_preview_window && last_st.laid {
        let k = animate(sub_id(wid, "dock aim"), if aimed { 1.0 } else { 0.0 }, dock_preview_motion) as f32;
        let ak = sub_id(wid, "dock area").v;
        let ta = float4 { aim.x, aim.y, aim.w, aim.h };
        // Coming from no target, it starts at the one it is on.
        if aimed { animate_lanes(ak, ta, if k > 0.0 { dock_preview_motion } else { INSTANT }, ta, true); }
        if k > 0.0001 {
            let found = anims.get(ak);
            let a = if found { found.value } else { ta };
            let size = if w.size.x > 0.0 && w.size.y > 0.0 { w.size } else { float2 { last.w, last.h } };
            let from = float4 { w.pos.x, w.pos.y, size.x, size.y };
            let r = from + (a - from) * k;
            at = float2 { r.x, r.y };
            fd = fd.size(r.z, r.w);
            fd.dim.w.lo = 0.0;
            fd.dim.h.lo = 0.0;
        }
        let gone = animate(sub_id(wid, "dock tab"), if into_tab { 1.0 } else { 0.0 }, dock_preview_motion) as f32;
        if gone > 0.0001 { fd = fd.opacity(1.0 - gone).isolate(); }
    }
    let root = open_root(ROOT_WINDOW, wid.v, Anchor { kind: ANCHOR_POINT, at: at, .. }, fd);
    id_stack.push(wid.v);
    nodes[root].scoped = true;
    if has_title {
        var td = bar_d;
        if roll == 0.0 { td = td.radius(class_style(WINDOW).normal.radius); }
        box(title_id, td) {
            if can_collapse {
                box(collapse_id, button_d) { icon(if w.collapsed { ICON_CHEVRON_RIGHT } else { ICON_CHEVRON_DOWN }); };
            }
            // Cut off, not pushing the buttons out, in a window too narrow for it.
            box(row().grow_w().clip().with_bits(SHRINKS)) { text(label_text(title)); };
            if closable { box(close_id, button_d) { icon(ICON_CLOSE); }; }
        };
    }
    if roll > 0.0 {
        var bd = d;
        bd.dim = SizeDesc { .. };
        bd.lay.absolute = false;
        // No wider than the window: what doesn't fit is cut off, not drawn past it.
        bd = bd.grow().with_bits(SHRINKS);
        if bd.vis.class.index == 0 { bd = bd.skin(WINDOW_BODY); }
        if rolling {
            // At its whole height, in a box as tall as has rolled out. The
            // box has no ID: one would scope the body's, and its widgets
            // would lose their state as it rolls.
            box(column().grow_w().height(roll * body_full).clip()) {
                window_body(flags, bd.grow_w().height(body_full)) { F(); };
            };
        } else {
            window_body(flags, bd) { F(); };
        }
    }
    // The grips last, over the edges of what is in it.
    if resizable {
        let t = class_style(RESIZE_GRIP).normal.min_size.x;
        let size = float2 { if w.size.x > 0.0 { w.size.x } else { last.w }, if w.size.y > 0.0 { w.size.y } else { last.h } };
        for g in 8 {
            let gid = sub_id(wid, g);
            let r = grip_rect(g, size, t);
            panel(gid, column().skin(RESIZE_GRIP).hit().absolute(r.x, r.y).size(r.w, r.h));
        }
    }
    close_root();
}

fn window_body<F>(flags: i64, bd: Desc) {
    if flags & WINDOW_NO_SCROLL != 0 {
        box("body", bd.clip()) { F(); };
    } else {
        scroll("body", bd) { F(); };
    }
}

// The roots in the order they are drawn and hit: the main one, the
// windows back to front, then the rest (popups, modals, tooltips) as they
// were recorded.
fn order_roots() {
    root_order.clear();
    if roots.len == 0 { return; }
    root_order.push(0);
    front_window = 0;
    // Docked windows first, in the program's dock spaces under every
    // floating one; then the floating ones, back to front, each floating
    // dock with its docked windows just over it.
    for r, k in roots {
        let ws = window_state(r.popup);
        if r.kind == ROOT_WINDOW && ws.dock >= 0 && dock_shown(ws.dock) && dock_host_of(ws.dock) == 0 {
            root_order.push(k as i32);
        }
    }
    for wid in window_order {
        let ws = window_state(wid);
        if ws.dock >= 0 && dock_shown(ws.dock) { continue; }
        for r, k in roots {
            if r.kind == ROOT_WINDOW && r.popup == wid {
                root_order.push(k as i32);
                // Not a copy of one hiding, which takes no input.
                if r.level >= 0 { front_window = wid; }
            }
        }
        if ws.host {
            for r, k in roots {
                let ds = window_state(r.popup);
                if r.kind == ROOT_WINDOW && ds.dock >= 0 && dock_shown(ds.dock) && dock_host_of(ds.dock) == wid {
                    root_order.push(k as i32);
                }
            }
        }
    }
    for r, k in roots {
        if k > 0 && r.kind != ROOT_WINDOW { root_order.push(k as i32); }
    }
}
