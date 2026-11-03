// Motion: how a value gets from where it is to where it is going. A Motion
// is data (Goose stores no functions): instant, a tween of a duration
// along an easing curve, or a spring; any of them after a delay.
//
//   let x = imgui::animate(imgui::id("panel x"), if open { 0.0 } else { -320.0 },
//                          imgui::spring(400, 30));
//   let t, alive = imgui::presence(imgui::id("toast"), show_toast, imgui::tween(0.25));
//   if alive { imgui::box("toast", imgui::row().opacity(t).offset(0, (1 - t) * 20)) { … }; }
//
// Every animated value is kept by key between frames. Retargeting one
// mid-flight is smooth: a tween starts again from where the value is, a
// spring keeps its velocity. Springs step at a fixed 1/240 s, so they move
// the same at any frame rate.

namespace imgui;

import std;
import vec;
import math;
import dictionary;
import gfx2d;

let MOTION_INSTANT = 0;
let MOTION_TWEEN = 1;
let MOTION_SPRING = 2;

let EASE_LINEAR = 0;
let EASE_IN_QUAD = 1;
let EASE_OUT_QUAD = 2;
let EASE_IN_OUT_QUAD = 3;
let EASE_IN_CUBIC = 4;
let EASE_OUT_CUBIC = 5;
let EASE_IN_OUT_CUBIC = 6;
let EASE_OUT_BACK = 7;          // past the end a little, and back
let EASE_OUT_EXPO = 8;
let EASE_IN_OUT_SINE = 9;
let EASE_OUT_ELASTIC = 10;      // a few wobbles

// `wait` is the delay (`delay` is the setter's name).
struct Motion { kind: u8 = 0, easing: u8 = 0, duration: f32 = 0.0, stiffness: f32 = 0.0,
                damping: f32 = 0.0, wait: f32 = 0.0 }

let INSTANT = Motion { .. };

fn tween(seconds: f64, easing: i64 = EASE_OUT_CUBIC) -> Motion {
    if seconds <= 0.0 { return INSTANT; }
    Motion { kind: MOTION_TWEEN, easing: easing as u8, duration: seconds as f32, .. }
}
// A spring pulling the value toward its target with `stiffness`, slowed
// by `damping`. 2·sqrt(stiffness) damping is critical: as fast as it goes
// without overshooting; less wobbles.
fn spring(stiffness: f64 = 300.0, damping: f64 = 30.0) -> Motion {
    Motion { kind: MOTION_SPRING, stiffness: stiffness as f32, damping: damping as f32, .. }
}
fn delay(var m: Motion, seconds: f64) -> Motion { m.wait = seconds as f32; m }
fn is_instant(m: Motion) -> bool { m.kind == MOTION_INSTANT && m.wait <= 0.0 }

// The easing curve e at t from 0 to 1.
fn ease(e: i64, t: f64) -> f64 {
    let x = clamp(t, 0.0, 1.0);
    match e {
        EASE_IN_QUAD => x * x,
        EASE_OUT_QUAD => 1.0 - (1.0 - x) * (1.0 - x),
        EASE_IN_OUT_QUAD => if x < 0.5 { 2.0 * x * x } else { 1.0 - pow(-2.0 * x + 2.0, 2.0) * 0.5 },
        EASE_IN_CUBIC => x * x * x,
        EASE_OUT_CUBIC => 1.0 - pow(1.0 - x, 3.0),
        EASE_IN_OUT_CUBIC => if x < 0.5 { 4.0 * x * x * x } else { 1.0 - pow(-2.0 * x + 2.0, 3.0) * 0.5 },
        EASE_OUT_BACK => {
            let c1 = 1.70158;
            let c3 = c1 + 1.0;
            1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)
        },
        EASE_OUT_EXPO => if x >= 1.0 { 1.0 } else { 1.0 - pow(2.0, -10.0 * x) },
        EASE_IN_OUT_SINE => -(cos(PI * x) - 1.0) * 0.5,
        EASE_OUT_ELASTIC => {
            if x <= 0.0 { 0.0 } else if x >= 1.0 { 1.0 } else {
                pow(2.0, -10.0 * x) * sin((x * 10.0 - 0.75) * (TAU / 3.0)) + 1.0
            }
        },
        _ => x,
    }
}

// --- animated values ------------------------------------------------------------------

let SPRING_STEP = 1.0 / 240.0;

// A value on its way: from `from` to `to` (a tween, `t` seconds in), or
// at `value` moving at `vel` (a spring). Four lanes, so one state serves
// numbers, points and colors.
struct AnimState {
    from: float4 = float4 { 0.0, 0.0, 0.0, 0.0 },
    to: float4 = float4 { 0.0, 0.0, 0.0, 0.0 },
    value: float4 = float4 { 0.0, 0.0, 0.0, 0.0 },
    vel: float4 = float4 { 0.0, 0.0, 0.0, 0.0 },
    t: f32 = 0.0,
    rest: f32 = 0.0,        // a spring's time not yet stepped
    seen: i64 = -1,         // the frame it last moved in
}

var anims = dictionary<u64, AnimState> {};

fn settled(a: AnimState) -> bool { a.value == a.to && a.vel == float4_0 }

