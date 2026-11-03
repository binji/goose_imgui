// Overlays: popups, menus, dropdowns, modals and tooltips. Each is a root
// of its own, laid out after the main tree (so it can be anchored to a
// widget recorded this frame) and drawn over it. Open popups form a stack:
// a menu's submenu is above it, a modal above everything opened before it.
// A press outside the top popups closes them; cancel closes the top one;
// a modal makes everything under it inert, and keeps the focus inside.
//
//   if imgui::button("Options") { imgui::open_popup("options"); }
//   imgui::popup("options", imgui::column().gap(6)) {
//       imgui::checkbox("Subtitles", subtitles);
//   };

namespace imgui;

import std;
import vec;
import gfx;
import gfx2d;

let POPUP_MENU = 0;
let POPUP_PLAIN = 1;
let POPUP_MODAL = 2;

struct OpenPopup {
    id: u64 = 0,
    opener: u64 = 0,            // focused when it opened; focused again when it closes
    kind: u8 = 0,
    anchor: Anchor = Anchor { .. },
    seen: i64 = 0,              // the frame it was last recorded in
}

let MAX_POPUPS = 16;
var popups: OpenPopup[..16] = [];
// Popups that are closing: their exit animation still plays.
var closing: OpenPopup[..16] = [];

// The level of the popup with `id`: 1 for the bottom one; 0 if not open.
fn popup_level(id: u64) -> i32 {
    for p, k in popups { if p.id == id { return (k + 1) as i32; } }
    0
}
fn top_popup_level() -> i32 { popups.len as i32 }
fn is_open(i: Id) -> bool { popup_level(i.v) > 0 }
fn is_open(label: const u8[:]) -> bool { is_open(id(label)) }

// The lowest level input reaches: the topmost modal's, or 0.
fn input_floor() -> i32 {
    var k = popups.len - 1;
    while k >= 0 {
        if popups[k].kind == POPUP_MODAL { return (k + 1) as i32; }
        k--;
    }
    0
}

fn open_popup_at(i: Id, kind: i64, a: Anchor) {
    let lv = popup_level(i.v);
    if lv > 0 {
        // Open already: what was opened over it closes.
        close_popups_above(lv);
        return;
    }
    // A popup opened from the main tree replaces the open ones, unless it is
    // a modal; one opened from inside a popup goes over it.
    let from = current_level();
    if kind != POPUP_MODAL { close_popups_above(from); }
    if popups.len >= MAX_POPUPS { misuse("open_popup: too many open"); return; }
    remove_closing(i.v);
    popups.push(OpenPopup { id: i.v, opener: focused, kind: kind as u8, anchor: a, seen: frame_index });
}

// A popup at the pointer.
fn open_popup(label: const u8[:]) {
    open_popup_at(id(label), POPUP_PLAIN, Anchor { kind: ANCHOR_POINT, at: input.pointer.pos, .. });
}
fn open_popup(i: Id) { open_popup_at(i, POPUP_PLAIN, Anchor { kind: ANCHOR_POINT, at: input.pointer.pos, .. }); }
// Below the last widget recorded.
fn open_popup_below(i: Id) {
    let r = state_of(last_interaction.id).screen;
    open_popup_at(i, POPUP_PLAIN, Anchor { kind: ANCHOR_BELOW, rect: r, .. });
}

fn close_popup(i: Id) {
    let lv = popup_level(i.v);
    if lv > 0 { close_popups_above(lv - 1); }
}
fn close_popup(label: const u8[:]) { close_popup(id(label)); }
// The popup being recorded, closed (from a button inside it).
fn close_current_popup() {
    let lv = current_level();
    if lv > 0 { close_popups_above(lv - 1); }
}
fn close_all_popups() { close_popups_above(0); }

// Every popup above `level` closed; the focus goes back to the lowest
// one's opener.
fn close_popups_above(level: i32) {
    if popups.len <= level { return; }
    let opener = popups[level].opener;
    while popups.len > level {
        let p = popups.pop();
        remove_closing(p.id);
        if closing.len < closing.cap { closing.push(p); }
    }
    if focused != 0 || focus_visible { focused = opener; }
}
fn close_top_popup() { if popups.len > 0 { close_popups_above((popups.len - 1) as i32); } }

