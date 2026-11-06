// Rich text: text in more than one style, and images on its lines, from
// markup in the string. Styles and images are registered by name, once:
//
//   imgui::add_span("dmg", imgui::Span { ink: gold, .. });
//   imgui::add_span("kw", imgui::Span { underline: true, .. });
//   imgui::add_inline("coin", coins, gfx2d::Rect { 0, 0, 32, 32 });
//   …
//   imgui::rich("Deal [dmg]20[/] damage. [kw]Burn[/kw] costs 3 [img=coin].",
//               imgui::column().wrap());
//
// [name] … [/] (or [/name]) is a span, and spans nest; [img=name] is an
// image, as tall as the text by default and centered on it; [[ is a [.
// [name=key] … [/] is a span the pointer can rest on: rich() returns which
// key is under it, and an Interaction for a tooltip there:
//
//   let h = imgui::rich("Deal 4 and [kw=burn]Burn[/] 2.", d);
//   imgui::tooltip(h.it) { if h.was("burn") { imgui::text("Burn: 1 damage a turn."); } };
//
// A
// span changes what it sets of the text's ink, font, size and look
// (letter spacing, outline, shadow), and can underline. The text wraps,
// justifies and sizes as text() does. Lines break at spaces only, so a
// word in two styles stays whole.

namespace imgui;

import std;
import vec;
import dictionary;
import gfx;
import gfx2d;

// What a span changes; each part unset (transparent, 0) is the text's.
struct Span {
    ink: gfx2d::Color = gfx2d::Color { 0.0, 0.0, 0.0, 0.0 },
    font: gfx2d::Font = gfx2d::Font { 0 },
    text_size: f32 = 0.0,
    text_look: u16 = 0,                 // add_text_look's: over the text's own
    underline: bool = false,
    text_fx: u16 = 0,                   // an effect for its characters (textfx.goose), and its numbers
    fx_args: float4 = float4 { 0.0, 0.0, 0.0, 0.0 },
}

// An image on a line: `src` of `texture`, `scale` times the text's size
// tall, and raised by `rise` times the size.
struct Inline {
    texture: gfx::Texture = gfx::Texture { 0 },
    src: gfx2d::Rect = gfx2d::Rect { 0.0, 0.0, 0.0, 0.0 },
    scale: f32 = 1.0,
    rise: f32 = 0.0,
}

var spans: Span[>..] = [];
var span_names = dictionary<u64, i64> {};
var inlines: Inline[>..] = [];
var inline_names = dictionary<u64, i64> {};

fn add_span(name: const u8[:], s: Span) {
    spans.push(s);
    span_names.insert(hash(name), spans.len - 1);
}
fn add_inline(name: const u8[:], t: gfx::Texture, src: gfx2d::Rect, scale: f64 = 1.0, rise: f64 = 0.0) {
    inlines.push(Inline { t, src, scale as f32, rise as f32 });
    inline_names.insert(hash(name), inlines.len - 1);
}

let PIECE_WORD: u8 = 0;
let PIECE_SPACE: u8 = 1;
let PIECE_BREAK: u8 = 2;        // a newline
let PIECE_IMAGE: u8 = 3;

// A piece of a rich text: a word (or part of one, in one style), spaces, a
// newline or an image; measured.
struct Piece {
    kind: u8 = 0,
    underline: bool = false,
    glued: bool = false,                // no break before it: it goes on from the piece before
    look: u16 = 0,                      // a text look over the text's own (0: its own)
    font: gfx2d::Font = gfx2d::Font { 0 },
    size: f32 = 0.0,
    ink: gfx2d::Color = gfx2d::Color { 0.0, 0.0, 0.0, 0.0 },   // transparent: the text's
    off: i32 = 0,                       // its bytes in text_arena; an image's inline
    len: i32 = 0,
    w: f32 = 0.0,
    ascent: f32 = 0.0,                  // above the baseline
    below: f32 = 0.0,                   // below it, to the next line
    fx: u16 = 0,                        // its span's effect, and the numbers for it
    fx_args: float4 = float4 { 0.0, 0.0, 0.0, 0.0 },
    key: u64 = 0,                       // its span's key ([name=key]), hashed; 0: none
}

