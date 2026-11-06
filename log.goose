// A log, and a console: lines kept in a ring the program owns, shown in a
// pane that records only the lines in view, stays on the newest unless
// scrolled back, and filters by text and level; a console adds a command
// line, with its history on Up and Down.
//
//   var log = imgui::Log { .. };
//   imgui::log(log, "loaded level 3");
//   imgui::logf(log, imgui::LOG_WARN) { out => format(out, "slow frame: ", ms, " ms"); };
//   imgui::log_view("log", log, imgui::column().grow());
//
//   var cmd: u8[>..] = [];
//   if imgui::console("console", log, cmd) { run(cmd); cmd.clear(); }

namespace imgui;

import std;
import vec;
import math;
import gfx2d;

let LOG_DEBUG = 0;
let LOG_INFO = 1;
let LOG_WARN = 2;
let LOG_ERROR = 3;
let LOG_INPUT = 4;          // a console's command, echoed

struct LogLine { at: i64 = 0, len: i32 = 0, level: u8 = 0, time: f64 = 0.0 }

// The lines: their text in a ring of bytes, themselves in a ring, each
// grown once to its size and then written over, the oldest lines going
// first. Nothing is ever taken out of them, so logging never shrinks an
// array (which a loop over string literals may not do).
root struct Log {
    lines_kept: i64 = 2000,     // at most this many lines
    bytes_kept: i64 = 131072,   // and this much text; a longer line is cut
    text: u8[>..] = [],
    lines: LogLine[>..] = [],
    first: i64 = 0,             // where the oldest line is in `lines`
    count: i64 = 0,
    written: i64 = 0,           // bytes written, ever: where the next goes is this, in the ring
    added: i64 = 0,             // lines logged, ever
}

fn log_count(l: Log&) -> i64 { l.count }
// Line k, the oldest 0.
fn log_line(l: Log&, k: i64) -> LogLine { l.lines[(l.first + k) % max(l.lines_kept, 1)] }
fn log_text(l: Log&, k: i64) -> const u8[:] {
    let ln = log_line(l, k);
    let cap = l.text.len;
    if cap == 0 { return ""; }
    let at = ln.at % cap;
    l.text[at..at + ln.len]
}
// Every line gone (the arrays kept, to be written over).
fn log_clear(l: Log&) {
    l.first = 0;
    l.count = 0;
}

// One line of s (no newlines) added.
fn log_one(l: Log&, s: const u8[:], level: i64) {
    let cap = max(l.bytes_kept, 64);
    let kept = max(l.lines_kept, 1);
    while l.text.len < cap { l.text.push(0); }
    let n = min(s.len, cap);
    // Whole in the ring: from its start if it would run past the end.
    var at = l.written;
    if at % cap + n > cap { at += cap - at % cap; }
    for k in n { l.text[(at + k) % cap] = s[k]; }
    l.written = at + n;
    // The lines written over, and the oldest past the count, gone.
    while l.count > 0 && (log_line(l, 0).at < l.written - cap || l.count >= kept) {
        l.first = (l.first + 1) % kept;
        l.count--;
    }
    let line = LogLine { at: at, len: n as i32, level: level as u8, time: clock };
    let slot = (l.first + l.count) % kept;
    if slot < l.lines.len { l.lines[slot] = line; } else { l.lines.push(line); }
    l.count++;
    l.added++;
}

// s added, a line for each of its lines.
fn log(l: Log&, s: const u8[:], level: i64 = LOG_INFO) {
    var at = 0;
    for k in s.len + 1 {
        if k == s.len || s[k] == '\n' {
            let end = if k > at && s[k - 1] == '\r' { k - 1 } else { k };
            log_one(l, s[at..end], level);
            at = k + 1;
        }
    }
}
// The block's text added: `out` to format into. (A buffer of its own each
// time, not a global one cleared, which would be a shrink.)
fn logf<F>(l: Log&, level: i64 = LOG_INFO) {
    var out: u8[>..] = [];
    F(&out);
    log(l, out, level);
}

// Whether `s` has `part` in it, ignoring case (ASCII).
fn has_text(s: const u8[:], part: const u8[:]) -> bool {
    if part.len == 0 { return true; }
    fn low(c: u8) -> u8 { if c >= 'A' && c <= 'Z' { c + 32 } else { c } }
    var k = 0;
    while k + part.len <= s.len {
        var j = 0;
        while j < part.len && low(s[k + j]) == low(part[j]) { j++; }
        if j == part.len { return true; }
        k++;
    }
    false
}

fn level_class(level: i64) -> StyleClass {
    match level {
        LOG_DEBUG => LOG_DEBUG_LINE,
        LOG_WARN => LOG_WARN_LINE,
        LOG_ERROR => LOG_ERROR_LINE,
        LOG_INPUT => LOG_INPUT_LINE,
        _ => LOG_LINE,
    }
}

// The lines shown this frame, by index: those that pass the filter.
var log_shown: i64[>..<] = [];

// What a log view shows: lines at `least` level or above, with `filter`
// in them (ignoring case).
struct LogFilter { least: i64 = 0 }

