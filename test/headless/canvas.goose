// Canvases drawn headless and read back: shapes at their place in the
// box's inner pixels (padding, layout and motion moving them); the size
// the block is given; drawing past a clipping canvas cut off; opacity; a
// canvas scrolled out of its pane not drawn; the pointer, in the canvas's
// pixels; transforms and a circle clip in a canvas.
import std;
import vec;
import math;
import gfx;
import gfx2d from "../../../goose_gfx2d";
import imgui from "../..";

let W = 320;
let H = 240;

var target: gfx::Texture;
var px: u8[>..] = [];
var seen_size = float2 { 0.0, 0.0 };

fn render<F>(p: imgui::Pointer) {
    gfx2d::draw_into(target, gfx2d::WHITE) {
        imgui::frame(imgui::Input { pointer: p, viewport: float2 { W, H }, .. }, 1.0 / 60.0) { F(); };
    };
    px = gfx::read_pixels(target);
}
fn at(x: i64, y: i64) -> u32 {
    let i = (y * W + x) * 4;
    (px[i] as u32 << 16) | (px[i + 1] as u32 << 8) | px[i + 2]
}
fn near(x: i64, y: i64, rgb: i64, tol: i64 = 6) -> bool {
    let c = at(x, y);
    let r: i64 = (c >> 16) & 255;
    let g: i64 = (c >> 8) & 255;
    let b: i64 = c & 255;
    let d = max(max(abs(r - ((rgb >> 16) & 255)), abs(g - ((rgb >> 8) & 255))), abs(b - (rgb & 255)));
    if d > tol { print("    (", x, ",", y, ") is ", c, " not ", rgb); }
    d <= tol
}

fn chart() {
    imgui::box(imgui::row().padding(20).gap(10)) {
        imgui::panel(imgui::column().size(30, 30));
        imgui::canvas("chart", imgui::column().size(200, 100).padding(10).bg(gfx2d::rgb(0xEEEEEE))) { size =>
            seen_size = size;
            imgui::fill_rect(0, 0, 40, 40, gfx2d::rgb(0xD02020));
            imgui::fill_circle(size.x - 20, 20, 15, gfx2d::rgb(0x2040D0));
            imgui::draw_line(0, size.y - 5, size.x, size.y - 5, 4, gfx2d::rgb(0x20A020));
            imgui::fill_polygon([float2 { 60.0, 70.0 }, float2 { 100.0, 70.0 }, float2 { 80.0, 40.0 }], gfx2d::rgb(0xA020A0));
        };
    };
}

fn main() {
    guard gfx::open_headless(W, H) else {
        print("gfx: ", gfx::error());
        return;
    }
    target = gfx::render_target(W, H, gfx::RGBA8);
    let none = imgui::Pointer { .. };

    // The canvas starts at 20 + 30 + 10 = 60 across, 20 down; its inner box
    // 10 in from that, at (70, 30), 180 by 80.
    render(none) { chart(); };
    print("first frame's size: ", seen_size);
    render(none) { chart(); };
    print("size: ", seen_size);
    print("rect: ", near(90, 50, 0xD02020), "; past it, the canvas's bg: ", near(115, 50, 0xEEEEEE),
          "; in the padding: ", near(65, 35, 0xEEEEEE), "; circle: ", near(70 + 160, 30 + 20, 0x2040D0),
          "; line: ", near(160, 30 + 75, 0x20A020), "; triangle: ", near(70 + 80, 30 + 62, 0xA020A0));

    // Clipped: a circle past the canvas's edge cut at it. Faded: half.
    render(none) {
        imgui::canvas("clip", imgui::column().size(100, 100).clip()) { size =>
            imgui::fill_circle(100, 50, 40, gfx2d::BLACK);
        };
        imgui::canvas("faded", imgui::column().size(100, 100).opacity(0.5).place(imgui::END, imgui::START)) { size =>
            imgui::fill_rect(0, 0, 100, 100, gfx2d::BLACK);
        };
    };
    print("clipped: inside ", near(90, 50, 0x000000), ", past the edge ", near(110, 50, 0xFFFFFF),
          "; faded ", near(W - 50, 50, 0x808080, 4));

    // Unclipped, a canvas may draw past its box; in a scroll pane, one
    // scrolled away is not drawn, its drawing culled with it.
    render(none) {
        imgui::canvas("spill", imgui::column().size(50, 50)) { size => imgui::fill_rect(60, 0, 30, 30, gfx2d::BLACK); };
    };
    print("drawn past its box: ", near(75, 15, 0x000000));
    fn pane() {
        imgui::scroll("pane", imgui::column().size(120, 60)) {
            imgui::canvas("top", imgui::column().size(100, 40)) { size => imgui::fill_rect(0, 0, 100, 40, gfx2d::rgb(0x00A000)); };
            imgui::spacer(imgui::column().height(400));
        };
    }
    render(none) { pane(); };
    render(none) { pane(); };
    print("in view: ", near(50, 20, 0x00A000));
    for k in 30 {
        render(imgui::Pointer { pos: float2 { 30.0, 30.0 }, wheel: float2 { 0.0, -3.0 }, .. }) { pane(); };
    }
    print("scrolled away: ", near(50, 20, 0xFFFFFF), "; canvases drawn: ", imgui::nodes.len > 0);

    // The pointer on a hit() canvas, in its pixels: (30, 20) from its inner
    // top left.
    fn hover() -> imgui::Interaction {
        imgui::canvas("hover", imgui::column().size(100, 100).padding(10).hit()) { size => imgui::fill_rect(0, 0, 10, 10, gfx2d::BLACK); }
    }
    var it = imgui::Interaction { .. };
    for k in 3 { render(imgui::Pointer { pos: float2 { 40.0, 30.0 }, .. }) { it = hover(); }; }
    print("hovered: ", it.hovered, "; pointer from the box: ", it.pointer, "; from its inner box: ",
          it.pointer - float2 { 10.0, 10.0 });

    // Transforms in a canvas: a bar from the center turned a quarter points
    // down; a square clipped to a circle loses its corners; a square moved
    // and scaled by 2.
    render(none) {
        imgui::canvas("turned", imgui::column().size(200, 200)) { size =>
            imgui::rotate(PI * 0.5, 100, 100) { imgui::fill_rect(100, 95, 80, 10, gfx2d::rgb(0xC00000)); };
            imgui::clip_circle(50, 50, 30) { imgui::fill_rect(20, 20, 60, 60, gfx2d::rgb(0x0000C0)); };
            imgui::translate(150, 0) { imgui::scale(2) { imgui::fill_rect(0, 10, 10, 10, gfx2d::rgb(0x00A000)); }; };
        };
    };
    print("rotate: turned ", near(100, 150, 0xC00000), ", not where it was ", near(150, 100, 0xFFFFFF),
          "; clip_circle: inside ", near(50, 50, 0x0000C0), ", its corner cut ", near(24, 24, 0xFFFFFF),
          "; translate and scale: ", near(160, 30, 0x00A000), ", ", near(155, 15, 0xFFFFFF));
}
