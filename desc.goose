// What a node is: how it lays out its children, how big it is, how it
// looks and moves, and how it takes input. A Desc is a fixed-size value,
// built by chaining setters, each a copy of the last with one thing
// changed:
//
//   imgui::row().gap(8).padding(12, 6).align(imgui::CENTER).grow_w().skin(imgui::PANEL)
//
// A field wins over a function in `d.f()`, so Desc's own fields have short
// names no setter uses (lay, dim, vis, mot, bits); the setters are the
// interface.

namespace imgui;

import std;
import vec;
import gfx;
import gfx2d;

// --- layout kinds, alignment --------------------------------------------------------

// LayoutDesc.kind: how a node places its children.
let ROW = 0;        // left to right
let COLUMN = 1;     // top to bottom
let STACK = 2;      // over each other, each placed in the whole inner box by its place()
let GRID = 3;       // in the cells of column (and row) tracks

// justify (along the main axis) and align (across it). In a stack, a
// child's place() is the pair; in a grid cell, a child that is not
// stretched is placed by its parent's justify and align.
let START = 0;
let CENTER = 1;
let END = 2;
let STRETCH = 3;            // align: as big as the line, or cell, across
let SPACE_BETWEEN = 4;      // justify: the free space between the children
let SPACE_AROUND = 5;       //          around each, half at the ends
let SPACE_EVENLY = 6;       //          between them and at the ends, equally
let INHERIT = 255;          // self_align: the parent's align

// --- sizes ----------------------------------------------------------------------------

let SIZE_FIT = 0;       // the content's size, within lo..hi
let SIZE_PX = 1;        // value pixels
let SIZE_GROW = 2;      // the content's size, then a share (value is the weight) of the space left
let SIZE_PCT = 3;       // value (0 to 1) of the parent's inner size

struct Size { kind: u8 = 0, value: f32 = 0.0, lo: f32 = 0.0, hi: f32 = 1.0e30 }

fn fit() -> Size { Size { .. } }
fn px(v: f64) -> Size { Size { kind: SIZE_PX, value: v as f32 } }
fn grow() -> Size { Size { kind: SIZE_GROW, value: 1.0 } }
fn grow(weight: f64) -> Size { Size { kind: SIZE_GROW, value: weight as f32 } }
fn pct(f: f64) -> Size { Size { kind: SIZE_PCT, value: f as f32 } }
fn between(var s: Size, lo: f64, hi: f64) -> Size { s.lo = lo as f32; s.hi = hi as f32; s }

let MAX_TRACKS = 8;

struct LayoutDesc {
    kind: u8 = 1,                       // COLUMN
    justify: u8 = 0,                    // START
    align: u8 = 0,                      // START
    wrap: bool = false,                 // a row: onto more lines; text: at spaces to fit its width
    spacing: float2 = float2 { 0.0, 0.0 },  // between columns (x) and rows (y)
    padding: float4 = float4 { 0.0, 0.0, 0.0, 0.0 },   // left, top, right, bottom
    columns: Size[..8] = [],            // a grid's column tracks: px, grow (fr), fit (auto), pct
    rows: Size[..8] = [],               // its first rows' tracks; rows past them are fit
    col: i8 = -1,                       // in a grid: the cell, or -1 for the next free one
    row: i8 = -1,
    col_span: u8 = 1,
    row_span: u8 = 1,
    self_align: u8 = 255,               // INHERIT: across the parent's main axis; in a stack, vertical
    self_justify: u8 = 0,               // in a stack: horizontal
    absolute: bool = false,             // out of the flow, at `at` in the parent's padding box
    pivot_x: i16 = 0,                   // the point of its own put at `at`, in 1/PIVOT_UNIT of its size
    pivot_y: i16 = 0,
    at: float2 = float2 { 0.0, 0.0 },
}

struct SizeDesc { w: Size = Size { .. }, h: Size = Size { .. } }

// How a node looks, beyond its class's style: inline overrides, each
// flagged in `ov`.
let OV_BG = 1;
let OV_RADIUS = 2;
let OV_BORDER = 4;
let OV_INK = 8;
let OV_TEXT_SIZE = 16;
let OV_FONT = 32;
let OV_SHADOW = 64;
let OV_PADDING = 128;
let OV_LETTER_SPACING = 256;
let OV_TEXT_OUTLINE = 512;
let OV_TEXT_SHADOW = 1024;
let OV_REVEAL = 2048;
let OV_TEXT_FX = 4096;

