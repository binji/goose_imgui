// Layouts saved and loaded: where the windows are and how big, which are
// collapsed and which were open, their order front to back, the dock
// spaces' trees (floating docks too), the splitters' panes, and which
// headers and tree nodes are open. As JSON, in a file or a string.
//
//   if !imgui::load_layout("layout.json") { default_layout(); }
//   …
//   imgui::save_layout("layout.json");      // on the way out
//
// Windows, panes and nodes are kept by their IDs, which come from their
// labels: a layout fits a program whose labels are the same.

namespace imgui;

import std;
import vec;
import math;
import dictionary;
import json;
import os;
import gfx2d;

let LAYOUT_VERSION = 1;

// Which windows were open when the layout was loaded, by ID.
var layout_opened = dictionary<u64, bool> {};

// Whether window `title` was open in the layout loaded; `fallback` if it
// wasn't in it (or none was loaded). For the flag a closable window's
// open: bool& starts from.
fn layout_open(title: const u8[:], fallback: bool) -> bool {
    let o = layout_opened.get(id(title).v);
    if o { return o; }
    fallback
}

// --- writing ------------------------------------------------------------------------------

// An ID as 16 hex digits, quoted: JSON's numbers are f64s, which can't
// hold every u64.
fn format_id(out: u8[>..]&, v: u64) {
    let digits = "0123456789abcdef";
    out.push('"');
    var k = 15;
    while k >= 0 {
        out.push(digits[((v >> (k * 4) as u64) & 15) as! i64]);
        k--;
    }
    out.push('"');
}
// An f32, to 6 places: as an f64 it would be written to 17 digits.
fn format_f32(out: u8[>..]&, v: f32) {
    let x: f64 = v;
    json::format_number(out, round(x * 1000000.0) / 1000000.0);
}
fn format_member(out: u8[>..]&, key: const u8[:], first: bool) {
    if !first { out.push(','); }
    json::format_key(out, key);
}

// The keys of a dictionary's entries, sorted, so that a layout saved twice
// is the same text.
fn sort_ids(ids: u64[>..<]&) {
    for k in 1..ids.len {
        let v = ids[k];
        var j = k - 1;
        while j >= 0 && ids[j] > v {
            ids[j + 1] = ids[j];
            j--;
        }
        ids[j + 1] = v;
    }
}

// The layout as JSON, appended to `out`.
fn layout_json(out: u8[>..]&) {
    out.append("{\"version\":");
    json::format_int(out, LAYOUT_VERSION);
    // The windows, back to front.
    out.append(",\n\"windows\":[");
    for w, k in window_order {
        let ws = window_state(w);
        out.append(if k > 0 { ",\n{" } else { "\n{" });
        format_member(out, "id", true);
        format_id(out, w);
        format_member(out, "title", false);
        json::format_string(out, ws.title[..]);
        format_member(out, "x", false);
        format_f32(out, ws.pos.x);
        format_member(out, "y", false);
        format_f32(out, ws.pos.y);
        format_member(out, "w", false);
        format_f32(out, ws.size.x);
        format_member(out, "h", false);
        format_f32(out, ws.size.y);
        format_member(out, "collapsed", false);
        json::format_bool(out, ws.collapsed);
        format_member(out, "dock", false);
        json::format_int(out, ws.dock);
        format_member(out, "host", false);
        json::format_bool(out, ws.host);
        format_member(out, "open", false);
        json::format_bool(out, ws.called >= frame_index - 1);
        out.push('}');
    }
    // Every dock node, by its index, which the windows' and nodes' links are.
    out.append("],\n\"dock\":[");
    for n, k in dock_nodes {
        out.append(if k > 0 { ",\n{" } else { "\n{" });
        format_member(out, "used", true);
        json::format_bool(out, n.used);
        if n.used {
            format_member(out, "space", false);
            format_id(out, n.space);
            format_member(out, "parent", false);
            json::format_int(out, n.parent);
            if n.axis >= 0 {
                format_member(out, "axis", false);
                json::format_int(out, n.axis);
                format_member(out, "ratio", false);
                format_f32(out, n.ratio);
                format_member(out, "a", false);
                json::format_int(out, n.a);
                format_member(out, "b", false);
                json::format_int(out, n.b);
            } else {
                format_member(out, "tabs", false);
                out.push('[');
                for t, j in n.tabs {
                    if j > 0 { out.push(','); }
                    format_id(out, t);
                }
                out.push(']');
                format_member(out, "selected", false);
                format_id(out, n.selected);
                format_member(out, "hide_tabs", false);
                json::format_bool(out, n.hide_tabs);
            }
        }
        out.push('}');
    }
    // The panes' fractions, and the headers' and tree nodes' open states.
    var ids: u64[>..<] = [];
    pane_fractions.each() { i, f => ids.push(i); };
    sort_ids(ids);
    out.append("],\n\"panes\":[");
    for i, k in ids {
        out.append(if k > 0 { ",\n{" } else { "\n{" });
        format_member(out, "id", true);
        format_id(out, i);
        format_member(out, "fraction", false);
        json::format_number(out, pane_fraction(i, 0.0));
        out.push('}');
    }
    ids.clear();
    opened.each() { i, o => ids.push(i); };
    sort_ids(ids);
    out.append("],\n\"open\":[");
    for i, k in ids {
        out.append(if k > 0 { ",\n{" } else { "\n{" });
        format_member(out, "id", true);
        format_id(out, i);
        format_member(out, "open", false);
        let o = opened.get(i);
        json::format_bool(out, o && o == 1);
        out.push('}');
    }
    out.append("]}\n");
}

