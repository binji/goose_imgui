// The frame's tree: nodes recorded in order, each linked to its parent,
// first and last children and next sibling by index. A box is a node with
// children; text and images are leaves. Popups, modals and tooltips are
// roots of their own, laid out and drawn after the main one.
//
//   imgui::box("hud", imgui::row().gap(8).place(imgui::END, imgui::START)) {
//       imgui::image(heart, imgui::column().size(24, 24));
//       imgui::text(str("x ", lives));
//   };

namespace imgui;

import std;
import vec;
import dictionary;
import gfx;
import gfx2d;

let NODE_BOX = 0;
let NODE_TEXT = 1;
let NODE_IMAGE = 2;
let NODE_ICON = 3;
let NODE_RICH = 4;          // rich text: its pieces in `pieces`, text_len of them from text_off

struct Node {
    id: u64 = 0,
    parent: i32 = -1,
    first: i32 = -1,
    last: i32 = -1,
    next: i32 = -1,
    prev: i32 = -1,                     // the sibling before it, as recorded
    end: i32 = 0,                       // past its subtree in `nodes`, with any roots recorded inside it
    kids: i32 = 0,
    kind: u8 = 0,
    scoped: bool = false,               // pushed an ID scope
    named: bool = false,                // its ID came from the program, not its place
    ghost: u8 = 0,                      // a copy of what has left, playing its exit (GHOST_*)
    root: i16 = 0,
    d: Desc = Desc { .. },
    style: Style = Style { .. },        // its class's, mixed by its state, with the Desc's overrides
    // text
    text_off: i32 = 0,
    text_len: i32 = 0,
    natural: float2 = float2 { 0.0, 0.0 },  // text or image, unwrapped
    word: f32 = 0.0,                    // wrapped text's longest word
    // image
    image: gfx::Texture = gfx::Texture { 0 },
    src: gfx2d::Rect = gfx2d::Rect { 0.0, 0.0, 0.0, 0.0 },
    fit_mode: u8 = 1,                   // gfx2d::FIT_CONTAIN
    filter: i8 = -1,                    // gfx2d::FILTER_DEFAULT
    icon: u8 = 0,
    // layout
    fit: float2 = float2 { 0.0, 0.0 },  // the size it would like
    least: float2 = float2 { 0.0, 0.0 },    // the smallest it can be
    rect: gfx2d::Rect = gfx2d::Rect { 0.0, 0.0, 0.0, 0.0 },
    col: i16 = 0,                       // its grid cell
    row: i16 = 0,
    tracks: i32 = 0,                    // a grid's: where its column, then row, sizes start in `tracks`
    ncols: i16 = 0,
    nrows: i16 = 0,
    scroll: float2 = float2 { 0.0, 0.0 },   // its children moved this much up and left
    content: float2 = float2 { 0.0, 0.0 },  // how far its children reach, from its inner box
    // drawn
    shown: gfx2d::Rect = gfx2d::Rect { 0.0, 0.0, 0.0, 0.0 },  // its own box, where motion puts it
    shift: float2 = float2 { 0.0, 0.0 },    // its subtree moved this much
    zoom: f32 = 1.0,                    // and scaled about its center
    alpha: f32 = 1.0,
    m: gfx2d::Affine = gfx2d::Affine { 1.0, 0.0, 0.0, 1.0, 0.0, 0.0 },   // to the screen
    clip: gfx2d::Rect = gfx2d::Rect { 0.0, 0.0, 0.0, 0.0 },  // the screen clip it is drawn in
    screen: gfx2d::Rect = gfx2d::Rect { 0.0, 0.0, 0.0, 0.0 },    // its box on the screen
    bounds: gfx2d::Rect = gfx2d::Rect { 0.0, 0.0, 0.0, 0.0 },    // what it and its subtree draw on, on the screen
    ring: bool = false,                 // its focus ring shows
    scope: u64 = 0,                     // its nav scope
    owner: i32 = -1,                    // the nearest node at or above it that takes the pointer
    look: i32 = 0,                      // its text look, in node_looks
    pass: bool = false,                 // it or a box above it is passthrough()
    // a canvas's commands: where in draw_cmds, how many, the box they reach
    cmd_first: i32 = 0,
    cmd_end: i32 = 0,
    cmd_count: i32 = 0,
    cmd_lo: float2 = float2 { 0.0, 0.0 },
    cmd_hi: float2 = float2 { 0.0, 0.0 },
}

