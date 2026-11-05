// Plots and colors, driven by made-up input, no GPU: a rolling buffer; a
// line plot's range, fitted or fixed, its scale, and the value under the
// pointer; a bar plot's bar under the pointer; a color's hex written and
// read; a picker's square, hue and alpha dragged, its hue kept through
// black, its channels and hex typed in; a color field's swatch opening
// and closing its picker.
import std;
import vec;
import math;
import gfx;
import gfx2d from "../../../goose_gfx2d";
import imgui from "../..";

var samples: f64[>..] = [];
var bars: f32[>..] = [];
var color = gfx2d::rgb(0x3366CC);
var tint = gfx2d::rgba(0xFF8800, 0.5);
var fixed = false;

fn ui() {
    imgui::box(imgui::column().gap(8).padding(10).width(400)) {
        imgui::plot_lines("##lines", samples, if fixed { imgui::Plot { lo: 0, hi: 20 } } else { imgui::Plot { .. } },
                          imgui::column().size(300, 80));
        imgui::plot_bars("##bars", bars, imgui::Plot { decimals: 0 }, imgui::column().size(300, 60));
        imgui::color_picker("pick", color);
        imgui::color_edit("Tint", tint);
    };
}

var at = float2 { -100.0, -100.0 };
fn run_frame(p: imgui::Pointer) {
    imgui::frame(imgui::Input { pointer: p, viewport: float2 { 640.0, 640.0 }, .. }, 1.0 / 60.0) { ui(); };
}
fn step() { run_frame(imgui::Pointer { pos: at, .. }); }
fn click_at(p: float2) {
    at = p;
    step();
    run_frame(imgui::Pointer { pos: at, down: true, pressed: true, clicks: 1, .. });
    run_frame(imgui::Pointer { pos: at, released: true, .. });
    step();
}
fn drag_to(p: float2, to: float2) {
    at = p;
    step();
    run_frame(imgui::Pointer { pos: at, down: true, pressed: true, clicks: 1, .. });
    at = to;
    run_frame(imgui::Pointer { pos: at, down: true, .. });
    run_frame(imgui::Pointer { pos: at, released: true, .. });
    step();
}
fn type_text(s: const u8[:]) {
    var inp = imgui::Input { pointer: imgui::Pointer { pos: at, .. }, viewport: float2 { 640.0, 640.0 }, .. };
    for c in s { inp.text.push(c); }
    imgui::frame(inp, 1.0 / 60.0) { ui(); };
    var e = imgui::Input { pointer: imgui::Pointer { pos: at, .. }, viewport: float2 { 640.0, 640.0 }, .. };
    e.keys.push(imgui::EditKey { key: imgui::KEY_ENTER, .. });
    e.nav.accept = true;
    imgui::frame(e, 1.0 / 60.0) { ui(); };
    step();
}
fn mid(r: gfx2d::Rect) -> float2 { float2 { r.x + r.w * 0.5, r.y + r.h * 0.5 } }
// The text the canvases drew this frame.
fn drawn_text() -> u8[>..] {
    var line: u8[>..] = [];
    for c in imgui::draw_cmds {
        match c.op {
            Text v => { format(line, "[", imgui::text_arena[v.off..v.off + v.len], "] "); },
            _ => {},
        }
    }
    line
}
fn show(c: gfx2d::Color) -> u8[>..] {
    var t: u8[>..] = [];
    imgui::format_hex(t, c, true);
    t
}
fn hsv_of(name: const u8[:]) -> u8[>..] {
    let h = imgui::picker_hsv.get(imgui::id(name).v);
    var t: u8[>..] = [];
    if h { format(t, "h ", round(h.x * 100.0) / 100.0, " s ", round(h.y * 100.0) / 100.0, " v ", round(h.z * 100.0) / 100.0); }
    t
}
// The text node showing exactly `s`, and the widget above it.
fn text_at(s: const u8[:]) -> float2 {
    for n, i in imgui::nodes {
        if n.kind == imgui::NODE_TEXT && imgui::node_text(i as i32) == s { return mid(n.rect); }
    }
    print("no text ", s);
    float2 { -100.0, -100.0 }
}

