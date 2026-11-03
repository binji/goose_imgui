// An inventory: a grid of slots in a scroll pane, each a button with its
// own drawing (a colored gem, a count); a tooltip on the one under the
// pointer (or focus); the chosen one's details beside it. The arrows move
// across the grid, and the pane scrolls to keep the focus in view.
//
//   goose examples/inventory.goose [-- --frames 60 --screenshot inventory.png]
import std;
import vec;
import math;
import gfx;
import gfx2d from "../../goose_gfx2d";
import imgui from "..";
import .common;

struct Item { name: u8[..20], kind: i64, count: i64 }

let KINDS = ["Ruby", "Sapphire", "Emerald", "Topaz", "Amethyst", "Pearl"];
let COLORS = [0xE0455A, 0x3D7DE0, 0x2EBE7A, 0xF2B53C, 0x9C5BE0, 0xE8E4DA];

var items: Item[>..] = [];
var chosen = 0;

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
        var it = Item { kind: kind, count: rand_int(r, 20) + 1, .. };
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
                                let d = imgui::stack().size(64, 64).skin(slot).look(imgui::checked_look(k == chosen));
                                let c = gfx2d::rgb(COLORS[item.kind]);
                                // A slot is a box that takes clicks and focus, made
                                // here: a gem, and its count in the corner.
                                let it = imgui::box(k, imgui::clickable(d)) {
                                    imgui::panel(imgui::column().size(34, 34).radius(17).bg(gfx2d::lighten(c, 0.2), c)
                                                 .place(imgui::CENTER, imgui::CENTER));
                                    imgui::textf(imgui::column().text_size(13).place(imgui::END, imgui::END)) { out =>
                                        format(out, item.count);
                                    };
                                };
                                if it.activated { chosen = k; }
                                imgui::tooltip(it) {
                                    imgui::text(item.name);
                                    imgui::textf(imgui::column().skin(imgui::MUTED)) { out => format(out, "x", item.count); };
                                };
                            }
                        };
                    };
                    let item = items[chosen];
                    imgui::box("details", imgui::column().skin(imgui::PANEL).width(240).gap(10)) {
                        imgui::box(imgui::id(str("gem", chosen)), imgui::stack().size(96, 96).radius(48)
                                     .bg(gfx2d::lighten(gfx2d::rgb(COLORS[item.kind]), 0.15), gfx2d::rgb(COLORS[item.kind]))
                                     .enter(imgui::pop_in(0.6, imgui::spring(400, 18)))) {};
                        imgui::text(item.name, imgui::TITLE);
                        imgui::textf(imgui::column()) { out => format(out, "You have ", item.count, "."); };
                        imgui::text("Gems are traded at any town's market, or set into gear at a jeweler's.",
                                    imgui::column().wrap().grow_w().skin(imgui::MUTED));
                    };
                };
            };
        };
    };
}
