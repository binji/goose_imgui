// An inventory: a grid of slots in a scroll pane, each a button with its
// own drawing (a colored gem, a count); a tooltip on the one under the
// pointer (or focus); the chosen one's details beside it. The arrows move
// across the grid, and the pane scrolls to keep the focus in view.
//
// Gems are dragged between slots (two swap), or onto the trash; the gem
// carried is drawn under the pointer. With the keys: Enter picks the
// focused one up, the arrows carry it, and Enter puts it down; Escape puts
// it back. Each gem glides to its new slot: from where it was let go, or,
// swapped, from the other slot. One thrown away pops where it was let go.
//
//   goose examples/inventory.goose [-- --frames 60 --screenshot inventory.png]
import std;
import vec;
import math;
import gfx;
import gfx2d from "../../goose_gfx2d";
import imgui from "..";
import .common;

// kind -1: an empty slot. `gem` names the gem, wherever it goes, so that it
// glides from one slot to another.
struct Item { name: u8[..20], kind: i64, count: i64, gem: i64 = 0 }

let KINDS = ["Ruby", "Sapphire", "Emerald", "Topaz", "Amethyst", "Pearl"];
let COLORS = [0xE0455A, 0x3D7DE0, 0x2EBE7A, 0xF2B53C, 0x9C5BE0, 0xE8E4DA];

var items: Item[>..] = [];
var chosen = 0;
let GEM = 1;                    // what drag and drop carries here: a slot's index
// A drop, applied after the frame, when nothing drawn this frame reads the
// items any more: the slots from and to, or to the trash (-2).
var move_from = -1;
var move_to = -1;
let TRASH = -2;

// The ID of gem g's drawing: the same in whichever slot it is, and in the
// ghost under the pointer.
fn gem_id(g: i64) -> imgui::Id { imgui::sub_id(imgui::Id { 0x6E35A11 }, g) }
let GLIDE = imgui::spring(420, 30);

let POP = imgui::pop_out(1.8, imgui::tween(0.25));

// A gem of `kind`, `size` across, gliding to wherever it is drawn next;
// when it is drawn nowhere (thrown away), popping where it was.
fn gem(g: i64, kind: i64, size: f64, d: imgui::Desc) {
    let c = gfx2d::rgb(COLORS[kind]);
    imgui::panel(gem_id(g), d.size(size, size).radius(size * 0.5).bg(gfx2d::lighten(c, 0.2), c).glide(GLIDE).exit(POP));
}

fn apply_move() {
    guard move_from >= 0;
    if move_to == TRASH {
        items[move_from].kind = -1;
        items[move_from].count = 0;
        items[move_from].name = [];
    } else {
        let a = items[move_from];
        items[move_from] = items[move_to];
        items[move_to] = a;
        chosen = move_to;
    }
    move_from = -1;
    move_to = -1;
}

// A class of the program's own for the slots: faint, lighter when hovered,
// outlined in blue when chosen, ringed when focused.
fn slot_class() -> imgui::StyleClass {
    var s = imgui::style_set(imgui::Style { bg: gfx2d::rgba(0xFFFFFF, 0.05), border: gfx2d::rgba(0xFFFFFF, 0.08),
                                            border_width: 1.0, radius: imgui::radii(10.0), padding: imgui::radii(6.0) },
                             imgui::tween(0.12));
    s.hover.bg = gfx2d::rgba(0xFFFFFF, 0.1);
    s.active.zoom = 0.94;
    s.checked.bg = gfx2d::rgba(0x5B8CFF, 0.18);
    s.checked.border = gfx2d::rgb(0x5B8CFF);
    s.checked.border_width = 2.0;
    s.focused.ring = gfx2d::rgb(0xE9ECF1);
    s.focused.ring_width = 2.0;
    s.focused.ring_offset = 2.0;
    imgui::add_class(s)
}

