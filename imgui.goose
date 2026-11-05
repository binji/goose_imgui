// imgui: an immediate-mode GUI for games, drawn through gfx2d.
//
//   import gfx;
//   import gfx2d from "../goose_gfx2d";      // the program declares gfx2d
//   import imgui from "../goose_imgui";
//
//   while gfx::frame() {
//       gfx2d::frame(gfx2d::rgb(0x101418)) {
//           imgui::frame() {
//               imgui::box("menu", imgui::column().gap(10).skin(imgui::PANEL).place(imgui::CENTER, imgui::CENTER)) {
//                   imgui::text("Paused", imgui::TITLE);
//                   if imgui::button("Resume") { paused = false; }
//                   imgui::slider("Volume", volume, 0, 1);
//               };
//           };
//       };
//   }
//
// Each frame records a tree of boxes, text and widgets, lays it out
// (rows, columns, grids, stacks; fit, fixed, growing and percentage
// sizes), applies motion, and draws it. A widget's result is known when it
// is recorded: input is tested against where things were drawn the frame
// before. docs/imgui.md is the reference; docs/design.md the reasoning.

namespace imgui;

import std;
import vec;
import math;
import dictionary;
import json;
import os;
import gfx;
import gfx2d;
import context;
import id;
import desc;
import motion;
import style;
import tree;
import layout;
import input;
import nav;
import popup;
import draw;
import widgets;
import scroll;
import text_input;
import canvas;
import drag;
import exit;
import notice;
import rich;
import textfx;
import events;
import pixel;
import window;
import devwidgets;
import plots;
import table;
import log;
import split;
import dock;
import save;
import small;

// --- frames ---------------------------------------------------------------------------

// Starts a frame with this input, `dt` seconds after the last.
fn begin_frame(inp: Input, dt: f64) {
    if in_frame { misuse("begin_frame: already in a frame"); }
    frame_index++;
    delta = clamp(dt, 0.0, 0.25);
    clock += delta;
    if inp.viewport.x > 0.0 && inp.viewport.y > 0.0 {
        viewport = gfx2d::Rect { 0.0, 0.0, inp.viewport.x, inp.viewport.y };
    }
    sweep_popups();
    begin_menus();
    begin_windows();
    keyboard_used = false;
    id_stack.clear();
    scope_stack.clear();
    begin_input(inp);
    in_frame = true;
    begin_canvases();
    begin_tree();
}
// With gfx's input and frame time.
fn begin_frame() { begin_frame(input_from_gfx(), gfx::delta_time()); }

// Ends the frame: lays it out, and settles what the next frame's input is
// tested against.
fn end_frame() {
    if !in_frame { misuse("end_frame: not in a frame"); return; }
    end_tree();
    in_frame = false;
    layout_all();
    finish_frame();
    play_exits();
    order_roots();      // again: with the copies of windows hiding
    place_span_boxes();
    end_nav();
    place_focus_cursor();
    end_drag();
    publish_ui_events();
    if frame_index % 30 == 0 {
        sweep_states();
        sweep_anims();
    }
    check();
}

// A frame: begun, recorded by the block, ended, and drawn if inside a
// gfx2d frame (a program can call draw() itself, later, instead).
fn frame<F>(inp: Input, dt: f64) {
    begin_frame(inp, dt);
    F();
    end_frame();
    if gfx2d::state.drawing { draw(); }
    if inp.from_gfx { sync_gfx(); }
}
// With gfx's input; and the clipboard and text input given back to gfx.
fn frame<F>() { frame(gfx::delta_time()) { F(); }; }
// The same, `dt` seconds after the last (a fixed step, for recording).
fn frame<F>(dt: f64) {
    begin_frame(input_from_gfx(), dt);
    F();
    end_frame();
    if gfx2d::state.drawing { draw(); }
    sync_gfx();
}

