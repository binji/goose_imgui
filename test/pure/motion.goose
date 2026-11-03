// Motion, no GPU: easing curves; tweens and springs by animate(),
// retargeted mid-flight; a spring the same at 60 and 144 frames a second;
// presence in and out; a node's enter transition and its glide when the
// layout moves it.
import std;
import vec;
import math;
import gfx;
import gfx2d from "../../../goose_gfx2d";
import imgui from "../..";

fn r3(x: f64) -> f64 { round(x * 1000.0) / 1000.0 }

var order_flipped = false;
var show_toast = false;
var toast_t = 0.0;
var toast_alive = false;
var target = 0.0;
var tween_v = 0.0;
var spring_v = 0.0;

fn ui() {
    tween_v = imgui::animate("tween", target, imgui::tween(0.5, imgui::EASE_LINEAR));
    spring_v = imgui::animate("spring", target, imgui::spring(200, 20));
    toast_t, toast_alive = imgui::presence("toast", show_toast, imgui::tween(0.2));
    imgui::box(imgui::column().gap(10)) {
        let a = if order_flipped { "B" } else { "A" };
        let b = if order_flipped { "A" } else { "B" };
        imgui::panel(imgui::id(a), imgui::column().size(100, 20).glide(imgui::tween(0.3, imgui::EASE_LINEAR)));
        imgui::panel(imgui::id(b), imgui::column().size(100, 20).glide(imgui::tween(0.3, imgui::EASE_LINEAR)));
        imgui::panel(imgui::id("C"), imgui::column().size(100, 20)
                     .enter(imgui::slide_in(0, 40, imgui::tween(0.4, imgui::EASE_LINEAR)).delay(0.1)));
    };
}

fn frame(dt: f64) {
    imgui::frame(imgui::Input { viewport: float2 { 400.0, 300.0 }, .. }, dt) { ui(); };
}
fn node(label: const u8[:]) -> imgui::Node& {
    let want = imgui::id(label).v;
    for &n in imgui::nodes { if n.id == want { return n; } }
    imgui::nodes[0]
}
fn show(label: const u8[:]) {
    let n .= node(label);
    print("  ", label, ": y ", r3(n.rect.y), " drawn at ", r3(n.rect.y + n.shift.y), " alpha ", r3(n.alpha));
}

fn main() {
    print("ease out cubic at 0.5: ", r3(imgui::ease(imgui::EASE_OUT_CUBIC, 0.5)),
          "; in-out quad at 0.25: ", r3(imgui::ease(imgui::EASE_IN_OUT_QUAD, 0.25)),
          "; out back at 0.6: ", r3(imgui::ease(imgui::EASE_OUT_BACK, 0.6)));

    // A node entering: C slides up from 40 below, after 0.1 s, over 0.4 s.
    frame(0.1);
    print("first frame:");
    show("C");
    frame(0.1);
    frame(0.1);
    show("C");
    frame(0.2);
    show("C");
    frame(0.2);
    show("C");

    // Values: from 0 toward 100; the tween linear over 0.5 s.
    target = 100.0;
    for k in 3 {
        frame(0.1);
        print("t ", r3((k + 1) * 0.1), ": tween ", r3(tween_v), " spring ", r3(spring_v));
    }
    // Retargeted halfway: the tween starts again from where it is.
    target = 0.0;
    frame(0.1);
    print("retargeted: tween ", r3(tween_v), " spring ", r3(spring_v));
    for k in 30 { frame(0.1); }
    print("settled: tween ", r3(tween_v), " spring ", r3(spring_v));

    // A spring the same at any frame rate.
    var at60 = 0.0;
    var at144 = 0.0;
    for k in 15 { frame(1.0 / 60.0); at60 = imgui::animate_from(imgui::id("s60"), 0.0, 1.0, imgui::spring(300, 30)); }
    for k in 36 { frame(1.0 / 144.0); at144 = imgui::animate_from(imgui::id("s144"), 0.0, 1.0, imgui::spring(300, 30)); }
    print("spring after 0.25 s at 60 and 144 Hz: ", r3(at60), " ", r3(at144));

    // Presence: in over 0.2 s, out over 0.2 s, alive until it is out.
    show_toast = true;
    frame(0.1);
    print("toast in: ", r3(toast_t), " ", toast_alive);
    frame(0.15);
    print("toast in: ", r3(toast_t), " ", toast_alive);
    show_toast = false;
    frame(0.1);
    print("toast out: ", r3(toast_t), " ", toast_alive);
    frame(0.15);
    print("toast out: ", r3(toast_t), " ", toast_alive);

    // A glide: A and B swap places, and travel there over 0.3 s.
    order_flipped = true;
    frame(0.1);
    print("swapped:");
    show("A");
    show("B");
    frame(0.1);
    show("A");
    frame(0.2);
    show("A");
    show("B");
}
