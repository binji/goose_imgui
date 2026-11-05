# goose_imgui: design

An immediate-mode GUI for Goose, for the UIs of games: title screens,
pause menus, settings, inventories, HUD panels, dialogs. It draws through
[goose_gfx2d](https://github.com/binji/goose_gfx2d) and reads input from
goose_gfx's `gfx`. It is written entirely in Goose.

This document is the plan and the reasoning behind it.
[imgui.md](imgui.md) is the reference for what was built.

## Goals

1. **An immediate-mode call style.** The program describes its UI every
   frame with ordinary code, in the style of Dear ImGui:
   `if imgui::button("Play") { start(); }`. There are no widget objects to
   create, keep in sync or destroy.
2. **It can look like the game.** Every widget's look is data (colors,
   gradients, borders, radii, shadows, nine-slice images, fonts) in a theme
   the program can replace or edit. Every built-in widget is made of the
   same public primitives a program uses, so a widget the theme can't
   express can be written from scratch in a few lines.
3. **Real layout.** Rows and columns with gap, padding, justify, align,
   grow and wrap (CSS flexbox); grids of fixed, fractional and
   content-sized tracks (CSS grid); stacked overlays; and anchored popups.
   Every size can be fit-to-content, fixed, grow or a percentage, each with
   a min and a max.
4. **Motion, optional.** New items can fade, slide or pop in. Moved items
   glide to their new place. State changes (hover, press, focus) ease
   between looks. Any value can be animated by key with a tween or a
   spring. Everything defaults to instant, so a traditional UI needs none
   of it.
5. **Pad and keyboard first.** Every interactive widget can be focused,
   moved between with the d-pad, arrows or Tab, activated with A or Enter,
   and backed out of with B or Escape. Focus is trapped in modals and
   menus, and scrolls into view.

**Next: developer tools.** Movable windows, docking, trees, tables, number
fields, color pickers, plots and a log, so that a game's debug overlays and
its editors are made with the same library as its menus, in its own
themes. Goose's `ui` (Nuklear) covers some of this, but it draws and lays
out on its own and can't use gfx2d's looks. [future_work.md](future_work.md)
ranks the widgets by how often a developer's program needs them.

