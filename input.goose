// Input: what the frame is given (an Input, from gfx or made by the
// program), and what it means, as of where things were drawn last frame:
// which widget the pointer is over (hot), which it holds (active), what was
// clicked, and where the wheel goes.
//
// Hit testing is against the last frame's hit list, in draw order, with
// the pointer where it is now; so a widget's result is known the moment it
// is recorded, and a click lands on what the player saw.

namespace imgui;

import std;
import vec;
import math;
import gfx;
import gfx2d;

struct Pointer {
    pos: float2 = float2 { -1.0e9, -1.0e9 },    // in the UI's units (gfx2d's, under its base scale)
    down: bool = false,
    pressed: bool = false,
    released: bool = false,
    clicks: i32 = 0,                // 2 when the press is a double click
    wheel: float2 = float2 { 0.0, 0.0 },        // lines; y positive scrolls up (content moves down)
    secondary: bool = false,        // the right button pressed: context menus
}

// Navigation buttons, pressed this frame (held ones repeat).
struct NavInput {
    up: bool = false, down: bool = false, left: bool = false, right: bool = false,
    next: bool = false, prev: bool = false,         // Tab, Shift+Tab
    accept: bool = false,                           // Enter, Space, gamepad A
    cancel: bool = false,                           // Escape, gamepad B
    tab_left: bool = false, tab_right: bool = false,    // shoulder buttons: tabs
}

// Editing keys, for a focused text field.
let KEY_LEFT = 1;
let KEY_RIGHT = 2;
let KEY_HOME = 3;
let KEY_END = 4;
let KEY_BACKSPACE = 5;
let KEY_DELETE = 6;
let KEY_ENTER = 7;
let KEY_SELECT_ALL = 8;
let KEY_COPY = 9;
let KEY_CUT = 10;
let KEY_PASTE = 11;

struct EditKey { key: u8 = 0, shift: bool = false, word: bool = false }

struct Input {
    pointer: Pointer = Pointer { .. },
    nav: NavInput = NavInput { .. },
    text: u8[..256] = [],           // typed (and pasted) this frame, UTF-8
    keys: EditKey[..32] = [],
    chords: Chord[..16] = [],       // keys pressed with Ctrl, Alt or Cmd: for shortcut()
    viewport: float2 = float2 { 0.0, 0.0 },     // the UI's size; 0: keep the last
    from_gfx: bool = false,         // made by input_from_gfx: the frame gives gfx back text input and the clipboard
}

// A key pressed with modifiers: its keycode (a lowercase letter or digit
// for most) and the MOD_ bits.
let MOD_SHIFT = 1;
let MOD_CTRL = 2;               // Ctrl, or Cmd on a Mac
let MOD_ALT = 4;
struct Chord { key: i32 = 0, mods: u8 = 0 }

// What a widget's state is this frame.
struct Interaction {
    id: u64 = 0,
    rect: gfx2d::Rect = gfx2d::Rect { 0.0, 0.0, 0.0, 0.0 },   // where it was drawn last frame
    hovered: bool = false,
    held: bool = false,
    pressed: bool = false,          // the pointer went down on it this frame
    released: bool = false,         // and came up, anywhere
    clicked: bool = false,          // down and up on it
    double_clicked: bool = false,
    focused: bool = false,
    activated: bool = false,        // clicked, or accepted by navigation while focused
    dragging: bool = false,         // held, and moved since the press
    pointer: float2 = float2 { 0.0, 0.0 },  // the pointer from the rect's top left
    drag: float2 = float2 { 0.0, 0.0 },     // the pointer from where it was pressed
    nav: int2 = int2 { 0, 0 },      // captured left/right, up/down presses while focused
    hover_t: f32 = 0.0,             // eased, from 0 to 1
    press_t: f32 = 0.0,
    focus_t: f32 = 0.0,
    checked_t: f32 = 0.0,
}

fn activated(it: Interaction) -> bool { it.activated }

// --- this frame's input --------------------------------------------------------------

var input = Input { .. };
var hot: u64 = 0;               // the widget under the pointer
var hot_level: i32 = 0;              // the popup level it is in (0: the main tree)
var over_ui = false;            // the pointer is over something of the UI's
var active: u64 = 0;            // the widget held
var press_pos = float2_0;
var pressed_id: u64 = 0;
var released_id: u64 = 0;
var clicked_id: u64 = 0;
var double_id: u64 = 0;
var wheel_id: u64 = 0;          // the scroll pane the wheel goes to
var accept_id: u64 = 0;         // the widget navigation accepted
var denied_id: u64 = 0;         // the disabled widget the pointer went down on
var keyboard_used = false;
var pointer_moved = false;      // the pointer is somewhere else than last frame
var last_pointer = float2 { -1.0e9, -1.0e9 };