// `a` moved toward `target` by `m` for `dt` seconds.
fn advance(a: AnimState&, target: float4, m: Motion, dt: f64) {
    if a.to != target {
        a.from = a.value;
        a.to = target;
        a.t = 0.0;
    }
    if m.kind == MOTION_INSTANT && m.wait <= 0.0 {
        a.value = a.to;
        a.vel = float4_0;
        return;
    }
    if a.value == a.to && a.vel == float4_0 { return; }
    a.t += dt as f32;
    let running = a.t - m.wait;
    if running <= 0.0 { return; }
    if m.kind == MOTION_SPRING {
        // Only the time since the delay ended counts.
        var left = a.rest + min(running, dt as f32);
        let h: f32 = SPRING_STEP;
        while left >= h - 1.0e-5 {
            let acc = (a.to - a.value) * m.stiffness - a.vel * m.damping;
            a.vel += acc * h;
            a.value += a.vel * h;
            left -= h;
        }
        a.rest = left;
        let d = a.to - a.value;
        if dot(d, d) < 1.0e-8 && dot(a.vel, a.vel) < 1.0e-6 {
            a.value = a.to;
            a.vel = float4_0;
            a.rest = 0.0;
        }
    } else {
        let p = if m.kind == MOTION_TWEEN && m.duration > 0.0 { running / m.duration } else { 1.0 };
        if p >= 1.0 {
            a.value = a.to;
        } else {
            let k = ease(m.easing, p) as f32;
            a.value = a.from + (a.to - a.from) * k;
        }
    }
}

// The value kept under `key`, moved toward `target` by `m` once a frame.
// A key seen the first time starts at `initial` if `from_initial`, else
// at the target.
fn animate_lanes(key: u64, target: float4, m: Motion, initial: float4, from_initial: bool) -> float4 {
    var a = AnimState { .. };
    let found = anims.get(key);
    if found {
        a = found;
    } else {
        let start = if from_initial { initial } else { target };
        a = AnimState { from: start, to: start, value: start, .. };
    }
    if a.seen == frame_index {
        // Asked again this frame: retargeted, not moved again.
        if a.to != target { a.from = a.value; a.to = target; a.t = 0.0; }
    } else {
        advance(a, target, m, delta);
        a.seen = frame_index;
    }
    anims.insert(key, a);
    a.value
}

fn lanes(v: f64) -> float4 { float4 { v as f32, 0.0, 0.0, 0.0 } }
fn lanes(v: float2) -> float4 { float4 { v.x, v.y, 0.0, 0.0 } }
fn lanes(c: gfx2d::Color) -> float4 { gfx2d::premultiplied(c) }
fn color_of(v: float4) -> gfx2d::Color {
    if v.w <= 0.0 { return gfx2d::TRANSPARENT; }
    gfx2d::Color { v.x / v.w, v.y / v.w, v.z / v.w, min(v.w, 1.0) }
}

fn animate(key: Id, target: f64, m: Motion) -> f64 {
    animate_lanes(key.v, lanes(target), m, float4_0, false).x
}
fn animate(key: Id, target: float2, m: Motion) -> float2 {
    let v = animate_lanes(key.v, lanes(target), m, float4_0, false);
    float2 { v.x, v.y }
}
// Colors move premultiplied, so a fade from transparent keeps its hue.
fn animate(key: Id, target: gfx2d::Color, m: Motion) -> gfx2d::Color {
    color_of(animate_lanes(key.v, lanes(target), m, float4_0, false))
}
fn animate(key: const u8[:], target: f64, m: Motion) -> f64 { animate(id(key), target, m) }
fn animate(key: const u8[:], target: float2, m: Motion) -> float2 { animate(id(key), target, m) }
fn animate(key: const u8[:], target: gfx2d::Color, m: Motion) -> gfx2d::Color { animate(id(key), target, m) }
// Starting from `from` the first time the key is seen, not at the target.
fn animate_from(key: Id, from: f64, target: f64, m: Motion) -> f64 {
    animate_lanes(key.v, lanes(target), m, lanes(from), true).x
}

// An item's presence: t goes from 0 to 1 while `visible`, starting the
// first frame it is asked about, and back to 0 after; `alive` while t is
// above 0 or it is visible, so the item keeps being drawn as it leaves.
fn presence(key: Id, visible: bool, m: Motion) -> f64, bool {
    let t = animate_lanes(key.v, lanes(if visible { 1.0 } else { 0.0 }), m, float4_0, true).x;
    let alive = visible || t > 0.0005;
    return t, alive;
}
fn presence(key: const u8[:], visible: bool, m: Motion) -> f64, bool {
    return presence(id(key), visible, m);
}
// The block run with t while the item is alive.
fn presence<F>(key: const u8[:], visible: bool, m: Motion) {
    let t, alive = presence(id(key), visible, m);
    if alive { F(t); }
}

// An amount from 0 to 1 eased toward on (1) or off (0) by `m`: the
// linear progress kept in `p`, its eased value returned.
fn ease_toward(p: f32&, on: bool, m: Motion, dt: f64) -> f32 {
    let target: f32 = if on { 1.0 } else { 0.0 };
    if m.kind == MOTION_INSTANT || m.duration <= 0.0 {
        // Springs ease state amounts as tweens of a fitting length.
        if m.kind == MOTION_SPRING {
            let secs = 4.0 / max(sqrt(m.stiffness), 1.0);
            let step = (dt / secs) as f32;
            p = if on { min(p + step, 1.0) } else { max(p - step, 0.0) };
            return ease(EASE_OUT_CUBIC, p) as f32;
        }
        p = target;
        return target;
    }
    let step = (dt / m.duration) as f32;
    p = if on { min(p + step, 1.0) } else { max(p - step, 0.0) };
    ease(m.easing, p) as f32
}

// Entries not moved for a while are dropped.
fn sweep_anims() {
    var stale: u64[>..<] = [];
    anims.each() { k, a => if a.seen < frame_index - 120 { stale.push(k); } };
    for k in stale { anims.remove(k); }
}
