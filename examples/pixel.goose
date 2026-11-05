// A shop in pixel art: imgui in pixel-art mode, three screen pixels to a
// unit, its built-in pixel font and theme_pixel(). Sprites drawn from
// pictures in text, shown nearest at twice their size; slots framed by a
// nine-slice of a few pixels; buttons, a checkbox and a slider in the
// pixel theme, every box on whole pixels. Click an item, or move with the
// arrow keys; Buy takes the gold.
//
//   goose examples/pixel.goose [-- --frames 60 --screenshot pixel.png --scale 4]
import std;
import vec;
import math;
import gfx;
import gfx2d from "../../goose_gfx2d";
import imgui from "..";
import .common;

let NAMES = ["Potion", "Sword", "Shield", "Gem", "Boots", "Map"];
let PRICES = [5, 30, 20, 50, 15, 10];
let ABOUT = ["Heals 10 HP.", "+3 attack.", "+2 defense.", "Shiny. Sells well.", "+1 speed.", "Shows the way."];
// Each item's 8 x 8 picture: a character a pixel, from its colors.
let PICTURES = [
    ["...XX...", "...WW...", "..XrrX..", ".XrrrrX.", ".XrWrrX.", ".XrrrrX.", "..XXXX..", "........"],
    [".......W", "......WX", ".....WX.", "....WX..", ".o.WX...", "..oX....", ".o.o....", "o......."],
    [".XXXXXX.", ".XbbbbX.", ".XbWWbX.", ".XbWWbX.", ".XbbbbX.", "..XbbX..", "...XX...", "........"],
    ["........", "..XXXX..", ".XgWggX.", "XgWggggX", ".XggggX.", "..XggX..", "...XX...", "........"],
    ["........", "..XX....", "..oX....", "..oX....", "..ooX...", "..oooXX.", "..XXXXX.", "........"],
    ["........", ".WWWWWW.", ".WoWWoW.", ".WWrWWW.", ".WoWWrW.", ".WWWWWW.", "........", "........"],
];
let SLOT = 20;                          // a slot's side: a 16-unit sprite and its frame

var gold = 60;
var chosen = 0;
var owned = [0, 0, 0, 0, 0, 0];
var sound = true;
var volume = 0.6;
var said: u8[>..] = [];

// A texture of a picture: X dark, W light, r red, b blue, g green, o brown.
fn sprite(rows: const u8[:][:]) -> gfx::Texture {
    var data: u8[>..] = [];
    for row in rows {
        for c in row {
            let v: i64 = if c == 'X' { 0xFF14101E } else if c == 'W' { 0xFFF4EBD9 } else if c == 'r' { 0xFFD8505A }
                         else if c == 'b' { 0xFF4C7BD8 } else if c == 'g' { 0xFF6CC08A } else if c == 'o' { 0xFFB0763A }
                         else { 0 };
            data.append([((v >> 16) & 255) as u8, ((v >> 8) & 255) as u8, (v & 255) as u8, ((v >> 24) & 255) as u8]);
        }
    }
    let t = gfx::texture2d(8, 8);
    gfx::update_texture(t, data);
    t
}

// A slot's frame, 6 x 6: a light edge a pixel wide, a darker one inside it,
// its corners cut; drawn as a nine-slice, its corners 2 pixels.
fn slot_frame() -> u16 {
    let rows = [".LLLL.", "LDDDDL", "LD..DL", "LD..DL", "LDDDDL", ".LLLL."];
    var data: u8[>..] = [];
    for row in rows {
        for c in row {
            let v: i64 = if c == 'L' { 0xFFE8D6B0 } else if c == 'D' { 0xFF5C4A7A } else { 0x00000000 };
            data.append([((v >> 16) & 255) as u8, ((v >> 8) & 255) as u8, (v & 255) as u8, ((v >> 24) & 255) as u8]);
        }
    }
    let t = gfx::texture2d(6, 6);
    gfx::update_texture(t, data);
    imgui::add_nine_slice(t, gfx2d::rect_of(0, 0, 6, 6), float4 { 2.0, 2.0, 2.0, 2.0 })
}

