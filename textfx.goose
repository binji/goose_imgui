// Text effects: characters that shake, wave, pulse, swing, cycle their
// hue or flash, and characters that pop, drop or fade in as reveal()
// uncovers them. Each character's effect is worked out when its text is
// recorded, by code of the program's own if it likes, and applied when it
// is drawn; it moves only what is drawn, never the layout.
//
// A text or a span of rich text names an effect, and up to four numbers
// for it (0: the effect's default):
//
//   imgui::add_span("scared", imgui::Span { text_fx: imgui::FX_SHAKE, fx_args: float4 { 2, 0, 0, 0 }, .. });
//   imgui::rich("Get [scared]OUT[/] of here!", d.text_fx(imgui::FX_POP_IN).reveal(shown));
//
// and standard_fx plays the built-in ones. A block given to text or rich
// is run for each character instead, with a Glyph to change, so a program
// can make its own (numbered from FX_USER) and keep the built-ins:
//
//   imgui::rich(line, d) { g =>
//       imgui::standard_fx(g);
//       if g.span_fx == WOBBLE { g.turn += sin(g.time * 6.0 + g.index) * 0.2; }
//   };

namespace imgui;

import std;
import vec;
import math;
import gfx2d;

// The built-in effects, and what their numbers are (in order; 0 for the
// default given):
let FX_SHAKE: u16 = 1;      // jumping about: pixels (1.5), jumps a second (14)
let FX_WAVE: u16 = 2;       // a wave along the text: pixels (3), waves a second (1.5), radians per character (0.45)
let FX_PULSE: u16 = 3;      // growing and shrinking: by (0.15), pulses a second (1.5), radians per character (0.5)
let FX_SWING: u16 = 4;      // rocking: radians (0.15), swings a second (1), radians per character (0.6)
let FX_RAINBOW: u16 = 5;    // hue going round: turns a second (0.25), turns per character (0.06), lightness (0.8), chroma (0.16)
let FX_FLASH: u16 = 6;      // brightening and dimming: flashes a second (1.5), how bright (0.6), radians per character (0)
let FX_POP_IN: u16 = 7;     // growing in as revealed: from (0.2), over characters (4)
let FX_DROP_IN: u16 = 8;    // dropping in as revealed: from pixels above (10), over characters (4)
let FX_FADE_IN: u16 = 9;    // fading in as revealed: over characters (4)
let FX_USER: u16 = 64;      // a program's own effects from here

// A character of a text with effects: what it is, and how it is drawn.
struct Glyph {
    // what the effect works from
    index: i32 = 0,             // which character: as reveal() counts them
    count: i32 = 0,             // of how many
    cp: u32 = 0,                // the character (an image of rich text: 0xFFFC)
    seed: f32 = 0.0,            // 0 to 1, the text's own, so two texts don't move together
    time: f64 = 0.0,            // imgui::time()
    age: f32 = 1.0e9,           // characters revealed since this one was (reveal() - index); large without reveal
    text_fx: u16 = 0,           // the text's effect, and its numbers
    text_args: float4 = float4 { 0.0, 0.0, 0.0, 0.0 },
    span_fx: u16 = 0,           // the span's, in rich text
    span_args: float4 = float4 { 0.0, 0.0, 0.0, 0.0 },
    base: gfx2d::Color = gfx2d::Color { 0.0, 0.0, 0.0, 0.0 },  // its ink before any effect
    // what the effect changes
    offset: float2 = float2 { 0.0, 0.0 },   // moved
    scale: f32 = 1.0,           // about its middle
    turn: f32 = 0.0,            // radians, clockwise, about its middle
    ink: gfx2d::Color = gfx2d::Color { 0.0, 0.0, 0.0, 0.0 },
    alpha: f32 = 1.0,
}

// This frame's characters with effects; a text's are cmd_first..cmd_end
// (a text has no canvas commands).
var glyphs: Glyph[>..<] = [];

