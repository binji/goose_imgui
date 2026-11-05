// Dialogue, as an RPG's: a speaker's portrait and name, glowing, and what they say
// typed out a character at a time (rich text, revealed), its lines laid
// out whole from the start so that nothing moves as it types, each letter
// popping in. Names, places and items are in spans, some with effects: a
// place waving, an item flashing in a halo, a danger shaking, a cold voice shivering
// (an effect of the program's own), magic in a rainbow; the key is an
// image on the line. Click, Enter or Space shows the rest at once, then
// goes on to the next line; a chevron bobs when a line is all there.
//
//   goose examples/dialogue.goose [-- --frames 90 --screenshot dialogue.png]
import std;
import vec;
import math;
import gfx;
import gfx2d from "../../goose_gfx2d";
import imgui from "..";
import .common;
import .scene;

let LINES = [
    ["Elder Maren", "Ah, [who]Wren[/]. You came back from the [place]Ashen Hollow[/] alive. Few do, these days."],
    ["Elder Maren", "Did you find it? The [item]Cinder Key[/] [img=key], the one my grandmother hid beneath the old watchtower?"],
    ["Wren", "I found it. But the [danger]Wardens[/] know it's gone, and [cold]they will come looking[/]."],
    ["Elder Maren", "Then we have little time. Rest tonight, and at first light, take the north road to [magic]Emberfall[/]."],
];
let PORTRAITS = [0xC79A5A, 0x3D7DE0];
let CHARS_PER_SECOND = 40.0;
let SHIVER: u16 = imgui::FX_USER;     // the program's own effect: a quick, small tremble

var line = 0;
var line_at = 0.0;          // when the line began typing
var seed = rng { 3 };

fn speaker_color(name: const u8[:]) -> i64 { if name == "Wren" { PORTRAITS[1] } else { PORTRAITS[0] } }

// The spans, and the key: drawn once into a texture, after the window opens.
fn spans() {
    imgui::add_span("who", imgui::Span { ink: rgb(0x8EC3FF), .. });
    imgui::add_span("place", imgui::Span { ink: rgb(0xF2CF7A), text_fx: imgui::FX_WAVE, fx_args: float4 { 2, 0.8, 0, 0 }, .. });
    let halo = imgui::add_text_look(imgui::TextLook { glow: 3, glow_color: rgba(0xFF7A2A, 0.55), .. });
    imgui::add_span("item", imgui::Span { ink: rgb(0xFF9F5A), underline: true, text_look: halo, text_fx: imgui::FX_FLASH, .. });
    imgui::add_span("danger", imgui::Span { ink: rgb(0xFF6A6A), text_fx: imgui::FX_SHAKE, fx_args: float4 { 1.2, 0, 0, 0 }, .. });
    imgui::add_span("cold", imgui::Span { ink: rgb(0xB8D8FF), text_fx: SHIVER, .. });
    imgui::add_span("magic", imgui::Span { text_fx: imgui::FX_RAINBOW, .. });
}
fn key_icon() {
    let tex = gfx::render_target(32, 32, gfx::RGBA8);
    gfx2d::draw_into(tex, gfx2d::TRANSPARENT) {
        let gold = rgb(0xF2B53C);
        gfx2d::circle_outline(10, 16, 6, 3.5, gold);
        gfx2d::rect(15, 14.5, 14, 3.5, gold);
        gfx2d::rect(22, 17, 3, 6, gold);
        gfx2d::rect(27, 17, 2.5, 5, gold);
    };
    imgui::add_inline("key", tex, gfx2d::rect_of(0, 0, 32, 32), 1.3);
}

fn main() {
    make_rocks(seed);
    spans();
    var icons_ready = false;
    run("imgui: dialogue", 1000, 640) {
        if !icons_ready { key_icon(); icons_ready = true; }
        let t = imgui::time();
        let view = view_size();
        let all = imgui::rich_chars(LINES[line][1]) as f64;
        let shown = (t - line_at) * CHARS_PER_SECOND;
        gfx2d::frame(rgb(0x26332A)) {
            gfx2d::scale(imgui::ui_scale_of()) {
                draw_ground(f2(0, 0), view);
                draw_player(view, 0.0);
            };
            imgui::frame(frame_dt()) {
                // Click, Enter or Space: the rest of the line, or the next.
                let it = imgui::box("dialogue", hud_panel(imgui::row().gap(18).align(imgui::START)).padding(20)
                                                  .width(720).place(imgui::CENTER, imgui::END).offset(0, -28).hit()) {
                    // The portrait: a face in the speaker's color.
                    imgui::panel(imgui::column().size(84, 84).radius(42)
                                 .bg(gfx2d::lighten(rgb(speaker_color(LINES[line][0])), 0.25), rgb(speaker_color(LINES[line][0])))
                                 .border(3, rgba(INK, 0.85)));
                    imgui::box(imgui::column().gap(8).grow_w()) {
                        imgui::text(LINES[line][0], imgui::column().text_size(15).letter_spacing(2).ink(rgb(GOLD))
                                                    .text_glow(2, rgba(GOLD, 0.7)));
                        // Laid out whole, three lines tall at least, so the
                        // panel keeps its size as the text types.
                        // Each letter pops in as it is revealed; the spans'
                        // effects are the built-in ones, and SHIVER, ours.
                        imgui::rich(LINES[line][1], imgui::column().text_size(19).ink(rgb(INK)).wrap().grow_w()
                                                .min_h(84).reveal(shown).text_fx(imgui::FX_POP_IN)) { g =>
                            imgui::standard_fx(g);
                            if g.span_fx == SHIVER {
                                g.turn += (sin(g.time * 40.0 + g.index * 1.7) * 0.06) as f32;
                                g.offset.x += (sin(g.time * 33.0 + g.index * 2.3) * 0.6) as f32;
                            }
                        };
                    };
                    // The chevron, once the line is all there, bobbing. Always
                    // laid out, so that the text's width doesn't change.
                    let more = imgui::animate("more", if shown >= all { 1.0 } else { 0.0 }, imgui::tween(0.2));
                    imgui::icon(imgui::ICON_CHEVRON_DOWN, imgui::column().size(22, 22).ink(rgb(GOLD)).opacity(more)
                                                     .self_align(imgui::END).offset(0, sin(t * 6.0) * 3.0));
                };
                if it.clicked || gfx::key_pressed("Return") || gfx::key_pressed("Space") {
                    if shown < all {
                        line_at = t - all / CHARS_PER_SECOND;
                    } else {
                        line = (line + 1) % LINES.len;
                        line_at = t;
                    }
                }
            };
        };
    };
}