// This frame's pieces; a rich node's are text_len of them from text_off.
var pieces: Piece[>..<] = [];

// The style a piece is in, inside the spans open where it is.
struct RunStyle {
    font: gfx2d::Font,
    size: f32,
    ink: gfx2d::Color,
    look: u16,
    underline: bool,
    fx: u16,
    fx_args: float4,
    key: u64,
}

fn run_text_style(r: RunStyle, letter_spacing: f32) -> gfx2d::TextStyle {
    gfx2d::TextStyle { font: r.font, size: r.size, letter_spacing: letter_spacing, .. }
}

// The letter spacing of a piece in look `k` of a node whose own is `own`.
fn piece_look(k: u16, own: TextLook) -> TextLook { if k == 0 { own } else { over_look(text_look_of(k), own) } }

// Rich text from markup; which of its keyed spans the pointer is on.
fn rich(s: const u8[:], d: Desc) -> SpanHit {
    let i = record_rich(s, d);
    if i < 0 { return SpanHit { .. }; }
    var any = look_of(nodes[i]).text_fx != 0;
    for k in nodes[i].text_off..nodes[i].text_off + nodes[i].text_len { if pieces[k].fx != 0 { any = true; } }
    if any {
        rich_glyphs_of(i);
        run_glyphs(i) { g => standard_fx(g); };
    }
    span_hit(i)
}
// Rich text with effects of the program's own: the block run for each
// character, with a Glyph to change (textfx.goose).
fn rich<F>(s: const u8[:], d: Desc) -> SpanHit {
    let i = record_rich(s, d);
    if i < 0 { return SpanHit { .. }; }
    rich_glyphs_of(i);
    run_glyphs(i) { g => F(g); };
    span_hit(i)
}
fn record_rich(s: const u8[:], d: Desc) -> i32 {
    // With keyed spans, it has an ID, from its text in its scope, to keep
    // which was hovered by.
    let i = add_node(NODE_RICH, if has_keys(s) { id(s).v } else { 0 }, d);
    if i < 0 { return -1; }
    let own = look_of(nodes[i]);
    let base_font = if nodes[i].style.font.id != 0 { nodes[i].style.font } else { gfx2d::default_font() };
    var stack: RunStyle[..16] = [];
    stack.push(RunStyle { base_font, nodes[i].style.text_size, gfx2d::Color { 0.0, 0.0, 0.0, 0.0 }, 0, false, 0,
                          float4 { 0.0, 0.0, 0.0, 0.0 }, 0 });
    nodes[i].text_off = pieces.len as i32;
    var word = -1;              // where the word being read starts in text_arena, -1: none
    var glue = false;           // the next piece goes on from the one before

    fn add(kind: u8, off: i64, len: i64, w: f64, ascent: f64, below: f64) {
        let r = stack[stack.len - 1];
        pieces.push(Piece { kind: kind, underline: r.underline, glued: glue && (kind == PIECE_WORD || kind == PIECE_IMAGE), look: r.look, font: r.font, size: r.size,
                            ink: r.ink, off: off as i32, len: len as i32, w: w as f32, ascent: ascent as f32,
                            below: below as f32, fx: r.fx, fx_args: r.fx_args, key: r.key });
        glue = kind == PIECE_WORD || kind == PIECE_IMAGE;
    }
    fn text_piece(kind: u8, off: i64) {
        let r = stack[stack.len - 1];
        let len = text_arena.len - off;
        let w = gfx2d::measure_text(text_arena[off..off + len], run_text_style(r, piece_look(r.look, own).letter_spacing)).x;
        let ascent = gfx2d::font_ascent(r.font, r.size);
        add(kind, off, len, w, ascent, gfx2d::font_line_height(r.font, r.size) - ascent);
    }
    fn end_word() {
        if word >= 0 { text_piece(PIECE_WORD, word); word = -1; }
    }

    var at = 0;
    while at < s.len {
        let c = s[at];
        if c == '[' && at + 1 < s.len && s[at + 1] == '[' {
            if word < 0 { word = text_arena.len; }
            text_arena.push('[');
            at += 2;
            continue;
        }
        if c == '[' {
            var close = at + 1;
            while close < s.len && s[close] != ']' { close++; }
            if close < s.len {
                let tag = s[at + 1..close];
                end_word();
                at = close + 1;
                if tag.len > 0 && tag[0] == '/' {
                    if stack.len > 1 { stack.pop(); } else { misuse("rich: a [/] closes no span"); }
                } else if tag.len > 4 && tag[..4] == "img=" {
                    let k = inline_names.get(hash(tag[4..]));
                    if !k { misuse("rich: no image of that name (add_inline)"); continue; }
                    let im = inlines[k];
                    let r = stack[stack.len - 1];
                    let h = r.size * im.scale;
                    let w = if im.src.h > 0.0 { h * im.src.w / im.src.h } else { h };
                    // Centered on the text's middle, raised by `rise`.
                    let ascent = gfx2d::font_ascent(r.font, r.size);
                    let mid = (ascent + gfx2d::font_descent(r.font, r.size)) * 0.5 + r.size * im.rise;
                    let below = gfx2d::font_line_height(r.font, r.size) - ascent;
                    add(PIECE_IMAGE, k, 0, w, max(ascent, mid + h * 0.5), max(below, h * 0.5 - mid));
                } else {
                    // A span, perhaps with a key: [name=key].
                    var eq = 0;
                    while eq < tag.len && tag[eq] != '=' { eq++; }
                    let k = span_names.get(hash(tag[..eq]));
                    if !k { misuse("rich: no span of that name (add_span)"); continue; }
                    if stack.len == 16 { misuse("rich: spans nested too deep"); continue; }
                    let sp = spans[k];
                    var r = stack[stack.len - 1];
                    if sp.ink.a > 0.0 { r.ink = sp.ink; }
                    if sp.font.id != 0 { r.font = sp.font; }
                    if sp.text_size > 0.0 { r.size = sp.text_size; }
                    if sp.text_look != 0 { r.look = sp.text_look; }
                    if sp.underline { r.underline = true; }
                    if sp.text_fx != 0 { r.fx = sp.text_fx; r.fx_args = sp.fx_args; }
                    if eq < tag.len { r.key = hash(tag[eq + 1..]); }
                    stack.push(r);
                }
                continue;
            }
        }
        if c == ' ' || c == '\n' {
            end_word();
            let off = text_arena.len;
            if c == '\n' {
                text_piece(PIECE_BREAK, off);
                glue = false;
                at++;
            } else {
                while at < s.len && s[at] == ' ' { text_arena.push(' '); at++; }
                text_piece(PIECE_SPACE, off);
                glue = false;
            }
            continue;
        }
        if word < 0 { word = text_arena.len; }
        text_arena.push(c);
        at++;
    }
    end_word();
    // Empty, it is still a line tall.
    if pieces.len == nodes[i].text_off { text_piece(PIECE_WORD, text_arena.len); }
    nodes[i].text_len = (pieces.len - nodes[i].text_off) as i32;

    // Its size on lines broken only at newlines, and its widest unbreakable run.
    let n .= nodes[i];
    var size = float2 { 0.0, 0.0 };
    each_rich_line(i, 0.0) { from, to, w, ascent, below =>
        size.x = max(size.x, w);
        size.y += ascent + below;
    };
    n.natural = size;
    var widest: f32 = 0.0;
    var run: f32 = 0.0;
    for k in n.text_off..n.text_off + n.text_len {
        let p = pieces[k];
        if p.kind == PIECE_WORD || p.kind == PIECE_IMAGE {
            run = if p.glued { run + p.w } else { p.w };
            widest = max(widest, run);
        }
    }
    n.word = widest;
    i
}
fn rich(s: const u8[:]) -> SpanHit { rich(s, column()) }
fn rich(s: const u8[:], c: StyleClass) -> SpanHit { rich(s, column().skin(c)) }