struct LookDesc {
    class: StyleClass = StyleClass { 0 },   // NONE: no style but the overrides
    ov: u16 = 0,
    bg: gfx2d::Color = gfx2d::Color { 0.0, 0.0, 0.0, 0.0 },
    bg2: gfx2d::Color = gfx2d::Color { 0.0, 0.0, 0.0, 0.0 },
    gradient: u8 = 0,                   // GRADIENT_NONE
    radius: float4 = float4 { 0.0, 0.0, 0.0, 0.0 },
    border: gfx2d::Color = gfx2d::Color { 0.0, 0.0, 0.0, 0.0 },
    border_width: f32 = 0.0,
    ink: gfx2d::Color = gfx2d::Color { 0.0, 0.0, 0.0, 0.0 },
    text_size: f32 = 0.0,
    font: gfx2d::Font = gfx2d::Font { 0 },
    shadow: Shadow = Shadow { .. },
    fx: u32 = 0,                        // its text effects: 0 none, else where in a table (desc_fx)
    fx_frame: u32 = 0,                  // the frame they were set in, if in that frame's table
    opacity: f32 = 1.0,
    clips: bool = false,                // children clipped to the node's (rounded) box
    isolated: bool = false,             // drawn into a layer, composited at its opacity
    state: LookState = LookState { .. },
}

// Where a node is in its widget's states, each from 0 to 1: what its
// class's styles are mixed by.
struct LookState { hover: f32 = 0.0, press: f32 = 0.0, focus: f32 = 0.0, checked: f32 = 0.0,
                   disabled: bool = false }

struct Enter { alpha: f32 = 1.0, shift: float2 = float2 { 0.0, 0.0 }, zoom: f32 = 1.0,
               motion: Motion = Motion { .. } }
// What a node goes to as it leaves: its opacity times `alpha`, moved by
// `shift`, scaled by `zoom`.
struct Exit { alpha: f32 = 1.0, shift: float2 = float2 { 0.0, 0.0 }, zoom: f32 = 1.0,
              motion: Motion = Motion { .. } }

struct MotionDesc {
    enter: Enter = Enter { .. },        // played the first frame the node's ID is seen
    exit: u32 = 0,                      // played, on a copy of it, the first frame its ID is not: 0 none, else where in a table (desc_exit)
    exit_frame: u32 = 0,                // the frame it was set in, if in that frame's table
    glide: Motion = Motion { .. },      // from where it was to where it is, when its layout moves
    offset: float2 = float2 { 0.0, 0.0 },   // drawn this far from its laid-out place
    zoom: f32 = 1.0,                    // and scaled about its center
    turn: f32 = 0.0,                    // and turned about it, radians clockwise
    slant: f32 = 0.0,                   // and skewed: its verticals leaning right by this angle
}

// Desc.bits.
let HIT = 1;                // takes the pointer: hover, press, click, drag
let FOCUSABLE = 2;          // in the focus order
let BLOCKS = 4;             // stops the pointer reaching what is under it, without taking it
let NAV_SKIP = 8;           // focusable by the pointer, not by navigation
let CAPTURE_X = 16;         // when focused, left and right go to the widget, not to navigation
let CAPTURE_Y = 32;         // up and down
let SCROLLS_X = 64;
let SCROLLS_Y = 128;
let KEEP = 256;             // keeps state between frames though nothing else asks for it
let DISABLED = 512;
let CLICK_ON_PRESS = 1024;  // clicked when pressed, not when released over it
let PASSTHROUGH = 2048;     // it and its subtree let the pointer through, but for what takes it

struct Desc {
    lay: LayoutDesc = LayoutDesc { .. },
    dim: SizeDesc = SizeDesc { .. },
    vis: LookDesc = LookDesc { .. },
    mot: MotionDesc = MotionDesc { .. },
    bits: u32 = 0,
}

// --- text effects ---------------------------------------------------------------------

// A Desc's text effects are kept out of it, in a table: few nodes have
// them, and every setter copies the whole Desc. Set during a frame, they go
// in that frame's table, and the Desc is good for that frame only; set
// outside any frame (a Desc made once and kept), in a lasting table, each
// different value once. Its flags in `ov` say which parts it sets.
var frame_fx: TextLook[>..<] = [];
var lasting_fx: TextLook[>..<] = [];
let FX_LASTING: u32 = 0x80000000;

