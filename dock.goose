// Docking: windows held in a dock space, a tree of splits whose leaves each
// show their windows' tabs and the selected one's body. A floating window
// dragged by its title over a dock space shows where it would go: by a
// leaf's edge, splitting it; in its middle, a tab with the others. Let go,
// it docks. A tab dragged out floats its window again, still held.
//
//   imgui::dock_space("main", imgui::column().grow());
//   imgui::window("Scene") { … };          // docked or not, recorded the same
//   // a layout to start with, once:
//   imgui::dock_window("Scene", "main", imgui::DOCK_LEFT, 0.25);
//   imgui::dock_window_with("Log", "Scene", imgui::DOCK_BOTTOM, 0.4);

namespace imgui;

import std;
import vec;
import math;
import dictionary;
import gfx2d;

let DOCK_CENTER = 0;        // a tab with the others
let DOCK_LEFT = 1;
let DOCK_RIGHT = 2;
let DOCK_TOP = 3;
let DOCK_BOTTOM = 4;

let DOCK_TABS = 8;          // windows in one leaf, at most

struct DockNode {
    space: u64 = 0,             // its dock space
    parent: i32 = -1,
    a: i32 = -1,                // a split's: left or top
    b: i32 = -1,                // right or bottom
    axis: i8 = -1,              // -1: a leaf; 0: a and b side by side; 1: one above the other
    ratio: f32 = 0.5,           // a's share of a split
    tabs: u64[..8] = [],        // a leaf's windows, in order
    selected: u64 = 0,          // the one shown
    hide_tabs: bool = false,    // a leaf's tab bar hidden (its tab's menu): a button in its corner shows it
    used: bool = false,
}

// Every dock node, of every space; unused ones are taken again before the
// array grows (it never shrinks).
var dock_nodes: DockNode[>..] = [];
var dock_roots = dictionary<u64, i32> {};
var dock_spaces: u64[>..<] = [];
// Floating docks: each space's window, by the space's ID.
var space_host = dictionary<u64, u64> {};

// The floating dock node n is in (its window's ID), or 0.
fn dock_host_of(n: i32) -> u64 {
    guard n >= 0 && n < dock_nodes.len else { return 0; }
    let h = space_host.get(dock_nodes[n].space);
    if h { return h; }
    0
}
fn host_space(h: u64) -> u64 { hash_combine(h, 0x5ACE) }

fn new_dock_node(space: u64) -> i32 {
    for n, k in dock_nodes {
        if !n.used {
            dock_nodes[k] = DockNode { space: space, used: true, .. };
            return k as i32;
        }
    }
    dock_nodes.push(DockNode { space: space, used: true, .. });
    (dock_nodes.len - 1) as i32
}

// The root node of space `space`, made (an empty leaf) the first time.
fn dock_root(space: u64) -> i32 {
    let found = dock_roots.get(space);
    if found { return found; }
    let r = new_dock_node(space);
    dock_roots.insert(space, r);
    dock_spaces.push(space);
    r
}

// Whether node n's space was laid out last frame or this: its windows are
// shown in it; if not, they float.
fn dock_shown(n: i32) -> bool {
    guard n >= 0 && n < dock_nodes.len && dock_nodes[n].used else { return false; }
    let st = state_of(dock_nodes[n].space);
    st.laid && st.seen >= frame_index - 1
}

// A window's tab shows if the window was called for this frame or last.
fn tab_live(w: u64) -> bool { window_state(w).called >= frame_index - 1 }

// The rect of node n: its space's, divided by the splits above it.
fn dock_rect(n: i32) -> gfx2d::Rect {
    var path: i32[..32] = [];
    var q = n;
    while q >= 0 && path.len < path.cap {
        path.push(q);
        q = dock_nodes[q].parent;
    }
    var r = state_of(dock_nodes[n].space).rect;
    let t = class_style(SPLITTER).normal.min_size.x;
    var k = path.len - 1;
    while k > 0 {
        let p = dock_nodes[path[k]];
        let child = path[k - 1];
        if p.axis == 0 {
            let wa = max((r.w - t) * p.ratio, 0.0);
            r = if child == p.a { gfx2d::Rect { r.x, r.y, wa, r.h } }
                else { gfx2d::Rect { r.x + wa + t, r.y, max(r.w - wa - t, 0.0), r.h } };
        } else {
            let ha = max((r.h - t) * p.ratio, 0.0);
            r = if child == p.a { gfx2d::Rect { r.x, r.y, r.w, ha } }
                else { gfx2d::Rect { r.x, r.y + ha + t, r.w, max(r.h - ha - t, 0.0) } };
        }
        k--;
    }
    r
}

