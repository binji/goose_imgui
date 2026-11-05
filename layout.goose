// The layout solver. The frame's nodes are in pre-order, so every child
// comes after its parent, and the solver is a handful of passes over the
// array, none recursive:
//
//   1. fit widths, last node first: what each would like, and the least it
//      can be, from its content up;
//   2. widths, first node first: each container shares its width among its
//      children (grow, shrink, stretch, percentages, grid columns);
//   3. wrapped text measured at its width;
//   4. fit heights, last first, as 1 (wrapping rows broken into lines);
//   5. heights, first first, as 2;
//   6. positions, first first: justify, align, grid cells, scrolling,
//      absolute children, and the popups' anchors.
//
// Sizes along an axis are a Size: fit (the content's), px, grow (the
// content's, and a weighted share of what is left), pct (of the parent's
// inner size); each within lo..hi.

namespace imgui;

import std;
import vec;
import math;
import gfx;
import gfx2d;

// --- per axis -------------------------------------------------------------------------

fn ax(v: float2, a: i64) -> f32 { if a == 0 { v.x } else { v.y } }
fn set_ax(v: float2&, a: i64, x: f32) { if a == 0 { v.x = x; } else { v.y = x; } }
fn rsize(r: gfx2d::Rect, a: i64) -> f32 { if a == 0 { r.w } else { r.h } }
fn set_rsize(r: gfx2d::Rect&, a: i64, x: f32) { if a == 0 { r.w = x; } else { r.h = x; } }
fn rpos(r: gfx2d::Rect, a: i64) -> f32 { if a == 0 { r.x } else { r.y } }
fn set_rpos(r: gfx2d::Rect&, a: i64, x: f32) { if a == 0 { r.x = x; } else { r.y = x; } }
fn dim_of(n: Node&, a: i64) -> Size { if a == 0 { n.d.dim.w } else { n.d.dim.h } }
fn pad_lo(n: Node&, a: i64) -> f32 { if a == 0 { n.d.lay.padding.x } else { n.d.lay.padding.y } }
fn pad_sum(n: Node&, a: i64) -> f32 {
    if a == 0 { n.d.lay.padding.x + n.d.lay.padding.z } else { n.d.lay.padding.y + n.d.lay.padding.w }
}
fn gap_of(n: Node&, a: i64) -> f32 { ax(n.d.lay.spacing, a) }
fn scrolls(n: Node&, a: i64) -> bool {
    n.d.bits & (if a == 0 { SCROLLS_X | OVERFLOW_X } else { SCROLLS_Y | OVERFLOW_Y }) != 0
}
fn in_flow(n: Node&) -> bool { !n.d.lay.absolute }
// The axis a row or column lays its children along; -1 for a stack or grid.
fn main_axis(n: Node&) -> i64 {
    if n.kind != NODE_BOX { return -1; }
    match n.d.lay.kind { ROW => 0, COLUMN => 1, _ => -1 }
}
fn is_grid(n: Node&) -> bool { n.kind == NODE_BOX && n.d.lay.kind == GRID }
fn inner_size(n: Node&, a: i64) -> f32 { max(rsize(n.rect, a) - pad_sum(n, a), 0.0) }
fn child_align(parent: Node&, child: Node&) -> u8 {
    if child.d.lay.self_align != INHERIT { child.d.lay.self_align } else { parent.d.lay.align }
}

fn track_at(n: Node&, a: i64, k: i64) -> f32 {
    tracks[n.tracks + (if a == 0 { 0 } else { n.ncols }) + k]
}
fn set_track(n: Node&, a: i64, k: i64, v: f32) {
    tracks[n.tracks + (if a == 0 { 0 } else { n.ncols }) + k] = v;
}
fn track_count(n: Node&, a: i64) -> i64 { if a == 0 { n.ncols } else { n.nrows } }
fn track_desc(n: Node&, a: i64, k: i64) -> Size {
    if a == 0 {
        if k < n.d.lay.columns.len { return n.d.lay.columns[k]; }
        return grow();
    }
    if k < n.d.lay.rows.len { return n.d.lay.rows[k]; }
    fit()
}
fn cell_pos(c: Node&, a: i64) -> i64 { if a == 0 { c.col } else { c.row } }
fn cell_span(c: Node&, a: i64) -> i64 { if a == 0 { c.d.lay.col_span } else { c.d.lay.row_span } }

