// Drawing of the program's own, inside the layout: charts, minimaps,
// meters, a portrait's frame. A canvas is a box whose block draws, in the
// box's inner pixels (0, 0 its top left), with the calls below. They are
// recorded as commands, since a block can't be kept until the frame is
// drawn, and replayed then: under the box's clip, motion and opacity, over
// its background and under its children.
//
//   imgui::canvas("health", imgui::column().size(120, 120)) { size =>
//       let c = size * 0.5;
//       imgui::stroke_arc(c.x, c.y, 50, -PI / 2, -PI / 2 + TAU * hp, 10, gfx2d::RED);
//       imgui::draw_text(c.x, c.y, str(round(hp * 100), "%"), 20, gfx2d::WHITE, gfx2d::ALIGN_CENTER,
//                        gfx2d::BASELINE_MIDDLE);
//   };
//
// The block is given the box's inner size, as it was laid out last frame
// (or its px size the first frame), so a chart can fill whatever room the
// layout gives it. A hit() canvas's Interaction (canvas returns it) tells
// where the pointer is on it, in the same pixels: `it.pointer`.

namespace imgui;

import std;
import vec;
import math;
import gfx;
import gfx2d;

enum DrawOp {
    Rect { r: gfx2d::Rect, radius: float4, c: gfx2d::Color },
    RectStroke { r: gfx2d::Rect, radius: float4, width: f32, c: gfx2d::Color },
    Gradient { r: gfx2d::Rect, radius: float4, c0: gfx2d::Color, c1: gfx2d::Color, vertical: bool },
    Circle { at: float2, radius: f32, c: gfx2d::Color },
    CircleStroke { at: float2, radius: f32, width: f32, c: gfx2d::Color },
    Line { a: float2, b: float2, width: f32, c: gfx2d::Color },
    Arc { at: float2, radius: f32, a0: f32, a1: f32, width: f32, c: gfx2d::Color },
    Pie { at: float2, radius: f32, a0: f32, a1: f32, c: gfx2d::Color },
    Poly { first: i32, count: i32, width: f32, c: gfx2d::Color },     // width 0: filled
    Text { at: float2, off: i32, len: i32, size: f32, align: u8, baseline: u8, c: gfx2d::Color },
    Image { t: gfx::Texture, dst: gfx2d::Rect, src: gfx2d::Rect, c: gfx2d::Color },
    // The commands up to `end` (DrawCmd's) drawn transformed by m, or
    // clipped to a circle.
    Push { m: gfx2d::Affine, clip: bool, at: float2, radius: f32 },
}

// A command, the canvas (node index) it draws in, and for a Push, where the
// commands inside it end.
struct DrawCmd { owner: i32, op: DrawOp, end: i32 = 0 }

var draw_cmds: DrawCmd[>..] = [];
var draw_points: float2[>..] = [];
var canvas_stack: i32[>..<] = [];
// The transform the drawing calls are under, in the canvas's pixels: for the
// box their drawing reaches.
var canvas_m: gfx2d::Affine[>..<] = [];

fn begin_canvases() {
    draw_cmds.clear();
    draw_points.clear();
    canvas_stack.clear();
    canvas_m.clear();
}

// The canvas the drawing calls go to, and the box its drawing reaches.
fn current_canvas() -> i32 {
    if canvas_stack.len == 0 { misuse("drawing outside a canvas"); return -1; }
    canvas_stack[canvas_stack.len - 1]
}
fn record(op: DrawOp, lo: float2, hi: float2) {
    let i = current_canvas();
    guard i >= 0;
    draw_cmds.push(DrawCmd { i, op, 0 });
    // Under a transform, what it reaches is the box around the corners moved.
    let m = canvas_m[canvas_m.len - 1];
    var a = lo;
    var b = hi;
    if m != gfx2d::IDENTITY {
        let r = gfx2d::transformed_bounds(m, gfx2d::Rect { lo.x, lo.y, hi.x - lo.x, hi.y - lo.y });
        a = float2 { r.x, r.y };
        b = float2 { r.x + r.w, r.y + r.h };
    }
    let n .= nodes[i];
    if n.cmd_count == 0 {
        n.cmd_first = (draw_cmds.len - 1) as i32;
        n.cmd_lo = a;
        n.cmd_hi = b;
    } else {
        n.cmd_lo = float2 { min(n.cmd_lo.x, a.x), min(n.cmd_lo.y, a.y) };
        n.cmd_hi = float2 { max(n.cmd_hi.x, b.x), max(n.cmd_hi.y, b.y) };
    }
    n.cmd_count += 1;
    n.cmd_end = draw_cmds.len as i32;
}

