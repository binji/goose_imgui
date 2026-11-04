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
  (`gfx2d::set_scale`) and imgui's own (`imgui::set_scale`, or the
  `IMGUI_SCALE` environment variable). `input_from_gfx` divides the mouse
  by both. On a high-density screen, set the scale to the display's (gfx
  can't tell imgui what it is yet).
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
- `settings`: a menu bar, tabs, dropdowns, a text field, a scrolling
  list of key bindings, and a modal;
- `stats`: a run's summary on canvases: a line chart with values on hover,
  bars that grow in, a gauge, a minimap, each filling a grid card.

Each takes `-- --frames N --screenshot file.png --theme light|dark|game
--scale 2 --keys Down,Return`. With `--frames`, every frame is 1/60 s.

## The frame

| | |
|---|---|
| `frame() { … }` | a frame: gfx's input and frame time; recorded by the block, laid out, and drawn (when inside a gfx2d frame) |
| `frame(dt) { … }` | the same, `dt` seconds after the last: a fixed step for recording |
| `frame(input, dt) { … }` | with an `Input` the program made (tests, replays, gamepads), or one from `input_from_gfx` it changed; for the latter the frame still turns gfx's text input on while a field has the keyboard, and hands copied text to the clipboard |
| `begin_frame(input, dt)`, `end_frame()`, `draw()` | the parts: `draw` inside a gfx2d frame, after `end_frame` |
| `input_from_gfx() -> Input` | gfx's mouse and keyboard, and the ordered events for typed text and the clipboard |
| `nav_from_pad(input, PadState)` | a gamepad's held buttons and stick, as navigation, with repeat (gfx v1 has no gamepads; a program reading one passes what it holds) |
| `set_viewport(rect)` | the UI's area; by default the screen, under the scales |
| `set_scale(s)` | the UI drawn `s` times as big: 2 for a high-density screen; starts at `IMGUI_SCALE` |
| `edge_clamp(p, inset)`, `edge_clamp(p, rect)` | where to put a marker for p: p, if it is in the viewport inset by `inset` (or in `rect`); else where the line from the center to p leaves it. Also the angle to p, and whether it is in |
| `wants_pointer()`, `wants_keyboard()` | whether the UI took the pointer (it is over something that takes it or has a background, not in a `passthrough()` box, or holds a press) or the keyboard (a text field has focus) this frame |
| `cancelled()` | Escape or B pressed with no popup open to close: for the game's own "back" |
| `shortcut("Ctrl+Q")` | a key pressed with modifiers this frame: Ctrl (Cmd on a Mac), Shift, Alt, and a letter or digit. A `menu_item`'s shortcut text is only shown; this acts on it |
| `time()`, `dt()` | imgui's clock |
| `rect_of(id)`, `state_of(id)`, `dump()` | where a widget was laid out; its kept state; the tree, for tests |

`Input` holds:
- `pointer`: `pos`, `down`, `pressed`, `released`, `clicks`, `wheel`;
- `nav`: `up`, `down`, `left`, `right`, `next`, `prev`, `accept`,
  `cancel`, `tab_left`, `tab_right`, each pressed this frame;