// --- the passes ---------------------------------------------------------------------

fn layout_all() {
    let n = nodes.len as i32;
    // Grids' cells, before anything is measured.
    for i: i32 in 0..n { if is_grid(nodes[i]) { place_grid(i); } }
    var i = n - 1;
    while i >= 0 { fit_node(i, 0); i--; }
    for j: i32 in 0..n { resolve_node(j, 0); }
    for j: i32 in 0..n { measure_wrapped(j); }
    i = n - 1;
    while i >= 0 { fit_node(i, 1); i--; }
    for j: i32 in 0..n { resolve_node(j, 1); }
    for j: i32 in 0..n { position_node(j); }
}

// A grid's children into cells: in order, along the rows, or where cell()
// puts them; its tracks' sizes then have room in `tracks`.
fn place_grid(i: i32) {
    let g .= nodes[i];
    let ncols = max(g.d.lay.columns.len, 1);
    var col = 0;
    var row = 0;
    var rows = g.d.lay.rows.len;
    var c = g.first;
    while c >= 0 {
        let k .= nodes[c];
        if in_flow(k) {
            let span = min(k.d.lay.col_span as i64, ncols);
            if k.d.lay.col >= 0 || k.d.lay.row >= 0 {
                k.col = max(k.d.lay.col as i64, 0) as i16;
                k.row = max(k.d.lay.row as i64, 0) as i16;
            } else {
                if col + span > ncols { col = 0; row++; }
                k.col = col as i16;
                k.row = row as i16;
                col += span;
            }
            rows = max(rows, k.row + k.d.lay.row_span);
        }
        c = k.next;
    }
    g.tracks = tracks.len as i32;
    g.ncols = ncols as i16;
    g.nrows = rows as i16;
    for t in ncols + rows { tracks.push(0.0); }
}

// Pass 1 and 4: what node i would like to be along `a`, and the least.
fn fit_node(i: i32, a: i64) {
    let n .= nodes[i];
    var content: f32 = 0.0;
    var least: f32 = 0.0;
    if n.kind == NODE_TEXT || n.kind == NODE_RICH {
        if a == 0 {
            content = n.natural.x;
            least = if n.d.lay.wrap { n.word } else { n.natural.x };
        } else {
            content = n.content.y;
            least = content;
        }
    } else if n.kind == NODE_IMAGE || n.kind == NODE_ICON {
        content = ax(n.natural, a);
        least = if n.kind == NODE_ICON { content } else { 0.0 };
    } else if is_grid(n) {
        content, least = fit_grid(i, a);
    } else {
        let m = main_axis(n);
        let g = gap_of(n, a);
        var count = 0;
        var c = n.first;
        if m == a && !(n.d.lay.wrap && a == 1 && m == 0) {
            while c >= 0 {
                let k .= nodes[c];
                if in_flow(k) {
                    content += ax(k.fit, a);
                    least = if n.d.lay.wrap { max(least, ax(k.least, a)) } else { least + ax(k.least, a) };
                    count++;
                }
                c = k.next;
            }
            if count > 1 {
                content += g * (count - 1);
                if !n.d.lay.wrap { least += g * (count - 1); }
            }
        } else if n.d.lay.wrap && m == 0 && a == 1 {
            content = wrapped_height(i);
            least = content;
        } else {
            while c >= 0 {
                let k .= nodes[c];
                if in_flow(k) {
                    content = max(content, ax(k.fit, a));
                    least = max(least, ax(k.least, a));
                }
                c = k.next;
            }
        }
    }
    let pads = pad_sum(n, a);
    content += pads;
    least += pads;
    if scrolls(n, a) || (a == 0 && n.d.bits & SHRINKS != 0) { least = pads; }
    let s = dim_of(n, a);
    var fit: f32 = 0.0;
    if s.kind == SIZE_PX {
        fit = max(s.value, s.lo);
        least = fit;
    } else {
        fit = clamp(content, s.lo, max(s.hi, s.lo));
        least = clamp(least, s.lo, fit);
    }
    set_ax(n.fit, a, fit);
    set_ax(n.least, a, least);
}

