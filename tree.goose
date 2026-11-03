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

struct Node {
    id: u64 = 0,
    parent: i32 = -1,
    first: i32 = -1,
    last: i32 = -1,
    next: i32 = -1,
    kids: i32 = 0,
    kind: u8 = 0,
    scoped: bool = false,               // pushed an ID scope
    named: bool = false,                // its ID came from the program, not its place
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
    ring: bool = false,                 // its focus ring shows
    scope: u64 = 0,                     // its nav scope
}

// A popup's root: where it goes is its anchor.
let ROOT_MAIN = 0;
let ROOT_POPUP = 1;
let ROOT_MODAL = 2;
let ROOT_TOOLTIP = 3;

let ANCHOR_VIEWPORT = 0;        // the whole viewport (the main root, a modal's backdrop)
let ANCHOR_POINT = 1;           // its top left at `at`
let ANCHOR_BELOW = 2;           // under `rect`, left edges lined up
let ANCHOR_RIGHT = 3;           // right of `rect`, top edges lined up
let ANCHOR_CENTER = 4;          // centered in the viewport

struct Anchor { kind: u8 = 0, at: float2 = float2 { 0.0, 0.0 },
                rect: gfx2d::Rect = gfx2d::Rect { 0.0, 0.0, 0.0, 0.0 }, node: i32 = -1 }

struct Root { node: i32 = 0, kind: u8 = 0, popup: u64 = 0, anchor: Anchor = Anchor { .. }, level: i32 = 0 }

var nodes: Node[>..] = [];
var text_arena: u8[>..] = [];
var tracks: f32[>..] = [];
var parents: i32[>..<] = [];
var roots: Root[>..<] = [];
var node_of = dictionary<u64, i32> {};     // this frame's named nodes
// What text inherits: the nearest ink, font and size up the tree.
struct Inherited { ink: gfx2d::Color, font: gfx2d::Font, size: f32 }
var inherited: Inherited[>..<] = [];

fn begin_tree() {
    nodes.clear();
    text_arena.clear();
    tracks.clear();
    parents.clear();
    roots.clear();
    node_of.clear();
    inherited.clear();
    let base = resolve_style(LABEL, LookState { .. });
    inherited.push(Inherited { base.ink, if base.font.id != 0 { base.font } else { gfx2d::default_font() },
                               if base.text_size > 0.0 { base.text_size } else { 16.0 } });
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
    nodes.push(Node { id: rid, kind: NODE_BOX, root: roots.len as i16, d: nd, style: st, .. });
    roots.push(Root { node: i, kind: kind as u8, popup: popup, anchor: a, level: popup_level(popup) });
    parents.push(i);
    push_inherited(st);
    i
}
fn close_root() { close_node(); }

fn push_inherited(s: Style) {
    let up = inherited[inherited.len - 1];
    inherited.push(Inherited { if s.ink.a > 0.0 { s.ink } else { up.ink },
                               if s.font.id != 0 { s.font } else { up.font },
                               if s.text_size > 0.0 { s.text_size } else { up.size } });
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
    d.dim.w.lo = max(d.dim.w.lo, st.min_size.x);
    d.dim.h.lo = max(d.dim.h.lo, st.min_size.y);
    let up = inherited[inherited.len - 1];
    if st.ink.a <= 0.0 { st.ink = up.ink; }
    if st.font.id == 0 { st.font = up.font; }
    if st.text_size <= 0.0 { st.text_size = up.size; }
    let i = nodes.len as i32;
    nodes.push(Node { id: nid, parent: p, kind: kind as u8, named: named, root: nodes[p].root, d: d,
                      style: st, scope: current_scope(), .. });
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
    push_inherited(nodes[i].style);
}

fn close_node() {
    if parents.len <= 1 && roots.len <= 1 { misuse("close: nothing open"); return; }
    let i = parents.pop();
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
    gfx2d::TextStyle { font: n.style.font, size: n.style.text_size, .. }
}

// Text, in the inherited ink, font and size, or its Desc's. A text's
// Desc can wrap() it at its width, justify() its lines, and size it like
// any box.
fn text(s: const u8[:], d: Desc) {
    let i = add_node(NODE_TEXT, 0, d);
    if i < 0 { return; }
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
}
fn text(s: const u8[:]) { text(s, column()); }
fn text(s: const u8[:], c: StyleClass) { text(s, column().skin(c)); }

// Text built by the block, straight into the frame's text: no str() first.
//   imgui::textf(imgui::column()) { out => format(out, "Score ", score); };
fn textf<F>(d: Desc) {
    let start = text_arena.len;
    F(text_arena);
    let len = text_arena.len - start;
    let i = add_node(NODE_TEXT, 0, d);
    if i < 0 { return; }
    let n .= nodes[i];
    n.text_off = start as i32;
    n.text_len = len as i32;
    n.natural = gfx2d::measure_text(text_arena[start..start + len], text_style_of(n));
}

fn node_text(i: i32) -> const u8[:] {
    let n .= nodes[i];
    text_arena[n.text_off..n.text_off + n.text_len]
}

// --- images -------------------------------------------------------------------------------

// A texture, its whole size unless the Desc sizes it; fitted into its box
// by `fit_mode` (gfx2d::FIT_CONTAIN, COVER or STRETCH).
fn image(t: gfx::Texture, d: Desc, fit_mode: i64 = gfx2d::FIT_CONTAIN) {
    let info = gfx::texture_info(t);
    image(t, gfx2d::rect_of(0, 0, info.width, info.height), d, fit_mode);
}
// A part of one: a sprite from a sheet.
fn image(t: gfx::Texture, src: gfx2d::Rect, d: Desc, fit_mode: i64 = gfx2d::FIT_CONTAIN) {
    let i = add_node(NODE_IMAGE, 0, d);
    if i < 0 { return; }
    let n .= nodes[i];
    n.image = t;
    n.src = src;
    n.natural = float2 { src.w, src.h };
    n.fit_mode = fit_mode as u8;
}

// --- icons --------------------------------------------------------------------------------

// Small line drawings in the ink, for widgets' parts: a check mark, the
// chevrons of dropdowns and submenus, a cross.
let ICON_CHECK = 1;
let ICON_CHEVRON_DOWN = 2;
let ICON_CHEVRON_RIGHT = 3;
let ICON_CHEVRON_LEFT = 4;
let ICON_CHEVRON_UP = 5;
let ICON_CLOSE = 6;
let ICON_PLUS = 7;
let ICON_MINUS = 8;

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
