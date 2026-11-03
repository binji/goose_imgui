# imgui

An immediate-mode GUI for Goose games, drawn through goose_gfx2d. This is
the reference: what there is and how to call it. Then how it is built,
tested and measured. [design.md](design.md) has the reasoning;
[future_work.md](future_work.md) has what is next.

## Using it

```goose
import gfx;
import gfx2d from "../goose_gfx2d";         // the program declares gfx2d
import imgui from "../goose_imgui";

var music: f64 = 0.7;

fn main() {
    gfx::open("game", 1280, 720, gfx::WINDOW_RESIZABLE);
    imgui::theme_game();
    while gfx::frame() {
        gfx2d::frame(gfx2d::rgb(0x0B1020)) {
            imgui::frame() {
                imgui::box("pause", imgui::column().skin(imgui::PANEL).width(360).align(imgui::STRETCH)
                                      .place(imgui::CENTER, imgui::CENTER)) {
                    imgui::text("Paused", imgui::TITLE);
                    if imgui::button("Resume") { /* … */ }
                    imgui::slider("Music", music, 0, 1, 0.05, imgui::row().grow_w());
                    if imgui::button("Quit") { gfx::quit(); }
                };
            };
        };
    }
}
```

**Conventions**
* **Units:** pixels with y down, under gfx2d's base scale
  (`gfx2d::set_scale`). `input_from_gfx` divides the mouse by that scale.
* **Scalar parameters are `f64`**, as in gfx2d, so integers and floats of
  either width all pass. Layout, styles and motion keep `f32`.
* **Namespace:** everything is `imgui::name`.
* **Blocks:** containers take a trailing block, `box(…) { … };`, as gfx2d's
  scopes do. A block can't be an `if` condition, so a container that shows
  its children only sometimes (a tab, a menu, a popup) decides inside
  itself whether to run its block.
* **Results come at once.** Input is tested against where things were
  drawn the frame before, using the pointer where it is now. So
  `button(…)` returns `true` the frame it is clicked.
* **Errors:** misuse, such as a `tab` outside `tabs`, is printed when it
  happens and aborts at `end_frame`, as gfx and gfx2d do.

The examples each show one part:
- `hello`: a box, text and a button;
- `widgets`: the basic widgets in a settings panel;
- `main_menu`: a title screen in the game theme, with staggered entrances,
  keyboard navigation and modals;
- `motion`: a leaderboard whose rows glide when re-sorted, and slide in or
  fade out when added or removed; a drawer on a spring; a rolling counter;
- `inventory`: a grid of custom slots in a scroll pane, with tooltips and
  a class of the program's own;
- `settings`: a menu bar, tabs, dropdowns, a text field and a modal.

Each takes `-- --frames N --screenshot file.png --theme light|dark|game
--keys Down,Return`. With `--frames`, every frame is 1/60 s.

## The frame

| | |
|---|---|
| `frame() { … }` | a frame: gfx's input and frame time; recorded by the block, laid out, and drawn (when inside a gfx2d frame) |
| `frame(dt) { … }` | the same, `dt` seconds after the last: a fixed step for recording |
| `frame(input, dt) { … }` | with an `Input` the program made (tests, replays, gamepads) |
| `begin_frame(input, dt)`, `end_frame()`, `draw()` | the parts: `draw` inside a gfx2d frame, after `end_frame` |
| `input_from_gfx() -> Input` | gfx's mouse and keyboard, and the ordered events for typed text and the clipboard |
| `nav_from_pad(input, PadState)` | a gamepad's held buttons and stick, as navigation, with repeat (gfx v1 has no gamepads; a program reading one passes what it holds) |
| `set_viewport(rect)` | the UI's area; by default the screen, under gfx2d's scale |
| `wants_pointer()`, `wants_keyboard()` | whether the UI took the pointer (it is over the UI, or holds a press) or the keyboard (a text field has focus) this frame |
| `cancelled()` | Escape or B pressed with no popup open to close: for the game's own "back" |
| `time()`, `dt()` | imgui's clock |
| `rect_of(id)`, `state_of(id)`, `dump()` | where a widget was laid out; its kept state; the tree, for tests |

`Input` holds:
- `pointer`: `pos`, `down`, `pressed`, `released`, `clicks`, `wheel`;
- `nav`: `up`, `down`, `left`, `right`, `next`, `prev`, `accept`,
  `cancel`, `tab_left`, `tab_right`, each pressed this frame;
- `text`: typed this frame;
- `keys`: editing keys (`KEY_LEFT` … `KEY_PASTE`, with `shift` and `word`);
- `viewport`.

## Boxes and layout

Every node is described by a `Desc`, built by chaining setters on one of
the starting points.