- `text`: typed this frame;
- `keys`: editing keys (`KEY_LEFT` … `KEY_PASTE`, with `shift` and `word`);
- `chords`: keys pressed with Ctrl, Alt or Cmd, for `shortcut`;
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
| `pivot(px, py)` | an absolute node's own point put at (x, y), as fractions of its size: (0.5, 1) is its bottom center, for a bar over a character's head |

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
| `letter_spacing(px)` | pixels after each character, inherited the same way |
| `text_outline(w, c)`, `no_text_outline()` | an outline `w` pixels wide around the glyphs (up to a sixteenth of the text's size), inherited; for text over a busy scene. Faded, `isolate()` keeps it from showing through the glyphs |
| `text_shadow(c, dx, dy)`, `no_text_shadow()` | a copy of the text and its outline, moved, under it; inherited |

A Desc with text effects set during a frame is good for that frame only.
One made outside any frame, and kept, is good for any frame.
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
- `text_look`: a `TextLook` from `add_text_look(TextLook { … })`: letter
  spacing, an outline and its color, a shadow and its offset. Text inherits
  each part unless the look sets it. A spacing or outline of 0, or a
  transparent shadow, is unset. An outline < 0, or a shadow moved by
  (0, 0), is none;
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
| `screen_color()` | the theme's color for the screen behind the UI, for a menu screen to clear to, so that it changes with the theme |
| `class_style(C)`, `set_class(C, set)` | read and replace a class |
| `add_class(set) -> StyleClass` | a class of the program's own (kept across theme changes) |

The classes are:
- PANEL, BUTTON, LABEL, TITLE, MUTED, CHOICE;
- CHECKBOX, CHECK, TOGGLE, TOGGLE_KNOB, RADIO, RADIO_DOT;
- SLIDER_TRACK, SLIDER_FILL, SLIDER_THUMB, PROGRESS_TRACK, PROGRESS_FILL;
- METER (its gap is between segments), METER_TRACK, METER_FILL, METER_TRAIL;
- FOCUS_CURSOR, for `set_focus_cursor`;
  a `Meter` can name other classes for its parts, so that health is red and
  stamina green;
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
| `.rotate(radians)`, `.skew(radians)` | drawn turned clockwise about its center, or slanted (its verticals leaning right), with its subtree: a fanned hand of cards, a diamond, a slanted panel. It is hit where it is drawn; its `it.pointer` is from the box around it |

## Widgets

| | |
|---|---|
| `button(label[, d]) -> bool`, `button_with(label, d) { … } -> bool` | clicked or accepted; the second with any content |
| `checkbox(label, v[, d])`, `toggle(label, v[, d])` | true the frame `v` changes |
| `radio(label, selected, value[, d])` | `selected` becomes `value` |
| `slider(label, v, lo, hi, step[, d])` | `f64`, `f32`, `i64`, `i32`; dragged, clicked along, or left/right while focused |
| `progress(value[, d])` | a bar from 0 to 1 |
| `meter(label, value[, d][, m])` | a bar from 0 to 1 for health, stamina or a boss: `Meter { vertical, segments, trail, … }`; a trail (a Motion) eases down after a drop, showing what it took |
| `radial_meter(label, value[, d][, m])` | the same round a circle from the top, clockwise: a ring `m.thickness` wide, or a sweep (for a cooldown over an icon) |
| `selectable(label, selected[, d])` | a list row |
| `separator()` | across a column, or up a row |
| `scroll(label, d, axes) { … } -> ScrollInfo` | a clipped pane, scrolled by the wheel, its thumb, or the focus |
| `tabs(label, selected, d) { tab("A") { … }; … }` | tab headers and the selected one's content (which fades in by TAB_PANEL's transition); the shoulder buttons switch; the content is spaced by TAB_PANEL's `gap` |
| `menu_bar(label) { menu("File") { menu_item("Open", "Ctrl+O"); menu("Recent") { … }; }; }` | drop-down menus; hovering moves between open menus and opens submenus; `menu_check` |
| `dropdown(label, items, selected[, d])` | one of `items`, in a popup list under it |
| `open_popup(label)`, `popup(label, d) { … }`, `close_popup`, `close_current_popup` | a popup at the pointer |
| `modal(label, open, d) { … }` | centered over a backdrop while `open`; inert below; cancel sets `open` false |
| `tooltip(it, s)`, `tooltip(it) { … }` | under a widget the pointer rests on, or the focus is on |
| `drag_source(it, kind, payload) -> bool`, `drop_target(it, kind) -> Drop`, `drag_ghost(d) { … }` | drag and drop: a widget's payload (an `i64`) carried to a target that takes its `kind`, picked up by dragging it (or accepting it with the keys, carried by navigation, put down by accepting); `Drop { over, dropped, payload }`; the ghost drawn under the pointer, never in its way. Escape puts it back. `dragging(kind)`, `drag_payload()` |
| `text_input(label, buf, d, max_len, placeholder) -> TextEdit` | one line, edited in place: a `u8[>..]` or a `u8[..N]` |

A label's `##` and what follows it are part of the ID but not shown:
`"Play##dlc"`.

## Canvases

A canvas is a box whose block draws, for charts, meters, minimaps and
portraits' frames:

```goose
let it = imgui::canvas("score", imgui::column().grow().hit()) { size =>
    imgui::fill_polygon(area, gfx2d::with_alpha(accent, 0.2));
    imgui::stroke_polyline(line, 2.5, accent);
};
if it.hovered { imgui::tooltip(it) { imgui::text(value_at(it.pointer.x / it.rect.w)); }; }
```

How a canvas works:
- **Coordinates.** It draws in its inner box's pixels, from (0, 0) at the
  top left.