// A popup's root: where it goes is its anchor.
let ROOT_MAIN = 0;
let ROOT_POPUP = 1;
let ROOT_MODAL = 2;
let ROOT_TOOLTIP = 3;
let ROOT_WINDOW = 4;            // a window: over the main tree, under popups, in the windows' order

let ANCHOR_VIEWPORT = 0;        // the whole viewport (the main root, a modal's backdrop)
let ANCHOR_POINT = 1;           // its top left at `at`
let ANCHOR_BELOW = 2;           // under `rect`, left edges lined up
let ANCHOR_RIGHT = 3;           // right of `rect`, top edges lined up
let ANCHOR_CENTER = 4;          // centered in the viewport

struct Anchor { kind: u8 = 0, at: float2 = float2 { 0.0, 0.0 },
                rect: gfx2d::Rect = gfx2d::Rect { 0.0, 0.0, 0.0, 0.0 }, node: i32 = -1 }

// `after`: a widget its focusable widgets follow in Tab order, if it is
// focusable (a docked window's, its tab); 0: in draw order.
struct Root { node: i32 = 0, kind: u8 = 0, popup: u64 = 0, anchor: Anchor = Anchor { .. }, level: i32 = 0, after: u64 = 0 }

var nodes: Node[>..] = [];
var text_arena: u8[>..] = [];
var tracks: f32[>..] = [];
var parents: i32[>..<] = [];
var roots: Root[>..<] = [];
// The roots in the order they are drawn and hit: the main one, the windows
// back to front, then the rest as recorded. Made after layout.
var root_order: i32[>..<] = [];
var node_of = dictionary<u64, i32> {};     // this frame's named nodes
// What text inherits: the nearest ink, font and size up the tree, and its
// text look: where in `node_looks` the letter spacing, outline and shadow
// it gets are (0: none).
struct Inherited { ink: gfx2d::Color, font: gfx2d::Font, size: f32, look: i32 = 0 }
// The text looks this frame's nodes have, each from its style's and Desc's
// over its parent's. A node keeps its parent's unless it changes it, so
// this holds only what changes.
var node_looks: TextLook[>..<] = [];

// The look a node with style s and Desc look v has under a parent's `up`.
fn resolve_look(s: Style, v: LookDesc, up: i32) -> i32 {
    let fx_ov = v.ov & (OV_LETTER_SPACING | OV_TEXT_OUTLINE | OV_TEXT_SHADOW | OV_TEXT_GLOW | OV_REVEAL |
                         OV_TEXT_FX);
    if s.text_look == 0 && fx_ov == 0 && node_looks[up as i64].reveal < 0.0 { return up; }
    var l = node_looks[up as i64];
    l.reveal = -1.0;
    if s.text_look != 0 { l = over_look(text_look_of(s.text_look), l); }
    if fx_ov != 0 {
        let d = desc_fx(v);
        if v.ov & OV_LETTER_SPACING != 0 { l.letter_spacing = d.letter_spacing; }
        if v.ov & OV_TEXT_OUTLINE != 0 { l.outline = d.outline; l.outline_color = d.outline_color; }
        if v.ov & OV_TEXT_SHADOW != 0 { l.shadow = d.shadow; l.shadow_offset = d.shadow_offset; l.shadow_soft = d.shadow_soft; }
        if v.ov & OV_TEXT_GLOW != 0 { l.glow = d.glow; l.glow_color = d.glow_color; }
        if v.ov & OV_REVEAL != 0 { l.reveal = d.reveal; }
        if v.ov & OV_TEXT_FX != 0 { l.text_fx = d.text_fx; l.fx_args = d.fx_args; }
    }
    node_looks.push(l);
    (node_looks.len - 1) as i32
}
fn look_of(n: Node&) -> TextLook { node_looks[n.look as i64] }
var inherited: Inherited[>..<] = [];

