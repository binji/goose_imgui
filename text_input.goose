// A single line of text to edit: a name, a seed, a chat line. Clicked or
// focused, it takes the keyboard: typed text, the arrows (with Shift to
// select, Ctrl or Alt by word), Home and End, Backspace and Delete,
// select all, copy, cut and paste, Enter to submit.
//
//   var name: u8[>..] = [];
//   let e = imgui::text_input("Name", name, imgui::row().width(240));
//   if e.submitted { start(name); }
//
// The buffer is the program's: a u8[>..] or a u8[..N] (keep max_len at
// most N).

namespace imgui;

import std;
import vec;
import math;
import gfx2d;

struct TextEdit { changed: bool = false, submitted: bool = false, active: bool = false }

// The caret: solid for CARET_HOLD seconds after it is placed, moved, or
// the text changes, or the field takes the focus, so it is there while
// typing; then blinking, on for half of CARET_PERIOD and off for half,
// fading over CARET_FADE at each turn.
let CARET_HOLD = 0.5;
let CARET_PERIOD = 1.0;
let CARET_FADE = 0.12;
var caret_blinks = true;
// A caret that never blinks, for players who find blinking distracting.
fn set_caret_blink(on: bool) { caret_blinks = on; }

// How much of the caret shows, `idle` seconds after it last moved.
fn caret_alpha(idle: f64) -> f64 {
    if !caret_blinks || idle < CARET_HOLD { return 1.0; }
    let t = (idle - CARET_HOLD) % CARET_PERIOD;
    let half = CARET_PERIOD * 0.5;
    let k = if t < half { 1.0 - clamp((t - (half - CARET_FADE)) / CARET_FADE, 0.0, 1.0) }
            else { clamp((t - (CARET_PERIOD - CARET_FADE)) / CARET_FADE, 0.0, 1.0) };
    k * k * (3.0 - 2.0 * k)
}

// Copied or cut this frame, for the clipboard: limited, as last_misuse is.
var copied: u8[..4096] = [];

fn copy_out(s: const u8[:]) {
    copied.clear();
    for c in s { if copied.len < copied.cap { copied.push(c); } }
}

fn utf8_prev(s: const u8[:], i: i64) -> i64 {
    var k = i - 1;
    while k > 0 && (s[k] & 0xC0) == 0x80 { k--; }
    max(k, 0)
}
fn utf8_next(s: const u8[:], i: i64) -> i64 {
    var k = i + 1;
    while k < s.len && (s[k] & 0xC0) == 0x80 { k++; }
    min(k, s.len)
}
fn word_prev(s: const u8[:], i: i64) -> i64 {
    var k = i;
    while k > 0 && s[k - 1] == ' ' { k--; }
    while k > 0 && s[k - 1] != ' ' { k--; }
    k
}
fn word_next(s: const u8[:], i: i64) -> i64 {
    var k = i;
    while k < s.len && s[k] == ' ' { k++; }
    while k < s.len && s[k] != ' ' { k++; }
    k
}

// buf[a..b] removed.
fn erase_text<A>(buf: A&, a: i64, b: i64) {
    let n = b - a;
    if n <= 0 { return; }
    for k in a..buf.len - n { buf[k] = buf[k + n]; }
    for k in n { buf.pop(); }
}
// `s` put in buf at `at`, as much as max_len leaves room for (whole
// characters); how much went in.
fn insert_text<A>(buf: A&, at: i64, s: const u8[:], max_len: i64) -> i64 {
    var n = min(s.len, max_len - buf.len);
    if n <= 0 { return 0; }
    while n < s.len && n > 0 && (s[n] & 0xC0) == 0x80 { n--; }
    let old = buf.len;
    for k in n { buf.push(0); }
    var k = old - 1;
    while k >= at {
        buf[k + n] = buf[k];
        k--;
    }
    for j in n { buf[at + j] = s[j]; }
    n
}