// A grid's fit along `a`: its tracks' sizes from their single-cell
// children's, written into its tracks, and their sum.
fn fit_grid(i: i32, a: i64) -> f32, f32 {
    let g .= nodes[i];
    let count = track_count(g, a);
    var content: f32 = 0.0;
    var least: f32 = 0.0;
    for k in count {
        let t = track_desc(g, a, k);
        var want: f32 = 0.0;
        var low: f32 = 0.0;
        if t.kind == SIZE_PX {
            want = t.value;
            low = t.value;
        } else {
            var c = g.first;
            while c >= 0 {
                let ch .= nodes[c];
                if in_flow(ch) && cell_pos(ch, a) == k && cell_span(ch, a) == 1 {
                    want = max(want, ax(ch.fit, a));
                    low = max(low, ax(ch.least, a));
                }
                c = ch.next;
            }
            want = clamp(want, t.lo, max(t.hi, t.lo));
            if t.kind == SIZE_PCT { low = 0.0; }
        }
        set_track(g, a, k, want);
        content += want;
        least += low;
    }
    if count > 1 {
        content += gap_of(g, a) * (count - 1);
        least += gap_of(g, a) * (count - 1);
    }
    return content, least;
}

// The height of a wrapping row's lines, its children's widths known.
fn wrapped_height(i: i32) -> f32 {
    let n .= nodes[i];
    let inner = inner_size(n, 0);
    let gx = gap_of(n, 0);
    let gy = gap_of(n, 1);
    var total: f32 = 0.0;
    var line_w: f32 = 0.0;
    var line_h: f32 = 0.0;
    var lines = 0;
    var in_line = 0;
    var c = n.first;
    while c >= 0 {
        let k .= nodes[c];
        if in_flow(k) {
            let w = k.rect.w;
            if in_line > 0 && line_w + gx + w > inner + 0.01 {
                total += line_h;
                lines++;
                line_w = 0.0;
                line_h = 0.0;
                in_line = 0;
            }
            line_w += (if in_line > 0 { gx } else { 0.0 }) + w;
            line_h = max(line_h, k.fit.y);
            in_line++;
        }
        c = k.next;
    }
    if in_line > 0 {
        total += line_h;
        lines++;
    }
    if lines > 1 { total += gy * (lines - 1); }
    total
}

// Pass 2 and 5: node i's size along `a` is known (a root's set here); its
// children's from it.
fn resolve_node(i: i32, a: i64) {
    let n .= nodes[i];
    if n.parent < 0 {
        // A root: the main one is the viewport; a popup is its fit, in it.
        let r = roots[n.root];
        if r.anchor.kind == ANCHOR_VIEWPORT {
            set_rsize(n.rect, a, rsize(viewport, a));
        } else {
            set_rsize(n.rect, a, min(ax(n.fit, a), rsize(viewport, a)));
        }
    }
    if n.kind != NODE_BOX || n.first < 0 { return; }
    let inner = inner_size(n, a);
    let m = main_axis(n);
    if is_grid(n) {
        resolve_grid(i, a, inner);
    } else if m == a && !(n.d.lay.wrap && m == 0) {
        share_main(i, a, inner);
    } else if n.d.lay.wrap && m == 0 {
        if a == 0 { share_wrapped(i, inner); } else { stretch_lines(i, inner); }
    } else {
        var c = n.first;
        while c >= 0 {
            let k .= nodes[c];
            if in_flow(k) {
                let al = if n.d.lay.kind == STACK && a == 0 { k.d.lay.self_justify } else { child_align(n, k) };
                set_rsize(k.rect, a, cross_size(k, a, inner, al, scrolls(n, a)));
            }
            c = k.next;
        }
    }
    // Absolute children: their own size, percentages of the inner box.
    var c = n.first;
    while c >= 0 {
        let k .= nodes[c];
        if !in_flow(k) { set_rsize(k.rect, a, cross_size(k, a, inner, START, false)); }
        c = k.next;
    }
}

