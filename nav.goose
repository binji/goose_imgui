// Navigation: moving the focus with a gamepad's d-pad, the arrow keys and
// Tab, accepting with A or Enter, backing out with B or Escape. Focus
// moves among where focusable widgets were drawn last frame:
//
//   * a direction picks the nearest widget that way, preferring ones in
//     line with the focused one;
//   * Tab and Shift+Tab go in the order the widgets were recorded;
//   * a nav_scope keeps the focus inside it (NAV_TRAP), or wraps it around
//     at its ends (NAV_WRAP); an open popup or modal traps it;
//   * focus moved by navigation scrolls into view, and shows a focus ring,
//     which the pointer hides again (as CSS's :focus-visible).

namespace imgui;

import std;
import vec;
import math;
import dictionary;
import gfx2d;

let NAV_TRAP = 1;
let NAV_WRAP = 2;

struct Focusable { id: u64, rect: gfx2d::Rect, scope: u64, level: i32, bits: u32 }

var focusables: Focusable[>..<] = [];       // last frame's, in order
var scope_flags = dictionary<u64, u32> {};   // last frame's scopes
var next_scope_flags = dictionary<u64, u32> {};
var scope_stack: u64[>..<] = [];

var focused: u64 = 0;
var focus_visible = false;
var nav_captured = int2 { 0, 0 };
var cancel_pressed = false;
var scroll_into: u64 = 0;           // focused by navigation: to be scrolled into view
var wanted_default: u64 = 0;        // default_focus's, this frame
var default_id: u64 = 0;            // and last frame's

fn current_scope() -> u64 { if scope_stack.len > 0 { scope_stack[scope_stack.len - 1] } else { 0 } }

// The widgets recorded in the block form a scope: NAV_TRAP keeps the
// focus in it, NAV_WRAP wraps it around at the ends.
fn nav_scope<F>(label: const u8[:], flags: i64 = 0) {
    let sid = id(label).v;
    scope_stack.push(sid);
    next_scope_flags.insert(sid, flags as u32);
    defer scope_stack.pop();
    F();
}

// The widget to focus when navigation starts and nothing has focus.
fn default_focus(i: Id) { wanted_default = i.v; }
fn focus(i: Id) { focused = i.v; }
fn focus(i: Id, visible: bool) { focused = i.v; focus_visible = visible; }
fn focused_id() -> Id { Id { focused } }
fn is_focused(i: Id) -> bool { focused == i.v }
fn blur() { focused = 0; }
// Cancel (B, Escape) pressed with no popup or modal open to close.
fn cancelled() -> bool { cancel_pressed }

fn center_of(r: gfx2d::Rect) -> float2 { float2 { r.x + r.w * 0.5, r.y + r.h * 0.5 } }

// The candidates for the focus: those in the topmost popup level, in the
// focused one's scope if that traps.
fn candidate(f: Focusable, floor: i32, top: i32, trap: u64) -> bool {
    if f.bits & NAV_SKIP != 0 || f.bits & DISABLED != 0 { return false; }
    if f.level < floor { return false; }
    if top > 0 && f.level != top { return false; }
    if trap != 0 && f.scope != trap { return false; }
    true
}

// How far b is from a toward (dx, dy), or -1 if it is not that way: the
// gap along the axis, plus what is off it, more if their spans do not
// overlap across.
fn direction_score(a: gfx2d::Rect, b: gfx2d::Rect, dx: i64, dy: i64) -> f32 {
    let ca = center_of(a);
    let cb = center_of(b);
    var along: f32 = 0.0;
    var gap: f32 = 0.0;
    var off: f32 = 0.0;
    var overlap = false;
    if dx != 0 {
        along = (cb.x - ca.x) * dx;
        gap = if dx > 0 { b.x - (a.x + a.w) } else { a.x - (b.x + b.w) };
        off = abs(cb.y - ca.y);
        overlap = b.y < a.y + a.h && a.y < b.y + b.h;
    } else {
        along = (cb.y - ca.y) * dy;
        gap = if dy > 0 { b.y - (a.y + a.h) } else { a.y - (b.y + b.h) };
        off = abs(cb.x - ca.x);
        overlap = b.x < a.x + a.w && a.x < b.x + b.w;
    }
    if along <= 1.0 || gap < -0.5 * (if dx != 0 { min(a.w, b.w) } else { min(a.h, b.h) }) { return -1.0; }
    max(gap, 0.0) + off * (if overlap { 0.25 } else { 2.0 })
}

