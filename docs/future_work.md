# Future work

What is left, roughly in order of value.

1. **A safe triangle for submenus.** Moving the pointer diagonally from a
   submenu's item toward the submenu crosses the items below or above it,
   and hovering one of those closes the submenu before the pointer gets
   there. Desktop menus ignore hovers inside the triangle from where the
   pointer was to the submenu's near edge, for a moment, while the pointer
   keeps moving toward it. `menu_item`'s "hovering closes a sibling's
   submenu", and `menu`'s hover-to-open, would both check it.
2. **Exit transitions without the program's help.** `presence` needs the
   program to keep drawing what is leaving. Instead, a node with an `exit`
   could leave behind a copy of its subtree's nodes, drawn while it plays
   out.
3. **The display's scale from gfx.** imgui's scale is the program's to set
   (`set_scale`, `IMGUI_SCALE`). gfx could expose SDL's display content
   scale and its window size in points, and then imgui would start at the
   right size on a high-density screen without being told.
4. **Gamepads from gfx.** gfx's v1 has no gamepad calls, so a program reads
   its pad and passes it to `nav_from_pad`. Once a gfx release has them,
   `input_from_gfx` should read the first pad itself. The
   `crowded-additions` branch of goose_gfx has them already.
5. **Text.**
   - Multi-line editing.
   - A blinking caret that pauses while typing (now it resets on each edit).
   - IME composition.
   - Measurements cached by text, font and size, if the benchmark shows a
     need.
   - Text drawn wrapped only where it must be.
6. **Developer widgets:** tables with resizable columns, trees, color
   pickers, number fields with drag, plots (on a canvas).
7. **Sizes from aspect ratios** (an image box as wide as its height says),
   and grid tracks of `minmax`.
8. **Momentum scrolling** and drag-to-scroll for touch, and scroll snapping
   (a carousel of cards).
9. **Per-node rotation**, beside the offset and scale.
10. **Sounds on interaction:** a hook, polled once a frame, for "a button
   was hovered or clicked", for a game's UI sounds.
11. **Accessibility:** the tree is all there, so an outline of it could be
    given to a screen reader.
12. **Several contexts:** the state is global, as gfx2d's is. Gathering it
    into a `root struct` would allow, say, a UI in the world and a UI on
    the screen.
