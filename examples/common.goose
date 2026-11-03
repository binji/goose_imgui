// What the examples share: the command line (--frames N runs N frames and
// quits, --screenshot FILE saves the last one, --dark uses the dark theme)
// and the loop around a frame.
import std;
import os;
import gfx;

var frames_wanted = -1;
var screenshot_path: u8[>..] = [];
var dark = false;

fn parse_args() {
    let argv = args();
    var i = 1;
    while i < argv.len {
        if argv[i] == "--frames" && i + 1 < argv.len {
            let n, ok = parse_int(argv[i + 1]);
            if ok { frames_wanted = n; }
            i++;
        } else if argv[i] == "--screenshot" && i + 1 < argv.len {
            screenshot_path.append(argv[i + 1]);
            i++;
        } else if argv[i] == "--dark" {
            dark = true;
        }
        i++;
    }
}

// The window open, and the block run each frame until it closes, Escape
// is pressed (if `escape_quits`), or --frames have run.
fn run<F>(title: const u8[:], w: i64, h: i64, escape_quits: bool = true) {
    parse_args();
    guard gfx::open(title, w, h, gfx::WINDOW_RESIZABLE) else {
        write_stderr(str("gfx: ", gfx::error(), "\n"));
        return;
    }
    var drawn = 0;
    while gfx::frame() {
        if drawn == frames_wanted { break; }
        if escape_quits && gfx::key_pressed("Escape") { break; }
        F();
        drawn++;
    }
    if screenshot_path.len > 0 { gfx::screenshot(screenshot_path); }
    gfx::close();
}