fn main() {
    // A rolling buffer: the newest at the end, no more than kept.
    for k in 6 { imgui::push_sample(samples, k * 3, 4); }
    print("samples: ", samples[0], " ", samples[1], " ", samples[2], " ", samples[3], " (", samples.len, ")");
    for k in 5 { imgui::push_sample(bars, k + 1, 10); }
    step();
    step();
    // Fitted, the scale is the values' range; fixed, the Plot's.
    print("fitted: ", drawn_text());
    fixed = true;
    step();
    print("fixed: ", drawn_text());
    fixed = false;
    // Under the pointer: the nearest value, read out.
    let lr = imgui::rect_of(imgui::id("##lines"));
    at = float2 { lr.x + lr.w * 0.68, lr.y + lr.h * 0.5 };
    step();
    step();
    print("pointer on lines: ", drawn_text());
    let br = imgui::rect_of(imgui::id("##bars"));
    at = float2 { br.x + br.w * 0.5, br.y + br.h * 0.5 };
    step();
    step();
    print("pointer on bars: ", drawn_text());

    // Hex, written and read.
    let c1, ok1 = imgui::parse_hex("#ff8000", 1.0);
    let c2, ok2 = imgui::parse_hex("1a2b3c80", 1.0);
    let c3, ok3 = imgui::parse_hex("#fff", 0.5);
    let c4, ok4 = imgui::parse_hex("#12345", 1.0);
    print("hex: ", show(c1), " ", ok1, ", ", show(c2), " ", ok2, ", ", show(c3), " ", ok3, ", ", ok4);

    // The picker: its square's top right is full saturation and value;
    // its hue bar's middle is cyan; dragged to black and back up, the hue
    // is kept.
    print("picker: ", show(color), " ", hsv_of("pick"));
    let sq = imgui::rect_of(imgui::sub_id(imgui::id("pick"), "sv"));
    drag_to(mid(sq), float2 { sq.x + sq.w + 10.0, sq.y - 10.0 });
    print("square's corner: ", show(color), " ", hsv_of("pick"));
    let hb = imgui::rect_of(imgui::sub_id(imgui::id("pick"), "hue"));
    drag_to(mid(hb), mid(hb));
    print("hue's middle: ", show(color), " ", hsv_of("pick"));
    drag_to(mid(sq), float2 { sq.x + sq.w * 0.5, sq.y + sq.h + 20.0 });
    print("to black: ", show(color), " ", hsv_of("pick"));
    drag_to(float2 { sq.x + sq.w * 0.5, sq.y + sq.h - 1.0 }, float2 { sq.x + sq.w + 10.0, sq.y - 10.0 });
    print("back up: ", show(color), " ", hsv_of("pick"));
    let ab = imgui::rect_of(imgui::sub_id(imgui::id("pick"), "alpha"));
    drag_to(mid(ab), float2 { ab.x + ab.w * 0.5, ab.y + ab.h * 0.75 });
    print("alpha three quarters down: ", show(color));
    // A channel typed: R 0 -> 16; the hex typed, its alpha kept.
    click_at(text_at("0"));
    type_text("16");
    print("typed R: ", show(color));
    click_at(text_at(show(color)));
    type_text("#102030");
    print("typed hex: ", show(color), " ", hsv_of("pick"));

    // A color field: its swatch opens the picker under it, and closes it.
    let sw = imgui::rect_of(imgui::sub_id(imgui::id("Tint"), "swatch"));
    print("tint: ", show(tint), ", open ", imgui::popups.len);
    click_at(mid(sw));
    // (Above it here: there is no room below.)
    print("swatch clicked: open ", imgui::popups.len, ", picker shown: ",
          imgui::rect_of(imgui::sub_id(imgui::sub_id(imgui::id("Tint"), "picker"), "picker")).w > 0.0);
    click_at(mid(sw));
    print("again: open ", imgui::popups.len);
}