// The hit list: last frame's, in the order it was drawn.
struct Hit {
    id: u64, rect: gfx2d::Rect, clip: gfx2d::Rect, bits: u32, level: i32,
    turned: i32 = -1,               // drawn turned or skewed: where in turned_hits its own box is
}
// A turned or skewed hit's own box, and the pointer taken back into it.
struct TurnedHit { inv: gfx2d::Affine, local: gfx2d::Rect }
var turned_hits: TurnedHit[>..<] = [];
// Whether the pointer at p is on hit h: in its box, turned as it is drawn.
fn hit_at(h: Hit, p: float2) -> bool {
    if !inside(h.clip, p) || !inside(h.rect, p) { return false; }
    if h.turned < 0 { return true; }
    let t = turned_hits[h.turned as i64];
    inside(t.local, gfx2d::apply(t.inv, p))
}
var hits: Hit[>..<] = [];

fn inside(r: gfx2d::Rect, p: float2) -> bool { p.x >= r.x && p.y >= r.y && p.x < r.x + r.w && p.y < r.y + r.h }

// Settles what the input means against the last frame.
fn begin_input(inp: Input) {
    input = inp;
    let p = input.pointer.pos;
    pointer_moved = p != last_pointer;
    last_pointer = p;
    let floor = input_floor();
    hot = 0;
    hot_level = 0;
    over_ui = false;
    denied_id = 0;
    var k = hits.len - 1;
    while k >= 0 {
        let h = hits[k];
        if h.level >= floor && hit_at(h, p) {
            over_ui = true;
            hot_level = h.level;
            if h.bits & HIT != 0 && h.bits & DISABLED == 0 { hot = h.id; }
            if h.bits & HIT != 0 && h.bits & DISABLED != 0 && input.pointer.pressed { denied_id = h.id; }
            break;
        }
        k--;
    }
    // A modal takes the pointer wherever it is.
    if floor > 0 && !over_ui { over_ui = true; hot_level = floor; }
    pressed_id = 0;
    released_id = 0;
    clicked_id = 0;
    double_id = 0;
    if active != 0 && (!input.pointer.down || input.pointer.released) {
        released_id = active;
        if hot == active { clicked_id = active; }
        active = 0;
    }
    if input.pointer.pressed {
        close_popups_above(level_kept_by(hot, hot_level));
        if hot != 0 {
            active = hot;
            pressed_id = hot;
            press_pos = p;
            if input.pointer.clicks >= 2 { double_id = hot; }
            let bits = hit_bits(hot);
            if bits & CLICK_ON_PRESS != 0 { clicked_id = hot; }
            if bits & FOCUSABLE != 0 { focused = hot; } else { focused = 0; }
        } else {
            focused = 0;
        }
        focus_visible = false;
        // A press and release in one frame.
        if input.pointer.released && active != 0 {
            released_id = active;
            if clicked_id == 0 { clicked_id = active; }
            active = 0;
        }
    }
    // The wheel: the innermost scroll pane under the pointer, in the level
    // the pointer is in.
    wheel_id = 0;
    if input.pointer.wheel != float2_0 {
        var j = hits.len - 1;
        while j >= 0 {
            let h = hits[j];
            if h.level == hot_level && h.bits & (SCROLLS_X | SCROLLS_Y) != 0 && hit_at(h, p) {
                wheel_id = h.id;
                break;
            }
            j--;
        }
    }
    begin_nav();
    begin_drag();
}

fn hit_bits(id: u64) -> u32 {
    for h in hits { if h.id == id { return h.bits; } }
    0
}

// Whether the game should leave the pointer, or the keyboard, alone this
// frame: the UI is under it or holds it; a text field has focus.
fn wants_pointer() -> bool { over_ui || active != 0 }
fn wants_keyboard() -> bool { focused != 0 && keyboard_used }

// The pointer, this frame.
fn pointer() -> Pointer { input.pointer }

// --- interactions ----------------------------------------------------------------------

var last_interaction = Interaction { .. };