// --- keyed spans ------------------------------------------------------------------------

// Which keyed span of a rich text the pointer is on (`key`, 0 for none),
// the one it was last on (`last`, to keep a tooltip's content as it
// fades), and an Interaction for a tooltip: hovered while on one, its
// rect that span's.
struct SpanHit {
    key: u64 = 0,
    last: u64 = 0,
    it: Interaction = Interaction { .. },
}
fn is(h: SpanHit, key: const u8[:]) -> bool { h.key != 0 && h.key == hash(key) }
fn was(h: SpanHit, key: const u8[:]) -> bool { h.last != 0 && h.last == hash(key) }

// Where each keyed span was on the screen, last frame: a box per line it
// is on, with the rich text's ID and the widget it was in (its nearest
// ancestor that takes the pointer).
struct SpanBox { node: u64, owner: u64, key: u64, rect: gfx2d::Rect, clip: gfx2d::Rect, level: i32, window: u64 }
var span_boxes: SpanBox[>..<] = [];

// Whether s has a keyed span: a tag with '=' that is not an image.
fn has_keys(s: const u8[:]) -> bool {
    var at = 0;
    while at < s.len {
        if s[at] == '[' && at + 1 < s.len && s[at + 1] == '[' { at += 2; continue; }
        if s[at] == '[' {
            var k = at + 1;
            while k < s.len && s[k] != ']' && s[k] != '=' { k++; }
            if k < s.len && s[k] == '=' && !(k - at == 4 && s[at + 1..k] == "img") { return true; }
        }
        at++;
    }
    false
}