| Starting points | |
|---|---|
| `row()`, `column()` | flex: children along x, along y |
| `stack()` | children over each other, each placed by its `place(h, v)`; the frame's root is one |
| `grid(n)`, `grid([px(64), grow(), fit()])` | columns of tracks; children go along the rows, or where `cell` puts them; they stretch to their cells |

| Layout | |
|---|---|
| `gap(v)`, `gap(x, y)` | between children; a grid's or a wrapping row's columns and rows |
| `padding(all)`, `padding(x, y)`, `padding(l, t, r, b)` | |
| `justify(START, CENTER, END, SPACE_BETWEEN, SPACE_AROUND, SPACE_EVENLY)` | along the main axis |
| `align(START, CENTER, END, STRETCH)`, `center()` | across it; `center()` is both |
| `self_align(a)`, `place(h, v)` | a child's own: across its parent; in a stack, both ways |
| `wrap()` | a row onto more lines; text at spaces to fit its width |
| `columns(ts)`, `rows(ts)`, `cell(col, row)`, `span(cols, rows)` | grids: up to 8 tracks given each way; rows past those fit their content |
| `absolute(x, y)` | out of the flow, at (x, y) in the parent's inner box, not scrolled |

| Sizes | |
|---|---|
| `width(v)`, `height(v)`, `size(w, h)` | pixels |
| `width(Size)`: `fit()`, `px(v)`, `grow()`, `grow(weight)`, `pct(f)` | the content's size (the default); pixels; the content's and a share of what is left; a fraction of the parent's inner size |
| `grow()`, `grow_w()`, `grow_h()` | |
| `min_w`, `max_w`, `min_h`, `max_h` | limits on any of them |

How children share space:
- Along a row or column, each child starts at its base size. What is left
  is shared among the growing children by weight. What is missing is taken
  from the children that can shrink, in proportion to how far they can.
- Children sized in px and pct don't shrink. A fit child shrinks no further
  than its content's least size: wrapped text's longest word, a scroll
  pane's padding.
- Across, a child is its content's size but no bigger than the room. It
  fills the room if it grows, or if its alignment is STRETCH.

| Containers and leaves | |
|---|---|
| `box(d) { … }`, `box(label, d) { … }`, `box(key, d) { … }`, `box(id, d) { … }` | a box and its children; returns its `Interaction`. A label, integer key or `Id` names it: its ID scopes the labels inside it, and it keeps state between frames |
| `panel(d)`, `panel(id, d)` | a box with no children |
| `spacer()`, `spacer(d)` | empty space; by default it grows |
| `text(s)`, `text(s, d)`, `text(s, CLASS)` | text in the inherited ink, font and size, or its Desc's |
| `textf(d) { out => format(out, …); }` | text formatted straight into the frame's text, without a `str` first |
| `image(texture, d, fit_mode)`, `image(texture, src, d, fit_mode)` | an image, or a sprite from a sheet; fitted by `gfx2d::FIT_CONTAIN`, `COVER` or `STRETCH` |
| `icon(ICON_CHECK …)`, `icon(kind, d)` | line icons in the ink: check, chevrons, close, plus, minus |

## Looks

| Inline, on a Desc | |
|---|---|
| `skin(CLASS)` | the class's look: the StyleSet for each state |
| `bg(c)`, `bg(top, bottom)`, `bg_h(left, right)` | a color, or a two-color gradient |
| `border(w, c)`, `radius(r)`, `radius(float4)` | inside the box; corners top left, top right, bottom right, bottom left |
| `shadow(c, blur, dx, dy)` | a box shadow |
| `ink(c)`, `text_size(s)`, `font(f)` | the node's text, and its text descendants' |
| `opacity(o)` | multiplied into its colors and its subtree's |
| `isolate()` | the subtree drawn into a gfx2d layer and composited at its opacity, so overlaps inside it don't show through (a pass more) |
| `clip()` | children clipped to its rounded box |
| `look(LookState)` | the state amounts its class's styles are mixed by: hover, press, focus, checked (0 to 1), disabled |

A `Style` has:
- `bg`, `bg2` and `gradient`;
- `border` and `border_width`;
- `radius`;
- `shadow`;
- `padding`;
- `ink`, `font` and `text_size` (which text inherits);
- `slice` and `slice_tint`: a nine-slice from `add_nine_slice(texture, src,
  insets)`;
- `alpha`, `offset` and `zoom`: a state's motion, such as a pressed button
  sinking;
