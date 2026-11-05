// Logs and consoles, driven by made-up input, no GPU: the ring dropping the
// oldest lines past its count and its bytes; text split into lines; a view
// that follows the newest line, stops when scrolled back and follows again
// at the end; filtered by text and level; a console running a command,
// echoing it, and stepping through its history; logging from a loop over
// string literals.
import std;
import vec;
import math;
import gfx;
import gfx2d from "../../../goose_gfx2d";
import imgui from "../..";

var small = imgui::Log { lines_kept: 5, .. };
var tiny = imgui::Log { bytes_kept: 64, .. };
var lg = imgui::Log { .. };
var cmd: u8[>..] = [];
var filter: u8[>..] = [];
var least = imgui::LOG_DEBUG;
var ran: u8[>..] = [];

fn ui() {
    imgui::box(imgui::column().gap(8).padding(10).width(400)) {
        imgui::log_view("view", lg, imgui::column().height(120), filter, least);
        if imgui::console("con", small, cmd, imgui::column().height(140)) {
            format(ran, cmd[..], ";");
            cmd.clear();
        }
    };
}

var at = float2 { -100.0, -100.0 };
fn run_frame(inp: imgui::Input) {
    var i = inp;
    i.viewport = float2 { 640.0, 480.0 };
    imgui::frame(i, 1.0 / 60.0) { ui(); };
}
fn step() { run_frame(imgui::Input { pointer: imgui::Pointer { pos: at, .. }, .. }); }
fn wait(n: i64) { for k in n { step(); } }
fn click_at(p: float2) {
    at = p;
    step();
    run_frame(imgui::Input { pointer: imgui::Pointer { pos: at, down: true, pressed: true, clicks: 1, .. }, .. });
    run_frame(imgui::Input { pointer: imgui::Pointer { pos: at, released: true, .. }, .. });
    step();
}
fn type_line(s: const u8[:]) {
    var inp = imgui::Input { pointer: imgui::Pointer { pos: at, .. }, .. };
    for c in s { inp.text.push(c); }
    run_frame(inp);
    var e = imgui::Input { pointer: imgui::Pointer { pos: at, .. }, .. };
    e.keys.push(imgui::EditKey { key: imgui::KEY_ENTER, .. });
    e.nav.accept = true;
    run_frame(e);
    step();
}
fn nav(n: imgui::NavInput) { run_frame(imgui::Input { pointer: imgui::Pointer { pos: at, .. }, nav: n, .. }); step(); }
fn lines(l: imgui::Log&) -> u8[>..] {
    var t: u8[>..] = [];
    for k in imgui::log_count(l) { format(t, "[", imgui::log_text(l, k), "]"); }
    t
}
fn mid(r: gfx2d::Rect) -> float2 { float2 { r.x + r.w * 0.5, r.y + r.h * 0.5 } }
// The lines the view recorded: how many, the first and last.
fn shown(prefix: const u8[:]) {
    var count = 0;
    var first: const u8[:] = "";
    var last: const u8[:] = "";
    for n, i in imgui::nodes {
        if n.kind != imgui::NODE_TEXT { continue; }
        let t = imgui::node_text(i as i32);
        if t.len >= prefix.len && t[..prefix.len] == prefix {
            if count == 0 { first = t; }
            last = t;
            count++;
        }
    }
    print("  ", count, " shown, ", first, " .. ", last);
}

fn main() {
    // The ring: five lines kept; the oldest go.
    for k in 8 { imgui::logf(small) { out => format(out, "line ", k); }; }
    print("five kept: ", lines(small), " of ", small.added);
    // 64 bytes kept: lines written over go too.
    for k in 6 { imgui::logf(tiny) { out => format(out, "a longer line, number ", k); }; }
    print("by bytes: ", lines(tiny));
    // Text of several lines; a loop over string literals.
    imgui::log(small, "one\ntwo\r\nthree");
    for s in ["four", "five"] { imgui::log(small, s, imgui::LOG_WARN); }
    print("split: ", lines(small));
    imgui::log_clear(small);
    print("cleared: ", imgui::log_count(small), " lines");

    // The view: 200 lines; it follows the newest.
    for k in 200 {
        imgui::logf(lg, if k % 10 == 0 { imgui::LOG_ERROR } else if k % 3 == 0 { imgui::LOG_DEBUG } else { imgui::LOG_INFO }) { out =>
            format(out, "entry ", k);
        };
    }
    wait(40);
    print("following:");
    shown("entry ");
    // Scrolled back by the wheel: new lines don't move it.
    at = mid(imgui::rect_of(imgui::sub_id(imgui::id("view"), "pane")));
    run_frame(imgui::Input { pointer: imgui::Pointer { pos: at, wheel: float2 { 0.0, 3.0 }, .. }, .. });
    wait(40);
    for k in 200..205 { imgui::logf(lg) { out => format(out, "entry ", k); }; }
    wait(40);
    print("scrolled back, five more logged:");
    shown("entry ");
    // Back at the end: following again.
    run_frame(imgui::Input { pointer: imgui::Pointer { pos: at, wheel: float2 { 0.0, -50.0 }, .. }, .. });
    wait(40);
    for k in 205..210 { imgui::logf(lg) { out => format(out, "entry ", k); }; }
    wait(40);
    print("at the end again, five more:");
    shown("entry ");
    // Filtered: by text; by level.
    filter.append("ENTRY 19");
    wait(40);
    print("filtered by \"ENTRY 19\":");
    shown("entry ");
    filter.clear();
    least = imgui::LOG_ERROR;
    wait(40);
    print("errors only:");
    shown("entry ");
    least = imgui::LOG_DEBUG;

    // The console: a command run and echoed; its history by Up and Down.
    let input = imgui::rect_of(imgui::sub_id(imgui::id("con"), "input"));
    click_at(mid(input));
    type_line("spawn 3");
    type_line("help");
    print("ran: ", ran, " log: ", lines(small), ", cmd now \"", cmd, "\"");
    nav(imgui::NavInput { up: true, .. });
    print("up: \"", cmd, "\"");
    nav(imgui::NavInput { up: true, .. });
    print("up: \"", cmd, "\"");
    nav(imgui::NavInput { up: true, .. });
    print("up again (the oldest): \"", cmd, "\"");
    nav(imgui::NavInput { down: true, .. });
    nav(imgui::NavInput { down: true, .. });
    print("down twice: \"", cmd, "\"");
}