**Non-goals:** windows of the OS's own (gfx has one window), and the tools
a program can build from canvases (node graphs, gizmos, code editors).
Custom drawing inside the layout (charts, meters) came after the first set:
see [Canvases](#canvases).

## The frame

```goose
while gfx::frame() {
    gfx2d::frame(gfx2d::BLACK) {
        draw_game();
        imgui::frame() {                       // records, lays out, then draws
            imgui::box("menu", imgui::column().gap(12).padding(24).skin(imgui::PANEL)) {
                imgui::text("Paused", imgui::TITLE);
                if imgui::button("Resume") { paused = false; }
                imgui::slider("Volume", volume, 0, 1);
                if imgui::button("Quit") { gfx::quit(); }
            };
        };
    };
}
```

Each frame goes through four steps.

1. **Begin.** The input, either from `gfx` or a struct the program built,
   is resolved against the **previous frame's** hit list, using the pointer
   where it is now. This settles which widget is hovered, which is held,
   and what was clicked. Navigation input moves the focus among the
   previous frame's focusable rects.
2. **Record.** Calls append nodes to a flat, per-frame array, in pre-order.
   Each node has parent, first-child, last-child and next-sibling links,
   given as indices. A widget call returns its result right away, because
   step 1 already knows it. Text is copied into a per-frame byte arena.
3. **End.** The tree is laid out (see [Layout](#layout)). Then motion is
   applied: enter transitions, layout glides, and state easing. Then the
   hit list, the focus list and the per-ID state are written for the next
   frame. IDs not seen for a while are dropped.
4. **Draw.** A recursive walk draws each node through gfx2d. Nested clips
   (scroll panes) and isolated layers are gfx2d's scoped blocks. Popups,
   menus, tooltips and modals are separate roots, drawn after the main
   tree in the order they were opened.

This is the deferred model of Clay and egui, not Dear ImGui's
place-as-you-go. Flex and grid need every child's size before any child
can be placed, so the layout has to come after the whole tree is known.
The price is that a click is tested against where things were drawn last
frame. That is also where the player saw them, so nothing is lost.

`imgui::frame()` draws only when it runs inside a gfx2d frame. Pure tests
call it outside one and get the layout with no GPU at all.

## State

There is no heap, so state lives in globals, like gfx2d's:

- **Per frame:** `Node[>..]`, the text arena, the parent and ID stacks,
  and the list of roots. All are cleared at begin. Nodes are reached by
  `i32` index, never by stored reference, so clearing is always legal.
- **Persistent:** `dictionary<u64, WidgetState>` and
  `dictionary<u64, AnimState>`, both of fixed-size values.
  - `WidgetState` holds the last rect and the shown rect, the hover, press
    and focus amounts (0 to 1), the scroll offset and content size, the
    caret and selection, open/closed, and the frame last seen.
  - The pattern is to copy a state out, change the copy, and insert it
    back. No `get` reference is ever held across a call that could
    insert.
  - Entries not seen for 120 frames are removed.
- **Between frames:** the hit list, the focus list and the scroll regions,
  each with its rect, clip and root.

## IDs

An ID is a `u64`: `hash_combine` of the enclosing scope's ID and the hash
of a label or an integer.
- `"Play##main"` shows "Play" but hashes the whole string, as in Dear
  ImGui.
- `id_scope(i) { … }` gives each iteration of a loop its own scope.
- A box without a label is keyed by its parent and its index among its
  siblings, which is stable as long as the structure is.
- Motion that follows an item as it moves (enter, glide) needs a labeled or
  keyed ID.
- Explicit IDs have their own type, `Id`, so `box(id, d)` is never
  ambiguous with `box(i, d)`, where `i` is an integer key.

## Descriptors

A node is described by a `Desc`, a fixed-size struct built by chaining
copy-and-modify setters:

```goose
imgui::row().gap(8).padding(12, 6).align(imgui::CENTER).grow_w().skin(imgui::PANEL)
```

- Goose has no named arguments. Chained UFCS calls on a value give the same
  readability, and a named struct literal with `..` is the long form.
- A setter must not share its name with a field of `Desc`, because a field
  wins over a function. So the setter-facing struct uses short internal
  field names (`lay`, `dim`, `vis`, `mot`, `bits`).
- `pad` is a keyword, so padding is set with `padding`.
- Scalars are `f64`, as in gfx2d, so any number can be passed.
- What few nodes use is kept out of the structs that every node copies.
  56 bytes more in `Style` made recording about 12% slower, used or not.
  So text effects (letter spacing, outline, shadow, glow) are indices:
  - A Style refers to a `TextLook` registered by `add_text_look`, as it
    refers to a nine-slice.
  - A Desc's setters put theirs in a table. Set during a frame, they go in
    that frame's table, and using the Desc in a later frame is misuse. Set
    outside any frame (a Desc made once and kept), they go in a lasting
    table, with each different value stored once.
  - Each node keeps an index into the frame's resolved looks. It is its
    parent's unless its style or Desc changes something.

## Layout

**Containers** are `row()` and `column()` (flex), `grid(tracks)`, and
`stack()`, which lays its children over each other.
- Containers set `gap`, `padding`, `justify` (START, CENTER, END,
  SPACE_BETWEEN, SPACE_AROUND, SPACE_EVENLY) and `align` (START, CENTER,
  END, STRETCH).
- A row can `wrap()`.
- A child can override the cross-axis alignment with `self_align`.
- A child can be `absolute(x, y)`: placed in its parent's padding box,
  outside the flow.

**Sizes**, on each axis:
- `fit()` (the default): the content's size;
- `px(v)`;
- `grow(weight)`: a share of what's left;
- `pct(f)`: a fraction of the parent's inner size.

Each can also have a min and a max.

**Grids:**
- Tracks are `track_px(v)`, `fr(n)` or `auto_track()`, up to 8 columns and
  8 rows.
- Children go in row-major order, or into the cell they name with `cell`.
  They can span cells.
- Rows that aren't given are `auto`.

**The solver** runs in passes over the flat array. Children always come
after their parents, so no pass recurses.
1. **Fit widths, bottom up.** This is a reverse index walk. Text's fit
   width is its width without wrapping, and wrapped text's minimum is its
   longest word.
2. **Resolve widths, top down.** Grow and shrink happen along the main
   axis, stretch across it, and percentages resolve. Grid columns are
   sized here.
3. **Wrap and fit heights, bottom up.** Wrapped text is measured at its
   final width. Wrapping rows are broken into lines here.
4. **Resolve heights, top down.**
5. **Positions, top down.** Justify, align, grid cells, scroll offsets and
   absolute children are placed. Then popup roots are placed by their
   anchors.

Popup roots are laid out after the main root, in the order they were
opened. So a menu anchors to the menu button's rect from this same frame.

## Look

A node's look is a `Style`:
- the background: a color, or a two-color vertical or horizontal gradient;
- a border color and width;
- per-corner radii;
- a box shadow;
- padding;
- ink (text color), font and text size, which the node's text descendants
  inherit;
- an optional nine-slice image and its tint;
- opacity, an offset and a scale (so a pressed button can shrink a
  little);
- a focus ring;
- a minimum size.

A **StyleSet** has one Style for each state: normal, hover, active (held),
focused, checked and disabled. It also has a transition `Motion`, and a
mask of which states it defines.
- Each widget class is a StyleSet in the theme's registry, reached by a
  `StyleClass` index: BUTTON, PANEL, CHECKBOX, SLIDER_TRACK, TAB, and so
  on.
- The node records its class and its state amounts.
- The style is mixed at record time, from normal toward checked, hover,
  active and focused by their amounts, with disabled overriding.
- The amounts ease by the class's transition. A transition of 0 makes them
  flip as they would in a traditional UI.
- A program can make its own classes (`add_class`), restyle the built-in
  ones (`set_class`), or override a single node's colors and radii inline
  (`.bg(c)`, `.radius(r)`, `.border(w, c)`).
- Three themes are built in: `theme_light()`, `theme_dark()`, and
  `theme_game()`, which uses gradients, shadows and bold type, to show how
  far a skin can go.

Nodes hold a class index and the mixed `Style`, about 200 bytes. They never
hold a gfx2d `Paint`, which is about 500 bytes because of its 16 gradient
stops. Gradients are built at draw time from the style's two colors and
the node's rect.

## Motion

Motion is data, because Goose can't store a function. A `Motion` is one of:
- `tween(seconds, EASE_*)`;
- `spring(stiffness, damping)`;
- `INSTANT`.

Any of them can also have a `delay`. Springs integrate in fixed 1/240 s
steps, so they move the same at any frame rate.

- `animate(key, target, m)` returns the current value for an `f64`,
  `float2` or `Color`, keyed by ID. The value moves toward the target, and
  retargeting mid-flight is smooth.
- `presence(key, visible, m) -> t, alive` handles enter and exit with no
  copies. `t` runs from 0 to 1 as the item appears and back as it
  leaves. `alive` stays true until it has left, so the program keeps
  drawing it while it fades out.
- The per-node transitions are:
  - `.enter(fade_in(m))`, `slide_in(dx, dy, m)` or `pop_in(scale, m)`,
    which play the first frame a node's ID appears;
  - `.glide(m)`, which animates the node from its last laid-out rect to its
    new one, so reordered list items slide into place;
  - `.delay(s)`, for staggering a list;
  - `.exit(fade_out(m))`, `slide_out` or `pop_out`, which play on a copy
    once the node's ID is not recorded (below).
- Exits without the program's help: each frame, every node with an exit
  is copied with its subtree (its nodes, text, looks and canvas commands,
  their indices made relative). The next frame, a copy whose ID was not
  recorded is drawn again, among its parent's children after the sibling
  it came after, or over the main root where it was if its parent is gone
  too. A copy inside another that is leaving is drawn in that one. Copies
  are added after layout and the hit list, so they take no space and no
  input, and are kept by copying them again each frame until their exit is
  over. Only what has an exit is copied, so a frame without exits pays a
  test per node. And only what is drawn: a subtree wholly outside its clip
  (rows scrolled out of a pane) is left out of the copy, as the draw would
  skip it, so a copy costs what is on the screen. A window's copy, taken
  every frame while windows have exits, cost 0.05 to 0.1 µs a node before
  this: a 250-row list in one, 3,767 nodes, 0.15 to 0.35 ms a frame. Now
  it is 20 to 40 µs, about what a 50-row list costs (11 µs). The Exit itself is kept out of the Desc, in a table, as
  text effects are: it would add 36 bytes to every Desc copied, and cost
  about 5% of a frame.
- Notices are the program's events shown for a while, in queues the
  program keeps, of two kinds. A `Notices<T>` holds the program's own data,
  fixed-size, as an element of a growing array must be, so imgui guesses
  at no fields and a notice of an `i64` holds that and its time. A
  `TextNotices` holds text of any length: each notice's is a run of one
  `slice_pool<u8>` shared by every queue, taken when it is posted and given
  back whenever it is dropped, so its space is reused. (The pool can't be
  in the queue: a root can't own another yet.) One kind holding both would
  keep room for text in notices that have none, or need the program to
  free its own data, and Goose can't keep a function in a queue to do it.
  The two share their bookkeeping: dropping and drawing are generic over
  the notice, the text queue's dropping giving back its text. A queue is
  bounded only by the limit the program gives it. `notify` drops what has
  expired, so a queue not drawn doesn't grow, and
  `notices` draws the queue each frame, dropping what has expired first. A
  dropped notice is simply not recorded, so its exit plays as any other
  node's does: notices need nothing of their own to leave.
- Opacity is multiplied into colors, which is cheap. `.isolate()` draws a
  subtree through a gfx2d layer instead, so overlaps within it don't show
  through each other. That costs a pass.
- A color filter (`.filter(m)`) is that layer's color matrix. The matrix is
  80 bytes, so a Desc holds where it is in a table, as it does its text
  effects and exit; the node it is recorded in moves it into the frame's
  `node_filters`, which an exit's copy carries along with the node.
- Time comes from the `dt` passed to the frame. Tests pass a fixed one.

## Input

`Input` is a plain struct holding:
- the pointer: position, down, pressed, released, clicks, wheel;
- navigation buttons: up, down, left, right, next, prev, accept, cancel,
  tab_left, tab_right;
- modifiers;
- the text typed this frame;
- edit keys.

`input_from_gfx()` builds an `Input` from gfx's mouse and keyboard, and
from the ordered event list for text. gfx's v1 has no gamepad calls (they
are on a later branch), so a program that reads a pad passes what it
holds to `nav_from_pad`. That turns held directions into presses that
repeat. Tests build their own `Input`, because gfx can't inject wheel or
gamepad input.

`wants_pointer()` and `wants_keyboard()` tell the game whether the UI took
the input this frame. Anything with a background takes the pointer, as a
menu's panel should. A HUD's panels often should not, so `passthrough()`
lets it through a subtree. The widgets in that subtree still take it.

## Navigation

- **Focusable nodes** go in a per-frame focus list, with their rect, nav
  scope and root.
- **Moving focus:**
  - The d-pad or arrows move focus to the best candidate in that
    direction, scored by distance along the axis plus a penalty for being
    off it.
  - Tab moves in tree order.
  - Accept activates the focused widget, and cancel closes the innermost
    popup or modal. Otherwise cancel is reported to the program with
    `cancelled()`.
- **Scopes:** `nav_scope(id, flags) { }` groups nodes. NAV_TRAP keeps focus
  inside the scope, and NAV_WRAP wraps around at its ends. Modals and
  menus trap focus automatically.
- **Focus ring:** the ring shows only after navigation input, like CSS
  `:focus-visible`. Pointer use hides it.
- **Scrolling and popups:** focus moved by navigation scrolls its scroll
  panes to keep it in view. A closing popup gives focus back to the widget
  that opened it.

## Pixel art

- A pixel-art UI wants its own pixels square: a whole number of screen
  pixels a unit, every box on whole units, nothing blended at edges, and
  images sampled nearest. One switch, `set_pixel_art`, does all of it, as
  the parts are useless apart: whole boxes at a fractional scale still
  land between screen pixels.
- Boxes are snapped after layout, each edge rounded, not each size: two
  boxes that meet still meet. Motion's shifts are rounded too; a zoom is
  not, so a scaled box can leave the grid.
- Antialiasing is gfx2d's switch, set while imgui draws and put back
  after. Images and nine-slices default to `FILTER_DEFAULT`, which gfx2d
  turns into nearest when antialiasing is off, so a program's choice of
  filter still wins.
- `theme_pixel` is the built-in theme with every length scaled to the
  font and rounded, rather than a second table of numbers: a class added
  to the themes later gets a pixel look without being listed here. Text
  sizes are made the font's own, since a bitmap font at 0.875 of its size
  loses its pixels.
- The built-in font is small capitals 3 x 5: enough for menus and HUDs in
  any example or test without the program drawing one.

## UI events

- Sounds are the program's: imgui keeps a list of events a frame, and
  plays nothing. A list read after the frame, not a callback, since a
  Goose function value can't be stored, and the program's audio is its
  own business anyway.
- Hovers, focus, presses and activations come from `interact`, so every
  widget, the program's own too, has them, and each carries its class:
  a program picks a sound for buttons and another for tabs without
  naming IDs.
- Each widget keeps whether it was hovered, and showing focus, the frame
  before, so the events fire as they begin. A hover counts only when the
  pointer moved: a menu that opens, or a page that changes, under a still
  pointer would otherwise tick for whatever lands under it. Focus counts
  only as navigation shows it, so a click doesn't sound twice.
- A dragged slider changes every frame. It ticks instead, a ratchet:
  once a step, or once a twentieth of its range without one.
- Events raised between frames (a popup opened by the program's own
  logic) go in the next frame's list: the list in progress is published
  when a frame ends.

## What building it taught

- **The root is a stack.** Top-level boxes are each placed by
  `place(h, v)`: a HUD's corners, a centered menu. A program wanting one
  flow of boxes puts them in a column.
- **Hit testing follows draw order.** The hit list is written root by
  root, not in record order. Otherwise a popup recorded inside the menu bar
  would sit under the main tree recorded after it.
- **The borrow checker shaped the buffers.** A program's loop over string
  literals (`for name in ["Easy", "Hard"] { radio(name, …); }`) may not
  call a function that can shrink a growable `u8` global, nor an array
  whose elements have `u8` fields. So:
  - the misuse and clipboard buffers are limited arrays;
  - the default theme is built by a global's initializer, not on first use;
  - only `theme()` replaces the registry.
- **Fixed-size buffers are copied** into untyped parameters, so
  `text_input` takes its buffer as `A&`.
- **Culling.** Drawing dominated the benchmark until subtrees outside
  their clip were skipped. Each node's bounds are found in one reverse
  pass after layout.

## Canvases

A canvas is a box whose block draws. Goose can't keep a block until the
frame is drawn, so its calls (`fill_rect`, `stroke_polyline`,
`draw_text`, …) are recorded as commands into a per-frame list. Each
command names the node it belongs to. At draw time the list is replayed
from the box's inner corner, between its background and its children,
inside its clip, motion transform and opacity.

The block is given the inner size from last frame's layout. The layout
isn't known yet while the block runs, and charts want to fill their box.
What the commands reach is kept per node, so culling counts drawing that
spills past the box.

## Windows

- A window is a root of its own, as a popup is, so it is laid out after
  the main tree and placed by its anchor: a point, its kept top left. It
  can be recorded anywhere, even inside another box: what it contains
  isn't the box's.
- Roots are drawn and hit in one order, made after layout: the main root,
  the windows back to front, then the rest as recorded. So a menu opened
  from the menu bar before a window is recorded still opens over it, and a
  dropdown inside a window over the windows in front of it. Without
  windows the order is the one before them.
- The windows' order is a list of IDs, back to front, kept between
  frames. A press anywhere in a window puts it in front: each hit carries
  the window it is in, so the press is known to be in it before anything
  is recorded, wherever in the window it lands.
- A window's own state (its place, size, collapse, and where a drag began)
  is in a dictionary of its own rather than in `WidgetState`, which every
  widget has and which is dropped once its ID isn't seen for a while. A
  window closed for a minute comes back where it was.
- Its title bar, buttons and grips are asked for their interactions before
  anything is recorded, so a move or a resize is drawn the frame it
  happens, not a frame late. The size goes in the frame's Desc, the place
  in its root's anchor.
- Rolling up (`set_window_roll`) is an amount from 0 to 1 animated by the
  window's ID, which starts where it is going, so a window first seen
  collapsed doesn't roll. While it moves, the frame is the title bar's
  height plus that much of the body's height when it was last open, and
  the body, at that whole height, is in a clipping box as tall as has
  rolled out: the content doesn't reflow or scroll as it goes. A spring's
  overshoot is clamped, as the body can't be taller than itself. The grips
  wait until it is open.
- Showing and hiding (`set_window_show`) are the window frame's enter and
  exit, so a window hides however it goes, closed by its cross or simply
  not recorded, without imgui running the program's block after it has
  gone. Its copy would be put under the main root, below every window, so
  a window's copy is made a window root of its own, without input, and the
  roots are ordered again after the copies are placed: it fades out where
  it was among the windows. A window showing or hiding is isolated, so
  that its parts don't show through each other; at rest it isn't, as a
  layer costs a pass.
- A box can't be narrower than its content's least width, so a window
  made narrower than a long line or a row of fields would have had its
  body (and its title) reach past its edges, the body's clip with them.
  Both have `SHRINKS`: their least width is their padding's, so they are
  as wide as the window, and what doesn't fit is cut off. It acts across
  only: a title bar that could shrink down would lower the window's least
  height, which is reckoned from it.
- A window fits its content until it is resized, and then keeps its size.
  Its body is a scroll pane that grows, so a fitted window that the screen
  is too small for still scrolls.
- The grips are thin boxes astride the frame's edges, recorded last so
  they are hit first near an edge. The frame doesn't clip, so that they
  can reach past it; its title bar rounds its own top corners instead.
- A grip asks for a pointer shape, read by `cursor()`. gfx v1 can't change
  the pointer's shape, so imgui only says which it wants.
- A context menu is a menu popup at the pointer, opened by a right press
  on the widget it is given. A right press anywhere else closes the menus,
  as a left one does.

## Developers' widgets

- **Property rows** are a grid of two columns, the labels' fit and the
  widgets' grow, so a group lines up without the program measuring
  anything. Each window keeps its widest label from the frame before (a
  label's width is known as it is recorded), and every group in it takes
  that as its labels' column's least width, so groups under different
  headers line up too.
- A property's label is centered down its cell in a column of its own,
  and its widget's cell stretches across with the widget centered down
  it: a grid cell's `self_align` would center it both ways.
- **Open state** of headers and tree nodes is kept in a dictionary of its
  own, never swept. Widget state is dropped after 120 frames unseen, and
  the nodes inside a closed one aren't recorded, so they would forget
  that they were open.
- A tree node's row takes Left and Right (`CAPTURE_X`): Right opens, Left
  closes, or, on a closed node or a leaf, moves the focus to its parent,
  found from the open nodes recorded around it.
- **Number fields** change by the pointer's movement each frame, not by
  where it was pressed, so pressing or letting go of Shift mid-drag
  changes the rate from there on without a jump. The value before
  rounding is kept in the widget's state as an `f64` (a slider's `f32` is
  too coarse for a double), so slow drags of whole numbers add up.
- Typing in one swaps the field for a `text_input` of one buffer shared
  by all of them, as only one has the keyboard at a time. A click that
  didn't drag starts it, as in Blender, rather than a double click or
  Ctrl-click: easier to find, and a drag is never mistaken for it.
- **Rolling** a header or tree node open and closed (`set_tree_roll`) is
  a window's roll without the window's trouble: its content, at its whole
  height, is in a clipping box as tall as has rolled out. That box has no
  ID, so the content's IDs (and its widgets' state) don't change as it
  rolls, and it has `OVERFLOW_Y`, which lays out its children as a scroll
  pane does, at their content's height whatever its own. So the content's
  whole height is measured even as it starts to open the first time, and
  read the next frame, when it matters.
- **A row list** records only what is in view, so it has to know what
  that is before layout. Its rows are all one height, so where row k is
  needs no measuring: each is placed absolutely at k times the step, in a
  box as tall as all of them, so a scroll pane scrolls it, and shows its
  scrollbar, as if every row were there. After layout, the part of the
  list its clip showed is kept in its state (the `ROW_LIST` bit asks for
  it), with the offset of the pane it is in. The next frame the pane may
  have scrolled (the wheel eases it), so the range moves by the
  difference, and a row more each way covers the rest. 10,000 rows of
  text in a pane (AOT, on the benchmark's machine): 10,004 nodes, 1.77 ms
  to record and 1.54 ms to lay out a frame; in a row list, 75 nodes,
  0.02 ms and 0.01 ms.
- **Selection** is the program's: a `bool` for each row, in its own array,
  which `select_row` changes as a desktop list does. imgui keeps only each
  list's anchor for Shift.
- **A table** is a header row and a scroll pane holding a row list, each
  row a row of cells of the columns' widths. The widths are kept in the
  headers' state; a column never dragged has none, and shares what the
  others leave, so a table fits its box until a column is resized. Its
  columns mustn't make it wider (they are sized from its width, and would
  hold it there), so it has `OVERFLOW_X`: its children are as wide as
  their content, and it clips them. Sorting is the program's, as the rows
  are: the table keeps the column and the way, and says when they change.
- **A log** is the program's, a `root struct` (it owns two growing
  arrays: its text and its lines). Both are rings, grown once to their
  size and written over, oldest first, a line always in one piece (from
  the start, if it would run past the end). Nothing is taken out of them,
  so logging never shrinks an array, which Goose doesn't allow inside a
  loop over string literals; `logf` formats into a buffer of its own for
  the same reason.
- **A log view** is a scroll pane of a row list, so a log of any length
  costs what is on the screen; filtering makes the list of lines shown
  each frame. Following the newest line is a flag of the view's own, not
  "at the end last frame": the frame the content first grows, the pane
  is at 0, which is no longer its end. While following, the view scrolls
  to the end as it was last frame, not past it, so that a turn of the
  wheel back leaves it short of the end, and that is what stops it.
- **A split** sizes its panes itself rather than leaving them to grow:
  a growing box starts from its content's size, so panes sharing what is
  left would share it unevenly. Last frame's handles know the panes on
  their sides, so before any pane is recorded the split reads their
  fractions, gives each with one its length, and the rest equal shares
  of what is left; the last of those grows, to take what rounding
  leaves. A pane's fraction to start with is kept the first time it is
  recorded, for the next frame's reading. A handle's drag is applied
  then too, so a pane is its new size the frame it is dragged.
- **Docking** keeps a tree of nodes for each dock space, in one array
  that is never shrunk (unused nodes are taken again). A split node has
  two children and a ratio; a leaf, its windows' IDs as tabs and the one
  shown. A window's own state says which leaf it is in, and keeps its
  title and whether it can close, for its tab, which the dock space draws
  without the window's help.
- A leaf's rect is its space's last-frame rect divided by the ratios of
  the splits above it, so it is known before anything this frame is laid
  out, whatever order the dock space and its windows are recorded in. A
  docked window is then a window root at its leaf's rect, under the tab
  bar, recorded where the program calls `window(…)`: its content is the
  program's code, and needs no other place. Roots are ordered with the
  docked windows first, so the floating ones are over them.
- A tab dragged out undocks its window and hands the drag to its title:
  `active` becomes the title's ID and the press is moved to where the
  pointer is, so the window, now floating, follows the same drag, and a
  release over a dock space docks it again.
- **A tab dragged along its bar** is recorded last, at the pointer, out
  of the flow, so it is drawn over the others, with an empty box of its
  width in its place. Where each tab is along the bar is worked out from
  the order and last frame's widths, not taken from last frame's rects,
  which would be a frame behind just after two change places and have
  them change back. Sliding is the tab's place along the bar, animated
  and drawn as an offset, rather than `.glide`, which would have the tabs
  trail the bar when a handle moves it.
- **The window as its own preview** (`set_dock_preview(true)`): only
  the dragged window moves, drawn at the target's rect; its kept place and
  size don't change. Laying the whole dock out as if it were docked would
  move the targets, which are placed from the leaves' rects, out from
  under the pointer, and it would flicker between docked and not. How far
  it is toward the target and the target's rect are animated apart, so
  that dragging freely follows the pointer exactly, and moving from one
  target to another moves between their rects.
- **Tab order** is the order widgets are drawn in, root by root, but a
  root can follow a widget (`Root.after`): its focusables are put right
  after that widget's, if it is focusable that frame. A docked window
  follows its tab, so Tab goes from the tab into the window rather than
  through every tab bar first; with its tab bar hidden, the window keeps
  its place in draw order.
- A tab bar is a drop target with no square of its own: the squares are
  tested first, and the bar under the pointer after. The space's top edge
  square sits below the tab bars, so it doesn't cover the middle of the
  top leaf's bar. Where a dropped tab goes is found from the tabs' widths
  and order, without the room made for it (which would move the tabs as it
  opened, and change where it goes). The window over the bar is a
  "guest" of the bar for a frame (`dock_guest`): the dock space, recorded
  before or after the window, lays out an empty box of its tab's width
  where it goes, and draws its tab there over the others, as it does a
  tab dragged along the bar. Its width is its tab's last width, if it
  was ever docked; else its title measured.
- **A floating dock** is a window of imgui's (its ID from the window it
  was made on) whose body is a dock space of its own, with a different
  ID, as a window root and the box in it can't share one. Nothing in the
  program records it, so the first of its windows recorded each frame
  records it first: `window_with` for the window calls `record_host`,
  which calls `window_with` for the dock (so `record_host` is declared
  recursive). The frame it is made, its space isn't laid out yet, so its
  windows wait a frame rather than float. Roots are ordered with each
  floating dock's windows just over it, among the floating windows.
