// The metrics window, driven by made-up input, no GPU: the last frame's
// counts and times; its nodes kept only while the window is shown; the
// tree opened a row at a time; a node picked by the pointer, selected,
// its parents opened, outlined; the class names in step with the classes.
import std;
import vec;
import math;
import gfx;
import gfx2d from "../../../goose_gfx2d";
import imgui from "../..";

var show = false;

fn ui() {
    imgui::box(imgui::column().padding(20).gap(10)) {
        imgui::text("A panel");
        imgui::button("Press me");
    };
    imgui::set_window_rect("Metrics", gfx2d::Rect { 300.0, 10.0, 330.0, 460.0 });
    imgui::metrics_window(show);
}

var at = float2 { 600.0, 470.0 };
fn run_frame(p: imgui::Pointer) { imgui::frame(imgui::Input { pointer: p, viewport: float2 { 640.0, 480.0 }, .. }, 1.0 / 60.0) { ui(); }; }
fn step() { run_frame(imgui::Pointer { pos: at, .. }); }
fn click_at(p: float2) {
    at = p;
    step();
    run_frame(imgui::Pointer { pos: at, down: true, pressed: true, clicks: 1, .. });
    run_frame(imgui::Pointer { pos: at, released: true, .. });
    step();
}
fn mid(r: gfx2d::Rect) -> float2 { float2 { r.x + r.w * 0.5, r.y + r.h * 0.5 } }
fn outlined() -> bool {
    for r in imgui::roots { if r.popup == imgui::METRICS_OUTLINE { return true; } }
    false
}

fn main() {
    step();
    step();
    let c = imgui::frame_counts;
    print("counts: nodes ", c.nodes > 0, ", roots ", c.roots, ", hits ", c.hits > 0, ", focusables ", c.focusables);
    let t = imgui::frame_times;
    print("times: none less than 0 ", t.record >= 0.0 && t.layout >= 0.0 && t.after >= 0.0);
    print("nodes kept while hidden: ", imgui::metric_nodes.len);
    show = true;
    step();
    step();
    print("shown: nodes kept ", imgui::metric_nodes.len > 0, ", rows ", imgui::metric_rows.len, " (the roots, closed)");
    // The first root's row opened by its arrow.
    let first = imgui::metric_nodes[0].id;
    let arrow = imgui::sub_id(imgui::sub_id(imgui::Id { first }, "row"), "arrow");
    click_at(mid(imgui::rect_of(arrow)));
    print("first root opened: rows ", imgui::metric_rows.len, ", open ", imgui::metrics_open.contains(first));

    // Picking: the pointer on the button's label; a press selects it.
    imgui::metrics_picking = true;
    let button = imgui::id("Press me");
    let b = imgui::rect_of(button);
    at = mid(b);
    step();
    print("picking: outlined ", outlined());
    click_at(at);
    var sel: i64 = -1;
    for m, k in imgui::metric_nodes { if m.id == imgui::metrics_selected { sel = k; } }
    let m = imgui::metric_nodes[sel];
    print("picked: ", imgui::kind_name(m.kind), " \"", m.text[..], "\", its parent the button ",
          imgui::metric_nodes[m.parent].id == button.v, "; picking off ", !imgui::metrics_picking);
    var shown_row = false;
    for r in imgui::metric_rows { if r == sel { shown_row = true; } }
    print("its row shown (its parents opened) ", shown_row, "; outlined while selected ", outlined());
    print("the button's class: ", imgui::class_name(imgui::metric_nodes[m.parent].class));

    // The names in step with the classes.
    print("class names: ", imgui::class_name(0), ", ", imgui::class_name(imgui::BUTTON.index),
          ", the last ", imgui::class_name(imgui::CLASS_COUNT - 1) == "KNOB", ", past them ",
          imgui::class_name(imgui::CLASS_COUNT));

    show = false;
    step();
    step();
    print("closed: outlined ", outlined());
}