// What the frame asks of gfx: text input while a field has focus, the
// clipboard after a copy.
fn sync_gfx() {
    if keyboard_used != text_wanted {
        text_wanted = keyboard_used;
        gfx::text_input(text_wanted);
    }
    if copied.len > 0 {
        gfx::set_clipboard(copied);
        copied.clear();
    }
}

fn set_viewport(r: gfx2d::Rect) { viewport = r; }

// --- after layout ----------------------------------------------------------------------

// Whether node n keeps state between frames.
fn keeps_state(n: Node&) -> bool {
    n.named || n.d.bits & (HIT | FOCUSABLE | SCROLLS_X | SCROLLS_Y | KEEP) != 0 ||
    !is_instant(n.d.mot.enter.motion) || !is_instant(n.d.mot.glide) || n.d.mot.exit != 0
}

// Motion applied, and the state, hit list and focus list the next frame
// starts from.
fn finish_frame() {
    scroll_focused_into_view();
    hits.clear();
    turned_hits.clear();
    focusables.clear();
    exit_nodes.clear();
    let everywhere = gfx2d::Rect { -1.0e9, -1.0e9, 2.0e9, 2.0e9 };
    for i: i32 in 0..nodes.len as i32 {
        let n .= nodes[i];
        let keeps = keeps_state(n);
        var st = if keeps { state_of(n.id) } else { WidgetState { .. } };
        let appearing = !st.laid || st.seen < frame_index - 1;
        if pixel_art { n.rect = snap_rect(n.rect); }
        n.shown = n.rect;
        n.alpha = n.style.alpha;
        n.zoom = n.style.zoom * n.d.mot.zoom;
        n.shift = n.style.offset + n.d.mot.offset;
        // Entering: from the Desc's enter look to its own.
        let e = n.d.mot.enter;
        if !is_instant(e.motion) {
            if appearing { st.entered = 0.0; } else { st.entered += delta as f32; }
            let k = enter_progress(e.motion, st.entered);
            if k < 1.0 {
                n.alpha *= e.alpha + (1.0 - e.alpha) * k;
                n.shift += e.shift * (1.0 - k);
                n.zoom *= e.zoom + (1.0 - e.zoom) * k;
            }
        }
        // Gliding: from where it was laid out to where it is now.
        if !is_instant(n.d.mot.glide) {
            let to = float4 { n.rect.x, n.rect.y, n.rect.w, n.rect.h };
            let from = if appearing { to } else { float4 { st.shown.x, st.shown.y, st.shown.w, st.shown.h } };
            let v = animate_lanes(hash_combine(n.id, 0x611DE), to, n.d.mot.glide, from, true);
            n.shown = gfx2d::Rect { v.x, v.y, v.z, v.w };
            n.shift += float2 { v.x - n.rect.x, v.y - n.rect.y };
        }
        if pixel_art {
            n.shift = float2 { round(n.shift.x), round(n.shift.y) };
            n.shown = snap_rect(n.shown);
        }
        // To the screen: under the parent's transform, then its own motion.
        let parent_m = if n.parent >= 0 { nodes[n.parent].m } else { gfx2d::IDENTITY };
        n.m = if moved(n) { gfx2d::mul(parent_m, motion_affine(n)) } else { parent_m };
        let pm = if n.parent >= 0 { nodes[n.parent].m } else { gfx2d::IDENTITY };
        n.clip = if n.parent < 0 {
            everywhere
        } else {
            let p .= nodes[n.parent];
            if p.d.vis.clips { gfx2d::intersect(p.clip, gfx2d::transformed_bounds(pm, box_of(p))) } else { p.clip }
        };
        n.owner = if n.d.bits & HIT != 0 { i } else if n.parent >= 0 { nodes[n.parent].owner } else { -1 };
        n.pass = n.d.bits & PASSTHROUGH != 0 || (n.parent >= 0 && nodes[n.parent].pass);
        // Its own focus, or its widget's, for a part that shares it (a slider's thumb).
        n.ring = !focus_cursor_on() &&
                 ((focus_visible && focused == n.id && n.d.bits & FOCUSABLE != 0) || n.d.vis.state.focus > 0.01);
        let screen = gfx2d::transformed_bounds(n.m, box_of(n));
        n.screen = screen;
        if n.d.mot.exit != 0 { exit_nodes.push(i); }
        if keeps {
            st.rect = n.rect;
            st.screen = screen;
            st.shown = n.shown;
            if n.d.bits & ROW_LIST != 0 { keep_row_view(i, st); }
            if n.d.bits & (SCROLLS_X | SCROLLS_Y) != 0 {
                st.content = n.content;
                st.view = float2 { inner_size(n, 0), inner_size(n, 1) };
            }
            if st.born < 0 || appearing { st.born = frame_index; }
            st.seen = frame_index;
            st.laid = true;
            put_state(n.id, st);
        }
    }
    list_bounds();
    list_hits();
}

