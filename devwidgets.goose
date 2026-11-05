// Widgets for developers' tools: property rows, collapsing headers, tree
// nodes, and number fields that are dragged or typed in.
//
//   imgui::collapsing("Transform", imgui::column(), true) {
//       imgui::properties() {
//           imgui::property("Position") { imgui::drag_vec("", pos); };
//           imgui::property("Speed") { imgui::drag_number("", speed, imgui::Drag { lo: 0, hi: 10 }); };
//       };
//   };
//   let it = imgui::tree_node("World", selected == 0) { imgui::tree_leaf("Player", selected == 1); };

namespace imgui;

import std;
import vec;
import math;
import dictionary;
import gfx2d;

// --- properties ------------------------------------------------------------------------

// The widest property label in each window (or in the main tree), this
// frame's and last frame's: every properties() in a window has its labels'
// column at least as wide as last frame's, so their widgets line up.
struct LabelWidth { last: f32 = 0.0, now: f32 = 0.0, frame: i64 = -1 }
var label_widths = dictionary<u64, LabelWidth> {};

// The window (or root) being recorded, by its ID.
fn root_key() -> u64 {
    let p = top_parent();
    if p < 0 { return 0; }
    let r = roots[nodes[p].root as i64];
    if r.popup != 0 { r.popup } else { ROOT_ID }
}
fn label_width(key: u64) -> LabelWidth {
    var w = LabelWidth { .. };
    let found = label_widths.get(key);
    if found { w = found; }
    if w.frame != frame_index {
        if w.frame >= 0 { w.last = w.now; }
        w.now = 0.0;
        w.frame = frame_index;
        label_widths.insert(key, w);
    }
    w
}

// Rows of a label and its widget: a grid whose first column is as wide as
// the widest label in the window, the widgets sharing the rest.
fn properties<F>(d: Desc = column()) {
    let lw = label_width(root_key());
    var g = grid([between(fit(), lw.last, 1.0e30), grow()]).skin(PROPERTIES).grow_w();
    if d.lay.spacing != float2_0 { g.lay.spacing = d.lay.spacing; }
    box(g) { F(); };
}

// A property: its label, and its widget (the block) as wide as the rest of
// the row. The block's IDs are under the label's, so its widgets can be
// labelled "" (or "##x") without clashing with the next row's. Outside
// properties(), a row of its own.
fn property<F>(label: const u8[:]) {
    let p = top_parent();
    let in_grid = p >= 0 && nodes[p].d.lay.kind == GRID;
    if in_grid {
        // In a column, centered down its cell but at its left.
        box(column().justify(CENTER)) { text(label_text(label), column().skin(PROPERTY_LABEL)); };
        let key = root_key();
        var lw = label_width(key);
        lw.now = max(lw.now, nodes[nodes.len - 1].natural.x);
        label_widths.insert(key, lw);
        // Stretched across its cell, the widget centered down it.
        box(label, column().align(STRETCH).justify(CENTER)) { F(); };
    } else {
        box(row().align(CENTER).grow_w().gap(class_style(PROPERTIES).normal.gap)) {
            text(label_text(label), column().skin(PROPERTY_LABEL));
            box(label, column().align(STRETCH).grow_w()) { F(); };
        };
    }
}

// --- collapsing headers and trees ------------------------------------------------------

// Whether each header and tree node is open: kept as long as the program
// runs (1 open, 2 closed), not dropped with its widget's state, so a node
// inside a closed one keeps its own.
var opened = dictionary<u64, u8> {};

fn open_state(id: u64, at_first: bool) -> bool {
    let o = opened.get(id);
    if o { return o == 1; }
    at_first
}
fn set_open(i: Id, on: bool) { opened.insert(i.v, if on { 1 } else { 2 }); }
// Whether the header or tree node `label` (in the scope it is recorded in)
// is open; opened or closed by the program.
fn is_open_node(label: const u8[:]) -> bool { open_state(id(label).v, false) }
fn set_open(label: const u8[:], on: bool) { set_open(id(label), on); }