fn main() {
    imgui::theme_dark();
    var r = rng { 42 };
    for k in 40 {
        let kind = rand_int(r, KINDS.len);
        var it = Item { kind: kind, count: rand_int(r, 20) + 1, gem: k, .. };
        format(it.name, KINDS[kind]);
        items.push(it);
    }
    let slot = slot_class();
    run("imgui: inventory", 860, 560, false) {
        gfx2d::frame(gfx2d::rgb(0x0F1115)) {
            imgui::frame(frame_dt()) {
                imgui::box("page", imgui::row().grow().padding(24).gap(20)) {
                    imgui::box("bag", imgui::column().skin(imgui::PANEL).gap(12).grow_h()) {
                        imgui::text("Bag", imgui::TITLE);
                        imgui::scroll("slots", imgui::grid(6).gap(8).padding(4, 4, 16, 4).grow_h()) {
                            for item, k in items {
                                let empty = item.kind < 0;
                                let d = imgui::stack().size(64, 64).skin(slot).look(imgui::checked_look(k == chosen));
                                // A slot is a box that takes clicks and focus, made
                                // here: a gem, and its count in the corner. It is
                                // a source of its gem and a target for others.
                                let it = imgui::interact(imgui::id(k), imgui::clickable(d));
                                let carried = !empty && imgui::drag_source(it, GEM, k);
                                let drop = imgui::drop_target(it, GEM);
                                if drop.dropped && drop.payload != k { move_from = drop.payload; move_to = k; }
                                // Lit while a gem is over it.
                                let dd = if drop.over { d.border(2, gfx2d::rgb(0xE9ECF1)) } else { d };
                                imgui::box(k, imgui::clickable(dd)) {
                                    // While carried, the gem is in the ghost; its
                                    // slot keeps a faint mark.
                                    if carried {
                                        imgui::panel(imgui::column().size(34, 34).radius(17).bg(gfx2d::rgba(0xFFFFFF, 0.06))
                                                     .place(imgui::CENTER, imgui::CENTER));
                                    } else if !empty {
                                        gem(item.gem, item.kind, 34, imgui::column().place(imgui::CENTER, imgui::CENTER));
                                        imgui::textf(imgui::column().text_size(13).place(imgui::END, imgui::END)) { out =>
                                            format(out, item.count);
                                        };
                                    }
                                };
                                if it.activated && !empty { chosen = k; }
                                if !empty && !imgui::dragging(GEM) {
                                    imgui::tooltip(it) {
                                        imgui::text(item.name);
                                        imgui::textf(imgui::column().skin(imgui::MUTED)) { out => format(out, "x", item.count); };
                                    };
                                }
                            }
                        };
                    };
                    // The gem carried, under the pointer, a little bigger: the
                    // same gem, so that let go, it glides from here.
                    imgui::drag_ghost(imgui::stack()) {
                        let g = items[imgui::drag_payload()];
                        gem(g.gem, g.kind, 40, imgui::column().shadow(gfx2d::rgba(0x000000, 0.5), 10, 0, 4)
                                                              .place(imgui::CENTER, imgui::CENTER));
                    };
                    let item = items[chosen];
                    imgui::box("side", imgui::column().width(240).gap(20)) {
                        imgui::box("details", imgui::column().skin(imgui::PANEL).grow_w().gap(10)) {
                            if item.kind >= 0 {
                                imgui::box(imgui::id(str("gem", chosen)), imgui::stack().size(96, 96).radius(48)
                                             .bg(gfx2d::lighten(gfx2d::rgb(COLORS[item.kind]), 0.15), gfx2d::rgb(COLORS[item.kind]))
                                             .enter(imgui::pop_in(0.6, imgui::spring(400, 18)))) {};
                                imgui::text(item.name, imgui::TITLE);
                                imgui::textf(imgui::column()) { out => format(out, "You have ", item.count, "."); };
                            } else {
                                imgui::text("Empty", imgui::TITLE);
                            }
                            imgui::text("Gems are traded at any town's market, or set into gear at a jeweler's.",
                                        imgui::column().wrap().grow_w().skin(imgui::MUTED));
                        };
                        // The trash: a target that takes gems, and empties their slots.
                        let tid = imgui::id("trash");
                        let td = imgui::column().skin(slot).grow_w().height(72).center();
                        let drop = imgui::drop_target(imgui::interact(tid, imgui::clickable(td)), GEM);
                        if drop.dropped { move_from = drop.payload; move_to = TRASH; }
                        imgui::box(tid, imgui::clickable(if drop.over { td.border(2, gfx2d::rgb(0xE0455A)) } else { td })) {
                            imgui::text(if imgui::dragging(GEM) { "Drop here to throw away" } else { "Trash" },
                                        imgui::column().skin(imgui::MUTED));
                        };
                    };
                };
            };
        };
        // What was dropped this frame moves now, after it is drawn.
        apply_move();
    };
}
