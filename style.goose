// How things look. A Style is one look: background, border, corners,
// shadow, padding, text, a nine-slice image, and a little motion (opacity,
// offset, scale). A StyleSet is a widget class's looks in each of its
// states, and how fast it moves between them. The theme is the registry
// of StyleSets, one per StyleClass; a node names its class, and its look
// is its class's styles mixed by the node's state amounts:
//
//   var b = imgui::class_style(imgui::BUTTON);
//   b.normal.bg = gfx2d::rgb(0x2D6A4F);
//   b.hover.bg = gfx2d::rgb(0x40916C);
//   b.transition = imgui::tween(0.12);
//   imgui::set_class(imgui::BUTTON, b);
//
// theme(palette) builds every class from a few colors and sizes;
// theme_light(), theme_dark() and theme_game() are three palettes and
// their touches.

namespace imgui;

import std;
import vec;
import gfx;
import gfx2d;

let GRADIENT_NONE = 0;
let GRADIENT_VERTICAL = 1;      // bg at the top, bg2 at the bottom
let GRADIENT_HORIZONTAL = 2;    // bg at the left, bg2 at the right

struct Shadow {
    color: gfx2d::Color = gfx2d::Color { 0.0, 0.0, 0.0, 0.0 },
    offset: float2 = float2 { 0.0, 0.0 },
    blur: f32 = 0.0,
    spread: f32 = 0.0,
}

struct Style {
    bg: gfx2d::Color = gfx2d::Color { 0.0, 0.0, 0.0, 0.0 },
    bg2: gfx2d::Color = gfx2d::Color { 0.0, 0.0, 0.0, 0.0 },
    gradient: u8 = 0,                       // GRADIENT_NONE
    border: gfx2d::Color = gfx2d::Color { 0.0, 0.0, 0.0, 0.0 },
    border_width: f32 = 0.0,                // inside the box
    radius: float4 = float4 { 0.0, 0.0, 0.0, 0.0 },   // top left, top right, bottom right, bottom left
    shadow: Shadow = Shadow { .. },
    padding: float4 = float4 { 0.0, 0.0, 0.0, 0.0 },  // left, top, right, bottom
    ink: gfx2d::Color = gfx2d::Color { 0.0, 0.0, 0.0, 0.0 },  // transparent: the parent's
    font: gfx2d::Font = gfx2d::Font { 0 },  // 0: the parent's
    text_size: f32 = 0.0,                   // 0: the parent's
    text_look: u16 = 0,                     // letter spacing, outline, shadow (add_text_look); 0: the parent's
    slice: u16 = 0,                         // a nine-slice (add_nine_slice), drawn over the bg
    slice_tint: gfx2d::Color = gfx2d::Color { 1.0, 1.0, 1.0, 1.0 },
    alpha: f32 = 1.0,
    offset: float2 = float2 { 0.0, 0.0 },
    zoom: f32 = 1.0,
    ring: gfx2d::Color = gfx2d::Color { 0.0, 0.0, 0.0, 0.0 },     // the focus ring, when focus shows
    ring_width: f32 = 0.0,
    ring_offset: f32 = 0.0,                 // outside the box
    min_size: float2 = float2 { 0.0, 0.0 },
    gap: f32 = 0.0,                         // between a widget's parts (a checkbox and its label)
}

struct StyleSet {
    normal: Style = Style { .. },
    hover: Style = Style { .. },
    active: Style = Style { .. },           // held down
    focused: Style = Style { .. },
    checked: Style = Style { .. },          // on, selected
    disabled: Style = Style { .. },
    transition: Motion = Motion { .. },     // how the state amounts move
}

// Every state the normal look, to change from.
fn style_set(s: Style, transition: Motion = INSTANT) -> StyleSet {
    StyleSet { normal: s, hover: s, active: s, focused: s, checked: s, disabled: s, transition: transition }
}

struct StyleClass { index: u16 }

