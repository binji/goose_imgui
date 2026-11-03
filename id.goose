// IDs: what a widget is known by from one frame to the next. An ID is a
// hash of a label (or an integer) and the IDs of the scopes it is in, so
// "OK" in one dialog and "OK" in another differ. A label's "##" and what
// follows it are part of its ID but not shown: "Play##main", "Play##dlc".
//
//   for item, i in items {
//       imgui::id_scope(i) { if imgui::button("Use") { use(item); } };
//   }

namespace imgui;

import std;

// An explicit ID: its own type, so that box(id, d) and box(i, d), an
// integer key, never mean the same thing.
struct Id { v: u64 }

let ROOT_ID: u64 = 0x9E3779B97F4A7C15;

var id_stack: u64[>..<] = [];

fn scope_id() -> u64 { if id_stack.len > 0 { id_stack[id_stack.len - 1] } else { ROOT_ID } }

// What a label shows: the part before "##".
fn label_text(s: const u8[:]) -> const u8[:] {
    var i = 0;
    while i + 1 < s.len {
        if s[i] == '#' && s[i + 1] == '#' { return s[..i]; }
        i++;
    }
    s
}

fn id(s: const u8[:]) -> Id { Id { hash_combine(scope_id(), hash(s)) } }
fn id(n: i64) -> Id { Id { hash_combine(scope_id(), hash(n) ^ 0x51ED27) } }
// An ID derived from another: a widget's parts.
fn sub_id(parent: Id, part: const u8[:]) -> Id { Id { hash_combine(parent.v, hash(part)) } }
fn sub_id(parent: Id, n: i64) -> Id { Id { hash_combine(parent.v, hash(n) ^ 0x51ED27) } }

fn id_scope<F>(s: const u8[:]) {
    id_stack.push(id(s).v);
    defer id_stack.pop();
    F();
}
fn id_scope<F>(n: i64) {
    id_stack.push(id(n).v);
    defer id_stack.pop();
    F();
}
fn id_scope<F>(i: Id) {
    id_stack.push(i.v);
    defer id_stack.pop();
    F();
}
