// imgui's own metrics: a window of what the last frame took (its times and
// counts) and of its nodes, as a tree. A node hovered in the tree, or
// under the pointer while picking, is outlined where it was drawn; one
// clicked shows its details.
//
//   imgui::menu_check("Metrics", show_metrics);
//   imgui::metrics_window(show_metrics);

namespace imgui;

import std;
import vec;
import math;
import dictionary;
import os;
import gfx2d;

// What the last frame took, in milliseconds: recording (the program's
// block), layout, what follows it (motion, hits, focus), and drawing.
struct FrameTimes { record: f64 = 0.0, layout: f64 = 0.0, after: f64 = 0.0, draw: f64 = 0.0 }
var frame_times = FrameTimes { .. };
var times_mark: i64 = 0;
fn ms_since(t: i64) -> f64 { (clock_ns() - t) / 1000000.0 }

// How many of each there were, at the end of the last frame.
struct FrameCounts {
    nodes: i64 = 0,
    roots: i64 = 0,
    hits: i64 = 0,
    focusables: i64 = 0,
    states: i64 = 0,
    animations: i64 = 0,
    windows: i64 = 0,
    canvas_ops: i64 = 0,
}
var frame_counts = FrameCounts { .. };

// The last frame's nodes, kept while the window is shown.
struct MetricNode {
    id: u64 = 0,
    parent: i32 = -1,
    depth: i32 = 0,
    kind: u8 = 0,
    kids: i32 = 0,
    class: i32 = 0,
    named: bool = false,
    bits: u32 = 0,
    rank: i32 = 0,          // its root's place in the drawing order
    root_id: u64 = 0,       // its root's window (or popup), if any
    screen: gfx2d::Rect = gfx2d::Rect { 0.0, 0.0, 0.0, 0.0 },
    text: u8[..40] = [],
}
var metric_nodes: MetricNode[>..<] = [];
var metric_rows: i32[>..<] = [];            // the tree's rows: the nodes whose parents are all open
var metrics_open = dictionary<u64, bool> {};
var metrics_shown: i64 = -10;               // the frame the window was last recorded
var metrics_id: u64 = 0;                    // its window
var metrics_selected: u64 = 0;
var metrics_picking = false;

// At the end of a frame: its counts, and, while the window is shown, its
// nodes.
fn note_frame() {
    frame_counts = FrameCounts { nodes: nodes.len, roots: roots.len, hits: hits.len, focusables: focusables.len,
                                 states: states.count, animations: anims.count, windows: windows.count,
                                 canvas_ops: draw_cmds.len };
    guard metrics_shown >= frame_index - 1;
    metric_nodes.clear();
    var rank: i32[>..<] = [];
    for k in roots.len { rank.push(0); }
    for r, k in root_order { rank[r as i64] = k as i32; }
    for n, i in nodes {
        var m = MetricNode { id: n.id, parent: n.parent, kind: n.kind, kids: n.kids, class: n.d.vis.class.index,
                             named: n.named, bits: n.d.bits, rank: rank[n.root as i64],
                             root_id: roots[n.root as i64].popup, screen: n.screen, .. };
        if n.parent >= 0 { m.depth = metric_nodes[n.parent].depth + 1; }
        if n.kind == NODE_TEXT {
            for c in node_text(i as i32) { if m.text.len < m.text.cap { m.text.push(c); } }
        }
        metric_nodes.push(m);
    }
}