- `ring`, `ring_width` and `ring_offset`: the focus ring;
- `min_size`, and `gap` (between a widget's parts).

A `StyleSet` has one Style for each state (`normal`, `hover`, `active`,
`focused`, `checked`, `disabled`) and a `transition` Motion for the
amounts. It is made with `style_set(normal, transition)` and changed
state by state.
- A node's look is its class's normal style, plus each state's difference
  from normal, scaled by the state's amount.
- So a checked box hovered keeps its checked fill and gains its hover
  border.
- Focus counts only while it shows, after navigation.

| Themes and classes | |
|---|---|
| `theme_light()`, `theme_dark()`, `theme_game()` | the built-in themes; the light one is in place from the start |
| `theme(Palette { … })` | every built-in class from a palette: surface, raised, hover, pressed, line, ink, muted, accent and their sizes |
| `class_style(C)`, `set_class(C, set)` | read and replace a class |
| `add_class(set) -> StyleClass` | a class of the program's own (kept across theme changes) |

The classes are:
- PANEL, BUTTON, LABEL, TITLE, MUTED, CHOICE;
- CHECKBOX, CHECK, TOGGLE, TOGGLE_KNOB, RADIO, RADIO_DOT;
- SLIDER_TRACK, SLIDER_FILL, SLIDER_THUMB, PROGRESS_TRACK, PROGRESS_FILL;
- SEPARATOR, SELECTABLE, SCROLLBAR, SCROLL_THUMB;
- TAB_BAR, TAB, TAB_PANEL, MENU_BAR, MENU_HEADER, MENU, MENU_ITEM;
- POPUP, MODAL, BACKDROP, TOOLTIP;
- INPUT, CARET, SELECTION, DROPDOWN.

## Motion

A `Motion` is `INSTANT`, `tween(seconds, EASE_*)` or `spring(stiffness,
damping)`, with or without `delay(seconds)`.
- The eases are LINEAR, IN/OUT/IN_OUT of QUAD and CUBIC, OUT_BACK,
  OUT_EXPO, IN_OUT_SINE and OUT_ELASTIC.
- Springs step at a fixed 1/240 s, so they move the same at any frame
  rate.

| | |
|---|---|
| `animate(key, target, m)` | a value (`f64`, `float2`, `Color`) kept by key, moving toward its target; retargeting is smooth |
| `animate_from(key, from, target, m)` | starting from `from` the first time |
| `presence(key, visible, m) -> t, alive` | `t` from 0 to 1 while visible, and back after; `alive` until it has gone, so the program keeps drawing what is leaving |
| `presence(key, visible, m) { t => … }` | the block, while alive |
| `.enter(fade_in(m))`, `slide_in(dx, dy, m)`, `pop_in(scale, m)`, `.delay(s)` | played the first frame a node's ID appears; a list staggered by `delay` |
| `.glide(m)` | from where the node was laid out to where it is now: reordered rows slide to their places |
| `.offset(x, y)`, `.scale(s)` | drawn moved, or scaled about its center, with its subtree |

## Widgets

| | |
|---|---|
| `button(label[, d]) -> bool`, `button_with(label, d) { … } -> bool` | clicked or accepted; the second with any content |
| `checkbox(label, v[, d])`, `toggle(label, v[, d])` | true the frame `v` changes |
| `radio(label, selected, value[, d])` | `selected` becomes `value` |
| `slider(label, v, lo, hi, step[, d])` | `f64`, `f32`, `i64`, `i32`; dragged, clicked along, or left/right while focused |
| `progress(value[, d])` | a bar from 0 to 1 |
| `selectable(label, selected[, d])` | a list row |
| `separator()` | across a column, or up a row |
| `scroll(label, d, axes) { … } -> ScrollInfo` | a clipped pane, scrolled by the wheel, its thumb, or the focus |
| `tabs(label, selected, d) { tab("A") { … }; … }` | tab headers and the selected one's content (which fades in by TAB_PANEL's transition); the shoulder buttons switch |
| `menu_bar(label) { menu("File") { menu_item("Open", "Ctrl+O"); menu("Recent") { … }; }; }` | drop-down menus; hovering moves between open menus and opens submenus; `menu_check` |
| `dropdown(label, items, selected[, d])` | one of `items`, in a popup list under it |
| `open_popup(label)`, `popup(label, d) { … }`, `close_popup`, `close_current_popup` | a popup at the pointer |
| `modal(label, open, d) { … }` | centered over a backdrop while `open`; inert below; cancel sets `open` false |
| `tooltip(it, s)`, `tooltip(it) { … }` | under a widget the pointer rests on, or the focus is on |
| `text_input(label, buf, d, max_len, placeholder) -> TextEdit` | one line, edited in place: a `u8[>..]` or a `u8[..N]` |

A label's `##` and what follows it are part of the ID but not shown:
`"Play##dlc"`.

## Making widgets

Every widget is made of the parts above:

```goose
fn slot(k: i64, item: Item, chosen: bool) -> bool {
    let it = imgui::box(k, imgui::clickable(imgui::stack().size(64, 64).skin(SLOT)
                                            .look(imgui::checked_look(chosen)))) {
        imgui::image(item.icon, imgui::column().size(40, 40).place(imgui::CENTER, imgui::CENTER));
        imgui::textf(imgui::column().place(imgui::END, imgui::END)) { out => format(out, item.count); };
    };
    imgui::tooltip(it, item.name);
    it.activated
}
```