// A block of drawing calls under a Push: transformed by m, or clipped.
fn push_block<F>(m: gfx2d::Affine, clip: bool, at: float2, radius: f32) {
    let i = current_canvas();
    if i < 0 { F(); return; }
    let k = draw_cmds.len;
    draw_cmds.push(DrawCmd { i, DrawOp.Push { m, clip, at, radius }, 0 });
    let n .= nodes[i];
    if n.cmd_count == 0 { n.cmd_first = k as i32; n.cmd_lo = float2_0; n.cmd_hi = float2_0; }
    n.cmd_count += 1;
    canvas_m.push(gfx2d::mul(canvas_m[canvas_m.len - 1], m));
    F();
    canvas_m.pop();
    draw_cmds[k].end = draw_cmds.len as i32;
    nodes[i].cmd_end = draw_cmds.len as i32;
}

// --- canvases -------------------------------------------------------------------------

fn canvas_size(i: Id, d: Desc) -> float2 {
    let st = state_of(i.v);
    if st.laid {
        return float2 { max(st.rect.w - d.lay.padding.x - d.lay.padding.z, 0.0),
                        max(st.rect.h - d.lay.padding.y - d.lay.padding.w, 0.0) };
    }
    // The first frame: its px size, less its padding, if it has one.
    float2 { if d.dim.w.kind == SIZE_PX { max(d.dim.w.value - d.lay.padding.x - d.lay.padding.z, 0.0) } else { 0.0 },
             if d.dim.h.kind == SIZE_PX { max(d.dim.h.value - d.lay.padding.y - d.lay.padding.w, 0.0) } else { 0.0 } }
}

// A canvas: a box (with its Desc's look and size, and children if the block
// records any) whose block draws, given its inner size.
fn canvas<F>(label: const u8[:], d: Desc) -> Interaction { canvas(id(label), d) { s => F(s); } }
fn canvas<F>(i: Id, d: Desc) -> Interaction {
    let dk = d.keep();
    let size = canvas_size(i, dk);
    let at = nodes.len as i32;
    let it = box(i, dk) {
        canvas_stack.push(at);
        canvas_m.push(gfx2d::IDENTITY);
        F(size);
        canvas_m.pop();
        canvas_stack.pop();
    };
    it
}

// --- drawing, in a canvas's inner pixels -----------------------------------------------------

fn f2(x: f64, y: f64) -> float2 { float2 { x as f32, y as f32 } }
fn rect4(x: f64, y: f64, w: f64, h: f64) -> gfx2d::Rect { gfx2d::rect_of(x, y, w, h) }
fn same4(r: f64) -> float4 { let v = r as f32; float4 { v, v, v, v } }