fn desc_fx(v: LookDesc) -> TextLook {
    if v.fx == 0 { return TextLook { .. }; }
    if v.fx & FX_LASTING != 0 { return lasting_fx[((v.fx & ~FX_LASTING) - 1) as i64]; }
    if v.fx_frame != frame_index as u32 || v.fx > frame_fx.len {
        misuse("a Desc's text effects were set in an earlier frame: set them in the frame that uses the Desc, or outside any frame");
        return TextLook { .. };
    }
    frame_fx[(v.fx - 1) as i64]
}

fn with_fx(var d: Desc, fx: TextLook, flag: i64) -> Desc {
    if in_frame {
        frame_fx.push(fx);
        d.vis.fx = frame_fx.len as u32;
        d.vis.fx_frame = frame_index as u32;
    } else {
        var k = 0;
        while k < lasting_fx.len && !same_fx(lasting_fx[k], fx) { k++; }
        if k == lasting_fx.len { lasting_fx.push(fx); }
        d.vis.fx = (k + 1) as u32 | FX_LASTING;
    }
    d.vis.ov |= flag as u16;
    d
}

fn same_fx(a: TextLook, b: TextLook) -> bool {
    a.letter_spacing == b.letter_spacing && a.outline == b.outline && a.outline_color == b.outline_color &&
    a.shadow == b.shadow && a.shadow_offset == b.shadow_offset && a.reveal == b.reveal &&
    a.text_fx == b.text_fx && a.fx_args == b.fx_args
}

// A Desc's exit is kept in tables the same way: few nodes have one.
var frame_exits: Exit[>..<] = [];
var lasting_exits: Exit[>..<] = [];

fn desc_exit(m: MotionDesc) -> Exit {
    if m.exit == 0 { return Exit { .. }; }
    if m.exit & FX_LASTING != 0 { return lasting_exits[((m.exit & ~FX_LASTING) - 1) as i64]; }
    if m.exit_frame != frame_index as u32 || m.exit > frame_exits.len {
        misuse("a Desc's exit was set in an earlier frame: set it in the frame that uses the Desc, or outside any frame");
        return Exit { .. };
    }
    frame_exits[(m.exit - 1) as i64]
}

// --- starting points ------------------------------------------------------------------

fn row() -> Desc { Desc { lay: LayoutDesc { kind: ROW }, .. } }
fn column() -> Desc { Desc { .. } }
fn stack() -> Desc { Desc { lay: LayoutDesc { kind: STACK }, .. } }
// Columns of these tracks; its children stretch to fill their cells.
fn grid(ts: const Size[:]) -> Desc { column().columns(ts).align(STRETCH).justify(STRETCH) }
// `n` equal columns.
fn grid(n: i64) -> Desc {
    var d = column();
    d.lay.kind = GRID;
    d.lay.align = STRETCH;
    d.lay.justify = STRETCH;
    for i in min(n, MAX_TRACKS) { d.lay.columns.push(grow()); }
    d
}

// --- layout setters -------------------------------------------------------------------

