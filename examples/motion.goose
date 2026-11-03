// Motion: a leaderboard whose rows glide to their new places when it is
// re-sorted, rows that slide in when added and fade out when removed, a
// drawer that springs open, and a counter that rolls to its value.
//
//   goose examples/motion.goose [-- --frames 120 --screenshot motion.png]
import std;
import vec;
import math;
import gfx;
import gfx2d from "../../goose_gfx2d";
import imgui from "..";
import .common;

struct Player { id: i64, name: u8[..16], score: i64, leaving: bool }

var players: Player[>..<] = [];
var next_id = 0;
var drawer = false;
var shown_total = 0.0;
var seed = rng { 7 };

fn add_player() {
    let names = ["Ada", "Brin", "Cass", "Dov", "Eli", "Fen", "Gus", "Hal", "Ivo", "Juno", "Kit", "Lux"];
    let n = names[next_id % names.len];
    players.push(Player { id: next_id, name: n, score: rand_int(seed, 900) + 100, leaving: false });
    next_id++;
}

fn sort_players() {
    // Insertion sort, highest score first.
    for i in 1..players.len {
        var j = i;
        while j > 0 && players[j - 1].score < players[j].score {
            let t = players[j];
            players[j] = players[j - 1];
            players[j - 1] = t;
            j--;
        }
    }
}

fn main() {
    imgui::theme_dark();
    for k in 6 { add_player(); }
    sort_players();
    let glide = imgui::spring(220, 24);
    run("imgui: motion", 900, 620, false) {
        gfx2d::frame(gfx2d::rgb(0x0F1115)) {
            imgui::frame(frame_dt()) {
                imgui::box("page", imgui::row().grow().padding(32).gap(24)) {
                    imgui::box("board", imgui::column().skin(imgui::PANEL).width(420).gap(8)) {
                        imgui::text("Leaderboard", imgui::TITLE);
                        imgui::box(imgui::row().gap(8)) {
                            if imgui::button("Shuffle scores") {
                                for &p in players { p.score = rand_int(seed, 900) + 100; }
                                sort_players();
                            }
                            if imgui::button("Add") { add_player(); sort_players(); }
                            if imgui::button("Remove") {
                                for &p in players { if !p.leaving { p.leaving = true; break; } }
                            }
                        };
                        var total = 0;
                        var rank = 0;
                        var k = 0;
                        while k < players.len {
                            let p = players[k];
                            // A leaving row fades out, then is gone.
                            let t, alive = imgui::presence(imgui::id(p.id), !p.leaving, imgui::tween(0.3));
                            if !alive {
                                players[k] = players[players.len - 1];
                                players.pop();
                                sort_players();
                                continue;
                            }
                            if !p.leaving { rank++; total += p.score; }
                            imgui::box(p.id, imgui::row().gap(12).padding(12, 8).grow_w().align(imgui::CENTER)
                                               .radius(8).bg(gfx2d::rgba(0xFFFFFF, 0.05))
                                               .glide(glide).opacity(t).scale(0.9 + 0.1 * t)
                                               .enter(imgui::slide_in(-40, 0, imgui::tween(0.35)))) {
                                imgui::textf(imgui::column().width(28).skin(imgui::MUTED)) { out => format(out, rank, "."); };
                                imgui::text(p.name, imgui::column().grow_w());
                                imgui::textf(imgui::column()) { out => format(out, p.score); };
                            };
                            k++;
                        }
                        shown_total = imgui::animate("total", total, imgui::tween(0.6));
                        imgui::textf(imgui::column().skin(imgui::MUTED)) { out =>
                            format(out, "Total ", round(shown_total) as i64);
                        };
                    };
                    imgui::box(imgui::column().gap(12)) {
                        imgui::toggle("Drawer", drawer);
                        // The drawer's width springs between closed and open; its
                        // content is clipped while it moves.
                        let w = imgui::animate("drawer", if drawer { 280.0 } else { 0.0 }, imgui::spring(300, 22));
                        imgui::box("drawer", imgui::column().skin(imgui::PANEL).width(max(w, 0.0)).height(300).clip()
                                               .padding(if w > 1.0 { 16.0 } else { 0.0 })) {
                            imgui::box(imgui::column().width(248).gap(10)) {
                                imgui::text("Inventory", imgui::TITLE);
                                imgui::text("A drawer that opens on a spring, overshooting a little.",
                                            imgui::column().wrap().grow_w());
                                imgui::progress(min(w / 280.0, 1.0));
                            };
                        };
                    };
                };
            };
        };
    };
}