let NONE = StyleClass { 0 };
let PANEL = StyleClass { 1 };
let BUTTON = StyleClass { 2 };
let LABEL = StyleClass { 3 };
let TITLE = StyleClass { 4 };
let MUTED = StyleClass { 5 };
let CHECKBOX = StyleClass { 6 };
let CHECK = StyleClass { 7 };
let TOGGLE = StyleClass { 8 };
let TOGGLE_KNOB = StyleClass { 9 };
let RADIO = StyleClass { 10 };
let RADIO_DOT = StyleClass { 11 };
let SLIDER_TRACK = StyleClass { 12 };
let SLIDER_FILL = StyleClass { 13 };
let SLIDER_THUMB = StyleClass { 14 };
let PROGRESS_TRACK = StyleClass { 15 };
let PROGRESS_FILL = StyleClass { 16 };
let SEPARATOR = StyleClass { 17 };
let SELECTABLE = StyleClass { 18 };
let SCROLLBAR = StyleClass { 19 };
let SCROLL_THUMB = StyleClass { 20 };
let TAB_BAR = StyleClass { 21 };
let TAB = StyleClass { 22 };
let TAB_PANEL = StyleClass { 23 };
let MENU_BAR = StyleClass { 24 };
let MENU_HEADER = StyleClass { 25 };
let MENU = StyleClass { 26 };
let MENU_ITEM = StyleClass { 27 };
let POPUP = StyleClass { 28 };
let MODAL = StyleClass { 29 };
let BACKDROP = StyleClass { 30 };
let TOOLTIP = StyleClass { 31 };
let INPUT = StyleClass { 32 };
let CARET = StyleClass { 33 };
let SELECTION = StyleClass { 34 };
let DROPDOWN = StyleClass { 35 };
let CHOICE = StyleClass { 36 };         // the row of a checkbox, toggle or radio and its label
let METER = StyleClass { 37 };          // a meter: its gap is between segments
let METER_TRACK = StyleClass { 38 };    // each segment's groove
let METER_FILL = StyleClass { 39 };
let METER_TRAIL = StyleClass { 40 };    // what a drop took, easing down behind the fill
let FOCUS_CURSOR = StyleClass { 41 };   // set_focus_cursor's look: drawn ring_offset outside the focused box
let NOTICE = StyleClass { 42 };         // a notice drawn by notices() without a block
let WINDOW = StyleClass { 43 };         // a window's frame: its title bar, body and grips go inside
let WINDOW_TITLE = StyleClass { 44 };   // its title bar; checked while it is the front window
let WINDOW_BODY = StyleClass { 45 };    // its content's pane: padding and gap
let WINDOW_BUTTON = StyleClass { 46 };  // the collapse and close buttons in the title bar
let RESIZE_GRIP = StyleClass { 47 };    // an edge or corner dragged to resize; its min_size.x is its thickness
let HEADER = StyleClass { 48 };         // a collapsing header's row
let TREE_ROW = StyleClass { 49 };       // a tree node's row (checked: selected)
let TREE = StyleClass { 50 };           // a tree node's children: its left padding is the indent
let NUMBER = StyleClass { 51 };         // a number field, dragged or typed in
let PROPERTIES = StyleClass { 52 };     // a grid of properties: its gap
let PROPERTY_LABEL = StyleClass { 53 }; // a property's label
let PLOT = StyleClass { 54 };           // a plot's frame; its ink the scale's and the readout's
let PLOT_LINE = StyleClass { 55 };      // a line plot's line (bg), its width (min_size.x)
let PLOT_BAR = StyleClass { 56 };       // a bar plot's bars (bg); hover: the one under the pointer
let SWATCH = StyleClass { 57 };         // a color's swatch: its frame, size and radius
let PICKER = StyleClass { 58 };         // a color picker: its gap, and its square's side (min_size.x)
let TABLE = StyleClass { 59 };          // a table's frame
let TABLE_HEADER = StyleClass { 60 };   // its header's row
let TABLE_HEAD = StyleClass { 61 };     // a column's header: clicked to sort by it
let TABLE_ROW = StyleClass { 62 };      // a row (checked: selected); its min_size.y the rows' height
let TABLE_ROW_ALT = StyleClass { 63 };  // every other row, for stripes
let TABLE_CELL = StyleClass { 64 };     // a cell: its padding
let LOG = StyleClass { 65 };            // a log's pane: its look, padding and text size
let LOG_LINE = StyleClass { 66 };       // a line of LOG_INFO (its ink), and of each level:
let LOG_DEBUG_LINE = StyleClass { 67 };
let LOG_WARN_LINE = StyleClass { 68 };
let LOG_ERROR_LINE = StyleClass { 69 };
let LOG_INPUT_LINE = StyleClass { 70 }; // a console's command, echoed
let SPLITTER = StyleClass { 71 };       // the handle between two panes: its min_size.x is its thickness
let DOCK_SPACE = StyleClass { 72 };     // a dock space: what shows where no window is
let DOCK_TAB_BAR = StyleClass { 73 };   // a dock leaf's row of tabs
let DOCK_TAB = StyleClass { 74 };       // a docked window's tab (checked: shown); its min_size.y the bar's height
let DOCKED = StyleClass { 75 };         // a docked window's frame
let DOCK_PREVIEW = StyleClass { 76 };   // where a window dragged over a dock space would go
let CLASS_COUNT = 77;

// The registry: the light theme to start with. Built by a global's
// initializer, not on first use, so that no widget can reach the shrink a
// new theme is (which the checker would hold against a program iterating
// over text while calling one).
var classes: StyleSet[>..] = theme_classes(Palette { .. });
var nine_slices: NineSlice[>..] = [];

fn class_style(c: StyleClass) -> StyleSet {
    if c.index >= classes.len { return StyleSet { .. }; }
    classes[c.index]
}
fn set_class(c: StyleClass, s: StyleSet) {
    if c.index >= classes.len { misuse("set_class: no such class"); return; }
    classes[c.index] = s;
}
// A class of the program's own.
fn add_class(s: StyleSet) -> StyleClass {
    classes.push(s);
    StyleClass { (classes.len - 1) as u16 }
}

// A nine-slice for Style.slice: the part `src` of `t`, its corners `insets`
// (left, top, right, bottom) kept their size and the rest stretched;
// sampled by `filter` (FILTER_DEFAULT: nearest in pixel-art mode, else linear).
struct NineSlice { texture: gfx::Texture, src: gfx2d::Rect, insets: float4, filter: i32 }
fn add_nine_slice(t: gfx::Texture, src: gfx2d::Rect, insets: float4,
                  filter: i64 = gfx2d::FILTER_DEFAULT) -> u16 {
    if nine_slices.len == 0 { nine_slices.push(NineSlice { gfx::Texture { 0 }, gfx2d::Rect { .. }, float4_0, 0 }); }
    nine_slices.push(NineSlice { t, src, insets, filter as i32 });
    (nine_slices.len - 1) as u16
}

// Text's letter spacing, outline, shadow and glow, for Style.text_look.
// Text inherits each part from its parents unless it is set here: a
// spacing of 0, an outline or glow of 0 and a transparent shadow are
// unset. An outline or glow < 0, or a shadow moved by (0, 0), is none.
struct TextLook {
    letter_spacing: f32 = 0.0,              // pixels after each character
    outline: f32 = 0.0,                     // pixels around the glyphs
    outline_color: gfx2d::Color = gfx2d::Color { 0.0, 0.0, 0.0, 0.0 },
    shadow: gfx2d::Color = gfx2d::Color { 0.0, 0.0, 0.0, 0.0 },     // a copy under the text and its outline
    shadow_offset: float2 = float2 { 0.0, 0.0 },
    shadow_soft: f32 = 0.0,                 // > 0: the shadow soft, fading over this many pixels
    glow: f32 = 0.0,                        // pixels a halo reaches past the glyphs
    glow_color: gfx2d::Color = gfx2d::Color { 0.0, 0.0, 0.0, 0.0 },
    reveal: f32 = -1.0,                     // characters drawn (< 0: all); the node's own, not inherited
    text_fx: u16 = 0,                       // its effect (textfx.goose), and the numbers for it
    fx_args: float4 = float4 { 0.0, 0.0, 0.0, 0.0 },
}
var text_looks: TextLook[>..] = [];
fn add_text_look(l: TextLook) -> u16 {
    if text_looks.len == 0 { text_looks.push(TextLook { .. }); }
    text_looks.push(l);
    (text_looks.len - 1) as u16
}
fn text_look_of(k: u16) -> TextLook { if k < text_looks.len { text_looks[k as i64] } else { TextLook { .. } } }

