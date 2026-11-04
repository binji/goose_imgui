// Exit transitions: what has left, played out without the program's help.
// A node with an exit is copied, with its subtree, each frame it is drawn.
// The first frame its ID is not recorded, the copy is drawn where it was,
// moving to its exit's look, until the exit is over.
//
//   for t in toasts {
//       imgui::box(t.id, imgui::row().skin(TOAST).enter(imgui::slide_in(0, 20, m))
//                                    .exit(imgui::fade_out(imgui::tween(0.3)))) { … };
//   }
//
// The copy is drawn among its parent's children, after the sibling it came
// after, if its parent is still there; if not, where it was on the screen,
// over the main root. It takes no input. A copy of a subtree is as it was
// last drawn: its text, images and drawing, still.

namespace imgui;

import std;
import vec;
import math;
import gfx2d;

let GHOST_IN = 1;           // a node in a copy
let GHOST_TOP = 2;          // its top, among its parent's children
let GHOST_ALONE = 3;        // its top, its parent gone: drawn with its own transform

// A copy of a subtree, and what it was in. Its nodes, text, looks,
// commands and points are in the leaver_ arrays, their indices from the
// copy's own start.
struct Leaver {
    id: u64 = 0,
    outer: u64 = 0,             // the nearest node above it with an exit (0: none), which copies it too
    parent: u64 = 0,            // its parent's ID
    after: u64 = 0,             // its sibling before it (0: it was the first)
    parent_m: gfx2d::Affine = gfx2d::Affine { 1.0, 0.0, 0.0, 1.0, 0.0, 0.0 },  // its parent's to the screen
    exit: Exit = Exit { .. },
    leaving: bool = false,
    since: f64 = 0.0,           // when it left
    alpha: f32 = 1.0,           // its own motion as it left, what the exit plays from
    shift: float2 = float2 { 0.0, 0.0 },
    zoom: f32 = 1.0,
    node: i32 = 0,
    node_count: i32 = 0,
    text: i32 = 0,
    text_len: i32 = 0,
    look: i32 = 0,
    cmd: i32 = 0,
    cmd_count: i32 = 0,
    point: i32 = 0,
    point_count: i32 = 0,
    piece: i32 = 0,
    piece_count: i32 = 0,
    glyph: i32 = 0,
    glyph_count: i32 = 0,
}

var leavers: Leaver[>..] = [];
var leaver_nodes: Node[>..] = [];
var leaver_text: u8[>..] = [];
var leaver_looks: TextLook[>..] = [];
var leaver_cmds: DrawCmd[>..] = [];
var leaver_points: float2[>..] = [];
var leaver_pieces: Piece[>..] = [];
var leaver_glyphs: Glyph[>..] = [];
var exit_nodes: i32[>..<] = [];     // this frame's nodes with exits (finish_frame)
var kept: Leaver[>..<] = [];        // copies drawn this frame, `node` their top in `nodes`

// How far an exit is, `t` seconds after it began, and whether it is over.
fn exit_progress(m: Motion, t: f64) -> f32, bool {
    let run = t - m.wait;
    if run <= 0.0 { return 0.0, false; }
    if m.kind == MOTION_SPRING {
        let w = sqrt(max(m.stiffness, 1.0) as f64);
        let x = 1.0 - (1.0 + w * run) * exp(-w * run);
        return x as f32, x > 0.999;
    }
    if m.duration <= 0.0 { return 1.0, true; }
    // Over a hair early: a clock summed from frame times may fall just short.
    return ease(m.easing, run / m.duration) as f32, run >= m.duration - 1.0e-6;
}

fn seen_now(id: u64) -> bool { state_of(id).seen == frame_index }

// How many copies of what has left are drawn this frame.
fn exits_playing() -> i64 { kept.len }

// After the frame is laid out: last frame's copies of what is gone now,
// drawn; then this frame's copies taken, for the next.
fn play_exits() {
    kept.clear();
    guard leavers.len > 0 || exit_nodes.len > 0;
    let live = nodes.len as i32;
    for k in 0..leavers.len {
        var r = leavers[k];
        if seen_now(r.id) { continue; }     // drawn itself (back again, if it was leaving)
        if !r.leaving {
            // Inside another copy that is leaving too: drawn in that one.
            if r.outer != 0 && !seen_now(r.outer) { continue; }
            let top = leaver_nodes[r.node as i64];
            r.leaving = true;
            r.since = clock;
            r.alpha = top.alpha;
            r.shift = top.shift;
            r.zoom = top.zoom;
        }
        let p, over = exit_progress(r.exit.motion, clock - r.since);
        if over { continue; }
        r.node = place_copy(r, p, live);
        kept.push(r);
    }
    // This frame's copies: of each node with an exit, and of what is leaving.
    leavers.clear();
    leaver_nodes.clear();
    leaver_text.clear();
    leaver_looks.clear();
    leaver_cmds.clear();
    leaver_points.clear();
    leaver_pieces.clear();
    leaver_glyphs.clear();
    for i in exit_nodes {
        let n .= nodes[i];
        var r = Leaver { id: n.id, exit: desc_exit(n.d.mot), .. };
        let p = n.parent;
        if p >= 0 {
            r.parent = nodes[p].id;
            r.parent_m = nodes[p].m;
            // The sibling before it: the node before it, or the one above
            // that under the same parent.
            var j = i - 1;
            while j != p && nodes[j].parent != p { j = nodes[j].parent; }
            if j != p { r.after = nodes[j].id; }
            var q = p;
            while q >= 0 && nodes[q].d.mot.exit == 0 { q = nodes[q].parent; }
            if q >= 0 { r.outer = nodes[q].id; }
        }
        copy_out(r, i, live);
    }
    for r in kept { copy_out(r, r.node, nodes.len as i32); }
}

