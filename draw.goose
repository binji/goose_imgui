// Drawing the frame through gfx2d: each root's tree, depth first, each
// node's box (shadow, background, nine-slice, border), its text or image,
// its children (clipped to its box if it clips), and its focus ring. A
// node's motion (offset, scale) is a transform around it and its subtree;
// its opacity multiplies into its colors, or, isolated, composites a layer.

namespace imgui;

import std;
import vec;
import math;
import gfx;
import gfx2d;

// The frame, drawn: inside a gfx2d frame, after end_frame.
fn draw() {
    guard gfx2d::state.drawing else {
        misuse("draw: not inside a gfx2d frame");
        return;
    }
    // Pixel art: nothing antialiased, images nearest.
    let aliased = gfx2d::state.aliased;
    if pixel_art { gfx2d::set_antialias(false); }
    let s = drawn_scale();
    if s != 1.0 {
        gfx2d::scale(s) { draw_roots(); };
    } else {
        draw_roots();
    }
    gfx2d::set_antialias(!aliased);
}
// Each root, then the focus cursor over them all.
fn draw_roots() {
    for k in root_order { draw_tree(roots[k as i64].node, 1.0); }
    if cursor_node >= 0 { draw_tree(cursor_node, 1.0); }
}

// Where node n's own box is drawn, in its layout's space: its rect, at the
// size its glide has reached.
fn box_of(n: Node&) -> gfx2d::Rect { gfx2d::Rect { n.rect.x, n.rect.y, n.shown.w, n.shown.h } }

fn moved(n: Node&) -> bool { n.zoom != 1.0 || n.shift != float2_0 || n.d.mot.turn != 0.0 || n.d.mot.slant != 0.0 }

// What node n's motion does to it and its subtree: a shift, and a scale,
// a skew and a turn about its box's center (scaled, then skewed, then
// turned).
fn motion_affine(n: Node&) -> gfx2d::Affine {
    let b = box_of(n);
    let c = float2 { b.x + b.w * 0.5, b.y + b.h * 0.5 };
    let z = n.zoom;
    let turn = n.d.mot.turn;
    let slant = n.d.mot.slant;
    if turn == 0.0 && slant == 0.0 {
        return gfx2d::Affine { z, 0.0, 0.0, z, c.x + n.shift.x - z * c.x, c.y + n.shift.y - z * c.y };
    }
    var m = gfx2d::scaling(z);
    if slant != 0.0 { m = gfx2d::mul(gfx2d::skewing(-slant, 0.0), m); }      // top to the right
    if turn != 0.0 { m = gfx2d::mul(gfx2d::rotation(turn), m); }
    gfx2d::mul(gfx2d::translation(c.x + n.shift.x, c.y + n.shift.y), gfx2d::mul(m, gfx2d::translation(-c.x, -c.y)))
}

fn overlaps(a: gfx2d::Rect, b: gfx2d::Rect) -> bool {
    a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
}

recursive fn draw_tree(i: i32, alpha: f32) {
    let a = alpha * nodes[i].alpha;
    if a <= 0.002 { return; }
    // Scrolled or clipped out of sight: none of it drawn.
    if !overlaps(nodes[i].bounds, nodes[i].clip) { return; }
    if nodes[i].ghost == GHOST_ALONE {
        // What has left, whose parent has too: where it was on the screen.
        gfx2d::transform(nodes[i].m) { draw_body(i, a); };
    } else if moved(nodes[i]) {
        gfx2d::transform(motion_affine(nodes[i])) { draw_body(i, a); };
    } else {
        draw_body(i, a);
    }
}

fn draw_body(i: i32, a: f32) {
    let f = nodes[i].d.vis.filter;
    if f != 0 {
        gfx2d::layer(gfx2d::LayerDesc { opacity: a, color_matrix: node_filters[(f - 1) as i64] }) { draw_inner(i, 1.0); };
    } else if nodes[i].d.vis.isolated {
        gfx2d::layer(a) { draw_inner(i, 1.0); };
    } else {
        draw_inner(i, a);
    }
}

