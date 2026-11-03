// The layout solver, no GPU: rows, columns, gaps and padding; fit, px,
// grow, pct, min and max; justify and align; wrapping rows and text;
// grids; stacks and absolute children. Each case is one frame, its tree
// printed with each node's rect.
import std;
import vec;
import gfx;
import gfx2d from "../../../goose_gfx2d";
import imgui from "../..";

fn view(w: f64, h: f64) -> imgui::Input { imgui::Input { viewport: float2 { w as f32, h as f32 }, .. } }

fn case<F>(name: const u8[:]) {
    print("--- ", name);
    imgui::frame(view(400, 300), 1.0 / 60.0) { F(); };
    imgui::dump();
}

fn main() {
    case("row: px boxes, gap, padding") {
        imgui::box(imgui::row().gap(10).padding(5)) {
            imgui::panel(imgui::column().size(50, 20));
            imgui::panel(imgui::column().size(30, 40));
            imgui::panel(imgui::column().size(20, 10));
        };
    };
    case("row: grow by weight, max") {
        imgui::box(imgui::row().width(300).gap(10)) {
            imgui::panel(imgui::column().width(imgui::grow(1)).height(10));
            imgui::panel(imgui::column().width(imgui::grow(2)).height(10));
            imgui::panel(imgui::column().width(imgui::grow(1)).max_w(30).height(10));
        };
    };
    case("row: shrink to fit, pct") {
        imgui::box(imgui::row().width(200)) {
            imgui::panel(imgui::column().width(imgui::pct(0.25)).height(10));
            imgui::text("a long label that cannot fit", imgui::column().wrap());
        };
    };
    case("column: justify and align") {
        imgui::box(imgui::column().size(200, 200).justify(imgui::SPACE_BETWEEN).align(imgui::CENTER)) {
            imgui::panel(imgui::column().size(40, 20));
            imgui::panel(imgui::column().size(60, 20));
            imgui::panel(imgui::column().size(80, 20).self_align(imgui::END));
        };
        imgui::box(imgui::column().width(120).align(imgui::STRETCH).gap(4)) {
            imgui::panel(imgui::column().height(10));
            imgui::panel(imgui::column().height(10).width(50).self_align(imgui::CENTER));
        };
    };
    case("row: center, space evenly") {
        imgui::box(imgui::row().size(300, 50).justify(imgui::SPACE_EVENLY).align(imgui::CENTER)) {
            imgui::panel(imgui::column().size(30, 30));
            imgui::panel(imgui::column().size(30, 10));
        };
        imgui::box(imgui::row().size(300, 50).center()) {
            imgui::panel(imgui::column().size(100, 20));
        };
    };
    case("wrap") {
        imgui::box(imgui::row().width(220).wrap().gap(10, 5)) {
            for i in 5 { imgui::panel(imgui::column().size(60, 20 + i * 5)); }
        };
    };
    case("grid") {
        imgui::box(imgui::grid([imgui::px(50), imgui::grow(), imgui::grow(2)]).width(350).gap(10)) {
            for i in 5 { imgui::panel(imgui::column().height(20 + i * 10)); }
            imgui::panel(imgui::column().height(15).span(3, 1));
        };
        imgui::box(imgui::grid(3).width(120).gap(0)) {
            imgui::panel(imgui::column().size(10, 10).cell(2, 1).self_align(imgui::CENTER));
        };
    };
    case("stack and absolute") {
        imgui::box(imgui::stack().grow()) {
            imgui::panel(imgui::column().size(50, 50).place(imgui::END, imgui::START));
            imgui::panel(imgui::column().size(60, 20).place(imgui::CENTER, imgui::CENTER));
            imgui::box(imgui::column().size(100, 100).padding(10).place(imgui::START, imgui::END)) {
                imgui::panel(imgui::column().size(10, 10).absolute(5, 5));
                imgui::panel(imgui::column().size(20, 20));
            };
        };
    };
    case("min and max, fit content") {
        imgui::box(imgui::column().min_w(150).padding(8).gap(6)) {
            imgui::text("Title");
            imgui::box(imgui::row().max_w(100)) {
                imgui::panel(imgui::column().size(80, 10));
                imgui::panel(imgui::column().size(80, 10));
            };
        };
    };
}