// The floor behind the shop: tiles, in the UI's units, a pixel a unit.
fn floor(view: float2) {
    for ty in (view.y as i64) / 16 + 1 {
        for tx in (view.x as i64) / 16 + 1 {
            let x = tx * 16;
            let y = ty * 16;
            let shade = if (tx + ty) % 2 == 0 { 0x231C33 } else { 0x1E182C };
            gfx2d::rect(x, y, 16, 16, gfx2d::rgb(shade));
            gfx2d::rect(x, y, 16, 1, gfx2d::rgb(0x2B2440));
        }
    }
}

fn main() {
    imgui::set_pixel_art(true);
    imgui::set_scale(3);
    var ready = false;
    var sprites: gfx::Texture[>..] = [];
    var framed = imgui::NONE;
    run("imgui: pixel art", 960, 540) {
        // What needs the window: the font, in the theme; sprites; the frame.
        if !ready {
            imgui::theme_pixel();
            for p in PICTURES { sprites.push(sprite(p)); }
            framed = imgui::add_class(imgui::style_set(imgui::Style { padding: float4 { 2.0, 2.0, 2.0, 2.0 }, slice: slot_frame() }));
            ready = true;
        }
        let scale = gfx2d::current_scale() * imgui::ui_scale_of();
        let ss = gfx::screen_size();
        let view = float2 { (ss.x / scale) as f32, (ss.y / scale) as f32 };
        gfx2d::frame(imgui::screen_color()) {
            gfx2d::scale(imgui::ui_scale_of()) { floor(view); };
            imgui::frame(frame_dt()) {
                imgui::box("shop", imgui::column().skin(imgui::PANEL).place(imgui::CENTER, imgui::CENTER).width(220)) {
                    imgui::box(imgui::row().align(imgui::CENTER).grow_w()) {
                        imgui::text("Shop", imgui::TITLE);
                        imgui::box(imgui::row().grow_w()) {};
                        imgui::textf(imgui::column().ink(gfx2d::rgb(0xF2C14E))) { out => format(out, gold, " G"); };
                    };
                    // The goods: a slot each, its sprite at twice its size.
                    imgui::box(imgui::grid(6).gap(4)) {
                        for k in NAMES.len {
                            let on = k == chosen;
                            let it = imgui::box(imgui::sub_id(imgui::id("slot"), k),
                                                imgui::stack().skin(framed).size(SLOT + 4, SLOT + 4).hit().focusable()) {
                                // The chosen one lit inside its frame, clear of its cut corners.
                                if on { imgui::panel(imgui::column().absolute(0, 0).size(SLOT, SLOT).bg(gfx2d::rgb(0x46395F))); }
                                imgui::image(sprites[k], imgui::column().size(16, 16).place(imgui::CENTER, imgui::CENTER));
                                if owned[k] > 0 {
                                    imgui::textf(imgui::column().place(imgui::END, imgui::END)) { out => format(out, owned[k]); };
                                }
                            };
                            if it.activated || it.focused { chosen = k; }
                        }
                    };
                    imgui::separator();
                    imgui::textf(imgui::column()) { out => format(out, NAMES[chosen], " - ", PRICES[chosen], " G"); };
                    imgui::text(ABOUT[chosen], imgui::MUTED);
                    imgui::box(imgui::row().gap(6)) {
                        if imgui::button("Buy", imgui::row().disabled(PRICES[chosen] > gold)) {
                            gold -= PRICES[chosen];
                            owned[chosen]++;
                            said.clear();
                            format(said, "Bought the ", NAMES[chosen], ".");
                        }
                        if imgui::button("Sell", imgui::row().disabled(owned[chosen] == 0)) {
                            gold += PRICES[chosen] / 2;
                            owned[chosen]--;
                            said.clear();
                            format(said, "Sold the ", NAMES[chosen], ".");
                        }
                    };
                    imgui::separator();
                    imgui::checkbox("Sound", sound);
                    imgui::slider("Volume", volume, 0, 1, 0.1);
                    imgui::textf(imgui::column().skin(imgui::MUTED)) { out => out.append(if said.len > 0 { said[..] } else { "Welcome, traveller!" }); };
                };
            };
        };
    };
}
