// Notices, no GPU: posted once and drawn by a queue until their time is
// up; stacked oldest first, gliding as the oldest goes and fading out; a
// queue's limit; a queue of the program's own type, drawn by a block;
// clearing a queue; text given back and reused; long text kept whole.
import std;
import vec;
import math;
import gfx;
import gfx2d from "../../../goose_gfx2d";
import imgui from "../..";

fn r3(x: f64) -> f64 { round(x * 1000.0) / 1000.0 }

var chain = false;      // the block posts another as it draws

struct Hit { amount: i64, at: float2 }
var toasts = imgui::TextNotices { .. };
var feed = imgui::TextNotices { limit: 2, .. };
var hits = imgui::Notices<Hit> { .. };

fn ui() {
    imgui::notices(toasts, imgui::column().gap(10).absolute(0, 0));
    imgui::notices(feed, imgui::column().absolute(200, 0), imgui::row().skin(imgui::NOTICE));
    imgui::notices(hits, imgui::stack().grow()) { n =>
        imgui::box(n.id(), imgui::column().absolute(n.data.at.x, n.data.at.y - n.age() * 10.0)) {
            imgui::textf(imgui::column()) { out => format(out, n.data.amount); };
        };
        if chain { chain = false; imgui::notify(hits, Hit { n.data.amount + 1, n.data.at + float2 { 5.0, 0.0 } }, 1.0); }
    };
}

fn frame(dt: f64) {
    imgui::frame(imgui::Input { viewport: float2 { 400.0, 300.0 }, .. }, dt) { ui(); };
}
fn frames(n: i64) { for k in n { frame(0.1); } }

// Each live notice of a queue: what it holds, where its box is, how far in.
fn show_box(key: u64, what: const u8[:], age: f64) {
    for m in imgui::nodes {
        guard m.id == key && m.ghost == 0 else { continue; }
        print("    ", what, " at ", round(m.rect.x), ",", round(m.rect.y + m.shift.y), " alpha ", r3(m.alpha),
              " age ", r3(age));
    }
}
fn show(q: imgui::TextNotices&, name: const u8[:]) {
    print("  ", name, ": ", imgui::notice_count(q), " live, ", imgui::exits_playing(), " leaving");
    for n in q.list { show_box(n.key, n.text, n.age()); }
}
fn show_hits() {
    print("  hits: ", imgui::notice_count(hits), " live, ", imgui::exits_playing(), " leaving");
    for n in hits.list { show_box(n.key, str(n.data.amount), n.age()); }
}

fn main() {
    // Posted before the first frame, and in frames after.
    imgui::notify(toasts, "Saved", 1.0);
    frame(0.1);
    imgui::notify(toasts, "Found a map", 2.0);
    frame(0.1);
    print("two posted:");
    show(toasts, "toasts");
    frames(5);
    show(toasts, "toasts");
    // The first's time is up: it fades out where it was, and the second
    // glides up into its place.
    frames(4);
    print("the first gone:");
    show(toasts, "toasts");
    frame(0.1);
    show(toasts, "toasts");
    frames(5);
    show(toasts, "toasts");
    frames(6);
    print("both gone:");
    show(toasts, "toasts");

    // A feed of at most two: a third pushes out the oldest.
    imgui::notify(feed, "one", 5.0);
    imgui::notify(feed, "two", 5.0);
    frame(0.1);
    imgui::notify(feed, "three", 5.0);
    frame(0.1);
    print("feed of two:");
    show(feed, "feed");
    imgui::clear_notices(feed);
    frame(0.1);
    print("feed cleared:");
    show(feed, "feed");
    // The text of what has gone is given back, and taken again.
    let pooled = imgui::notice_text.items.len;
    imgui::notify(feed, "four", 5.0);
    imgui::notify(feed, "five", 5.0);
    print("text reused: ", imgui::notice_text.items.len == pooled, " (", pooled, " bytes)");

    // Drawn by the block, from what the program kept: rising 10 a second.
    imgui::notify(hits, Hit { 12, float2 { 100.0, 100.0 } }, 1.0);
    frames(5);
    print("damage:");
    show_hits();
    // A notice posted from the block is drawn from the next frame.
    chain = true;
    frame(0.1);
    print("chained:");
    show_hits();
    frame(0.1);
    show_hits();

    var long: u8[>..] = [];
    for k in 200 { long.push('a' + (k % 26) as u8); }
    imgui::notify(toasts, long, 1.0);
    print("long text kept: ", toasts.list[toasts.list.len - 1].text.len, " of ", long.len);
}