// A child's size across its parent, or in a stack: `inner` is the room.
fn cross_size(k: Node&, a: i64, inner: f32, al: u8, unbounded: bool) -> f32 {
    let s = dim_of(k, a);
    let hi = max(s.hi, s.lo);
    if s.kind == SIZE_PX { return max(s.value, s.lo); }
    if s.kind == SIZE_PCT { return clamp(s.value * inner, s.lo, hi); }
    if unbounded { return ax(k.fit, a); }
    if s.kind == SIZE_GROW || al == STRETCH { return clamp(max(inner, ax(k.least, a)), s.lo, hi); }
    // Fit: its content's size, but no more than there is, and no less than
    // its least.
    clamp(min(ax(k.fit, a), max(inner, ax(k.least, a))), s.lo, hi)
}

// Whether a child shrinks when its siblings do not fit: not if its size is
// px or a percentage.
fn shrinks(k: Node&, a: i64) -> bool {
    let kind = dim_of(k, a).kind;
    kind != SIZE_PX && kind != SIZE_PCT
}

// The base size of a child along its parent's main axis.
fn base_size(k: Node&, a: i64, inner: f32) -> f32 {
    let s = dim_of(k, a);
    if s.kind == SIZE_PCT { return clamp(s.value * inner, s.lo, max(s.hi, s.lo)); }
    ax(k.fit, a)
}

// Along a row or column: each child its base size, then what is left
// shared among the growing ones by weight, or what is missing taken from
// the shrinkable ones in proportion to how far they can shrink.
fn share_main(i: i32, a: i64, inner: f32) {
    let n .= nodes[i];
    share_run(n.first, -1, a, inner, gap_of(n, a), scrolls(n, a));
}

// The in-flow children from `first` up to (not including) `stop`.
fn share_run(first: i32, stop: i32, a: i64, inner: f32, g: f32, unbounded: bool) {
    var used: f32 = 0.0;
    var count = 0;
    var weight: f32 = 0.0;
    var c = first;
    while c >= 0 && c != stop {
        let k .= nodes[c];
        if in_flow(k) {
            let b = base_size(k, a, inner);
            set_rsize(k.rect, a, b);
            used += b;
            count++;
            let s = dim_of(k, a);
            if s.kind == SIZE_GROW { weight += s.value; }
        }
        c = k.next;
    }
    if count > 1 { used += g * (count - 1); }
    var free = inner - used;
    if free > 0.0 && weight > 0.0 {
        // Up to three rounds: a child held at its max gives its share back.
        for round in 3 {
            guard free > 0.01 && weight > 0.0 else { break; }
            var given: f32 = 0.0;
            var next_weight: f32 = 0.0;
            c = first;
            while c >= 0 && c != stop {
                let k .= nodes[c];
                let s = dim_of(k, a);
                if in_flow(k) && s.kind == SIZE_GROW {
                    let cur = rsize(k.rect, a);
                    let hi = max(s.hi, s.lo);
                    if cur < hi {
                        let want = min(cur + free * s.value / weight, hi);
                        given += want - cur;
                        set_rsize(k.rect, a, want);
                        if want < hi { next_weight += s.value; }
                    }
                }
                c = k.next;
            }
            free -= given;
            weight = next_weight;
        }
    } else if free < 0.0 && !unbounded {
        var room: f32 = 0.0;
        c = first;
        while c >= 0 && c != stop {
            let k .= nodes[c];
            if in_flow(k) && shrinks(k, a) { room += max(rsize(k.rect, a) - ax(k.least, a), 0.0); }
            c = k.next;
        }
        if room > 0.0 {
            let f = min(-free / room, 1.0);
            c = first;
            while c >= 0 && c != stop {
                let k .= nodes[c];
                if in_flow(k) && shrinks(k, a) {
                    let cur = rsize(k.rect, a);
                    set_rsize(k.rect, a, cur - max(cur - ax(k.least, a), 0.0) * f);
                }
                c = k.next;
            }
        }
    }
}

// A wrapping row's widths: each line's run shared as a row is.
fn share_wrapped(i: i32, inner: f32) {
    let n .= nodes[i];
    let gx = gap_of(n, 0);
    var line_start = n.first;
    var line_w: f32 = 0.0;
    var in_line = 0;
    var c = n.first;
    while c >= 0 {
        let k .= nodes[c];
        if in_flow(k) {
            let w = min(base_size(k, 0, inner), inner);
            if in_line > 0 && line_w + gx + w > inner + 0.01 {
                share_run(line_start, c, 0, inner, gx, false);
                line_start = c;
                line_w = 0.0;
                in_line = 0;
            }
            line_w += (if in_line > 0 { gx } else { 0.0 }) + w;
            in_line++;
        }
        c = k.next;
    }
    if in_line > 0 { share_run(line_start, -1, 0, inner, gx, false); }
}