// The interaction of the node with ID `nid` and Desc `d`, its eased
// amounts moved once a frame by its class's transition.
fn interaction_for(nid: u64, d: Desc) -> Interaction {
    var st = state_of(nid);
    let p = input.pointer.pos;
    var it = Interaction { id: nid, rect: st.screen, .. };
    let enabled = d.bits & DISABLED == 0;
    it.hovered = enabled && hot == nid && (active == 0 || active == nid);
    it.held = enabled && active == nid;
    it.pressed = enabled && pressed_id == nid;
    it.released = released_id == nid;
    it.clicked = enabled && clicked_id == nid;
    it.double_clicked = enabled && double_id == nid;
    it.focused = focused == nid;
    it.activated = it.clicked || (enabled && accept_id == nid);
    it.pointer = p - float2 { st.screen.x, st.screen.y };
    if it.held {
        it.drag = p - press_pos;
        it.dragging = length(it.drag) > 2.0;
    }
    if it.focused { it.nav = nav_captured; }
    let m = class_transition(d.vis.class);
    if st.stamp < 0 {
        // New: at its checked state already, not easing into it.
        st.checked_p = if d.vis.state.checked > 0.5 { 1.0 } else { 0.0 };
        st.checked = st.checked_p;
    }
    if st.stamp != frame_index {
        // Its events, once a frame: a hover or a shown focus only as it
        // begins, a hover only by the pointer moving onto it.
        let c = d.vis.class;
        let shown_focus = it.focused && focus_visible;
        if it.hovered && !st.heard_hover && pointer_moved { ui_event(UI_HOVER, nid, c); }
        if shown_focus && !st.heard_focus { ui_event(UI_FOCUS, nid, c); }
        if it.pressed { ui_event(UI_PRESS, nid, c); }
        if it.activated { ui_event(UI_ACTIVATE, nid, c); }
        if !enabled && denied_id == nid { ui_event(UI_DENIED, nid, c); }
        st.heard_hover = it.hovered;
        st.heard_focus = shown_focus;
        st.hover = ease_toward(st.hover_p, it.hovered || it.held, m, delta);
        st.press = ease_toward(st.press_p, it.held && hot == nid, m, delta);
        st.focus = ease_toward(st.focus_p, it.focused && focus_visible, m, delta);
        st.checked = ease_toward(st.checked_p, d.vis.state.checked > 0.5, m, delta);
        st.stamp = frame_index;
        put_state(nid, st);
    }
    it.hover_t = st.hover;
    it.press_t = st.press;
    it.focus_t = st.focus;
    it.checked_t = st.checked;
    last_interaction = it;
    it
}

// The interaction of node i as recorded: its own if it takes input, else
// just its ID and last rect.
fn interaction_of(i: i32) -> Interaction {
    let n .= nodes[i];
    if n.d.bits & (HIT | FOCUSABLE) != 0 && last_interaction.id == n.id { return last_interaction; }
    Interaction { id: n.id, rect: state_of(n.id).screen, .. }
}

// The look a widget's interaction gives its node.
fn merge_state(s: LookState, it: Interaction) -> LookState {
    LookState { hover: it.hover_t, press: it.press_t, focus: it.focus_t, checked: it.checked_t,
                disabled: s.disabled }
}
// The look state of an interaction, for a part of a widget (a slider's
// thumb) that shares the widget's state.
fn look_of(it: Interaction, checked: bool = false, disabled: bool = false) -> LookState {
    LookState { hover: it.hover_t, press: it.press_t, focus: it.focus_t,
                checked: if checked { 1.0 } else { it.checked_t }, disabled: disabled }
}

fn class_transition(c: StyleClass) -> Motion {
    if c.index == 0 || c.index >= classes.len { return INSTANT; }
    classes[c.index].transition
}

// --- from gfx ------------------------------------------------------------------------------

var codes_ready = false;
var sc_up = 0;
var sc_down = 0;
var sc_left = 0;
var sc_right = 0;
var sc_tab = 0;
var sc_return = 0;
var sc_enter = 0;
var sc_space = 0;
var sc_escape = 0;
var sc_home = 0;
var sc_end = 0;
var sc_backspace = 0;
var sc_delete = 0;
var text_wanted = false;        // gfx's text input is on

fn scan_codes() {
    if codes_ready { return; }
    codes_ready = true;
    sc_up = gfx::scancode("Up");
    sc_down = gfx::scancode("Down");
    sc_left = gfx::scancode("Left");
    sc_right = gfx::scancode("Right");
    sc_tab = gfx::scancode("Tab");
    sc_return = gfx::scancode("Return");
    sc_enter = gfx::scancode("Keypad Enter");
    sc_space = gfx::scancode("Space");
    sc_escape = gfx::scancode("Escape");
    sc_home = gfx::scancode("Home");
    sc_end = gfx::scancode("End");
    sc_backspace = gfx::scancode("Backspace");
    sc_delete = gfx::scancode("Delete");
}