fn draw_inner(i: i32, a: f32) {
    draw_self(i, a);
    if nodes[i].first >= 0 || nodes[i].cmd_count > 0 {
        if nodes[i].d.vis.clips {
            let b = box_of(nodes[i]);
            let r = nodes[i].style.radius;
            if r == float4_0 {
                gfx2d::clip_rect(b.x, b.y, b.w, b.h) { draw_content(i, a); };
            } else {
                gfx2d::clip_rounded_rect(b.x, b.y, b.w, b.h, r) { draw_content(i, a); };
            }
        } else {
            draw_content(i, a);
        }
    }
    draw_ring(i, a);
}

// A canvas's drawing, then the children over it.
fn draw_content(i: i32, a: f32) {
    replay(i, a);
    draw_kids(i, a);
}

fn draw_kids(i: i32, a: f32) {
    var c = nodes[i].first;
    while c >= 0 {
        draw_tree(c, a);
        c = nodes[c].next;
    }
}

fn faded(c: gfx2d::Color, a: f32) -> gfx2d::Color { gfx2d::Color { c.r, c.g, c.b, c.a * a } }
fn any_radius(r: float4) -> bool { r != float4_0 }

// The box of node i: shadow, background, nine-slice, border; then its text
// or image.
fn draw_self(i: i32, alpha: f32) {
    let n .= nodes[i];
    let s .= n.style;
    let a = alpha;
    let b = box_of(n);
    if b.w <= 0.0 || b.h <= 0.0 { return; }
    let r = s.radius;
    if s.shadow.color.a > 0.0 {
        let rr = max(max(r.x, r.y), max(r.z, r.w));
        gfx2d::box_shadow(b.x + s.shadow.offset.x, b.y + s.shadow.offset.y, b.w, b.h, rr, s.shadow.blur,
                          faded(s.shadow.color, a), s.shadow.spread);
    }
    if s.gradient != GRADIENT_NONE && (s.bg.a > 0.0 || s.bg2.a > 0.0) {
        let p = if s.gradient == GRADIENT_HORIZONTAL {
            gfx2d::linear(b.x, b.y, b.x + b.w, b.y, faded(s.bg, a), faded(s.bg2, a))
        } else {
            gfx2d::linear(b.x, b.y, b.x, b.y + b.h, faded(s.bg, a), faded(s.bg2, a))
        };
        if any_radius(r) { gfx2d::rounded_rect(b.x, b.y, b.w, b.h, r, p); } else { gfx2d::rect(b, p); }
    } else if s.bg.a > 0.0 {
        let c = faded(s.bg, a);
        if any_radius(r) { gfx2d::rounded_rect(b.x, b.y, b.w, b.h, r, c); } else { gfx2d::rect(b, c); }
    }
    if s.slice != 0 && s.slice < nine_slices.len {
        let ns = nine_slices[s.slice];
        gfx2d::nine_slice(ns.texture, b, ns.src, ns.insets, faded(s.slice_tint, a), ns.filter);
    }
    if s.border_width > 0.0 && s.border.a > 0.0 {
        let h = s.border_width * 0.5;
        let c = faded(s.border, a);
        if any_radius(r) {
            let ir = float4 { max(r.x - h, 0.0), max(r.y - h, 0.0), max(r.z - h, 0.0), max(r.w - h, 0.0) };
            gfx2d::rounded_rect_outline(b.x + h, b.y + h, b.w - s.border_width, b.h - s.border_width, ir,
                                        s.border_width, c);
        } else {
            gfx2d::rect_outline(b.x + h, b.y + h, b.w - s.border_width, b.h - s.border_width, s.border_width, c);
        }
    }
    if n.kind == NODE_TEXT {
        draw_text(i, a);
    } else if n.kind == NODE_RICH {
        draw_rich(i, a);
    } else if n.kind == NODE_ICON {
        draw_icon(n.icon, b, faded(n.style.ink, a));
    } else if n.kind == NODE_IMAGE && n.image.id != 0 {
        let inner = gfx2d::Rect { b.x + n.d.lay.padding.x, b.y + n.d.lay.padding.y,
                                  b.w - pad_sum(n, 0), b.h - pad_sum(n, 1) };
        let ink = if n.d.vis.ov & OV_INK != 0 { n.style.ink } else { gfx2d::WHITE };
        gfx2d::image(n.image, fitted(n.src, inner, n.fit_mode), n.src, faded(ink, a), n.filter);
    }
}