// A wrapping row's heights: across each line, as a row's are across it.
fn stretch_lines(i: i32, inner: f32) {
    let n .= nodes[i];
    each_wrapped_line(i) { first, stop, line_h =>
        var c = first;
        while c >= 0 && c != stop {
            let k .= nodes[c];
            if in_flow(k) { set_rsize(k.rect, 1, cross_size(k, 1, line_h, child_align(n, k), false)); }
            c = k.next;
        }
    };
}

// Each line of a wrapping row, its widths known: its first child, the
// child after its last (or -1), and its height.
fn each_wrapped_line<F>(i: i32) {
    let n .= nodes[i];
    let inner = inner_size(n, 0);
    let gx = gap_of(n, 0);
    var line_start = n.first;
    var line_w: f32 = 0.0;
    var line_h: f32 = 0.0;
    var in_line = 0;
    var c = n.first;
    while c >= 0 {
        let k .= nodes[c];
        if in_flow(k) {
            let w = k.rect.w;
            if in_line > 0 && line_w + gx + w > inner + 0.01 {
                F(line_start, c, line_h);
                line_start = c;
                line_w = 0.0;
                line_h = 0.0;
                in_line = 0;
            }
            line_w += (if in_line > 0 { gx } else { 0.0 }) + w;
            line_h = max(line_h, k.fit.y);
            in_line++;
        }
        c = k.next;
    }
    let none: i32 = -1;
    if in_line > 0 { F(line_start, none, line_h); }
}

// A grid's tracks along `a` from its inner size, and its children's sizes
// from their cells.
fn resolve_grid(i: i32, a: i64, inner: f32) {
    let g .= nodes[i];
    let count = track_count(g, a);
    let gap = gap_of(g, a);
    var used: f32 = if count > 1 { gap * (count - 1) } else { 0.0 };
    var weight: f32 = 0.0;
    for k in count {
        let t = track_desc(g, a, k);
        if t.kind == SIZE_GROW {
            weight += t.value;
        } else {
            if t.kind == SIZE_PCT { set_track(g, a, k, t.value * inner); }
            used += track_at(g, a, k);
        }
    }
    let free = max(inner - used, 0.0);
    for k in count {
        let t = track_desc(g, a, k);
        if t.kind == SIZE_GROW {
            let share = if weight > 0.0 { free * t.value / weight } else { 0.0 };
            // A growing column is its share; a growing row at least its content.
            let v = if a == 0 { share } else { max(share, track_at(g, a, k)) };
            set_track(g, a, k, clamp(v, t.lo, max(t.hi, t.lo)));
        }
    }
    let al = if a == 0 { g.d.lay.justify } else { g.d.lay.align };
    var c = g.first;
    while c >= 0 {
        let k .= nodes[c];
        if in_flow(k) {
            let at = cell_pos(k, a);
            let span = cell_span(k, a);
            var cell: f32 = 0.0;
            for s in at..min(at + span, count) { cell += track_at(g, a, s); }
            if span > 1 { cell += gap * (min(at + span, count) - at - 1); }
            set_rsize(k.rect, a, cross_size(k, a, cell, if k.d.lay.self_align != INHERIT { k.d.lay.self_align } else { al },
                                            false));
        }
        c = k.next;
    }
}

// Pass 3: wrapped text's height at its width.
fn measure_wrapped(i: i32) {
    let n .= nodes[i];
    guard n.kind == NODE_TEXT || n.kind == NODE_RICH;
    if n.kind == NODE_RICH && n.d.lay.wrap && n.rect.w + 0.5 < n.natural.x {
        n.content.y = rich_height(i, n.rect.w);
    } else if n.kind == NODE_TEXT && n.d.lay.wrap && n.rect.w + 0.5 < n.natural.x {
        var style = text_style_of(n);
        style.wrap_width = n.rect.w;
        n.content.y = gfx2d::measure_text(node_text(i), style).y;
    } else {
        n.content.y = n.natural.y;
    }
}