fn begin_tree() {
    nodes.clear();
    text_arena.clear();
    pieces.clear();
    glyphs.clear();
    tracks.clear();
    parents.clear();
    roots.clear();
    node_of.clear();
    inherited.clear();
    frame_fx.clear();
    frame_exits.clear();
    frame_filters.clear();
    node_filters.clear();
    node_looks.clear();
    node_looks.push(TextLook { .. });
    let base = resolve_style(LABEL, LookState { .. });
    inherited.push(Inherited { base.ink, if base.font.id != 0 { base.font } else { gfx2d::default_font() },
                               if base.text_size > 0.0 { base.text_size } else { 16.0 },
                               resolve_look(base, LookDesc { .. }, 0) });
    open_root(ROOT_MAIN, 0, Anchor { kind: ANCHOR_VIEWPORT, rect: viewport, .. }, stack());
}

fn end_tree() {
    if parents.len != 1 { misuse(str("end_frame: ", parents.len - 1, " boxes still open")); }
    parents.clear();
}

fn top_parent() -> i32 { if parents.len > 0 { parents[parents.len - 1] } else { -1 } }

// A root, open: what is recorded until close_root goes in it.
fn open_root(kind: i64, popup: u64, a: Anchor, d: Desc) -> i32 {
    let i = nodes.len as i32;
    let rid = if popup != 0 { popup } else { ROOT_ID };
    let st = apply_overrides(resolve_style(d.vis.class, d.vis.state), d.vis, d.lay);
    var nd = d;
    nd.lay.padding = st.padding;
    nd.vis = node_filter(nd.vis);
    let look = resolve_look(st, d.vis, inherited[inherited.len - 1].look);
    nodes.push(Node { id: rid, end: i + 1, kind: NODE_BOX, root: roots.len as i16, d: nd, style: st, look: look, .. });
    roots.push(Root { node: i, kind: kind as u8, popup: popup, anchor: a, level: popup_level(popup) });
    parents.push(i);
    push_inherited(st, look);
    i
}
fn close_root() { close_node(); }

fn push_inherited(s: Style, look: i32) {
    let up = inherited[inherited.len - 1];
    inherited.push(Inherited { if s.ink.a > 0.0 { s.ink } else { up.ink },
                               if s.font.id != 0 { s.font } else { up.font },
                               if s.text_size > 0.0 { s.text_size } else { up.size }, look });
}

// A node, linked under the open parent. `id` 0 is keyed by its place.
fn add_node(kind: i64, id: u64, var d: Desc) -> i32 {
    if !in_frame { misuse("recording outside a frame"); }
    let p = top_parent();
    if p < 0 { misuse("no open box"); return -1; }
    let named = id != 0;
    let nid = if named { id } else { hash_combine(nodes[p].id, nodes[p].kids as u64 + 0x2545F491) };
    // Interactive nodes find their state first: the look depends on it.
    if d.bits & (HIT | FOCUSABLE) != 0 {
        let it = interaction_for(nid, d);
        d.vis.state = merge_state(d.vis.state, it);
    }
    var st = apply_overrides(resolve_style(d.vis.class, d.vis.state), d.vis, d.lay);
    d.lay.padding = st.padding;
    if d.lay.spacing == float2_0 && st.gap > 0.0 { d.lay.spacing = float2 { st.gap, st.gap }; }
    // A style's minimum size, unless the Desc gives one in pixels.
    if d.dim.w.kind != SIZE_PX { d.dim.w.lo = max(d.dim.w.lo, st.min_size.x); }
    if d.dim.h.kind != SIZE_PX { d.dim.h.lo = max(d.dim.h.lo, st.min_size.y); }
    let up = inherited[inherited.len - 1];
    if st.ink.a <= 0.0 { st.ink = up.ink; }
    if st.font.id == 0 { st.font = up.font; }
    if st.text_size <= 0.0 { st.text_size = up.size; }
    let i = nodes.len as i32;
    d.vis = node_filter(d.vis);
    nodes.push(Node { id: nid, parent: p, prev: nodes[p].last, end: i + 1, kind: kind as u8, named: named, root: nodes[p].root, d: d,
                      style: st, scope: current_scope(), look: resolve_look(st, d.vis, up.look), .. });
    let last = nodes[p].last;
    if last >= 0 { nodes[last].next = i; } else { nodes[p].first = i; }
    nodes[p].last = i;
    nodes[p].kids += 1;
    if named {
        if node_of.contains(nid) && d.bits & (HIT | FOCUSABLE) != 0 {
            write_stderr(str("imgui: two widgets have the same ID; give one a ##suffix or an id_scope\n"));
        }
        node_of.insert(nid, i);
    }
    i
}