// The layout saved to the file at `path` (all or nothing: a file beside it,
// renamed over it).
fn save_layout(path: const u8[:]) -> bool {
    var text: u8[>..] = [];
    layout_json(text);
    write_file_atomic(path, text[..])
}

// --- reading ------------------------------------------------------------------------------

struct SavedWindow {
    id: u64 = 0,
    title: u8[..48] = [],
    pos: float2 = float2 { 0.0, 0.0 },
    size: float2 = float2 { 0.0, 0.0 },
    collapsed: bool = false,
    dock: i32 = -1,
    host: bool = false,
    open: bool = true,
}
struct SavedPane { id: u64 = 0, fraction: f64 = 0.0 }
struct SavedOpen { id: u64 = 0, open: bool = false }

// The ID in 16 hex digits; false for anything else.
fn parse_id(s: const u8[:]) -> u64, bool {
    guard s.len == 16 else { return 0, false; }
    var v: u64 = 0;
    for c in s {
        var d: u64 = 0;
        if c >= '0' && c <= '9' { d = c - '0'; }
        else if c >= 'a' && c <= 'f' { d = c - 'a' + 10; }
        else { return 0, false; }
        v = (v << 4) | d;
    }
    return v, true;
}

var saved_windows: SavedWindow[>..<] = [];
var saved_nodes: DockNode[>..<] = [];
var saved_panes: SavedPane[>..<] = [];
var saved_open: SavedOpen[>..<] = [];

