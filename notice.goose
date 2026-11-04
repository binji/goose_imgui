// Notices: what the program reports once, and imgui shows for a while and
// takes away. A toast, an area's name as it is entered, a damage number, a
// line of a kill feed. The program keeps a queue, posts to it with
// notify(), in a frame or out of one, and draws it with notices(): its
// live notices, oldest first, each dropped when its time is up or the
// queue is past its limit. A notice drawn with an exit plays it out as it
// is dropped.
//
// There are two kinds of queue. TextNotices holds text of any length, kept
// by imgui and given back as each notice goes; it has a look of its own:
//
//   var toasts = imgui::TextNotices { limit: 3, .. };
//   if found { imgui::notify(toasts, "Found a map", 2.5); }
//   imgui::notices(toasts, imgui::column().gap(8).place(imgui::CENTER, imgui::END));
//
// Notices<T> holds data of the program's own fixed-size type, and a block
// draws each, in a box of the notice's own ID:
//
//   struct Hit { amount: i64, at: float2 }
//   var hits = imgui::Notices<Hit> { .. };
//   imgui::notify(hits, Hit { 12, enemy.pos }, 0.6);
//   imgui::notices(hits, imgui::stack().grow()) { n =>
//       let s = to_screen(n.data.at);
//       imgui::box(n.id(), imgui::column().absolute(s.x, s.y - n.age() * 50).pivot(0.5, 1)
//                            .exit(imgui::fade_out(imgui::tween(0.2)))) {
//           imgui::textf(imgui::column()) { out => format(out, n.data.amount); };
//       };
//   };
//
// Text with other data (a kill feed's names and weapon) is a Notices<T>
// whose T holds the text in arrays of the size the program chooses.

namespace imgui;

import std;
import vec;
import slice_pool;

// A notice of the program's data, and a queue of them. At most `limit`
// are live (0: any number); past it the oldest go first.
struct Notice<T> {
    key: u64 = 0,               // its ID
    data: T,
    born: f64 = 0.0,
    seconds: f64 = 0.0,
}
struct Notices<T> {
    limit: i64 = 0,
    list: Notice<T>[>..<] = [],
}

// A notice of text, and a queue of them.
struct TextNotice {
    key: u64 = 0,
    text: const u8[:] = "",     // a run of notice_text
    born: f64 = 0.0,
    seconds: f64 = 0.0,
}
struct TextNotices {
    limit: i64 = 0,
    list: TextNotice[>..<] = [],
}

// Every text notice's text, each a run taken when it is posted and given
// back when it is dropped.
var notice_text = slice_pool<u8> {};
var notices_posted: u64 = 0;

// The ID of the notice's box; its seconds since it was
// posted, and left.
fn id<T>(n: Notice<T>) -> Id { Id { n.key } }
fn id(n: TextNotice) -> Id { Id { n.key } }
fn age<T>(n: Notice<T>) -> f64 { clock - n.born }
fn age(n: TextNotice) -> f64 { clock - n.born }
fn left<T>(n: Notice<T>) -> f64 { n.seconds - (clock - n.born) }
fn left(n: TextNotice) -> f64 { n.seconds - (clock - n.born) }
fn is_live(n) -> bool { n.seconds > clock - n.born }

fn next_notice_key() -> u64 {
    notices_posted++;
    hash_combine(ROOT_ID ^ 0x6E07, notices_posted)
}

// Posts to the queue, shown for `seconds`.
fn notify<T>(q: Notices<T>&, data: T, seconds: f64 = 3.0) {
    expire_list(q.list, q.limit, 1) { n => };
    q.list.push(Notice<T> { key: next_notice_key(), data: data, born: clock, seconds: seconds });
}
fn notify(q: TextNotices&, text: const u8[:], seconds: f64 = 3.0) {
    expire_list(q.list, q.limit, 1) { n => notice_text.free_slice(n.text); };
    q.list.push(TextNotice { key: next_notice_key(), text: notice_text.alloc_copy(text), born: clock,
                             seconds: seconds });
}

// The queue emptied at once (each plays its exit).
fn clear_notices<T>(q: Notices<T>&) { q.list.clear(); }
fn clear_notices(q: TextNotices&) {
    for n in q.list { notice_text.free_slice(n.text); }
    q.list.clear();
}

// How many of the queue's notices are live.
fn notice_count(q) -> i64 {
    var c = 0;
    for n in q.list { if is_live(n) { c++; } }
    c
}

// The notices whose time is up dropped, and the oldest past `limit`,
// leaving room for `adding` more; the block given each dropped.
fn expire_list<N, F>(list: N[>..<]&, limit: i64, adding: i64) {
    var over = adding - limit;
    for n in list { if is_live(n) { over++; } }
    if limit <= 0 { over = 0; }
    var w = 0;
    for k in list.len {
        let n = list[k];
        if !is_live(n) { F(n); continue; }
        if over > 0 { over--; F(n); continue; }
        list[w] = n;
        w++;
    }
    while list.len > w { list.pop(); }
}

// The live notices, in a box of `d`, oldest first, each drawn by the block.
fn draw_list<N, F>(list: N[>..<]&, d: Desc) {
    box(d) {
        // By index, and each a copy: the block may post more.
        let count = list.len;
        for k in count {
            if k >= list.len { break; }
            F(list[k]);
        }
    };
}

// The queue's live notices, in a box of `d`, oldest first, each drawn by
// the block.
fn notices<T, F>(q: Notices<T>&, d: Desc) {
    expire_list(q.list, q.limit, 0) { n => };
    draw_list(q.list, d) { n => F(n); };
}
fn notices<F>(q: TextNotices&, d: Desc) {
    expire_list(q.list, q.limit, 0) { n => notice_text.free_slice(n.text); };
    draw_list(q.list, d) { n => F(n); };
}

// A text notice's box, for notices() without a block: a NOTICE, sliding
// in, gliding as those before it go, and fading out.
fn notice_item() -> Desc {
    row().skin(NOTICE).enter(slide_in(0, 12, spring(300, 26))).glide(spring(300, 30))
         .exit(fade_out(tween(0.3)))
}
// A queue of text, each as `item` holding its text.
fn notices(q: TextNotices&, d: Desc = column().gap(8), item: Desc = notice_item()) {
    notices(q, d) { n => box(n.id(), item) { text(n.text); }; };
}
