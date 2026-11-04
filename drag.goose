// Drag and drop: a widget's payload carried to another widget. Items move
// between a chest and a bag, onto a trash can; a card onto an enemy.
//
//   let it = imgui::box(k, imgui::clickable(slot)) { … };
//   if imgui::drag_source(it, ITEM, k) { /* it is being carried: dim it */ }
//   let drop = imgui::drop_target(it, ITEM);
//   if drop.dropped { swap(drop.payload, k); }
//   imgui::drag_ghost(imgui::stack()) { draw_item(imgui::drag_payload()); };
//
// With the pointer: pressed on a source and moved, it is picked up; let go
// over a target that takes its kind, it is dropped there. With the keys or
// a pad: accepting a focused source (Enter, A) picks it up, navigation
// moves, and accepting a target puts it down. Escape (B) puts it back.
// While something is carried, `drop_target`'s `over` says it is over a
// target that takes it, for the target to light up.

namespace imgui;

import std;
import vec;
import gfx2d;

// A drop target's state this frame.
struct Drop {
    over: bool = false,             // what is carried, of its kind, is over it (or it has the focus)
    dropped: bool = false,          // and was let go on it this frame: take `payload`
    payload: i64 = 0,
}

var drag_on = false;
var drag_by_nav = false;            // picked up by accepting the focus, not by the pointer
var drag_src: u64 = 0;
var drag_kind: i64 = 0;
var drag_load: i64 = 0;
var drag_grab = float2 { 0.0, 0.0 };    // where on its source the pointer took it
var drag_size = float2 { 0.0, 0.0 };    // its source's size
var drop_now = false;               // this frame, what is carried is let go
var drop_to: u64 = 0;               // on this widget (0: nowhere)
var drag_held_off = false;          // put back while the pointer is down: not picked up again till it is up
let GHOST_ID: u64 = 0x6405770D;

// At the start of a frame, after input and navigation: whether what is
// carried is let go this frame, and where.
fn begin_drag() {
    drop_now = false;
    drop_to = 0;
    if !input.pointer.down { drag_held_off = false; }
    guard drag_on;
    if input.nav.cancel {
        drag_on = false;
        drag_held_off = !drag_by_nav && input.pointer.down;
        return;
    }
    if drag_by_nav {
        if input.nav.accept { drop_now = true; drop_to = focused; }
    } else if !input.pointer.down {
        drop_now = true;
        drop_to = hot;
        // Let go over its source, it is a drop, not a click.
        clicked_id = 0;
        double_id = 0;
    }
}
// At the end of a frame: a drop is over.
fn end_drag() { if drop_now { drag_on = false; } }

// Widget `it` as a source of a payload of `kind`: picked up when dragged by
// the pointer, or accepted by navigation; true while it is being carried.
fn drag_source(it: Interaction, kind: i64, payload: i64) -> bool {
    if drag_on { return drag_src == it.id; }
    let by_pointer = it.dragging && !drag_held_off;
    let by_nav = it.activated && !it.clicked && !it.held;
    guard by_pointer || by_nav else { return false; }
    drag_on = true;
    drag_by_nav = !by_pointer;
    drag_src = it.id;
    drag_kind = kind;
    drag_load = payload;
    drag_grab = if by_pointer { it.pointer - it.drag } else { float2 { it.rect.w * 0.5, it.rect.h * 0.5 } };
    drag_size = float2 { it.rect.w, it.rect.h };
    true
}

// Widget `it` as a target for payloads of `kind`. It must take the pointer
// (clickable() or hit()) to be found under it.
fn drop_target(it: Interaction, kind: i64) -> Drop {
    guard drag_on && drag_kind == kind else { return Drop { .. }; }
    let on = if drop_now { drop_to } else if drag_by_nav { focused } else { hot };
    let over = on == it.id;
    Drop { over: over, dropped: over && drop_now, payload: drag_load }
}

// What is carried: whether anything of `kind` is, and its payload.
fn dragging(kind: i64) -> bool { drag_on && drag_kind == kind }
fn drag_payload() -> i64 { drag_load }

// The block's content drawn with what is carried: under the pointer where
// it took its source (or by the focused widget, carried by navigation), over
// everything, never in the pointer's way. As big as its source unless `d`
// says.
fn drag_ghost<F>(d: Desc) {
    guard drag_on;
    var at = input.pointer.pos - drag_grab;
    if drag_by_nav {
        let r = state_of(focused).screen;
        at = float2 { r.x + 10.0, r.y - 10.0 };
    }
    var gd = d;
    if gd.dim.w.kind == SIZE_FIT { gd = gd.width(drag_size.x); }
    if gd.dim.h.kind == SIZE_FIT { gd = gd.height(drag_size.y); }
    open_root(ROOT_TOOLTIP, GHOST_ID, Anchor { kind: ANCHOR_POINT, at: at, .. }, column());
    roots[roots.len - 1].level = -1;
    box(gd) { F(); };
    close_root();
}
