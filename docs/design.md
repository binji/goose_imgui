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

**Non-goals for now:** docking, multiple OS windows, tables, trees,
plotting and the other developer-tool widgets. These are in
[future_work.md](future_work.md). Goose already has `ui` (Nuklear) for
developer UIs. Custom drawing inside the layout (charts, meters) came
after the first set: see [Canvases](#canvases).

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
  ghost copies. `t` runs from 0 to 1 as the item appears and back as it
  leaves. `alive` stays true until it has left, so the program keeps
  drawing it while it fades out.
- The per-node transitions are:
  - `.enter(fade_in(m))`, `slide_in(dx, dy, m)` or `pop_in(scale, m)`,
    which play the first frame a node's ID appears;
  - `.glide(m)`, which animates the node from its last laid-out rect to its
    new one, so reordered list items slide into place;
  - `.delay(s)`, for staggering a list.
- Opacity is multiplied into colors, which is cheap. `.isolate()` draws a
  subtree through a gfx2d layer instead, so overlaps within it don't show
  through each other. That costs a pass.
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
the input this frame.

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
| `style.goose` | `Style`, `StyleSet`, the class registry, themes |
| `draw.goose` | the draw walk |
| `widgets.goose` | buttons, toggles, sliders and the rest |
| `scroll.goose`, `popup.goose`, `text_input.goose` | the larger widgets |
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