fn tab_height() -> f32 { class_style(DOCK_TAB).normal.min_size.y }
// Leaf n's tab bar's height: 0 if it is hidden.
fn bar_height(n: i32) -> f32 { if dock_nodes[n].hide_tabs { 0.0 } else { tab_height() } }

// --- changing the tree --------------------------------------------------------------------

// Window w added to leaf n's tabs, before the one at `at` (-1: after
// them all), and shown. A leaf already full: it stays floating.
fn dock_into_leaf(w: u64, n: i32, at: i64 = -1) {
    guard dock_nodes[n].tabs.len < DOCK_TABS else { misuse("dock: a leaf has at most 8 windows"); return; }
    dock_nodes[n].tabs.push(w);
    if at >= 0 {
        var k = dock_nodes[n].tabs.len - 1;
        while k > at {
            dock_nodes[n].tabs[k] = dock_nodes[n].tabs[k - 1];
            k--;
        }
        dock_nodes[n].tabs[k] = w;
    }
    dock_nodes[n].selected = w;
    var ws = window_state(w);
    ws.dock = n;
    windows.insert(w, ws);
}

// Node n's content (its tabs, or its children) moved to node m.
fn move_dock_content(n: i32, m: i32) {
    let src = dock_nodes[n];
    dock_nodes[m].axis = src.axis;
    dock_nodes[m].ratio = src.ratio;
    dock_nodes[m].a = src.a;
    dock_nodes[m].b = src.b;
    dock_nodes[m].tabs = src.tabs;
    dock_nodes[m].selected = src.selected;
    dock_nodes[m].hide_tabs = src.hide_tabs;
    if src.a >= 0 { dock_nodes[src.a].parent = m; }
    if src.b >= 0 { dock_nodes[src.b].parent = m; }
    for w in src.tabs {
        var ws = window_state(w);
        ws.dock = m;
        windows.insert(w, ws);
    }
}

// Window w docked at node n: in it as a tab (DOCK_CENTER), or beside it on
// `side`, taking `ratio` of its length. As a tab, it goes before the tab
// at `at` (-1: after them all). A window docked elsewhere leaves there
// first.
fn dock_into(w: u64, n: i32, side: i64, ratio: f64, at: i64 = -1) {
    undock_id(w);
    guard n >= 0 && dock_nodes[n].used;
    let empty = dock_nodes[n].axis < 0 && dock_nodes[n].tabs.len == 0;
    if side == DOCK_CENTER || empty {
        // Into a split: its leaf with the most room.
        var leaf = n;
        while dock_nodes[leaf].axis >= 0 {
            let p = dock_nodes[leaf];
            leaf = if p.ratio >= 0.5 { p.a } else { p.b };
        }
        dock_into_leaf(w, leaf, if leaf == n { at } else { -1 });
        return;
    }
    // n becomes a split of what it held and a new leaf.
    let space = dock_nodes[n].space;
    let old = new_dock_node(space);
    move_dock_content(n, old);
    dock_nodes[old].parent = n;
    let leaf = new_dock_node(space);
    dock_nodes[leaf].parent = n;
    dock_nodes[n].tabs.clear();
    dock_nodes[n].selected = 0;
    dock_nodes[n].hide_tabs = false;
    dock_nodes[n].axis = if side == DOCK_LEFT || side == DOCK_RIGHT { 0 } else { 1 };
    let r = clamp(ratio, 0.05, 0.95) as f32;
    if side == DOCK_LEFT || side == DOCK_TOP {
        dock_nodes[n].a = leaf;
        dock_nodes[n].b = old;
        dock_nodes[n].ratio = r;
    } else {
        dock_nodes[n].a = old;
        dock_nodes[n].b = leaf;
        dock_nodes[n].ratio = 1.0 - r;
    }
    dock_into_leaf(w, leaf);
}

