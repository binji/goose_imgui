// Plots and colors, drawn on canvases: lines and bars of values (a rolling
// buffer of frame times, a histogram), a sparkline, and a color field that
// opens a picker.
//
//   imgui::push_sample(frame_ms, dt * 1000.0, 120);
//   imgui::plot_lines("frame time", frame_ms, imgui::Plot { lo: 0, hi: 33 });
//   imgui::color_edit("Tint", tint);

namespace imgui;

import std;
import vec;
import math;
import dictionary;
import gfx2d;

// --- plots ---------------------------------------------------------------------------------

// How a plot shows its values.
struct Plot {
    lo: f64 = 0.0,              // the range up the plot; lo == hi: fitted to the values
    hi: f64 = 0.0,
    offset: i64 = 0,            // where the first (oldest) value is, for a ring of them
    fill: bool = true,          // lines: the area under them too
    scale: bool = true,         // the range's ends written at the left
    readout: bool = true,       // under the pointer: a guide, and the value there
    decimals: i64 = 2,          // of the scale's and the readout's numbers
}

// v added at the end of buf, the oldest dropped past `keep` of them: a
// rolling buffer for plot_lines.
fn push_sample(buf: f64[>..]&, v: f64, keep: i64) {
    buf.push(v);
    let over = buf.len - max(keep, 1);
    if over > 0 {
        for k in 0..buf.len - over { buf[k] = buf[k + over]; }
        for k in over { buf.pop(); }
    }
}
fn push_sample(buf: f32[>..]&, v: f64, keep: i64) {
    buf.push(v as f32);
    let over = buf.len - max(keep, 1);
    if over > 0 {
        for k in 0..buf.len - over { buf[k] = buf[k + over]; }
        for k in over { buf.pop(); }
    }
}

// f32 values as f64, for the plots to share their code.
var plot_values: f64[>..<] = [];
fn as_f64(values: const f32[:]) -> const f64[:] {
    plot_values.clear();
    for v in values { plot_values.push(v as f64); }
    plot_values[..]
}

// The range a plot shows: p's, or the values' own; never empty.
fn plot_range(values: const f64[:], p: Plot) -> f64, f64 {
    var lo = p.lo;
    var hi = p.hi;
    if lo == hi {
        lo = 1.0e300;
        hi = -1.0e300;
        for v in values { lo = min(lo, v); hi = max(hi, v); }
        if values.len == 0 { lo = 0.0; hi = 1.0; }
    }
    if hi - lo < 1.0e-9 { lo -= 0.5; hi += 0.5; }
    return lo, hi;
}

// The value at k, in a ring that starts at `offset`.
fn ring_at(values: const f64[:], offset: i64, k: i64) -> f64 {
    let n = values.len;
    values[((offset % n + n) % n + k) % n]
}

// A plot's Desc: a frame, hit for its readout; 64 high and at least 120
// wide unless `d` says.
fn plot_desc(d: Desc) -> Desc {
    var pd = d.skin(PLOT).hit().clip();
    if pd.dim.w.kind == SIZE_FIT { pd = pd.grow_w().min_w(120); }
    if pd.dim.h.kind == SIZE_FIT { pd = pd.height(64); }
    pd
}

