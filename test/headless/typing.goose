// Typing into a text field through gfx: injected clicks and text, read by
// input_from_gfx, with the frame given an Input the program changed (as a
// game does to add its own keys). The frame turns gfx's text input on
// while the field has the keyboard, which typed text needs.
import std;
import vec;
import gfx;
import gfx2d from "../../../goose_gfx2d";
import imgui from "../..";

var name: u8[>..] = [];

fn run() {
    gfx::frame();
    let inp = imgui::input_from_gfx();
    imgui::frame(inp, 1.0 / 60.0) {
        imgui::box(imgui::column().padding(20)) { imgui::text_input("name", name, imgui::row().width(200)); };
    };
}

fn main() {
    guard gfx::open_headless(320, 120) else {
        print("gfx: ", gfx::error());
        return;
    }
    run();
    run();
    let r = imgui::rect_of(imgui::id("name"));
    let x = r.x + r.w * 0.5;
    let y = r.y + r.h * 0.5;
    gfx::inject_mouse(x, y, 0, false);
    run();
    gfx::inject_mouse(x, y, gfx::MOUSE_LEFT, true);
    run();
    gfx::inject_mouse(x, y, gfx::MOUSE_LEFT, false);
    run();
    run();
    print("focused: ", imgui::is_focused(imgui::id("name")), "; wants keyboard: ", imgui::wants_keyboard(),
          "; text input on: ", imgui::text_wanted);
    gfx::inject_text("Honk");
    run();
    run();
    print("typed: \"", name, "\"");
    // Clicked away: the text input goes off.
    gfx::inject_mouse(300, 110, gfx::MOUSE_LEFT, true);
    run();
    gfx::inject_mouse(300, 110, gfx::MOUSE_LEFT, false);
    run();
    run();
    print("unfocused; text input on: ", imgui::text_wanted);
    gfx::close();
}