// Each node's bounds: what its box, shadow and ring cover on the screen,
// and its subtree's; last node first, so children come before parents.
fn list_bounds() {
    var i = nodes.len as i32 - 1;
    while i >= 0 {
        let n .= nodes[i];
        let s .= n.style;
        var reach = max(s.shadow.blur * 3.0 + max(abs(s.shadow.offset.x), abs(s.shadow.offset.y)) + s.shadow.spread,
                        s.ring_offset + s.ring_width) + 2.0;
        if n.kind == NODE_TEXT {
            // A text's outline, shadow and glow reach past its box.
            reach = max(reach, look_reach(look_of(n), s.text_size) + 2.0);
        } else if n.kind == NODE_RICH {
            reach = max(reach, rich_reach(i) + 2.0);
        }
        if (n.kind == NODE_TEXT || n.kind == NODE_RICH) && has_glyphs(n) { reach += glyph_reach(n); }
        var b = gfx2d::inflate(n.screen, reach * n.m.a);
        if n.cmd_count > 0 {
            // What a canvas draws may reach past its box.
            let o = float2 { n.rect.x + n.d.lay.padding.x, n.rect.y + n.d.lay.padding.y };
            let local = gfx2d::Rect { o.x + n.cmd_lo.x, o.y + n.cmd_lo.y, n.cmd_hi.x - n.cmd_lo.x, n.cmd_hi.y - n.cmd_lo.y };
            b = gfx2d::union(b, gfx2d::inflate(gfx2d::transformed_bounds(n.m, local), 2.0));
        }
        var c = n.first;
        while c >= 0 {
            b = gfx2d::union(b, nodes[c].bounds);
            c = nodes[c].next;
        }
        n.bounds = b;
        i--;
    }
}

// Where node i is hit, as widget `id`: its box on the screen; if it is
// drawn turned or skewed, its own box, which the pointer is taken back into.
fn hit_of(i: i32, id: u64, bits: u32, level: i32) -> Hit {
    let n .= nodes[i];
    var h = Hit { id: id, rect: n.screen, clip: n.clip, bits: bits, level: level, .. };
    if n.m.b != 0.0 || n.m.c != 0.0 {
        let inv, ok = gfx2d::invert(n.m);
        if ok {
            h.turned = turned_hits.len as i32;
            turned_hits.push(TurnedHit { inv, box_of(n) });
        }
    }
    h
}