fn fill_rect(x: f64, y: f64, w: f64, h: f64, c: gfx2d::Color) { fill_rect(x, y, w, h, 0.0, c); }
fn fill_rect(x: f64, y: f64, w: f64, h: f64, radius: f64, c: gfx2d::Color) {
    record(DrawOp.Rect { rect4(x, y, w, h), same4(radius), c }, f2(x, y), f2(x + w, y + h));
}
fn stroke_rect(x: f64, y: f64, w: f64, h: f64, width: f64, c: gfx2d::Color, radius: f64 = 0.0) {
    let k = width * 0.5;
    record(DrawOp.RectStroke { rect4(x, y, w, h), same4(radius), width as f32, c }, f2(x - k, y - k),
           f2(x + w + k, y + h + k));
}
// Top to bottom, or left to right.
fn gradient_rect(x: f64, y: f64, w: f64, h: f64, c0: gfx2d::Color, c1: gfx2d::Color, vertical: bool = true,
                 radius: f64 = 0.0) {
    record(DrawOp.Gradient { rect4(x, y, w, h), same4(radius), c0, c1, vertical }, f2(x, y), f2(x + w, y + h));
}
fn fill_circle(cx: f64, cy: f64, r: f64, c: gfx2d::Color) {
    record(DrawOp.Circle { f2(cx, cy), r as f32, c }, f2(cx - r, cy - r), f2(cx + r, cy + r));
}
fn stroke_circle(cx: f64, cy: f64, r: f64, width: f64, c: gfx2d::Color) {
    let k = r + width * 0.5;
    record(DrawOp.CircleStroke { f2(cx, cy), r as f32, width as f32, c }, f2(cx - k, cy - k), f2(cx + k, cy + k));
}
fn draw_line(x0: f64, y0: f64, x1: f64, y1: f64, width: f64, c: gfx2d::Color) {
    let k = width * 0.5;
    record(DrawOp.Line { f2(x0, y0), f2(x1, y1), width as f32, c }, f2(min(x0, x1) - k, min(y0, y1) - k),
           f2(max(x0, x1) + k, max(y0, y1) + k));
}
// From angle a0 to a1 (radians, clockwise from +x), as a stroke or a wedge.
fn stroke_arc(cx: f64, cy: f64, r: f64, a0: f64, a1: f64, width: f64, c: gfx2d::Color) {
    let k = r + width * 0.5;
    record(DrawOp.Arc { f2(cx, cy), r as f32, a0 as f32, a1 as f32, width as f32, c }, f2(cx - k, cy - k),
           f2(cx + k, cy + k));
}
fn fill_pie(cx: f64, cy: f64, r: f64, a0: f64, a1: f64, c: gfx2d::Color) {
    record(DrawOp.Pie { f2(cx, cy), r as f32, a0 as f32, a1 as f32, c }, f2(cx - r, cy - r), f2(cx + r, cy + r));
}
fn points_op(points: const float2[:], width: f64, c: gfx2d::Color) {
    guard points.len > 0;
    let first = draw_points.len;
    var lo = points[0];
    var hi = points[0];
    for p in points {
        draw_points.push(p);
        lo = float2 { min(lo.x, p.x), min(lo.y, p.y) };
        hi = float2 { max(hi.x, p.x), max(hi.y, p.y) };
    }
    let k = (width * 0.5) as f32;
    record(DrawOp.Poly { first as i32, points.len as i32, width as f32, c }, lo - float2 { k, k }, hi + float2 { k, k });
}
// A line through the points: a chart's.
fn stroke_polyline(points: const float2[:], width: f64, c: gfx2d::Color) { points_op(points, max(width, 0.0001), c); }
// The shape the points outline, filled: an area under a chart.
fn fill_polygon(points: const float2[:], c: gfx2d::Color) { points_op(points, 0.0, c); }
// Text at (x, y): `align` gfx2d::ALIGN_LEFT, CENTER or RIGHT about x;
// `baseline` BASELINE_TOP, MIDDLE, ALPHABETIC or BOTTOM at y. In the
// canvas's inherited font.
fn draw_text(x: f64, y: f64, s: const u8[:], size: f64, c: gfx2d::Color, align: i64 = gfx2d::ALIGN_LEFT,
             baseline: i64 = gfx2d::BASELINE_TOP) {
    let off = text_arena.len;
    text_arena.append(s);
    let m = measure(s, size);
    let x0 = x - (if align == gfx2d::ALIGN_CENTER { m.x * 0.5 } else if align == gfx2d::ALIGN_RIGHT { m.x } else { 0.0 });
    let y0 = y - (if baseline == gfx2d::BASELINE_TOP { 0.0 } else if baseline == gfx2d::BASELINE_BOTTOM { m.y } else { m.y * 0.5 });
    record(DrawOp.Text { f2(x, y), off as i32, s.len as i32, size as f32, align as u8, baseline as u8, c },
           f2(x0, y0), f2(x0 + m.x, y0 + m.y));
}
// How big draw_text draws s, in the canvas's font.
fn measure(s: const u8[:], size: f64) -> float2 {
    let up = inherited[inherited.len - 1];
    gfx2d::measure_text(s, gfx2d::TextStyle { font: up.font, size: size, .. })
}
fn draw_image(t: gfx::Texture, x: f64, y: f64, w: f64, h: f64, tint: gfx2d::Color = gfx2d::WHITE) {
    let info = gfx::texture_info(t);
    draw_image(t, gfx2d::rect_of(0, 0, info.width, info.height), x, y, w, h, tint);
}
fn draw_image(t: gfx::Texture, src: gfx2d::Rect, x: f64, y: f64, w: f64, h: f64, tint: gfx2d::Color = gfx2d::WHITE) {
    record(DrawOp.Image { t, rect4(x, y, w, h), src, tint }, f2(x, y), f2(x + w, y + h));
}

// The drawing calls in the block, transformed: turned about the canvas's
// (0, 0), or about (cx, cy); moved; scaled about (0, 0); or by any matrix.
// For a needle, a minimap that turns with the player, a clock's hand.
//   imgui::rotate(angle, c.x, c.y) { imgui::fill_polygon(needle, red); };
fn transform<F>(m: gfx2d::Affine) { push_block(m, false, float2_0, 0.0) { F(); }; }
fn rotate<F>(radians: f64) { transform(gfx2d::rotation(radians)) { F(); }; }
fn rotate<F>(radians: f64, cx: f64, cy: f64) { transform(gfx2d::rotation_about(radians, cx, cy)) { F(); }; }
fn translate<F>(x: f64, y: f64) { transform(gfx2d::translation(x, y)) { F(); }; }
fn scale<F>(s: f64) { transform(gfx2d::scaling(s)) { F(); }; }
// The drawing calls in the block, clipped to a circle: a round minimap, an
// orb filled to a level.
fn clip_circle<F>(cx: f64, cy: f64, r: f64) { push_block(gfx2d::IDENTITY, true, f2(cx, cy), r as f32) { F(); }; }

