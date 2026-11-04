# Future work

What is left, roughly in order of value. Much of it comes from looking at
the HUDs and in-game menus of Hades, Slay the Spire, Stardew Valley, Horizon
Zero Dawn, Apex Legends, Hollow Knight and Diablo IV. The game examples
(`hud`, `wayfinding` and `cards`) work around what is missing, and name the
item here, by its title, at each workaround.

1. **Gamepads, and prompts for the device in use.**
   - Gamepads from gfx: gfx's v1 has no gamepad calls, so a program reads
     its pad and passes it to `nav_from_pad`. Once a gfx release has them,
     `input_from_gfx` should read the first pad itself. The
     `crowded-additions` branch of goose_gfx has them already.
   - `last_device()`: POINTER, KEYBOARD or PAD, by what was used last.
     A footer of prompts ("A Select, B Back") shows that device's glyphs.
   - `prompt(action)` would draw the glyph for an action, from a table of
     images the program fills in for each device.
2. **Text.**
    - A soft text shadow. `text_shadow` is a hard copy; the glyphs'
      distance field could be drawn wider and faded to blur it. That is
      gfx2d's "No text glow, and no soft text shadow" (its future work,
      item 14) first.
    - Multi-line editing.
    - IME composition.
    - Measurements cached by text, font and size, if the benchmark shows a
      need.
    - Text drawn wrapped only where it must be.
3. **A radial menu.** Items around a circle, chosen by the pointer's angle
    or the stick's, on release: a ping wheel, a weapon wheel. It needs the
    stick's direction, which `nav_from_pad` turns into d-pad steps now.
4. **A safe triangle for submenus.** Moving the pointer diagonally from a
    submenu's item toward the submenu crosses the items below or above it,
    and hovering one of those closes the submenu before the pointer gets
    there. Desktop menus ignore hovers inside the triangle from where the
    pointer was to the submenu's near edge, for a moment, while the pointer
    keeps moving toward it. `menu_item`'s "hovering closes a sibling's
    submenu", and `menu`'s hover-to-open, would both check it.
5. **The display's scale from gfx.** imgui's scale is the program's to set
    (`set_scale`, `IMGUI_SCALE`). gfx could expose SDL's display content
    scale and its window size in points, and then imgui would start at the
    right size on a high-density screen without being told.
6. **Pixel art.** Nine-slices take a filter; images should too. The scale
    could snap to whole numbers, so that pixels stay square.
7. **Backdrop blur:** a panel that blurs what is behind it. gfx2d's layers
    blur their own content but only copy their backdrop. gfx2d needs to
    blur the backdrop first (its future work, item 16: "A layer can't blur
    what is behind it"), and then a Desc could have `backdrop_blur(s)`.
8. **Developer widgets:** tables with resizable columns, trees, color
    pickers, number fields with drag, plots (on a canvas).
9. **Sizes from aspect ratios** (an image box as wide as its height says),
    and grid tracks of `minmax`.
10. **Momentum scrolling** and drag-to-scroll for touch, and scroll snapping
    (a carousel of cards).
11. **Sounds on interaction:** a hook, polled once a frame, for "a button
    was hovered or clicked", for a game's UI sounds.
12. **Accessibility:** the tree is all there, so an outline of it could be
    given to a screen reader.
13. **Several contexts:** the state is global, as gfx2d's is. Gathering it
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
