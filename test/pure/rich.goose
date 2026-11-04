// Rich text, no GPU: markup read into pieces; measured as plain text is;
// wrapped at spaces only, a word in two styles kept whole; a bigger span
// making its line taller, baselines kept; images sized to the text; [[;
// spans closed by name; a rich text played out by its exit.
import std;
import vec;
import math;
import gfx;
import gfx2d from "../../../goose_gfx2d";
import imgui from "../..";

fn r1(x: f64) -> f64 { round(x * 10.0) / 10.0 }

var which = 0;
var shown = true;

fn ui() {
    imgui::box(imgui::column().gap(4).absolute(0, 0)) {
        if which == 0 {
            imgui::text("Deal 20 damage to all", imgui::column());
            imgui::rich("Deal 20 damage to all", imgui::column());
        } else if which == 1 {
            imgui::rich("Deal [big]20[/] damage to [red]every[/red] foe, then [u]Burn[/u] them.",
                        imgui::column().wrap().width(150));
        } else if which == 2 {
            imgui::rich("aaaa[red]bbbb[/]cccc dd ee", imgui::column().wrap().width(40));
        } else if which == 3 {
            imgui::rich("Costs 3 [img=coin]. [[not a tag]\nnext line\n", imgui::column());
        } else if which == 4 && shown {
            imgui::rich("[red]Gone[/] soon", imgui::column().exit(imgui::fade_out(imgui::tween(0.2))));
        }
    };
}

fn frame() { imgui::frame(imgui::Input { viewport: float2 { 400.0, 300.0 }, .. }, 0.05) { ui(); }; }

// Each line of each rich node: its pieces' text, an image as <img>, where
// the style changes as |; and its size.
fn show() {
    for n, i in imgui::nodes {
        guard n.kind == imgui::NODE_RICH else { continue; }
        print("  rich ", r1(n.rect.w), "x", r1(n.rect.h), if n.ghost != 0 { " (leaving)" } else { "" },
              ", natural ", r1(n.natural.x), "x", r1(n.natural.y), ", longest word ", r1(n.word));
        imgui::each_rich_line(i as i32, if n.d.lay.wrap && n.rect.w + 0.5 < n.natural.x { n.rect.w } else { 0.0 })
        { from, to, w, ascent, below =>
            var line: u8[>..] = [];
            for k in from..to {
                let p = imgui::pieces[k];
                if k > from && p.glued { line.append("|"); }
                if p.kind == imgui::PIECE_IMAGE { format(line, "<img ", r1(p.w), ">"); }
                else { line.append(imgui::text_arena[p.off..p.off + p.len]); }
                if p.underline { line.append("_"); }
            }
            print("    \"", line, "\" width ", r1(w), " ascent ", r1(ascent), " below ", r1(below));
        };
    }
    for n in imgui::nodes {
        if n.kind == imgui::NODE_TEXT { print("  text natural ", r1(n.natural.x), "x", r1(n.natural.y)); }
    }
}

fn main() {
    imgui::add_span("big", imgui::Span { text_size: 32, .. });
    imgui::add_span("red", imgui::Span { ink: gfx2d::rgb(0xE04040), .. });
    imgui::add_span("u", imgui::Span { underline: true, .. });
    imgui::add_inline("coin", gfx::Texture { 1 }, gfx2d::Rect { 0, 0, 32, 16 });

    print("plain and rich, the same text:");
    frame();
    show();
    print("wrapped at 150, a bigger span:");
    which = 1;
    frame();
    frame();
    show();
    print("a word in two styles kept whole at 40:");
    which = 2;
    frame();
    frame();
    show();
    print("an image, [[, newlines:");
    which = 3;
    frame();
    show();
    print("leaving:");
    which = 4;
    frame();
    shown = false;
    frame();
    show();
    print("  playing ", imgui::exits_playing());
}
