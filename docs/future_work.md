# Future work

What is left, roughly in order of value. Much of it comes from looking at
the HUDs and in-game menus of Hades, Slay the Spire, Stardew Valley, Horizon
Zero Dawn, Apex Legends, Hollow Knight and Diablo IV. `examples/hud.goose`
works around what is missing and names the item here, by its title, at
each workaround.

1. **A HUD that lets the pointer through.** A box with a background or a
   nine-slice blocks the pointer, so `wants_pointer()` is true over every
   panel of a HUD, and the game never gets those clicks. `.passthrough()`
   would leave a node and its subtree out of hit testing unless a node in
   it `hit()`s (a HUD's buttons still work).
2. **Placing by a point, and clamping to the screen.** A health bar under a
   character, a damage number over an enemy, a marker on a quest's target:
   each is placed by a point of its own, such as its bottom center. Now
   `absolute(x, y)` places only a top left corner.
   - `.pivot(px, py)`, as fractions of the node's size, would be subtracted
     from where it is placed.
   - `edge_clamp(p, inset) -> pos, angle, on_screen` would keep a marker for
     something off screen at the screen's edge, with the angle for an arrow
     that points to it.
3. **Meters.** `progress` is one horizontal fill. HUDs need a `meter` that
   can be:
   - vertical;
   - segmented, by a count or a value per segment;
   - followed by a trail: a second fill that holds, then eases down to the
     value, showing what a hit took (boss bars);
   - radial: a ring, or a sweep over an icon for a cooldown.
   Its parts would be classes (METER_TRACK, METER_FILL, METER_TRAIL), as a
   slider's are.
4. **Rotation and skew per node**, beside the offset and scale: a fanned
   hand of cards, icons in diamonds, slanted panels. Hit testing can use the
   bounding box at first.
   - Canvases need the same: `rotate(a) { … }`, `translate(x, y) { … }`,
     and `clip_circle(…) { … }`. They would serve a minimap that turns with
     the player, a clock's hand, or a round orb filled to a level.
5. **A focus cursor that moves.** Console menus often have one highlight
   (brackets at the corners, a glowing frame) that glides from item to item.
   Now each item's ring fades in and out where it is. `focus_cursor(CLASS,
   motion)` would draw one node, in a root above the rest, at the focused
   rect, and animate the rect.
6. **Gamepads, and prompts for the device in use.**
   - Gamepads from gfx: gfx's v1 has no gamepad calls, so a program reads
     its pad and passes it to `nav_from_pad`. Once a gfx release has them,
     `input_from_gfx` should read the first pad itself. The
     `crowded-additions` branch of goose_gfx has them already.
   - `last_device()`: POINTER, KEYBOARD or PAD, by what was used last.
     A footer of prompts ("A Select, B Back") shows that device's glyphs.
   - `prompt(action)` would draw the glyph for an action, from a table of
     images the program fills in for each device.
7. **Drag and drop.** Items move between a chest and a bag, onto a trash
   can, or a card onto an enemy. `Interaction` has `dragging` and `drag`
   but nothing for what is dragged or where it goes.
   - `drag_source(it, payload)` would start a drag.
   - A ghost of the source would be drawn under the pointer, in a top root.
   - `drop_target(it) -> payload, dropped` would hover while a payload is
     over it.
   - With a pad: A picks up, navigation moves, and A puts down.
8. **Exit transitions without the program's help.** `presence` needs the
   program to keep drawing what is leaving. Instead, a node with an `exit`
   could leave behind a copy of its subtree's nodes, drawn while it plays
   out.
9. **Notices.** Damage numbers, an area's name as it is entered, a
   toast for an achievement, a kill feed. Each now needs a key and a
   `presence` the program keeps alive. A queue would take them and play
   them out by itself: `notify(text, d, seconds)` or a block, stacking,
   sliding up and fading. It is easier once 8 is done.
10. **Text.**
    - Rich text: spans in another color, font or size, and images (button
      glyphs, coins) on the baseline, in wrapped text. Item tooltips and
      upgrade cards are made of it. A little markup in the string would do:
      `"Deal {accent}20{} damage"`, `"{img:3}"`.
    - Revealed a character at a time, for dialogue: `.reveal(n)` lays out
      all of the text and draws its first `n` characters, so the lines
      don't move as it types.
    - A soft text shadow. `text_shadow` is a hard copy; the glyphs'
      distance field could be drawn wider and faded to blur it.
    - Multi-line editing.
    - A blinking caret that pauses while typing (now it resets on each edit).
    - IME composition.
    - Measurements cached by text, font and size, if the benchmark shows a
      need.
    - Text drawn wrapped only where it must be.
11. **A radial menu.** Items around a circle, chosen by the pointer's angle
    or the stick's, on release: a ping wheel, a weapon wheel. It needs the
    stick's direction, which `nav_from_pad` turns into d-pad steps now.
12. **A safe triangle for submenus.** Moving the pointer diagonally from a
    submenu's item toward the submenu crosses the items below or above it,
    and hovering one of those closes the submenu before the pointer gets
    there. Desktop menus ignore hovers inside the triangle from where the
    pointer was to the submenu's near edge, for a moment, while the pointer
    keeps moving toward it. `menu_item`'s "hovering closes a sibling's
    submenu", and `menu`'s hover-to-open, would both check it.
13. **The display's scale from gfx.** imgui's scale is the program's to set
    (`set_scale`, `IMGUI_SCALE`). gfx could expose SDL's display content
    scale and its window size in points, and then imgui would start at the
    right size on a high-density screen without being told.
14. **Pixel art.** Nine-slices take a filter; images should too. The scale
    could snap to whole numbers, so that pixels stay square.
15. **Backdrop blur:** a panel that blurs what is behind it. gfx2d's layers
    blur their own content but only copy their backdrop. gfx2d needs to
    blur the backdrop first, and then a Desc could have `backdrop_blur(s)`.
16. **Developer widgets:** tables with resizable columns, trees, color
    pickers, number fields with drag, plots (on a canvas).
17. **Sizes from aspect ratios** (an image box as wide as its height says),
    and grid tracks of `minmax`.
18. **Momentum scrolling** and drag-to-scroll for touch, and scroll snapping
    (a carousel of cards).
19. **Sounds on interaction:** a hook, polled once a frame, for "a button
    was hovered or clicked", for a game's UI sounds.
20. **Accessibility:** the tree is all there, so an outline of it could be
    given to a screen reader.
21. **Several contexts:** the state is global, as gfx2d's is. Gathering it
    into a `root struct` would allow, say, a UI in the world and a UI on
    the screen.

Some things seen in games can be made now:
- Staggered rows of slots: rows, each with its own left padding.
- Ornaments that reach past a panel's edges: `absolute` images in a
  `stack`.
- A compass strip, a clock and a minimap that doesn't turn: canvases.
