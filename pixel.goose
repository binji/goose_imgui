// Pixel art: a UI drawn in whole pixels of its own, each a square of the
// screen's. In pixel-art mode the UI's scale is a whole number of screen
// pixels a unit, every box lands on whole units, nothing is antialiased,
// and images are drawn nearest; a bitmap font draws the text.
//
//   imgui::set_pixel_art(true);
//   imgui::set_scale(3);                // three screen pixels to the UI's one
//   // once the window is open:
//   imgui::theme_pixel();               // pixel_font(), in a theme sized for it
//
// A design pixel is then a unit: a 6-unit-tall font is 18 screen pixels
// at scale 3, and a 16 x 16 sprite in image() is 48.

namespace imgui;

import std;
import vec;
import math;
import gfx;
import gfx2d;

var pixel_art = false;

// Pixel-art mode, on or off.
fn set_pixel_art(on: bool) { pixel_art = on; }
fn is_pixel_art() -> bool { pixel_art }

// The scale the UI is drawn at, over gfx2d's base scale: set_scale's, but
// in pixel-art mode, rounded down to whole screen pixels a unit (at least one).
fn drawn_scale() -> f64 {
    guard pixel_art else { return ui_scale; }
    let base = max(gfx2d::current_scale(), 0.0001);
    max(floor(ui_scale * base + 1.0e-6), 1.0) / base
}

// A box on whole units: each edge rounded, so that boxes that meet still do.
fn snap_rect(r: gfx2d::Rect) -> gfx2d::Rect {
    let x0 = round(r.x);
    let y0 = round(r.y);
    gfx2d::Rect { x0, y0, round(r.x + r.w) - x0, round(r.y + r.h) - y0 }
}

// --- a font --------------------------------------------------------------------------

// Small capitals 3 pixels wide and 5 high, in cells of 4 x 6, read row by
// row: digits, letters (lower case drawn as upper) and punctuation.
let PIXEL_FONT_CHARS = " 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz.,:;!?-+/%'\"()<>=*#_[]";
let PIXEL_GLYPHS = [
    "000000000000000",                                                                         // space
    "111101101101111", "010110010010111", "111001111100111", "111001111001111", "101101111001001",   // 0-4
    "111100111001111", "111100111101111", "111001001001001", "111101111101111", "111101111001111",   // 5-9
    "010101111101101", "110101110101110", "011100100100011", "110101101101110", "111100110100111",   // A-E
    "111100110100100", "011100101101011", "101101111101101", "111010010010111", "001001001101010",   // F-J
    "101101110101101", "100100100100111", "101111111101101", "110101101101101", "010101101101010",   // K-O
    "110101110100100", "010101101110011", "110101110101101", "011100010001110", "111010010010010",   // P-T
    "101101101101111", "101101101101010", "101101111111101", "101101010101101", "101101010010010",   // U-Y
    "111001010100111",                                                                         // Z
    "000000000000010", "000000000010100", "000010000010000", "000010000010100", "010010010000010",   // . , : ; !
    "110001010000010", "000000111000000", "000010111010000", "001001010100100", "101001010100101",   // ? - + / %
    "010010000000000", "101101000000000", "001010010010001", "100010010010100", "001010100010001",   // ' " ( ) <
    "100010001010100", "000111000111000", "000101010101000", "101111101111101", "000000000000111",   // > = * # _
    "011010010010011", "110010010010110",                                                      // [ ]
];

var pixel_font_made = gfx2d::Font { 0 };

// The built-in pixel font: small capitals in 4 x 6 cells, its size 6 (a
// texel a unit; 12, 18 … for two or three). Made the first time it is
// asked for, which has to be once the window is open.
fn pixel_font() -> gfx2d::Font {
    if pixel_font_made.id != 0 { return pixel_font_made; }
    // Each character's cell: the letters once more for lower case.
    var cells: i64[>..] = [];
    for k in 37 { cells.push(k); }                  // space, digits, A-Z
    for k in 26 { cells.push(11 + k); }             // a-z
    for k in PIXEL_GLYPHS.len - 37 { cells.push(37 + k); }
    let cols = 16;
    let rows = (cells.len + cols - 1) / cols;
    let w = cols * 4;
    let h = rows * 6;
    var texels: u8[>..] = [];
    texels.resize(w * h * 4, 0);
    for g, n in cells {
        let bits = PIXEL_GLYPHS[g];
        for k in 15 {
            if bits[k] == '1' {
                let at = (((n / cols) * 6 + k / 3) * w + (n % cols) * 4 + k % 3) * 4;
                for c in 4 { texels[at + c] = 255; }
            }
        }
    }
    let sheet = gfx::texture2d(w, h);
    gfx::update_texture(sheet, texels);
    pixel_font_made = gfx2d::bitmap_font(sheet, 4, 6, PIXEL_FONT_CHARS);
    pixel_font_made
}

