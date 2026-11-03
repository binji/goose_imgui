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

struct MotionDesc {
    enter: Enter = Enter { .. },        // played the first frame the node's ID is seen
    glide: Motion = Motion { .. },      // from where it was to where it is, when its layout moves
    offset: float2 = float2 { 0.0, 0.0 },   // drawn this far from its laid-out place
    zoom: f32 = 1.0,                    // and scaled about its center
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

struct Desc {
    lay: LayoutDesc = LayoutDesc { .. },
    dim: SizeDesc = SizeDesc { .. },
    vis: LookDesc = LookDesc { .. },
    mot: MotionDesc = MotionDesc { .. },
    bits: u32 = 0,
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
fn opacity(var d: Desc, o: f64) -> Desc { d.vis.opacity = o as f32; d }
fn clip(var d: Desc) -> Desc { d.vis.clips = true; d }
fn isolate(var d: Desc) -> Desc { d.vis.isolated = true; d }
fn look(var d: Desc, s: LookState) -> Desc { d.vis.state = s; d }

// --- motion setters -------------------------------------------------------------------

fn enter(var d: Desc, e: Enter) -> Desc { d.mot.enter = e; d }
fn glide(var d: Desc, m: Motion) -> Desc { d.mot.glide = m; d }
// The enter transition starts this much later: a list staggered by index.
fn delay(var d: Desc, seconds: f64) -> Desc { d.mot.enter.motion.wait = seconds as f32; d }
fn offset(var d: Desc, x: f64, y: f64) -> Desc { d.mot.offset = float2 { x as f32, y as f32 }; d }
fn scale(var d: Desc, s: f64) -> Desc { d.mot.zoom = s as f32; d }

// The enter transitions: from transparent, from (dx, dy) away, from
// `from` times the size; and all of them together.
fn fade_in(m: Motion) -> Enter { Enter { alpha: 0.0, motion: m, .. } }
fn slide_in(dx: f64, dy: f64, m: Motion) -> Enter {
    Enter { alpha: 0.0, shift: float2 { dx as f32, dy as f32 }, motion: m, .. }
}
fn pop_in(from: f64, m: Motion) -> Enter { Enter { alpha: 0.0, zoom: from as f32, motion: m, .. } }

// --- input setters --------------------------------------------------------------------

fn hit(var d: Desc) -> Desc { d.bits |= HIT; d }
fn focusable(var d: Desc) -> Desc { d.bits |= FOCUSABLE; d }
fn blocks(var d: Desc) -> Desc { d.bits |= BLOCKS; d }
fn nav_skip(var d: Desc) -> Desc { d.bits |= NAV_SKIP; d }
fn keep(var d: Desc) -> Desc { d.bits |= KEEP; d }
fn disabled(var d: Desc, on: bool) -> Desc {
    if on { d.bits |= DISABLED; d.vis.state.disabled = true; }
    d
}
fn with_bits(var d: Desc, b: u32) -> Desc { d.bits |= b; d }