// Window w out of its dock: a leaf left empty goes, its sibling taking
// its parent's place.
fn undock_id(w: u64) {
    var ws = window_state(w);
    let n = ws.dock;
    guard n >= 0 && n < dock_nodes.len;
    ws.dock = -1;
    // Floating where it was docked, as big, if it has never floated.
    if dock_shown(n) && ws.size == float2_0 {
        let r = dock_rect(n);
        ws.pos = float2 { r.x + 16.0, r.y + 16.0 };
        ws.size = float2 { max(r.w, 160.0), max(r.h, 120.0) };
    }
    windows.insert(w, ws);
    var k = 0;
    while k < dock_nodes[n].tabs.len {
        if dock_nodes[n].tabs[k] == w {
            for j in k..dock_nodes[n].tabs.len - 1 { dock_nodes[n].tabs[j] = dock_nodes[n].tabs[j + 1]; }
            dock_nodes[n].tabs.pop();
        } else {
            k++;
        }
    }
    if dock_nodes[n].selected == w { dock_nodes[n].selected = if dock_nodes[n].tabs.len > 0 { dock_nodes[n].tabs[0] } else { 0 }; }
    let p = dock_nodes[n].parent;
    if dock_nodes[n].tabs.len > 0 || p < 0 { return; }
    let other = if dock_nodes[p].a == n { dock_nodes[p].b } else { dock_nodes[p].a };
    move_dock_content(other, p);
    dock_nodes[other].used = false;
    dock_nodes[n].used = false;
}

// --- the program's -----------------------------------------------------------------------

// Window `title` docked in space `space` (both as labels at the top
// level), on `side` of all that is there, taking `ratio` of it; DOCK_CENTER:
// a tab in its biggest leaf. For a layout to start with.
fn dock_window(title: const u8[:], space: const u8[:], side: i64, ratio: f64 = 0.5) {
    let w = id(title).v;
    if !windows.contains(w) { window_order.push(w); windows.insert(w, WindowState { .. }); }
    dock_into(w, dock_root(id(space).v), side, ratio);
}
// Window `title` docked by window `other`: a tab with it, or beside it.
// If `other` floats, the two go in a floating dock where it is.
fn dock_window_with(title: const u8[:], other: const u8[:], side: i64, ratio: f64 = 0.5) {
    let w = id(title).v;
    if !windows.contains(w) { window_order.push(w); windows.insert(w, WindowState { .. }); }
    let o = id(other).v;
    if !windows.contains(o) { window_order.push(o); windows.insert(o, WindowState { .. }); }
    let n = window_state(o).dock;
    if n < 0 {
        dock_into_window(w, o, side, ratio);
        return;
    }
    dock_into(w, n, side, ratio);
}
fn undock_window(title: const u8[:]) { undock_id(id(title).v); }
fn is_docked(title: const u8[:]) -> bool { window_state(id(title).v).dock >= 0 }

// --- where a dragged window would go ------------------------------------------------------

struct DockTarget {
    window: u64 = 0,            // a floating window it docks with, in a floating dock; or
    node: i32 = -1,             // where it docks: a leaf, or a space's root (by its outer edges)
    side: i64 = 0,
    ratio: f64 = 0.5,           // of the node it takes
    rect: gfx2d::Rect = gfx2d::Rect { 0.0, 0.0, 0.0, 0.0 },    // the area it would take
    index: i64 = -1,            // dropped on a tab bar: the tab it goes before (-1: after them all)
    mark: f32 = 0.0,            // and where, along the bar
}

// The targets a window dragged over a dock space aims at: a cross of five
// on the leaf under the pointer (its middle: a tab; its four sides: half of
// it, beside what is there), and, if the space is split, four by the
// space's outer edges (a side of all of it). Only the middle, on an empty
// leaf. Each is a square; `at` is its rect.
struct DockAim { target: DockTarget = DockTarget { .. }, at: gfx2d::Rect = gfx2d::Rect { 0.0, 0.0, 0.0, 0.0 } }
var dock_aims: DockAim[..9] = [];
// The tab bar under the pointer, if any (its node: -1 if none): dropped
// there, a window goes in as a tab, between the tabs it is dropped between.
var dock_bar: DockTarget = DockTarget { .. };

// The part of r a window docked on `side` of it, taking `ratio`, would take.
fn side_rect(r: gfx2d::Rect, side: i64, ratio: f64) -> gfx2d::Rect {
    let f = ratio as f32;
    match side {
        DOCK_LEFT => gfx2d::Rect { r.x, r.y, r.w * f, r.h },
        DOCK_RIGHT => gfx2d::Rect { r.x + r.w * (1.0 - f), r.y, r.w * f, r.h },
        DOCK_TOP => gfx2d::Rect { r.x, r.y, r.w, r.h * f },
        DOCK_BOTTOM => gfx2d::Rect { r.x, r.y + r.h * (1.0 - f), r.w, r.h * f },
        _ => r,
    }
}