// The part of `dst` an image of `src`'s size covers, fitted as `mode` says.
fn fitted(src: gfx2d::Rect, dst: gfx2d::Rect, mode: u8) -> gfx2d::Rect {
    if mode == gfx2d::FIT_STRETCH || src.w <= 0.0 || src.h <= 0.0 { return dst; }
    let k = if mode == gfx2d::FIT_COVER { max(dst.w / src.w, dst.h / src.h) } else { min(dst.w / src.w, dst.h / src.h) };
    let w = src.w * k;
    let h = src.h * k;
    gfx2d::Rect { dst.x + (dst.w - w) * 0.5, dst.y + (dst.h - h) * 0.5, w, h }
}

fn draw_text(i: i32, a: f32) {
    let n .= nodes[i];
    let b = box_of(n);
    var style = text_style_of(n);
    let x = b.x + n.d.lay.padding.x;
    let y = b.y + n.d.lay.padding.y;
    let w = b.w - pad_sum(n, 0);
    let wrapping = n.d.lay.wrap && w + 0.5 < n.natural.x;
    if wrapping || n.d.lay.justify == CENTER || n.d.lay.justify == END {
        style.wrap_width = max(w, 1.0);
        style.align = if n.d.lay.justify == CENTER { gfx2d::ALIGN_CENTER } else if n.d.lay.justify == END {
            gfx2d::ALIGN_RIGHT
        } else {
            gfx2d::ALIGN_LEFT
        };
        if !wrapping && n.natural.x > w {
            // Too long to fit and not wrapping: shown from its start.
            style.wrap_width = 0.0;
            style.align = gfx2d::ALIGN_LEFT;
        }
    }
    let s = node_text(i);
    let l = look_of(n);
    let fx = if has_glyphs(n) { n.cmd_first } else { -1 };
    text_layers(l, style, n.style.text_size, faded(n.style.ink, a), a, true) { o, st, c, ink, pass =>
        text_part(x + o.x, y + o.y, s, st, c, l.reveal, fx, ink, a);
    };
}

// The passes of text_layers: shadows, halos, outlines, the glyphs.
let TEXT_SHADOWS = 0;
let TEXT_HALOS = 1;
let TEXT_OUTLINES = 2;
let TEXT_GLYPHS = 3;