fn push_text(out: u8[..256]&, cp: u32) {
    var b: u8[4] = [0; 4];
    var n = 0;
    if cp < 0x80 {
        b[0] = cp as u8; n = 1;
    } else if cp < 0x800 {
        b[0] = (0xC0 | (cp >> 6)) as u8; b[1] = (0x80 | (cp & 0x3F)) as u8; n = 2;
    } else if cp < 0x10000 {
        b[0] = (0xE0 | (cp >> 12)) as u8; b[1] = (0x80 | ((cp >> 6) & 0x3F)) as u8;
        b[2] = (0x80 | (cp & 0x3F)) as u8; n = 3;
    } else {
        b[0] = (0xF0 | (cp >> 18)) as u8; b[1] = (0x80 | ((cp >> 12) & 0x3F)) as u8;
        b[2] = (0x80 | ((cp >> 6) & 0x3F)) as u8; b[3] = (0x80 | (cp & 0x3F)) as u8; n = 4;
    }
    if out.len + n > out.cap { return; }
    for k in n { out.push(b[k]); }
}

fn push_key(inp: Input&, key: i64, shift: bool, word: bool) {
    if inp.keys.len < inp.keys.cap { inp.keys.push(EditKey { key as u8, shift, word }); }
}

// This frame's input from gfx: the mouse and the keyboard, in the UI's
// units: under gfx2d's base scale and imgui's own (set_scale). (gfx's v1 has no gamepads; a program
// reading one passes what it holds to nav_from_pad.)
fn input_from_gfx() -> Input {
    scan_codes();
    var inp = Input { from_gfx: true, .. };
    let scale = max(gfx2d::current_scale() * ui_scale, 0.0001) as f32;
    inp.pointer.pos = if gfx::mouse_in_window() || gfx::mouse_down(gfx::MOUSE_LEFT) {
        gfx::mouse_pos() / scale
    } else {
        float2 { -1.0e9, -1.0e9 }
    };
    inp.pointer.down = gfx::mouse_down(gfx::MOUSE_LEFT);
    inp.pointer.pressed = gfx::mouse_pressed(gfx::MOUSE_LEFT);
    inp.pointer.released = gfx::mouse_released(gfx::MOUSE_LEFT);
    inp.pointer.secondary = gfx::mouse_pressed(gfx::MOUSE_RIGHT);
    let size = gfx::screen_size();
    inp.viewport = float2 { size.x / scale, size.y / scale };
    var wheel = float2_0;
    for e in gfx::events() {
        if e.kind == gfx::EVENT_MOUSE_BUTTON && e.down && e.button == gfx::MOUSE_LEFT {
            inp.pointer.clicks = e.clicks;
        } else if e.kind == gfx::EVENT_MOUSE_WHEEL {
            wheel += float2 { e.x, e.y };
        } else if e.kind == gfx::EVENT_TEXT {
            push_text(inp.text, e.codepoint);
        } else if e.kind == gfx::EVENT_KEY && e.down {
            let sc = e.scancode as i64;
            let shift = e.mods & gfx::MOD_SHIFT != 0;
            let cmd = e.mods & (gfx::MOD_CTRL | gfx::MOD_GUI) != 0;
            let word = e.mods & (gfx::MOD_CTRL | gfx::MOD_ALT) != 0;
            if (cmd || e.mods & gfx::MOD_ALT != 0) && !e.repeat && inp.chords.len < inp.chords.cap {
                var m: u8 = 0;
                if shift { m |= MOD_SHIFT; }
                if cmd { m |= MOD_CTRL; }
                if e.mods & gfx::MOD_ALT != 0 { m |= MOD_ALT; }
                inp.chords.push(Chord { e.keycode, m });
            }
            if sc == sc_up { inp.nav.up = true; }
            else if sc == sc_down { inp.nav.down = true; }
            else if sc == sc_left { inp.nav.left = true; push_key(inp, KEY_LEFT, shift, word); }
            else if sc == sc_right { inp.nav.right = true; push_key(inp, KEY_RIGHT, shift, word); }
            else if sc == sc_tab { if shift { inp.nav.prev = true; } else { inp.nav.next = true; } }
            else if sc == sc_return || sc == sc_enter { inp.nav.accept = true; push_key(inp, KEY_ENTER, shift, word); }
            else if sc == sc_space && !text_wanted { inp.nav.accept = true; }
            else if sc == sc_escape { inp.nav.cancel = true; }
            else if sc == sc_home { push_key(inp, KEY_HOME, shift, word); }
            else if sc == sc_end { push_key(inp, KEY_END, shift, word); }
            else if sc == sc_backspace { push_key(inp, KEY_BACKSPACE, shift, word); }
            else if sc == sc_delete { push_key(inp, KEY_DELETE, shift, word); }
            else if cmd && !e.repeat {
                if e.keycode == 'a' { push_key(inp, KEY_SELECT_ALL, false, false); }
                else if e.keycode == 'c' { push_key(inp, KEY_COPY, false, false); }
                else if e.keycode == 'x' { push_key(inp, KEY_CUT, false, false); }
                else if e.keycode == 'v' {
                    push_key(inp, KEY_PASTE, false, false);
                    let clip = gfx::clipboard();
                    for c in clip { if c != '\n' && c != '\r' && inp.text.len < inp.text.cap { inp.text.push(c); } }
                }
            }
        }
    }
    inp.pointer.wheel = wheel;
    inp
}