fn gap(var d: Desc, v: f64) -> Desc { d.lay.spacing = float2 { v as f32, v as f32 }; d }
fn gap(var d: Desc, x: f64, y: f64) -> Desc { d.lay.spacing = float2 { x as f32, y as f32 }; d }
fn padding(var d: Desc, all: f64) -> Desc {
    let v = all as f32;
    d.lay.padding = float4 { v, v, v, v };
    d.vis.ov |= OV_PADDING;
    d
}
fn padding(var d: Desc, x: f64, y: f64) -> Desc {
    d.lay.padding = float4 { x as f32, y as f32, x as f32, y as f32 };
    d.vis.ov |= OV_PADDING;
    d
}
fn padding(var d: Desc, left: f64, top: f64, right: f64, bottom: f64) -> Desc {
    d.lay.padding = float4 { left as f32, top as f32, right as f32, bottom as f32 };
    d.vis.ov |= OV_PADDING;
    d
}
fn justify(var d: Desc, j: i64) -> Desc { d.lay.justify = j as u8; d }
fn align(var d: Desc, a: i64) -> Desc { d.lay.align = a as u8; d }
// Both: centered along and across.
fn center(var d: Desc) -> Desc { d.lay.justify = CENTER; d.lay.align = CENTER; d }
fn wrap(var d: Desc) -> Desc { d.lay.wrap = true; d }
fn columns(var d: Desc, ts: const Size[:]) -> Desc {
    d.lay.kind = GRID;
    d.lay.columns.clear();
    for t in ts { if d.lay.columns.len < MAX_TRACKS { d.lay.columns.push(t); } }
    d
}
fn rows(var d: Desc, ts: const Size[:]) -> Desc {
    d.lay.rows.clear();
    for t in ts { if d.lay.rows.len < MAX_TRACKS { d.lay.rows.push(t); } }
    d
}
fn cell(var d: Desc, col: i64, row: i64) -> Desc { d.lay.col = col as i8; d.lay.row = row as i8; d }
fn span(var d: Desc, cols: i64, rows: i64) -> Desc {
    d.lay.col_span = max(cols, 1) as u8;
    d.lay.row_span = max(rows, 1) as u8;
    d
}
fn self_align(var d: Desc, a: i64) -> Desc { d.lay.self_align = a as u8; d }
// In a stack (the frame's root is one): where the child goes, across and down.
fn place(var d: Desc, h: i64, v: i64) -> Desc { d.lay.self_justify = h as u8; d.lay.self_align = v as u8; d }
fn absolute(var d: Desc, x: f64, y: f64) -> Desc {
    d.lay.absolute = true;
    d.lay.at = float2 { x as f32, y as f32 };
    d
}
// The point of an absolute node that its (x, y) is, as fractions of its
// size: (0.5, 1) is its bottom center, for a bar over a character's head.
// Kept in 1/1024ths, between -32 and 32.
let PIVOT_UNIT = 1024.0;
fn pivot(var d: Desc, px: f64, py: f64) -> Desc {
    fn unit(f: f64) -> i16 { clamp(round(f * PIVOT_UNIT), -32767.0, 32767.0) as i16 }
    d.lay.pivot_x = unit(px);
    d.lay.pivot_y = unit(py);
    d
}

// --- size setters ---------------------------------------------------------------------

fn width(var d: Desc, s: Size) -> Desc { d.dim.w = s; d }
fn width(d: Desc, v: f64) -> Desc { width(d, px(v)) }
fn height(var d: Desc, s: Size) -> Desc { d.dim.h = s; d }
fn height(d: Desc, v: f64) -> Desc { height(d, px(v)) }
fn size(d: Desc, w: f64, h: f64) -> Desc { d.width(w).height(h) }
fn size(d: Desc, w: Size, h: Size) -> Desc { d.width(w).height(h) }
fn grow_w(var d: Desc) -> Desc { d.dim.w.kind = SIZE_GROW; d.dim.w.value = 1.0; d }
fn grow_h(var d: Desc) -> Desc { d.dim.h.kind = SIZE_GROW; d.dim.h.value = 1.0; d }
fn grow(d: Desc) -> Desc { d.grow_w().grow_h() }
fn min_w(var d: Desc, v: f64) -> Desc { d.dim.w.lo = v as f32; d }
fn max_w(var d: Desc, v: f64) -> Desc { d.dim.w.hi = v as f32; d }
fn min_h(var d: Desc, v: f64) -> Desc { d.dim.h.lo = v as f32; d }
fn max_h(var d: Desc, v: f64) -> Desc { d.dim.h.hi = v as f32; d }

// --- look setters ---------------------------------------------------------------------

