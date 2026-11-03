// The smallest imgui program: a box, some text and a button.
//
//   goose examples/hello.goose
import std;
import vec;
import gfx;
import gfx2d from "../../goose_gfx2d";
import imgui from "..";
import .common;

var clicks = 0;

fn main() {
    run("imgui: hello", 480, 320) {
        gfx2d::frame(gfx2d::rgb(0xE9ECEF)) {
            imgui::frame(frame_dt()) {
                imgui::box("hello", imgui::column().skin(imgui::PANEL).align(imgui::CENTER)
                                      .place(imgui::CENTER, imgui::CENTER)) {
                    imgui::text("Hello, Goose", imgui::TITLE);
                    if imgui::button("Click me") { clicks++; }
                    imgui::textf(imgui::column().skin(imgui::MUTED)) { out => format(out, "clicked ", clicks, " times"); };
                };
            };
        };
    };
}