// Rich node i's keyed span under the pointer, from last frame's boxes: the
// pointer in one, and the widget the text is in the one it is over.
fn span_hit(i: i32) -> SpanHit {
    let n .= nodes[i];
    guard n.named else { return SpanHit { .. }; }
    var st = state_of(n.id);
    var h = SpanHit { it: Interaction { id: hash_combine(n.id, 0x5BA7), rect: st.span_rect, .. } };
    let p = input.pointer.pos;
    for b in span_boxes {
        // Where it can be seen: not clipped away, not under a modal, a popup
        // or another window.
        if b.node == n.id && b.owner == hot && b.level == hot_level && b.window == hot_window &&
           inside(b.clip, p) && gfx2d::contains(b.rect, p) {
            h.key = b.key;
            h.it.hovered = true;
            h.it.rect = b.rect;
            h.it.pointer = p - float2 { b.rect.x, b.rect.y };
            st.span = b.key;
            st.span_rect = b.rect;
            break;
        }
    }
    h.last = st.span;
    put_state(n.id, st);
    h
}

// After layout: where this frame's keyed spans are, for the next frame.
fn place_span_boxes() {
    span_boxes.clear();
    for i: i32 in 0..nodes.len as i32 {
        let n .= nodes[i];
        guard n.kind == NODE_RICH && n.named && n.ghost == 0 else { continue; }
        let owner = if n.owner >= 0 { nodes[n.owner].id } else { 0 };
        let root = roots[n.root as i64];
        let b = box_of(n);
        let x0 = b.x + n.d.lay.padding.x;
        let w = b.w - pad_sum(n, 0);
        let wrap = if n.d.lay.wrap && w + 0.5 < n.natural.x { w } else { 0.0 };
        var y = b.y + n.d.lay.padding.y;
        each_rich_line(i, wrap) { from, to, lw, ascent, below =>
            var x = x0;
            if n.d.lay.justify == CENTER { x += (w - lw) * 0.5; } else if n.d.lay.justify == END { x += w - lw; }
            // A box for each run of pieces with one key on the line.
            var key: u64 = 0;
            var kx = x;
            fn close() {
                if key != 0 {
                    let r = gfx2d::Rect { kx, y, x - kx, ascent + below };
                    span_boxes.push(SpanBox { n.id, owner, key, gfx2d::transformed_bounds(n.m, r), n.clip, root.level,
                                              if root.kind == ROOT_WINDOW { root.popup } else { 0 } });
                }
            }
            for k in from..to {
                let p = pieces[k];
                if p.key != key { close(); key = p.key; kx = x; }
                x += p.w;
            }
            close();
            y += ascent + below;
        };
    }
}