// `l`'s parts over `up`'s, where l sets them.
fn over_look(l: TextLook, up: TextLook) -> TextLook {
    var r = up;
    if l.letter_spacing != 0.0 { r.letter_spacing = l.letter_spacing; }
    if l.outline != 0.0 { r.outline = l.outline; r.outline_color = l.outline_color; }
    if l.shadow.a > 0.0 { r.shadow = l.shadow; r.shadow_offset = l.shadow_offset; r.shadow_soft = l.shadow_soft; }
    if l.glow != 0.0 { r.glow = l.glow; r.glow_color = l.glow_color; }
    if l.text_fx != 0 { r.text_fx = l.text_fx; r.fx_args = l.fx_args; }
    r
}

// --- mixing ---------------------------------------------------------------------------

// Colors mix premultiplied: from transparent to red passes through faint
// red, not dark gray.
fn mix_color(a: gfx2d::Color, b: gfx2d::Color, t: f32) -> gfx2d::Color {
    if t <= 0.0 { return a; }
    if t >= 1.0 { return b; }
    let pa = gfx2d::premultiplied(a);
    let pb = gfx2d::premultiplied(b);
    color_of(pa + (pb - pa) * t)
}

fn mix_f(a: f32, b: f32, t: f32) -> f32 { a + (b - a) * t }

fn mix_style(a: Style, b: Style, t: f32) -> Style {
    if t <= 0.0 { return a; }
    if t >= 1.0 { return b; }
    var s = a;
    s.bg = mix_color(a.bg, b.bg, t);
    // A gradient against a plain color: the plain color as a gradient of one.
    let a2 = if a.gradient == GRADIENT_NONE { a.bg } else { a.bg2 };
    let b2 = if b.gradient == GRADIENT_NONE { b.bg } else { b.bg2 };
    s.bg2 = mix_color(a2, b2, t);
    s.gradient = if a.gradient != GRADIENT_NONE { a.gradient } else { b.gradient };
    s.border = mix_color(a.border, b.border, t);
    s.border_width = mix_f(a.border_width, b.border_width, t);
    s.radius = a.radius + (b.radius - a.radius) * t;
    s.shadow.color = mix_color(a.shadow.color, b.shadow.color, t);
    s.shadow.offset = a.shadow.offset + (b.shadow.offset - a.shadow.offset) * t;
    s.shadow.blur = mix_f(a.shadow.blur, b.shadow.blur, t);
    s.shadow.spread = mix_f(a.shadow.spread, b.shadow.spread, t);
    s.padding = a.padding + (b.padding - a.padding) * t;
    s.ink = mix_color(a.ink, b.ink, t);
    if t >= 0.5 { s.font = b.font; s.slice = b.slice; s.text_look = b.text_look; }
    s.text_size = mix_f(a.text_size, b.text_size, t);
    s.slice_tint = mix_color(a.slice_tint, b.slice_tint, t);
    s.alpha = mix_f(a.alpha, b.alpha, t);
    s.offset = a.offset + (b.offset - a.offset) * t;
    s.zoom = mix_f(a.zoom, b.zoom, t);
    s.ring = mix_color(a.ring, b.ring, t);
    s.ring_width = mix_f(a.ring_width, b.ring_width, t);
    s.ring_offset = mix_f(a.ring_offset, b.ring_offset, t);
    s.min_size = a.min_size + (b.min_size - a.min_size) * t;
    s.gap = mix_f(a.gap, b.gap, t);
    s
}

// A class's look in state `st`: the normal look, and each state's
// difference from it added in by the state's amount: checked, hover, held,
// focused (when focus shows), disabled. Differences compose: a checked box
// hovered keeps its checked fill and gains the hover border.
fn resolve_style(c: StyleClass, st: LookState) -> Style {
    if c.index == 0 || c.index >= classes.len { return Style { .. }; }
    let set .= classes[c.index];
    var s = set.normal;
    if st.checked > 0.0 { s = add_delta(s, set.normal, set.checked, st.checked); }
    if st.hover > 0.0 { s = add_delta(s, set.normal, set.hover, st.hover); }
    if st.press > 0.0 { s = add_delta(s, set.normal, set.active, st.press); }
    if st.focus > 0.0 { s = add_delta(s, set.normal, set.focused, st.focus); }
    if st.disabled { s = add_delta(s, set.normal, set.disabled, 1.0); }
    s
}

fn delta_color(s: gfx2d::Color, from: gfx2d::Color, to: gfx2d::Color, t: f32) -> gfx2d::Color {
    if from == to { return s; }
    let v = gfx2d::premultiplied(s) + (gfx2d::premultiplied(to) - gfx2d::premultiplied(from)) * t;
    color_of(float4 { clamp(v.x, 0.0, 1.0), clamp(v.y, 0.0, 1.0), clamp(v.z, 0.0, 1.0), clamp(v.w, 0.0, 1.0) })
}

// s plus t times the change from `from` to `to`.
fn add_delta(var s: Style, from: Style, to: Style, t: f32) -> Style {
    let s1 = s.bg;
    let s2 = if s.gradient == GRADIENT_NONE { s.bg } else { s.bg2 };
    let f2 = if from.gradient == GRADIENT_NONE { from.bg } else { from.bg2 };
    let t2 = if to.gradient == GRADIENT_NONE { to.bg } else { to.bg2 };
    s.bg = delta_color(s1, from.bg, to.bg, t);
    s.bg2 = delta_color(s2, f2, t2, t);
    if to.gradient != from.gradient && t >= 0.5 { s.gradient = to.gradient; }
    s.border = delta_color(s.border, from.border, to.border, t);
    s.border_width += (to.border_width - from.border_width) * t;
    s.radius += (to.radius - from.radius) * t;
    s.shadow.color = delta_color(s.shadow.color, from.shadow.color, to.shadow.color, t);
    s.shadow.offset += (to.shadow.offset - from.shadow.offset) * t;
    s.shadow.blur += (to.shadow.blur - from.shadow.blur) * t;
    s.shadow.spread += (to.shadow.spread - from.shadow.spread) * t;
    s.padding += (to.padding - from.padding) * t;
    s.ink = delta_color(s.ink, from.ink, to.ink, t);
    if t >= 0.5 {
        if to.font != from.font { s.font = to.font; }
        if to.slice != from.slice { s.slice = to.slice; }
        if to.text_look != from.text_look { s.text_look = to.text_look; }
    }
    s.text_size += (to.text_size - from.text_size) * t;
    s.slice_tint = delta_color(s.slice_tint, from.slice_tint, to.slice_tint, t);
    s.alpha += (to.alpha - from.alpha) * t;
    s.offset += (to.offset - from.offset) * t;
    s.zoom += (to.zoom - from.zoom) * t;
    s.ring = delta_color(s.ring, from.ring, to.ring, t);
    s.ring_width += (to.ring_width - from.ring_width) * t;
    s.ring_offset += (to.ring_offset - from.ring_offset) * t;
    s.min_size += (to.min_size - from.min_size) * t;
    s.gap += (to.gap - from.gap) * t;
    s
}