// How much text moves (offsets, scales, turns), for players who want less
// motion: 0 holds it still and keeps its colors.
var text_motion: f32 = 1.0;
fn set_text_motion(k: f64) { text_motion = clamp(k, 0.0, 1.0) as f32; }

fn has_glyphs(n: Node&) -> bool { n.cmd_end > n.cmd_first && n.cmd_count == 0 }

// A text's seed: from its ID, else its parent's and its text.
fn text_seed(i: i32, s: const u8[:]) -> f32 {
    let n .= nodes[i];
    let up = if n.parent >= 0 { nodes[n.parent].id } else { 0 };
    let h = if n.id != 0 { n.id } else { hash_combine(up, hash(s)) };
    let bits: f32 = (h >> 40) & 0xFFFF;
    bits / 65536.0
}

fn age_at(reveal: f32, index: i64) -> f32 { if reveal < 0.0 { 1.0e9 } else { reveal - index } }

// Plain text i's characters, ready for effects.
fn text_glyphs_of(i: i32, s: const u8[:]) {
    let n .= nodes[i];
    let l = look_of(n);
    let count = text_chars(s);
    let seed = text_seed(i, s);
    n.cmd_first = glyphs.len as i32;
    var at = 0;
    var k = 0;
    while at < s.len {
        let cp, next = gfx2d::decode_utf8(s, at);
        glyphs.push(Glyph { index: k as i32, count: count as i32, cp: cp, seed: seed, time: clock,
                            age: age_at(l.reveal, k), text_fx: l.text_fx, text_args: l.fx_args,
                            base: n.style.ink, ink: n.style.ink, .. });
        at = next;
        k++;
    }
    n.cmd_end = glyphs.len as i32;
}

// Rich text i's characters, ready for effects: each piece's, its span's
// effect and ink with it.
fn rich_glyphs_of(i: i32) {
    let n .= nodes[i];
    let l = look_of(n);
    var count = 0;
    for k in n.text_off..n.text_off + n.text_len { count += piece_chars(pieces[k]); }
    let seed = text_seed(i, text_arena[pieces[n.text_off].off..pieces[n.text_off].off + pieces[n.text_off].len]);
    n.cmd_first = glyphs.len as i32;
    var index = 0;
    for k in n.text_off..n.text_off + n.text_len {
        let p = pieces[k];
        let ink = if p.ink.a > 0.0 { p.ink } else { n.style.ink };
        var g = Glyph { count: count as i32, seed: seed, time: clock, text_fx: l.text_fx, text_args: l.fx_args,
                        span_fx: p.fx, span_args: p.fx_args, base: ink, ink: ink, .. };
        if p.kind == PIECE_IMAGE || p.kind == PIECE_BREAK {
            g.index = index as i32;
            g.cp = if p.kind == PIECE_IMAGE { 0xFFFC } else { '\n' };
            g.age = age_at(l.reveal, index);
            glyphs.push(g);
            index++;
            continue;
        }
        var at = p.off as i64;
        while at < p.off + p.len {
            let cp, next = gfx2d::decode_utf8(text_arena, at);
            g.index = index as i32;
            g.cp = cp;
            g.age = age_at(l.reveal, index);
            glyphs.push(g);
            at = next;
            index++;
        }
    }
    n.cmd_end = glyphs.len as i32;
}

// Node i's characters run through the block, each a copy (the block may
// record more text).
fn run_glyphs<F>(i: i32) {
    let first = nodes[i].cmd_first;
    let end = nodes[i].cmd_end;
    for k in first..end {
        var g = glyphs[k];
        F(&g);
        glyphs[k] = g;
    }
}

// --- the built-in effects ---------------------------------------------------------------

// The text's effect, then the span's.
fn standard_fx(g: Glyph&) {
    play_fx(g, g.text_fx, g.text_args);
    play_fx(g, g.span_fx, g.span_args);
}
fn is_standard_fx(fx: u16) -> bool { fx > 0 && fx < FX_USER }

fn or_default(v: f32, d: f64) -> f64 { if v != 0.0 { v } else { d } }