fn skin(var d: Desc, c: StyleClass) -> Desc { d.vis.class = c; d }
fn bg(var d: Desc, c: gfx2d::Color) -> Desc {
    d.vis.bg = c;
    d.vis.gradient = GRADIENT_NONE;
    d.vis.ov |= OV_BG;
    d
}
// Top to bottom.
fn bg(var d: Desc, top: gfx2d::Color, bottom: gfx2d::Color) -> Desc {
    d.vis.bg = top;
    d.vis.bg2 = bottom;
    d.vis.gradient = GRADIENT_VERTICAL;
    d.vis.ov |= OV_BG;
    d
}
// Left to right.
fn bg_h(var d: Desc, left: gfx2d::Color, right: gfx2d::Color) -> Desc {
    d.vis.bg = left;
    d.vis.bg2 = right;
    d.vis.gradient = GRADIENT_HORIZONTAL;
    d.vis.ov |= OV_BG;
    d
}
fn radius(var d: Desc, r: f64) -> Desc {
    let v = r as f32;
    d.vis.radius = float4 { v, v, v, v };
    d.vis.ov |= OV_RADIUS;
    d
}
// Top left, top right, bottom right, bottom left.
fn radius(var d: Desc, r: float4) -> Desc { d.vis.radius = r; d.vis.ov |= OV_RADIUS; d }
fn border(var d: Desc, w: f64, c: gfx2d::Color) -> Desc {
    d.vis.border_width = w as f32;
    d.vis.border = c;
    d.vis.ov |= OV_BORDER;
    d
}
fn shadow(var d: Desc, c: gfx2d::Color, blur: f64, dx: f64 = 0.0, dy: f64 = 0.0) -> Desc {
    d.vis.shadow = Shadow { color: c, offset: float2 { dx as f32, dy as f32 }, blur: blur as f32 };
    d.vis.ov |= OV_SHADOW;
    d
}
// The color of the node's text, and its text descendants'.
fn ink(var d: Desc, c: gfx2d::Color) -> Desc { d.vis.ink = c; d.vis.ov |= OV_INK; d }
fn text_size(var d: Desc, s: f64) -> Desc { d.vis.text_size = s as f32; d.vis.ov |= OV_TEXT_SIZE; d }
fn font(var d: Desc, f: gfx2d::Font) -> Desc { d.vis.font = f; d.vis.ov |= OV_FONT; d }
// Pixels added after each character of the node's text, and its text
// descendants'.
fn letter_spacing(d: Desc, px: f64) -> Desc {
    var fx = desc_fx(d.vis);
    fx.letter_spacing = px as f32;
    with_fx(d, fx, OV_LETTER_SPACING)
}
// An outline `w` pixels wide around the glyphs, in c, for text over busy
// scenes. It can be up to a sixteenth of the text's size.
fn text_outline(d: Desc, w: f64, c: gfx2d::Color) -> Desc {
    var fx = desc_fx(d.vis);
    fx.outline = w as f32;
    fx.outline_color = c;
    with_fx(d, fx, OV_TEXT_OUTLINE)
}
fn no_text_outline(d: Desc) -> Desc { text_outline(d, -1.0, gfx2d::TRANSPARENT) }
// A copy of the text (and its outline) in c, moved by (dx, dy), under it.
fn text_shadow(d: Desc, c: gfx2d::Color, dx: f64 = 1.0, dy: f64 = 1.0) -> Desc {
    var fx = desc_fx(d.vis);
    fx.shadow = c;
    fx.shadow_offset = float2 { dx as f32, dy as f32 };
    with_fx(d, fx, OV_TEXT_SHADOW)
}
fn no_text_shadow(d: Desc) -> Desc { text_shadow(d, gfx2d::BLACK, 0.0, 0.0) }
// The text's effect (FX_SHAKE, FX_WAVE … or a program's own, from
// FX_USER), and up to four numbers for it (0: its default); its text
// descendants' too. See textfx.goose.
fn text_fx(d: Desc, fx: u16, a: f64 = 0.0, b: f64 = 0.0, c: f64 = 0.0, e: f64 = 0.0) -> Desc {
    var t = desc_fx(d.vis);
    t.text_fx = fx;
    t.fx_args = float4 { a as f32, b as f32, c as f32, e as f32 };
    with_fx(d, t, OV_TEXT_FX)
}
// Only the text's first `chars` characters drawn (a newline, a space or a
// rich text's image each one), each where it is with all of them, so
// that typing it out doesn't move its lines: dialogue revealed as it is
// said. Not inherited; text_chars and rich_chars count a whole text.
fn reveal(d: Desc, chars: f64) -> Desc {
    var fx = desc_fx(d.vis);
    fx.reveal = max(chars, 0.0) as f32;
    with_fx(d, fx, OV_REVEAL)
}
fn opacity(var d: Desc, o: f64) -> Desc { d.vis.opacity = o as f32; d }
fn clip(var d: Desc) -> Desc { d.vis.clips = true; d }
fn isolate(var d: Desc) -> Desc { d.vis.isolated = true; d }
fn look(var d: Desc, s: LookState) -> Desc { d.vis.state = s; d }