// A Desc's inline overrides over a style.
fn apply_overrides(var s: Style, v: LookDesc, lay: LayoutDesc) -> Style {
    if v.ov & OV_BG != 0 { s.bg = v.bg; s.bg2 = v.bg2; s.gradient = v.gradient; }
    if v.ov & OV_RADIUS != 0 { s.radius = v.radius; }
    if v.ov & OV_BORDER != 0 { s.border = v.border; s.border_width = v.border_width; }
    if v.ov & OV_INK != 0 { s.ink = v.ink; }
    if v.ov & OV_TEXT_SIZE != 0 { s.text_size = v.text_size; }
    if v.ov & OV_FONT != 0 { s.font = v.font; }
    if v.ov & OV_SHADOW != 0 { s.shadow = v.shadow; }
    if v.ov & OV_PADDING != 0 { s.padding = lay.padding; }
    s.alpha *= v.opacity;
    s
}

// --- themes ---------------------------------------------------------------------------

// What a theme is made from.
struct Palette {
    screen: gfx2d::Color = gfx2d::rgb(0xDDE2E8),       // behind it all: for the game to clear to, if it likes
    surface: gfx2d::Color = gfx2d::rgb(0xFFFFFF),      // panels, popups
    raised: gfx2d::Color = gfx2d::rgb(0xF1F3F5),       // buttons, tracks
    hover: gfx2d::Color = gfx2d::rgb(0xE4E8EC),
    pressed: gfx2d::Color = gfx2d::rgb(0xD5DBE1),
    line: gfx2d::Color = gfx2d::rgb(0xCED4DA),         // borders, separators
    ink: gfx2d::Color = gfx2d::rgb(0x212529),          // text
    muted: gfx2d::Color = gfx2d::rgb(0x6C757D),
    accent: gfx2d::Color = gfx2d::rgb(0x3B6FE0),       // checked, filled, focused
    accent_hover: gfx2d::Color = gfx2d::rgb(0x2F5CC0),
    accent_ink: gfx2d::Color = gfx2d::rgb(0xFFFFFF),   // text on the accent
    backdrop: gfx2d::Color = gfx2d::rgba(0x000000, 0.45),
    shadow: gfx2d::Color = gfx2d::rgba(0x000000, 0.18),
    radius: f32 = 6.0,
    text_size: f32 = 16.0,
    title_size: f32 = 26.0,
    font: gfx2d::Font = gfx2d::Font { 0 },
    padding: float2 = float2 { 14.0, 8.0 },             // a button's, across and down
    control: f32 = 20.0,                                // a checkbox's side, a slider thumb's
    transition: f32 = 0.1,                              // seconds between states
    space: f32 = 1.0,                                   // the other paddings and gaps, times this: < 1 is denser
}

fn radii(r: f32) -> float4 { float4 { r, r, r, r } }
fn pad4(x: f32, y: f32) -> float4 { float4 { x, y, x, y } }

// Every built-in class, from a palette; the classes a program added kept
// after them.
var screen = gfx2d::rgb(0xDDE2E8);

// The theme's screen color: what a menu screen behind the UI might be
// cleared to, so that switching themes changes it too.
fn screen_color() -> gfx2d::Color { screen }

fn theme(p: Palette) {
    screen = p.screen;
    var extra: StyleSet[>..] = [];
    for k in CLASS_COUNT..classes.len { extra.push(classes[k]); }
    classes = theme_classes(p);
    for e in extra { classes.push(e); }
}

