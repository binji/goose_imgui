// How long a frame takes: recording, layout (end_frame) and drawing a UI
// of about `rows` × 8 nodes: a scroll pane of rows, each a label, a
// button, a checkbox, a slider and a progress bar; headless.
//
//   goose bench/bench.goose -- [rows]           JIT
//   goose build bench/bench.goose && ./bench    AOT
import std;
import vec;
import os;
import gfx;
import gfx2d from "../../goose_gfx2d";
import imgui from "..";

var flags: bool[>..] = [];
var values: f64[>..] = [];

fn ui(rows: i64) {
    imgui::scroll("list", imgui::column().gap(4).grow().padding(8)) {
        for k in rows {
            imgui::id_scope(k) {
                imgui::box(imgui::row().gap(10).align(imgui::CENTER).grow_w()) {
                    imgui::textf(imgui::column().width(80)) { out => format(out, "Row ", k); };
                    imgui::button("Use");
                    imgui::checkbox("On", flags[k]);
                    imgui::slider("##v", values[k], 0, 1, 0.0, imgui::row().width(160));
                    imgui::progress(values[k], imgui::column().width(120));
                };
            };
        }
    };
}

fn main() {
    var rows = 250;
    let argv = args();
    if argv.len > 1 {
        let n, ok = parse_int(argv[argv.len - 1]);
        if ok { rows = n; }
    }
    for k in rows { flags.push(k % 3 == 0); values.push((k % 10) / 10.0); }
    guard gfx::open_headless(1280, 720) else {
        print("gfx: ", gfx::error());
        return;
    }
    let target = gfx::render_target(1280, 720, gfx::RGBA8);
    let frames = 60;
    var record = 0.0;
    var layout = 0.0;
    var draw = 0.0;
    var nodes = 0;
    for f in frames + 10 {
        let t0 = clock();
        imgui::begin_frame(imgui::Input { viewport: float2 { 1280.0, 720.0 }, .. }, 1.0 / 60.0);
        ui(rows);
        let t1 = clock();
        imgui::end_frame();
        let t2 = clock();
        gfx2d::draw_into(target, gfx2d::WHITE) { imgui::draw(); };
        let t3 = clock();
        if f >= 10 {
            record += t1 - t0;
            layout += t2 - t1;
            draw += t3 - t2;
        }
        nodes = imgui::nodes.len;
    }
    let ms = 1000.0 / frames;
    print(rows, " rows, ", nodes, " nodes: record ", round(record * ms * 100.0) / 100.0, " ms, layout ",
          round(layout * ms * 100.0) / 100.0, " ms, draw (recorded into gfx2d, and drawn) ", round(draw * ms * 100.0) / 100.0,
          " ms a frame");
}