- A window docked by a drag is recorded docked the frame it is let go,
  not a frame later: a frame with nothing recorded would play its hiding.
- **A saved layout** is what lives outside widgets' states, which go when
  a widget isn't recorded for a while: the windows, the dock nodes, the
  panes' fractions (moved into a dictionary of their own for it) and the
  headers' open states. IDs are written as 16 hex digits, since JSON's
  numbers are f64s. Dock nodes are written by index, unused ones too, so
  the links between them and from windows stay as they are; each space's
  root is the used node with no parent, and the floating docks are the
  windows marked as hosts, so neither is written. Everything is read and
  checked (the links in range, each split's children naming it as their
  parent, windows docked in leaves) before anything is replaced. Loaded
  windows are marked as never called, so the first call doesn't raise
  them as it does a window new to the program.
- **Plots** are canvases: a plot is the values drawn, and the readout
  under the pointer is drawn too, not a tooltip, so it follows the
  pointer at once. `f32` values are copied into a scratch `f64` array, so
  both kinds share one drawing.
- **A color picker keeps its own HSV**, by its ID, and uses it while the
  color is still the one it makes: RGB can't say the hue of a gray or the
  saturation of black, so a color dragged through them would otherwise
  lose them. A color changed elsewhere (typed, or by the program) is read
  back into HSV, keeping the old hue where the new color has none.