// The scale's ends at the left, and under the pointer the value at `k`,
// its guide at x.
fn plot_marks(size: float2, lo: f64, hi: f64, p: Plot, k: i64, x: f64, v: f64, y: f64) {
    let st = class_style(PLOT).normal;
    let ts = st.text_size;
    let ink = st.ink;
    if p.scale {
        var t: u8[>..] = [];
        format_fixed(t, hi, p.decimals);
        draw_text(0, 0, t, ts, ink, gfx2d::ALIGN_LEFT, gfx2d::BASELINE_TOP);
        t.clear();
        format_fixed(t, lo, p.decimals);
        draw_text(0, size.y, t, ts, ink, gfx2d::ALIGN_LEFT, gfx2d::BASELINE_BOTTOM);
    }
    if k >= 0 {
        draw_line(x, 0, x, size.y, 1, gfx2d::with_alpha(ink, 0.6));
        var t: u8[>..] = [];
        format(t, k, ": ");
        format_fixed(t, v, p.decimals);
        let w = measure(t, ts).x + 8.0;
        let left = x + 6.0 + w > size.x;
        let tx = if left { x - 6.0 - w } else { x + 6.0 };
        let ty = clamp(y - ts, 0.0, max(size.y - ts * 1.4, 0.0));
        fill_rect(tx, ty, w, ts * 1.4, 3, gfx2d::with_alpha(class_style(WINDOW).normal.bg, 0.9));
        draw_text(tx + 4.0, ty + ts * 0.2, t, ts, class_style(LABEL).normal.ink, gfx2d::ALIGN_LEFT, gfx2d::BASELINE_TOP);
    }
}

// Lines through the values, oldest at the left (from p.offset in a ring),
// the area under them filled; the value under the pointer read out.
// Returns its interaction, for a tooltip or a click.
fn plot_lines(label: const u8[:], values: const f64[:], p: Plot = Plot { .. }, d: Desc = column()) -> Interaction {
    let i = id(label);
    let pd = plot_desc(d);
    let it = interact(i, pd);
    let lo, hi = plot_range(values, p);
    let n = values.len;
    let line = class_style(PLOT_LINE).normal;
    let ps = class_style(PLOT).normal.padding;
    var result = it;
    labelled(label, row().grow_w()) {
        result = canvas(i, pd) { size =>
            guard n > 0;
            fn px(k: i64) -> f64 { if n > 1 { k * size.x / (n - 1) } else { size.x * 0.5 } }
            fn py(v: f64) -> f64 { size.y - clamp((v - lo) / (hi - lo), 0.0, 1.0) * size.y }
            var pts: float2[>..] = [];
            for k in n { pts.push(f2(px(k), py(ring_at(values, p.offset, k)))); }
            if p.fill && n > 1 {
                var area: float2[>..] = [];
                area.push(f2(0, size.y));
                for q in pts { area.push(q); }
                area.push(f2(px(n - 1), size.y));
                fill_polygon(area, gfx2d::with_alpha(line.bg, 0.2));
            }
            if n > 1 { stroke_polyline(pts, max(line.min_size.x, 1.0), line.bg); }
            var k = -1;
            if p.readout && it.hovered && size.x > 0.0 {
                let x = it.pointer.x * (state_of(i.v).rect.w / max(it.rect.w, 0.0001)) - ps.x;
                k = clamp(round(x / size.x * (n - 1)) as i64, 0, n - 1);
            }
            let v = if k >= 0 { ring_at(values, p.offset, k) } else { 0.0 };
            if k >= 0 { fill_circle(px(k), py(v), 3, line.bg); }
            plot_marks(size, lo, hi, p, k, px(k), v, py(v));
        };
    };
    result
}
fn plot_lines(label: const u8[:], values: const f32[:], p: Plot = Plot { .. }, d: Desc = column()) -> Interaction {
    plot_lines(label, as_f64(values), p, d)
}