// The open box's children from here on go in node i.
fn push_parent(i: i32, scoped: bool) {
    parents.push(i);
    if scoped { id_stack.push(nodes[i].id); nodes[i].scoped = true; }
    push_inherited(nodes[i].style, nodes[i].look);
}

fn close_node() {
    if parents.len <= 1 && roots.len <= 1 { misuse("close: nothing open"); return; }
    let i = parents.pop();
    nodes[i].end = nodes.len as i32;
    inherited.pop();
    if nodes[i].scoped { id_stack.pop(); }
}

fn open_box(id: u64, d: Desc) -> Interaction {
    let i = add_node(NODE_BOX, id, d);
    if i < 0 { return Interaction { .. }; }
    push_parent(i, id != 0);
    interaction_of(i)
}

// --- boxes ----------------------------------------------------------------------------

// A box, its children recorded by the block. The result is the box's
// interaction (if it is hit() or focusable()), as of this frame's input.
fn box<F>(d: Desc) -> Interaction {
    let it = open_box(0, d);
    defer close_node();
    F();
    it
}
fn box<F>(label: const u8[:], d: Desc) -> Interaction {
    let it = open_box(id(label).v, d);
    defer close_node();
    F();
    it
}
fn box<F>(key: i64, d: Desc) -> Interaction {
    let it = open_box(id(key).v, d);
    defer close_node();
    F();
    it
}
fn box<F>(i: Id, d: Desc) -> Interaction {
    let it = open_box(i.v, d);
    defer close_node();
    F();
    it
}
// A box with no children.
fn panel(d: Desc) -> Interaction {
    let i = add_node(NODE_BOX, 0, d);
    if i < 0 { return Interaction { .. }; }
    interaction_of(i)
}
fn panel(i: Id, d: Desc) -> Interaction {
    let n = add_node(NODE_BOX, i.v, d);
    if n < 0 { return Interaction { .. }; }
    interaction_of(n)
}
// Empty space: grows along its parent's main axis by default.
fn spacer() { add_node(NODE_BOX, 0, column().grow()); }
fn spacer(d: Desc) { add_node(NODE_BOX, 0, d); }

// --- text ---------------------------------------------------------------------------------

fn text_style_of(n: Node&) -> gfx2d::TextStyle {
    gfx2d::TextStyle { font: n.style.font, size: n.style.text_size, letter_spacing: look_of(n).letter_spacing, .. }
}

// Text, in the inherited ink, font and size, or its Desc's. A text's
// Desc can wrap() it at its width, justify() its lines, and size it like
// any box.
fn text(s: const u8[:], d: Desc) {
    let i = record_text(s, d);
    if i >= 0 && look_of(nodes[i]).text_fx != 0 {
        text_glyphs_of(i, s);
        run_glyphs(i) { g => standard_fx(g); };
    }
}
// Text with effects of the program's own: the block run for each
// character, with a Glyph to change (textfx.goose).
//   imgui::text("Wobbly", d) { g => g.turn = sin(g.time * 6.0 + g.index) * 0.2; };
fn text<F>(s: const u8[:], d: Desc) {
    let i = record_text(s, d);
    if i < 0 { return; }
    text_glyphs_of(i, s);
    run_glyphs(i) { g => F(g); };
}
fn record_text(s: const u8[:], d: Desc) -> i32 {
    let i = add_node(NODE_TEXT, 0, d);
    if i < 0 { return -1; }
    let n .= nodes[i];
    n.text_off = text_arena.len as i32;
    text_arena.append(s);
    n.text_len = s.len as i32;
    let style = text_style_of(n);
    n.natural = gfx2d::measure_text(s, style);
    if d.lay.wrap {
        var w: f32 = 0.0;
        var at = 0;
        while at < s.len {
            while at < s.len && (s[at] == ' ' || s[at] == '\n') { at++; }
            var end = at;
            while end < s.len && s[end] != ' ' && s[end] != '\n' { end++; }
            if end > at { w = max(w, gfx2d::measure_text(s[at..end], style).x); }
            at = end;
        }
        n.word = w;
    }
    i
}
fn text(s: const u8[:]) { text(s, column()); }
fn text(s: const u8[:], c: StyleClass) { text(s, column().skin(c)); }

