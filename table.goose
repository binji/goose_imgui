// Long lists and tables: rows recorded only while they are in view, rows
// selected as a desktop's lists select them, and tables of columns that are
// resized by their edges and sorted by their headers.
//
//   imgui::scroll("log", imgui::column().grow()) {
//       imgui::row_list("lines", lines.len, 18) { k => imgui::text(lines[k]); };
//   };
//   let t = imgui::table("entities", ["Name", "HP", "Team"], ents.len, chosen) { k, c => … };
//   if t.clicked >= 0 { imgui::select_row("entities", chosen, t.clicked); }
//   if t.sorted { sort_by(t.sort, t.descending); }

namespace imgui;

import std;
import vec;
import math;
import dictionary;
import gfx2d;

// --- rows in view -----------------------------------------------------------------------

// After layout: what part of row list i its clip showed (its own y, from
// its top), and the scroll offset of the pane it is in, then.
fn keep_row_view(i: i32, st: WidgetState&) {
    let n .= nodes[i];
    let k = if n.rect.h > 0.0 { n.screen.h / n.rect.h } else { 1.0 };
    let vp = gfx2d::Rect { viewport.x, viewport.y, viewport.w, viewport.h };
    let clip = gfx2d::intersect(n.clip, vp);
    st.view = float2 { (clip.y - n.screen.y) / k, (clip.y + clip.h - n.screen.y) / k };
    var q = n.parent;
    while q >= 0 && nodes[q].d.bits & SCROLLS_Y == 0 { q = nodes[q].parent; }
    st.scroll = if q >= 0 { nodes[q].scroll } else { float2_0 };
}

// The scroll pane being recorded into, nearest first: its ID, or 0.
fn enclosing_pane() -> u64 {
    var q = top_parent();
    while q >= 0 && nodes[q].d.bits & SCROLLS_Y == 0 { q = nodes[q].parent; }
    if q >= 0 { nodes[q].id } else { 0 }
}

// `count` rows, each `row_height` high (and `d`'s gap apart), of which
// only those in view are recorded: the block records row k. The list is
// as tall as all of them, so a scroll pane scrolls it as if they were all
// there. Each row's IDs are under its index.
fn row_list<F>(label: const u8[:], count: i64, row_height: f64, d: Desc = column()) -> i64, i64 {
    let i = id(label);
    let st = state_of(i.v);
    let gap = d.lay.spacing.y;
    let step = max(row_height + gap, 1.0);
    let total = max(count * step - gap, 0.0);
    var first: i64 = 0;
    var last: i64 = 0;
    if st.laid {
        // What showed last frame, moved by how far its pane has scrolled
        // since; a row more each way.
        let pane = enclosing_pane();
        let moved = if pane != 0 { state_of(pane).scroll.y - st.scroll.y } else { 0.0 };
        first = clamp(floor((st.view.x + moved) / step) as i64 - 1, 0, count);
        last = clamp(ceil((st.view.y + moved) / step) as i64 + 1, first, count);
    } else {
        last = min(count, ceil(viewport.h / step) as i64 + 1);
    }
    // Its rows are out of the flow: with no width of its own, as wide as
    // it can be, for them to have one.
    let ld = if d.dim.w.kind == SIZE_FIT { d.grow_w() } else { d };
    box(i, ld.height(total).with_bits(ROW_LIST)) {
        for k in first..last {
            box(k, row().absolute(0, k * step).width(pct(1)).height(row_height).align(CENTER)) { F(k); };
        }
    };
    return first, last;
}

// --- selecting rows -----------------------------------------------------------------------

// Each list's anchor: the row a Shift+click selects from.
var select_anchor = dictionary<u64, i64> {};
// A table's sort and its columns' widths (0: a share), by the table's and
// the headers' IDs: the player's choices, kept as a tree node's are, however
// long the table is hidden.
struct TableSort { column: i32 = -1, descending: bool = false }
var table_sorts = dictionary<u64, TableSort> {};
var column_widths = dictionary<u64, f32> {};

// Row k of list `list` clicked (or accepted): with no key held, it alone is
// selected; with Ctrl, it is selected or not, the rest as they were; with
// Shift, the rows from the last one clicked to it (with Ctrl too, added
// to the rest). `selected` is the program's: a bool for each row.
fn select_row<A>(list: Id, selected: A&, k: i64) {
    guard k >= 0 && k < selected.len;
    let ctrl = input.mods & MOD_CTRL != 0;
    let shift = input.mods & MOD_SHIFT != 0;
    let found = select_anchor.get(list.v);
    if shift && found {
        let anchor: i64 = found;
        let a = clamp(anchor, 0, selected.len - 1);
        if !ctrl { for j in selected.len { selected[j] = false; } }
        for j in min(a, k)..max(a, k) + 1 { selected[j] = true; }
        return;
    }
    if ctrl {
        selected[k] = !selected[k];
    } else {
        for j in selected.len { selected[j] = false; }
        selected[k] = true;
    }
    select_anchor.insert(list.v, k);
}
fn select_row<A>(list: const u8[:], selected: A&, k: i64) { select_row(id(list), selected, k); }

// --- tables -------------------------------------------------------------------------------

// How a table looks and acts.
struct Table {
    row_height: f32 = 0.0,      // 0: TABLE_ROW's min_size.y
    sortable: bool = true,      // its headers sort it when clicked
    least: f32 = 32.0,          // a column's least width
}

