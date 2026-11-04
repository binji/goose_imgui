// imgui drawn headless and read back: a box's fill, border and corners; a
// gradient; opacity, multiplied in and through a layer; clipping by a box
// that clips (a scroll pane's content past its edge); a motion offset and
// scale; the focus ring, which shows only after navigation; a text's
// outline and shadow; a radial meter; a box turned and skewed; what has
// left drawn on, with its canvas, as its exit plays; rich text's spans, its
// image and its underline; text revealed in part, each character where it
// is in the whole.
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

    // Text effects: an outline in red around black glyphs, a shadow in
    // blue under them, inherited from a box, and turned off by a child.
    fn count(rgb: i64, tol: i64) -> i64 {
        var n = 0;
        for y in H { for x in W { if close_to(x, y, rgb, tol) { n++; } } }
        n
    }
    fn word(d: imgui::Desc) {
        imgui::text("HUD", d.text_size(40).ink(gfx2d::BLACK).place(imgui::CENTER, imgui::CENTER));
    }
    render(none) { word(imgui::column()); };
    let plain_red = count(0xFF0000, 60);
    let plain_blue = count(0x0000FF, 60);
    render(none) { word(imgui::column().text_outline(2, gfx2d::rgb(0xFF0000))); };
    let red = count(0xFF0000, 60);
    render(none) {
        imgui::box(imgui::stack().grow().text_shadow(gfx2d::rgb(0x0000FF), 4, 4)) { word(imgui::column()); };
    };
    let blue = count(0x0000FF, 60);
    render(none) {
        imgui::box(imgui::stack().grow().text_shadow(gfx2d::rgb(0x0000FF), 4, 4).text_outline(2, gfx2d::rgb(0xFF0000))) {
            word(imgui::column().no_text_shadow().no_text_outline());
        };
    };
    let off_red = count(0xFF0000, 60);
    let off_blue = count(0x0000FF, 60);
    print("text outline: none plain ", plain_red == 0, ", drawn ", red > 100);
    print("text shadow: none plain ", plain_blue == 0, ", inherited ", blue > 100,
          "; turned off ", off_red == 0 && off_blue == 0);

    // A radial meter, a quarter swept from the top, clockwise: red in the
    // top right quarter, not in the top left.
    let red = imgui::add_class(imgui::style_set(imgui::Style { bg: gfx2d::rgb(0xFF0000) }));
    let clear = imgui::add_class(imgui::style_set(imgui::Style { .. }));
    render(none) {
        imgui::radial_meter("sweep", 0.25, imgui::column().size(100, 100),
                            imgui::Meter { track_class: clear, fill_class: red, .. });
    };
    print("radial meter: swept ", near(70, 30, 0xFF0000, 8), ", not yet ", near(30, 30, 0xFFFFFF, 8),
          ", past a quarter ", near(70, 70, 0xFFFFFF, 8));

    // A bar turned a quarter about its center stands upright; a square
    // skewed by 0.5 leans right, its top moved right and its bottom left.
    render(none) {
        imgui::panel(imgui::column().size(120, 20).bg(gfx2d::rgb(0x8000C0)).place(imgui::CENTER, imgui::CENTER)
                     .rotate(PI * 0.5));
        imgui::panel(imgui::column().size(40, 40).bg(gfx2d::rgb(0x00A0A0)).place(imgui::START, imgui::START)
                     .offset(20, 20).skew(0.5));
    };
    print("turned: upright ", near(160, 70, 0x8000C0, 8), ", not across ", near(210, 120, 0xFFFFFF, 8),
          "; skewed: top right ", near(66, 22, 0x00A0A0, 8), ", top left ", near(22, 22, 0xFFFFFF, 8),
          ", bottom left ", near(14, 57, 0x00A0A0, 8));

    // A box with an exit, and a canvas in it: once it is not recorded, its
    // copy is drawn where it was, the canvas's dot too, until it has faded.
    fn leaver() {
        imgui::box("leaver", imgui::stack().size(60, 40).bg(gfx2d::rgb(0x20A040)).place(imgui::START, imgui::START)
                               .offset(20, 20).exit(imgui::fade_out(imgui::tween(0.25, imgui::EASE_LINEAR)))) {
            imgui::canvas("dot", imgui::column().size(20, 20)) { size => imgui::fill_circle(10, 10, 8, gfx2d::rgb(0xFF0000)); };
        };
    }
    render(none) { leaver(); };
    render(none) {};
    let kept = near(70, 50, 0x20A040, 8) && near(30, 30, 0xFF0000, 8);
    for k in 7 { render(none) {}; }
    let fading = !close_to(70, 50, 0x20A040, 8) && !close_to(70, 50, 0xFFFFFF, 8);
    for k in 10 { render(none) {}; }
    print("exit: drawn after it left ", kept, ", fading ", fading, ", gone ", near(70, 50, 0xFFFFFF, 2),
          " ", near(30, 30, 0xFFFFFF, 2), ", playing ", imgui::exits_playing());

    // Rich text: a red span, an image (a green square, drawn into a
    // texture) and a blue underlined span, each where its line puts it.
    let sq = gfx::render_target(8, 8, gfx::RGBA8);
    gfx2d::draw_into(sq, gfx2d::rgb(0x20C040)) {};
    imgui::add_span("red", imgui::Span { ink: gfx2d::rgb(0xFF0000), .. });
    imgui::add_span("blu", imgui::Span { ink: gfx2d::rgb(0x0000FF), underline: true, .. });
    imgui::add_inline("sq", sq, gfx2d::Rect { 0, 0, 8, 8 });
    render(none) {
        imgui::rich("[red]MMM[/] [img=sq] [blu]mmm[/]", imgui::column().text_size(32).ink(gfx2d::BLACK)
                                                         .place(imgui::START, imgui::START).offset(10, 10));
    };
    var reds = 0;
    var greens = 0;
    var blues = 0;
    var blue_row = 0;
    for y in H {
        var row = 0;
        for x in W {
            if close_to(x, y, 0xFF0000, 40) { reds++; }
            if close_to(x, y, 0x20C040, 8) { greens++; }
            if close_to(x, y, 0x0000FF, 40) { blues++; row++; }
        }
        blue_row = max(blue_row, row);
    }
    // The square is 32 tall at size 32; the underline runs the span's width.
    print("rich: red span ", reds > 100, ", image ", greens > 32 * 28, " ", greens <= 32 * 32 + 64,
          ", blue span ", blues > 100, ", underlined ", blue_row > 40);

    // Revealed: "MMM MMM" in a narrow box wraps to two centered lines. Five
    // characters show the first line and the second's first M, where it is
    // when all are shown; the rest of the second line not yet drawn.
    fn typed(rich: bool, chars: f64) {
        let d = imgui::column().text_size(32).ink(gfx2d::BLACK).wrap().width(110).justify(imgui::CENTER)
                               .place(imgui::START, imgui::START).offset(10, 10);
        let r = if chars < 0.0 { d } else { d.reveal(chars) };
        if rich { imgui::rich("[red]MMM[/] MMM", r); } else { imgui::text("MMM MMM", r); }
    }
    for rich in [false, true] {
        render(none) { typed(rich, -1.0); };
        let full = dark_span(60);
        let full_top = dark_span(25);
        render(none) { typed(rich, 5.0); };
        let part = dark_span(60);
        let top = dark_span(25);
        render(none) { typed(rich, 0.0); };
        let none_drawn = dark_span(25).x < 0;
        print(if rich { "rich" } else { "text" }, " revealed: first line whole ", top == full_top,
              ", second line's first M where it was ", part.x == full.x && part.y < full.y - 20,
              ", none at 0 ", none_drawn, ", all of it ", imgui::text_chars("MMM MMM"), " ",
              imgui::rich_chars("[red]MMM[/] MMM [img=sq][[x"));
    }
}

// The first and last columns with anything not white in row y (-1: none).
fn dark_span(y: i64) -> int2 {
    var first = -1;
    var last = -1;
    for x in W {
        if !close_to(x, y, 0xFFFFFF, 60) {
            if first < 0 { first = x; }
            last = x;
        }
    }
    int2 { first as i32, last as i32 }
}