// Pass 6: node i is placed (a root here, by its anchor); its children in
// its inner box.
fn position_node(i: i32) {
    let n .= nodes[i];
    if n.parent < 0 { place_root(i); }
    if n.kind != NODE_BOX || n.first < 0 { return; }
    let origin = float2 { n.rect.x + n.d.lay.padding.x, n.rect.y + n.d.lay.padding.y };
    let at = origin - n.scroll;
    let inner = float2 { inner_size(n, 0), inner_size(n, 1) };
    let m = main_axis(n);
    if is_grid(n) {
        place_cells(i, at);
    } else if m >= 0 && n.d.lay.wrap && m == 0 {
        let gy = gap_of(n, 1);
        var y = at.y;
        each_wrapped_line(i) { first, stop, line_h =>
            place_run(i, first, stop, 0, at.x, inner.x, y, line_h);
            y += line_h + gy;
        };
    } else if m >= 0 {
        let cross = 1 - m;
        place_run(i, n.first, -1, m, ax(at, m), ax(inner, m), ax(at, cross), ax(inner, cross));
    } else {
        // A stack: each child placed in the whole inner box.
        var c = n.first;
        while c >= 0 {
            let k .= nodes[c];
            if in_flow(k) {
                let h = k.d.lay.self_justify;
                let v = if k.d.lay.self_align != INHERIT { k.d.lay.self_align } else { n.d.lay.align };
                k.rect.x = at.x + offset_in(inner.x, k.rect.w, h);
                k.rect.y = at.y + offset_in(inner.y, k.rect.h, v);
            }
            c = k.next;
        }
    }
    // Absolute children, at their place in the inner box, not scrolled;
    // and how far the flow reaches, for scrolling.
    var reach = float2_0;
    var c = n.first;
    while c >= 0 {
        let k .= nodes[c];
        if in_flow(k) {
            reach.x = max(reach.x, k.rect.x + k.rect.w - at.x);
            reach.y = max(reach.y, k.rect.y + k.rect.h - at.y);
        } else {
            k.rect.x = origin.x + k.d.lay.at.x - k.rect.w * k.d.lay.pivot_x / PIVOT_UNIT;
            k.rect.y = origin.y + k.d.lay.at.y - k.rect.h * k.d.lay.pivot_y / PIVOT_UNIT;
        }
        c = k.next;
    }
    n.content = reach;
}

fn offset_in(room: f32, size: f32, al: u8) -> f32 {
    match al { CENTER => (room - size) * 0.5, END => room - size, _ => 0.0 }
}

// A run of children along axis m from `start` in `room`, justified; across
// it at `cross_at` in `cross_room`, aligned.
fn place_run(i: i32, first: i32, stop: i32, m: i64, start: f32, room: f32, cross_at: f32, cross_room: f32) {
    let n .= nodes[i];
    let cross = 1 - m;
    let g = gap_of(n, m);
    var used: f32 = 0.0;
    var count = 0;
    var c = first;
    while c >= 0 && c != stop {
        let k .= nodes[c];
        if in_flow(k) { used += rsize(k.rect, m); count++; }
        c = k.next;
    }
    if count > 1 { used += g * (count - 1); }
    let free = max(room - used, 0.0);
    var pos = start;
    var between = g;
    match n.d.lay.justify {
        CENTER => { pos += free * 0.5; },
        END => { pos += free; },
        SPACE_BETWEEN => { if count > 1 { between += free / (count - 1); } },
        SPACE_AROUND => { if count > 0 { pos += free / count * 0.5; between += free / count; } },
        SPACE_EVENLY => { if count > 0 { pos += free / (count + 1); between += free / (count + 1); } },
        _ => {},
    }
    c = first;
    while c >= 0 && c != stop {
        let k .= nodes[c];
        if in_flow(k) {
            set_rpos(k.rect, m, pos);
            set_rpos(k.rect, cross, cross_at + offset_in(cross_room, rsize(k.rect, cross), child_align(n, k)));
            pos += rsize(k.rect, m) + between;
        }
        c = k.next;
    }
}