// The built-in classes' names, in order: each StyleClass's index is its
// place here. (A test checks the last against CLASS_COUNT.)
let CLASS_NAMES = "NONE PANEL BUTTON LABEL TITLE MUTED CHECKBOX CHECK TOGGLE TOGGLE_KNOB RADIO RADIO_DOT SLIDER_TRACK SLIDER_FILL SLIDER_THUMB PROGRESS_TRACK PROGRESS_FILL SEPARATOR SELECTABLE SCROLLBAR SCROLL_THUMB TAB_BAR TAB TAB_PANEL MENU_BAR MENU_HEADER MENU MENU_ITEM POPUP MODAL BACKDROP TOOLTIP INPUT CARET SELECTION DROPDOWN CHOICE METER METER_TRACK METER_FILL METER_TRAIL FOCUS_CURSOR NOTICE WINDOW WINDOW_TITLE WINDOW_BODY WINDOW_BUTTON RESIZE_GRIP HEADER TREE_ROW TREE NUMBER PROPERTIES PROPERTY_LABEL PLOT PLOT_LINE PLOT_BAR SWATCH PICKER TABLE TABLE_HEADER TABLE_HEAD TABLE_ROW TABLE_ROW_ALT TABLE_CELL LOG LOG_LINE LOG_DEBUG_LINE LOG_WARN_LINE LOG_ERROR_LINE LOG_INPUT_LINE SPLITTER DOCK_SPACE DOCK_TAB_BAR DOCK_TAB DOCKED DOCK_PREVIEW DOCK_TARGET DOCK_TARGET_MARK DOCK_TAB_TOGGLE SMALL_BUTTON ICON_BUTTON TOOLBAR STATUS_BAR LINK LINK_LINE BULLET SPINNER KNOB";
fn class_name(k: i64) -> u8[>..] {
    var at = 0;
    var start = 0;
    for c, i in CLASS_NAMES {
        if c != ' ' { continue; }
        if at == k { return str(CLASS_NAMES[start..i]); }
        at++;
        start = i + 1;
    }
    if at == k { return str(CLASS_NAMES[start..]); }
    str("class ", k)
}

fn kind_name(k: u8) -> const u8[:] {
    match k as i64 {
        NODE_TEXT => "text",
        NODE_IMAGE => "image",
        NODE_ICON => "icon",
        NODE_RICH => "rich text",
        _ => "box",
    }
}
fn id_text(v: u64) -> u8[>..] {
    var out: u8[>..] = [];
    format_id(out, v);
    str(out[1..out.len - 1])
}

// The node under p, not in the metrics window: the last drawn there.
fn metric_node_at(p: float2) -> i64 {
    var best: i64 = -1;
    for m, k in metric_nodes {
        if m.root_id == metrics_id || m.root_id == METRICS_OUTLINE || !inside(m.screen, p) { continue; }
        if best < 0 || m.rank >= metric_nodes[best].rank { best = k; }
    }
    best
}

let METRICS_OUTLINE: u64 = 0xE7A1C5E7A1C5;
// Node k outlined where it was drawn, over everything, not in the
// pointer's way.
fn outline_metric_node(k: i64) {
    guard k >= 0 && k < metric_nodes.len;
    let r = metric_nodes[k].screen;
    open_root(ROOT_TOOLTIP, METRICS_OUTLINE, Anchor { kind: ANCHOR_POINT, at: float2 { viewport.x, viewport.y }, .. },
              column().size(viewport.w, viewport.h).passthrough());
    roots[roots.len - 1].level = -1;
    panel(column().skin(DOCK_PREVIEW).absolute(r.x - viewport.x, r.y - viewport.y).size(max(r.w, 1.0), max(r.h, 1.0)));
    close_root();
}

// Node k selected, its parents opened so that it shows in the tree.
fn select_metric_node(k: i64) {
    guard k >= 0 && k < metric_nodes.len;
    metrics_selected = metric_nodes[k].id;
    var p = metric_nodes[k].parent;
    while p >= 0 {
        metrics_open.insert(metric_nodes[p].id, true);
        p = metric_nodes[p].parent;
    }
}