// --- a theme -------------------------------------------------------------------------

// A theme for pixel-art mode, its text `font` at `size` (a bitmap font's
// cell height, or a whole multiple of it): each built-in class's sizes
// scaled to the font and rounded to whole units, corners square, shadows
// hard, borders and the focus ring a unit wide, and no easing between
// states. In `p`'s colors, or pixel_palette()'s.
fn theme_pixel() { theme_pixel(pixel_font(), 6); }
fn theme_pixel(font: gfx2d::Font, size: f64) { theme_pixel(font, size, pixel_palette()); }
fn theme_pixel(font: gfx2d::Font, size: f64, var p: Palette) {
    let base = Palette { .. };
    let k = size / base.text_size;
    p.font = font;
    p.text_size = size as f32;
    p.title_size = (size * 2.0) as f32;
    // The palette's own lengths are scaled with the rest, below.
    p.radius = 0.0;
    p.transition = 0.0;
    theme(p);
    for c in CLASS_COUNT {
        var s = classes[c];
        each_state(s) { st => st = pixel_style(st, k, size); };
        s.transition = INSTANT;
        classes[c] = s;
    }
    // A title is twice the size; the rest of the text one size: a bitmap
    // font scaled by a fraction loses its pixels.
    classes[TITLE.index] = style_set(Style { ink: p.ink, text_size: p.title_size });
    // A press moves a button down a unit, as zoom can't in whole pixels.
    for c in [BUTTON, DROPDOWN, SELECTABLE, MENU_HEADER, TAB, MENU_ITEM] {
        classes[c.index].active.offset = float2 { 0.0, 1.0 };
    }
}

// The colors theme_pixel uses by default: a dusk palette of its own.
fn pixel_palette() -> Palette {
    Palette { screen: gfx2d::rgb(0x15111F), surface: gfx2d::rgb(0x2B2440), raised: gfx2d::rgb(0x46395F),
              hover: gfx2d::rgb(0x5C4A7A), pressed: gfx2d::rgb(0x231C33), line: gfx2d::rgb(0xE8D6B0),
              ink: gfx2d::rgb(0xF4EBD9), muted: gfx2d::rgb(0xA898B8), accent: gfx2d::rgb(0x6CC08A),
              accent_hover: gfx2d::rgb(0x8EE0A8), accent_ink: gfx2d::rgb(0x14101E),
              backdrop: gfx2d::rgba(0x0B0812, 0.7), shadow: gfx2d::rgb(0x0B0812), .. }
}

// A style's lengths times k, on whole units: a length that was there is at
// least one; corners square; a shadow hard; any text at `size`.
fn pixel_style(var s: Style, k: f64, size: f64) -> Style {
    fn len(v: f32, k: f64) -> f32 {
        let l = max(round(abs(v) * k), 1.0) as f32;
        if v == 0.0 { 0.0 } else if v < 0.0 { -l } else { l }
    }
    fn len2(v: float2, k: f64) -> float2 { float2 { len(v.x, k), len(v.y, k) } }
    fn len4(v: float4, k: f64) -> float4 { float4 { len(v.x, k), len(v.y, k), len(v.z, k), len(v.w, k) } }
    s.border_width = len(s.border_width, k);
    s.radius = float4 { 0.0, 0.0, 0.0, 0.0 };
    s.shadow.offset = len2(s.shadow.offset, k);
    s.shadow.blur = 0.0;
    s.shadow.spread = len(s.shadow.spread, k);
    s.padding = len4(s.padding, k);
    s.offset = len2(s.offset, k);
    s.zoom = 1.0;
    s.ring_width = len(s.ring_width, k);
    s.ring_offset = len(s.ring_offset, k);
    s.min_size = len2(s.min_size, k);
    s.gap = len(s.gap, k);
    if s.text_size > 0.0 { s.text_size = size as f32; }
    s
}