fn text_input<A>(label: const u8[:], buf: A&, d: Desc = row(), max_len: i64 = 256, placeholder: const u8[:] = "") -> TextEdit {
    text_input(id(label), buf, d, max_len, placeholder)
}
fn text_input<A>(i: Id, buf: A&, d: Desc = row(), max_len: i64 = 256, placeholder: const u8[:] = "") -> TextEdit {
    let rd = clickable(d.skin(INPUT).with_bits(CAPTURE_X).align(CENTER)).clip();
    let it = interact(i, rd);
    var st = state_of(i.v);
    var e = TextEdit { active: it.focused, .. };
    var caret = clamp(st.caret as i64, 0, buf.len);
    var anchor = clamp(st.anchor as i64, 0, buf.len);
    // Taking the focus, the caret shows at once; `open` is whether it had it.
    if it.focused && !st.open { st.value = clock as f32; }
    st.open = it.focused;
    let up = inherited[inherited.len - 1];
    let cs = class_style(INPUT).normal;
    let style = gfx2d::TextStyle { font: if cs.font.id != 0 { cs.font } else { up.font },
                                   size: if cs.text_size > 0.0 { cs.text_size } else { up.size },
                                   letter_spacing: over_look(text_look_of(cs.text_look),
                                                             node_looks[up.look as i64]).letter_spacing, .. };
    let inset = cs.padding;
    // The pointer places the caret, and drags out a selection.
    if it.held {
        let scale = st.rect.w / max(it.rect.w, 0.0001);
        let x = it.pointer.x * scale - inset.x + st.text_scroll;
        let at = gfx2d::byte_at(0, 0, buf, style, float2 { x, 0.0 });
        caret = at;
        if it.pressed && !it.double_clicked { anchor = at; }
        st.value = clock as f32;
    }
    if it.double_clicked { anchor = 0; caret = buf.len; }
    if it.focused {
        keyboard_used = true;
        let lo = min(caret, anchor);
        let hi = max(caret, anchor);
        var sel = hi > lo;
        for k in input.keys {
            let s0 = min(caret, anchor);
            let s1 = max(caret, anchor);
            sel = s1 > s0;
            match k.key {
                KEY_LEFT => {
                    if sel && !k.shift { caret = s0; } else {
                        caret = if k.word { word_prev(buf, caret) } else { utf8_prev(buf, caret) };
                    }
                    if !k.shift { anchor = caret; }
                },
                KEY_RIGHT => {
                    if sel && !k.shift { caret = s1; } else {
                        caret = if k.word { word_next(buf, caret) } else { utf8_next(buf, caret) };
                    }
                    if !k.shift { anchor = caret; }
                },
                KEY_HOME => { caret = 0; if !k.shift { anchor = caret; } },
                KEY_END => { caret = buf.len; if !k.shift { anchor = caret; } },
                KEY_BACKSPACE => {
                    if sel { erase_text(buf, s0, s1); caret = s0; } else if caret > 0 {
                        let from = if k.word { word_prev(buf, caret) } else { utf8_prev(buf, caret) };
                        erase_text(buf, from, caret);
                        caret = from;
                    }
                    anchor = caret;
                    e.changed = true;
                },
                KEY_DELETE => {
                    if sel { erase_text(buf, s0, s1); caret = s0; } else if caret < buf.len {
                        let to = if k.word { word_next(buf, caret) } else { utf8_next(buf, caret) };
                        erase_text(buf, caret, to);
                    }
                    anchor = caret;
                    e.changed = true;
                },
                KEY_SELECT_ALL => { anchor = 0; caret = buf.len; },
                KEY_COPY => { if sel { copy_out(buf[s0..s1]); } },
                KEY_CUT => {
                    if sel {
                        copy_out(buf[s0..s1]);
                        erase_text(buf, s0, s1);
                        caret = s0;
                        anchor = caret;
                        e.changed = true;
                    }
                },
                KEY_ENTER => { e.submitted = true; },
                _ => {},
            }
            st.value = clock as f32;
        }
        if input.text.len > 0 {
            let s0 = min(caret, anchor);
            let s1 = max(caret, anchor);
            if s1 > s0 { erase_text(buf, s0, s1); caret = s0; }
            caret += insert_text(buf, caret, input.text, max_len);
            anchor = caret;
            e.changed = true;
            st.value = clock as f32;
        }
    }
    caret = clamp(caret, 0, buf.len);
    anchor = clamp(anchor, 0, buf.len);
    // Scrolled to keep the caret in view.
    let inner = max(st.rect.w - inset.x - inset.z, 1.0);
    let caret_x = gfx2d::measure_text(buf[..caret], style).x;
    if caret_x - st.text_scroll > inner - 2.0 { st.text_scroll = caret_x - inner + 2.0; }
    if caret_x - st.text_scroll < 0.0 { st.text_scroll = caret_x; }
    let full = gfx2d::measure_text(buf, style).x;
    st.text_scroll = clamp(st.text_scroll, 0.0, max(full - inner + 2.0, 0.0));
    st.caret = caret as i32;
    st.anchor = anchor as i32;
    put_state(i.v, st);
    let scroll_x = st.text_scroll;
    let line = gfx2d::font_line_height(style.font, style.size) as f32;
    box(i, rd) {
        let s0 = min(caret, anchor);
        let s1 = max(caret, anchor);
        if s1 > s0 && it.focused {
            let x0 = gfx2d::measure_text(buf[..s0], style).x - scroll_x;
            let x1 = gfx2d::measure_text(buf[..s1], style).x - scroll_x;
            panel(column().skin(SELECTION).absolute(x0, 0).size(x1 - x0, line));
        }
        if buf.len == 0 && placeholder.len > 0 && !it.focused {
            text(placeholder, column().skin(MUTED).text_size(style.size));
        } else {
            text(buf, column().offset(-scroll_x, 0).height(line));
        }
        if it.focused {
            let cw = class_style(CARET).normal.min_size.x;
            panel(column().skin(CARET).absolute(caret_x - scroll_x, 0).size(cw, line)
                  .opacity(caret_alpha(clock - st.value as f64)));
        }
    };
    e
}