// The metrics window: closed by its close button, which sets `open` false.
fn metrics_window(open: bool&) {
    guard open;
    metrics_shown = frame_index;
    metrics_id = id("Metrics").v;
    window("Metrics", open, column().size(380, 560).gap(6), WINDOW_NO_SCROLL) {
        let t = frame_times;
        let total = t.record + t.layout + t.after + t.draw;
        label_value("Frame", str(round(delta * 10000.0) / 10.0, " ms, ", round(1.0 / max(delta, 0.0001)), " fps"));
        label_value("imgui", str(round(total * 100.0) / 100.0, " ms"));
        box(column().gap(2).padding(10, 0, 0, 0)) {
            label_value("recording", str(round(t.record * 100.0) / 100.0, " ms"));
            label_value("layout", str(round(t.layout * 100.0) / 100.0, " ms"));
            label_value("after layout", str(round(t.after * 100.0) / 100.0, " ms"));
            label_value("drawing", str(round(t.draw * 100.0) / 100.0, " ms"));
        };
        let c = frame_counts;
        label_value("Nodes", str(c.nodes, " in ", c.roots, " roots"));
        label_value("Hit and focus lists", str(c.hits, ", ", c.focusables));
        label_value("States, animations", str(c.states, ", ", c.animations));
        label_value("Windows, canvas ops", str(c.windows, ", ", c.canvas_ops));
        separator();

        // Picking: the node under the pointer outlined; a click selects it.
        var hovered: i64 = -1;
        box(row().align(CENTER).gap(6)) {
            icon_toggle("Pick a node", ICON_SEARCH, metrics_picking);
            text(if metrics_picking { "click a node to select it" } else { "Nodes" }, MUTED);
        };
        if metrics_picking && hot_window != metrics_id {
            hovered = metric_node_at(input.pointer.pos);
            if input.pointer.pressed && hovered >= 0 {
                select_metric_node(hovered);
                metrics_picking = false;
            }
        }

        // The tree: each node whose parents are all open, a row each.
        metric_rows.clear();
        var closed_at: i32 = 1 << 30;
        for m, k in metric_nodes {
            if m.depth > closed_at { continue; }
            closed_at = 1 << 30;
            metric_rows.push(k as i32);
            let o = metrics_open.get(m.id);
            let is_open = if o { o } else { false };
            if m.kids > 0 && !is_open { closed_at = m.depth; }
        }
        let rh = max(class_style(TREE_ROW).normal.min_size.y, 18.0);
        scroll("tree", column().grow().min_h(rh * 4)) {
            row_list("nodes", metric_rows.len, rh, column().grow_w()) { r =>
                let k = metric_rows[r] as i64;
                let m = metric_nodes[k];
                let o = metrics_open.get(m.id);
                let is_open = if o { o } else { false };
                id_scope(Id { m.id }) {
                    let rd = clickable(row().skin(TREE_ROW).grow_w().align(CENTER).height(rh))
                        .look(checked_look(m.id == metrics_selected));
                    let it = box("row", rd) {
                        panel(row().width(m.depth * 12));
                        if m.kids > 0 {
                            let ad = clickable(row()).nav_skip();
                            let at = box("arrow", ad) { icon(if is_open { ICON_CHEVRON_DOWN } else { ICON_CHEVRON_RIGHT }); };
                            if at.activated { metrics_open.insert(m.id, !is_open); }
                        } else {
                            panel(row().width(class_style(LABEL).normal.text_size * 0.75));
                        }
                        text(kind_name(m.kind));
                        if m.text.len > 0 { text(str("\"", m.text[..], "\""), MUTED); }
                        else if m.named { text(id_text(m.id)[..], MUTED); }
                        panel(row().grow_w());
                        text(str(round(m.screen.w), "x", round(m.screen.h)), MUTED);
                        // Clear of the scrollbar, which is over the rows.
                        panel(row().width(10));
                    };
                    if it.hovered { hovered = k; }
                    if it.activated { metrics_selected = m.id; }
                };
            };
        };

        // The one selected.
        var sel: i64 = -1;
        for m, k in metric_nodes { if sel < 0 && m.id == metrics_selected { sel = k; } }
        separator();
        if sel >= 0 {
            let m = metric_nodes[sel];
            label_value("Kind", str(kind_name(m.kind), if m.named { ", named" } else { "" }));
            label_value("ID", id_text(m.id)[..]);
            label_value("Class", class_name(m.class)[..]);
            label_value("Rect", str(round(m.screen.x), ", ", round(m.screen.y), "  ", round(m.screen.w), " x ",
                                    round(m.screen.h)));
            var bits: u8[>..] = [];
            if m.bits & HIT != 0 { bits.append("hit "); }
            if m.bits & FOCUSABLE != 0 { bits.append("focusable "); }
            if m.bits & (SCROLLS_X | SCROLLS_Y) != 0 { bits.append("scrolls "); }
            if m.bits & PASSTHROUGH != 0 { bits.append("passthrough "); }
            if m.bits & DISABLED != 0 { bits.append("disabled "); }
            label_value("Takes", if bits.len > 0 { bits[..] } else { "nothing" });
            label_value("Children", str(m.kids));
            if hovered < 0 { hovered = sel; }
        } else {
            text("Click a row, or pick a node, to see it here.", MUTED);
        }
        if hovered >= 0 { outline_metric_node(hovered); }
    };
}
