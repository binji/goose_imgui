// What the examples share: the command line (--frames N runs N frames and
// quits, --screenshot FILE saves the last one, --theme light|dark|game
// picks a theme, --keys A,B presses keys during the run) and the loop
// around a frame.
import std;
import os;
import gfx;

var frames_wanted = -1;
var screenshot_path: u8[>..] = [];
var theme_name: u8[>..] = [];
var keys: u8[>..] = [];         // --keys Down,Return: pressed one by one from frame 40, 12 apart

var parsed = false;

fn parse_args() {
    if parsed { return; }
    parsed = true;
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
        } else if argv[i] == "--keys" && i + 1 < argv.len {
            keys.append(argv[i + 1]);
            i++;
        } else if argv[i] == "--theme" && i + 1 < argv.len {
            theme_name.append(argv[i + 1]);
            i++;
        }
        i++;
    }
}

// The seconds a frame takes: gfx's, or 1/60 when --frames records a run,
// so that it comes out the same however fast frames are drawn.
fn frame_dt() -> f64 { if frames_wanted >= 0 { 1.0 / 60.0 } else { gfx::delta_time() } }

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
        inject_keys(drawn);
        F();
        drawn++;
    }
    if screenshot_path.len > 0 { gfx::screenshot(screenshot_path); }
    gfx::close();
}

// The --keys pressed, the k-th at frame 40 + 12k, released the frame after.
fn inject_keys(frame: i64) {
    guard keys.len > 0 && frame >= 40;
    let k = (frame - 40) / 12;
    let phase = (frame - 40) % 12;
    guard phase <= 1;
    let names = split(keys, ',');
    guard k < names.len;
    gfx::inject_key(names[k], phase == 0);
}