- A color's hex is typed in as a number is: the typing that number fields
  do (the shared buffer, its text all selected, Enter or a click away to
  keep it, Escape not to) is `start_typing` and `typing`, used by both.
- `Input.mods` is new: the modifiers held, not only those pressed with a
  key, which a drag needs.

## Rich text

- `rich(s)` reads BBCode-like markup (`[dmg]20[/]`, `[img=coin]`) rather
  than taking spans from code: tooltips and cards are data, often
  translated, and the styling has to travel with the string. Brackets, not
  braces, so it doesn't read as a format string.
- Spans and images are registered by name, as classes are. A span sets
  only what it changes, over the text's own style.
- A rich text is its own kind of node, its pieces in a side table for the
  frame, as canvas commands are: a word (or the part of one in one style),
  spaces, a newline or an image, each measured once as it is recorded. So
  plain `text` costs nothing more, and a rich text is measured by
  gfx2d a piece at a time, which drops kerning across a change of style.
- gfx2d breaks lines of one style; rich text breaks its own, at spaces
  only, a run of pieces with no space between them staying whole. A line
  is as tall as its tallest piece, with every piece on one baseline, so an
  unstyled rich text measures exactly as `text` does.
- `reveal(n)` draws a text's first `n` characters where they are in the
  whole. A prefix drawn on its own would wrap and align differently (a
  word half typed fits on the line before), so plain text draws each row
  of the whole, up to the count, from where the whole row starts; rich
  text counts its pieces, newlines and broken spaces included, so both
  count a string alike. The count is kept with the text effects, out of
  the Desc, and not inherited.