// A grid's children in their cells; one smaller than its cell placed in it
// by the grid's justify and align (or its own self_align).
fn place_cells(i: i32, at: float2) {
    let g .= nodes[i];
    let gx = gap_of(g, 0);
    let gy = gap_of(g, 1);
    var c = g.first;
    while c >= 0 {
        let k .= nodes[c];
        if in_flow(k) {
            var x = at.x;
            for s in k.col { x += track_at(g, 0, s) + gx; }
            var y = at.y;
            for s in k.row { y += track_at(g, 1, s) + gy; }
            var cw: f32 = 0.0;
            let c1 = min(k.col as i64 + k.d.lay.col_span, g.ncols);
            for s in k.col..c1 { cw += track_at(g, 0, s); }
            if c1 - k.col > 1 { cw += gx * (c1 - k.col - 1); }
            var ch: f32 = 0.0;
            let r1 = min(k.row as i64 + k.d.lay.row_span, g.nrows);
            for s in k.row..r1 { ch += track_at(g, 1, s); }
            if r1 - k.row > 1 { ch += gy * (r1 - k.row - 1); }
            let h = if k.d.lay.self_align != INHERIT { k.d.lay.self_align } else { g.d.lay.justify };
            let v = if k.d.lay.self_align != INHERIT { k.d.lay.self_align } else { g.d.lay.align };
            k.rect.x = x + offset_in(cw, k.rect.w, h);
            k.rect.y = y + offset_in(ch, k.rect.h, v);
        }
        c = k.next;
    }
}

// A root's place: the viewport's top left, or by its anchor, kept inside
// the viewport.
fn place_root(i: i32) {
    let n .= nodes[i];
    let a = roots[n.root].anchor;
    var r = a.rect;
    if a.node >= 0 { r = nodes[a.node].rect; }
    var x = viewport.x;
    var y = viewport.y;
    match a.kind {
        ANCHOR_POINT => { x = a.at.x; y = a.at.y; },
        ANCHOR_BELOW => { x = r.x; y = r.y + r.h + 2.0; },
        ANCHOR_RIGHT => { x = r.x + r.w; y = r.y; },
        ANCHOR_CENTER => {
            x = viewport.x + (viewport.w - n.rect.w) * 0.5;
            y = viewport.y + (viewport.h - n.rect.h) * 0.5;
        },
        _ => {},
    }
    // Inside the viewport: a menu that would run off the right opens to the
    // left of its anchor instead.
    if x + n.rect.w > viewport.x + viewport.w {
        x = if a.kind == ANCHOR_RIGHT { r.x - n.rect.w } else { viewport.x + viewport.w - n.rect.w };
    }
    if y + n.rect.h > viewport.y + viewport.h {
        y = if a.kind == ANCHOR_BELOW { r.y - n.rect.h - 2.0 } else { viewport.y + viewport.h - n.rect.h };
    }
    n.rect.x = max(x, viewport.x);
    n.rect.y = max(y, viewport.y);
}

// --- placing by the screen ----------------------------------------------------------------

// Where to put a marker for p, a point in the UI's space: p itself if it
// is inside r, or else where the line from r's center to p leaves r. Also
// the angle from the center to p (radians, clockwise from +x, as arcs
// are), for an arrow that points to it, and whether p is inside.
//   let at, angle, seen = imgui::edge_clamp(enemy_on_screen, 40);
fn edge_clamp(p: float2, r: gfx2d::Rect) -> float2, f64, bool {
    let c = float2 { r.x + r.w * 0.5, r.y + r.h * 0.5 };
    let d = p - c;
    let angle: f64 = atan2(d.y, d.x);
    if p.x >= r.x && p.y >= r.y && p.x <= r.x + r.w && p.y <= r.y + r.h { return p, angle, true; }
    let f = min(r.w * 0.5 / max(abs(d.x), 0.0001), r.h * 0.5 / max(abs(d.y), 0.0001));
    return c + d * f, angle, false;
}
// Inside the viewport, `inset` from its edges.
fn edge_clamp(p: float2, inset: f64) -> float2, f64, bool {
    let k = inset as f32;
    return edge_clamp(p, gfx2d::Rect { viewport.x + k, viewport.y + k, max(viewport.w - 2.0 * k, 0.0),
                                       max(viewport.h - 2.0 * k, 0.0) });
}