// The log's lines in a pane: only those in view recorded, each in its
// level's color; the newest kept in view as lines come, unless it has been
// scrolled back (scrolled to the end, it follows again). Right-click for
// Copy (what is shown, as much as the clipboard takes) and Clear.
fn log_view(label: const u8[:], l: Log&, d: Desc = column(), filter: const u8[:] = "", least: i64 = LOG_DEBUG) {
    let i = id(label);
    log_shown.clear();
    for k in l.count {
        let ln = log_line(l, k);
        if (ln.level == LOG_INPUT || ln.level >= least) && has_text(log_text(l, k), filter) {
            log_shown.push(k);
        }
    }
    // Following the newest line, unless scrolled back (the view's state's
    // `open`): scrolled to its end, as it was last frame. To that, not past
    // it, so that a turn of the wheel back still shows as one.
    let pane = sub_id(i, "pane");
    var vs = state_of(i.v);
    var ps = state_of(pane.v);
    let limit = max(ps.content.y - ps.view.y, 0.0);
    if !vs.open {
        ps.scroll_to.y = limit;
        put_state(pane.v, ps);
    }
    let size = class_style(LOG).normal.text_size;
    let line_h = (if size > 0.0 { size } else { class_style(LABEL).normal.text_size }) * 1.4;
    var pd = d.skin(LOG).hit();
    if pd.dim.w.kind == SIZE_FIT { pd = pd.grow_w(); }
    if pd.dim.h.kind == SIZE_FIT { pd = pd.height(line_h * 10.0); }
    let it = interact(pane, pd);
    id_scope(i) {
        scroll("pane", pd) {
            row_list("lines", log_shown.len, line_h) { k =>
                let n = log_shown[k];
                text(log_text(l, n), column().skin(level_class(log_line(l, n).level)));
            };
        };
    };
    // Scrolled back from the end (by the wheel, the thumb or the focus), it
    // stops following; scrolled to the end, it follows again.
    let after = state_of(pane.v).scroll_to.y;
    vs.open = after < limit - 1.0;
    vs.seen = frame_index;
    put_state(i.v, vs);
    context_menu(it) {
        if menu_item("Copy") {
            // The newest lines that fit the clipboard, in order.
            var from = log_shown.len;
            var bytes = 0;
            while from > 0 && bytes + log_text(l, log_shown[from - 1]).len + 1 <= copied.cap {
                from--;
                bytes += log_text(l, log_shown[from]).len + 1;
            }
            copied.clear();
            for k in from..log_shown.len {
                for c in log_text(l, log_shown[k]) { copied.push(c); }
                copied.push('\n');
            }
        }
        if menu_item("Clear") { log_clear(l); }
    };
}

// The commands typed into consoles, oldest first, for Up and Down.
var console_history = Log { lines_kept: 200, bytes_kept: 16384, .. };
// The line being typed, kept aside while the history is stepped through.
var console_draft: u8[>..] = [];
// How far back each console is in them: 0 and up from the newest; -1 (or
// not here), the line being typed. Kept however long it is hidden.
var console_back = dictionary<u64, i32> {};

// A log view and, under it, a command line: Enter echoes the command into
// the log and returns true, for the program to run it (and clear `cmd`);
// Up and Down step through the commands typed before.
fn console<A>(label: const u8[:], l: Log&, cmd: A&, d: Desc = column(), filter: const u8[:] = "") -> bool {
    let i = id(label);
    let input_id = sub_id(i, "input");
    var back: i64 = -1;
    let kept = console_back.get(i.v);
    if kept { back = kept as i64; }
    var ran = false;
    var cd = d.gap(class_style(PROPERTIES).normal.gap);
    if cd.dim.w.kind == SIZE_FIT { cd = cd.grow_w(); }
    box(i, cd) {
        log_view("log", l, column().grow(), filter);
        // Up and Down: through the history, newest first, then back to
        // what was being typed (kept aside as it was).
        if focused == input_id.v && nav_captured.y != 0 && console_history.count > 0 {
            let n = console_history.count;
            let at = clamp(back - nav_captured.y, -1, n - 1);
            if at != back {
                if back < 0 {
                    console_draft.clear();
                    console_draft.append(cmd[..]);
                }
                erase_text(cmd, 0, cmd.len);
                if at >= 0 {
                    insert_text(cmd, 0, log_text(console_history, n - 1 - at), text_room(cmd, 4096));
                } else {
                    insert_text(cmd, 0, console_draft[..], text_room(cmd, 4096));
                }
                var es = state_of(input_id.v);
                es.caret = cmd.len as i32;
                es.anchor = es.caret;
                put_state(input_id.v, es);
                back = at;
            }
        }
        let e = text_input(input_id, cmd, row().grow_w().with_bits(CAPTURE_Y), 4096, "command");
        if e.submitted && cmd.len > 0 {
            var echo: u8[>..] = [];
            echo.append("> ");
            echo.append(cmd[..]);
            log(l, echo, LOG_INPUT);
            log(console_history, cmd[..]);
            back = -1;
            ran = true;
            // Following the log again, to see what the command does.
            let lv = sub_id(i, "log");
            var vs = state_of(lv.v);
            vs.open = false;
            put_state(lv.v, vs);
        }
    };
    console_back.insert(i.v, back as i32);
    ran
}
