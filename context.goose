// imgui's state: what this frame records (cleared at its start), and what
// lasts between frames (kept by ID). It is all global, as gfx's and
// gfx2d's is, and the main thread's alone.

namespace imgui;

import std;
import vec;
import dictionary;
import os;
import gfx;
import gfx2d;

// --- the clock ----------------------------------------------------------------------------

var frame_index: i64 = 0;       // frames begun
var delta: f64 = 0.0;           // this frame's seconds
var clock: f64 = 0.0;           // seconds since the first frame
var in_frame = false;
var viewport = gfx2d::Rect { 0.0, 0.0, 800.0, 600.0 };

fn time() -> f64 { clock }
fn dt() -> f64 { delta }

// --- misuse ---------------------------------------------------------------------------

var misuse_count = 0;
var last_misuse: u8[>..] = [];

// A mistake in how imgui is called: printed now, and fatal at the end of
// the frame, as gfx and gfx2d do it.
fn misuse(what: const u8[:]) {
    write_stderr(str("imgui: ", what, "\n"));
    misuse_count++;
    last_misuse.clear();
    last_misuse.append(what);
}
fn check() {
    if misuse_count > 0 { abort(str("imgui: ", last_misuse)); }
}

// --- what lasts between frames ------------------------------------------------------------

// A widget's state, kept by its ID from frame to frame.
struct WidgetState {
    rect: gfx2d::Rect = gfx2d::Rect { 0.0, 0.0, 0.0, 0.0 },     // where it was laid out, last frame
    screen: gfx2d::Rect = gfx2d::Rect { 0.0, 0.0, 0.0, 0.0 },   // where it was drawn, last frame
    shown: gfx2d::Rect = gfx2d::Rect { 0.0, 0.0, 0.0, 0.0 },    // gliding: where it is on its way
    hover: f32 = 0.0, press: f32 = 0.0, focus: f32 = 0.0, checked: f32 = 0.0,   // eased amounts
    hover_p: f32 = 0.0, press_p: f32 = 0.0, focus_p: f32 = 0.0, checked_p: f32 = 0.0,  // their progress
    entered: f32 = 0.0,             // seconds since it appeared
    scroll: float2 = float2 { 0.0, 0.0 },
    scroll_to: float2 = float2 { 0.0, 0.0 },
    content: float2 = float2 { 0.0, 0.0 },     // a scroll pane's content and view sizes, last frame
    view: float2 = float2 { 0.0, 0.0 },
    value: f32 = 0.0,
    open: bool = false,
    index: i32 = -1,                // its place among its owner's: a tab's index
    owner: u64 = 0,
    caret: i32 = 0,
    anchor: i32 = 0,                // the other end of the selection
    text_scroll: f32 = 0.0,
    seen: i64 = -1,                 // the frame it was last recorded in
    born: i64 = -1,                 // the frame it first was
    stamp: i64 = -1,                // the frame its amounts last moved in
    laid: bool = false,             // laid out at least once
}

var states = dictionary<u64, WidgetState> {};

fn state_of(id: u64) -> WidgetState {
    let s = states.get(id);
    if s { return s; }
    WidgetState { .. }
}
fn has_state(id: u64) -> bool { states.contains(id) }
fn put_state(id: u64, s: WidgetState) { states.insert(id, s); }

// States not recorded for a while are dropped.
fn sweep_states() {
    var stale: u64[>..<] = [];
    states.each() { k, s => if s.seen < frame_index - 120 { stale.push(k); } };
    for k in stale { states.remove(k); }
}

// Whether `id` was recorded last frame: present, not newly appeared.
fn was_seen(id: u64) -> bool {
    let s = states.get(id);
    if s { return s.seen >= frame_index - 1; }
    false
}
