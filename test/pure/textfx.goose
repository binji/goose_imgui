// Text effects, no GPU: each character's change worked out as its text is
// recorded. The built-in effects, at a known time; one of the program's
// own, by a block; a rich text's spans, each with its own effect and ink;
// a box's effect inherited by its text; characters popping in as
// revealed; a leaving copy, its built-in effect playing on and the
// program's own held as it was.
import std;
import vec;
import math;
import gfx;
import gfx2d from "../../../goose_gfx2d";
import imgui from "../..";

fn r2(x: f64) -> f64 { round(x * 100.0) / 100.0 }

let WOBBLE: u16 = imgui::FX_USER;

var which = 0;
var shown = true;
var reveal = 0.0;

fn ui() {
    imgui::box(imgui::column().absolute(0, 0)) {
        if which == 0 {
            imgui::text("wave", imgui::column().text_fx(imgui::FX_WAVE, 4, 0.5));
            imgui::text("grow", imgui::column().text_fx(imgui::FX_PULSE));
            imgui::text("hue", imgui::column().ink(gfx2d::BLACK).text_fx(imgui::FX_RAINBOW));
            imgui::text("plain");
        } else if which == 1 {
            imgui::text("mine", imgui::column()) { g => g.turn = g.index * 0.1; g.alpha = 0.5; };
        } else if which == 2 {
            imgui::rich("ab [shake]cd[/] [glow]e[/]", imgui::column().ink(gfx2d::BLACK));
        } else if which == 3 {
            imgui::box("swingy", imgui::column().text_fx(imgui::FX_SWING, 0.3)) { imgui::text("in"); };
        } else if which == 4 {
            imgui::text("typing", imgui::column().text_fx(imgui::FX_POP_IN, 0.2, 2).reveal(reveal));
        } else if which == 5 && shown {
            imgui::box("bye", imgui::column().exit(imgui::fade_out(imgui::tween(0.5)))) {
                imgui::text("ww", imgui::column().text_fx(imgui::FX_WAVE));
                imgui::text("mm", imgui::column()) { g => g.offset.x = 7.0 + g.time as f32; };
            };
        }
    };
}

fn frame(dt: f64) { imgui::frame(imgui::Input { viewport: float2 { 400.0, 300.0 }, .. }, dt) { ui(); }; }

// Each text node's characters with effects.
fn show() {
    for n, i in imgui::nodes {
        guard (n.kind == imgui::NODE_TEXT || n.kind == imgui::NODE_RICH) else { continue; }
        guard imgui::has_glyphs(n) else {
            if n.kind == imgui::NODE_TEXT { print("  \"", imgui::node_text(i as i32), "\": none"); }
            continue;
        };
        print("  ", if n.kind == imgui::NODE_RICH { "rich" } else { "text" }, if n.ghost != 0 { " (leaving)" } else { "" }, ":");
        for k in n.cmd_first..n.cmd_end {
            let g = imgui::glyphs[k];
            var cp: u8[>..] = [];
            if g.cp < 0x80 && g.cp >= 0x20 { cp.push(g.cp as u8); } else { format(cp, "#", g.cp); }
            let age: u8[>..] = if g.age < 1.0e8 { str(" age ", r2(g.age)) } else { [] };
            print("    ", g.index, "/", g.count, " '", cp, "' fx ", g.text_fx, "/", g.span_fx, " offset ", r2(g.offset.x), ",",
                  r2(g.offset.y), " scale ", r2(g.scale), " turn ", r2(g.turn), " ink ", r2(g.ink.r), ",", r2(g.ink.g), ",",
                  r2(g.ink.b), " alpha ", r2(g.alpha), age);
        }
    }
}

fn main() {
    imgui::add_span("shake", imgui::Span { text_fx: imgui::FX_SHAKE, fx_args: float4 { 3, 0, 0, 0 }, .. });
    imgui::add_span("glow", imgui::Span { ink: gfx2d::rgb(0x2040C0), text_fx: imgui::FX_FLASH, .. });

    print("built-in effects at 0.5 s, and none:");
    frame(0.25);
    frame(0.25);
    show();
    print("the program's own:");
    which = 1;
    frame(0.1);
    show();
    print("rich spans:");
    which = 2;
    frame(0.1);
    show();
    print("inherited from a box:");
    which = 3;
    frame(0.1);
    show();
    print("popping in as revealed, 3.5 of 6:");
    which = 4;
    reveal = 3.5;
    frame(0.1);
    show();

    print("leaving: the wave plays on, the program's own is held");
    which = 5;
    frame(0.1);
    shown = false;
    frame(0.1);
    show();
    frame(0.1);
    show();
    print("  playing ", imgui::exits_playing());
}