// 0 to 1, the same for the same seed, character, step and axis.
fn noise01(seed: f32, index: i32, step: f64, axis: i64) -> f64 {
    let h = hash_combine(hash_combine(hash(seed), hash(index as i64 * 2 + axis)), hash(step as i64));
    let bits: f64 = h >> 11;
    bits / 9007199254740992.0
}

// Effect `fx` with numbers `a` played on g.
fn play_fx(g: Glyph&, fx: u16, a: float4) {
    guard fx != 0;
    let t = g.time;
    let i: f64 = g.index;
    let phase = g.seed * TAU;
    if fx == FX_SHAKE {
        let px = or_default(a.x, 1.5);
        let step = floor(t * or_default(a.y, 14.0));
        g.offset += float2 { ((noise01(g.seed, g.index, step, 0) * 2.0 - 1.0) * px) as f32,
                             ((noise01(g.seed, g.index, step, 1) * 2.0 - 1.0) * px) as f32 };
    } else if fx == FX_WAVE {
        let s = sin(t * or_default(a.y, 1.5) * TAU - i * or_default(a.z, 0.45) + phase);
        g.offset.y -= (s * or_default(a.x, 3.0)) as f32;
    } else if fx == FX_PULSE {
        let s = sin(t * or_default(a.y, 1.5) * TAU - i * or_default(a.z, 0.5) + phase);
        g.scale *= (1.0 + or_default(a.x, 0.15) * s) as f32;
    } else if fx == FX_SWING {
        let s = sin(t * or_default(a.y, 1.0) * TAU - i * or_default(a.z, 0.6) + phase);
        g.turn += (or_default(a.x, 0.15) * s) as f32;
    } else if fx == FX_RAINBOW {
        let hue = t * or_default(a.x, 0.25) + i * or_default(a.y, 0.06) + g.seed;
        g.ink = gfx2d::oklcha(or_default(a.z, 0.8), or_default(a.w, 0.16), hue - floor(hue), g.ink.a);
    } else if fx == FX_FLASH {
        let s = 0.5 + 0.5 * sin(t * or_default(a.x, 1.5) * TAU - i * a.z + phase);
        let k = or_default(a.y, 0.6) * s;
        g.ink = gfx2d::mix(g.ink, gfx2d::with_alpha(gfx2d::WHITE, g.ink.a), k);
    } else if fx == FX_POP_IN {
        let p = clamp(g.age / or_default(a.y, 4.0), 0.0, 1.0);
        let from = or_default(a.x, 0.2);
        g.scale *= (from + (1.0 - from) * ease(EASE_OUT_BACK, p)) as f32;
        g.alpha *= min(p * 3.0, 1.0) as f32;
    } else if fx == FX_DROP_IN {
        let p = clamp(g.age / or_default(a.y, 4.0), 0.0, 1.0);
        g.offset.y -= (or_default(a.x, 10.0) * (1.0 - ease(EASE_OUT_CUBIC, p))) as f32;
        g.alpha *= p as f32;
    } else if fx == FX_FADE_IN {
        g.alpha *= clamp(g.age / or_default(a.x, 4.0), 0.0, 1.0) as f32;
    }
}

// The glyph's change, as gfx2d draws it, motion scaled by text_motion.
fn glyph_edit(e: gfx2d::GlyphEdit&, g: Glyph) {
    let k = text_motion;
    e.offset = g.offset * k;
    e.scale = 1.0 + (g.scale - 1.0) * k;
    e.turn = g.turn * k;
}

// How far a text's effects can take its glyphs past its box.
fn glyph_reach(n: Node&) -> f32 {
    var r: f32 = 0.0;
    let size = n.style.text_size;
    for k in n.cmd_first..n.cmd_end {
        let g = glyphs[k];
        r = max(r, max(abs(g.offset.x), abs(g.offset.y)) + abs(g.scale - 1.0) * size + abs(g.turn) * size);
    }
    r
}
