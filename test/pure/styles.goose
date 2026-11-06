// The built-in classes' states, no GPU. A state's look is its difference
// from normal, so a change made to normal and missed in a state shows up as
// that state changing something it never meant to. In every theme: no state
// changes a class's corners, padding, gap or minimum size; and being
// disabled changes only the alpha. Each listed if not, then a count.
import std;
import vec;
import gfx;
import gfx2d from "../../../goose_gfx2d";
import imgui from "../..";

fn same_shape(a: imgui::Style, b: imgui::Style) -> bool {
    a.radius == b.radius && a.padding == b.padding && a.gap == b.gap && a.min_size == b.min_size
}
fn only_alpha(n: imgui::Style, var d: imgui::Style) -> bool {
    d.alpha = n.alpha;
    d == n
}

fn check_theme(name: const u8[:]) {
    var bad = 0;
    for c in imgui::CLASS_COUNT {
        let set = imgui::class_style(imgui::StyleClass { c as u16 });
        fn shape(state: const u8[:], s: imgui::Style) {
            if !same_shape(set.normal, s) { print("  class ", c, " ", state, " changes its shape"); bad++; }
        }
        shape("hover", set.hover);
        shape("active", set.active);
        shape("focused", set.focused);
        shape("checked", set.checked);
        shape("disabled", set.disabled);
        if !only_alpha(set.normal, set.disabled) { print("  class ", c, " disabled changes more than alpha"); bad++; }
    }
    print(name, ": ", bad);
}

fn main() {
    // each_state reaches all six, and leaves the transition.
    var set = imgui::style_set(imgui::Style { .. }, imgui::tween(0.25));
    set.hover.gap = 3.0;
    imgui::each_state(set) { s => s.radius = imgui::radii(7.0); };
    print("each_state: ", set.normal.radius.x, " ", set.hover.radius.x, " ", set.active.radius.x, " ",
          set.focused.radius.x, " ", set.checked.radius.x, " ", set.disabled.radius.x,
          "; hover gap ", set.hover.gap, "; same transition ", set.transition == imgui::tween(0.25));

    check_theme("light");
    imgui::theme_dark();
    check_theme("dark");
    imgui::theme_dev();
    check_theme("dev");
    imgui::theme_dev_light();
    check_theme("dev light");
    imgui::theme_game();
    check_theme("game");
    imgui::theme_pixel(gfx2d::Font { 0 }, 6);
    check_theme("pixel");

    // States adding up: a radio pressed and focused keeps its corners, and
    // a dropdown its gap while its list is open.
    imgui::theme_light();
    let pressed = imgui::resolve_style(imgui::RADIO, imgui::LookState { press: 1.0, focus: 1.0, .. });
    print("radio radius ", imgui::class_style(imgui::RADIO).normal.radius.x, ", pressed and focused ", pressed.radius.x);
    let open = imgui::resolve_style(imgui::DROPDOWN, imgui::LookState { checked: 1.0, .. });
    print("dropdown gap ", imgui::class_style(imgui::DROPDOWN).normal.gap, ", open ", open.gap);
}