// A header that opens and closes what follows it, recorded by the block
// while it is open: clicked, or Right and Left while it has the focus.
// True while open.
fn collapsing<F>(label: const u8[:], d: Desc = column(), open_at_first: bool = false) -> bool {
    let i = id(label);
    let hd = clickable(row().skin(HEADER).grow_w().align(CENTER).with_bits(CAPTURE_X));
    let it = interact(i, hd);
    var open = open_state(i.v, open_at_first);
    if it.activated { open = !open; }
    if it.nav.x != 0 { open = it.nav.x > 0; }
    set_open(i, open);
    box(i, hd) {
        icon(if open { ICON_CHEVRON_DOWN } else { ICON_CHEVRON_RIGHT }, column().opacity(0.7));
        text(label_text(label), column().grow_w());
    };
    let t = open_amount(i, open);
    if t > 0.0 {
        var bd = d.grow_w();
        if bd.lay.spacing == float2_0 { bd = bd.gap(class_style(WINDOW_BODY).normal.gap); }
        let body = sub_id(i, "body");
        rolled(body, t) { box(body, bd) { F(); }; };
    }
    open
}

// How headers and tree nodes roll open and closed: INSTANT (the default)
// not at all; a tween or spring, what is under them rolling down from
// them and back up, cut off at its bottom edge, the rows below following.
var tree_roll = INSTANT;
fn set_tree_roll(m: Motion) { tree_roll = m; }

// How far open a header or tree node is, from 0 to 1.
fn open_amount(i: Id, open: bool) -> f32 {
    if is_instant(tree_roll) { return if open { 1.0 } else { 0.0 }; }
    let t = clamp(animate(sub_id(i, "roll"), if open { 1.0 } else { 0.0 }, tree_roll), 0.0, 1.0) as f32;
    if t < 0.0005 { 0.0 } else if t > 0.9995 { 1.0 } else { t }
}
// The block (a header's or node's content, as `body`), in a box as tall as
// `t` of it while it rolls: the box has no ID, so the content's IDs and
// state are as they are when it is still, and it lays the content out at
// its whole height, which it reads the next frame.
fn rolled<F>(body: Id, t: f32) {
    if t >= 1.0 {
        F();
        return;
    }
    box(column().grow_w().height(t * state_of(body.v).rect.h).clip().with_bits(OVERFLOW_Y)) { F(); };
}

// The tree nodes open around the one being recorded, for Left on a closed
// node to go up to its parent.
var tree_path: u64[>..<] = [];

// A tree node: an arrow and its label, its children (the block) under it,
// indented, while it is open. The arrow or a double click opens and closes
// it; Right opens it and Left closes it, or goes up to its parent. A click
// on the row is the program's to select it by: the result is the row's
// interaction (`activated`), for selection, tooltips and context menus.
fn tree_node<F>(label: const u8[:], selected: bool = false, open_at_first: bool = false) -> Interaction {
    let i = id(label);
    let arrow_id = sub_id(i, "arrow");
    let rd = clickable(row().skin(TREE_ROW).grow_w().align(CENTER).with_bits(CAPTURE_X)).look(checked_look(selected));
    let it = interact(i, rd);
    let ad = row().hit().center();
    let arrow = interact(arrow_id, ad);
    var open = open_state(i.v, open_at_first);
    if arrow.clicked || it.double_clicked { open = !open; }
    if it.nav.x > 0 { open = true; }
    if it.nav.x < 0 {
        if open { open = false; } else if tree_path.len > 0 { focus(Id { tree_path[tree_path.len - 1] }, true); scroll_into = focused; }
    }
    set_open(i, open);
    box(i, rd) {
        box(arrow_id, ad) { icon(if open { ICON_CHEVRON_DOWN } else { ICON_CHEVRON_RIGHT }, column().opacity(0.7)); };
        text(label_text(label));
    };
    let t = open_amount(i, open);
    if t > 0.0 {
        tree_path.push(i.v);
        defer tree_path.pop();
        let kids = sub_id(i, "children");
        rolled(kids, t) { box(kids, column().skin(TREE).grow_w()) { F(); }; };
    }
    it
}