fn theme_classes(p: Palette) -> StyleSet[>..] {
    var classes: StyleSet[>..] = [];
    for i in CLASS_COUNT { classes.push(StyleSet { .. }); }
    let move = tween(p.transition);
    let r = radii(p.radius);
    let sp = p.space;
    fn sq(v: f32) -> float4 { radii(v * sp) }
    fn sp4(x: f32, y: f32) -> float4 { pad4(x * sp, y * sp) }
    let ring = Style { ring: gfx2d::with_alpha(p.accent, 0.9), ring_width: 2.0, ring_offset: 2.0, .. };

    fn focus_ring(s: Style) -> Style {
        var f = s;
        f.ring = ring.ring;
        f.ring_width = ring.ring_width;
        f.ring_offset = ring.ring_offset;
        f
    }
    fn clickable(base: Style, hover: gfx2d::Color, pressed: gfx2d::Color) -> StyleSet {
        var s = style_set(base, move);
        s.hover.bg = hover;
        s.active.bg = pressed;
        s.active.zoom = 0.97;
        s.focused = focus_ring(base);
        s.disabled.alpha = 0.45;
        s
    }

    classes[PANEL.index] = style_set(Style { bg: p.surface, radius: radii(p.radius * 1.5),
                                             padding: sq(16.0), border: p.line, border_width: 1.0,
                                             shadow: Shadow { color: p.shadow, offset: float2 { 0.0, 4.0 }, blur: 16.0 },
                                             ink: p.ink, font: p.font, text_size: p.text_size, gap: 10.0 * sp });
    classes[BUTTON.index] = clickable(Style { bg: p.raised, radius: r, border: p.line, border_width: 1.0,
                                              padding: pad4(p.padding.x, p.padding.y), ink: p.ink,
                                              min_size: float2 { 0.0, p.control + p.padding.y }, gap: 8.0 * sp },
                                      p.hover, p.pressed);
    classes[LABEL.index] = style_set(Style { ink: p.ink, font: p.font, text_size: p.text_size });
    classes[TITLE.index] = style_set(Style { ink: p.ink, text_size: p.title_size });
    classes[MUTED.index] = style_set(Style { ink: p.muted, text_size: p.text_size * 0.875 });

    // The row a checkbox, toggle or radio and its label share: what takes
    // the pointer and the focus.
    var choice = style_set(Style { radius: r, gap: 8.0 * sp, padding: sp4(2.0, 2.0) }, move);
    choice.focused = focus_ring(choice.normal);
    choice.disabled.alpha = 0.45;
    classes[CHOICE.index] = choice;

    let side = p.control;
    var box = style_set(Style { bg: p.surface, border: p.line, border_width: 1.5, radius: radii(p.radius * 0.66),
                                min_size: float2 { side, side } }, move);
    box.hover.border = p.accent;
    box.checked.bg = p.accent;
    box.checked.border = p.accent;
    classes[CHECKBOX.index] = box;
    classes[CHECK.index] = style_set(Style { ink: p.accent_ink });

    var track = style_set(Style { bg: p.pressed, radius: radii(side * 0.5),
                                  min_size: float2 { side * 1.8, side } }, move);
    track.hover.bg = p.line;
    track.checked.bg = p.accent;
    classes[TOGGLE.index] = track;
    classes[TOGGLE_KNOB.index] = style_set(Style { bg: gfx2d::WHITE, radius: radii(side * 0.5),
                                                   shadow: Shadow { color: p.shadow, offset: float2 { 0.0, 1.0 }, blur: 3.0 },
                                                   min_size: float2 { side - 4.0, side - 4.0 } });
    var radio = box;
    radio.normal.radius = radii(side * 0.5);
    radio.hover.radius = radio.normal.radius;
    radio.checked.radius = radio.normal.radius;
    radio.checked.bg = p.surface;
    radio.checked.border_width = 2.0;
    classes[RADIO.index] = radio;
    classes[RADIO_DOT.index] = style_set(Style { bg: p.accent, radius: radii(side * 0.25) });

    classes[SLIDER_TRACK.index] = style_set(Style { bg: p.pressed, radius: radii(3.0),
                                                    min_size: float2 { 160.0 * sp, 6.0 } });
    classes[SLIDER_FILL.index] = style_set(Style { bg: p.accent, radius: radii(3.0) });
    var thumb = style_set(Style { bg: gfx2d::WHITE, border: p.accent, border_width: 2.0, radius: radii(side * 0.5),
                                  shadow: Shadow { color: p.shadow, offset: float2 { 0.0, 1.0 }, blur: 3.0 },
                                  min_size: float2 { side, side } }, move);
    thumb.hover.zoom = 1.12;
    thumb.active.zoom = 1.2;
    thumb.focused = focus_ring(thumb.normal);
    classes[SLIDER_THUMB.index] = thumb;
    classes[PROGRESS_TRACK.index] = style_set(Style { bg: p.pressed, radius: radii(4.0),
                                                      min_size: float2 { 160.0 * sp, 8.0 } });
    classes[PROGRESS_FILL.index] = style_set(Style { bg: p.accent, radius: radii(4.0) });
    classes[METER.index] = style_set(Style { gap: 3.0 });
    classes[FOCUS_CURSOR.index] = style_set(Style { border: p.accent, border_width: 2.0, radius: radii(p.radius + 4.0),
                                                    ring_offset: 4.0 });
    classes[METER_TRACK.index] = style_set(Style { bg: p.pressed, radius: radii(3.0) });
    classes[METER_FILL.index] = style_set(Style { bg: p.accent, radius: radii(3.0) });
    classes[METER_TRAIL.index] = style_set(Style { bg: gfx2d::with_alpha(p.ink, 0.45), radius: radii(3.0) });
    classes[SEPARATOR.index] = style_set(Style { bg: p.line, min_size: float2 { 1.0, 1.0 } });

    var sel = clickable(Style { radius: r, padding: sp4(10.0, 6.0), ink: p.ink }, p.hover, p.pressed);
    sel.active.zoom = 1.0;
    sel.checked.bg = gfx2d::with_alpha(p.accent, 0.16);
    sel.checked.ink = p.accent_hover;
    classes[SELECTABLE.index] = sel;

    classes[SCROLLBAR.index] = style_set(Style { bg: gfx2d::with_alpha(p.line, 0.35), radius: radii(4.0),
                                                 min_size: float2 { 8.0, 8.0 } });
    var sthumb = style_set(Style { bg: gfx2d::with_alpha(p.muted, 0.55), radius: radii(4.0),
                                   min_size: float2 { 8.0, 24.0 } }, move);
    sthumb.hover.bg = gfx2d::with_alpha(p.muted, 0.8);
    sthumb.active.bg = p.muted;
    classes[SCROLL_THUMB.index] = sthumb;

    classes[TAB_BAR.index] = style_set(Style { gap: 4.0 * sp, border: p.line, padding: pad4(0.0, 0.0) });
    var tab = clickable(Style { radius: float4 { p.radius, p.radius, 0.0, 0.0 }, padding: sp4(16.0, 8.0),
                                ink: p.muted }, p.hover, p.pressed);
    tab.active.zoom = 1.0;
    tab.checked.bg = p.surface;
    tab.checked.ink = p.accent;
    tab.checked.border = p.line;
    tab.checked.border_width = 1.0;
    classes[TAB.index] = tab;
    classes[TAB_PANEL.index] = style_set(Style { bg: p.surface, border: p.line, border_width: 1.0,
                                                 radius: float4 { 0.0, p.radius, p.radius, p.radius },
                                                 padding: sq(16.0), gap: 12.0 * sp }, tween(p.transition * 1.5));

    classes[MENU_BAR.index] = style_set(Style { bg: p.raised, padding: sp4(4.0, 2.0), gap: 2.0 * sp,
                                                border: p.line });
    var header = clickable(Style { radius: r, padding: sp4(10.0, 5.0), ink: p.ink }, p.hover, p.pressed);
    header.active.zoom = 1.0;
    header.checked.bg = p.pressed;
    classes[MENU_HEADER.index] = header;
    let floating = Style { bg: p.surface, border: p.line, border_width: 1.0, radius: r, padding: sp4(4.0, 4.0),
                           shadow: Shadow { color: p.shadow, offset: float2 { 0.0, 6.0 }, blur: 18.0 },
                           ink: p.ink, text_size: p.text_size, font: p.font };
    classes[MENU.index] = style_set(floating);
    var item = clickable(Style { radius: radii(p.radius * 0.66), padding: sp4(12.0, 6.0), ink: p.ink, gap: 24.0 * sp },
                         p.hover, p.pressed);
    item.active.zoom = 1.0;
    item.hover.bg = p.accent;
    item.hover.ink = p.accent_ink;
    item.focused.bg = p.accent;
    item.focused.ink = p.accent_ink;
    item.focused.ring_width = 0.0;
    classes[MENU_ITEM.index] = item;
    var pop = floating;
    pop.padding = sq(12.0);
    classes[POPUP.index] = style_set(pop);
    var modal = floating;
    modal.padding = sq(24.0);
    modal.radius = radii(p.radius * 2.0);
    modal.gap = 14.0 * sp;
    classes[MODAL.index] = style_set(modal);
    classes[BACKDROP.index] = style_set(Style { bg: p.backdrop });
    var notice = floating;
    notice.padding = sp4(18.0, 10.0);
    notice.gap = 10.0 * sp;
    classes[NOTICE.index] = style_set(notice);
    classes[TOOLTIP.index] = style_set(Style { bg: gfx2d::with_alpha(p.ink, 0.92), radius: radii(4.0),
                                               padding: sp4(8.0, 4.0), ink: p.surface,
                                               text_size: p.text_size * 0.875 });

    var input = style_set(Style { bg: p.surface, border: p.line, border_width: 1.0, radius: r,
                                  padding: pad4(10.0 * sp, p.padding.y), ink: p.ink,
                                  min_size: float2 { 180.0 * sp, p.control + p.padding.y } }, move);
    input.hover.border = p.muted;
    input.focused.border = p.accent;
    input.focused.border_width = 2.0;
    classes[INPUT.index] = input;
    classes[CARET.index] = style_set(Style { bg: p.accent, min_size: float2 { 2.0, 0.0 } });
    classes[SELECTION.index] = style_set(Style { bg: gfx2d::with_alpha(p.accent, 0.3), radius: radii(2.0) });
    var dd = classes[BUTTON.index];
    dd.normal.gap = 12.0 * sp;
    dd.hover.gap = 12.0 * sp;
    dd.active.gap = 12.0 * sp;
    dd.focused.gap = 12.0 * sp;
    classes[DROPDOWN.index] = dd;

    // Windows: a frame holding a title bar and a body; grips on its edges.
    // The frame doesn't clip, so the grips can reach past it; its title
    // bar's top corners are the frame's.
    classes[WINDOW.index] = style_set(Style { bg: p.surface, border: p.line, border_width: 1.0, radius: r,
                                              shadow: Shadow { color: p.shadow, offset: float2 { 0.0, 4.0 }, blur: 14.0 },
                                              ink: p.ink, font: p.font, text_size: p.text_size });
    var wt = style_set(Style { bg: p.raised, radius: float4 { p.radius, p.radius, 0.0, 0.0 },
                               padding: sp4(10.0, 6.0), gap: 6.0 * sp, ink: p.muted });
    wt.checked.bg = p.pressed;
    wt.checked.ink = p.ink;
    classes[WINDOW_TITLE.index] = wt;
    classes[WINDOW_BODY.index] = style_set(Style { padding: sq(12.0), gap: 8.0 * sp });
    var wb = clickable(Style { radius: radii(p.radius * 0.66), padding: sp4(3.0, 3.0), ink: p.muted }, p.hover, p.pressed);
    wb.active.zoom = 1.0;
    wb.hover.ink = p.ink;
    classes[WINDOW_BUTTON.index] = wb;
    var grip = style_set(Style { radius: radii(2.0), min_size: float2 { 6.0, 6.0 } }, move);
    grip.hover.bg = gfx2d::with_alpha(p.accent, 0.35);
    grip.active.bg = gfx2d::with_alpha(p.accent, 0.6);
    classes[RESIZE_GRIP.index] = grip;

    // Developers' widgets.
    var hdr = clickable(Style { bg: p.raised, radius: r, padding: sp4(10.0, 6.0), gap: 6.0 * sp, ink: p.ink },
                        p.hover, p.pressed);
    hdr.active.zoom = 1.0;
    classes[HEADER.index] = hdr;
    var tr = clickable(Style { radius: r, padding: sp4(6.0, 3.0), gap: 4.0 * sp, ink: p.ink }, p.hover, p.pressed);
    tr.active.zoom = 1.0;
    tr.checked.bg = gfx2d::with_alpha(p.accent, 0.2);
    tr.checked.ink = p.accent_hover;
    classes[TREE_ROW.index] = tr;
    classes[TREE.index] = style_set(Style { padding: float4 { p.text_size, 0.0, 0.0, 0.0 } });
    var num = clickable(Style { bg: p.raised, border: p.line, border_width: 1.0, radius: r,
                                padding: pad4(8.0 * sp, p.padding.y), gap: 4.0 * sp, ink: p.ink,
                                min_size: float2 { 48.0, p.control + p.padding.y } }, p.hover, p.pressed);
    num.active.zoom = 1.0;
    classes[NUMBER.index] = num;
    classes[PROPERTIES.index] = style_set(Style { gap: 8.0 * sp });
    classes[PROPERTY_LABEL.index] = style_set(Style { ink: p.ink });
    classes[PLOT.index] = style_set(Style { bg: gfx2d::with_alpha(p.pressed, 0.5), border: p.line, border_width: 1.0,
                                            radius: r, padding: sp4(6.0, 6.0), ink: p.muted,
                                            text_size: p.text_size * 0.8 });
    classes[PLOT_LINE.index] = style_set(Style { bg: p.accent, min_size: float2 { 1.5, 0.0 } });
    var bar = style_set(Style { bg: p.accent });
    bar.hover.bg = p.accent_hover;
    classes[PLOT_BAR.index] = bar;
    var sw = clickable(Style { border: p.line, border_width: 1.0, radius: radii(p.radius * 0.66),
                               min_size: float2 { p.control + p.padding.y, p.control + p.padding.y } },
                       gfx2d::TRANSPARENT, gfx2d::TRANSPARENT);
    sw.hover.border = p.muted;
    sw.active.zoom = 1.0;
    classes[SWATCH.index] = sw;
    classes[PICKER.index] = style_set(Style { gap: 8.0 * sp, min_size: float2 { p.control * 9.0, 0.0 } });

    classes[TABLE.index] = style_set(Style { bg: p.surface, border: p.line, border_width: 1.0, radius: r });
    classes[TABLE_HEADER.index] = style_set(Style { bg: p.raised, radius: float4 { p.radius, p.radius, 0.0, 0.0 } });
    var th = clickable(Style { padding: sp4(8.0, 5.0), gap: 4.0 * sp, ink: p.muted }, p.hover, p.pressed);
    th.active.zoom = 1.0;
    th.checked.ink = p.ink;
    classes[TABLE_HEAD.index] = th;
    var row_h = p.text_size * 1.5 + 4.0 * sp;
    var trow = clickable(Style { min_size: float2 { 0.0, row_h } }, p.hover, p.pressed);
    trow.active.zoom = 1.0;
    trow.checked.bg = gfx2d::with_alpha(p.accent, 0.22);
    trow.focused.ring_offset = -1.0;
    classes[TABLE_ROW.index] = trow;
    var alt = trow;
    alt.normal.bg = gfx2d::with_alpha(p.ink, 0.035);
    classes[TABLE_ROW_ALT.index] = alt;
    classes[TABLE_CELL.index] = style_set(Style { padding: sp4(8.0, 0.0) });

    classes[LOG.index] = style_set(Style { bg: gfx2d::with_alpha(p.pressed, 0.35), border: p.line, border_width: 1.0,
                                           radius: r, padding: sp4(8.0, 6.0), text_size: p.text_size * 0.92 });
    classes[LOG_LINE.index] = style_set(Style { ink: p.ink });
    classes[LOG_DEBUG_LINE.index] = style_set(Style { ink: p.muted });
    classes[LOG_WARN_LINE.index] = style_set(Style { ink: gfx2d::rgb(0xD29922) });
    classes[LOG_ERROR_LINE.index] = style_set(Style { ink: gfx2d::rgb(0xE5534B) });
    classes[LOG_INPUT_LINE.index] = style_set(Style { ink: p.accent });
    var sp_h = style_set(Style { bg: gfx2d::with_alpha(p.line, 0.7), min_size: float2 { 5.0, 5.0 } }, move);
    sp_h.hover.bg = gfx2d::with_alpha(p.accent, 0.5);
    sp_h.active.bg = p.accent;
    classes[SPLITTER.index] = sp_h;
    classes[DOCK_SPACE.index] = style_set(Style { bg: gfx2d::with_alpha(p.surface, 0.35) });
    classes[DOCK_TAB_BAR.index] = style_set(Style { bg: p.raised, padding: sp4(4.0, 0.0), gap: 2.0 * sp });
    let tab_h = p.text_size * 1.25 + 12.0 * sp;
    var dt = clickable(Style { radius: float4 { p.radius, p.radius, 0.0, 0.0 }, padding: sp4(10.0, 4.0), gap: 6.0 * sp,
                               ink: p.muted, min_size: float2 { 0.0, tab_h } }, p.hover, p.pressed);
    dt.active.zoom = 1.0;
    dt.checked.bg = p.surface;
    dt.checked.ink = p.ink;
    classes[DOCK_TAB.index] = dt;
    classes[DOCKED.index] = style_set(Style { bg: p.surface, ink: p.ink, font: p.font, text_size: p.text_size });
    classes[DOCK_PREVIEW.index] = style_set(Style { bg: gfx2d::with_alpha(p.accent, 0.25), border: p.accent,
                                                    border_width: 2.0, radius: r });
    classes
}