// Nodes from `i` to the end of its subtree (before `limit`), copied into
// the leaver_ arrays as a copy described by r.
fn copy_out(var r: Leaver, i: i32, limit: i32) {
    var end = i + 1;
    while end < limit && nodes[end].parent >= i { end++; }
    r.node = leaver_nodes.len as i32;
    r.text = leaver_text.len as i32;
    r.look = leaver_looks.len as i32;
    r.cmd = leaver_cmds.len as i32;
    r.point = leaver_points.len as i32;
    r.piece = leaver_pieces.len as i32;
    r.glyph = leaver_glyphs.len as i32;
    for k in i..end {
        var n = nodes[k];
        // Linked again below, without what is not in the copy.
        n.parent = if k == i { -1 } else { n.parent - i };
        n.first = -1;
        n.last = -1;
        n.next = -1;
        if n.kind == NODE_TEXT {
            n.text_off = leaver_text.len as i32 - r.text;
            leaver_text.append(text_arena[nodes[k].text_off..nodes[k].text_off + nodes[k].text_len]);
        } else if n.kind == NODE_RICH {
            // Its pieces, each word's and space's text with it.
            n.text_off = leaver_pieces.len as i32 - r.piece;
            for q in nodes[k].text_off..nodes[k].text_off + nodes[k].text_len {
                var pc = pieces[q];
                if pc.kind != PIECE_IMAGE {
                    pc.off = leaver_text.len as i32 - r.text;
                    leaver_text.append(text_arena[pieces[q].off..pieces[q].off + pieces[q].len]);
                }
                leaver_pieces.push(pc);
            }
        }
        leaver_looks.push(node_looks[n.look as i64]);
        n.look = k - i;
        if (n.kind == NODE_TEXT || n.kind == NODE_RICH) && has_glyphs(n) {
            // Its characters' effects, as they were.
            let g0 = leaver_glyphs.len as i32 - r.glyph;
            for q in n.cmd_first..n.cmd_end { leaver_glyphs.push(glyphs[q]); }
            n.cmd_end = g0 + (n.cmd_end - n.cmd_first);
            n.cmd_first = g0;
        }
        if n.cmd_count > 0 {
            let c0 = leaver_cmds.len as i32 - r.cmd;
            for c in n.cmd_first..n.cmd_end {
                let cmd = draw_cmds[c];
                var op = cmd.op;
                match cmd.op {
                    Text v => {
                        op = DrawOp.Text { v.at, leaver_text.len as i32 - r.text, v.len, v.size, v.align, v.baseline, v.c };
                        leaver_text.append(text_arena[v.off..v.off + v.len]);
                    },
                    Poly v => {
                        op = DrawOp.Poly { leaver_points.len as i32 - r.point, v.count, v.width, v.c };
                        for q in v.first..v.first + v.count { leaver_points.push(draw_points[q]); }
                    },
                    _ => {},
                }
                let owner = if cmd.owner >= i && cmd.owner < end { cmd.owner - i } else { -1 };
                let ce = if cmd.end > 0 { cmd.end - n.cmd_first + c0 } else { 0 };
                leaver_cmds.push(DrawCmd { owner, op, ce });
            }
            n.cmd_end = c0 + (n.cmd_end - n.cmd_first);
            n.cmd_first = c0;
        }
        n.ghost = GHOST_IN;
        leaver_nodes.push(n);
        if k > i {
            let at = leaver_nodes.len as i32 - 1;
            let pp = r.node + n.parent;
            let last = leaver_nodes[pp as i64].last;
            if last >= 0 { leaver_nodes[(r.node + last) as i64].next = at - r.node; }
            else { leaver_nodes[pp as i64].first = at - r.node; }
            leaver_nodes[pp as i64].last = at - r.node;
        }
    }
    r.node_count = end - i;
    r.text_len = leaver_text.len as i32 - r.text;
    r.cmd_count = leaver_cmds.len as i32 - r.cmd;
    r.point_count = leaver_points.len as i32 - r.point;
    r.piece_count = leaver_pieces.len as i32 - r.piece;
    r.glyph_count = leaver_glyphs.len as i32 - r.glyph;
    leavers.push(r);
}

fn moved_link(l: i32, base: i32) -> i32 { if l >= 0 { l + base } else { -1 } }

