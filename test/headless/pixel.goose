// Pixel-art mode drawn headless and read back: the scale rounded down to
// whole screen pixels; boxes placed at fractions landing on whole units;
// every unit one color (nothing antialiased, the bitmap font and an image
// drawn nearest, a nine-slice too); theme_pixel's sizes whole and its
// corners square; and with the mode off, the same scene antialiased.
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
var checker: gfx::Texture;
var framed = imgui::NONE;

fn scene() {
    imgui::box(imgui::stack().grow()) {
        imgui::panel(imgui::id("red"), imgui::column().absolute(10.5, 7.25).size(30.4, 20.6).bg(gfx2d::rgb(0xD8505A)));
        imgui::text("Gold 12!", imgui::column().absolute(5, 40).ink(gfx2d::BLACK));
        imgui::image(checker, imgui::column().absolute(60, 10).size(16, 16));
        imgui::panel(imgui::column().absolute(90, 10).size(24, 16).skin(framed));
        // Centered: 7 wide in 20, at 6.5.
        imgui::box(imgui::row().absolute(0, 60).size(20, 8).justify(imgui::CENTER)) {
            imgui::panel(imgui::id("mid"), imgui::column().size(7, 8).bg(gfx2d::rgb(0x4C7BD8)));
        };
        imgui::button("Buy", imgui::row().absolute(30, 60));
    };
}

fn render() {
    let s = imgui::ui_scale_of();
    gfx2d::draw_into(target, gfx2d::WHITE) {
        imgui::frame(imgui::Input { viewport: float2 { (W / s) as f32, (H / s) as f32 }, .. }, 1.0 / 60.0) { scene(); };
    };
    px = gfx::read_pixels(target);
}
fn at(x: i64, y: i64) -> u32 {
    let i = (y * W + x) * 4;
    (px[i] as u32 << 16) | (px[i + 1] as u32 << 8) | px[i + 2]
}
// The k x k blocks of the target not all one color.
fn mixed_blocks(k: i64) -> i64 {
    var n = 0;
    var by = 0;
    while by + k <= H {
        var bx = 0;
        while bx + k <= W {
            let c = at(bx, by);
            var same = true;
            for j in k { for i in k { if at(bx + i, by + j) != c { same = false; } } }
            if !same { n++; }
            bx += k;
        }
        by += k;
    }
    n
}
fn r(v: f32) -> f64 { round(v * 100.0) / 100.0 }

fn main() {
    guard gfx::open_headless(W, H) else {
        print("gfx: ", gfx::error());
        return;
    }
    target = gfx::render_target(W, H, gfx::RGBA8);
    // A 2 x 2 checker of black and white, and a 6 x 6 frame: white edge, black middle.
    checker = gfx::texture2d(2, 2);
    gfx::update_texture(checker, [0, 0, 0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 0, 0, 0, 255]);
    let ft = gfx::texture2d(6, 6);
    var fd: u8[>..] = [];
    for y in 6 { for x in 6 {
        let edge = x == 0 || y == 0 || x == 5 || y == 5;
        let v: u8 = if edge { 255 } else { 0 };
        fd.append([v, v, v, 255]);
    } }
    gfx::update_texture(ft, fd);
    framed = imgui::add_class(imgui::style_set(imgui::Style {
        slice: imgui::add_nine_slice(ft, gfx2d::rect_of(0, 0, 6, 6), float4 { 2.0, 2.0, 2.0, 2.0 }) }));

    imgui::set_pixel_art(true);
    imgui::set_scale(2.5);
    print("scale 2.5 in pixel art: ", imgui::ui_scale_of());
    imgui::theme_pixel();
    render();
    render();
    let red = imgui::rect_of(imgui::id("red"));
    let mid = imgui::rect_of(imgui::id("mid"));
    print("placed at 10.5, 7.25, 30.4 x 20.6: ", r(red.x), ", ", r(red.y), ", ", r(red.w), " x ", r(red.h),
          "; centered, 7 in 20: ", r(mid.x));
    print("2 x 2 blocks of more than one color: ", mixed_blocks(2));
    // The checker's texels: 8 units each, black then white, nothing between.
    let cx: i64 = 60 * 2;
    let cy: i64 = 10 * 2;
    print("image nearest: ", at(cx + 15, cy + 4) == 0x000000, " ", at(cx + 16, cy + 4) == 0xFFFFFF,
          " ", at(cx + 4, cy + 16) == 0xFFFFFF, " ", at(cx + 16, cy + 16) == 0x000000);
    // The nine-slice's corner: 2 units of white edge, scaled up, no blur.
    print("nine-slice nearest: ", at(90 * 2, 10 * 2) == 0xFFFFFF, " ", at(90 * 2 + 2, 10 * 2 + 2) == 0x000000);

    // The theme: whole sizes, square corners, hard shadows, one text size.
    let panel = imgui::class_style(imgui::PANEL).normal;
    let button = imgui::class_style(imgui::BUTTON).normal;
    print("theme_pixel: panel padding ", panel.padding.x, ", radius ", panel.radius.x, ", shadow blur ", panel.shadow.blur,
          " offset ", panel.shadow.offset.y, "; button padding ", button.padding.x, ",", button.padding.y,
          " border ", button.border_width, "; text ", button.text_size, ", title ",
          imgui::class_style(imgui::TITLE).normal.text_size, ", muted ", imgui::class_style(imgui::MUTED).normal.text_size,
          "; pressed offset ", imgui::class_style(imgui::BUTTON).active.offset.y, " zoom ",
          imgui::class_style(imgui::BUTTON).active.zoom);
    let font = imgui::pixel_font();
    let m = gfx2d::measure_text("Gold 12!", gfx2d::TextStyle { font: font, size: 6 });
    print("pixel font: \"Gold 12!\" ", m.x, " x ", m.y, ", lower case as upper ",
          gfx2d::measure_text("gold", gfx2d::TextStyle { font: font, size: 6 }).x == gfx2d::measure_text("GOLD", gfx2d::TextStyle { font: font, size: 6 }).x);

    // Off: the scale as set, the box where it was put, the image blended.
    imgui::set_pixel_art(false);
    render();
    render();
    let red2 = imgui::rect_of(imgui::id("red"));
    let s = imgui::ui_scale_of();
    let edge = at(((60.0 + 8.0) * s) as i64, ((10.0 + 4.0) * s) as i64);
    print("off: scale ", s, ", placed at ", r(red2.x), ", ", r(red2.y), ", the image blended ",
          edge != 0x000000 && edge != 0xFFFFFF);
}
