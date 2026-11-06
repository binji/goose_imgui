// Small things in the core, no GPU, each its own little UI: a disabled
// slider; focus when its widget goes; a menu's item chosen in a modal; what
// a widget comes back as; the wheel past a pane with nothing to scroll;
// place() in a grid's cell; padded wrapped text; textf wrapping as text does;
// set_viewport; a paste cut at a character's end; a text field's overrides
// and a fixed buffer; a long dropdown; shortcuts and text fields; a modal not
// recorded for a frame; a selected tab past the last.
import std;
import vec;
import gfx;
import gfx2d from "../../../goose_gfx2d";
import imgui from "../..";

var mode = 0;
var shown = true;
var open = true;
var value: f64 = 0.2;
var range_to: f64 = 80.0;
var range_from: f64 = 20.0;
var knob_v: f64 = 0.5;
var hover: f32 = 0.0;
var chosen = 0;
var outer_at: f32 = 0.0;
var item_id = imgui::Id { 0 };
var target_id = imgui::Id { 0 };
var inner_id = imgui::Id { 0 };
var pos = float2 { -100.0, -100.0 };
var down = false;
var right = false;
var wheel = float2 { 0.0, 0.0 };
var typed: u8[..8] = [];
var big: u8[>..] = [];
var keys: u8[>..] = [];
var choice = 0;
var tab = 5;
var chord_a = false;
var chord_q = false;
var inp = imgui::Input { viewport: float2 { 640.0, 300.0 }, .. };

fn ui() {
    match mode {
        0 => {
            imgui::box(imgui::column().padding(10)) {
                imgui::slider("off", value, 0, 1, 0.0, imgui::row().width(300).disabled(true));
                imgui::range_slider("range", range_from, range_to, 0, 100, 0, imgui::row().width(300).disabled(true));
                imgui::knob("knob", knob_v, 0, 1, 0, imgui::column().disabled(true));
            };
        },
        1 => {
            imgui::box(imgui::column().padding(10)) {
                if shown { imgui::button("B"); hover = imgui::last_item().hover_t; }
                imgui::button("Other");
            };
        },
        2 => {
            imgui::modal("m", open, imgui::column()) {
                target_id = imgui::id("target");
                let it = imgui::box("target", imgui::clickable(imgui::column().size(100, 40))) {};
                imgui::context_menu(it) {
                    item_id = imgui::id("Item");
                    if imgui::menu_item("Item") { chosen++; }
                };
            };
        },
        3 => {
            var info = imgui::ScrollInfo { float2 { 0.0, 0.0 }, float2 { 0.0, 0.0 }, float2 { 0.0, 0.0 } };
            imgui::box(imgui::column()) {
                info = imgui::scroll("outer", imgui::column().size(200, 120)) {
                    inner_id = imgui::id("inner");
                    imgui::scroll("inner", imgui::column().size(180, 60)) { imgui::text("short"); };
                    for k in 20 { imgui::text("line"); }
                };
            };
            outer_at = info.offset.y;
        },
        4 => {
            imgui::box("g", imgui::grid(1).size(200, 100)) {
                imgui::box("p", imgui::column().size(20, 20).place(imgui::CENTER, imgui::END)) {};
            };
            imgui::box("g2", imgui::grid(1).size(200, 100)) {
                imgui::box("a", imgui::column().size(20, 20).self_align(imgui::END)) {};
            };
        },
        6 => { imgui::box("vp", imgui::column().size(50, 50)) {}; },
        7 => {
            imgui::box(imgui::column().padding(10)) {
                imgui::text_input("fixed", typed, imgui::row().width(300));
                imgui::text_input("big", big, imgui::row().width(300).text_size(40).padding(60, 4, 4, 4));
                imgui::text_input("keys", keys, imgui::row().width(300));
                chord_a = imgui::shortcut("Ctrl+A");
                chord_q = imgui::shortcut("Ctrl+Q");
            };
        },
        8 => {
            var many: (const u8[:])[>..] = [];
            for k in 100 { many.push("item"); }
            imgui::box(imgui::column().padding(10)) { imgui::dropdown("Long", many[..], choice, imgui::row().width(200)); };
        },
        9 => { if shown { imgui::modal("again", open, imgui::column()) { imgui::text("here"); }; } },
        10 => {
            imgui::tabs("tabs", tab) {
                imgui::tab("One") { imgui::text("one"); };
                imgui::tab("Two") { imgui::text("two"); };
            };
        },
        _ => {
            let long = "several words here that will have to wrap around at this width";
            imgui::box("plain", imgui::column().width(160)) { imgui::text(long, imgui::column().wrap().grow_w()); };
            imgui::box("padded", imgui::column().width(200)) {
                imgui::text(long, imgui::column().wrap().grow_w().padding(20, 0, 20, 0));
            };
            imgui::box(imgui::row().width(10)) {
                imgui::box("t", imgui::column().grow_w()) { imgui::text("unbreakable", imgui::column().wrap()); };
            };
            imgui::box(imgui::row().width(10)) {
                imgui::box("f", imgui::column().grow_w()) {
                    imgui::textf(imgui::column().wrap()) { out => out.append("unbreakable"); };
                };
            };
            imgui::textf(imgui::column().text_fx(imgui::FX_WAVE, 4, 0.5)) { out => out.append("waves"); };
        }
    }
}
fn frame_with(p: imgui::Pointer) {
    var i = inp;
    if i.viewport.x == 640.0 && i.viewport.y == 300.0 && mode != 8 { i.viewport.y = 480.0; }
    i.pointer = p;
    imgui::frame(i, 1.0 / 60.0) { ui(); };
}
fn step() { frame_with(imgui::Pointer { pos: pos, down: down, wheel: wheel, .. }); }
fn press() {
    down = true;
    frame_with(imgui::Pointer { pos: pos, down: true, pressed: true, clicks: 1, .. });
}
fn release() {
    down = false;
    frame_with(imgui::Pointer { pos: pos, released: true, .. });
}
fn center(i: imgui::Id) -> float2 {
    let r = imgui::rect_of(i);
    float2 { r.x + r.w * 0.5, r.y + r.h * 0.5 }
}
fn track(label: const u8[:]) -> imgui::Id { imgui::sub_id(imgui::id(label), "track") }