fn theme_light() { theme(Palette { .. }); }

fn dark_palette() -> Palette {
    Palette { screen: gfx2d::rgb(0x111318), surface: gfx2d::rgb(0x1E2128), raised: gfx2d::rgb(0x2A2E37), hover: gfx2d::rgb(0x353A45),
              pressed: gfx2d::rgb(0x414754), line: gfx2d::rgb(0x434957), ink: gfx2d::rgb(0xE9ECF1),
              muted: gfx2d::rgb(0x9AA3B2), accent: gfx2d::rgb(0x5B8CFF), accent_hover: gfx2d::rgb(0x7AA2FF),
              accent_ink: gfx2d::rgb(0x0E1117), backdrop: gfx2d::rgba(0x000000, 0.6),
              shadow: gfx2d::rgba(0x000000, 0.5), .. }
}
fn theme_dark() { theme(dark_palette()); }

// For developers' tools: dense (small text, short rows, thin padding),
// quick between states, in dark or light.
fn dev_palette(dark: bool = true) -> Palette {
    var p = if dark {
        Palette { screen: gfx2d::rgb(0x0F1115), surface: gfx2d::rgb(0x1B1E24), raised: gfx2d::rgb(0x262A31),
                  hover: gfx2d::rgb(0x30353D), pressed: gfx2d::rgb(0x3A404A), line: gfx2d::rgb(0x363B44),
                  ink: gfx2d::rgb(0xDCE0E6), muted: gfx2d::rgb(0x8A929E), accent: gfx2d::rgb(0x4C8DF6),
                  accent_hover: gfx2d::rgb(0x6AA1FF), accent_ink: gfx2d::rgb(0x0B0D10),
                  backdrop: gfx2d::rgba(0x000000, 0.5), shadow: gfx2d::rgba(0x000000, 0.45), .. }
    } else {
        Palette { screen: gfx2d::rgb(0xE6E8EB), surface: gfx2d::rgb(0xF7F8FA), raised: gfx2d::rgb(0xE9ECF0),
                  hover: gfx2d::rgb(0xDDE1E7), pressed: gfx2d::rgb(0xCFD5DD), shadow: gfx2d::rgba(0x000000, 0.14),
                  .. }
    };
    p.radius = 3.0;
    p.text_size = 13.0;
    p.title_size = 18.0;
    p.padding = float2 { 8.0, 3.0 };
    p.control = 14.0;
    p.transition = 0.05;
    p.space = 0.5;
    p
}
fn theme_dev() { theme(dev_palette(true)); }
fn theme_dev_light() { theme(dev_palette(false)); }

