// imgui drawn headless and read back: a box's fill, border and corners; a
// gradient; opacity, multiplied in and through a layer; clipping by a box
// that clips (a scroll pane's content past its edge); a motion offset and
// scale; the focus ring, which shows only after navigation.
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

fn render<F>(nav: imgui::NavInput) {
    gfx2d::draw_into(target, gfx2d::WHITE) {
        imgui::frame(imgui::Input { nav: nav, viewport: float2 { W, H }, .. }, 1.0 / 60.0) { F(); };
    };
    px = gfx::read_pixels(target);
}
fn at(x: i64, y: i64) -> u32 {
    let i = (y * W + x) * 4;
    (px[i] as u32 << 16) | (px[i + 1] as u32 << 8) | px[i + 2]
}
fn near(x: i64, y: i64, rgb: i64, tol: i64 = 3) -> bool {
    let ok = close_to(x, y, rgb, tol);
    if !ok { print("    (", x, ",", y, ") is ", hex(at(x, y)), " not ", hex(rgb as u32)); }
    ok
}
fn close_to(x: i64, y: i64, rgb: i64, tol: i64) -> bool {
    let c = at(x, y);
    let r: i64 = (c >> 16) & 255;
    let g: i64 = (c >> 8) & 255;
    let b: i64 = c & 255;
    let d = max(max(abs(r - ((rgb >> 16) & 255)), abs(g - ((rgb >> 8) & 255))), abs(b - (rgb & 255)));
    d <= tol
}
fn hex(c: u32) -> u8[>..] {
    var s: u8[>..] = [];
    let digits = "0123456789ABCDEF";
    for k in 6 { s.push(digits[((c >> ((5 - k) * 4)) & 15) as i64]); }
    s
}

fn main() {
    guard gfx::open_headless(W, H) else {
        print("gfx: ", gfx::error());
        return;
    }
    target = gfx::render_target(W, H, gfx::RGBA8);
    let none = imgui::NavInput { .. };

    // A box: its fill inside, its border at its edge, its corner rounded off.
    render(none) {
        imgui::panel(imgui::column().size(100, 60).bg(gfx2d::rgb(0x3060C0)).border(4, gfx2d::rgb(0xC03030))
                     .radius(16).place(imgui::START, imgui::START).offset(20, 20));
    };
    print("fill: ", near(70, 50, 0x3060C0), "; border: ", near(70, 22, 0xC03030),
          "; corner outside: ", near(21, 21, 0xFFFFFF));

    // A vertical gradient, red at the top to blue at the bottom.
    render(none) {
        imgui::panel(imgui::column().size(100, 100).bg(gfx2d::rgb(0xFF0000), gfx2d::rgb(0x0000FF)));
    };
    print("gradient: top red ", near(50, 1, 0xFF0000, 12), ", bottom blue ", near(50, 98, 0x0000FF, 12),
          ", middle between ", near(50, 50, 0x800080, 12));

    // Opacity: half of black over white; a child's own half more again.
    render(none) {
        imgui::box(imgui::column().size(200, 100).bg(gfx2d::BLACK).opacity(0.5)) {
            imgui::panel(imgui::column().size(50, 50).bg(gfx2d::BLACK).opacity(0.5).offset(120, 0));
        };
    };
    print("opacity 0.5: ", near(20, 20, 0x808080, 3), "; nested, over its parent: ", near(140, 20, 0x606060, 4));
    // Isolated: the group composited at 0.5, its overlaps not showing.
    render(none) {
        imgui::box(imgui::stack().size(200, 100).isolate().opacity(0.5)) {
            imgui::panel(imgui::column().size(100, 100).bg(gfx2d::BLACK));
            imgui::panel(imgui::column().size(100, 100).bg(gfx2d::BLACK).offset(50, 0));
        };
    };
    print("isolated overlap: ", near(75, 50, 0x808080, 3));

    // A clipping box: a child reaching past it is cut off at its edge.
    render(none) {
        imgui::box(imgui::column().size(100, 50).clip()) {
            imgui::panel(imgui::column().size(200, 200).bg(gfx2d::rgb(0x00A000)));
        };
    };
    print("clipped: inside ", near(50, 25, 0x00A000), ", outside ", near(150, 25, 0xFFFFFF),
          ", below ", near(50, 100, 0xFFFFFF));

    // Motion: an offset moves the box and what is in it; a scale grows it
    // about its center.
    render(none) {
        imgui::box(imgui::column().size(40, 40).bg(gfx2d::rgb(0x202020)).offset(100, 100)) {
            imgui::panel(imgui::column().size(10, 10).bg(gfx2d::rgb(0xF0F000)));
        };
        imgui::panel(imgui::column().size(40, 40).bg(gfx2d::rgb(0x2020A0)).place(imgui::END, imgui::END).scale(2.0));
    };
    print("offset: ", near(130, 130, 0x202020), " child moved too ", near(105, 105, 0xF0F000),
          "; scaled: ", near(W - 20, H - 20, 0x2020A0), ", past its box: ", near(W - 55, H - 55, 0x2020A0));

    // A nine-slice: a 30-pixel texture, red within 10 of its edge and green
    // inside, stretched over 120 by 60: its corners and edges keep their
    // 10 pixels, its middle stretches.
    let tex = gfx::render_target(30, 30, gfx::RGBA8);
    gfx2d::draw_into(tex, gfx2d::rgb(0xFF0000)) { gfx2d::rect(10, 10, 10, 10, gfx2d::rgb(0x00FF00)); };
    let slice = imgui::add_nine_slice(tex, gfx2d::rect_of(0, 0, 30, 30), float4 { 10.0, 10.0, 10.0, 10.0 },
                                      gfx2d::FILTER_NEAREST);
    let framed = imgui::add_class(imgui::style_set(imgui::Style { slice: slice, .. }));
    render(none) { imgui::panel(imgui::column().size(120, 60).skin(framed)); };
    print("nine-slice: corner ", near(3, 3, 0xFF0000, 8), ", edge ", near(60, 4, 0xFF0000, 8),
          ", middle ", near(60, 30, 0x00FF00, 8), ", past the corner's 10 ", near(15, 30, 0x00FF00, 8));

    // The UI's scale: a 20-pixel box drawn 40 at 2.
    imgui::set_scale(2);
    render(none) { imgui::panel(imgui::column().size(20, 20).bg(gfx2d::rgb(0x00A0A0))); };
    imgui::set_scale(1);
    print("scale 2: ", near(35, 35, 0x00A0A0), ", past it ", near(45, 45, 0xFFFFFF));

    // The focus ring: none after the pointer; around the button after
    // navigation focuses it.
    fn buttons() {
        imgui::box(imgui::column().padding(20)) { imgui::button("Focus me"); };
    }
    render(none) { buttons(); };
    render(none) { buttons(); };
    let r = imgui::rect_of(imgui::id("Focus me"));
    let rx = r.x as i64 + 20;
    let ry = r.y as i64 - 3;
    print("no ring: ", near(rx, ry, 0xFFFFFF));
    render(imgui::NavInput { down: true, .. }) { buttons(); };
    for k in 10 { render(none) { buttons(); }; }
    print("ring after navigation: ", !close_to(rx, ry, 0xFFFFFF, 40));
}
