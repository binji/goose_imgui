// What the HUD and wayfinding examples share: a top-down field of rocks, a
// player walking round an ellipse with the camera on them, and the helpers
// to draw it and to place things over it.
import std;
import vec;
import math;
import gfx;

let INK = 0xF1EDE4;
let GOLD = 0xF2B53C;
let SHADE = 0x05070A;           // shadows, to read text on any ground

fn f2(x: f64, y: f64) -> float2 { float2 { x as f32, y as f32 } }
fn rgb(c: i64) -> gfx2d::Color { gfx2d::rgb(c) }
fn rgba(c: i64, a: f64) -> gfx2d::Color { gfx2d::rgba(c, a) }

var rocks: float4[>..] = [];    // x, y, radius, shade

fn make_rocks(seed: rng&) {
    for k in 70 {
        rocks.push(float4 { (rand_flt(seed) * 2400.0 - 1200.0) as f32, (rand_flt(seed) * 1600.0 - 800.0) as f32,
                            (6.0 + rand_flt(seed) * 22.0) as f32, rand_flt(seed) as f32 });
    }
}

// Where the player is at time t; the camera follows.
fn player_at(t: f64) -> float2 { f2(cos(t * 0.3) * 300.0, sin(t * 0.3) * 180.0) }
// The way they walk: degrees clockwise from north (up), the way a compass
// reads.
fn heading_at(t: f64) -> f64 { bearing(player_at(t + 0.05) - player_at(t)) }
fn bearing(d: float2) -> f64 {
    let b = atan2(d.x, -d.y) * 180.0 / PI;
    if b < 0.0 { b + 360.0 } else { b }
}
// From a to b the short way round, -180 to 180.
fn turn(a: f64, b: f64) -> f64 {
    var d = b - a;
    while d > 180.0 { d -= 360.0; }
    while d < -180.0 { d += 360.0; }
    d
}

// The window's size in the UI's units.
fn view_size() -> float2 {
    let scale = gfx2d::current_scale() * imgui::ui_scale_of();
    let ss = gfx::screen_size();
    f2(ss.x / scale, ss.y / scale)
}

// The ground and its rocks, `cam` at the middle of a `view` in the UI's
// units.
fn draw_ground(cam: float2, view: float2) {
    let o = view * 0.5 - cam;
    let grid = 80.0;
    let line = rgba(0xFFFFFF, 0.04);
    var x = floor(-o.x / grid) * grid;
    while x < -o.x + view.x { gfx2d::line(x + o.x, 0.0, x + o.x, view.y, 1.0, line); x += grid; }
    var y = floor(-o.y / grid) * grid;
    while y < -o.y + view.y { gfx2d::line(0.0, y + o.y, view.x, y + o.y, 1.0, line); y += grid; }
    for r in rocks {
        gfx2d::circle(r.x + o.x + 3.0, r.y + o.y + 4.0, r.z, rgba(0x000000, 0.25));
        gfx2d::circle(r.x + o.x, r.y + o.y, r.z, gfx2d::mix(rgb(0x3A4A3C), rgb(0x56604F), r.w));
    }
}

// The player at the middle of the view: a disk, and a wedge pointing where
// they walk.
fn draw_player(view: float2, t: f64) {
    let c = view * 0.5;
    let a = (heading_at(t) - 90.0) * PI / 180.0;
    gfx2d::circle(c.x + 2.0, c.y + 4.0, 16.0, rgba(0x000000, 0.3));
    gfx2d::circle(c.x, c.y, 16.0, rgb(0x3D7DE0));
    gfx2d::polygon([f2(c.x + cos(a) * 26.0, c.y + sin(a) * 26.0),
                    f2(c.x + cos(a + 2.5) * 14.0, c.y + sin(a + 2.5) * 14.0),
                    f2(c.x + cos(a - 2.5) * 14.0, c.y + sin(a - 2.5) * 14.0)], rgb(INK));
}

// A translucent panel for a HUD's corners.
fn hud_panel(d: imgui::Desc) -> imgui::Desc { d.bg(rgba(0x0B0F14, 0.62)).radius(10).padding(12) }