// The hit list and the focus list, in the order things are drawn: root by
// root (the main one, the windows back to front, the rest as recorded),
// each in the order it was recorded. Each hit knows its window.
fn list_hits() {
    order_roots();
    for k in root_order {
        let r = roots[k as i64];
        let level = r.level;
        let win = if r.kind == ROOT_WINDOW { r.popup } else { 0 };
        let first_hit = hits.len;
        for i: i32 in r.node..nodes.len as i32 {
            let n .= nodes[i];
            if n.root != k { continue; }
            // A box that shows blocks, unless it is in a passthrough subtree
            // and not a part of a widget there.
            let solid = n.kind == NODE_BOX && (n.style.bg.a > 0.0 || n.style.slice != 0) &&
                        (!n.pass || (n.owner >= 0 && nodes[n.owner].pass));
            let blocks = n.d.bits & BLOCKS != 0 || solid;
            if n.d.bits & (HIT | SCROLLS_X | SCROLLS_Y) != 0 {
                hits.push(hit_of(i, n.id, n.d.bits, level));
            } else if blocks {
                // A part of a widget (a toggle's track, a slider's thumb, a
                // drawn icon) is hit as the widget it is in.
                if n.owner >= 0 {
                    hits.push(hit_of(i, nodes[n.owner].id, nodes[n.owner].d.bits, level));
                } else {
                    hits.push(hit_of(i, n.id, n.d.bits, level));
                }
            }
            if n.d.bits & FOCUSABLE != 0 {
                focusables.push(Focusable { n.id, n.screen, n.scope, level, n.d.bits, k });
            }
        }
        for h in first_hit..hits.len { hits[h].window = win; }
    }
    order_focusables();
}

// How far an enter transition is, `t` seconds after its node appeared.
fn enter_progress(m: Motion, t: f32) -> f32 {
    let run = t - m.wait;
    if run <= 0.0 { return 0.0; }
    if m.kind == MOTION_SPRING {
        // A critically damped spring's step response.
        let w = sqrt(max(m.stiffness, 1.0));
        let x = 1.0 - (1.0 + w * run) * exp(-w * run);
        return if x > 0.999 { 1.0 } else { x };
    }
    if m.duration <= 0.0 { return 1.0; }
    ease(m.easing, run / m.duration) as f32
}

// The node focused by navigation, scrolled into view in each scroll pane
// it is in.
fn scroll_focused_into_view() {
    guard scroll_into != 0;
    let found = node_of.get(scroll_into);
    guard found;
    let target = found;
    var c = nodes[target].parent;
    while c >= 0 {
        let p .= nodes[c];
        if p.d.bits & (SCROLLS_X | SCROLLS_Y) != 0 {
            let t .= nodes[target];
            let at = float2 { p.rect.x + p.d.lay.padding.x - p.scroll.x, p.rect.y + p.d.lay.padding.y - p.scroll.y };
            let view = float2 { inner_size(p, 0), inner_size(p, 1) };
            var st = state_of(p.id);
            let margin: f32 = 8.0;
            for a in 2 {
                guard scrolls(p, a);
                let lo = rpos(t.rect, a) - ax(at, a);
                let hi = lo + rsize(t.rect, a);
                var s = ax(st.scroll_to, a);
                if lo - margin < s { s = lo - margin; }
                if hi + margin > s + ax(view, a) { s = hi + margin - ax(view, a); }
                set_ax(st.scroll_to, a, max(s, 0.0));
            }
            put_state(p.id, st);
        }
        c = p.parent;
    }
}

// --- debugging ------------------------------------------------------------------------

// The frame's tree, one node a line: its kind, rect and text, for tests.
fn dump() {
    for n, i in nodes {
        if i == cursor_node || n.ghost != 0 { continue; }
        var line: u8[>..] = [];
        var d = 0;
        var p = n.parent;
        while p >= 0 { d++; p = nodes[p].parent; }
        for k in d { line.append("  "); }
        line.append(match n.kind { NODE_TEXT => "text", NODE_RICH => "rich", NODE_IMAGE => "image", _ => if n.parent < 0 { "root" } else { "box" } });
        format(line, " ", round(n.rect.x), " ", round(n.rect.y), " ", round(n.rect.w), " ", round(n.rect.h));
        if n.kind == NODE_TEXT { format(line, " \"", node_text(i as i32), "\""); }
        print(line);
    }
}

// Where the node with ID `i` was laid out, last frame (or this one, after
// end_frame).
fn rect_of(i: Id) -> gfx2d::Rect { state_of(i.v).rect }