// The layout in `text` (as layout_json writes it) in place of the one
// there is: false, and nothing changed, if it isn't one, with what is
// wrong.
fn load_layout_json(text: const u8[:]) -> bool, u8[>..] {
    saved_windows.clear();
    saved_nodes.clear();
    saved_panes.clear();
    saved_open.clear();
    var r = json::reader(text);
    var scratch: u8[>..] = [];
    var version: i64 = 0;
    var bad: const u8[:] = "";
    fn read_id() -> u64 {
        let v, ok = parse_id(json::read_string(r, scratch));
        if !ok { bad = "an ID that isn't 16 hex digits"; }
        v
    }
    fn read_in(least: i64, most: i64) -> i64 {
        let v = json::read_int(r);
        if v >= least && v <= most { return v; }
        bad = "a number out of range";
        -1
    }
    let LINK_MOST: i64 = 0x7fffffff;
    json::each_member(r) { key =>
        if key == "version" { version = json::read_int(r); }
        else if key == "windows" {
            json::each_element(r) {
                var w = SavedWindow { .. };
                json::each_member(r) { k =>
                    if k == "id" { w.id = read_id(); }
                    else if k == "title" { for c in json::read_string(r, scratch) { if w.title.len < w.title.cap { w.title.push(c); } } }
                    else if k == "x" { w.pos.x = json::read_number(r) as f32; }
                    else if k == "y" { w.pos.y = json::read_number(r) as f32; }
                    else if k == "w" { w.size.x = json::read_number(r) as f32; }
                    else if k == "h" { w.size.y = json::read_number(r) as f32; }
                    else if k == "collapsed" { w.collapsed = json::read_bool(r); }
                    else if k == "dock" { w.dock = read_in(-1, LINK_MOST) as i32; }
                    else if k == "host" { w.host = json::read_bool(r); }
                    else if k == "open" { w.open = json::read_bool(r); }
                    else { json::skip(r); }
                };
                saved_windows.push(w);
            };
        }
        else if key == "dock" {
            json::each_element(r) {
                var n = DockNode { .. };
                json::each_member(r) { k =>
                    if k == "used" { n.used = json::read_bool(r); }
                    else if k == "space" { n.space = read_id(); }
                    else if k == "parent" { n.parent = read_in(-1, LINK_MOST) as i32; }
                    else if k == "axis" { n.axis = read_in(-1, 1) as i8; }
                    else if k == "ratio" { n.ratio = json::read_number(r) as f32; }
                    else if k == "a" { n.a = read_in(-1, LINK_MOST) as i32; }
                    else if k == "b" { n.b = read_in(-1, LINK_MOST) as i32; }
                    else if k == "tabs" {
                        json::each_element(r) {
                            let t = read_id();
                            if n.tabs.len < n.tabs.cap { n.tabs.push(t); } else { bad = "a leaf with too many tabs"; }
                        };
                    }
                    else if k == "selected" { n.selected = read_id(); }
                    else if k == "hide_tabs" { n.hide_tabs = json::read_bool(r); }
                    else { json::skip(r); }
                };
                saved_nodes.push(n);
            };
        }
        else if key == "panes" {
            json::each_element(r) {
                var p = SavedPane { .. };
                json::each_member(r) { k =>
                    if k == "id" { p.id = read_id(); }
                    else if k == "fraction" { p.fraction = json::read_number(r); }
                    else { json::skip(r); }
                };
                saved_panes.push(p);
            };
        }
        else if key == "open" {
            json::each_element(r) {
                var o = SavedOpen { .. };
                json::each_member(r) { k =>
                    if k == "id" { o.id = read_id(); }
                    else if k == "open" { o.open = json::read_bool(r); }
                    else { json::skip(r); }
                };
                saved_open.push(o);
            };
        }
        else { json::skip(r); }
    };
    guard json::finish(r) else { return false, json::message(r); }
    guard version == LAYOUT_VERSION else { return false, str("layout: version ", version, ", not ", LAYOUT_VERSION); }
    guard bad.len == 0 else { return false, str("layout: ", bad); }
    // The links all in range, ...
    let count = saved_nodes.len as i32;
    fn link(k: i32) -> bool { k >= -1 && k < count }
    for n, k in saved_nodes {
        if !n.used { continue; }
        guard link(n.parent) && link(n.a) && link(n.b) else { return false, str("layout: dock node ", k, " links outside the tree"); }
    }
    for w in saved_windows {
        guard link(w.dock) && (w.dock < 0 || (saved_nodes[w.dock].used && saved_nodes[w.dock].axis < 0))
            else { return false, str("layout: a window docked outside a leaf"); }
    }
    // ... each split with two used children that name it as their parent,
    // each child listed by its parent, each space with one root, ...
    fn child_of(c: i32, k: i32) -> bool { c >= 0 && saved_nodes[c].used && saved_nodes[c].parent == k }
    for n, k in saved_nodes {
        if !n.used { continue; }
        let at = k as i32;
        if n.axis >= 0 {
            guard n.a != n.b && child_of(n.a, at) && child_of(n.b, at) && n.ratio >= 0.0 && n.ratio <= 1.0
                else { return false, str("layout: dock node ", k, "'s split is broken"); }
        }
        if n.parent >= 0 {
            let p = saved_nodes[n.parent];
            guard p.used && p.axis >= 0 && (p.a == at || p.b == at) && p.space == n.space
                else { return false, str("layout: dock node ", k, " isn't a child of its parent"); }
        } else {
            for o, j in saved_nodes {
                guard j >= k || !o.used || o.parent >= 0 || o.space != n.space
                    else { return false, str("layout: dock node ", k, " is a second root of a space"); }
            }
        }
        // ... a leaf's tabs its windows, once each ...
        for t, j in n.tabs {
            var there = false;
            for w in saved_windows { if w.id == t && w.dock == at { there = true; } }
            for o in n.tabs[..j] { if o == t { there = false; } }
            guard there else { return false, str("layout: dock node ", k, " has a tab that isn't its window"); }
        }
    }
    for w in saved_windows {
        if w.dock < 0 { continue; }
        var there = false;
        for t in saved_nodes[w.dock].tabs { if t == w.id { there = true; } }
        guard there else { return false, str("layout: a docked window with no tab"); }
    }
    // ... and every node's way up ending at a root, not going round.
    for n, k in saved_nodes {
        if !n.used { continue; }
        var up = n.parent;
        var left = count;
        while up >= 0 && left > 0 {
            up = saved_nodes[up].parent;
            left--;
        }
        guard up < 0 else { return false, str("layout: dock node ", k, " is in a loop"); }
    }

    // In place of what there is. Every window not in it floats.
    windows.each() { i, ws => ws.dock = -1; };
    for k in dock_nodes.len { dock_nodes[k].used = false; }
    for n, k in saved_nodes {
        if k < dock_nodes.len { dock_nodes[k] = n; } else { dock_nodes.push(n); }
    }
    dock_roots.clear();
    dock_spaces.clear();
    space_host.clear();
    for n, k in saved_nodes {
        if n.used && n.parent < 0 {
            dock_roots.insert(n.space, k as i32);
            dock_spaces.push(n.space);
        }
    }
    var order: u64[>..<] = [];
    for w in saved_windows {
        var ws = window_state(w.id);
        ws.pos = w.pos;
        ws.size = w.size;
        ws.collapsed = w.collapsed;
        ws.dock = w.dock;
        ws.host = w.host;
        ws.title.clear();
        for c in w.title { ws.title.push(c); }
        // Not raised the first time it is called, as a window new to the
        // program is: the order is the layout's.
        ws.called = -1;
        windows.insert(w.id, ws);
        if w.host { space_host.insert(host_space(w.id), w.id); }
        layout_opened.insert(w.id, w.open);
        order.push(w.id);
    }
    for w in window_order {
        var listed = false;
        for o in order { if o == w { listed = true; } }
        if !listed { order.push(w); }
    }
    window_order.clear();
    for w in order { window_order.push(w); }
    for p in saved_panes { pane_fractions.insert(p.id, p.fraction); }
    for o in saved_open { opened.insert(o.id, if o.open { 1 } else { 2 }); }
    return true, str("");
}

// The layout in the file at `path`: false, and nothing changed, if there
// is none or it isn't one. A file left by another version is an ordinary
// thing for a program to meet, so that isn't misuse: what's wrong with it
// goes to stderr, and the program goes on to its default layout.
fn load_layout(path: const u8[:]) -> bool {
    var text: u8[>..] = [];
    guard read_file(path, text) else { return false; }
    let ok, err = load_layout_json(text[..]);
    if !ok { write_stderr(str("imgui: ", path, ": ", err, "\n")); }
    ok
}