// --- motion setters -------------------------------------------------------------------

fn enter(var d: Desc, e: Enter) -> Desc { d.mot.enter = e; d }
// When the node's ID is no longer recorded, a copy of it and its subtree,
// as they were last drawn, plays `e` out where it was. It needs an ID that
// stays its own (a label, a key): one from its place goes to its neighbour
// when it is gone.
fn exit(var d: Desc, e: Exit) -> Desc {
    if is_instant(e.motion) { d.mot.exit = 0; return d; }
    if in_frame {
        frame_exits.push(e);
        d.mot.exit = frame_exits.len as u32;
        d.mot.exit_frame = frame_index as u32;
    } else {
        var k = 0;
        while k < lasting_exits.len && lasting_exits[k] != e { k++; }
        if k == lasting_exits.len { lasting_exits.push(e); }
        d.mot.exit = (k + 1) as u32 | FX_LASTING;
    }
    d
}
fn glide(var d: Desc, m: Motion) -> Desc { d.mot.glide = m; d }
// The enter transition starts this much later: a list staggered by index.
fn delay(var d: Desc, seconds: f64) -> Desc { d.mot.enter.motion.wait = seconds as f32; d }
fn offset(var d: Desc, x: f64, y: f64) -> Desc { d.mot.offset = float2 { x as f32, y as f32 }; d }
fn scale(var d: Desc, s: f64) -> Desc { d.mot.zoom = s as f32; d }
// Drawn turned about its center by `radians`, clockwise, with its subtree:
// a fanned hand of cards, an icon in a diamond. It is hit where it is
// drawn.
fn rotate(var d: Desc, radians: f64) -> Desc { d.mot.turn = radians as f32; d }
// Drawn slanted about its center, its verticals leaning right by `radians`
// (left if negative), with its subtree: a slanted panel.
fn skew(var d: Desc, radians: f64) -> Desc { d.mot.slant = radians as f32; d }

// The enter transitions: from transparent, from (dx, dy) away, from
// `from` times the size; and all of them together.
fn fade_in(m: Motion) -> Enter { Enter { alpha: 0.0, motion: m, .. } }
fn slide_in(dx: f64, dy: f64, m: Motion) -> Enter {
    Enter { alpha: 0.0, shift: float2 { dx as f32, dy as f32 }, motion: m, .. }
}
fn pop_in(from: f64, m: Motion) -> Enter { Enter { alpha: 0.0, zoom: from as f32, motion: m, .. } }
fn delay(var e: Enter, seconds: f64) -> Enter { e.motion.wait = seconds as f32; e }

// The exit transitions: to transparent, to (dx, dy) away, to `to` times the
// size; each fading too.
fn fade_out(m: Motion) -> Exit { Exit { alpha: 0.0, motion: m, .. } }
fn slide_out(dx: f64, dy: f64, m: Motion) -> Exit {
    Exit { alpha: 0.0, shift: float2 { dx as f32, dy as f32 }, motion: m, .. }
}
fn pop_out(to: f64, m: Motion) -> Exit { Exit { alpha: 0.0, zoom: to as f32, motion: m, .. } }
fn delay(var e: Exit, seconds: f64) -> Exit { e.motion.wait = seconds as f32; e }

// --- input setters --------------------------------------------------------------------

fn hit(var d: Desc) -> Desc { d.bits |= HIT; d }
fn focusable(var d: Desc) -> Desc { d.bits |= FOCUSABLE; d }
fn blocks(var d: Desc) -> Desc { d.bits |= BLOCKS; d }
// The pointer goes through this box and its subtree, though they have
// backgrounds, to what is under them (a game, for wants_pointer). What in
// it takes the pointer (a button, a hit() box, a scroll pane) and the
// parts of those still do, and so does what blocks().
fn passthrough(var d: Desc) -> Desc { d.bits |= PASSTHROUGH; d }
fn nav_skip(var d: Desc) -> Desc { d.bits |= NAV_SKIP; d }
fn keep(var d: Desc) -> Desc { d.bits |= KEEP; d }
fn disabled(var d: Desc, on: bool) -> Desc {
    if on { d.bits |= DISABLED; d.vis.state.disabled = true; }
    d
}
fn with_bits(var d: Desc, b: u32) -> Desc { d.bits |= b; d }