// What a table did this frame.
struct TableInfo {
    clicked: i64 = -1,          // the row clicked (or accepted), if any
    double_clicked: i64 = -1,
    hovered: i64 = -1,
    sort: i64 = -1,             // the column it is sorted by (-1: none), and which way
    descending: bool = false,
    sorted: bool = false,       // the sort changed this frame: sort the rows again
}

var no_selection: bool[0] = [];

// A table: a header of `headers`, and `count` rows of a cell for each,
// recorded by the block (row k, column c) only while in view, under the
// header, which stays as the rows scroll. Each column is as wide as it was
// dragged to be by its header's right edge, or a share of what the others
// leave. A click on a header sorts by it (again: the other way); the rows
// are the program's to sort, by `sort` and `descending`. Rows in
// `selected` (a bool for each row) are shown selected.
fn table<F>(label: const u8[:], headers: const u8[:][:], count: i64, t: Table = Table { .. }, d: Desc = column()) -> TableInfo {
    table_of(id(label), headers, count, no_selection, t, d) { k, c => F(k, c); }
}
fn table<F, A>(label: const u8[:], headers: const u8[:][:], count: i64, selected: const A&, t: Table = Table { .. },
               d: Desc = column()) -> TableInfo {
    table_of(id(label), headers, count, selected, t, d) { k, c => F(k, c); }
}

fn table_of<F, A>(i: Id, headers: const u8[:][:], count: i64, selected: const A&, t: Table, d: Desc) -> TableInfo {
    var info = TableInfo { .. };
    let st = state_of(i.v);
    let n = min(headers.len, 32);
    let sort = table_sorts.get(i.v);
    if sort {
        info.sort = sort.column as i64;
        info.descending = sort.descending;
    }
    let inner = max(st.rect.w - 2.0, 0.0);
    var widths: f32[32] = [0.0; 32];
    var fixed: f32 = 0.0;
    var shares = 0;
    for c in n {
        let w = column_widths.get(sub_id(i, c).v);
        if w && w > 0.0 { widths[c] = max(w, t.least); fixed += widths[c]; } else { shares++; }
    }
    let share = if shares > 0 { max((inner - fixed) / shares, t.least) } else { 0.0 };
    for c in n { if widths[c] <= 0.0 { widths[c] = if inner > 0.0 { share } else { 120.0 }; } }

    // The header: clicked, a column sorts; its right edge dragged, it resizes.
    let hd = clickable(row().skin(TABLE_HEAD).align(CENTER).clip()).nav_skip();
    let grip = class_style(RESIZE_GRIP).normal.min_size.x;
    for c in n {
        let hid = sub_id(i, c);
        let gid = sub_id(hid, "grip");
        let g = interact(gid, column().skin(RESIZE_GRIP).hit());
        if g.pressed { var hs = state_of(hid.v); hs.num = widths[c]; put_state(hid.v, hs); }
        if g.held {
            widths[c] = max(state_of(hid.v).num + g.drag.x, t.least) as f32;
            column_widths.insert(hid.v, widths[c]);
        }
        if g.hovered || g.held { wanted_cursor = CURSOR_EW_RESIZE; }
        if t.sortable && interact(hid, hd.width(widths[c]).look(checked_look(info.sort == c))).activated {
            if info.sort == c { info.descending = !info.descending; } else { info.sort = c; info.descending = false; }
            info.sorted = true;
            table_sorts.insert(i.v, TableSort { c as i32, info.descending });
        }
    }
    let row_h = if t.row_height > 0.0 { t.row_height } else { class_style(TABLE_ROW).normal.min_size.y };

    // Its columns don't make it wider: those past its edge are cut off.
    var td = d.skin(TABLE).clip().with_bits(OVERFLOW_X);
    if td.dim.w.kind == SIZE_FIT { td = td.grow_w(); }
    if td.dim.h.kind == SIZE_FIT { td = td.height(row_h * 8.0 + 34.0); }
    td.lay.kind = COLUMN;
    box(i, td) {
        // The header and the rows as wide as the table, whatever their columns.
        box(row().skin(TABLE_HEADER).width(pct(1))) {
            for c in n {
                let hid = sub_id(i, c);
                let on = info.sort == c;
                box(hid, hd.width(widths[c]).look(checked_look(on))) {
                    text(label_text(headers[c]), column().grow_w());
                    if on { icon(if info.descending { ICON_CHEVRON_DOWN } else { ICON_CHEVRON_UP }, column().opacity(0.7)); }
                };
            }
            // Each column's right edge, over the headers (not in one, whose
            // padding and clip would move it and cut it off).
            var x: f32 = 0.0;
            for c in n {
                x += widths[c];
                panel(sub_id(sub_id(i, c), "grip"), column().skin(RESIZE_GRIP).hit().absolute(x - grip * 0.5, 0)
                                                     .width(grip).height(pct(1)));
            }
        };
        scroll("rows", column().width(pct(1)).grow_h()) {
            row_list("list", count, row_h) { k =>
                let sel = k < selected.len && selected[k];
                let rd = clickable(row().skin(if k % 2 == 1 { TABLE_ROW_ALT } else { TABLE_ROW }).grow().align(CENTER))
                         .look(checked_look(sel));
                // Under the row's own scope (its index): an ID of its own.
                let it = box("row", rd) {
                    for c in n {
                        box(column().skin(TABLE_CELL).width(widths[c]).grow_h().justify(CENTER).clip()) { F(k, c); };
                    }
                };
                if it.activated { info.clicked = k; }
                if it.double_clicked { info.double_clicked = k; }
                if it.hovered { info.hovered = k; }
            };
        };
    };
    info
}