// Each line of rich node i at `width` (0: broken only at newlines): its
// pieces from..to, its width, and how far it reaches above and below its
// baseline. Spaces where a line breaks are on neither line.
fn each_rich_line<F>(i: i32, width: f32) {
    let n .= nodes[i];
    let end = n.text_off + n.text_len;
    var a = n.text_off;         // the line's first piece
    var last = a;               // the end of its last word
    var lw: f32 = 0.0;          // its width to there
    var gap: f32 = 0.0;         // the spaces since
    fn emit(to: i32, fallback: i32) {
        var ascent: f32 = 0.0;
        var below: f32 = 0.0;
        if to > a {
            for k in a..to { ascent = max(ascent, pieces[k].ascent); below = max(below, pieces[k].below); }
        } else {
            let p = pieces[min(fallback, end - 1)];
            ascent = p.ascent;
            below = p.below;
        }
        F(a, to, lw, ascent, below);
    }
    var k = a;
    while k < end {
        let p = pieces[k];
        if p.kind == PIECE_SPACE { gap += p.w; k++; continue; }
        if p.kind == PIECE_BREAK {
            emit(last, k);
            a = k + 1;
            last = a;
            lw = 0.0;
            gap = 0.0;
            k++;
            continue;
        }
        // A run that can't be broken: this piece and those glued on.
        var u = k + 1;
        var uw = p.w;
        while u < end && pieces[u].glued { uw += pieces[u].w; u++; }
        if width > 0.0 && last > a && lw + gap + uw > width + 0.5 {
            emit(last, last);
            a = k;
            lw = uw;
        } else {
            lw += gap + uw;
        }
        gap = 0.0;
        last = u;
        k = u;
    }
    emit(last, end - 1);
}

// Its height at width w.
fn rich_height(i: i32, w: f32) -> f32 {
    var h: f32 = 0.0;
    each_rich_line(i, w) { from, to, lw, ascent, below => h += ascent + below; };
    h
}