| | |
|---|---|
| `clickable(d)`, `.hit()`, `.focusable()` | take the pointer, take the focus |
| `.blocks()`, `.nav_skip()`, `.disabled(on)`, `.keep()` | stop the pointer; leave out of navigation; disable; keep state without a label |
| `with_bits(CAPTURE_X)` | left and right go to the widget while it is focused (`it.nav.x`) |
| `interact(id, d) -> Interaction` | the interaction a widget recorded with `id` and `d` will have, asked before recording it so its look can follow |
| `look_of(it)`, `checked_look(on)` | the look state of an interaction, or of on/off |
| `id(label)`, `id(key)`, `sub_id(id, part)`, `id_scope(…) { … }` | IDs |

`Interaction` holds:
- `hovered`, `held`, `pressed`, `released`, `clicked`, `double_clicked`;
- `focused`, and `activated` (clicked, or accepted while focused);
- `dragging` and `drag`;
- `pointer` (from the rect), `rect` (last frame's, on the screen), and
  `nav` (captured presses);
- the eased amounts `hover_t`, `press_t`, `focus_t` and `checked_t`.

## Navigation

- **Focus.** `focus(id)`, `blur()`, `is_focused(id)`, `focused_id()`.
  `default_focus(id)` is where navigation starts.
- **Scopes.** `nav_scope(label, NAV_TRAP | NAV_WRAP) { … }`.
- **Moving.**
  - The arrows (and a pad's d-pad and stick) move to the nearest widget
    that way, preferring ones in line with the focused one.
  - Tab and Shift+Tab go in recorded order.
  - Enter, Space or A accepts.
  - Escape or B closes the top popup, or is the program's `cancelled()`.
- **Popups.** An open popup or modal keeps the focus in it, takes it as
  soon as it opens (while focus shows), and gives it back to its opener
  when it closes.
- **Scrolling and the ring.** Focus moved by navigation scrolls its panes
  to keep it in view. The focus ring shows only after navigation.

## How it works

Each frame records a flat array of nodes in pre-order, linked by index to
parents, children and siblings. Text is copied into a per-frame arena.

At `end_frame` the solver lays the array out in passes, none recursive:
1. fit widths (last node first);
2. resolve widths (first node first);
3. measure wrapped text;
4. fit heights;
5. resolve heights;
6. positions.

Then motion is applied, and each node's screen rect, clip and bounds are
found. The hit list and the focus list for the next frame are written in
draw order: root by root (popups after the main tree), each in the order
it was recorded.

`draw()` walks each root depth first through gfx2d. Clipping boxes are
gfx2d clip blocks, motion is a transform block, and isolated subtrees are
layers. Subtrees outside the clip they are in are not drawn.

State that lasts goes in two dictionaries keyed by ID, `WidgetState` and
`AnimState`. Entries not seen for 120 frames are dropped.

Two Goose rules shaped the code:
- **Shrinking a growable `u8` global.** A program's loop over string
  literals may not call a function that can shrink one. So the misuse and
  clipboard buffers are limited arrays, and the default theme is built by
  a global's initializer rather than on first use.
- **Fixed-size buffers.** A `u8[..N]` is fixed-size and would be copied
  into an untyped parameter, so `text_input` takes its buffer as `A&`.

## Testing

```bash
python test/run_tests.py --goose path/to/goose [--update] [name ...]
```

The tests are in three groups:
- **`test/pure/`** (no GPU) drive frames with made-up input and print what
  comes back:
  - `layout`: rows, columns, grow, shrink, justify, align, wrap, grids,
    stacks, absolute;
  - `interact`: clicks, checkboxes, sliders, radios, navigation;
  - `overlays`: menus, submenus, tabs, dropdowns, tooltips, modals;
  - `motion`: easing, tweens, springs at two frame rates, presence, enter,
    glide;
  - `scroll`: the wheel, clamping, scrolling to the focus, the thumb;
  - `text_input`: typing, caret and selection, words, cut and paste,
    limits.
- **`test/headless/`** draws and reads back: fills, borders, corners,
  gradients, opacity, isolation, clipping, motion, nine-slices, the focus
  ring.
- **Expected output** is in `test/expected/<dir>_<name>.out`. A headless
  test with no GPU is reported skipped.

**Platforms tested:** Windows 11 with D3D12, and Arch Linux in WSL2 with
Vulkan through Mesa's dzn: the tests, and every example, headless.

## Benchmark

`bench/bench.goose` times record, layout and draw for a scroll pane of
widget rows. [bench/results.md](../bench/results.md) has the numbers. At
250 rows (3,754 nodes), AOT takes 0.6 ms to record, 0.26 ms to lay out and
2.25 ms to draw.