// Copy r drawn this frame, `p` of the way through its exit: its nodes
// added to the frame's, its top linked where it was. Its top's index.
fn place_copy(r: Leaver, p: f32, live: i32) -> i32 {
    let base = nodes.len as i32;
    let tb = text_arena.len as i32 - r.text;
    let lb = node_looks.len as i32;
    let cb = draw_cmds.len as i32 - r.cmd;
    let pb = draw_points.len as i32 - r.point;
    let everywhere = gfx2d::Rect { -1.0e9, -1.0e9, 2.0e9, 2.0e9 };
    text_arena.append(leaver_text[r.text..r.text + r.text_len]);
    let qb = pieces.len as i32 - r.piece;
    // Its characters' effects: the built-in ones played on, at this frame's
    // time; a program's own, whose code isn't run again, as they were.
    let gb = glyphs.len as i32 - r.glyph;
    for q in r.glyph..r.glyph + r.glyph_count {
        var g = leaver_glyphs[q];
        if is_standard_fx(g.text_fx) || is_standard_fx(g.span_fx) {
            g = Glyph { index: g.index, count: g.count, cp: g.cp, seed: g.seed, time: clock, age: g.age,
                        text_fx: g.text_fx, text_args: g.text_args, span_fx: g.span_fx, span_args: g.span_args,
                        base: g.base, ink: g.base, .. };
            standard_fx(g);
        }
        glyphs.push(g);
    }
    for q in r.piece..r.piece + r.piece_count {
        var pc = leaver_pieces[q];
        if pc.kind != PIECE_IMAGE { pc.off += r.text + tb; }
        pieces.push(pc);
    }
    for q in r.point..r.point + r.point_count { draw_points.push(leaver_points[q]); }
    for c in r.cmd..r.cmd + r.cmd_count {
        let cmd = leaver_cmds[c];
        var op = cmd.op;
        match cmd.op {
            Text v => { op = DrawOp.Text { v.at, v.off + r.text + tb, v.len, v.size, v.align, v.baseline, v.c }; },
            Poly v => { op = DrawOp.Poly { v.first + r.point + pb, v.count, v.width, v.c }; },
            _ => {},
        }
        draw_cmds.push(DrawCmd { moved_link(cmd.owner, base), op, if cmd.end > 0 { cmd.end + r.cmd + cb } else { 0 } });
    }
    for k in 0..r.node_count {
        var n = leaver_nodes[(r.node + k) as i64];
        n.parent = moved_link(n.parent, base);
        n.first = moved_link(n.first, base);
        n.last = moved_link(n.last, base);
        n.next = moved_link(n.next, base);
        if n.kind == NODE_TEXT { n.text_off += r.text + tb; }
        if n.kind == NODE_RICH { n.text_off += r.piece + qb; }
        if (n.kind == NODE_TEXT || n.kind == NODE_RICH) && has_glyphs(n) {
            n.cmd_first += r.glyph + gb;
            n.cmd_end += r.glyph + gb;
        }
        node_looks.push(leaver_looks[(r.look + n.look) as i64]);
        n.look = lb + k;
        if n.cmd_count > 0 { n.cmd_first += r.cmd + cb; n.cmd_end += r.cmd + cb; }
        n.ring = false;
        n.bounds = everywhere;
        n.clip = everywhere;
        nodes.push(n);
    }
    // The top, moved toward its exit's look.
    let e = r.exit;
    let t .= nodes[base];
    t.alpha = r.alpha * (1.0 + (e.alpha - 1.0) * p);
    t.shift = r.shift + e.shift * p;
    t.zoom = r.zoom * (1.0 + (e.zoom - 1.0) * p);
    // Under its parent, after its sibling, if they are still there.
    var parent: i32 = -1;
    for j: i32 in 0..live { if nodes[j].id == r.parent && nodes[j].ghost == 0 { parent = j; break; } }
    if parent < 0 {
        nodes[base].ghost = GHOST_ALONE;
        nodes[base].parent = 0;
        nodes[base].m = gfx2d::mul(r.parent_m, motion_affine(nodes[base]));
        link_after(0, base, nodes[0].last);
        return base;
    }
    nodes[base].ghost = GHOST_TOP;
    nodes[base].parent = parent;
    nodes[base].m = gfx2d::mul(nodes[parent].m, motion_affine(nodes[base]));
    var before: i32 = -1;
    if r.after != 0 {
        var c = nodes[parent].first;
        while c >= 0 && nodes[c].id != r.after { c = nodes[c].next; }
        before = if c >= 0 { c } else { nodes[parent].last };
    }
    link_after(parent, base, before);
    base
}

// Node i linked into p's children after `before` (-1: first).
fn link_after(p: i32, i: i32, before: i32) {
    if before < 0 {
        nodes[i].next = nodes[p].first;
        nodes[p].first = i;
        if nodes[p].last < 0 { nodes[p].last = i; }
    } else {
        nodes[i].next = nodes[before].next;
        nodes[before].next = i;
        if nodes[p].last == before { nodes[p].last = i; }
    }
}