fn begin_nav() {
    let nav = input.nav;
    cancel_pressed = false;
    accept_id = 0;
    nav_captured = int2 { 0, 0 };
    scroll_into = 0;
    let floor = input_floor();
    let top = top_popup_level();
    // The focused widget is gone: nothing is focused.
    var cur = -1;
    for f, k in focusables { if f.id == focused { cur = k; } }
    if focused != 0 && cur < 0 && frame_index > 1 {
        if !node_was_kept(focused) { focused = 0; }
    }
    let moving = nav.up || nav.down || nav.left || nav.right || nav.next || nav.prev;
    if moving || nav.accept { focus_visible = true; }
    var trap: u64 = 0;
    if cur >= 0 {
        let sc = focusables[cur].scope;
        let fl = scope_flags.get(sc);
        if fl { if fl & NAV_TRAP != 0 { trap = sc; } }
    }
    // A focus outside what may be focused now (a popup opened over it) moves
    // into it on the first navigation.
    // The focus on the title of the open bar menu (it was clicked open):
    // left and right go to the menus beside it, as they do from inside it.
    if top > 0 && focused != 0 && popups[0].header == focused && (nav.left || nav.right) {
        if switch_bar_menu(if nav.left { -1 } else { 1 }) { focus_visible = true; return; }
    }
    if cur >= 0 && !candidate(focusables[cur], floor, top, trap) {
        cur = -1;
        // Showing focus: it moves into the popup at once.
        if focus_visible {
            let first = first_candidate(floor, top);
            if first != 0 { focused = first; }
        }
    }
    if nav.cancel {
        if top > 0 { close_top_popup(); } else { cancel_pressed = true; }
    }
    if cur < 0 {
        if moving || nav.accept {
            let first = first_candidate(floor, top);
            if first != 0 {
                focused = first;
                scroll_into = first;
            }
        }
        return;
    }
    let f = focusables[cur];
    // What the focused widget takes for itself.
    var up = nav.up;
    var down = nav.down;
    var left = nav.left;
    var right = nav.right;
    if f.bits & CAPTURE_X != 0 {
        nav_captured.x = ((if right { 1 } else { 0 }) - (if left { 1 } else { 0 })) as i32;
        left = false;
        right = false;
    }
    if f.bits & CAPTURE_Y != 0 {
        nav_captured.y = ((if down { 1 } else { 0 }) - (if up { 1 } else { 0 })) as i32;
        up = false;
        down = false;
    }
    if nav.accept { accept_id = f.id; }
    // In a submenu, left goes back to the menu it opened from.
    if left && top >= 2 && popups[top - 1].kind == POPUP_MENU && popups[top - 2].kind == POPUP_MENU {
        close_top_popup();
        return;
    }
    // In a menu bar's menu, left and right go to the menu next to it (right
    // on an item with a submenu opens that instead).
    if (left || (right && !opens_submenu(f.id))) && switch_bar_menu(if left { -1 } else { 1 }) { return; }
    var dx = 0;
    var dy = 0;
    if left { dx = -1; } else if right { dx = 1; } else if up { dy = -1; } else if down { dy = 1; }
    var to: u64 = 0;
    if dx != 0 || dy != 0 {
        var best = -1.0;
        for c in focusables {
            if c.id == f.id || !candidate(c, floor, top, trap) { continue; }
            let s = direction_score(f.rect, c.rect, dx, dy);
            if s >= 0.0 && (best < 0.0 || s < best) { best = s; to = c.id; }
        }
        let fl = scope_flags.get(f.scope);
        let wraps = top > 0 || (if fl { fl & NAV_WRAP != 0 } else { false });
        if to == 0 && wraps {
            // Around: the one furthest the other way, most in line.
            var best_far = -1.0e30;
            for c in focusables {
                if c.id == f.id || !candidate(c, floor, top, trap) { continue; }
                if top == 0 && c.scope != f.scope { continue; }
                let cc = center_of(c.rect);
                let cf = center_of(f.rect);
                let far = if dx != 0 { (cf.x - cc.x) * dx } else { (cf.y - cc.y) * dy };
                let off = if dx != 0 { abs(cc.y - cf.y) } else { abs(cc.x - cf.x) };
                let s = far - off * 2.0;
                if far > 1.0 && s > best_far { best_far = s; to = c.id; }
            }
        }
    } else if nav.next || nav.prev {
        let n = focusables.len;
        let step = if nav.next { 1 } else { n - 1 };
        var k = (cur + step) % n;
        while k != cur {
            if candidate(focusables[k], floor, top, trap) { to = focusables[k].id; break; }
            k = (k + step) % n;
        }
    }
    if to != 0 {
        focused = to;
        scroll_into = to;
    }
}

fn first_candidate(floor: i32, top: i32) -> u64 {
    if default_id != 0 {
        for f in focusables { if f.id == default_id && candidate(f, floor, top, 0) { return f.id; } }
    }
    for f in focusables { if candidate(f, floor, top, 0) { return f.id; } }
    0
}

// A focused widget that was not drawn last frame (it is being recorded
// for the first time, focused by the program) keeps its focus a frame.
fn node_was_kept(id: u64) -> bool { !was_seen(id) }

// Called at the end of the frame: this frame's scopes are the next's.
fn end_nav() {
    scope_flags.clear();
    next_scope_flags.each() { k, v => scope_flags.insert(k, v); };
    next_scope_flags.clear();
    default_id = wanted_default;
    wanted_default = 0;
    scope_stack.clear();
}