// --- replaying ----------------------------------------------------------------------------

fn shifted(r: gfx2d::Rect, o: float2) -> gfx2d::Rect { gfx2d::Rect { r.x + o.x, r.y + o.y, r.w, r.h } }

// Node i's commands, drawn from its inner box's top left, faded by `a`.
fn replay(i: i32, a: f32) {
    let n .= nodes[i];
    guard n.cmd_count > 0;
    let o = float2 { n.rect.x + n.d.lay.padding.x, n.rect.y + n.d.lay.padding.y };
    replay_range(i, a, o, n.style.font, n.cmd_first, n.cmd_end);
}

// Node i's commands from `from` up to `to`; a Push's, inside its transform
// or clip.
recursive fn replay_range(i: i32, a: f32, o: float2, font: gfx2d::Font, from: i32, to: i32) {
    var k = from;
    while k < to {
        let cmd = draw_cmds[k];
        k++;
        if cmd.owner != i { continue; }
        match cmd.op {
            Push v => {
                if v.clip {
                    gfx2d::clip_circle(v.at.x + o.x, v.at.y + o.y, v.radius) { replay_range(i, a, o, font, k, cmd.end); };
                } else {
                    // m is in the canvas's pixels: moved to the box and back.
                    let m = gfx2d::mul(gfx2d::translation(o.x, o.y), gfx2d::mul(v.m, gfx2d::translation(-o.x, -o.y)));
                    gfx2d::transform(m) { replay_range(i, a, o, font, k, cmd.end); };
                }
                k = cmd.end;
            },
            Rect v => {
                let r = shifted(v.r, o);
                if v.radius == float4_0 { gfx2d::rect(r, faded(v.c, a)); }
                else { gfx2d::rounded_rect(r.x, r.y, r.w, r.h, v.radius, faded(v.c, a)); }
            },
            RectStroke v => {
                let r = shifted(v.r, o);
                if v.radius == float4_0 { gfx2d::rect_outline(r, v.width, faded(v.c, a)); }
                else { gfx2d::rounded_rect_outline(r.x, r.y, r.w, r.h, v.radius, v.width, faded(v.c, a)); }
            },
            Gradient v => {
                let r = shifted(v.r, o);
                let p = if v.vertical {
                    gfx2d::linear(r.x, r.y, r.x, r.y + r.h, faded(v.c0, a), faded(v.c1, a))
                } else {
                    gfx2d::linear(r.x, r.y, r.x + r.w, r.y, faded(v.c0, a), faded(v.c1, a))
                };
                gfx2d::rounded_rect(r.x, r.y, r.w, r.h, v.radius, p);
            },
            Circle v => { gfx2d::circle(v.at + o, v.radius, faded(v.c, a)); },
            CircleStroke v => { gfx2d::circle_outline(v.at.x + o.x, v.at.y + o.y, v.radius, v.width, faded(v.c, a)); },
            Line v => { gfx2d::line(v.a + o, v.b + o, v.width, faded(v.c, a), gfx2d::CAP_ROUND); },
            Arc v => {
                gfx2d::arc(v.at.x + o.x, v.at.y + o.y, v.radius, v.a0, v.a1, v.width, faded(v.c, a), gfx2d::CAP_ROUND);
            },
            Pie v => { gfx2d::pie(v.at.x + o.x, v.at.y + o.y, v.radius, v.a0, v.a1, faded(v.c, a)); },
            Poly v => { replay_poly(v.first, v.count, v.width, faded(v.c, a), o); },
            Text v => {
                let style = gfx2d::TextStyle { font: font, size: v.size, align: v.align, baseline: v.baseline, .. };
                gfx2d::text(v.at.x + o.x, v.at.y + o.y, text_arena[v.off..v.off + v.len], style, faded(v.c, a));
            },
            Image v => { gfx2d::image(v.t, shifted(v.dst, o), v.src, faded(v.c, a)); },
        }
    }
}

var poly_scratch: float2[>..<] = [];

fn replay_poly(first: i32, count: i32, width: f32, c: gfx2d::Color, o: float2) {
    poly_scratch.resize(0);
    for k in first..first + count { poly_scratch.push(draw_points[k] + o); }
    if width > 0.0 {
        gfx2d::polyline(poly_scratch, width, c, gfx2d::CAP_ROUND, gfx2d::JOIN_ROUND);
    } else {
        gfx2d::polygon(poly_scratch, c);
    }
}