fn add_aim(c: float2, t: DockTarget) {
    let s = class_style(DOCK_TARGET).normal.min_size.x;
    if dock_aims.len < dock_aims.cap { dock_aims.push(DockAim { t, gfx2d::Rect { c.x - s * 0.5, c.y - s * 0.5, s, s } }); }
}

// A cross of five on r, its middle at its center, each a target of `t`
// (for its side and its part of r): its sides only if `sides`, its middle
// only if `middle`.
fn add_cross(r: gfx2d::Rect, t: DockTarget, sides: bool, middle: bool = true) {
    let s = class_style(DOCK_TARGET).normal.min_size.x;
    let k = s * 1.2;
    let c = float2 { r.x + r.w * 0.5, r.y + r.h * 0.5 };
    fn one(at: float2, side: i64) {
        var u = t;
        u.side = side;
        u.ratio = if side == DOCK_CENTER { 1.0 } else { 0.5 };
        u.rect = side_rect(r, side, u.ratio);
        add_aim(at, u);
    }
    if middle { one(c, DOCK_CENTER); }
    if sides {
        one(c - float2 { k, 0.0 }, DOCK_LEFT);
        one(c + float2 { k, 0.0 }, DOCK_RIGHT);
        one(c - float2 { 0.0, k }, DOCK_TOP);
        one(c + float2 { 0.0, k }, DOCK_BOTTOM);
    }
}

// Space sp's targets for a window dragged to p, if p is over it.
fn space_aims(sp: u64, p: float2) -> bool {
    let root = dock_root(sp);
    guard dock_shown(root) else { return false; }
    let space = dock_rect(root);
    guard inside(space, p) else { return false; }
    var n = root;
    while dock_nodes[n].axis >= 0 {
        let a = dock_nodes[n].a;
        n = if inside(dock_rect(a), p) { a } else { dock_nodes[n].b };
    }
    var live = 0;
    for w in dock_nodes[n].tabs { if tab_live(w) { live++; } }
    let leaf = dock_rect(n);
    let bh = bar_height(n);
    // A full leaf takes no more tabs.
    let room = dock_nodes[n].tabs.len < DOCK_TABS;
    if room && live > 0 && bh > 0.0 && p.y < leaf.y + bh {
        // On its tab bar: before the first tab whose middle is past p.
        var at: i64 = -1;
        var x = leaf.x + 4.0;
        for w, k in dock_nodes[n].tabs {
            if !tab_live(w) { continue; }
            let r = state_of(sub_id(Id { w }, "tab").v).screen;
            if at < 0 && p.x < r.x + r.w * 0.5 {
                at = k;
                x = r.x - 1.0;
            }
            if at < 0 { x = r.x + r.w + 1.0; }
        }
        dock_bar = DockTarget { node: n, side: DOCK_CENTER, ratio: 1.0, rect: leaf, index: at, mark: x, .. };
    }
    add_cross(dock_rect(n), DockTarget { node: n, .. }, live > 0, room);
    if dock_nodes[root].axis >= 0 {
        let m = class_style(DOCK_TARGET).normal.min_size.x * 0.5 + 8.0;
        let sc = float2 { space.x + space.w * 0.5, space.y + space.h * 0.5 };
        fn edge(at: float2, side: i64) {
            add_aim(at, DockTarget { node: root, side: side, ratio: 0.25, rect: side_rect(space, side, 0.25), .. });
        }
        edge(float2 { space.x + m, sc.y }, DOCK_LEFT);
        edge(float2 { space.x + space.w - m, sc.y }, DOCK_RIGHT);
        // (The top one below the tab bars, which are targets too.)
        edge(float2 { sc.x, space.y + tab_height() + m }, DOCK_TOP);
        edge(float2 { sc.x, space.y + space.h - m }, DOCK_BOTTOM);
    }
    true
}