// Text in look `l`, drawn in `style` at `size` in `ink`, as the layers
// the block draws, in order: its shadow (a copy of it and its outline,
// moved; or soft, a glow), its halo (a glow), its outline (a stroke, half
// of it hidden by the glyphs), and its glyphs. The block gets where the
// layer is moved to, its style and color, whether it is the glyphs, and
// its pass. A glow (gfx2d's, under all of a string's glyphs) is drawn on
// its own, under glyphs of no color; with `merge`, for text drawn whole,
// one rides on the outline, or on the glyphs if there is none.
fn text_layers<F>(l: TextLook, style: gfx2d::TextStyle, size: f32, ink: gfx2d::Color, a: f32, merge: bool) {
    let ow = outline_width(l, size);
    var os = style;
    os.outline = ow * 2.0;
    let outlined = ow > 0.0 && l.outline_color.a > 0.0;
    let sh = l.shadow_offset;
    let shadowed = l.shadow.a > 0.0 && sh != float2_0;
    let soft = shadowed && l.shadow_soft > 0.0;
    let halo = l.glow > 0.0 && l.glow_color.a > 0.0;
    var soft_style = style;
    soft_style.glow = l.shadow_soft;
    soft_style.glow_color = faded(l.shadow, a);
    soft_style.glow_offset = sh;
    var halo_style = style;
    halo_style.glow = l.glow;
    halo_style.glow_color = faded(l.glow_color, a);
    // Which glow rides on the top layer under the glyphs' own: the halo,
    // else the soft shadow.
    let rides_halo = merge && halo;
    let rides_soft = merge && soft && !halo;
    if shadowed && !soft {
        let c = faded(l.shadow, a);
        if ow > 0.0 { F(sh, os, c, false, TEXT_SHADOWS); }
        F(sh, style, c, false, TEXT_SHADOWS);
    }
    if soft && !rides_soft { F(float2_0, soft_style, gfx2d::TRANSPARENT, false, TEXT_SHADOWS); }
    if halo && !rides_halo { F(float2_0, halo_style, gfx2d::TRANSPARENT, false, TEXT_HALOS); }
    var top = if outlined { os } else { style };
    if rides_halo || rides_soft {
        let g = if rides_halo { halo_style } else { soft_style };
        top.glow = g.glow;
        top.glow_color = g.glow_color;
        top.glow_offset = g.glow_offset;
    }
    if outlined { F(float2_0, top, faded(l.outline_color, a), false, TEXT_OUTLINES); }
    F(float2_0, if outlined { style } else { top }, ink, true, TEXT_GLYPHS);
}

// How far a text's shadow, halo and outline reach past its glyphs, at `size`.
fn look_reach(l: TextLook, size: f32) -> f32 {
    let o = l.shadow_offset;
    let outline: f32 = max(l.outline, 0.0);
    let soft: f32 = if l.shadow.a > 0.0 { min(l.shadow_soft, size / 8.0) } else { 0.0 };
    let glow: f32 = if l.glow > 0.0 { min(l.glow, size / 8.0) } else { 0.0 };
    max(outline + max(abs(o.x), abs(o.y)), max(soft + max(abs(o.x), abs(o.y)), glow))
}

// s drawn as gfx2d::text draws it, but only its first `chars` characters
// (all, if < 0), each where it is with all of them: row by row, from
// where each row of the whole starts.
//
// With effects (`fx`, its characters' first in `glyphs`; -1 for none),
// each glyph changed as its character says: its ink, on the ink pass,
// else `c`, faded by its alpha.
fn text_part(x: f64, y: f64, s: const u8[:], style: gfx2d::TextStyle, c: gfx2d::Color, chars: f32,
             fx: i32 = -1, ink_pass: bool = false, a: f32 = 1.0) {
    if chars < 0.0 { fx_text(x, y, s, style, c, fx, 0, ink_pass, a); return; }
    var left = ceil(chars) as i64;
    var before: i64 = 0;
    let lh = gfx2d::font_line_height(gfx2d::style_font(style), style.size) * style.line_spacing;
    var row_style = style;
    row_style.wrap_width = 0.0;
    row_style.align = gfx2d::ALIGN_LEFT;
    var r = 0;
    for row in gfx2d::break_lines(s, style) {
        if left <= 0 { break; }
        let end = chars_end(s, row.start, row.end, left);
        fx_text(gfx2d::line_left(x, row.width, style), y + r * lh, s[row.start..end], row_style, c, fx, before,
                ink_pass, a);
        let taken = text_chars(s[row.start..row.next]);
        left -= taken;
        before += taken;
        r++;
    }
}