// A bar for each value, from zero (or the range's end nearest it); the bar
// under the pointer lit and read out.
fn plot_bars(label: const u8[:], values: const f64[:], p: Plot = Plot { .. }, d: Desc = column()) -> Interaction {
    let i = id(label);
    let pd = plot_desc(d);
    let it = interact(i, pd);
    let lo0, hi0 = plot_range(values, p);
    let lo = if p.lo == p.hi { min(lo0, 0.0) } else { lo0 };
    let hi = if p.lo == p.hi { max(hi0, 0.0) } else { hi0 };
    let n = values.len;
    let bar = class_style(PLOT_BAR);
    let ps = class_style(PLOT).normal.padding;
    var result = it;
    labelled(label, row().grow_w()) {
        result = canvas(i, pd) { size =>
            guard n > 0;
            fn py(v: f64) -> f64 { size.y - clamp((v - lo) / (hi - lo), 0.0, 1.0) * size.y }
            let w = size.x / n;
            let gap = if w > 4.0 { max(1.0, w * 0.15) } else { 0.0 };
            let base = py(clamp(0.0, lo, hi));
            var k = -1;
            if p.readout && it.hovered && size.x > 0.0 {
                let x = it.pointer.x * (state_of(i.v).rect.w / max(it.rect.w, 0.0001)) - ps.x;
                k = clamp(floor(x / w) as i64, 0, n - 1);
            }
            for j in n {
                let y = py(ring_at(values, p.offset, j));
                fill_rect(j * w + gap * 0.5, min(y, base), max(w - gap, 1.0), max(abs(base - y), 1.0),
                          if j == k { bar.hover.bg } else { bar.normal.bg });
            }
            let v = if k >= 0 { ring_at(values, p.offset, k) } else { 0.0 };
            plot_marks(size, lo, hi, p, k, (k + 0.5) * w, v, py(v));
        };
    };
    result
}
fn plot_bars(label: const u8[:], values: const f32[:], p: Plot = Plot { .. }, d: Desc = column()) -> Interaction {
    plot_bars(label, as_f64(values), p, d)
}

// A small line, no frame, scale or readout: for a row of stats.
fn sparkline(label: const u8[:], values: const f64[:], d: Desc = column()) {
    let i = id(label);
    var sd = d;
    if sd.dim.w.kind == SIZE_FIT { sd = sd.width(80); }
    if sd.dim.h.kind == SIZE_FIT { sd = sd.height(class_style(LABEL).normal.text_size); }
    let lo, hi = plot_range(values, Plot { .. });
    let n = values.len;
    let line = class_style(PLOT_LINE).normal;
    canvas(i, sd) { size =>
        guard n > 1;
        var pts: float2[>..] = [];
        for k in n {
            pts.push(f2(k * size.x / (n - 1), size.y - (values[k] - lo) / (hi - lo) * size.y));
        }
        stroke_polyline(pts, max(line.min_size.x, 1.0), line.bg);
    };
}
fn sparkline(label: const u8[:], values: const f32[:], d: Desc = column()) { sparkline(label, as_f64(values), d); }

// --- colors ----------------------------------------------------------------------------------

// A checkerboard, behind a color that is see-through.
fn checker(x: f64, y: f64, w: f64, h: f64, cell: f64) {
    fill_rect(x, y, w, h, gfx2d::rgb(0xCCCCCC));
    let dark = gfx2d::rgb(0x999999);
    var r = 0;
    var cy = y;
    while cy < y + h {
        var c = if r % 2 == 0 { 0 } else { 1 };
        var cx = x;
        while cx < x + w {
            if c % 2 == 1 { fill_rect(cx, cy, min(cell, x + w - cx), min(cell, y + h - cy), dark); }
            c++;
            cx += cell;
        }
        r++;
        cy += cell;
    }
}

// A swatch of c: its color over a checkerboard, as wide as it is tall
// unless `d` says. Clicked, it is activated, as a button is.
fn color_swatch(label: const u8[:], c: gfx2d::Color, d: Desc = column()) -> Interaction {
    color_swatch(id(label), c, d)
}
fn color_swatch(i: Id, c: gfx2d::Color, d: Desc = column()) -> Interaction {
    let side = class_style(SWATCH).normal.min_size;
    var sd = clickable(d.skin(SWATCH).clip());
    if sd.dim.w.kind == SIZE_FIT { sd = sd.width(side.x); }
    if sd.dim.h.kind == SIZE_FIT { sd = sd.height(side.y); }
    canvas(i, sd) { size =>
        if c.a < 1.0 {
            checker(0, 0, size.x, size.y, max(size.y / 3.0, 3.0));
            // The left half as it is opaque, the right half as it is.
            fill_rect(0, 0, size.x * 0.5, size.y, gfx2d::with_alpha(c, 1.0));
            fill_rect(size.x * 0.5, 0, size.x * 0.5, size.y, c);
        } else {
            fill_rect(0, 0, size.x, size.y, c);
        }
    }
}