// Text built by the block, straight into the frame's text: no str() first.
//   imgui::textf(imgui::column()) { out => format(out, "Score ", score); };
fn textf<F>(d: Desc) {
    let start = text_arena.len;
    F(&text_arena);
    let len = text_arena.len - start;
    let i = add_node(NODE_TEXT, 0, d);
    if i < 0 { return; }
    let n .= nodes[i];
    n.text_off = start as i32;
    n.text_len = len as i32;
    n.natural = gfx2d::measure_text(text_arena[start..start + len], text_style_of(n));
}

// The characters in s: its UTF-8 sequences, as reveal() counts them.
fn text_chars(s: const u8[:]) -> i64 {
    var c = 0;
    for b in s { if b & 0xC0 != 0x80 { c++; } }
    c
}
// Where in s[from..to] its first `chars` characters end.
fn chars_end(s: const u8[:], from: i64, to: i64, chars: i64) -> i64 {
    var left = chars;
    var k = from;
    while k < to {
        if s[k] & 0xC0 != 0x80 {
            if left == 0 { return k; }
            left--;
        }
        k++;
    }
    to
}

fn node_text(i: i32) -> const u8[:] {
    let n .= nodes[i];
    text_arena[n.text_off..n.text_off + n.text_len]
}

// --- images -------------------------------------------------------------------------------

// A texture, its whole size unless the Desc sizes it; fitted into its box
// by `fit_mode` (gfx2d::FIT_CONTAIN, COVER or STRETCH), sampled by `filter`
// (gfx2d::FILTER_LINEAR or NEAREST; FILTER_DEFAULT: nearest in pixel-art
// mode, else linear).
fn image(t: gfx::Texture, d: Desc, fit_mode: i64 = gfx2d::FIT_CONTAIN, filter: i64 = gfx2d::FILTER_DEFAULT) {
    let info = gfx::texture_info(t);
    image(t, gfx2d::rect_of(0, 0, info.width, info.height), d, fit_mode, filter);
}
// A part of one: a sprite from a sheet.
fn image(t: gfx::Texture, src: gfx2d::Rect, d: Desc, fit_mode: i64 = gfx2d::FIT_CONTAIN,
         filter: i64 = gfx2d::FILTER_DEFAULT) {
    let i = add_node(NODE_IMAGE, 0, d);
    if i < 0 { return; }
    let n .= nodes[i];
    n.image = t;
    n.src = src;
    n.natural = float2 { src.w, src.h };
    n.fit_mode = fit_mode as u8;
    n.filter = filter as i8;
}

// --- icons --------------------------------------------------------------------------------

// Small drawings in the ink, for widgets' parts (a check mark, the
// chevrons of dropdowns and submenus, a cross) and for icon buttons and
// toolbars (play, pause, stop, step; a menu's lines, a search, a refresh,
// a dot).
let ICON_CHECK = 1;
let ICON_CHEVRON_DOWN = 2;
let ICON_CHEVRON_RIGHT = 3;
let ICON_CHEVRON_LEFT = 4;
let ICON_CHEVRON_UP = 5;
let ICON_CLOSE = 6;
let ICON_PLUS = 7;
let ICON_MINUS = 8;
let ICON_PLAY = 9;
let ICON_PAUSE = 10;
let ICON_STOP = 11;
let ICON_STEP = 12;         // one step forward: a play triangle and a bar
let ICON_MENU = 13;         // three lines
let ICON_SEARCH = 14;
let ICON_REFRESH = 15;
let ICON_DOT = 16;

// An icon, as big as the text (or the Desc's size).
fn icon(kind: i64, d: Desc) {
    let i = add_node(NODE_ICON, 0, d);
    if i < 0 { return; }
    let n .= nodes[i];
    n.icon = kind as u8;
    let side = n.style.text_size * 0.75;
    n.natural = float2 { side, side };
}
fn icon(kind: i64) { icon(kind, column()); }