- **Size.** The block is given the box's inner size as it was laid out last
  frame (on the first frame, its px size if it has one). So a chart fills
  whatever room the layout gives it.
- **Recording.** The calls are recorded as commands and replayed at draw
  time, over the box's background and under its children, with its clip,
  motion and opacity.
- **Interaction.** `canvas` returns the box's `Interaction`. For a `hit()`
  canvas, `it.pointer` says where the pointer is on it.
- **Culling.** Drawing may reach past the box unless the box `clip()`s, and
  the culling counts what it reaches.

| In a canvas's block | |
|---|---|
| `fill_rect(x, y, w, h[, radius], c)`, `stroke_rect(x, y, w, h, width, c[, radius])` | |
| `gradient_rect(x, y, w, h, c0, c1, vertical, radius)` | |
| `fill_circle(cx, cy, r, c)`, `stroke_circle(cx, cy, r, width, c)` | |
| `draw_line(x0, y0, x1, y1, width, c)` | round caps |
| `stroke_arc(cx, cy, r, a0, a1, width, c)`, `fill_pie(cx, cy, r, a0, a1, c)` | radians, clockwise from +x |
| `stroke_polyline(points, width, c)`, `fill_polygon(points, c)` | `float2` points |
| `draw_text(x, y, s, size, c, align, baseline)`, `measure(s, size)` | in the canvas's inherited font; `gfx2d::ALIGN_*`, `BASELINE_*` |
| `draw_image(texture[, src], x, y, w, h, tint)` | |
| `rotate(a[, cx, cy]) { … }`, `translate(x, y) { … }`, `scale(s) { … }`, `transform(m) { … }` | the calls in the block, turned (about (0, 0) or (cx, cy)), moved, scaled or by any `gfx2d::Affine`: a needle, a minimap that turns |
| `clip_circle(cx, cy, r) { … }` | the calls in the block, clipped to a circle: an orb filled to a level |

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
| `.passthrough()` | let the pointer through the box and its subtree, though they have backgrounds, for a HUD over a game; what in it takes the pointer (and its parts) and what `blocks()` still do |

The parts inside a widget that have looks of their own (a toggle's
track, a slider's thumb, the gem in an inventory slot) are hit as the
widget: the pointer on any of them hovers, presses and drags the widget.
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
- **Menus.** In a submenu, Left closes it and goes back to its item;
  Right on a submenu's item opens it. Otherwise, in a menu bar's menu,
  Left and Right open the menu next to it (wrapping around), as desktop
  menus do; so they do from the title of a menu opened by a click.
  The pointer opens menus and submenus by hovering only when it moves, so
  a pointer resting on a title doesn't take the menu back from the
  keyboard. A click on an open menu's title closes it. A submenu closes
  0.35 s after the pointer has left it and its item.
- **Keys and a game's own bindings.** A game that maps keys itself (Q and E
  for tabs, say) should leave them alone while `wants_keyboard()`, when a
  text field is taking them.
- **Popups.** An open popup or modal keeps the focus in it, takes it as
  soon as it opens (while focus shows), and gives it back to its opener
  when it closes.
- **Scrolling and the ring.** Focus moved by navigation scrolls its panes
  to keep it in view. The focus ring shows only after navigation.
- **A focus cursor.** `set_focus_cursor(class, motion)` draws one look
  round the focused widget instead of each widget's ring, over everything,
  and moves it to the next by `motion` as the focus moves (a spring glides
  it). It is the class's normal style, `ring_offset` outside the widget:
  a frame (FOCUS_CURSOR, in the themes), or brackets at its corners from a
  nine-slice, as `examples/main_menu.goose` has. It fades in and out as
  focus shows and hides. `set_focus_cursor(NONE, INSTANT)` turns it off.

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
  ring, the UI scale (`draw`); typing through gfx's injected input
  (`typing`); canvases: placement, size, clipping, opacity, culling, the
  pointer (`canvas`).
- **Expected output** is in `test/expected/<dir>_<name>.out`. A headless
  test with no GPU is reported skipped.

**Platforms tested:** Windows 11 with D3D12, and Arch Linux in WSL2 with
Vulkan through Mesa's dzn: the tests, and every example, headless.

## Benchmark

`bench/bench.goose` times record, layout and draw for a scroll pane of
widget rows. [bench/results.md](../bench/results.md) has the numbers. At
250 rows (3,754 nodes), AOT takes 0.6 ms to record, 0.26 ms to lay out and
2.25 ms to draw.