// Each picker's hue, saturation, value and alpha: kept, so that a color
// dragged to gray or black keeps its hue (which its RGB can't say).
var picker_hsv = dictionary<u64, float4> {};

fn close_colors(a: gfx2d::Color, b: gfx2d::Color) -> bool {
    abs(a.r - b.r) < 0.002 && abs(a.g - b.g) < 0.002 && abs(a.b - b.b) < 0.002 && abs(a.a - b.a) < 0.002
}
fn hsv_color(h: float4) -> gfx2d::Color { gfx2d::hsva(h.x, h.y, h.z, h.w) }

// c as hex: #RRGGBB, and AA if `alpha`.
fn format_hex(out: u8[>..]&, c: gfx2d::Color, alpha: bool) {
    fn hex2(out: u8[>..]&, v: f32) {
        let b = clamp(round(v * 255.0) as i64, 0, 255);
        let digits = "0123456789ABCDEF";
        out.push(digits[b / 16]);
        out.push(digits[b % 16]);
    }
    out.push('#');
    hex2(out, c.r);
    hex2(out, c.g);
    hex2(out, c.b);
    if alpha { hex2(out, c.a); }
}
// The color in "#RGB", "#RRGGBB" or "#RRGGBBAA" (the # optional), and
// whether it was one.
fn parse_hex(s: const u8[:], keep_alpha: f32) -> gfx2d::Color, bool {
    var t = s;
    while t.len > 0 && (t[0] == ' ' || t[0] == '#') { t = t[1..]; }
    while t.len > 0 && t[t.len - 1] == ' ' { t = t[..t.len - 1]; }
    fn digit(c: u8) -> i64 {
        if c >= '0' && c <= '9' { return c - '0'; }
        if c >= 'a' && c <= 'f' { return c - 'a' + 10; }
        if c >= 'A' && c <= 'F' { return c - 'A' + 10; }
        -1
    }
    for c in t { if digit(c) < 0 { return gfx2d::TRANSPARENT, false; } }
    if t.len == 3 {
        return gfx2d::rgbaf(digit(t[0]) / 15.0, digit(t[1]) / 15.0, digit(t[2]) / 15.0, keep_alpha), true;
    }
    if t.len != 6 && t.len != 8 { return gfx2d::TRANSPARENT, false; }
    fn byte(k: i64) -> f64 { (digit(t[k]) * 16 + digit(t[k + 1])) / 255.0 }
    return gfx2d::rgbaf(byte(0), byte(2), byte(4), if t.len == 8 { byte(6) } else { keep_alpha as f64 }), true;
}