fn main() {
    print("--- disabled");
    step();
    step();
    pos = center(track("off"));
    pos.x += 80.0;
    step();
    press();
    step();
    release();
    pos = center(track("range"));
    step();
    press();
    release();
    pos = center(imgui::sub_id(imgui::id("knob"), "knob"));
    step();
    press();
    pos.y -= 40.0;
    step();
    step();
    release();
    print("slider ", value, ", range ", range_from, " ", range_to, ", knob ", knob_v);
    imgui::focus(track("off"), true);
    step();
    frame_with(imgui::Pointer { pos: pos, .. });
    print("--- gone");
    mode = 1;
    pos = float2 { -100.0, -100.0 };
    step();
    step();
    let b = imgui::id("B");
    imgui::focus(b, false);
    step();
    print("focused ", imgui::is_focused(b));
    shown = false;
    for k in 5 { step(); }
    print("gone: focused ", imgui::focused_id().v == b.v);
    shown = true;
    for k in 5 { step(); }
    print("back: focused ", imgui::focused_id().v == b.v);

    print("--- back from away");
    pos = center(b);
    for k in 60 { step(); }
    print("hover held ", hover > 0.9);
    pos = float2 { -100.0, -100.0 };
    shown = false;
    for k in 60 { step(); }
    shown = true;
    step();
    print("hover on its return ", hover);

    print("--- a menu's item in a modal");
    mode = 2;
    step();
    step();
    pos = center(target_id);
    step();
    frame_with(imgui::Pointer { pos: pos, secondary: true, .. });
    step();
    step();
    pos = center(item_id);
    step();
    press();
    release();
    step();
    step();
    print("chosen ", chosen, ", modal ", open);

    print("--- the wheel");
    mode = 3;
    step();
    step();
    step();
    pos = center(inner_id);
    step();
    wheel = float2 { 0.0, -3.0 };
    step();
    wheel = float2 { 0.0, 0.0 };
    for k in 30 { step(); }
    print("over a pane with nothing to scroll, the outer moved ", outer_at > 0.0);

    print("--- place in a cell");
    mode = 4;
    step();
    step();
    let g = imgui::rect_of(imgui::id("g"));
    imgui::id_scope(imgui::id("g")) {
        let p = imgui::rect_of(imgui::id("p"));
        print("place(CENTER, END): ", p.x - g.x, " ", p.y - g.y);
    };
    let g2 = imgui::rect_of(imgui::id("g2"));
    imgui::id_scope(imgui::id("g2")) {
        let a = imgui::rect_of(imgui::id("a"));
        print("self_align(END): ", a.x - g2.x, " ", a.y - g2.y);
    };

    print("--- wrapped");
    mode = 5;
    for k in 3 { step(); }
    print("same width to wrap in, same height: ", imgui::rect_of(imgui::id("plain")).h, " ", imgui::rect_of(imgui::id("padded")).h);
    let t = imgui::rect_of(imgui::id("t")).w;
    let f = imgui::rect_of(imgui::id("f")).w;
    print("the longest word holds them open: text ", t > 10.0, ", textf the same ", t == f);

    print("--- set_viewport");
    mode = 6;
    imgui::set_viewport(gfx2d::Rect { 100.0, 50.0, 300.0, 200.0 });
    step();
    step();
    print("at ", imgui::rect_of(imgui::id("vp")).x, " ", imgui::rect_of(imgui::id("vp")).y);
    imgui::set_viewport(gfx2d::Rect { 0.0, 0.0, 0.0, 0.0 });
    step();
    step();
    print("the screen again: ", imgui::rect_of(imgui::id("vp")).x);

    print("--- a long paste");
    var pasted = imgui::Input { .. };
    var long_text: u8[>..] = [];
    long_text.push('a');
    for k in 200 { long_text.append("é"); }
    imgui::add_pasted(pasted, long_text[..]);
    print("bytes ", pasted.text.len, ", ends a character ", pasted.text[pasted.text.len - 1] & 0xC0 == 0x80 && pasted.text[pasted.text.len - 2] & 0xC0 == 0xC0);

    print("--- text fields");
    mode = 7;
    step();
    step();
    let fixed = imgui::id("fixed");
    imgui::focus(fixed, false);
    step();
    inp.text.clear();
    for k in 20 { inp.text.push('x'); }
    step();
    inp.text.clear();
    print("a fixed buffer holds ", typed.len);

    let bi = imgui::id("big");
    imgui::focus(bi, false);
    step();
    for k in 10 { big.push('m'); }
    let br = imgui::rect_of(bi);
    pos = float2 { br.x + 62.0, br.y + br.h * 0.5 };
    step();
    press();
    release();
    print("pressed at the text's start: caret ", imgui::state_of(bi.v).caret);

    pos = float2 { -100.0, -100.0 };
    imgui::focus(imgui::id("keys"), false);
    step();
    step();
    inp.chords.push(imgui::Chord { 'a', imgui::MOD_CTRL });
    inp.chords.push(imgui::Chord { 'q', imgui::MOD_CTRL });
    step();
    inp.chords.clear();
    print("in a text field: Ctrl+A ", chord_a, ", Ctrl+Q ", chord_q);
    imgui::blur();

    print("--- a long dropdown");
    mode = 8;
    step();
    step();
    pos = center(imgui::id("Long"));
    step();
    press();
    release();
    step();
    step();
    let list = imgui::rect_of(imgui::sub_id(imgui::sub_id(imgui::id("Long"), "list"), "items"));
    print("in the screen: ", list.h > 0.0 && list.y >= 0.0 && list.y + list.h <= 300.0);

    print("--- a modal not recorded");
    mode = 9;
    open = true;
    pos = float2 { -100.0, -100.0 };
    step();
    step();
    shown = false;
    step();
    step();
    shown = true;
    step();
    step();
    print("open ", open);

    print("--- past the last tab");
    mode = 10;
    open = false;
    step();
    step();
    print("selected ", tab);
}