// The targets for window `dragged`, dragged to p, in dock_aims: those of the
// floating window in front under p (a floating dock's, its space's; any
// other's, a cross on it, docking the two together), else of the dock
// space under p; none if there is neither.
fn find_dock_aims(p: float2, dragged: u64) {
    dock_aims.clear();
    dock_bar = DockTarget { .. };
    var k = window_order.len - 1;
    while k >= 0 {
        let w = window_order[k];
        k--;
        if w == dragged { continue; }
        let ws = window_state(w);
        if ws.dock >= 0 && dock_shown(ws.dock) { continue; }
        let st = state_of(w);
        if st.seen < frame_index - 1 || !inside(st.screen, p) { continue; }
        if ws.host {
            space_aims(host_space(w), p);
            return;
        }
        add_cross(st.screen, DockTarget { window: w, .. }, true);
        return;
    }
    for sp in dock_spaces {
        if space_host.contains(sp) { continue; }
        if space_aims(sp, p) { return; }
    }
}

// The target under p, if any, of a window dragged there.
fn dock_target_at(p: float2, dragged: u64) -> DockTarget {
    find_dock_aims(p, dragged);
    for a in dock_aims { if inside(a.at, p) { return a.target; } }
    dock_bar
}

// How the area a dragged window would take is shown: outlined, or (with
// `window`) the window drawn there, moving there and back by `m`.
var dock_preview_window = false;
var dock_preview_motion = INSTANT;
fn set_dock_preview(window: bool, m: Motion = INSTANT) {
    dock_preview_window = window;
    dock_preview_motion = m;
}

// The targets of a window dragged to p, over everything; and the area the
// one under p would give it, outlined unless the window is to be drawn
// there. The target under p, if any.
fn dock_preview(p: float2, dragged: u64) -> DockTarget {
    find_dock_aims(p, dragged);
    guard dock_aims.len > 0 else { return DockTarget { .. }; }
    var hit = -1;
    for a, k in dock_aims { if inside(a.at, p) { hit = k; } }
    let bar = hit < 0 && dock_bar.node >= 0;
    let outline = !dock_preview_window;
    open_root(ROOT_TOOLTIP, hash_combine(ROOT_ID, 0xD0C4), Anchor { kind: ANCHOR_POINT, at: float2 { viewport.x, viewport.y }, .. },
              column().size(viewport.w, viewport.h));
    roots[roots.len - 1].level = -1;
    if hit >= 0 && outline {
        let r = dock_aims[hit].target.rect;
        panel(column().skin(DOCK_PREVIEW).absolute(r.x - viewport.x, r.y - viewport.y).size(r.w, r.h));
    }
    if bar {
        // The leaf it would join, and where its tab would go.
        let r = dock_bar.rect;
        let th = tab_height();
        if outline { panel(column().skin(DOCK_PREVIEW).absolute(r.x - viewport.x, r.y - viewport.y).size(r.w, r.h)); }
        panel(column().skin(DOCK_TARGET_MARK).absolute(dock_bar.mark - 1.0 - viewport.x, r.y + 2.0 - viewport.y)
                  .size(2.0, th - 4.0));
    }
    for a, k in dock_aims {
        let at = a.at;
        box(column().skin(DOCK_TARGET).look(checked_look(k == hit)).absolute(at.x - viewport.x, at.y - viewport.y)
                .size(at.w, at.h)) {
            // Its mark: the part of a window it would fill.
            let inner = gfx2d::Rect { at.w * 0.2, at.h * 0.2, at.w * 0.6, at.h * 0.6 };
            let m = side_rect(inner, a.target.side, 0.5);
            panel(column().skin(DOCK_TARGET_MARK).absolute(m.x, m.y).size(m.w, m.h));
        };
    }
    close_root();
    if hit >= 0 { dock_aims[hit].target } else { dock_bar }
}

// --- recording ----------------------------------------------------------------------------

