// Splitters: panes side by side (or one above another), resized by
// dragging the handle between two of them.
//
//   imgui::split("main", imgui::ROW, imgui::row().grow()) {
//       imgui::pane("tree", 0.25) { scene_tree(); };
//       imgui::pane("view") { viewport(); };
//       imgui::pane("inspector", 0.3) { inspector(); };
//   };

namespace imgui;

import std;
import vec;
import math;
import dictionary;
import gfx2d;

struct SplitCtx {
    id: u64 = 0,
    axis: i64 = 0,              // 0: across (a row), 1: down (a column)
    len: f32 = 0.0,             // its length along the axis, last frame
    count: i64 = 0,             // panes recorded so far
    prev: u64 = 0,              // the pane before the next handle
    share: f32 = 0.0,           // each sharing pane's length (0: unknown yet; they grow)
    last_free: i64 = -1,        // the last sharing pane, which grows to take what rounding leaves
    panes: i64 = 0,             // how many there were last frame
}
var split_stack: SplitCtx[>..<] = [];

let PANE_LEAST: f32 = 32.0;     // the least a pane is, along the split

// Each pane's fraction of its split's length, once it has one (none: it
// shares what the others leave). Kept apart from its state, which goes
// when the pane isn't recorded for a while, and saved with the layout.
var pane_fractions = dictionary<u64, f64> {};
fn pane_fraction(i: u64, at_first: f64) -> f64 {
    let f = pane_fractions.get(i);
    if f { return f; }
    at_first
}
fn set_pane_fraction(i: u64, f: f64) { pane_fractions.insert(i, f); }

// Panes along `axis` (ROW: side by side; COLUMN: one above another), each
// recorded by pane(…) in the block, a handle between each two.
fn split<F>(label: const u8[:], axis: i64 = ROW, d: Desc = row()) {
    let i = id(label);
    var st = state_of(i.v);
    let a = if axis == COLUMN { 1 } else { 0 };
    let len = rsize(st.rect, a);
    // The handles dragged: known before the panes are recorded, so they
    // take their new sizes this frame. Each handle keeps the panes on its
    // sides (`owner` and `span`), its press the first one's length (`num`)
    // and the two's together (`value`).
    let count = st.index as i64;
    for k in 1..count {
        let hid = sub_id(i, k);
        var hs = state_of(hid.v);
        let it = interact(hid, column().hit());
        if it.pressed {
            let before = rsize(state_of(hs.owner).rect, a);
            hs.num = before;
            hs.value = before + rsize(state_of(hs.span).rect, a);
            put_state(hid.v, hs);
        }
        if it.held && len > 0.0 {
            // The pane before takes the length the handle leaves it; the
            // one after, if it has a fraction, keeps the two's total.
            let total = hs.value;
            let moved = if a == 0 { it.drag.x } else { it.drag.y };
            let first = clamp(hs.num + moved, PANE_LEAST, max(total - PANE_LEAST, PANE_LEAST));
            set_pane_fraction(hs.owner, first / len);
            if pane_fraction(hs.span, 0.0) > 0.0 { set_pane_fraction(hs.span, (total - first) / len); }
        }
        if it.hovered || it.held { wanted_cursor = if a == 0 { CURSOR_EW_RESIZE } else { CURSOR_NS_RESIZE }; }
    }
    // The panes, as last frame's handles knew them: those with a fraction
    // take it; the rest share what is left.
    var ctx = SplitCtx { id: i.v, axis: a, len: len, panes: count, .. };
    if count > 1 && len > 0.0 {
        let t = class_style(SPLITTER).normal.min_size.x;
        var fixed: f32 = 0.0;
        var free = 0;
        for k in count {
            let pid = if k == 0 { state_of(sub_id(i, 1).v).owner } else { state_of(sub_id(i, k).v).span };
            let f = pane_fraction(pid, 0.0);
            if f > 0.0 { fixed += max(f * len, PANE_LEAST) as f32; } else { free++; ctx.last_free = k; }
        }
        if free > 0 { ctx.share = max((len - t * (count - 1) - fixed) / free, PANE_LEAST); }
    }
    var sd = d.gap(0);
    sd.lay.kind = if a == 0 { ROW } else { COLUMN };
    if sd.dim.w.kind == SIZE_FIT { sd = sd.grow_w(); }
    if sd.dim.h.kind == SIZE_FIT { sd = sd.grow_h(); }
    box(i, sd.align(STRETCH)) {
        split_stack.push(ctx);
        F();
        let ctx = split_stack.pop();
        st.index = ctx.count as i32;
    };
    st.seen = frame_index;
    put_state(i.v, st);
}

// A pane in a split: `fraction` of its length to start with (0: a share of
// what the others leave), and what it is dragged to after. Its content is
// cut off at its edges.
fn pane<F>(label: const u8[:], fraction: f64 = 0.0, d: Desc = column()) {
    guard split_stack.len > 0 else { misuse("pane: not inside split"); return; }
    let k = split_stack.len - 1;
    let ctx = split_stack[k];
    let i = id(label);
    let a = ctx.axis;
    if ctx.count > 0 {
        // The handle before it, between it and the pane before.
        let hid = sub_id(Id { ctx.id }, ctx.count);
        var hs = state_of(hid.v);
        hs.owner = ctx.prev;
        hs.span = i.v;
        put_state(hid.v, hs);
        let t = class_style(SPLITTER).normal.min_size.x;
        let it = interact(hid, column().hit());
        var hd = column().skin(SPLITTER).hit().look(look_of(it));
        hd = if a == 0 { hd.width(t).grow_h() } else { hd.height(t).grow_w() };
        panel(hid, hd);
    }
    // Its fraction to start with, kept: the split reads it before the
    // panes are recorded.
    if !pane_fractions.contains(i.v) && fraction > 0.0 { set_pane_fraction(i.v, fraction); }
    let f = pane_fraction(i.v, fraction);
    let index = ctx.count;
    // Its length: its fraction's, or its share; or it grows: the last
    // sharing pane (or the last pane, if none share), to take what rounding
    // leaves, and every pane until the split's length is known.
    var px_len: f32 = 0.0;
    let grows = ctx.len <= 0.0 || index >= ctx.panes || index == ctx.last_free ||
                (ctx.last_free < 0 && index == ctx.panes - 1);
    if !grows {
        px_len = if f > 0.0 { max(f * ctx.len, PANE_LEAST) as f32 } else { ctx.share };
    }
    var pd = d.clip().with_bits(SHRINKS);
    if px_len > 0.0 {
        pd = if a == 0 { pd.width(px_len).grow_h() } else { pd.height(px_len).grow_w() };
    } else {
        pd = pd.grow();
        pd = if a == 0 { pd.min_w(PANE_LEAST) } else { pd.min_h(PANE_LEAST) };
    }
    box(i, pd) { F(); };
    split_stack[k].prev = i.v;
    split_stack[k].count = ctx.count + 1;
}
