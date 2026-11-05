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
    used: bool = false,
}

// Every dock node, of every space; unused ones are taken again before the
// array grows (it never shrinks).
var dock_nodes: DockNode[>..] = [];
var dock_roots = dictionary<u64, i32> {};
var dock_spaces: u64[>..<] = [];

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

// --- changing the tree --------------------------------------------------------------------

// Window w added to leaf n's tabs, and shown.
fn dock_into_leaf(w: u64, n: i32) {
    if dock_nodes[n].tabs.len < DOCK_TABS { dock_nodes[n].tabs.push(w); }
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
    if src.a >= 0 { dock_nodes[src.a].parent = m; }
    if src.b >= 0 { dock_nodes[src.b].parent = m; }
    for w in src.tabs {
        var ws = window_state(w);
        ws.dock = m;
        windows.insert(w, ws);
    }
}

// Window w docked at node n: in it as a tab (DOCK_CENTER), or beside it on
// `side`, taking `ratio` of its length. A window docked elsewhere leaves
// there first.
fn dock_into(w: u64, n: i32, side: i64, ratio: f64) {
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
        dock_into_leaf(w, leaf);
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
fn dock_window_with(title: const u8[:], other: const u8[:], side: i64, ratio: f64 = 0.5) {
    let w = id(title).v;
    if !windows.contains(w) { window_order.push(w); windows.insert(w, WindowState { .. }); }
    let n = window_state(id(other).v).dock;
    guard n >= 0 else { misuse("dock_window_with: the other window isn't docked"); return; }
    dock_into(w, n, side, ratio);
}
fn undock_window(title: const u8[:]) { undock_id(id(title).v); }
fn is_docked(title: const u8[:]) -> bool { window_state(id(title).v).dock >= 0 }

// --- where a dragged window would go ------------------------------------------------------

struct DockTarget { node: i32 = -1, side: i64 = 0, rect: gfx2d::Rect = gfx2d::Rect { 0.0, 0.0, 0.0, 0.0 } }

// The leaf under p in a dock space shown, and the side of it p is by (its
// outer quarter by an edge), or its middle; and the rect the window would
// take there.
fn dock_target_at(p: float2) -> DockTarget {
    for sp in dock_spaces {
        let root = dock_root(sp);
        guard dock_shown(root) else { continue; }
        guard inside(dock_rect(root), p) else { continue; }
        var n = root;
        while dock_nodes[n].axis >= 0 {
            let a = dock_nodes[n].a;
            n = if inside(dock_rect(a), p) { a } else { dock_nodes[n].b };
        }
        let r = dock_rect(n);
        var live = 0;
        for w in dock_nodes[n].tabs { if tab_live(w) { live++; } }
        if live == 0 { return DockTarget { node: n, side: DOCK_CENTER, rect: r }; }
        let fx = (p.x - r.x) / max(r.w, 1.0);
        let fy = (p.y - r.y) / max(r.h, 1.0);
        let m = min(min(fx, 1.0 - fx), min(fy, 1.0 - fy));
        guard m < 0.25 else { return DockTarget { node: n, side: DOCK_CENTER, rect: r }; }
        if m == fx { return DockTarget { node: n, side: DOCK_LEFT, rect: gfx2d::Rect { r.x, r.y, r.w * 0.5, r.h } }; }
        if m == 1.0 - fx { return DockTarget { node: n, side: DOCK_RIGHT, rect: gfx2d::Rect { r.x + r.w * 0.5, r.y, r.w * 0.5, r.h } }; }
        if m == fy { return DockTarget { node: n, side: DOCK_TOP, rect: gfx2d::Rect { r.x, r.y, r.w, r.h * 0.5 } }; }
        return DockTarget { node: n, side: DOCK_BOTTOM, rect: gfx2d::Rect { r.x, r.y + r.h * 0.5, r.w, r.h * 0.5 } };
    }
    DockTarget { .. }
}

// Where a window dragged to p would dock, shown over everything.
fn dock_preview(p: float2) {
    let t = dock_target_at(p);
    guard t.node >= 0;
    open_root(ROOT_TOOLTIP, hash_combine(ROOT_ID, 0xD0C4), Anchor { kind: ANCHOR_POINT, at: float2 { t.rect.x, t.rect.y }, .. },
              column());
    roots[roots.len - 1].level = -1;
    panel(column().skin(DOCK_PREVIEW).size(t.rect.w, t.rect.h));
    close_root();
}

// --- recording ----------------------------------------------------------------------------

// A dock space: its windows' tabs and bodies in its leaves, the handles
// between them. As big as there is room unless `d` says.
fn dock_space(label: const u8[:], d: Desc = column()) {
    let i = id(label);
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
            box(row().skin(DOCK_TAB_BAR).absolute(r.x - o.x, r.y - o.y).size(r.w, th).clip().align(END)) {
                for w in n.tabs {
                    if !tab_live(w) { continue; }
                    dock_tab(w, k, sel == w, r);
                }
            };
        }
    };
}

// Window w's tab in leaf n: clicked, it is shown; dragged out of the tab
// bar, it floats, still held by the pointer as if by its title.
fn dock_tab(w: u64, n: i32, on: bool, leaf: gfx2d::Rect) {
    let wid = Id { w };
    let tid = sub_id(wid, "tab");
    let td = clickable(row().skin(DOCK_TAB).align(CENTER)).nav_skip().look(checked_look(on));
    let it = interact(tid, td);
    if it.pressed { dock_nodes[n].selected = w; }
    let p = input.pointer.pos;
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
    let ws = window_state(w);
    box(tid, td) {
        text(ws.title[..]);
        if ws.closable {
            let bd = clickable(row().skin(WINDOW_BUTTON)).nav_skip();
            box(sub_id(wid, "close"), bd) { icon(ICON_CLOSE); };
        }
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
    let th = tab_height();
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
    close_root();
}