// A dock space: its windows' tabs and bodies in its leaves, the handles
// between them. As big as there is room unless `d` says.
fn dock_space(label: const u8[:], d: Desc = column()) { dock_space_of(id(label), d); }
fn dock_space_of(i: Id, d: Desc) {
    let st = state_of(i.v);
    if !dock_roots.contains(i.v) { dock_root(i.v); }
    var dd = d.skin(DOCK_SPACE);
    if dd.dim.w.kind == SIZE_FIT { dd = dd.grow_w(); }
    if dd.dim.h.kind == SIZE_FIT { dd = dd.grow_h(); }
    let t = class_style(SPLITTER).normal.min_size.x;
    let th = tab_height();
    box(i, dd.with_bits(SHRINKS)) {
        guard st.laid;
        let o = float2 { st.rect.x, st.rect.y };
        for k: i32 in 0..dock_nodes.len as i32 {
            let n = dock_nodes[k];
            if !n.used || n.space != i.v { continue; }
            let r = dock_rect(k);
            if n.axis >= 0 {
                // The handle between its two: dragged, its ratio.
                let hid = sub_id(i, k as i64);
                let it = interact(hid, column().hit());
                var hs = state_of(hid.v);
                let len = if n.axis == 0 { r.w - t } else { r.h - t };
                if it.pressed { hs.num = n.ratio * len; put_state(hid.v, hs); }
                if it.held && len > 0.0 {
                    let moved = if n.axis == 0 { it.drag.x } else { it.drag.y };
                    dock_nodes[k].ratio = clamp((hs.num + moved) / len, PANE_LEAST / len, 1.0 - PANE_LEAST / len) as f32;
                }
                if it.hovered || it.held { wanted_cursor = if n.axis == 0 { CURSOR_EW_RESIZE } else { CURSOR_NS_RESIZE }; }
                let ra = dock_rect(n.a);
                let hr = if n.axis == 0 { gfx2d::Rect { ra.x + ra.w, r.y, t, r.h } } else { gfx2d::Rect { r.x, ra.y + ra.h, r.w, t } };
                panel(hid, column().skin(SPLITTER).hit().look(look_of(it)).absolute(hr.x - o.x, hr.y - o.y).size(hr.w, hr.h));
                continue;
            }
            // A leaf: its tabs, the live ones; the selected one shown.
            var sel = n.selected;
            if !tab_live(sel) {
                sel = 0;
                for w in n.tabs { if sel == 0 && tab_live(w) { sel = w; } }
                dock_nodes[k].selected = sel;
            }
            if n.hide_tabs { continue; }
            // Tabs past the bar's end: a button lists them all, and the
            // one shown goes first, so that it shows.
            let gap = class_style(DOCK_TAB_BAR).normal.gap;
            var wide: f32 = 0.0;
            for w in n.tabs { if tab_live(w) { wide += tab_width(w) + gap; } }
            let list_w = th * 0.9;
            let over = wide > r.w - 8.0;
            var order: u64[..8] = [];
            if over && tab_live(sel) { order.push(sel); }
            for w in n.tabs { if tab_live(w) && !(over && w == sel) { order.push(w); } }
            // A tab dragged along the bar: drawn over the others, after them,
            // a gap where it goes. (Not while the bar is full: the one shown
            // goes first there.)
            var dragged: u64 = 0;
            if !over { for w in order { if tab_dragging(w) { dragged = w; } } }
            box(row().skin(DOCK_TAB_BAR).absolute(r.x - o.x, r.y - o.y).size(r.w, th).clip().align(END)
                    .padding(4, 0, if over { list_w + 4.0 } else { 4.0 }, 0)) {
                // The tabs cut off before the list's button, not under it.
                box(row().grow().align(END).clip().with_bits(SHRINKS).gap(gap)) {
                    var x: f32 = 0.0;
                    var dragged_at: f32 = 0.0;
                    for w in order {
                        let tw = tab_width(w);
                        if w == dragged {
                            panel(row().size(tw, th));
                            dragged_at = x;
                        } else {
                            dock_tab(w, k, sel == w, r, x, false);
                        }
                        x += tw + gap;
                    }
                    if dragged != 0 { dock_tab(dragged, k, sel == dragged, r, dragged_at, true); }
                };
            };
            if over { tab_list(i, k, gfx2d::Rect { r.x + r.w - list_w - 2.0 - o.x, r.y - o.y, list_w, th }); }
        }
    };
}

// How tabs slide to their places when one is dragged past them, and the
// dragged one when it is let go (INSTANT: they jump).
var tab_slide = INSTANT;
fn set_tab_slide(m: Motion) { tab_slide = m; }

fn tab_id(w: u64) -> Id { sub_id(Id { w }, "tab") }
// Its width, last frame.
fn tab_width(w: u64) -> f32 { state_of(tab_id(w).v).rect.w }
fn tab_desc(on: bool) -> Desc { clickable(row().skin(DOCK_TAB).align(CENTER)).nav_skip().look(checked_look(on)) }
fn tab_dragging(w: u64) -> bool {
    let it = interact(tab_id(w), tab_desc(false));
    it.held && it.dragging
}

