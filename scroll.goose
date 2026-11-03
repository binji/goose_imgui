// Scroll panes: a box whose children are clipped to it and moved by its
// scroll offset; scrolled by the wheel over it, by dragging its scrollbar's
// thumb, by dragging its content (scroll_drag), and to keep the focus in
// view. Its size is its Desc's (a fit pane is as big as its content, and
// so never scrolls): px, grow or pct, along the axes it scrolls.
//
//   imgui::scroll("log", imgui::column().gap(4).height(240).grow_w()) {
//       for line in log { imgui::text(line); }
//   };

namespace imgui;

import std;
import vec;
import math;
import gfx2d;

let WHEEL_STEP: f32 = 48.0;     // pixels a line of wheel scrolls

struct ScrollInfo { offset: float2, content: float2, view: float2 }

// A scroll pane: along `axes` (SCROLLS_Y, SCROLLS_X, or both).
fn scroll<F>(label: const u8[:], d: Desc, axes: i64 = SCROLLS_Y) -> ScrollInfo {
    let i = id(label);
    let thumb_id = sub_id(i, "thumb y");
    let thumb_x_id = sub_id(i, "thumb x");
    var st = state_of(i.v);
    let limit = float2 { max(st.content.x - st.view.x, 0.0), max(st.content.y - st.view.y, 0.0) };
    let ax_bits = axes as u32;
    if wheel_id == i.v {
        let w = input.pointer.wheel;
        if ax_bits & SCROLLS_Y != 0 {
            st.scroll_to.y -= w.y * WHEEL_STEP;
            if ax_bits & SCROLLS_X != 0 { st.scroll_to.x -= w.x * WHEEL_STEP; }
        } else {
            st.scroll_to.x -= (w.x + w.y) * WHEEL_STEP;
        }
    }
    // Dragging a thumb: the content follows, by the ratio of the content to
    // the view.
    let ty = interaction_for(thumb_id.v, column().hit());
    if ty.pressed { st.value = st.scroll.y; }
    if ty.held && st.view.y > 0.0 {
        st.scroll_to.y = st.value + ty.drag.y * (st.rect.h / max(st.screen.h, 0.0001)) * (st.content.y / st.view.y);
    }
    let tx = interaction_for(thumb_x_id.v, column().hit());
    if tx.pressed { st.value = st.scroll.x; }
    if tx.held && st.view.x > 0.0 {
        st.scroll_to.x = st.value + tx.drag.x * (st.content.x / st.view.x) * (st.rect.w / max(st.screen.w, 0.0001));
    }
    st.scroll_to = float2 { clamp(st.scroll_to.x, 0.0, limit.x), clamp(st.scroll_to.y, 0.0, limit.y) };
    if ax_bits & SCROLLS_X == 0 { st.scroll_to.x = 0.0; }
    if ax_bits & SCROLLS_Y == 0 { st.scroll_to.y = 0.0; }
    // Eased toward where it is going; at once while dragged.
    if ty.held || tx.held {
        st.scroll = st.scroll_to;
    } else {
        let k = (1.0 - exp(-delta * 18.0)) as f32;
        st.scroll += (st.scroll_to - st.scroll) * k;
        if abs(st.scroll.x - st.scroll_to.x) < 0.25 && abs(st.scroll.y - st.scroll_to.y) < 0.25 { st.scroll = st.scroll_to; }
    }
    put_state(i.v, st);
    let at = nodes.len as i32;
    box(i, d.clip().with_bits(ax_bits)) {
        nodes[at].scroll = st.scroll;
        F();
        // The scrollbars, over the content, not scrolled.
        let bar = class_style(SCROLLBAR).normal.min_size.x;
        let min_thumb = class_style(SCROLL_THUMB).normal.min_size.y;
        if ax_bits & SCROLLS_Y != 0 && st.content.y > st.view.y + 0.5 {
            let view = st.view.y;
            let len = max(view * view / st.content.y, min_thumb);
            let pos = if limit.y > 0.0 { (view - len) * st.scroll.y / limit.y } else { 0.0 };
            box(column().skin(SCROLLBAR).absolute(st.view.x + nodes[at].d.lay.padding.z - bar - 2.0, 0).size(bar, view)) {
                panel(thumb_id, column().skin(SCROLL_THUMB).hit().look(look_of(ty)).absolute(0, pos).size(bar, len));
            };
        }
        if ax_bits & SCROLLS_X != 0 && st.content.x > st.view.x + 0.5 {
            let view = st.view.x;
            let len = max(view * view / st.content.x, min_thumb);
            let pos = if limit.x > 0.0 { (view - len) * st.scroll.x / limit.x } else { 0.0 };
            box(column().skin(SCROLLBAR).absolute(0, st.view.y + nodes[at].d.lay.padding.w - bar - 2.0).size(view, bar)) {
                panel(thumb_x_id, column().skin(SCROLL_THUMB).hit().look(look_of(tx)).absolute(pos, 0).size(len, bar));
            };
        }
    };
    ScrollInfo { st.scroll, st.content, st.view }
}

// Scrolls the pane `label` to an offset (or as near as its content allows).
fn scroll_to(label: const u8[:], offset: float2) {
    let i = id(label);
    var st = state_of(i.v);
    st.scroll_to = offset;
    put_state(i.v, st);
}
