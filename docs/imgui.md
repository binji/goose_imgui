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
  keyboard navigation, modals and toasts;
- `motion`: a leaderboard whose rows glide when re-sorted, and slide in or
  out when added or removed; a drawer on a spring; a rolling counter;
- `inventory`: a grid of custom slots in a scroll pane, with tooltips and
  a class of the program's own;
- `settings`: a menu bar, tabs, dropdowns, a text field, a scrolling
  list of key bindings, and a modal;
- `stats`: a run's summary on canvases: a line chart with values on hover,
  bars that grow in, a gauge, a minimap, each filling a grid card;
- `pixel`: a shop in pixel-art mode: the pixel font and theme, sprites
  drawn nearest at twice their size, slots framed by a nine-slice;
- `windows`: an editor of a running scene, in the dense dev theme: windows
  docked around its viewport, and floating ones moved, resized,
  collapsed, closed and raised; a tree of the
  scene's entities, each with a context menu; an inspector of the one
  selected, of property rows, number fields, colors and collapsing
  headers; a table of the entities, sorted by its headers, rows selected
  with Ctrl and Shift; a plot of frame times, a histogram and a
  sparkline; a console that logs slow frames and selections and takes
  commands;
- `dialogue`: a speaker's portrait and name, and rich text typed out a
  character at a time, each letter popping in, with spans that wave, glow,
  shake, shiver (an effect of the program's own) and cycle their hue.

Each takes `-- --frames N --screenshot file.png --theme light|dark|game
--scale 2 --keys Down,Return --log-ui`. With `--frames`, every frame is
1/60 s; `--log-ui` prints the UI's events each frame.

## The frame

| | |
|---|---|
| `frame() { … }` | a frame: gfx's input and frame time; recorded by the block, laid out, and drawn (when inside a gfx2d frame) |
| `frame(dt) { … }` | the same, `dt` seconds after the last: a fixed step for recording |
| `frame(input, dt) { … }` | with an `Input` the program made (tests, replays, gamepads), or one from `input_from_gfx` it changed; for the latter the frame still turns gfx's text input on while a field has the keyboard, and hands copied text to the clipboard |
| `begin_frame(input, dt)`, `end_frame()`, `draw()` | the parts: `draw` inside a gfx2d frame, after `end_frame` |
| `input_from_gfx() -> Input` | gfx's mouse and keyboard, and the ordered events for typed text and the clipboard |
| `nav_from_pad(input, PadState)` | a gamepad's held buttons and stick, as navigation, with repeat (gfx v1 has no gamepads; a program reading one passes what it holds) |
| `set_viewport(rect)` | the UI's area from now on; by default the screen, under the scales, which an empty rect goes back to |
| `set_scale(s)`, `ui_scale_of()` | the UI drawn `s` times as big: 2 for a high-density screen; starts at `IMGUI_SCALE`. `ui_scale_of()` is the scale it is drawn at (whole in pixel-art mode) |
| `edge_clamp(p, inset)`, `edge_clamp(p, rect)` | where to put a marker for p: p, if it is in the viewport inset by `inset` (or in `rect`); else where the line from the center to p leaves it. Also the angle to p, and whether it is in |
| `wants_pointer()`, `wants_keyboard()` | whether the UI took the pointer (it is over something that takes it or has a background, not in a `passthrough()` box, or holds a press) or the keyboard (a text field has focus) this frame |
| `cancelled()` | Escape or B pressed with no popup open to close, and nothing being carried or typed into a number field (which take it first): for the game's own "back" |
| `shortcut("Ctrl+Q")` | a key pressed with modifiers this frame: Ctrl (Cmd on a Mac), Shift, Alt, and a letter or digit; anything else is misuse. Ctrl+A, C, X and V go to a text field that has the keyboard, not here. A `menu_item`'s shortcut text is only shown; this acts on it |
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
| `columns(ts)`, `rows(ts)`, `cell(col, row)`, `span(cols, rows)` | grids: up to 8 tracks given each way; rows past those fit their content. A `cell` past the last column, or past 127, is misuse |
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
| `rich(s)`, `rich(s, d)`, `rich(s, CLASS)` | text in several styles, with images on its lines, from BBCode-like markup: `"Deal [dmg]20[/] damage, [kw]Burn[/kw] 3 [img=coin]"`. `[name]…[/]` (or `[/name]`) is a span, and spans nest; `[img=name]` an image; `[[` a `[`. It wraps, justifies and sizes as `text` does; lines break at spaces only, so a word in two styles stays whole |
| `[name=key]…[/]`, `rich(…) -> SpanHit` | a span the pointer can rest on: `rich` returns which key is under it (`h.is("burn")`), the one it was last on (`h.was("burn")`, to keep a tooltip's content as it fades), and `h.it`, an Interaction at that span for `tooltip(h.it) { … }`. The text doesn't take the pointer itself: a span is on when the widget the text is in (a card, a button) is the one under the pointer |
| `add_span(name, Span { ink, font, text_size, text_look, underline })` | a span's style, by name: what it sets of the text's ink, font, size and look (`add_text_look`'s, over the text's own), and an underline |
| `add_inline(name, texture, src, scale = 1, rise = 0)` | an image for `[img=name]`: `src` of the texture, `scale` times the text's size tall, centered on the text and raised by `rise` times its size |
| `image(texture, d, fit_mode, filter)`, `image(texture, src, d, fit_mode, filter)` | an image, or a sprite from a sheet; fitted by `gfx2d::FIT_CONTAIN`, `COVER` or `STRETCH`; sampled by `gfx2d::FILTER_LINEAR` or `NEAREST` (by default nearest in pixel-art mode, else linear) |
| `icon(ICON_CHECK …)`, `icon(kind, d)` | icons in the ink: `ICON_CHECK`, the chevrons (`ICON_CHEVRON_DOWN`, `_UP`, `_LEFT`, `_RIGHT`), `ICON_CLOSE`, `ICON_PLUS`, `ICON_MINUS`; for tools, `ICON_PLAY`, `ICON_PAUSE`, `ICON_STOP`, `ICON_STEP`, `ICON_MENU`, `ICON_SEARCH`, `ICON_REFRESH`, `ICON_DOT` |

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
| `text_shadow(c, dx, dy, soft)`, `no_text_shadow()` | a shadow moved by (dx, dy) under the text; inherited. `soft` 0: a copy of the text and its outline; > 0: soft, fading from the glyphs' edges over `soft` pixels (at most an eighth of the text's size; a wider one is a `layer` with a blur). Under an outline, a soft shadow starts at the glyphs, not the outline |
| `text_glow(reach, c)`, `no_text_glow()` | a halo in `c` around the glyphs, fading over `reach` pixels (at most an eighth of the text's size); inherited. With a soft shadow too, one of them takes a pass of its own |
| `reveal(chars)` | only the text's first `chars` characters drawn (of `text` or `rich`; a space, a newline or an image each one), each where it is with all of them, so typing it out doesn't move its lines: `reveal((time() - began) * 40)`. A fraction shows the next character just begun (for `FX_POP_IN` and the like). Not inherited |
| `text_fx(fx, a, b, c, d)` | an effect on each character of the text, and of its text descendants': `FX_SHAKE`, `FX_WAVE`, `FX_PULSE`, `FX_SWING`, `FX_RAINBOW`, `FX_FLASH`, and, as `reveal` uncovers them, `FX_POP_IN`, `FX_DROP_IN`, `FX_FADE_IN`; up to four numbers for it, 0 for its default (textfx.goose lists them). It moves only what is drawn, never the layout |
| `Span { text_fx, fx_args, .. }` | a span's effect, over the text's own: `[scared]OUT[/]` |
| `text(s, d) { g => … }`, `rich(s, d) { g => … }` | the block run for each character as the text is recorded, with a `Glyph`: what it reads (`index`, `count`, `cp`, `time`, `seed`, `age` since it was revealed, `text_fx`/`text_args`, `span_fx`/`span_args`) and what it sets (`offset`, `scale`, `turn`, `ink`, `alpha`). `standard_fx(g)` plays the built-in effects; a program's own are numbered from `FX_USER`. Without a block, a text with an effect runs `standard_fx` |
| `set_text_motion(k)` | how much text effects move, from 0 (still; colors still change) to 1: for players who want less motion |
| `text_chars(s)`, `rich_chars(s)` | the characters `reveal` counts in the whole of a text, or of a rich text (its markup left out): when the typing is done |

A Desc with text effects set during a frame is good for that frame only.
One made outside any frame, and kept, is good for any frame.
| `opacity(o)` | multiplied into its colors and its subtree's |
| `isolate()` | the subtree drawn into a gfx2d layer and composited at its opacity, so overlaps inside it don't show through (a pass more) |
| `filter(m)`, `no_filter()` | the subtree's colors run through a gfx2d `ColorMatrix`: `grayscale(1)` for something locked, `flash(c, t)` for something hit, `sepia`, `hue_rotate`, `saturate`, `brightness`, `contrast`, `tint_matrix`, or several by `gfx2d::mul`. Drawn into a layer, as `isolate()` is; kept by an exit's copy. Set every frame to animate it |
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
  insets, filter)` (the filter by default nearest in pixel-art mode, else
  linear);
- `alpha`, `offset` and `zoom`: a state's motion, such as a pressed button
  sinking;
- `ring`, `ring_width` and `ring_offset`: the focus ring;
- `min_size`, and `gap` (between a widget's parts).

A `StyleSet` has one Style for each state (`normal`, `hover`, `active`,
`focused`, `checked`, `disabled`) and a `transition` Motion for the
amounts. It is made with `style_set(normal, transition)` and changed
state by state, or in every state at once with
`each_state(set) { s => s.radius = radii(12.0); };`.
- A node's look is its class's normal style, plus each state's difference
  from normal, scaled by the state's amount.
- So a checked box hovered keeps its checked fill and gains its hover
  border.
- And a change to `normal` alone is the opposite change in each state that
  didn't get it, so anything that isn't a state's own goes in `each_state`.
- Focus counts only while it shows, after navigation.

| Themes and classes | |
|---|---|
| `theme_light()`, `theme_dark()`, `theme_game()` | the built-in themes; the light one is in place from the start |
| `theme_dev()`, `theme_dev_light()`, `dev_palette(dark)` | for developers' tools: small text, short rows, thin padding, quick between states |
| `theme_pixel()`, `theme_pixel(font, size[, palette])` | for pixel-art mode: every class's sizes scaled to the font and whole, corners square, shadows hard, borders and the ring a unit wide, a press moving a unit down, no easing between states; in `pixel_font()` at 6 by default |
| `theme(Palette { … })` | every built-in class from a palette: surface, raised, hover, pressed, line, ink, muted, accent and their sizes; `space` scales the other paddings and gaps (below 1 is denser) |
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
- POPUP, MODAL, BACKDROP, TOOLTIP, NOTICE;
- INPUT, CARET, SELECTION, DROPDOWN;
- WINDOW, WINDOW_TITLE (checked while its window is in front),
  WINDOW_BODY, WINDOW_BUTTON, RESIZE_GRIP (its `min_size.x` is how thick
  the grips are);
- HEADER, TREE_ROW (checked: selected), TREE (its left padding is the
  indent), NUMBER, PROPERTIES (its gap), PROPERTY_LABEL;
- TABLE, TABLE_HEADER, TABLE_HEAD (a column's header; checked: sorted
  by), TABLE_ROW (its `min_size.y` the rows' height; checked: selected),
  TABLE_ROW_ALT (every other row), TABLE_CELL (its padding);
- SPLITTER (the handle between panes, and between dock leaves: its
  `min_size.x` its thickness);
- DOCK_SPACE (where no window is), DOCK_TAB_BAR, DOCK_TAB (checked: the
  one shown; its `min_size.y` the tab bar's height), DOCKED (a docked
  window's frame), DOCK_PREVIEW (where a dragged window would go),
  DOCK_TARGET (a target; checked: under the pointer; its `min_size.x` its
  side), DOCK_TARGET_MARK (the part of a window it fills), DOCK_TAB_TOGGLE
  (a leaf's corner button, its tab bar hidden);
- LOG (the pane: its look, padding and text size), LOG_LINE,
  LOG_DEBUG_LINE, LOG_WARN_LINE, LOG_ERROR_LINE, LOG_INPUT_LINE (each
  level's ink);
- PLOT (its ink and text size the scale's and readout's), PLOT_LINE (its
  bg the line's color, its `min_size.x` the line's width), PLOT_BAR (hover:
  the bar under the pointer), SWATCH, PICKER (its gap, and its square's
  side as `min_size.x`).

## Pixel art

In pixel-art mode the UI is drawn in whole pixels of its own, each a
square of the screen's:

```goose
imgui::set_pixel_art(true);
imgui::set_scale(3);                // three screen pixels a unit
// once the window is open (the font is a texture):
imgui::theme_pixel();
```

- The scale is rounded down to whole screen pixels a unit (at least one),
  so 2.5 draws at 2.
- Every box lands on whole units (its edges rounded), and motion's shifts
  too, so text and images placed at fractions stay on the grid.
- Nothing is antialiased, and images and nine-slices are drawn nearest
  unless they ask otherwise.
- Text should be in a bitmap font (`gfx2d::bitmap_font`), at its cell
  height or a whole multiple of it; a vector font this small, unblended,
  is hard to read. `pixel_font()` is a built-in one: small capitals 3 x 5
  in cells of 4 x 6, its size 6, lower case drawn as upper. It is made the
  first time it is asked for, once the window is open.
- A design pixel is a unit: `image(sprite, column().size(16, 16))` is a
  16-pixel sprite at the scale.

| | |
|---|---|
| `set_pixel_art(on)`, `is_pixel_art()` | the mode |
| `pixel_font() -> gfx2d::Font` | the built-in pixel font |
| `theme_pixel(…)`, `pixel_palette()` | the theme for it, and its default colors |

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
| `.exit(fade_out(m))`, `slide_out(dx, dy, m)`, `pop_out(scale, m)`, `.delay(s)` on the Exit | played the first frame a node's ID is not recorded, on a copy of it and its subtree as they were last drawn (what was on the screen of it), where they were: a removed row slides out, a gem thrown away pops. The node needs an ID of its own (a label, a key), not one from its place |
| `exits_playing()` | how many such copies are drawn this frame |
| `Notices<T> { limit: n, .. }` | a queue of notices holding the program's own fixed-size data: a damage number's amount and where it landed. At most `limit` are live (0: any number); past it the oldest go first |
| `TextNotices { limit: n, .. }` | a queue of text of any length, kept by imgui and given back as each notice goes. Text with other data (a kill feed's names and weapon) is a `Notices<T>` whose `T` holds arrays of the size the program chooses |
| `notify(q, data, seconds = 3)`, `notify(q, text, seconds = 3)` | posts a notice once, in a frame or out of one: a hit, a toast, an area's name, a line of a feed |
| `notices(q, d) { n => … }` | the queue's live notices in a box of `d`, oldest first, each drawn by the block: `n.data` (or `n.text`), `n.age()`, `n.left()`. Its box should be `box(n.id(), …)`, with an exit to play as it is dropped, when its time is up or past the limit |
| `notices(q, d = column().gap(8), item = notice_item())` | a queue of text, each an `item` holding its text: `notice_item()` is a NOTICE that slides in, glides, and fades out |
| `clear_notices(q)`, `notice_count(q)` | the queue emptied (each plays its exit); how many are live |
| `.glide(m)` | from where the node was laid out to where it is now: reordered rows slide to their places |
| `.offset(x, y)`, `.scale(s)` | drawn moved, or scaled about its center, with its subtree |
| `.rotate(radians)`, `.skew(radians)` | drawn turned clockwise about its center, or slanted (its verticals leaning right), with its subtree: a fanned hand of cards, a diamond, a slanted panel. It is hit where it is drawn; its `it.pointer` is from the box around it |

## Widgets

| | |
|---|---|
| `button(label[, d]) -> bool`, `button_with(label, d) { … } -> bool` | clicked or accepted; the second with any content |
| `checkbox(label, v[, d])`, `toggle(label, v[, d])` | true the frame `v` changes |
| `radio(label, selected, value[, d])` | `selected` becomes `value` |
| `slider(label, v, lo, hi, step[, d])` | `f64`, `f32`, `i64`, `i32`; dragged, clicked along, or left/right while focused. Only that changes `v`: a value just shown is left as it is, out of range or between steps |
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
| `context_menu(it[, d]) { menu_item(…); … } -> bool` | a menu at the pointer when the widget is right-clicked; true while open. A right click elsewhere closes it |
| `last_item() -> Interaction` | the last widget's interaction, for one that returns only its value: `if selectable(…) { … }; context_menu(last_item()) { … };` |
| `drag_source(it, kind, payload) -> bool`, `drop_target(it, kind) -> Drop`, `drag_ghost(d) { … }` | drag and drop: a widget's payload (an `i64`) carried to a target that takes its `kind`, picked up by dragging it (or accepting it with the keys, carried by navigation, put down by accepting); `Drop { over, dropped, payload }`; the ghost drawn under the pointer, never in its way. Escape puts it back. `dragging(kind)`, `drag_payload()` |
| `text_input(label, buf, d, max_len, placeholder) -> TextEdit` | one line, edited in place: a `u8[>..]` or a `u8[..N]`. Its caret is solid while typing, for half a second after it moves and on taking the focus, then blinks, fading |
| `set_caret_blink(on)` | a caret that never blinks, for players who find blinking distracting |

A label's `##` and what follows it are part of the ID but not shown:
`"Play##dlc"`. A label's `###` and what follows it are the whole of the ID,
so the text before them can change and the widget stays the same one,
with its focus, its press and its state: `str("Clear (", n, ")###clear")`.
A window's title works the same way, and other calls can name it by that
part alone: `raise_window("###score")`.

## Windows

```goose
imgui::window("Stats", show_stats, imgui::column().size(260, 180).absolute(16, 16)) {
    imgui::textf(imgui::column()) { out => format(out, "fps ", fps); };
    imgui::checkbox("Wireframe", wireframe);
};
```

A window is a root of its own:
- **Drawn** over the main tree and under popups, back to front in the
  order the windows were last pressed. A press anywhere in one puts it in
  front, and a window opened again comes up in front.
- **Moved** by dragging its title bar, and kept on the screen.
- **Resized** by dragging any edge or corner, to no less than its title
  bar needs.
- **Collapsed** to its title bar by its arrow or a double click on the
  title; its block isn't run while it is.
- **Closed** by its cross, which sets `open` false; nothing is recorded
  while `open` is false.
- **Clipped:** made narrower than what is in it, its body and title are
  cut off at its edges (its buttons kept), not drawn past them.
- **Scoped:** its title is its ID, and the IDs inside it are under it, so
  two windows can each have an "OK".
- **Kept:** where it is, its size and whether it is collapsed last as long
  as the program does, so a window closed and opened again is where it
  was.

| | |
|---|---|
| `window(title[, d][, flags]) { … }`, `window(title, open, d, flags) { … }` | `d` is the body's: a column's gap, padding and alignment (WINDOW_BODY's by default). Its size, in pixels, is the window's to start with, else it fits its content; its `absolute(x, y)` is where it starts, else each new one a little below and to the right of the last. The body scrolls when it is smaller than its content |
| `WINDOW_NO_TITLE`, `WINDOW_NO_RESIZE`, `WINDOW_NO_MOVE`, `WINDOW_NO_COLLAPSE`, `WINDOW_NO_SCROLL` | flags, or-ed. A body that scrolls lays out its content at the content's height, so what should fill the window and scroll itself (a log, a table) wants `WINDOW_NO_SCROLL` |
| `window_rect(title)`, `set_window_rect(title, rect)` | where it was drawn; moved and sized by the program (a size of 0: its content's) |
| `raise_window(title)`, `collapse_window(title, on)`, `is_window_collapsed(title)` | |
| `set_window_show(m, zoom = 0.95)`, `set_window_show(enter, exit)` | windows fade and grow from `zoom` of their size as they show (opened, or first recorded), and fade and shrink as they hide (closed, or no longer recorded), by `m`; or any `Enter` and `Exit`. Off (instant) by default. Hiding plays on a copy of the window as it was last drawn, in its place among the windows, taking no input; a window showing or hiding is drawn in a layer, so its parts don't show through each other. With it on, each window is copied every frame, as anything with an exit is: what of it is on the screen, not what is scrolled away. Set once at the start: set on windows already showing, their enter plays |
| `set_window_roll(m)` | windows roll up into their title bars as they collapse, and down as they open, by `m` (a tween or a spring); `INSTANT`, the default, doesn't roll. The body keeps its height and is cut off at the bottom, its content still recorded until it has rolled away |
| `cursor() -> i64` | the pointer's shape the UI wants, `CURSOR_DEFAULT` or a grip's `CURSOR_EW_RESIZE`, `NS`, `NWSE`, `NESW`, numbered as gfx's are. gfx v1 has no cursor shapes; a program on a gfx that does passes it on |

## Developers' widgets

```goose
imgui::collapsing("Transform", imgui::column(), true) {
    imgui::properties() {
        imgui::property("Position") { imgui::drag_vec("", pos); };
        imgui::property("Speed") { imgui::drag_number("", speed, imgui::Drag { lo: 0, hi: 10, decimals: 2 }); };
        imgui::property("Lives") { imgui::input_number("", lives, imgui::Drag { lo: 0, hi: 9 }); };
    };
};
let it = imgui::tree_node("Enemies", chosen == -1) {
    for e, k in enemies { if imgui::tree_leaf(e.name, chosen == k).activated { chosen = k; } }
};
```

| | |
|---|---|
| `properties([d]) { property(label) { … }; … }` | rows of a label and its widget: a grid, its labels' column as wide as the widest label in the window (in any `properties` there, from the frame before), the widgets as wide as the rest. A property's block is under its label's ID, so its widget can be labelled `""`. Outside `properties`, a row of its own |
| `collapsing(label[, d][, open_at_first]) { … } -> bool` | a header that shows its block while open: clicked, or Right and Left while focused. True while open |
| `tree_node(label[, selected][, open_at_first]) { … } -> Interaction` | an arrow and a label, its children (the block) indented under it while it is open. The arrow or a double click opens and closes it; Right opens it, Left closes it or goes up to its parent. Its row's interaction is the result: `activated` to select it, or for `tooltip` and `context_menu` |
| `tree_leaf(label[, selected]) -> Interaction` | a node with no children, lined up with its siblings' labels |
| `set_tree_roll(m)` | headers and tree nodes roll open and closed by `m` (a tween or a spring), their content cut off at its bottom edge and the rows below following; `INSTANT`, the default, doesn't roll. The content keeps its IDs and is recorded until it has rolled away |
| `is_open_node(label)`, `set_open(label, on)`, `set_open(id, on)` | a header's or tree node's open state, in the scope it is recorded in. It lasts as long as the program, so a node inside a closed one keeps its own |
| `drag_number(label, v[, Drag][, d]) -> bool` | `f64`, `f32`, `i64`, `i32`. Dragged sideways (finer with Shift, coarser with Alt), Left and Right by its step while focused; a click without a drag, or Enter, types in it: Enter or a click elsewhere keeps what was typed (clamped), Escape doesn't. True the frame it changes |
| `input_number(label, v[, Drag][, d]) -> bool` | the same between − and + buttons, which step it |
| `drag_vec(label, v[, Drag][, d]) -> bool` | a `float2`, `float3` or `float4`: a field for each part, tagged X, Y, Z, W in red, green, blue and gold |
| `Drag { speed, lo, hi, decimals, step }` | `speed`: the change a pixel dragged (0: a 200th of the range, else 0.1, or 0.2 for whole numbers); `lo` and `hi`: its range; `decimals`: shown and kept to (-1: 3, or 0 for whole numbers); `step`: Left, Right and the buttons (0: 1 for whole numbers, else ten pixels' worth) |
| `format_fixed(out, v, decimals)` | `v` written with that many digits after the point |

`Input.mods` holds the `MOD_SHIFT`, `MOD_CTRL` and `MOD_ALT` held this
frame (from gfx in `input_from_gfx`).

## Small pieces

```goose
imgui::toolbar("tools") {
    if imgui::icon_button("Step", imgui::ICON_STEP) { step(); }
    imgui::icon_toggle("Pause", imgui::ICON_PAUSE, paused);
    imgui::separator();
    if imgui::small_button("Reset") { reset(); }
};
imgui::knob("Gain", gain, 0, 2);
imgui::status_bar("status") { imgui::spinner("busy"); imgui::text("loading"); };
```

| | |
|---|---|
| `small_button(label[, d]) -> bool` | a button with less padding (SMALL_BUTTON) |
| `icon_button(label, kind[, d]) -> bool` | a square button with an icon, flat until hovered (ICON_BUTTON); its label is its ID and its tooltip (none if it is all after "##") |
| `icon_toggle(label, kind, v&[, d]) -> bool` | an icon button that turns `v` on and off, checked while on; true the frame it changes |
| `toolbar(label[, d]) { … }` | a row of tools, as wide as there is room (TOOLBAR); `separator()` stands up in it |
| `status_bar(label[, d]) { … }` | a row of small, muted text (STATUS_BAR): last in a column that fills a window or the screen |
| `link(label[, d]) -> bool` | text in the accent, underlined while hovered or focused (LINK, LINK_LINE); true when clicked or accepted |
| `bullet([d])`, `bullet_text(s)` | a dot (BULLET); one and text beside it |
| `label_value(label, value[, d])` | a label, muted, and its value at the row's other end |
| `spinner([label][, d])` | an arc going round (SPINNER: its ink the arc, its bg the track); `label` is its ID |
| `vslider(label, v, lo, hi[, step][, d]) -> bool` | a slider standing up, lo at the bottom; Up and Down step it; its label under it |
| `slider_angle(label, radians, lo_deg = -180, hi_deg = 180) -> bool` | an angle kept in radians, slid in whole degrees, shown beside it |
| `range_slider(label, from, to, lo, hi[, step][, d]) -> bool` | two thumbs that don't cross: a press takes the nearer; Left and Right move the one taken last, and accept changes which |
| `knob(label, v, lo, hi[, step][, d]) -> bool` | a dial (KNOB, in the slider's colors): dragged up or right turns it up, the whole range in 200 pixels; the arrows step it, and past its ends move the focus on; its label under it |

## Long lists and tables

```goose
imgui::scroll("log", imgui::column().grow()) {
    imgui::row_list("lines", lines.len, 18) { k => imgui::text(lines[k]); };
};
let t = imgui::table("ents", ["Name", "HP", "Team"], ents.len, picked) { k, c =>
    let e = ents[order[k]];
    if c == 0 { imgui::text(e.name); } else if c == 1 { imgui::textf(imgui::column()) { out => format(out, e.hp); }; }
    else { imgui::text(e.team); }
};
if t.clicked >= 0 { imgui::select_row("ents", picked, t.clicked); }
if t.sorted { sort_ents(t.sort, t.descending); }
```

| | |
|---|---|
| `row_list(label, count, row_height[, d]) { k => … } -> first, last` | `count` rows `row_height` high (and `d`'s gap apart), only those in view recorded (with a row more each way): the block records row k, under an ID scope of its own. The list is as tall as all of them, so the scroll pane it is in scrolls it as if they were there. What was in view is kept from last frame's layout, moved by how far its pane has scrolled since. Returns the rows recorded |
| `select_row(list, selected, k)` | row k clicked (or accepted), in the program's `bool` for each row: alone; with Ctrl, toggled; with Shift, the rows from the last one clicked (with Ctrl too, added to the rest) |
| `table(label, headers, count[, selected][, Table][, d]) { k, c => … } -> TableInfo` | a header, and `count` rows of a cell for each column, recorded by the block (row k, column c) only while in view, under the header, which stays as they scroll. A column is as wide as its header's right edge was dragged to, or a share of what the others leave (no less than `Table.least`); columns past the table's edge are cut off. A header clicked sorts by it, again the other way; the program sorts its rows. Rows in `selected` show selected; rows are striped. 8 rows high and as wide as there is room unless `d` says |
| `Table { row_height, sortable, least }` | `row_height`: 0 for TABLE_ROW's `min_size.y` |
| `TableInfo { clicked, double_clicked, hovered, sort, descending, sorted }` | the row clicked, double-clicked and under the pointer (-1: none); the column sorted by (-1: none) and which way; `sorted` the frame that changed |

## Splitters

```goose
imgui::split("main", imgui::ROW, imgui::row().grow()) {
    imgui::pane("tree", 0.25) { scene_tree(); };
    imgui::pane("view") { viewport(); };
    imgui::pane("inspector", 0.3) { inspector(); };
};
```

| | |
|---|---|
| `split(label, ROW or COLUMN[, d]) { pane(…) { … }; … }` | panes side by side (or one above another), a handle between each two; as big as there is room unless `d` says. A handle dragged moves the pane before it (the one after too, if that has a fraction, so the two keep their total), no pane less than 32 pixels |
| `pane(label[, fraction][, d]) { … }` | `fraction` of the split's length to start with, then what it is dragged to, kept as a fraction, so it grows and shrinks with the split; 0: it shares what the others leave with the other panes that do (the last of which takes what rounding leaves, or the last pane, if none share). Its content is cut off at its edges. Its IDs are under the split's |

## Docking

```goose
imgui::dock_space("dock", imgui::column().grow());
imgui::window("Viewport", imgui::column(), imgui::WINDOW_NO_SCROLL) { viewport(); };
imgui::window("Scene") { tree(); };
// a layout to start with, once:
imgui::dock_window("Viewport", "dock", imgui::DOCK_CENTER);
imgui::dock_window("Scene", "dock", imgui::DOCK_LEFT, 0.2);
imgui::dock_window_with("Console", "Viewport", imgui::DOCK_BOTTOM, 0.3);
```

A dock space is a tree of splits, whose leaves each hold windows as tabs:
- **A window is recorded the same docked or not.** Docked, in a dock
  space being shown, its body fills its leaf under the tab bar, while its
  tab is the one shown; its title bar, grips and roll are its tab's and
  the leaf's. If its dock space isn't recorded, it floats.
- **Docking:** a floating window dragged by its title over a dock space
  shows targets: a cross of five on the leaf under the pointer (the middle
  a tab with what is there; each side, half of the leaf, beside it) and,
  if the space is split, four by its outer edges (a quarter of the whole
  space, on that side). The area a target would give is shown while the
  pointer is on it; let go there, the window docks. A leaf's tab bar is a
  target too: let go on it, the window goes in as a tab where it was let
  go, between the tabs either side: while it is over the bar, its tab is
  shown there, the others making room (sliding, with `set_tab_slide`;
  not in a bar too full for its tabs). Let go anywhere
  else, it floats on. An empty leaf has only the middle. A leaf holds at
  most 8 windows; a full one has no middle, and its tab bar is no target.
- **The preview:** `set_dock_preview(true[, m])` shows where a window
  would go by drawing the window itself there, at that size, rather than
  an outline; it moves there and back by `m`. Nothing else moves until it
  is let go. Over a tab bar, it shrinks into its tab there and fades out.
- **Floating docks:** dragged over another floating window, a window
  shows a cross of targets on it too. Let go on one, the two go in a
  floating dock where the other was: a window of imgui's, titled by the
  window shown in its first leaf, holding a dock space of its own that
  takes targets, tabs, splits and undocking as any does. It is moved,
  resized and rolled up by its title, its windows with it; it isn't
  docked itself (its windows are, one by one). It has no window of its
  own to record: it shows while any of its windows is recorded.
- **Undocking:** a tab dragged out of its tab bar floats its window, as
  big as its leaf was, still held by the pointer as if by its title. A
  leaf left with no windows goes, its sibling taking its place.
- **Tabs:** clicked, the window is shown; dragged along the bar, it
  follows the pointer, over the others, and once its edge is past the
  middle of the tab beside it, the two change places (the other sliding,
  with `set_tab_slide`). From the keys, the shown tab is the bar's one
  stop (Tab reaches it); Left and Right show the tab beside it, and the
  focus goes with it; at the bar's ends, they go on that way, to the next
  bar or widget. Tab goes from a tab into its window's widgets, and from
  the last of them to the next tab bar. A window that can
  close has a close button on its tab; closed, it keeps its place, for
  when it is opened again. A window not recorded (closed, or not called
  for) has no tab. Tabs that don't fit are cut off, the one shown first,
  and a button at the bar's end lists them all. A tab's menu (a right
  click) can hide its leaf's tab bar (a button in the leaf's corner shows
  it again) or undock it.
- **Resizing:** the handle between two leaves, dragged.
- Docked windows are drawn under the floating ones.

| | |
|---|---|
| `dock_space(label[, d])` | a dock space, as big as there is room unless `d` says |
| `dock_window(title, space, side[, ratio])` | window `title` docked in `space` (both labels at the top level), on `DOCK_LEFT`, `DOCK_RIGHT`, `DOCK_TOP` or `DOCK_BOTTOM` of all that is there, taking `ratio` of it; `DOCK_CENTER`, a tab in its biggest leaf. Into an empty space, it fills it, whatever its side. For a layout to start with |
| `dock_window_with(title, other, side[, ratio])` | docked by window `other`: a tab with it, or beside it in its leaf; if `other` floats, the two in a floating dock where it is (`set_window_rect` it first to say where) |
| `undock_window(title)`, `is_docked(title)` | floating again (where its leaf was, as big, if it never floated) |
| `set_dock_preview(window[, m])` | while a dragged window is on a target, the window itself drawn in the area it would take (`true`), or that area outlined (`false`, the default); with `m`, it moves between the pointer and the target |
| `set_tab_slide(m)` | tabs slide to their places by `m` (a tween or a spring) as a dragged tab passes them, and the dragged one when it is let go; `INSTANT`, the default, jumps |

## Saving the layout

```goose
// At the start: the layout from last time, or one made in code.
if !imgui::load_layout("layout.json") {
    imgui::dock_window("Scene", "dock", imgui::DOCK_LEFT, 0.2);
}
show_log = imgui::layout_open("Log", true);
// On the way out:
imgui::save_layout("layout.json");
```

A layout is where the windows are and how big, which are collapsed and
which were open, their order front to back, every dock space's tree
(floating docks too), the panes' fractions, and which headers and tree
nodes are open. It is JSON. Windows and the rest are kept by their IDs, so
a layout fits a program whose labels are the same; a window it doesn't
name keeps its place, floating. Windows first shown after it is loaded
keep its order, rather than coming to the front as they first show.
Tables' column widths aren't in it.

| | |
|---|---|
| `save_layout(path) -> bool` | the layout written to the file at `path` (a new file beside it, renamed over it, so a failed write leaves the old one) |
| `load_layout(path) -> bool` | the layout in the file in place of this one; false, and nothing changed, if there is no file or it isn't a layout (which is written to stderr, and is not misuse: the program goes on) |
| `layout_json(out&)`, `load_layout_json(text) -> bool, error` | the same, as text: appended to `out`; read from `text`, with what is wrong if it isn't a layout (malformed, another version, an ID that isn't one, a number out of range, or a dock tree that isn't a tree or doesn't match its windows) |
| `layout_open(title, fallback) -> bool` | whether window `title` was open when the layout was saved; `fallback` if it isn't in it, or none was loaded. The program owns a closable window's open flag, so it starts it from this |

## Logs and consoles

```goose
var log = imgui::Log { .. };
imgui::logf(log, imgui::LOG_WARN) { out => format(out, "slow frame: ", ms, " ms"); };
var cmd: u8[>..] = [];
imgui::window("Console", show, imgui::column().size(400, 240), imgui::WINDOW_NO_SCROLL) {
    if imgui::console("console", log, cmd, imgui::column().grow()) { run(cmd); cmd.clear(); }
};
```

| | |
|---|---|
| `Log { lines_kept, bytes_kept }` | the program's lines, in a ring: at most `lines_kept` lines (2,000) and `bytes_kept` of text (128 KiB), the oldest going first. Its arrays grow once and are written over, never shrunk, so logging is fine in a loop over string literals |
| `log(l, s[, level])`, `logf(l[, level]) { out => format(out, …); }` | `s`, a line for each of its lines, at `LOG_DEBUG`, `LOG_INFO` (the default), `LOG_WARN` or `LOG_ERROR` |
| `log_count(l)`, `log_text(l, k)`, `log_line(l, k)`, `log_clear(l)` | the lines held, line k's text and its `LogLine { level, time }` (0 the oldest); all of them gone |
| `log_view(label, l[, d][, filter][, least])` | the lines in a pane, only those in view recorded, each in its level's color: those with `filter` in them (ignoring case), at `least` or above. It follows the newest line, unless scrolled back from the end; scrolled to the end, it follows again. Right-click: Copy (the newest of what is shown that fits the clipboard) and Clear. Ten lines high unless `d` says |
| `console(label, l, cmd[, d][, filter]) -> bool` | a log view and a command line under it: Enter echoes the command into the log (`LOG_INPUT`), follows it, and returns true, for the program to run `cmd` and clear it. Up and Down step through the commands typed before, and back to what was being typed |
| `has_text(s, part)` | whether `s` has `part` in it, ignoring case |

## Plots and colors

```goose
imgui::push_sample(frame_ms, dt * 1000.0, 120);
imgui::plot_lines("##frame time", frame_ms, imgui::Plot { lo: 0, hi: 33, decimals: 1 });
imgui::plot_bars("##spread", buckets[..], imgui::Plot { decimals: 0 }, imgui::column().height(48));
imgui::color_edit("Tint", tint);
```

| | |
|---|---|
| `plot_lines(label, values[, Plot][, d]) -> Interaction` | `f64` or `f32` values, a line through them, oldest at the left, the area under it filled; the range's ends written at the left; under the pointer, a guide and the nearest value (`k: v`). A frame 64 high and at least 120 wide unless `d` says. Its interaction, for a tooltip or a click |
| `plot_bars(label, values[, Plot][, d]) -> Interaction` | a bar for each value, from zero (or the end of the range nearest it); the bar under the pointer lit and read out |
| `sparkline(label, values[, d])` | a line alone, 80 wide and a line of text high unless `d` says: for a row of stats |
| `Plot { lo, hi, offset, fill, scale, readout, decimals }` | `lo` and `hi`: the range (equal: the values' own); `offset`: where the oldest value is, for a ring of them; `fill`: the area under the line; `scale`, `readout`: shown or not; `decimals`: of the numbers written |
| `push_sample(buf, v, keep)` | `v` added to a `f64[>..]` or `f32[>..]`, the oldest dropped past `keep`: a rolling buffer |
| `color_edit(label, c[, alpha][, d]) -> bool` | a swatch and the hex of a `gfx2d::Color`; the swatch opens a picker under it (or above, if there is no room), and closes it. True the frame it changes `c` |
| `color_picker(label, c[, alpha][, d]) -> bool` | a square of saturation across and value up, a bar of hue, a bar of alpha (if `alpha`), each dragged, or moved by the arrows while focused; fields for R, G, B (and A), 0 to 255, and the hex, to drag or type in. It keeps its own hue, so a color dragged to gray or black and back keeps it |
| `color_swatch(label, c[, d]) -> Interaction` | the color over a checkerboard (its left half opaque, if it is see-through); activated when clicked, as a button is |
| `format_hex(out, c, alpha)`, `parse_hex(s, alpha) -> Color, bool` | `#RRGGBB(AA)`; `#RGB`, `#RRGGBB` or `#RRGGBBAA`, the `#` optional, `alpha` used when it has none |

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
| `.with_bits(OVERFLOW_Y)`, `OVERFLOW_X` | its children are their content's height (or width) whatever its own, as in a scroll pane, but it doesn't scroll or take the pointer, and they don't make it bigger: with `.clip()`, a reveal, or a table's columns cut off at its edge |
| `.with_bits(SHRINKS)` | it can be narrower than its content (CSS's `min-width: 0`), its children laid out as ever: with `.clip()`, what doesn't fit is cut off. A window's body and title have it |
| `.passthrough()` | let the pointer through the box and its subtree, though they have backgrounds, for a HUD over a game; what in it takes the pointer (and its parts) and what `blocks()` still do |

The parts inside a widget that have looks of their own (a toggle's
track, a slider's thumb, the gem in an inventory slot) are hit as the
widget: the pointer on any of them hovers, presses and drags the widget.
| `with_bits(CAPTURE_X)` | left and right go to the widget while it is focused (`it.nav.x`); `CAPTURE_LEFT` or `CAPTURE_RIGHT`, only one of them (the other navigates): a widget with nothing more that way |
| `interact(id, d) -> Interaction` | the interaction a widget recorded with `id` and `d` will have, asked before recording it so its look can follow. Its events and easing go by `d`'s class, so recording the widget with another class is misuse (with none, `skin(NONE)`, is fine: the widget eases by `d`'s and draws nothing) |
| `look_of(it)`, `checked_look(on)` | the look state of an interaction, or of on/off |
| `id(label)`, `id(key)`, `sub_id(id, part)`, `id_scope(…) { … }` | IDs |

`Interaction` holds:
- `hovered`, `held`, `pressed`, `released`, `clicked`, `double_clicked`;
- `focused`, and `activated` (clicked, or accepted while focused);
- `dragging` and `drag`;
- `pointer` (from the rect), `rect` (last frame's, on the screen), and
  `nav` (captured presses);
- the eased amounts `hover_t`, `press_t`, `focus_t` and `checked_t`.

## UI events, for sounds

Each frame keeps a list of what happened in the interface, for the
program to play sounds by: imgui plays nothing itself. Read it after the
frame:

```goose
imgui::frame() { ui(); };
for e in imgui::ui_events() {
    if e.kind == imgui::UI_HOVER || e.kind == imgui::UI_FOCUS { play(tick); }
    else if e.kind == imgui::UI_ACTIVATE { play(if e.class == imgui::TAB { swish } else { click }); }
    else if e.kind == imgui::UI_CHANGE { play(ratchet); }
    else if e.kind == imgui::UI_DENIED { play(buzz); }
}
```

| | |
|---|---|
| `ui_events() -> const UiEvent[:]` | the last frame's events, in order: `{ kind, id, class }`, the widget's (or popup's) ID and its style class |
| `UI_HOVER` | the pointer moved onto an enabled widget; not when a widget comes under a pointer that is still |
| `UI_FOCUS` | navigation showed the focus on a widget; a click focuses quietly |
| `UI_PRESS`, `UI_ACTIVATE` | the pointer went down on it; it was clicked, or accepted while focused |
| `UI_CHANGE` | a value moved without an activation: a slider's ticks (each step, or each twentieth of its range without one), whether dragged or moved by left and right; tabs switched by the shoulder buttons |
| `UI_OPEN`, `UI_CLOSE` | a popup, menu, dropdown or modal opened, or closed (by cancel, a press outside, the program, or no longer being recorded); its class `POPUP`, `MENU` or `MODAL` |
| `UI_DENIED` | the pointer went down on a disabled widget |
| `UI_BACK` | cancel with no popup open to close, and nothing carried or typed into a number field: the program's "back" (`cancelled()` is true too) |
| `ui_event(kind, i, class)` | an event of the program's own widget, or of its own kind (from 64, say) |
| `ui_event_name(kind)` | "hover", "focus" …, for logging |

Hovers, focus, presses, activations and denials come from `interact`, so
widgets made with it have them without asking. An event raised between
frames goes in the next frame's list.

## Navigation

- **Focus.** `focus(id)`, `blur()`, `is_focused(id)`, `focused_id()`.
  `default_focus(id)` is where navigation starts.
- **Scopes.** `nav_scope(label, NAV_TRAP | NAV_WRAP) { … }`.
- **Moving.**
  - The arrows (and a pad's d-pad and stick) move to the nearest widget
    that way, preferring ones in line with the focused one.
  - Tab and Shift+Tab go in recorded order.
  - Enter, Space or A accepts.
  - Escape or B puts down what is carried or stops typing a number, if
    either is going on; else it closes the top popup, or is the program's
    `cancelled()`.
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

## Metrics

```goose
imgui::menu_check("Metrics", show_metrics);
imgui::metrics_window(show_metrics);
```

`metrics_window(open&)` is a window of what the last frame took: its
time in imgui (recording, layout, what follows layout, drawing), and how
many nodes, roots, hits, focusables, states, animations, windows and
canvas ops there were. Under them is the last frame's tree of nodes, a
row each (its kind, its text or its ID if it was named, its size): a row
hovered outlines its node on the screen, and one clicked shows its kind,
ID, class, rect, what it takes (hits, focus, scrolling) and its number of
children. The search button picks a node: the one under the pointer is
outlined, and a click selects it, opening the tree down to it. The nodes
are kept only while the window is shown; the times and counts always.

| | |
|---|---|
| `metrics_window(open&)` | the window, closed by its close button |
| `frame_times` | `FrameTimes { record, layout, after, draw }`, the last frame's, in milliseconds |
| `frame_counts` | `FrameCounts { nodes, roots, hits, focusables, states, animations, windows, canvas_ops }` |
| `class_name(index) -> u8[>..]` | a built-in class's name ("BUTTON"); "class N" for one a program added |

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
    glide, exits (in a list, alone, nested, coming back);
  - `rich`: markup, measuring as plain text does, wrapping, a word in two
    styles kept whole, images, `[[`, newlines, an exit; keyed spans under
    the pointer, under another widget, and their tooltip;
  - `textfx`: the built-in effects, a program's own by a block, rich text's
    spans, inheritance, popping in as revealed, an exit copy playing on;
  - `notices`: stacking and expiring, a queue's limit, a queue of the
    program's own type, clearing, text reused, long text kept whole;
  - `scroll`: the wheel, clamping, scrolling to the focus, the thumb;
  - `text_input`: typing, caret and selection, words, cut and paste,
    limits, the caret held solid while typing and then blinking;
  - `windows`: where windows start, moved and kept on the screen, resized
    by edges and corners down to their least size, raised by a press,
    what is in one cut off at its edges when it is made too narrow,
    collapsed and opened, closed and opened again in front, a press over
    two windows reaching the front one only, a context menu, rolling up
    and down, hiding (a copy in its place, taking no input) and showing;
  - `devwidgets`: property rows lined up, in one group and across two; a
    collapsing header; a tree opened and closed by its arrow, a double
    click and the keys, Left going up to the parent, open nodes kept while
    hidden; number fields dragged (finer with Shift), clamped, stepped by
    the keys and the buttons, typed in (Enter keeps, Escape doesn't, a
    click elsewhere keeps), a vector's parts; trees and headers rolling
    open and closed;
  - `table`: of 1,000 rows only those in view recorded, as the pane
    scrolls by the wheel and to its end; rows selected by a click, Ctrl
    and Shift; a table's columns sharing its width, one resized by its
    edge, the rest sharing what is left; sorting by a header, and the other
    way; a selected row shown so;
  - `split`: panes sharing a split's length, one with a fraction; handles
    dragged, moving the pane before and, if it has a fraction, the one
    after; a pane no less than its least; a split in a pane; the split
    resized, its panes keeping their fractions;
  - `metrics`: the counts and times; the nodes kept only while the
    window is shown; the tree opened by a row's arrow; a node picked,
    selected, its parents opened, outlined; the class names in step with
    the classes (the last name is CLASS_COUNT's);
  - `small`: an icon button, a toggle and a small button clicked; a
    link clicked and accepted; a knob dragged and stepped; a standing
    slider clicked and stepped, its label inside it; a range's nearer
    thumb taken, not past the other, the keys moving the one taken and
    accept changing which; an angle in degrees; a label and value,
    bullets, a spinner;
  - `save`: a layout saved and loaded, all of it changed in between:
    docked and floating windows, a collapsed one, the order, a pane, an
    open header, a closed window's flag; the text the same saved twice;
    bad layouts refused, nothing changed; a file; windows first shown
    after loading keeping its order;
  - `dock`: a layout made in code, each body in its leaf; tabs, one shown,
    another clicked, one dragged past another, and again with a slide, under
    the pointer as it goes; the shown tab the bar's one stop, Left and Right
    showing the tabs beside it, and going on to the next bar from the end; Tab from a tab into its window; a button in a docked
    window; the handle between two leaves; a tab dragged out, floating,
    still held; a floating window dragged over a leaf, its targets shown,
    let go off them and on one (the area shown first), docked; a target by
    the space's outer edge; windows let go on a tab bar, before its tab and
    past them all, the tabs making room for them; a tab's close button, and the window opened
    again in its place; a full tab bar's list; a tab bar hidden and shown;
    a floating window dropped on another, the two in a floating dock that
    moves with them and is drawn under them, a tab dragged out of it; a
    leaf's last window undocked, the leaf gone;
  - `log`: the ring dropping the oldest past its count and its bytes; text
    split into lines; a view following the newest, stopping when
    scrolled back, following again at the end; filtered by text and by
    level; a console running and echoing commands, its history by Up and
    Down; logging from a loop over string literals;
  - `plots`: a rolling buffer; a line plot's range, fitted or fixed, and
    the value under the pointer; a bar plot's bar under it; hex written
    and read; a picker's square, hue and alpha dragged, its hue kept
    through black, a channel and the hex typed in; a color field opening
    and closing its picker;
  - `events`: UI events for sounds: a hover once and only by moving, a
    press, an activation, a denial, focus shown by navigation, slider
    ticks with and without steps, tabs, popups opening and closing, back.
- **`test/headless/`** draws and reads back: fills, borders, corners,
  gradients, opacity, isolation, clipping, motion, nine-slices, the focus
  ring, the UI scale, exits drawn after their node has gone, rich text's
  spans, image and underline, text revealed in part where it is in the
  whole, text effects moving and coloring single characters, color
  filters (`draw`); pixel-art mode: the scale, boxes on whole units, every
  unit one color, the font and theme (`pixel`); typing through gfx's injected input
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