// Window w's tab in leaf n, `x` along its bar: clicked, it is shown;
// dragged along the bar (`dragged`), it follows the pointer, and passes
// the tabs beside it; dragged out of the bar, it floats, still held by the
// pointer as if by its title.
fn dock_tab(w: u64, n: i32, on: bool, leaf: gfx2d::Rect, x: f32, dragged: bool) {
    let wid = Id { w };
    let tid = sub_id(wid, "tab");
    var td = tab_desc(on);
    let it = interact(tid, td);
    let p = input.pointer.pos;
    if it.pressed {
        dock_nodes[n].selected = w;
        // Where on it it was pressed.
        var ts = state_of(tid.v);
        ts.num = p.x - ts.screen.x;
        put_state(tid.v, ts);
    }
    if it.held && it.dragging && (p.y < leaf.y - 4.0 || p.y > leaf.y + tab_height() + 8.0 || p.x < leaf.x || p.x > leaf.x + leaf.w) {
        // Out: floating, as big as the leaf was, its title under the pointer.
        undock_id(w);
        var ws = window_state(w);
        ws.size = float2 { max(leaf.w, 160.0), max(leaf.h, 120.0) };
        ws.pos = p - float2 { 40.0, tab_height() * 0.5 };
        ws.grab = ws.pos;
        ws.collapsed = false;
        windows.insert(w, ws);
        raise_window_id(w);
        active = sub_id(wid, "title").v;
        press_pos = p;
        // Its window has its own title bar now, close button and all.
        return;
    }
    // Where it is drawn along the bar: under the pointer, dragged; else
    // sliding to its place, from where it was.
    let slide = sub_id(tid, "slide");
    if dragged {
        let row_w = leaf.w - 8.0;
        let left = clamp(p.x - state_of(tid.v).num as f32 - (leaf.x + 4.0), 0.0, max(row_w - tab_width(w), 0.0));
        animate(slide, left, INSTANT);
        reorder_tab(w, n, left);
        td = td.absolute(left, 0);
    } else {
        td = td.offset(animate(slide, x, tab_slide) - x, 0);
    }
    let ws = window_state(w);
    box(tid, td) {
        text(ws.title[..]);
        if ws.closable {
            let bd = clickable(row().skin(WINDOW_BUTTON)).nav_skip();
            box(sub_id(wid, "close"), bd) { icon(ICON_CLOSE); };
        }
    };
    context_menu(it) {
        if menu_item("Hide tab bar") { dock_nodes[n].hide_tabs = true; }
        if menu_item("Undock") {
            undock_id(w);
            raise_window_id(w);
        }
    };
}

// A tab held and dragged along its bar, its left at `left`, past the
// middle of the live tab beside it: the two change places. Where the tabs
// are is worked out from their order now and their widths, not taken
// from last frame, which would have them change back the frame after.
fn reorder_tab(w: u64, n: i32, left: f32) {
    let tabs = dock_nodes[n].tabs;
    let gap = class_style(DOCK_TAB_BAR).normal.gap;
    var xs: f32[..8] = [];
    var x: f32 = 0.0;
    var at = -1;
    for t, k in tabs {
        xs.push(x);
        if tab_live(t) { x += tab_width(t) + gap; }
        if t == w { at = k; }
    }
    guard at >= 0;
    var before = at - 1;
    while before >= 0 && !tab_live(tabs[before]) { before--; }
    var after = at + 1;
    while after < tabs.len && !tab_live(tabs[after]) { after++; }
    var to = -1;
    if before >= 0 && left < xs[before] + tab_width(tabs[before]) * 0.5 { to = before; }
    if to < 0 && after < tabs.len && left + tab_width(w) > xs[after] + tab_width(tabs[after]) * 0.5 { to = after; }
    guard to >= 0;
    dock_nodes[n].tabs[at] = tabs[to];
    dock_nodes[n].tabs[to] = w;
}

// The button at the end of a full tab bar: it lists leaf n's windows, to
// show one. `r` is its rect in the dock space `space`.
fn tab_list(space: Id, n: i32, r: gfx2d::Rect) {
    let bid = sub_id(space, n as i64 + 0x7AB5);
    let pid = sub_id(bid, "list");
    let bd = clickable(row().skin(WINDOW_BUTTON).center()).nav_skip().absolute(r.x, r.y).size(r.w, r.h);
    let it = interact(bid, bd);
    if it.activated {
        if popup_level(pid.v) > 0 { close_popup(pid); }
        else {
            open_popup_at(pid, POPUP_MENU, Anchor { kind: ANCHOR_BELOW, rect: it.rect, .. });
            set_popup_header(pid, bid.v);
        }
    }
    let header = nodes.len as i32;
    box(bid, bd) { icon(ICON_CHEVRON_DOWN); };
    popup_root(pid, POPUP_MENU, column().min_w(140), MENU, header) {
        for w in dock_nodes[n].tabs {
            if !tab_live(w) { continue; }
            let item = box(Id { hash_combine(pid.v, w) }, clickable(row().skin(MENU_ITEM).grow_w().align(CENTER))
                                                   .look(checked_look(dock_nodes[n].selected == w))) {
                text(window_state(w).title[..]);
            };
            if item.activated {
                dock_nodes[n].selected = w;
                close_popup(pid);
            }
        }
    };
}

