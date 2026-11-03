// The text field, driven by made-up input, no GPU: focusing it by a click,
// typing, moving the caret by character and by word, selecting with Shift,
// select all, Backspace and Delete, cut and paste, max_len, Enter.
import std;
import vec;
import gfx;
import gfx2d from "../../../goose_gfx2d";
import imgui from "../..";

var name: u8[>..] = [];
var fixed: u8[..8] = [];
var last = imgui::TextEdit { .. };

fn ui() {
    imgui::box(imgui::column().gap(10).padding(10)) {
        last = imgui::text_input("name", name, imgui::row().width(240), 32, "Your name");
        imgui::text_input("code", fixed, imgui::row().width(120), 8);
    };
}
fn run(inp: imgui::Input) {
    var i = inp;
    i.viewport = float2 { 400.0, 300.0 };
    imgui::frame(i, 1.0 / 60.0) { ui(); };
}
fn step() { run(imgui::Input { .. }); }
fn typed(s: const u8[:]) {
    var i = imgui::Input { .. };
    for c in s { i.text.push(c); }
    run(i);
}
fn key(k: i64, shift: bool = false, word: bool = false) {
    var i = imgui::Input { .. };
    i.keys.push(imgui::EditKey { k as u8, shift, word });
    run(i);
}
fn click(label: const u8[:]) {
    let r = imgui::rect_of(imgui::id(label));
    let p = float2 { r.x + r.w - 4.0, r.y + r.h * 0.5 };
    run(imgui::Input { pointer: imgui::Pointer { pos: p, down: true, pressed: true, clicks: 1, .. }, .. });
    run(imgui::Input { pointer: imgui::Pointer { pos: p, released: true, .. }, .. });
}
fn show(what: const u8[:]) {
    let st = imgui::state_of(imgui::id("name").v);
    print(what, ": \"", name, "\" caret ", st.caret, " anchor ", st.anchor);
}

fn main() {
    step();
    step();
    typed("ignored");
    show("unfocused, typing");
    click("name");
    print("focused: ", imgui::is_focused(imgui::id("name")), "; wants keyboard: ", imgui::wants_keyboard());
    typed("Sir Goose");
    show("typed");
    key(imgui::KEY_LEFT, false, true);
    show("word left");
    typed("Honk ");
    show("typed in the middle");
    key(imgui::KEY_HOME);
    key(imgui::KEY_RIGHT, true);
    key(imgui::KEY_RIGHT, true);
    key(imgui::KEY_RIGHT, true);
    show("selected three");
    key(imgui::KEY_CUT);
    show("cut");
    print("copied: \"", imgui::copied, "\"");
    key(imgui::KEY_END);
    typed(" the Wise");
    show("typed at the end");
    key(imgui::KEY_BACKSPACE, false, true);
    show("word backspace");
    key(imgui::KEY_HOME);
    key(imgui::KEY_DELETE);
    show("delete");
    key(imgui::KEY_SELECT_ALL);
    typed("Mallard");
    show("replaced all");
    key(imgui::KEY_ENTER);
    print("submitted: ", last.submitted);
    // A limited buffer: no more than its max_len.
    click("code");
    typed("ABCDEFGHIJ");
    print("code: \"", fixed, "\" (", fixed.len, ")");
    key(imgui::KEY_LEFT);
    key(imgui::KEY_BACKSPACE);
    print("code: \"", fixed, "\"");
    typed("é");
    print("code: \"", fixed, "\" (", fixed.len, " bytes)");
}
