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
    header: u64 = 0,            // the widget that opens and closes it (a menu's title), if any
    bar: u64 = 0,               // a menu's: the menu bar it belongs to
    linger: f32 = 0.0,          // a submenu's: how long the pointer has been away from it
}

// What an open popup knows lives with it here, not in its ID's state,
// which is dropped when nothing records the ID for a while.
fn set_popup_bar(i: Id, bar: u64) {
    let lv = popup_level(i.v);
    if lv > 0 { popups[lv - 1].bar = bar; }
}

// The widget that toggles popup `i`: a press on it leaves the popup open
// for the widget's click to close, not closed by the press and reopened.
fn set_popup_header(i: Id, header: u64) {
    let lv = popup_level(i.v);
    if lv > 0 { popups[lv - 1].header = header; }
}
// The level to keep open when `id` is pressed: its own popup's, or the
// one it is the header of.
fn level_kept_by(id: u64, level: i32) -> i32 {
    var keep = level;
    for p, k in popups { if id != 0 && p.header == id { keep = max(keep, (k + 1) as i32); } }
    keep
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
    ui_event(UI_OPEN, i.v, popup_class(kind));
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
// The menu being recorded and the menus it opened from: chosen, an item is
// done with them, not with a modal or popup they are over.
fn close_menus() {
    var lv = current_level();
    while lv >= 2 && popups[lv - 2].kind == POPUP_MENU { lv--; }
    if lv > 0 { close_popups_above(lv - 1); }
}

// Every popup above `level` closed; the focus goes back to the lowest
// one's opener.
fn close_popups_above(level: i32) {
    if popups.len <= level { return; }
    let opener = popups[level].opener;
    while popups.len > level {
        let p = popups.pop();
        ui_event(UI_CLOSE, p.id, popup_class(p.kind));
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
            // A modal not recorded opens again when it is: `open` says.
            for j in k..popups.len {
                if popups[j].kind == POPUP_MODAL {
                    var ms = state_of(popups[j].id);
                    ms.open = false;
                    put_state(popups[j].id, ms);
                }
            }
            close_popups_above(k as i32);
        }
        k--;
    }
}

// --- the popups ----------------------------------------------------------------------------

var popup_motion = tween(0.12, EASE_OUT_CUBIC);