// --- floating docks ---------------------------------------------------------------------

// Window w docked with floating window `other`: the two in a floating dock,
// a window of imgui's where `other` was, holding a dock space; `other`
// fills it, and w goes on `side` of it (or as a tab, DOCK_CENTER).
fn dock_into_window(w: u64, other: u64, side: i64, ratio: f64) {
    let h = hash_combine(other, 0xD0C7);
    let os = window_state(other);
    let ost = state_of(other);
    var hs = window_state(h);
    // Where `other` is: as laid out, or (not yet) as it was set.
    let at = if ost.laid { float2 { ost.rect.x, ost.rect.y } } else { os.pos };
    let size = if ost.laid { float2 { ost.rect.w, ost.rect.h } } else { os.size };
    hs.pos = at;
    hs.size = float2 { max(size.x, 200.0), max(size.y, 150.0) };
    hs.collapsed = false;
    hs.host = true;
    hs.dock = -1;
    windows.insert(h, hs);
    raise_window_id(h);
    let space = host_space(h);
    space_host.insert(space, h);
    let root = dock_root(space);
    dock_into(other, root, DOCK_CENTER, 1.0);
    dock_into(w, root, side, ratio);
}

// Floating dock h recorded, once a frame: a window whose title is its
// first window's, and whose body is its dock space.
recursive fn record_host(h: u64) {
    var hs = window_state(h);
    guard hs.called != frame_index;
    // Its title: the window shown in its first leaf.
    var n = dock_root(host_space(h));
    while dock_nodes[n].axis >= 0 { n = dock_nodes[n].a; }
    var title: u8[..48] = [];
    let sel = dock_nodes[n].selected;
    if sel != 0 { for c in window_state(sel).title { title.push(c); } }
    var open = true;
    window_with(Id { h }, title[..], open, false, column().padding(0), WINDOW_NO_SCROLL) {
        dock_space_of(Id { host_space(h) }, column().grow());
    };
}

// A docked window shown: its body (the block, unless another tab is
// selected) as a root over its leaf, below the tab bar. Its tab's close
// button closes it, keeping its place.
fn docked_window<F>(wid: Id, open: bool&, d: Desc, flags: i64) {
    let ws = window_state(wid.v);
    let n = ws.dock;
    if ws.closable && interaction_for(sub_id(wid, "close").v, clickable(row().skin(WINDOW_BUTTON)).nav_skip()).activated {
        open = false;
        return;
    }
    guard dock_nodes[n].selected == wid.v;
    let r = dock_rect(n);
    let th = bar_height(n);
    // Its tab bar hidden: a button in its corner shows it again.
    let show_id = sub_id(wid, "show tabs");
    let show_d = clickable(column().skin(DOCK_TAB_TOGGLE)).nav_skip();
    if dock_nodes[n].hide_tabs && interaction_for(show_id.v, show_d).activated { dock_nodes[n].hide_tabs = false; }
    let root = open_root(ROOT_WINDOW, wid.v, Anchor { kind: ANCHOR_POINT, at: float2 { r.x, r.y + th }, .. },
                         column().skin(DOCKED).keep().size(r.w, max(r.h - th, 0.0)));
    id_stack.push(wid.v);
    nodes[root].scoped = true;
    var bd = d;
    bd.dim = SizeDesc { .. };
    bd.lay.absolute = false;
    bd = bd.grow().with_bits(SHRINKS);
    if bd.vis.class.index == 0 { bd = bd.skin(WINDOW_BODY); }
    window_body(flags, bd) { F(); };
    if dock_nodes[n].hide_tabs {
        let side = class_style(DOCK_TAB_TOGGLE).normal.min_size.x;
        panel(show_id, show_d.absolute(0, 0).size(side, side));
    }
    close_root();
}