- A keyed span (`[kw=burn]`) is found under the pointer from where it was
  last frame, as every widget's hover is: after layout, each keyed span's
  boxes on its lines are kept, in screen space (so turned text is found
  too). The text is not a hit target, which would take clicks from the
  card or button it is in; a span is on when the pointer is in its box and
  the widget it is in is the one under the pointer, so a panel over it
  blocks it. The text gets an ID from its string in its scope, to keep the
  span last hovered by, for a tooltip fading out.
- Drawn in passes over its lines, all shadows, then all halos, then all
  outlines, then glyphs, images and underlines, so that one piece's shadow
  or halo doesn't fall over the glyphs before it. A pass no piece needs is
  skipped.
- Soft shadows and halos are gfx2d's glows, from the glyphs' distance
  field: gfx2d draws a string's glow under all its glyphs, one glow a
  string. Plain text, drawn whole, puts one on its outline pass, or on its
  glyphs if it has no outline, so a soft shadow costs no pass of its own;
  with both, the shadow gets one, as text of no color carrying the glow.
  Rich text gives each its own pass, since a piece's glow drawn with its
  glyphs would fall over the piece before it where they touch.

## Text effects

- A program writes its own effects in Goose, and the built-in ones are
  written the same way. A function can't be stored in a Span or a Desc
  (Goose's function values exist only at compile time), so the effect
  runs where the text is recorded: `text(s, d) { g => … }` calls the block
  for each character with a `Glyph`, what the character is (its index,
  the time, how long since it was revealed, its text's and span's effect
  numbers) and what to change (offset, scale, turn, ink, alpha).
  `standard_fx(g)` is the built-in effects, an ordinary function on the
  same footing; without a block, a text with an effect runs it.
- Effects need only the index, the time and the reveal, not where the
  character lands, so working them out before layout loses nothing. They
  move only what is drawn.
- The characters' changes are in a side table for the frame; a text's
  are its canvas command range, which text never uses, so Node doesn't
  grow, and a text without effects costs nothing.
- gfx2d draws every glyph as its own quad. Its `text_glyphs(…) { g => … }`
  lets a block change each one's transform and color before it is added;
  `text` is the same code with no block, inlined, so plain text pays
  nothing for it.
- Revealed text counts a fraction: `reveal(3.4)` shows a fourth character
  just begun, and each character's `age` is how far past it the count
  is, so `FX_POP_IN` grows letters in as they are typed.
- An exit copy keeps its characters' changes. Its built-in effects are
  played again each frame, so a shaking word shakes as it fades; a
  program's own, whose block isn't run again, hold where they were.
- `set_text_motion(k)` scales offsets, scales and turns, for players who
  want less motion; colors still change.

## Widgets (first set)

| | |
|---|---|
| `text`, `image`, `spacer`, `separator` | content |
| `button`, `button_with { … }` | a label, or any content |
| `checkbox`, `toggle`, `radio` | on/off and one-of-many |
| `slider` | `f64`/`f32`/`i64`/`i32`, with a step; drag, click on the track, or left/right |
| `progress` | a bar, optionally animated toward its value |
| `selectable` | a list row that can be selected |
| `scroll { … }` | a clipped pane, scrolled by wheel, drag, scrollbar or focus |
| `tabs { tab(…) { … } }` | a tab bar and the selected tab's content; shoulder buttons switch |
| `menu_bar`, `menu`, `menu_item` | drop-down menus, submenus |
| `dropdown` | a value picked from a list in a popup |
| `popup`, `modal`, `tooltip` | overlays |
| `text_input` | single-line editing: caret, selection, clipboard |

## Repository layout

| | |
|---|---|
| `imgui.goose` | the entry: the frame API, and the imports of the rest |
| `context.goose` | the per-frame and persistent state, the clock |
| `id.goose` | IDs, labels, scopes |
| `desc.goose` | `Desc` and its setters |
| `tree.goose` | nodes, boxes, text, images, roots |
| `layout.goose` | the solver |
| `input.goose` | `Input`, `input_from_gfx`, hit testing |
| `nav.goose` | focus and navigation |
| `motion.goose` | `Motion`, easing, springs, `animate`, `presence` |
| `exit.goose` | exits: copies of what has left, drawn as they play |
| `notice.goose` | notices: queues of what the program posted once |
| `rich.goose` | rich text: markup read into pieces, broken into lines |
| `textfx.goose` | text effects: each character's change, and the built-in effects |
| `pixel.goose` | pixel-art mode: the scale, snapping, the pixel font and theme |
| `events.goose` | UI events: each frame's list, for sounds |
| `style.goose` | `Style`, `StyleSet`, the class registry, themes |
| `draw.goose` | the draw walk |
| `widgets.goose` | buttons, toggles, sliders and the rest |
| `scroll.goose`, `popup.goose`, `text_input.goose` | the larger widgets |
| `window.goose` | windows: their own roots, kept state and order |
| `devwidgets.goose` | property rows, collapsing headers, trees, number fields |
| `plots.goose` | plots, sparklines, color swatches, pickers and fields |
| `table.goose` | row lists (only the rows in view), selection, tables |
| `log.goose` | logs (a ring of lines), log views and consoles |
| `split.goose` | splitters: panes and the handles between them |
| `dock.goose` | dock spaces: a tree of splits whose leaves hold windows as tabs |
| `save.goose` | layouts saved and loaded, as JSON |
| `examples/` | programs, each a root file |
| `test/` | `run_tests.py`: `pure/` (layout, input, motion; no GPU) and `headless/` (drawn and read back) |
| `bench/` | `bench.goose` |

There is no C, so there is no CMake. `imgui.build` says the package runs on
the main thread and excludes the programs. The library imports gfx2d with
a bare `import gfx2d;`, so the program declares it. gfx2d has no release
tag yet, and a requirement line naming a source would clash with a program
that declares gfx2d by path.

## Phases

All of these are done. [imgui.md](imgui.md) is the reference.

0. Skeleton, this document, and the language spikes. These confirmed:
   - recursion through gfx2d's clip and layer blocks;
   - UFCS chaining from the program's namespace;
   - box overloads by ID type;
   - blocks ignoring their argument;
   - user recursion through `box`;
   - a library's bare `import gfx2d;`.
1. Tree, flex layout, drawing boxes and text.
2. Input, interaction, styles, and the basic widgets.
3. Navigation.
4. Motion.
5. Grid, stack, absolute, wrap, scroll panes.
6. Popups, modals, tooltips, menus, dropdowns, tabs.
7. Text input.
8. Themes and skins, the reference, the benchmark.
