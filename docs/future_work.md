# Future work

What is left, roughly in order of value. Much of it comes from looking at
the HUDs and in-game menus of Hades, Slay the Spire, Stardew Valley, Horizon
Zero Dawn, Apex Legends, Hollow Knight and Diablo IV. The game examples
(`hud`, `wayfinding` and `cards`) work around what is missing, and name the
item here, by its title, at each workaround.

1. **Developer widgets.** Tools for a game's developers, in ranked order.
    The ranking assumes three kinds of program, from most to least common:
    a tweak or debug overlay over the running game, an inspector (an
    entity tree and its properties, with a log), and an editor-style tool
    of docked panels. It draws on Dear ImGui, Nuklear, egui, microui,
    raygui, tweak panels (lil-gui, Tweakpane) and the inspectors of Unity,
    Godot and Blender.

    Almost every developer UI needs these:
    1. Windows: a title bar to drag by, resizing from the edges and
       corners, collapse and close; brought to the front when clicked; kept
       on the screen; a body that scrolls. Where each one is, its size, and
       its place in the stack are kept. Everything below goes in one.
    2. A compact theme, `theme_dev()`: a small font, short rows, thin
       padding. And property rows, a label on the left and its widget on
       the right, the labels as wide as each other in a window.
    3. Collapsing headers and tree nodes: an arrow, an indent, leaves,
       selected rows; Left and Right close and open them. For an
       inspector's sections and a scene's hierarchy.
    4. Number fields: dragged sideways to change (finer with Shift, coarser
       with Alt), double-clicked or Ctrl-clicked to type in, clamped,
       formatted, for each number type; a form with step buttons; and
       vectors of two to four, their parts tagged X, Y, Z, W in color.
    5. Context menus, opened by a right click on a widget.

    Common in tools:
    6. Plots, on canvases: lines from an array or a rolling buffer (frame
       times), bars, a fixed or fitted range, the value under the pointer,
       and a small sparkline.
    7. A color field: a swatch that opens a picker, with a saturation and
       value square, hue and alpha bars, and RGB, HSV and hex fields.
    8. Tables: a header, columns resized by dragging their edges, sorting by
       a header's click (the program sorts, by the order handed back),
       striped and selected rows, a header that stays as the rows scroll,
       and only the rows in view recorded. Reordering and hiding columns
       later.
    9. A list clipper, recording only the rows of a long list that are in
       view, and selecting several rows with Shift and Ctrl, in lists, trees
       and tables.
    10. A log and a console: lines that stay scrolled to the newest unless
        scrolled back, colored by level, filtered, copied; a command line
        with its history on Up and Down.
    11. Splitters and side panels: panes resized by dragging the line
        between them.
    12. Docking: windows dragged by their titles onto a dock space, to a
        side of a pane (splitting it) or its middle (a tab with the others
        there), and dragged out again to float. The dock space is a tree of
        splits that lasts. It builds on windows, splitters, tabs, and drag
        and drop. It is last of these only because an overlay seldom needs
        it; an editor always does.

    Useful, less often:
    13. Layouts saved and loaded: where the windows are, which are open,
        and the dock tree, in a file.
    14. Multi-line text editing (under Text, below).
    15. Small pieces: small and icon buttons, toolbars and a status bar, a
        label and its value, bullets, links, a spinner, vertical, angle
        and range sliders, a knob.
    16. An image viewer: a texture panned and zoomed, with a pixel grid and
        the value under the pointer.
    17. imgui's own tools: a window of its nodes, the one under the pointer
        outlined, with counts and timings; a style editor.
    18. A memory viewer in hex, and a profiler's timeline (an example on a
        canvas more than a widget).

    Not planned: windows of the OS's own (gfx has one), a code editor,
    node graphs, gizmos for 3D, file dialogs, curve and gradient editors.
    A program can make them from canvases.
2. **Gamepads, and prompts for the device in use.**
   - Gamepads from gfx: gfx's v1 has no gamepad calls, so a program reads
     its pad and passes it to `nav_from_pad`. Once a gfx release has them,
     `input_from_gfx` should read the first pad itself. The
     `crowded-additions` branch of goose_gfx has them already.
   - `last_device()`: POINTER, KEYBOARD or PAD, by what was used last.
     A footer of prompts ("A Select, B Back") shows that device's glyphs.
   - `prompt(action)` would draw the glyph for an action, from a table of
     images the program fills in for each device.
3. **Text.**
    - Multi-line editing.
    - IME composition.
    - Measurements cached by text, font and size, if the benchmark shows a
      need.
    - Text drawn wrapped only where it must be.
4. **A radial menu.** Items around a circle, chosen by the pointer's angle
    or the stick's, on release: a ping wheel, a weapon wheel. It needs the
    stick's direction, which `nav_from_pad` turns into d-pad steps now.
5. **A safe triangle for submenus.** Moving the pointer diagonally from a
    submenu's item toward the submenu crosses the items below or above it,
    and hovering one of those closes the submenu before the pointer gets
    there. Desktop menus ignore hovers inside the triangle from where the
    pointer was to the submenu's near edge, for a moment, while the pointer
    keeps moving toward it. `menu_item`'s "hovering closes a sibling's
    submenu", and `menu`'s hover-to-open, would both check it.
6. **The display's scale from gfx.** imgui's scale is the program's to set
    (`set_scale`, `IMGUI_SCALE`). gfx could expose SDL's display content
    scale and its window size in points, and then imgui would start at the
    right size on a high-density screen without being told.
7. **Backdrop blur:** a panel that blurs what is behind it. gfx2d's layers
    blur their own content but only copy their backdrop. gfx2d needs to
    blur the backdrop first (its future work, item 16: "A layer can't blur
    what is behind it"), and then a Desc could have `backdrop_blur(s)`.
8. **Sizes from aspect ratios** (an image box as wide as its height says),
    and grid tracks of `minmax`.
9. **Momentum scrolling** and drag-to-scroll for touch, and scroll snapping
    (a carousel of cards).
10. **Accessibility:** the tree is all there, so an outline of it could be
    given to a screen reader.
11. **Several contexts:** the state is global, as gfx2d's is. Gathering it
    into a `root struct` would allow, say, a UI in the world and a UI on
    the screen.

Smaller things:
- A turned or skewed node is hit where it is drawn, but its
  `Interaction.pointer` is from the box around it. Its own pixels would
  need its inverse transform kept with its state.
- An exit's copy is drawn where it was in its parent's layout: if the
  parent is a scroll pane that scrolls while the exit plays, the copy
  stays put. Its own motion (an enter not yet over, a glide) stops where it
  was, too.

Some things seen in games can be made now:
- Staggered rows of slots: rows, each with its own left padding.
- Ornaments that reach past a panel's edges: `absolute` images in a
  `stack`.
- A compass strip, a clock and a minimap that doesn't turn: canvases.