// --- shortcuts -------------------------------------------------------------------------

// Whether a shortcut such as "Ctrl+Q", "Ctrl+Shift+S" or "Alt+1" was
// pressed this frame (Ctrl is Cmd on a Mac). The key is a letter or a
// digit. A menu_item's shortcut text is only shown; this is what acts on it.
fn shortcut(s: const u8[:]) -> bool {
    var want: u8 = 0;
    var key: i32 = 0;
    var at = 0;
    while at <= s.len {
        var end = at;
        while end < s.len && s[end] != '+' { end++; }
        let part = s[at..end];
        if part == "Ctrl" || part == "Cmd" { want |= MOD_CTRL; }
        else if part == "Shift" { want |= MOD_SHIFT; }
        else if part == "Alt" { want |= MOD_ALT; }
        else if part.len == 1 {
            let c = part[0];
            key = if c >= 'A' && c <= 'Z' { c + 32 } else { c };
        }
        at = end + 1;
    }
    for ch in input.chords { if ch.key == key && ch.mods == want { return true; } }
    false
}

// --- gamepads ----------------------------------------------------------------------------

// A gamepad's buttons and stick as they are held now.
struct PadState {
    up: bool = false, down: bool = false, left: bool = false, right: bool = false,
    accept: bool = false, cancel: bool = false,
    tab_left: bool = false, tab_right: bool = false,
    stick: float2 = float2 { 0.0, 0.0 },        // the left stick, -1 to 1 each way
}

var pad_held = PadState { .. };
var pad_dir = int2 { 0, 0 };
var pad_repeat: f64 = 0.0;

// A gamepad's navigation added to `inp`, from what is held now: the
// buttons on their presses, the d-pad and stick as a direction that
// repeats while it is held (after 0.4 s, then every 0.09 s).
fn nav_from_pad(inp: Input&, held: PadState) {
    if held.accept && !pad_held.accept { inp.nav.accept = true; }
    if held.cancel && !pad_held.cancel { inp.nav.cancel = true; }
    if held.tab_left && !pad_held.tab_left { inp.nav.tab_left = true; }
    if held.tab_right && !pad_held.tab_right { inp.nav.tab_right = true; }
    var dir = int2 { 0, 0 };
    if held.left { dir.x = -1; }
    if held.right { dir.x = 1; }
    if held.up { dir.y = -1; }
    if held.down { dir.y = 1; }
    let still = int2 { 0, 0 };
    if dir == still {
        let sx = held.stick.x;
        let sy = held.stick.y;
        if abs(sx) > 0.5 && abs(sx) > abs(sy) { dir.x = if sx < 0.0 { -1 } else { 1 }; }
        else if abs(sy) > 0.5 { dir.y = if sy < 0.0 { -1 } else { 1 }; }
    }
    var fire = false;
    if dir != pad_dir {
        pad_dir = dir;
        fire = dir != still;
        pad_repeat = clock + 0.4;
    } else if dir != still && clock >= pad_repeat {
        fire = true;
        pad_repeat = clock + 0.09;
    }
    if fire {
        if dir.x < 0 { inp.nav.left = true; }
        if dir.x > 0 { inp.nav.right = true; }
        if dir.y < 0 { inp.nav.up = true; }
        if dir.y > 0 { inp.nav.down = true; }
    }
    pad_held = held;
}