// s drawn, its glyphs changed by their characters' effects if it has any:
// its first character is `index` of the text's.
fn fx_text(x: f64, y: f64, s: const u8[:], style: gfx2d::TextStyle, c: gfx2d::Color, fx: i32,
           index: i64, ink_pass: bool, a: f32) {
    if fx < 0 { gfx2d::text(x, y, s, style, c); return; }
    var at: i64 = 0;            // the byte counted to, and the characters before it
    var count = index;
    gfx2d::text_glyphs(x, y, s, style, c) { e =>
        while at < e.byte { if s[at] & 0xC0 != 0x80 { count++; } at++; }
        let g = glyphs[fx + count];
        glyph_edit(e, g);
        e.color = if ink_pass { faded(g.ink, a * g.alpha) } else { faded(c, g.alpha) };
        e.glow = faded(style.glow_color, g.alpha);
    };
}

// The outline drawn around text of a size, outside its glyphs: no more
// than the glyphs' distance field reaches (a sixteenth of the size).
fn outline_width(l: TextLook, size: f32) -> f64 {
    if l.outline <= 0.0 { 0.0 } else { min(l.outline, size / 16.0) }
}

fn draw_ring(i: i32, a: f32) {
    let n .= nodes[i];
    guard n.ring && n.style.ring_width > 0.0 && n.style.ring.a > 0.0;
    let b = box_of(n);
    let o = n.style.ring_offset + n.style.ring_width * 0.5;
    let r = n.style.radius;
    let rr = float4 { r.x + o, r.y + o, r.z + o, r.w + o };
    gfx2d::rounded_rect_outline(b.x - o, b.y - o, b.w + 2.0 * o, b.h + 2.0 * o, rr, n.style.ring_width,
                                faded(n.style.ring, a * max(nodes[i].d.vis.state.focus, 0.0)));
}

// Icon `kind` in box b, its lines in ink c.
fn draw_icon(kind: u8, b: gfx2d::Rect, c: gfx2d::Color) {
    let s = min(b.w, b.h);
    let x = b.x + (b.w - s) * 0.5;
    let y = b.y + (b.h - s) * 0.5;
    let w = max(s * 0.14, 1.5);
    fn p(u: f32, v: f32) -> float2 { float2 { x + u * s, y + v * s } }
    match kind {
        ICON_CHECK => { gfx2d::polyline([p(0.15, 0.52), p(0.4, 0.76), p(0.86, 0.26)], w, c, gfx2d::CAP_ROUND, gfx2d::JOIN_ROUND); },
        ICON_CHEVRON_DOWN => { gfx2d::polyline([p(0.2, 0.36), p(0.5, 0.66), p(0.8, 0.36)], w, c, gfx2d::CAP_ROUND, gfx2d::JOIN_ROUND); },
        ICON_CHEVRON_UP => { gfx2d::polyline([p(0.2, 0.64), p(0.5, 0.34), p(0.8, 0.64)], w, c, gfx2d::CAP_ROUND, gfx2d::JOIN_ROUND); },
        ICON_CHEVRON_RIGHT => { gfx2d::polyline([p(0.36, 0.2), p(0.66, 0.5), p(0.36, 0.8)], w, c, gfx2d::CAP_ROUND, gfx2d::JOIN_ROUND); },
        ICON_CHEVRON_LEFT => { gfx2d::polyline([p(0.64, 0.2), p(0.34, 0.5), p(0.64, 0.8)], w, c, gfx2d::CAP_ROUND, gfx2d::JOIN_ROUND); },
        ICON_CLOSE => {
            gfx2d::line(p(0.22, 0.22), p(0.78, 0.78), w, c, gfx2d::CAP_ROUND);
            gfx2d::line(p(0.78, 0.22), p(0.22, 0.78), w, c, gfx2d::CAP_ROUND);
        },
        ICON_PLUS => {
            gfx2d::line(p(0.2, 0.5), p(0.8, 0.5), w, c, gfx2d::CAP_ROUND);
            gfx2d::line(p(0.5, 0.2), p(0.5, 0.8), w, c, gfx2d::CAP_ROUND);
        },
        ICON_MINUS => { gfx2d::line(p(0.2, 0.5), p(0.8, 0.5), w, c, gfx2d::CAP_ROUND); },
        _ => {},
    }
}