// A game's look, to show how far a theme goes: deep blue panels with a
// gold edge, buttons of gradients that glow when hovered and sink when
// pressed, bigger type, springier motion.
fn game_palette() -> Palette {
    Palette { screen: gfx2d::rgb(0x0B1020), surface: gfx2d::rgb(0x182238), raised: gfx2d::rgb(0x24335A), hover: gfx2d::rgb(0x2E4170),
              pressed: gfx2d::rgb(0x1A2643), line: gfx2d::rgb(0xB8913F), ink: gfx2d::rgb(0xF3E9D2),
              muted: gfx2d::rgb(0xA99F8A), accent: gfx2d::rgb(0xE8B64C), accent_hover: gfx2d::rgb(0xF6CC6E),
              accent_ink: gfx2d::rgb(0x1B1406), backdrop: gfx2d::rgba(0x05070D, 0.7),
              shadow: gfx2d::rgba(0x000000, 0.55), radius: 10.0, text_size: 19.0, title_size: 34.0,
              padding: float2 { 22.0, 11.0 }, control: 24.0, transition: 0.14, .. }
}

fn theme_game() {
    let p = game_palette();
    theme(p);
    let gold = p.accent;
    let glow = gfx2d::with_alpha(gold, 0.45);

    var panel = classes[PANEL.index];
    panel.normal.bg = gfx2d::rgb(0x1F2C4A);
    panel.normal.bg2 = gfx2d::rgb(0x121A2D);
    panel.normal.gradient = GRADIENT_VERTICAL;
    panel.normal.border = gfx2d::with_alpha(gold, 0.8);
    panel.normal.border_width = 2.0;
    panel.normal.radius = radii(16.0);
    panel.normal.padding = radii(28.0);
    panel.normal.gap = 14.0;
    panel.normal.shadow = Shadow { color: gfx2d::rgba(0x000000, 0.6), offset: float2 { 0.0, 12.0 }, blur: 30.0 };
    classes[PANEL.index] = style_set(panel.normal);

    var b = classes[BUTTON.index];
    var n = b.normal;
    n.bg = gfx2d::rgb(0x34508C);
    n.bg2 = gfx2d::rgb(0x1E2D52);
    n.gradient = GRADIENT_VERTICAL;
    n.border = gfx2d::with_alpha(gold, 0.55);
    n.border_width = 1.5;
    n.radius = radii(12.0);
    n.shadow = Shadow { color: gfx2d::rgba(0x000000, 0.45), offset: float2 { 0.0, 4.0 }, blur: 8.0 };
    b = style_set(n, spring(500, 28));
    b.hover.bg = gfx2d::rgb(0x4767B0);
    b.hover.bg2 = gfx2d::rgb(0x283C6C);
    b.hover.border = gold;
    b.hover.shadow = Shadow { color: glow, offset: float2 { 0.0, 0.0 }, blur: 18.0, spread: 1.0 };
    b.hover.zoom = 1.04;
    b.active.bg = gfx2d::rgb(0x22355F);
    b.active.bg2 = gfx2d::rgb(0x1A2848);
    b.active.offset = float2 { 0.0, 2.0 };
    b.active.zoom = 0.98;
    b.active.shadow = Shadow { color: gfx2d::rgba(0x000000, 0.3), offset: float2 { 0.0, 1.0 }, blur: 3.0 };
    b.focused = b.hover;
    b.focused.zoom = 1.04;
    b.focused.ring = gfx2d::TRANSPARENT;
    b.disabled.alpha = 0.4;
    classes[BUTTON.index] = b;

    var title = classes[TITLE.index];
    title.normal.ink = gold;
    classes[TITLE.index] = style_set(title.normal);

    var thumb = classes[SLIDER_THUMB.index];
    thumb.normal.bg = gold;
    thumb.normal.border = gfx2d::rgb(0xFFF1C9);
    thumb.hover = thumb.normal;
    thumb.hover.zoom = 1.15;
    thumb.hover.shadow = Shadow { color: glow, blur: 10.0, .. };
    thumb.active = thumb.hover;
    thumb.active.zoom = 1.25;
    thumb.focused = thumb.hover;
    thumb.focused.ring = gfx2d::TRANSPARENT;
    classes[SLIDER_THUMB.index] = thumb;

    var choice = classes[CHOICE.index];
    choice.hover.bg = gfx2d::with_alpha(gold, 0.08);
    choice.focused.bg = gfx2d::with_alpha(gold, 0.12);
    choice.focused.ring = gfx2d::with_alpha(gold, 0.7);
    choice.normal.padding = pad4(8.0, 4.0);
    choice.hover.padding = choice.normal.padding;
    choice.focused.padding = choice.normal.padding;
    choice.active.padding = choice.normal.padding;
    choice.checked.padding = choice.normal.padding;
    choice.disabled.padding = choice.normal.padding;
    classes[CHOICE.index] = choice;

    // Tracks: faint light over the dark panel, not a darker blue lost in it.
    let groove = gfx2d::rgba(0xF3E9D2, 0.14);
    for c in [SLIDER_TRACK, PROGRESS_TRACK, METER_TRACK] {
        var t = classes[c.index];
        t.normal.bg = groove;
        classes[c.index] = style_set(t.normal);
    }
    var tog = classes[TOGGLE.index];
    tog.normal.bg = groove;
    tog.hover.bg = gfx2d::rgba(0xF3E9D2, 0.22);
    tog.active.bg = tog.hover.bg;
    tog.focused.bg = groove;
    tog.disabled.bg = groove;
    classes[TOGGLE.index] = tog;

    var tab = classes[TAB.index];
    tab.checked.bg = gfx2d::rgb(0x1F2C4A);
    tab.checked.border = gfx2d::with_alpha(gold, 0.8);
    tab.checked.ink = gold;
    classes[TAB.index] = tab;
    var tp = classes[TAB_PANEL.index];
    tp.normal.bg = gfx2d::rgb(0x1F2C4A);
    tp.normal.border = gfx2d::with_alpha(gold, 0.8);
    classes[TAB_PANEL.index] = style_set(tp.normal, tp.transition);
}