// Drawn, its lines justified in its box: under it all its shadows, then its
// halos, then its outlines, then its glyphs, images and underlines; a pass
// no piece needs is skipped.
fn draw_rich(i: i32, a: f32) {
    let n .= nodes[i];
    let b = box_of(n);
    let x0 = b.x + n.d.lay.padding.x;
    let w = b.w - pad_sum(n, 0);
    let wrap = if n.d.lay.wrap && w + 0.5 < n.natural.x { w } else { 0.0 };
    let own = look_of(n);
    // With reveal: the characters before each piece, the pieces between
    // lines (newlines, spaces where they broke) counted too.
    let limit: i64 = if own.reveal < 0.0 { 1 << 62 } else { ceil(own.reveal) as i64 };
    let fx = if has_glyphs(n) { n.cmd_first } else { -1 };
    var needed = 1 << TEXT_GLYPHS;
    for k in n.text_off..n.text_off + n.text_len {
        let p = pieces[k];
        guard p.kind == PIECE_WORD else { continue; }
        text_layers(piece_look(p.look, own), gfx2d::TextStyle { .. }, p.size, gfx2d::WHITE, 1.0, false)
        { o, st, c, ink, pass => needed |= 1 << pass; };
    }
    for pass in 4 {
        guard needed & (1 << pass) != 0 else { continue; }
        var y = b.y + n.d.lay.padding.y;
        var counted = n.text_off;
        var before: i64 = 0;
        each_rich_line(i, wrap) { from, to, lw, ascent, below =>
            var x = x0;
            if n.d.lay.justify == CENTER { x += (w - lw) * 0.5; } else if n.d.lay.justify == END { x += w - lw; }
            let base = y + ascent;
            for k in from..to {
                while counted < k { before += piece_chars(pieces[counted]); counted++; }
                let p = pieces[k];
                let shown = clamp(limit - before, 0, piece_chars(p));
                if shown == 0 { break; }
                let ink = faded(if p.ink.a > 0.0 { p.ink } else { n.style.ink }, a);
                if p.kind == PIECE_IMAGE {
                    if pass == TEXT_GLYPHS {
                        let im = inlines[p.off];
                        let h: f64 = p.size * im.scale;
                        let ascent_f = gfx2d::font_ascent(p.font, p.size);
                        let mid = (ascent_f + gfx2d::font_descent(p.font, p.size)) * 0.5 + p.size * im.rise;
                        let r = gfx2d::Rect { x, (base - mid - h * 0.5) as f32, p.w, h as f32 };
                        if fx < 0 {
                            gfx2d::image(im.texture, r, im.src, faded(gfx2d::WHITE, a));
                        } else {
                            // Changed as a glyph is, about its middle.
                            let g = glyphs[fx + before];
                            var e = gfx2d::GlyphEdit { .. };
                            glyph_edit(e, g);
                            let cx = r.x + r.w * 0.5;
                            let cy = r.y + r.h * 0.5;
                            let m = gfx2d::mul(gfx2d::translation(cx + e.offset.x, cy + e.offset.y),
                                               gfx2d::mul(gfx2d::rotation(e.turn),
                                                          gfx2d::mul(gfx2d::scaling(e.scale), gfx2d::translation(-cx, -cy))));
                            gfx2d::transform(m) { gfx2d::image(im.texture, r, im.src, faded(gfx2d::WHITE, a * g.alpha)); };
                        }
                    }
                } else if p.kind == PIECE_WORD || p.kind == PIECE_SPACE {
                    let l = piece_look(p.look, own);
                    var style = gfx2d::TextStyle { font: p.font, size: p.size, letter_spacing: l.letter_spacing,
                                                   baseline: gfx2d::BASELINE_ALPHABETIC, .. };
                    let whole = shown == piece_chars(p);
                    let s = text_arena[p.off..chars_end(text_arena, p.off, p.off + p.len, shown)];
                    if p.kind == PIECE_WORD {
                        text_layers(l, style, p.size, ink, a, false) { o, st, c, is_ink, layer =>
                            if layer == pass { fx_text(x + o.x, base + o.y, s, st, c, fx, before, is_ink, a); }
                        };
                    }
                    if pass == TEXT_GLYPHS {
                        if p.underline {
                            let t = max(p.size / 14.0, 1.0);
                            let uw = if whole { p.w } else { gfx2d::measure_text(s, style).x as f32 };
                            if pixel_art {
                                // On the grid, a unit under the baseline.
                                gfx2d::rect(round(x), round(base) + 1.0, round(uw), round(t), ink);
                            } else {
                                gfx2d::rect(x, base + p.size * 0.12, uw, t, ink);
                            }
                        }
                    }
                }
                x += p.w;
            }
            y += ascent + below;
        };
    }
}

// The characters a piece is, as reveal() counts them.
fn piece_chars(p: Piece) -> i64 {
    if p.kind == PIECE_IMAGE || p.kind == PIECE_BREAK { 1 } else { text_chars(text_arena[p.off..p.off + p.len]) }
}

// The characters rich text shows, its markup left out: what reveal()
// counts to show all of it.
fn rich_chars(s: const u8[:]) -> i64 {
    var c = 0;
    var at = 0;
    while at < s.len {
        if s[at] == '[' && at + 1 < s.len && s[at + 1] == '[' { c++; at += 2; continue; }
        if s[at] == '[' {
            var close = at + 1;
            while close < s.len && s[close] != ']' { close++; }
            if close < s.len {
                if close - at > 5 && s[at + 1..at + 5] == "img=" { c++; }
                at = close + 1;
                continue;
            }
        }
        if s[at] & 0xC0 != 0x80 { c++; }
        at++;
    }
    c
}

// How far its outlines, shadows and glows reach past its box.
fn rich_reach(i: i32) -> f32 {
    let n .= nodes[i];
    let own = look_of(n);
    var r: f32 = 0.0;
    for k in n.text_off..n.text_off + n.text_len {
        let l = piece_look(pieces[k].look, own);
        r = max(r, look_reach(l, pieces[k].size));
    }
    r
}