// A tree node with no children: its row, lined up with its siblings'
// labels. Left goes up to its parent.
fn tree_leaf(label: const u8[:], selected: bool = false) -> Interaction {
    let i = id(label);
    let rd = clickable(row().skin(TREE_ROW).grow_w().align(CENTER).with_bits(CAPTURE_X)).look(checked_look(selected));
    let it = interact(i, rd);
    if it.nav.x < 0 && tree_path.len > 0 { focus(Id { tree_path[tree_path.len - 1] }, true); scroll_into = focused; }
    box(i, rd) {
        box(row().center()) { icon(ICON_CHEVRON_RIGHT, column().opacity(0.0)); };
        text(label_text(label));
    };
    it
}

// --- number fields -----------------------------------------------------------------------

// How a number field moves and shows its value.
struct Drag {
    speed: f64 = 0.0,           // the value's change for each pixel dragged; 0: a 200th of the range,
                                // or 0.1 (0.2 for whole numbers) without one
    lo: f64 = -1.0e300,         // its range: clamped to it
    hi: f64 = 1.0e300,
    decimals: i64 = -1,         // shown, and kept to: -1, 3 (0 for whole numbers)
    step: f64 = 0.0,            // Left and Right, and the buttons of input_number; 0: 1 for whole
                                // numbers, else ten pixels' worth of dragging
}

// The field being typed in, and its text: one at a time.
var number_editing: u64 = 0;
var number_text: u8[..64] = [];

// Field `i` typed in from now on, starting from `s`, all of it selected.
fn start_typing(i: Id, s: const u8[:]) {
    number_editing = i.v;
    number_text.clear();
    for c in s { if number_text.len < number_text.cap { number_text.push(c); } }
    let edit_id = sub_id(i, "edit");
    var es = state_of(edit_id.v);
    es.caret = number_text.len as i32;
    es.anchor = 0;
    es.text_scroll = 0.0;
    put_state(edit_id.v, es);
    focus(edit_id, focus_visible);
}
// While field `i` is typed in: its text_input, `w` wide, recorded; true
// the frame what was typed is kept (Enter, or the focus gone elsewhere),
// in number_text. Escape stops it without keeping it.
fn typing(i: Id, d: Desc, w: f32) -> bool {
    let edit_id = sub_id(i, "edit");
    var ed = d.skin(INPUT).with_bits(CAPTURE_X);
    if w > 0.0 { ed = ed.width(w); }
    let e = text_input(edit_id, number_text, ed, 63);
    if input.nav.cancel {
        number_editing = 0;
        focus(i, focus_visible);
        return false;
    }
    guard e.submitted || focused != edit_id.v else { return false; }
    number_editing = 0;
    if e.submitted { focus(i, focus_visible); }
    true
}

// v written with `decimals` digits after the point.
fn format_fixed(out: u8[>..]&, v: f64, decimals: i64) {
    let d = clamp(decimals, 0, 12);
    var scale: f64 = 1.0;
    for k in d { scale *= 10.0; }
    let n = round(abs(v) * scale);
    if n >= 9.0e18 { format(out, v); return; }
    let whole = (n / scale) as! i64;
    let frac = (n - whole * scale) as! i64;
    if v < 0.0 && n > 0.0 { out.push('-'); }
    format(out, whole);
    if d > 0 {
        out.push('.');
        var digits: u8[..16] = [];
        var f = frac;
        for k in d { digits.push(('0' + f % 10) as u8); f /= 10; }
        var k = d - 1;
        while k >= 0 { out.push(digits[k]); k--; }
    }
}

// What a field's settings come to, for a value whole or not.
struct DragSpan { lo: f64, hi: f64, speed: f64, step: f64, decimals: i64 }
fn drag_span(o: Drag, whole: bool) -> DragSpan {
    let lo = min(o.lo, o.hi);
    let hi = max(o.lo, o.hi);
    let bounded = lo > -1.0e299 && hi < 1.0e299;
    let speed = if o.speed > 0.0 { o.speed } else if bounded { (hi - lo) / 200.0 } else if whole { 0.2 } else { 0.1 };
    let step = if o.step > 0.0 { o.step } else if whole { 1.0 } else { speed * 10.0 };
    let decimals = if o.decimals >= 0 { o.decimals } else if whole { 0 } else { 3 };
    DragSpan { lo, hi, speed, step, decimals }
}
fn kept_to(x: f64, s: DragSpan) -> f64 {
    var scale: f64 = 1.0;
    for k in clamp(s.decimals, 0, 12) { scale *= 10.0; }
    clamp(round(x * scale) / scale, s.lo, s.hi)
}