fn remove_closing(id: u64) {
    var k = 0;
    while k < closing.len {
        if closing[k].id == id {
            closing[k] = closing[closing.len - 1];
            closing.pop();
        } else {
            k++;
        }
    }
}
fn closing_index(id: u64) -> i64 {
    for p, k in closing { if p.id == id { return k; } }
    -1
}

// The popup level being recorded: that of the innermost open root.
fn current_level() -> i32 {
    let p = top_parent();
    if p < 0 { return 0; }
    let r = roots[nodes[p].root];
    if r.popup == 0 { return 0; }
    popup_level(r.popup)
}

// Popups not recorded last frame have gone: closed.
fn sweep_popups() {
    var k = popups.len - 1;
    while k >= 0 {
        if popups[k].seen < frame_index - 1 {
            close_popups_above(k as i32);
        }
        k--;
    }
}

// --- the popups ----------------------------------------------------------------------------

var popup_motion = tween(0.12, EASE_OUT_CUBIC);

// The root of popup `i`, its block recorded while it is open, or closing
// (input off, fading out).
fn popup_root<F>(i: Id, kind: i64, d: Desc, c: StyleClass) {
    let lv = popup_level(i.v);
    let ci = closing_index(i.v);
    guard lv > 0 || ci >= 0;
    var a = Anchor { .. };
    if lv > 0 {
        popups[lv - 1].seen = frame_index;
        a = popups[lv - 1].anchor;
    } else {
        a = closing[ci].anchor;
    }
    let t, alive = presence(sub_id(i, "presence"), lv > 0, popup_motion);
    if !alive {
        if ci >= 0 { remove_closing(i.v); }
        return;
    }
    let level = if lv > 0 { lv } else { -1 };
    let root_kind = if kind == POPUP_MODAL { ROOT_MODAL } else { ROOT_POPUP };
    if kind == POPUP_MODAL {
        // A backdrop over the viewport, the modal centered on it.
        open_root(root_kind, i.v, Anchor { kind: ANCHOR_VIEWPORT, .. },
                  stack().skin(BACKDROP).opacity(t).with_bits(BLOCKS).center());
        roots[roots.len - 1].level = level;
        box(sub_id(i, "panel"), d.skin(c).place(CENTER, CENTER).blocks().scale(0.96 + 0.04 * t)) {
            nav_scope("modal", NAV_TRAP) { F(); };
        };
        close_root();
    } else {
        open_root(root_kind, i.v, a, column());
        roots[roots.len - 1].level = level;
        box(sub_id(i, "panel"), d.skin(c).blocks().opacity(t).offset(0, (1.0 - t) * -4.0)) {
            nav_scope("popup", NAV_TRAP | NAV_WRAP) { F(); };
        };
        close_root();
    }
}

// A popup's block, recorded while it is open (open_popup).
fn popup<F>(label: const u8[:], d: Desc) { popup_root(id(label), POPUP_PLAIN, d, POPUP) { F(); }; }
fn popup<F>(label: const u8[:]) { popup_root(id(label), POPUP_PLAIN, column(), POPUP) { F(); }; }

// A modal: centered, over a backdrop, while `open`; cancel sets `open`
// false.
fn modal<F>(label: const u8[:], open: bool&, d: Desc) {
    let i = id(label);
    let lv = popup_level(i.v);
    var st = state_of(i.v);
    if lv == 0 && st.open {
        // Closed by cancel, or from inside, since last frame.
        open = false;
    } else if open && lv == 0 {
        open_popup_at(i, POPUP_MODAL, Anchor { kind: ANCHOR_CENTER, .. });
    } else if !open && lv > 0 {
        close_popups_above(lv - 1);
    }
    st.open = open;
    st.seen = frame_index;
    put_state(i.v, st);
    popup_root(i, POPUP_MODAL, d, MODAL) { F(); };
}
fn modal<F>(label: const u8[:], open: bool&) { modal(label, open, column()) { F(); }; }
