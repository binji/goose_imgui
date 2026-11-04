# Future work

What is left, roughly in order of value.

1. **A drawing API for custom content.** A `canvas(id, d) { … }` whose block
   records draw commands (lines, shapes, paths, text, images) into a
   per-frame list. The list is replayed at draw time, in the node's box,
   under its transform and clip. Blocks can't be kept until draw time, so
   the commands have to be data. This is how charts, minimaps and
   meters get drawn inside the layout. A program can already draw with
   gfx2d after `imgui::frame`, at a widget's `rect_of`, but over the UI
   rather than in it.
2. **A safe triangle for submenus.** Moving the pointer diagonally from a
   submenu's item toward the submenu crosses the items below or above it,
   and hovering one of those closes the submenu before the pointer gets
   there. Desktop menus ignore hovers inside the triangle from where the
   pointer was to the submenu's near edge, for a moment, while the pointer
   keeps moving toward it. `menu_item`'s "hovering closes a sibling's
   submenu", and `menu`'s hover-to-open, would both check it.
3. **Exit transitions without the program's help.** `presence` needs the
   program to keep drawing what is leaving. Instead, a node with an `exit`
   could leave behind a copy of its subtree's nodes, drawn while it plays
   out.
4. **The display's scale from gfx.** imgui's scale is the program's to set
   (`set_scale`, `IMGUI_SCALE`). gfx could expose SDL's display content
   scale and its window size in points, and then imgui would start at the
   right size on a high-density screen without being told.
5. **Gamepads from gfx.** gfx's v1 has no gamepad calls, so a program reads
   its pad and passes it to `nav_from_pad`. Once a gfx release has them,
   `input_from_gfx` should read the first pad itself. The
   `crowded-additions` branch of goose_gfx has them already.
6. **Text.**
   - Multi-line editing.
   - A blinking caret that pauses while typing (now it resets on each edit).
   - IME composition.
   - Measurements cached by text, font and size, if the benchmark shows a
     need.
   - Text drawn wrapped only where it must be.
7. **Developer widgets:** tables with resizable columns, trees, color
   pickers, number fields with drag, plots (on the canvas above).
8. **Sizes from aspect ratios** (an image box as wide as its height says),
   and grid tracks of `minmax`.
9. **Momentum scrolling** and drag-to-scroll for touch, and scroll snapping
   (a carousel of cards).
10. **Per-node rotation**, beside the offset and scale.
11. **Sounds on interaction:** a hook, polled once a frame, for "a button
   was hovered or clicked", for a game's UI sounds.
12. **Accessibility:** the tree is all there, so an outline of it could be
    given to a screen reader.
13. **Several contexts:** the state is global, as gfx2d's is. Gathering it
    into a `root struct` would allow, say, a UI in the world and a UI on
    the screen.