// A color picker: a square of saturation (across) and value (up), a bar
// of hue, a bar of alpha (if `alpha`), each dragged or moved by the arrows
// while focused; then fields for R, G, B (and A), 0 to 255, and its hex.
// True the frame it changes `c`.
fn color_picker(label: const u8[:], c: gfx2d::Color&, alpha: bool = true, d: Desc = column()) -> bool {
    let i = id(label);
    let start = c;
    // The kept HSV, unless the color has changed from it elsewhere.
    var h = float4 { 0.0, 0.0, 0.0, 1.0 };
    let known = picker_hsv.contains(i.v);
    if known {
        let kept = picker_hsv.get(i.v);
        if kept { h = kept; }
    }
    if !known || !close_colors(hsv_color(h), c) {
        let now = gfx2d::to_hsv(c);
        if now.z > 0.0001 && now.y > 0.0001 { h.x = now.x; }
        if now.z > 0.0001 { h.y = now.y; }
        h.z = now.z;
        h.w = now.w;
    }
    let side = class_style(PICKER).normal.min_size.x;
    let bar_w = max(class_style(SWATCH).normal.min_size.x * 0.7, 10.0);
    let sv_id = sub_id(i, "sv");
    let hue_id = sub_id(i, "hue");
    let alpha_id = sub_id(i, "alpha");
    let fd = clickable(column().with_bits(CAPTURE_X | CAPTURE_Y).clip()).radius(3);
    let sv = interact(sv_id, fd.size(side, side));
    let hb = interact(hue_id, fd.size(bar_w, side));
    let ab = interact(alpha_id, fd.size(bar_w, side));
    fn frac(it: Interaction, a: i64) -> f64 {
        let r = state_of(it.id).rect;
        let k = if a == 0 { r.w / max(it.rect.w, 0.0001) } else { r.h / max(it.rect.h, 0.0001) };
        let p = (if a == 0 { it.pointer.x } else { it.pointer.y }) * k;
        clamp(p / max(if a == 0 { r.w } else { r.h }, 1.0), 0.0, 1.0)
    }
    if sv.held { h.y = frac(sv, 0) as f32; h.z = 1.0 - frac(sv, 1) as f32; }
    if sv.nav.x != 0 { h.y = clamp(h.y + sv.nav.x * 0.02, 0.0, 1.0) as f32; }
    if sv.nav.y != 0 { h.z = clamp(h.z - sv.nav.y * 0.02, 0.0, 1.0) as f32; }
    if hb.held { h.x = min(frac(hb, 1), 0.9999) as f32; }
    if hb.nav.y != 0 { h.x = clamp(h.x + hb.nav.y * 0.01, 0.0, 0.9999) as f32; }
    if alpha && ab.held { h.w = 1.0 - frac(ab, 1) as f32; }
    if alpha && ab.nav.y != 0 { h.w = clamp(h.w - ab.nav.y * 0.02, 0.0, 1.0) as f32; }
    let still = int2 { 0, 0 };
    let moved = sv.held || hb.held || (alpha && ab.held) || sv.nav != still || hb.nav != still || (alpha && ab.nav != still);
    if moved { c = hsv_color(h); }
    let gap = class_style(PICKER).normal.gap;
    box(i, d.skin(PICKER)) {
        box(row().gap(gap)) {
            let hue = gfx2d::hsv(h.x, 1.0, 1.0);
            canvas(sv_id, fd.size(side, side).look(look_of(sv))) { size =>
                gradient_rect(0, 0, size.x, size.y, gfx2d::WHITE, hue, false);
                gradient_rect(0, 0, size.x, size.y, gfx2d::rgba(0x000000, 0.0), gfx2d::BLACK, true);
                let x = h.y * size.x;
                let y = (1.0 - h.z) * size.y;
                stroke_circle(x, y, 5, 3, gfx2d::rgba(0x000000, 0.6));
                stroke_circle(x, y, 5, 1.5, gfx2d::WHITE);
            };
            canvas(hue_id, fd.size(bar_w, side).look(look_of(hb))) { size =>
                for k in 6 {
                    let y0 = size.y * k / 6.0;
                    gradient_rect(0, y0, size.x, size.y / 6.0 + 0.5, gfx2d::hsv(k / 6.0, 1.0, 1.0),
                                  gfx2d::hsv((k + 1) / 6.0, 1.0, 1.0), true);
                }
                let y = h.x * size.y;
                stroke_rect(0.5, y - 2.0, size.x - 1.0, 4, 1.5, gfx2d::WHITE, 1);
            };
            if alpha {
                canvas(alpha_id, fd.size(bar_w, side).look(look_of(ab))) { size =>
                    checker(0, 0, size.x, size.y, size.x * 0.5);
                    let solid = hsv_color(float4 { h.x, h.y, h.z, 1.0 });
                    gradient_rect(0, 0, size.x, size.y, solid, gfx2d::with_alpha(solid, 0.0), true);
                    let y = (1.0 - h.w) * size.y;
                    stroke_rect(0.5, y - 2.0, size.x - 1.0, 4, 1.5, gfx2d::WHITE, 1);
                };
            }
        };
        // The channels, 0 to 255.
        var ch: f64[4] = [round(c.r * 255.0), round(c.g * 255.0), round(c.b * 255.0), round(c.a * 255.0)];
        var typed = false;
        let o = Drag { lo: 0, hi: 255, speed: 0.5 };
        box(row().gap(class_style(NUMBER).normal.gap).grow_w()) {
            let parts = if alpha { 4 } else { 3 };
            for k in parts {
                if number_field(sub_id(i, k + 4), ch[k], o, true, row().grow_w(), k + 4) { typed = true; }
            }
        };
        if typed { c = gfx2d::rgbaf(ch[0] / 255.0, ch[1] / 255.0, ch[2] / 255.0, ch[3] / 255.0); }
        hex_field(sub_id(i, "hex"), c, alpha, row().grow_w());
    };
    // Kept as it is now: from the color if it was typed, else as moved.
    if close_colors(hsv_color(h), c) { picker_hsv.insert(i.v, h); }
    else {
        var now = gfx2d::to_hsv(c);
        if now.y <= 0.0001 || now.z <= 0.0001 { now.x = h.x; }
        if now.z <= 0.0001 { now.y = h.y; }
        picker_hsv.insert(i.v, now);
    }
    let changed = !close_colors(c, start) || c.a != start.a;
    if changed { ui_event(UI_CHANGE, i.v, PICKER); }
    changed
}