// The root of popup `i`, its block recorded while it is open, or closing
// (input off, fading out).
fn popup_root<F>(i: Id, kind: i64, d: Desc, c: StyleClass, anchor_node: i32 = -1) {
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
    if anchor_node >= 0 { a.node = anchor_node; }
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

// --- menus ------------------------------------------------------------------------------

// How long a submenu stays open once the pointer has left it and its item.
let SUBMENU_LINGER: f32 = 0.35;

struct MenuCtx { bar: u64, in_popup: bool }
var menu_stack: MenuCtx[>..<] = [];

// The menus of the menu bars, in order, and the items that open
// submenus: this frame's, and last frame's (for navigation, which comes
// first).
struct BarMenu { bar: u64, header: u64, popup: u64 }
var bar_menus: BarMenu[>..<] = [];
var last_bar_menus: BarMenu[>..<] = [];
var submenu_items: u64[>..<] = [];
var last_submenu_items: u64[>..<] = [];

fn begin_menus() {
    last_bar_menus.clear();
    for m in bar_menus { last_bar_menus.push(m); }
    bar_menus.clear();
    last_submenu_items.clear();
    for m in submenu_items { last_submenu_items.push(m); }
    submenu_items.clear();
}

// Left or right in a menu bar's open menu: that bar's menu before or
// after it opens instead (wrapping around), its header focused. False if
// the top-level popup is not a bar's menu.
fn switch_bar_menu(step: i64) -> bool {
    guard popups.len > 0 && popups[0].kind == POPUP_MENU else { return false; }
    var k = -1;
    for m, j in last_bar_menus { if m.popup == popups[0].id { k = j; } }
    guard k >= 0 else { return false; }
    let bar = last_bar_menus[k].bar;
    let n = last_bar_menus.len;
    var j = k;
    loop {
        j = (j + step + n) % n;
        if j == k { return false; }
        if last_bar_menus[j].bar == bar { break; }
    }
    let m = last_bar_menus[j];
    close_popups_above(0);
    focused = m.header;
    open_popup_at(Id { m.popup }, POPUP_MENU, Anchor { kind: ANCHOR_BELOW, rect: state_of(m.header).screen, .. });
    set_popup_header(Id { m.popup }, m.header);
    set_popup_bar(Id { m.popup }, bar);
    true
}
fn opens_submenu(id: u64) -> bool {
    for m in last_submenu_items { if m == id { return true; } }
    false
}

// A row of menus along the top of a window or screen.
fn menu_bar<F>(label: const u8[:], d: Desc = row()) {
    let i = id(label);
    menu_stack.push(MenuCtx { i.v, false });
    defer menu_stack.pop();
    box(i, d.skin(MENU_BAR).grow_w().align(CENTER)) {
        nav_scope("menu bar", NAV_WRAP) { F(); };
    };
}

// Whether one of the bar's menus is open: hovering another then opens it.
fn bar_menu_open(bar: u64) -> bool {
    for p in popups { if p.kind == POPUP_MENU && p.bar == bar { return true; } }
    false
}

// A menu: a header in a menu bar (or an item in another menu, for a
// submenu), and its items in a popup while it is open. True while open.
fn menu<F>(label: const u8[:]) -> bool {
    let i = id(label);
    let pid = sub_id(i, "menu");
    let ctx = if menu_stack.len > 0 { menu_stack[menu_stack.len - 1] } else { MenuCtx { 0, false } };
    let nested = current_level() > 0;
    var open = popup_level(pid.v) > 0;
    let hd = if nested { clickable(row().skin(MENU_ITEM).grow_w().align(CENTER)) } else { clickable(row().skin(MENU_HEADER).align(CENTER)) };
    let it = interact(i, hd.look(checked_look(open)));
    var opening = false;
    if it.activated {
        if open { close_popup(pid); open = false; } else { opening = true; }
    } else if nested && it.focused && input.nav.right && !open {
        // Right on a submenu's item opens it (and the focus goes into it).
        opening = true;
    } else if it.hovered && !open && pointer_moved {
        // Hovered (by a pointer that moved there, not one resting where the
        // keyboard took the menu from): a submenu opens; a bar's menu opens
        // if another of the bar's is.
        if nested || (ctx.bar != 0 && bar_menu_open(ctx.bar)) { opening = true; }
    }
    if opening {
        let a = Anchor { kind: if nested { ANCHOR_RIGHT } else { ANCHOR_BELOW }, rect: it.rect, .. };
        open_popup_at(pid, POPUP_MENU, a);
        set_popup_header(pid, i.v);
        set_popup_bar(pid, ctx.bar);
        open = true;
    }
    if nested && open && !opening {
        // The pointer gone from the submenu and its item (and from any
        // submenu of its own) a moment: it closes.
        let p = input.pointer.pos;
        let panel_rect = state_of(sub_id(pid, "panel").v).screen;
        let deeper = popup_level(pid.v) < top_popup_level();
        let near = inside(it.rect, p) || inside(panel_rect, p) || deeper || focus_visible;
        let lv = popup_level(pid.v);
        let away = if near { 0.0 } else { popups[lv - 1].linger + delta as f32 };
        popups[lv - 1].linger = away;
        if away > SUBMENU_LINGER {
            close_popup(pid);
            open = false;
        }
    }
    if nested { submenu_items.push(i.v); } else if ctx.bar != 0 { bar_menus.push(BarMenu { ctx.bar, i.v, pid.v }); }
    let header = nodes.len as i32;
    box(i, hd.look(checked_look(open))) {
        text(label_text(label), column().grow_w());
        if nested { icon(ICON_CHEVRON_RIGHT); }
    };
    menu_stack.push(MenuCtx { ctx.bar, true });
    popup_root(pid, POPUP_MENU, column().min_w(160), MENU, header) { F(); };
    menu_stack.pop();
    open
}

// An item in a menu: true the frame it is chosen, which closes the menus.
fn menu_item(label: const u8[:], shortcut: const u8[:] = "") -> bool {
    let i = id(label);
    let it = box(i, clickable(row().skin(MENU_ITEM).grow_w().align(CENTER))) {
        text(label_text(label), column().grow_w());
        if shortcut.len > 0 { text(shortcut, column().skin(MUTED)); }
    };
    // Hovering an item closes a sibling's submenu.
    let lv = current_level();
    if it.hovered && pointer_moved && lv > 0 && popups.len > lv {
        close_popups_above(lv);
    }
    if it.activated { close_menus(); }
    it.activated
}
// An item with a check mark, toggling `v`.
fn menu_check(label: const u8[:], v: bool&) -> bool {
    let i = id(label);
    let it = box(i, clickable(row().skin(MENU_ITEM).grow_w().align(CENTER).gap(8))) {
        icon(ICON_CHECK, column().opacity(if v { 1.0 } else { 0.0 }));
        text(label_text(label), column().grow_w());
    };
    if it.activated {
        v = !v;
        close_menus();
    }
    it.activated
}

// --- context menus ------------------------------------------------------------------------

// A menu at the pointer when the widget `it` is the interaction of is
// right-clicked; its items recorded by the block while it is open. True
// while open.
//   if imgui::selectable(name, chosen == k) { chosen = k; }
//   imgui::context_menu(imgui::last_item()) {
//       if imgui::menu_item("Rename") { … }
//       if imgui::menu_item("Delete") { … }
//   };
fn context_menu<F>(it: Interaction, d: Desc = column().min_w(140)) -> bool {
    let pid = Id { hash_combine(it.id, 0xC0273E) };
    if it.id != 0 && hot == it.id && input.pointer.secondary {
        let a = Anchor { kind: ANCHOR_POINT, at: input.pointer.pos, .. };
        let lv = popup_level(pid.v);
        if lv > 0 {
            // Open already: again where the pointer is now.
            close_popups_above(lv);
            popups[lv - 1].anchor = a;
        } else {
            open_popup_at(pid, POPUP_MENU, a);
        }
    }
    menu_stack.push(MenuCtx { 0, true });
    popup_root(pid, POPUP_MENU, d, MENU) { F(); };
    menu_stack.pop();
    popup_level(pid.v) > 0
}

// --- dropdowns ----------------------------------------------------------------------------

// One of `items`, shown in a button; the list in a popup under it.
fn dropdown(label: const u8[:], items: const u8[:][:], selected: i64&) -> bool {
    dropdown(label, items, selected, row())
}
fn dropdown(label: const u8[:], items: const u8[:][:], selected: i64&, d: Desc) -> bool {
    let i = id(label);
    let pid = sub_id(i, "list");
    var open = popup_level(pid.v) > 0;
    let hd = clickable(d.skin(DROPDOWN).align(CENTER));
    let it = interact(i, hd.look(checked_look(open)));
    if it.activated {
        if open {
            close_popup(pid);
            open = false;
        } else {
            open_popup_at(pid, POPUP_MENU, Anchor { kind: ANCHOR_BELOW, rect: it.rect, .. });
            set_popup_header(pid, i.v);
            open = true;
            // The chosen item takes the focus, for the arrows to move from.
            if selected >= 0 && selected < items.len {
                id_scope(pid) { focused = id(selected).v; };
            }
        }
    }
    let shown = if selected >= 0 && selected < items.len { items[selected] } else { "" };
    let header = nodes.len as i32;
    let width = state_of(i.v).rect.w;
    box(i, hd.look(checked_look(open))) {
        text(label_text(shown), column().grow_w());
        icon(ICON_CHEVRON_DOWN, column().opacity(0.7));
    };
    let before = selected;
    popup_root(pid, POPUP_MENU, column().min_w(width), MENU, header) {
        id_scope(pid) {
            for item, k in items {
                let ok = box(k, clickable(row().skin(MENU_ITEM).grow_w().align(CENTER))
                                    .look(checked_look(k == selected))) {
                    text(label_text(item));
                };
                if ok.activated {
                    selected = k;
                    close_popup(pid);
                }
            }
        };
    };
    selected != before
}

// --- tooltips ---------------------------------------------------------------------------------

let TOOLTIP_DELAY = 0.5;

// A tooltip for the widget `it` is the interaction of: shown under it after
// the pointer has rested on it a moment (or the focus, by navigation).
fn tooltip<F>(it: Interaction) {
    let tid = Id { hash_combine(it.id, 0x7001) };
    var st = state_of(tid.v);
    let on = it.hovered || (it.focused && focus_visible);
    st.value = if on { st.value + delta as f32 } else { 0.0 };
    st.seen = frame_index;
    put_state(tid.v, st);
    let t, alive = presence(tid, on && st.value >= TOOLTIP_DELAY, tween(0.1));
    guard alive;
    open_root(ROOT_TOOLTIP, tid.v, Anchor { kind: ANCHOR_BELOW, rect: it.rect, .. }, column());
    roots[roots.len - 1].level = -1;
    box(column().skin(TOOLTIP).opacity(t).max_w(320)) { F(); };
    close_root();
}
fn tooltip(it: Interaction, s: const u8[:]) { tooltip(it) { text(s, column().wrap()); }; }