// The colors of a vector's parts' tags: X, Y, Z, W.
fn axis_color(k: i64) -> gfx2d::Color {
    match k {
        0 => gfx2d::rgb(0xE5534B),
        1 => gfx2d::rgb(0x57AB5A),
        2 => gfx2d::rgb(0x539BF5),
        _ => gfx2d::rgb(0xC69026),
    }
}

// A number field: dragged sideways to change its value (finer with Shift
// held, coarser with Alt), Left and Right by its step while focused; a
// click (or Enter) without a drag types in it, Enter or a click elsewhere
// keeping what was typed, Escape not. `tag` (0 to 3) shows X, Y, Z or W
// in its color before the value (4 to 7: R, G, B or A). True the frame
// the value changes.
fn number_field(i: Id, v: f64&, o: Drag, whole: bool, d: Desc, tag: i64) -> bool {
    let s = drag_span(o, whole);
    let start: f64 = v;
    var st = state_of(i.v);
    if number_editing == i.v {
        guard typing(i, d, st.rect.w) else { return false; }
        let x, ok = parse_flt(number_text[..]);
        if ok { v = if whole { clamp(round(x), s.lo, s.hi) } else { kept_to(x, s) }; }
        if v != start { ui_event(UI_CHANGE, i.v, NUMBER); }
        return v != start;
    }
    let fd = clickable(d.skin(NUMBER).with_bits(CAPTURE_X).align(CENTER).justify(CENTER));
    let it = interact(i, fd);
    var value = start;
    let x = input.pointer.pos.x;
    if it.pressed {
        st.num = start;
        st.open = false;            // not dragged yet
        st.text_scroll = x;         // the pointer, as of the last frame
    }
    if it.held && it.dragging {
        let k = if input.mods & MOD_SHIFT != 0 { 0.1 } else if input.mods & MOD_ALT != 0 { 10.0 } else { 1.0 };
        st.num = clamp(st.num + (x - st.text_scroll) * s.speed * k, s.lo, s.hi);
        value = if whole { round(st.num) } else { kept_to(st.num, s) };
        st.open = true;
    }
    if it.held { st.text_scroll = x; }
    if it.hovered || it.held { wanted_cursor = CURSOR_EW_RESIZE; }
    if it.nav.x != 0 {
        value = clamp(value + it.nav.x * s.step, s.lo, s.hi);
        value = if whole { round(value) } else { kept_to(value, s) };
    }
    if it.activated && !st.open {
        var t: u8[>..] = [];
        format_fixed(t, value, s.decimals);
        start_typing(i, t);
    }
    put_state(i.v, st);
    v = value;
    let changed = value != start;
    if changed { ui_event(UI_CHANGE, i.v, NUMBER); }
    box(i, fd) {
        if tag >= 0 {
            text(match tag { 0 => "X", 1 => "Y", 2 => "Z", 3 => "W", 4 => "R", 5 => "G", 6 => "B", _ => "A" },
                 column().ink(axis_color(tag % 4)));
        }
        textf(column()) { out => format_fixed(out, value, s.decimals); };
    };
    changed
}

// A label before a field, as a slider has, if it shows one.
fn labelled<F>(label: const u8[:], d: Desc) {
    let shown = label_text(label);
    if shown.len == 0 {
        F();
        return;
    }
    box(d.align(CENTER).gap(class_style(PROPERTIES).normal.gap)) {
        text(shown);
        F();
    };
}