// The color's hex, typed in as a number field is.
fn hex_field(i: Id, c: gfx2d::Color&, alpha: bool, d: Desc) {
    if number_editing == i.v {
        guard typing(i, d, state_of(i.v).rect.w);
        let v, ok = parse_hex(number_text[..], c.a);
        if ok { c = if alpha { v } else { gfx2d::with_alpha(v, c.a) }; }
        return;
    }
    let fd = clickable(d.skin(NUMBER).with_bits(CAPTURE_X).align(CENTER).justify(CENTER));
    let it = interact(i, fd);
    var t: u8[>..] = [];
    format_hex(t, c, alpha);
    if it.activated { start_typing(i, t); }
    box(i, fd) { text(t); };
}

// A swatch and the color's hex; the swatch opens a picker under it.
// True the frame it changes `c`.
fn color_edit(label: const u8[:], c: gfx2d::Color&, alpha: bool = true, d: Desc = row()) -> bool {
    let i = id(label);
    let pid = sub_id(i, "picker");
    let sw_id = sub_id(i, "swatch");
    let start = c;
    let open = popup_level(pid.v) > 0;
    labelled(label, d) {
        let rd = if label_text(label).len > 0 { row().grow_w() } else { d };
        box(rd.align(CENTER).gap(class_style(NUMBER).normal.gap)) {
            let header = nodes.len as i32;
            let sw = color_swatch(sw_id, c, column().look(checked_look(open)));
            if sw.activated {
                if open {
                    close_popup(pid);
                } else {
                    open_popup_at(pid, POPUP_PLAIN, Anchor { kind: ANCHOR_BELOW, rect: sw.rect, .. });
                    set_popup_header(pid, sw_id.v);
                }
            }
            hex_field(sub_id(i, "hex"), c, alpha, row().grow_w());
            popup_root(pid, POPUP_PLAIN, column(), POPUP, header) {
                id_scope(pid) { color_picker("picker", c, alpha); };
            };
        };
    };
    let changed = !close_colors(c, start) || c.a != start.a;
    changed
}
