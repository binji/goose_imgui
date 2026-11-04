# goose_imgui

An immediate-mode GUI for the [Goose](https://github.com/aardappel/goose)
programming language, made for the UIs of games: title screens, pause
menus, settings, inventories, HUDs and dialogs. It is drawn through
[goose_gfx2d](https://github.com/binji/goose_gfx2d) and takes its input from
[goose_gfx](https://github.com/aardappel/goose_gfx).

- **Immediate mode.** The UI is ordinary code, run every frame:
  `if imgui::button("Play") { start(); }`.
- **Layout.** Rows and columns with gap, padding, justify, align, grow and
  wrap, as in CSS flexbox. Grids of fixed, fractional and fit-to-content
  tracks. Stacks and absolute placement. Popups anchored to widgets.
- **Looks.** Every widget's look is data in a theme: colors, gradients,
  borders, corner radii, shadows, nine-slice images and fonts, for each
  state (hover, held, focused, checked, disabled). The built-in widgets are
  made of the same public parts a program can use to make its own.
- **Motion.** Items can fade, slide or pop in, and glide to new places
  when the layout changes. Looks ease between states. Any value can be
  animated with a tween or a spring. All of it is optional: everything
  defaults to instant.
- **Canvases.** Charts, meters and minimaps are drawn in the layout, in a
  box's own pixels, under its clip and motion.
- **Gamepad and keyboard.** Widgets take focus and can be moved between
  with the arrows (or a d-pad, through `nav_from_pad`) and Tab. They are
  used with Enter or A and backed out of with Escape or B. Focus is kept
  inside modals and menus.

**Status:** the first set of widgets, layout, themes and motion are done.
[docs/imgui.md](docs/imgui.md) is the reference,
[docs/design.md](docs/design.md) the plan and its reasoning, and
[docs/future_work.md](docs/future_work.md) what is next.

## Using it

```goose
import gfx;
import gfx2d from "../goose_gfx2d";
import imgui from "../goose_imgui";

var volume: f64 = 0.8;

fn main() {
    gfx::open("game", 1280, 720);
    while gfx::frame() {
        gfx2d::frame(gfx2d::rgb(0x101418)) {
            imgui::frame() {
                imgui::box("pause", imgui::column().skin(imgui::PANEL).gap(12)
                                      .place(imgui::CENTER, imgui::CENTER)) {
                    imgui::text("Paused", imgui::TITLE);
                    if imgui::button("Resume") { /* … */ }
                    imgui::slider("Volume", volume, 0, 1);
                    if imgui::button("Quit") { gfx::quit(); }
                };
            };
        };
    }
}
```

## Layout

| | |
|---|---|
| `imgui.goose` | the entry: the frame, and the step after layout |
| `desc.goose` | `Desc`, what a node is, and its setters |
| `tree.goose` | the frame's nodes: boxes, text, images, icons, roots |
| `layout.goose` | the layout solver |
| `style.goose` | styles, style sets, the class registry, themes |
| `motion.goose` | tweens, springs, `animate`, `presence` |
| `input.goose` | `Input`, `input_from_gfx`, hit testing, interactions |
| `nav.goose` | focus and navigation |
| `draw.goose` | drawing the frame through gfx2d |
| `widgets.goose`, `scroll.goose`, `popup.goose`, `text_input.goose` | the widgets |
| `canvas.goose` | canvases: drawing of the program's own inside the layout |
| `context.goose`, `id.goose` | the state kept between frames; IDs |
| `docs/` | `imgui.md`, the reference; `design.md`, the plan and its reasoning; `future_work.md`, what is next |
| `bench/` | `bench.goose`, and the latest `results.md` |
| `examples/` | `hello`, `widgets`, `main_menu`, `motion`, `inventory`, `settings`, `stats`, `hud`: programs using the package, each a root file |
| `test/run_tests.py` | runs `test/pure/` (no GPU) and `test/headless/` (drawn and read back), comparing with `test/expected/` |

All the modules are in `namespace imgui`.

## Testing

```bash
python test/run_tests.py --goose path/to/goose      # or GOOSE=..., or goose on the PATH
goose examples/widgets.goose                          # a window
```

The examples and tests find goose_gfx2d as a sibling checkout
(`../goose_gfx2d`).

## License

Apache License 2.0, as Goose, goose_gfx and goose_gfx2d.