// A number dragged or typed in; see number_field.
fn drag_number(label: const u8[:], v: f64&, o: Drag = Drag { .. }, d: Desc = row()) -> bool {
    var changed = false;
    let fd = if label_text(label).len > 0 { row().grow_w() } else { d };
    labelled(label, d) { changed = number_field(id(label), v, o, false, fd, -1); };
    changed
}
fn drag_number(label: const u8[:], v: f32&, o: Drag = Drag { .. }, d: Desc = row()) -> bool {
    var x: f64 = v;
    let changed = drag_number(label, x, o, d);
    v = x as f32;
    changed
}
fn drag_number(label: const u8[:], v: i64&, o: Drag = Drag { .. }, d: Desc = row()) -> bool {
    var x: f64 = v;
    var changed = false;
    let fd = if label_text(label).len > 0 { row().grow_w() } else { d };
    labelled(label, d) { changed = number_field(id(label), x, o, true, fd, -1); };
    v = x as! i64;
    changed
}
fn drag_number(label: const u8[:], v: i32&, o: Drag = Drag { .. }, d: Desc = row()) -> bool {
    var x: i64 = v;
    let changed = drag_number(label, x, o, d);
    v = x as! i32;
    changed
}

// A number field between buttons that step it down and up.
fn input_number(label: const u8[:], v: f64&, o: Drag = Drag { .. }, d: Desc = row()) -> bool {
    input_number_of(label, v, o, d, false)
}
fn input_number(label: const u8[:], v: i64&, o: Drag = Drag { .. }, d: Desc = row()) -> bool {
    var x: f64 = v;
    let changed = input_number_of(label, x, o, d, true);
    v = x as! i64;
    changed
}
fn input_number(label: const u8[:], v: i32&, o: Drag = Drag { .. }, d: Desc = row()) -> bool {
    var x: f64 = v;
    let changed = input_number_of(label, x, o, d, true);
    v = x as! i32;
    changed
}
fn input_number_of(label: const u8[:], v: f64&, o: Drag, d: Desc, whole: bool) -> bool {
    let i = id(label);
    let s = drag_span(o, whole);
    let start: f64 = v;
    let bd = clickable(row().skin(BUTTON).center()).nav_skip();
    let gap = class_style(NUMBER).normal.gap;
    let rd = if label_text(label).len > 0 { row().grow_w() } else { d };
    labelled(label, d) {
        box(rd.align(CENTER).gap(gap)) {
            let less = box(sub_id(i, "less"), bd) { icon(ICON_MINUS); };
            if less.activated {
                v = clamp(v - s.step, s.lo, s.hi);
                v = if whole { round(v) } else { kept_to(v, s) };
            }
            number_field(i, v, o, whole, row().grow_w(), -1);
            let more = box(sub_id(i, "more"), bd) { icon(ICON_PLUS); };
            if more.activated {
                v = clamp(v + s.step, s.lo, s.hi);
                v = if whole { round(v) } else { kept_to(v, s) };
            }
        };
    };
    v != start
}

// A vector's parts, each a number field tagged X, Y, Z or W in its color.
fn drag_vec(label: const u8[:], v: float2&, o: Drag = Drag { .. }, d: Desc = row()) -> bool {
    var a: f64[4] = [v.x, v.y, 0.0, 0.0];
    let changed = drag_parts(label, a, 2, o, d);
    v = float2 { a[0] as f32, a[1] as f32 };
    changed
}
fn drag_vec(label: const u8[:], v: float3&, o: Drag = Drag { .. }, d: Desc = row()) -> bool {
    var a: f64[4] = [v.x, v.y, v.z, 0.0];
    let changed = drag_parts(label, a, 3, o, d);
    v = float3 { a[0] as f32, a[1] as f32, a[2] as f32 };
    changed
}
fn drag_vec(label: const u8[:], v: float4&, o: Drag = Drag { .. }, d: Desc = row()) -> bool {
    var a: f64[4] = [v.x, v.y, v.z, v.w];
    let changed = drag_parts(label, a, 4, o, d);
    v = float4 { a[0] as f32, a[1] as f32, a[2] as f32, a[3] as f32 };
    changed
}
fn drag_parts(label: const u8[:], a: f64[4]&, n: i64, o: Drag, d: Desc) -> bool {
    let i = id(label);
    var changed = false;
    let gap = class_style(NUMBER).normal.gap;
    let rd = if label_text(label).len > 0 { row().grow_w() } else { d };
    labelled(label, d) {
        box(rd.align(CENTER).gap(gap)) {
            for k in n {
                if number_field(sub_id(i, k), a[k], o, false, row().grow_w(), k) { changed = true; }
            }
        };
    };
    changed
}
