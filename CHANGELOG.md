# Changelog

All notable changes to Drafter are documented here.
Versions marked with ★ were published to Hex.pm.

## [0.3.0] - 2026-08-03

Upgrading from 0.2.x: see **Removed** and the first three **Changed** entries. An
application that only uses `Drafter.App`, the widget constructors and `Drafter.run/2`
needs no source changes; a custom widget that paints images or declares traits does.

### Added

- **`Drafter.Pty.close/2` takes `:kill_after`** — milliseconds to wait before sending `SIGKILL` to the program's process group, for a program that ignores the `SIGHUP` that releasing the descriptors sends. The signal goes to the group, so children the program started go with it, and is skipped if the group has already gone. `close/1` sends nothing further.
- **`Drafter.ScrollMath.visible_range/3`, `scroll_by/4`, `page/4` and `to_oldest/2`** — the operations a widget rendering virtual rows needs, so a large row set is windowed without materialising what falls outside it.
- **`slider(opts)` widget** — a draggable value slider with a track, a fill and a thumb. Arrow keys move one step, `PageUp`/`PageDown` ten, `Home`/`End` jump to the ends of the range, and a press or drag anywhere on the track moves the thumb there (the gesture keeps tracking once the pointer leaves the widget). Supports `min`/`max`/`step`, `bind:` two-way binding, `on_change`, a label and a formatted readout that reserves the widest value in the range so the track never shifts, `:disabled`, per-part colour overrides, and `:horizontal` / `:vertical` orientation. An integer range keeps integer values; any other range works in floats rounded to the decimals the step implies. `Drafter.get_widget_value/1` and `set_widget_value/2` read and write its number.
- **Slider rendering through `french_curve`** — `renderer: :braille` draws the rounded track and disc thumb as braille cells, and a graphics protocol (`:auto`, `:pixel`, `:kitty`, `:iterm2`, `:sixel`) transmits it as a picture, falling back to braille where the terminal has none. The default `:text` renderer draws characters from the active skin, which now carries a `slider` glyph group.
- **A font catalogue for `digits(value, opts)`** — `font:` selects `:block` (7×5 box-drawing outlines, the default), `:compact` (5×3), `:tall` (8×4 half blocks), `:pixel` (4×4 quadrants) or `:braille` (4×4). Every built-in font covers digits, upper and lower case, and common punctuation, so swapping one for another never drops characters, and a character a font cannot draw renders as blanks of the font's widest glyph rather than raising. `Drafter.Widget.Digits.Font` exposes `height/1`, `glyph_width/2`, `text_width/2` and `supports?/2` for laying out around a headline. See the [Large Text guide](guides/large_text.md).
- **FIGlet fonts in `digits`** — `Drafter.Widget.Digits.Figlet.load/1` reads a `.flf` file and `Drafter.Widget.Digits.Font.register/2` names it, after which `digits("Vellum", font: :slant)` works like any built-in. FIGlet fonts are proportional, so measure with `text_width/2` rather than assuming a cell.
- **`digits` can render as a transmitted image** with `renderer:`, using the same graphics protocols as charts and sliders.
- **`31_font_catalogue.exs` and `32_slider.exs` examples.** The `widgets.exs` showcase and the theme sandbox gallery gained sliders too.
- **`Drafter.Clipboard`** — `copy/2` writes OSC 52 to the terminal the session is attached to, so a copy from an app served over SSH or telnet lands on the *client's* clipboard, and additionally writes the local clipboard through `pbcopy`, `clip`, `wl-copy`, `xclip` or `xsel` when one is on `PATH`. `paste/0` reads the clipboard of the machine the app process runs on. Both are configured by `clipboard:` in `Drafter.run/2` or `config :drafter` — `false` makes them no-ops returning `{:error, :disabled}`, and a keyword list sets the two directions separately (`clipboard: [copy: true, paste: false]`). Key bindings come from `:clipboard_keys`.
- **A widget receives pasted text** by declaring `handles: [:paste]` and implementing `c:Drafter.Widget.handle_paste/2`.
- **`Drafter.Pty`** — runs a program on a pseudoterminal and hands its byte stream to the caller. `spawn/2` allocates the pty, starts the program in a new session with the pty as its controlling terminal, and returns a handle whose ports deliver `{:data, bytes}` and `{:exit_status, status}` straight to the calling process, with no relay in between. `write/2` feeds standard input and `resize/3` sets the size, which makes the kernel deliver `SIGWINCH` to the program.
- **Pluggable character-width tables.** `Drafter.CharacterWidth` measures per grapheme cluster and is the single point every width measurement goes through — strip widths, truncation, wrapping, cursor placement and the compositor's column arithmetic. A host that owns the grid Drafter draws into can supply its own tables with `config :drafter, character_width: MyTables`; the setting is read with `Application.compile_env/3`, so the calls compile to direct dispatch.
- **`refresh_rate` accepts a frame-rate string** — `"30fps"`, `"7.5fps"`, `"unlimited"`, `:unlimited`, or a millisecond integer, in `Drafter.run/2` or the app's `c:Drafter.App.refresh_rate/0`. Anything else raises `ArgumentError` rather than pacing at a silently wrong rate.
- **`Drafter.Test.screen_text/1` and `screen_lines/1`** — what is on screen as plain text, so a test can assert on rendered output instead of only on state. `sync/1` blocks until the app has drained what it was sent.
- **Docking in layout** — a child carrying `dock: :top | :bottom | :left | :right` is taken out of the normal flow and given the full span of that edge; the remaining space is what its undocked siblings share. `footer` docks to the bottom without being asked.
- **Translucent colours.** A colour may carry an alpha component, which the compositor blends against what is already in the cell rather than replacing it.
- **`radio_set(options, opts)` takes `:width`**, which fixes the column width when `:cols` lays the options out in a grid.
- **`c:Drafter.Widget.image_active?/1`** — an optional callback saying whether a widget is painting a transmitted image right now.
- **`Drafter.Compositor.write_raw/1`** — writes bytes to the terminal through the compositor, so output from an embedded program interleaves with the frame rather than racing it.
- **`handles: [:click]`** is accepted as a spelling of `handles: [:press]`.
- **Terminal resize is driven by `SIGWINCH`**, so a window change is picked up as it happens rather than at the next poll.
- **The terminal is asked what graphics it supports instead of being guessed at.** At startup Drafter writes XTVERSION (`CSI > q`) and primary device attributes (`CSI c`) and reads the answers, which name the terminal and list its features. This settles kitty, iTerm2, WezTerm, ghostty and sixel support from the terminal itself, so it is right under a multiplexer, over ssh and over telnet alike — none of which carry the environment variables a guess depends on. A terminal that answers neither query within 250 ms falls back to the environment as before. `Drafter.Terminal.Probe` performs the exchange; `FrenchCurve.Capability.probe/0` and `from_probe/1` say what to send and what the answers mean.
- **`Drafter.Session.Context.terminal_env/0` and `terminal_protocol/0`** — the terminal a session is attached to, carried between processes by `capture/0` and `adopt/1` like the rest of the context, and falling back to the host's environment outside a session. `Drafter.run_session/3` sets both from `:terminal_env` and `:terminal_protocol` keys on the session context a transport builds.
- **Telnet negotiates TERMINAL-TYPE**, so a telnet client's `TERM` is known even when it does not answer the graphics probe. A client that answers neither starts anyway after 250 ms.
- **`Drafter.CellSession.take_lines/1` and `take_text/1`** — the cell grid as plain text, styling dropped and trailing blanks trimmed. The same view `Drafter.Test.screen_lines/1` gives of a headless app, so a host embedding a session can assert on or log what is displayed without flattening strips itself.
- **README sections for embedding and number formatting.** `Drafter.CellSession` and `Drafter.Format` were documented on the modules but named nowhere a reader would find them.
- **Two new guides** — [Large Text](guides/large_text.md), on choosing a `digits` font and how the fonts are built, and [Design Notes](guides/design_notes.md), on how the internals fit together, for anyone writing widgets or changing the framework.

### Changed

- **`Drafter.WidgetHierarchy` is documented.** `Drafter.Test.get_widget_hierarchy/1` returns it and the README describes its fields, but the module was marked internal, so the struct a test is handed had no reference to read.
- **Element examples render again in the published docs.** A doctest written inside an option list was absorbed into that list, and its result line — `{:label, "Ready", []}` and fourteen others — was parsed as a Markdown attribute list and dropped. The examples always ran; only the rendered page lost them.
- **`header(title, opts)` no longer shows a clock unless asked.** `:show_clock` now defaults to `false`, so a header draws a title and starts no timer of its own. Pass `show_clock: true` for the previous behaviour.
- **`option_list` draws its `▶` cursor only while focused**, and takes `:focused` as a mount option. Several lists can now sit side by side — arrow keys move between them and the highlight of an unfocused list stays put without competing for the eye. `Drafter.get_widget_state/1` reports the field.
- **`Drafter.Compositor.put_image/4`** takes the placement map a widget's `image/3` returns (`%{dx:, dy:, cols:, rows:, stamp:, place:}`) instead of nine positional arguments. Custom widgets that transmit images must update their calls.
- **Widget traits are declared with `use Drafter.Widget, traits: [...]`.** The Spark `traits do ... end` block is gone, and with it Drafter's dependency on a DSL compiler for widget definitions. A widget that used the block moves its trait list into the `use` options.
- **`use Drafter.App` appends its catch-all `handle_event/2` and `on_timer/2` clauses after a module's own clauses** rather than defining them ahead of an override. A module that already ends with its own catch-all keeps working; one that never wrote a catch-all now falls through to `{:noreply, state}` instead of raising `FunctionClauseError` on the first unnamed key. A module whose own catch-all is followed by more clauses will now see an unreachable-clause warning where the clauses were previously silently dropped.
- **A widget that draws characters costs nothing on the image path.** The renderer and the widget server ask `Drafter.Widget.image_active?/2` before placing or generating an image, so a chart, gauge, digits or slider in a `:text` or `:braille` mode never enters it. A widget that was painting and stops has its image withdrawn once at the transition rather than re-cleared every frame.
- **Widget value reads and writes go through `Drafter.WidgetValue`**, so a value read through the app loop and one read directly with `Drafter.get_widget_value/1` always agree.
- **Per-session services are resolved from the calling process rather than from a global name.** `Drafter.Session.Context` holds the association, with `capture/0` and `adopt/1` for carrying it to another process, and falls back to a globally registered process so a widget can still be rendered outside any session. Concurrent SSH and telnet sessions no longer see each other's widget registrations.
- **The framework's ETS tables are owned by a supervised process** for the lifetime of the application, so a crash in the process that happened to create one no longer takes the table with it.
- **Terminal input is buffered across reads**, so an escape sequence split across two reads — common on slow links and under multiplexers — is reassembled instead of being delivered as garbage keys.
- **`Drafter.Test`'s `send_*` functions block until the app has finished handling the input**, so a send and the assertion after it need no sleep between them.
- **The API documentation has been rewritten throughout**, covering every public callback, element constructor, option and return value, with executable examples. The README now documents `Drafter.run/2`'s options, the two `handle_event` arities and which events reach each, screen types and their option defaults, selector syntax, and headless testing. Several previously documented behaviours were wrong — notably `Ctrl+C` was never a global quit key; `Ctrl+Q` is, and `Ctrl+C` is delivered to the app and is the copy binding inside text widgets.

### Removed

- **`Drafter.Examples.*` and the `lib/drafter/examples/` tree.** Twenty-one demo modules compiled into the library and shipped to every application that depended on it, several of them scratch files (`button_debug`, `button_test`, `scrollable_test`, `input_debugger`) and most of them stale duplicates of the maintained scripts under `examples/`. The two with no script counterpart are now `examples/spark/33_css_styling.exs` and `examples/spark/34_breakpoints.exs`.
- **`Drafter.Util`.** `normalize_class/1` and `normalize_classes/1` moved to `Drafter.Style`, which is where the `:class` option they serve belongs; `safe_to_existing_atom/1` had no callers.
- **`Drafter.Transport.SSHChannel`.** An unused `:ssh_server_channel` implementation. The ssh transport runs an app through an OTP `shell:` function, which the runtime graphics probe reaches as readily as a custom channel would, so nothing needed it.
- **`Drafter.TreeDiff`, `Drafter.Widget.DirtyTracker`, `Drafter.Widget.Trait.Dsl` and `Drafter.Visualization.BinarySearch`.** These were internal to render-path bookkeeping and the trait DSL, and nothing replaces them at the call site: fingerprinting and dirty tracking now live in the compositor's per-row cache, and traits are declared in `use Drafter.Widget`.

### Fixed

- **Terminals that speak sixel are detected.** Konsole, foot and mlterm drew braille where they could have drawn images: Drafter carried its own copy of the terminal rules, and that copy knew no sixel terminal at all. Detection now goes through `FrenchCurve.Capability.detect/1`, which also recognises kitty and ghostty from `TERM` alone — a kitty session that does not export `KITTY_WINDOW_ID`, such as one inside a multiplexer, previously fell back to braille.
- **A remote session detects the connecting client's terminal rather than the host's.** Every ssh and telnet session read the environment of the machine the server runs on, so a server started under a plain shell served braille to every client whatever they were running, and a server started inside kitty sent kitty escape sequences to clients that could not draw them.
- **Switching a chart off a pixel renderer clears the graphic it already sent**, instead of leaving the old image on screen underneath the new glyphs, where the two appeared to alternate as rows repainted.
- **Escape sequences in pasted text never reach a widget's buffer.** A paste is sanitized where it is handed to the focused widget, so it applies to `text_input`, `text_area` and `file_picker` as well as to widgets declaring `handles: [:paste]`. Ordinary text and the newlines of a multi-line paste come through unchanged.
- **A widget rendered into a rect too small to draw in produces strips that fit it rather than raising** — reachable in a narrow split, a collapsed pane, or a small terminal.
- **A rapid second click is reported as consumed**, so a double click no longer leaks its second half to the widget underneath.
- **Dragging a `data_table` scrollbar** no longer also selects the row released on, no longer leaves the table stuck in drag mode after a plain click, and clamps at the ends instead of overscrolling. A table dragging its scrollbar captures the pointer, so the drag keeps tracking once the pointer leaves the table.
- **A scrollbar thumb round-trips**: the row a thumb is drawn at maps back to the offset that drew it, so dragging a thumb no longer drifts against the content.
- **A hovered `switch` is drawn differently**, rather than only recording that it is hovered.
- **A widget scrolled entirely off screen is marked invisible**, so it stops transmitting images that would be clipped away.
- **A slider's `:renderer` can change after mount**, so an app switching render modes at runtime moves its mounted sliders with it.
- **A telnet session registers its loop while it runs and leaves none behind once it closes**, and the last of several rapid keystrokes reaches the wire.

## [0.2.11] - 2026-06-29

### Added

- **`Drafter.set_widget_value/2`** — imperatively set a widget's value on demand (text widgets take a string, `checkbox` a boolean). The discrete counterpart to `get_widget_value/1`; routes through the widget's own `update/2` so text widgets reclamp the cursor. Lets a client own a self-managed input widget and write into it at specific moments rather than mirroring state on every keystroke.

### Changed

- **Per-keystroke render cost greatly reduced for editor-heavy UIs.** Incremental compositing now tracks dirty regions **per row** (a cache-key per strip) instead of per widget, so editing one line recomposites a single row instead of the whole widget; and a keystroke that changes neither app state nor layout now skips the component-tree reconcile via the render fast path.
- **`get_widget_value/1` and `get_widget_state/1` read the widget's `WidgetServer` directly** through the widget registry instead of round-tripping a message through the app loop. They are now deadlock-free and safe to call from inside app event handlers.

## [0.2.10] - 2026-03-27

### Added

- **Weighted scatter points** — scatter data points accept an optional weight component (`[x, y, weight]` or `{x, y, weight}`) where weight is a float 0.0–1.0. Higher weights produce denser braille dot clusters and brighter colors, providing visual density feedback for clustered data.
- **`fill_opacity` chart option** — controls the brightness of area fill relative to the series edge color, from `0.0` (invisible) to `1.0` (same as edge). Default `0.6`. Applies to `:area` and `:braille_area` chart types.
- **Braille area example** — `26_braille_area.exs` demonstrates stacked braille area charts with per-series opacity.
- **SSH anonymous authentication** — pass `auth: :anonymous` to `Drafter.Server` to allow anonymous SSH connections (still need password, but do not need to be registered).

### Changed

- **Adaptive color depth in braille area charts** — fill color now scales inversely with span thickness, producing more natural gradient fills for stacked series.

## [0.2.3] - 2026-03-24

### Added

- **SSH chat channels** — the `ssh_chat.exs` example now supports multiple chat rooms. `/join #channel` switches rooms, `/channels` lists active rooms, `/help` shows available commands.
- **`scrollable/2`: `focusable: false` option** — excludes a scrollable container from the tab/focus cycle on a per-instance basis.

### Fixed

- Various bug fixes and rendering improvements across SSH, layout, focus management, and screen lifecycle.

## [0.2.2] - 2026-03-24

### Added

- **CJK / multi-byte character input** — Japanese, Chinese, Korean, and emoji characters can now be typed into text inputs and text areas.
- **Braille area chart** — new `chart_type: :braille_area` renders smooth stacked area charts using braille characters with per-series color blending. Ideal for live metrics dashboards.
- **Collapsible focus behaviour** — children of collapsed sections are automatically excluded from keyboard navigation. Expanding a section makes its children navigable again.

### Fixed

- **Arrow key navigation** — arrow keys now correctly move focus between widgets. A regression had silently disabled all arrow-based navigation.
- **Text input race condition** — rapidly typed characters no longer get dropped due to async binding updates overwriting widget state.
- **Split pane resize crash** — dragging a pane to a very narrow width no longer crashes the box widget.
- **Action handlers in sub-apps** — custom action handlers registered before `Drafter.run` now work correctly when launched from the example gallery or any push-session context.

### Changed

- **NIF compilation** — switched from a custom build script to `elixir_make` with a standard Makefile. Run `mix deps.get` after upgrading.
- **Session isolation** — ScreenManager, ThemeManager, EventHandler, and Event.Manager are no longer started as global named processes. Each session creates its own instances, preventing state leakage between concurrent SSH/telnet sessions.
- **Event.Manager simplified** — removed the internal queue; events are dispatched directly in `handle_cast`, matching standard GenServer semantics.
- **SkinManager** — character set selection is now per-session instead of global, avoiding cross-session interference and `persistent_term` global GC.

### Removed

- **FocusRegistry** — unused global keybinding store that would have caused bugs with multiple SSH sessions.
- **Event.CustomRegistry** — unused runtime schema validation registry. Use `defstruct` and pattern matching instead.
- **Event.Processor** — stub module with unimplemented functions; all functionality lives in WidgetHierarchy.

## [0.2.0] - 2026-03-21

### ⚠ Breaking Changes

#### `Drafter.set_interval/2` — new unit-aware API

The second argument to `set_interval` is now a **unit atom** that also serves as
the timer ID passed to `on_timer/2`. Any app using `set_interval` must update
both the call site and the matching `on_timer` clause.

**Before:**
```elixir
def on_ready(state) do
  Drafter.set_interval(33, :my_timer)
  state
end

def on_timer(:my_timer, state), do: ...
```

**After — choose the unit that matches your intent:**
```elixir
def on_ready(state) do
  Drafter.set_interval(30, :fps)   # 30 fps  → ~33 ms interval
  # or
  Drafter.set_interval(500, :ms)   # 500 ms interval
  state
end

def on_timer(:fps, state), do: ...
# or
def on_timer(:ms, state), do: ...
```

The available units are:

| Unit | Meaning | Example |
|------|---------|---------|
| `:fps` | fires N times per second | `set_interval(30, :fps)` → ~33 ms |
| `:ms` | fires every N milliseconds | `set_interval(500, :ms)` → 500 ms |
| `:tick` | alias for `:ms` (backward compat) | `set_interval(500, :tick)` |

The timer ID used in `on_timer/2` is always the **unit atom** you passed, not a
separate name. If you need two independent timers, use two different unit atoms
(or combine `:tick` for one and `:fps`/`:ms` for the other):

```elixir
def on_ready(state) do
  Drafter.set_interval(30, :fps)
  Drafter.set_interval(1000, :ms)
  state
end

def on_timer(:fps, state), do: ...   # animation tick
def on_timer(:ms, state), do: ...    # slow poll
```

> **Apps using `send(self(), {:set_interval, ms, id})` directly** must switch to
> `Drafter.set_interval/2`. Direct sends bypass session isolation and can cause
> timers from one session to fire in the next.

### Added
- `run_examples.exs`: example gallery now starts `TreeSitterDaemon` automatically,
  so syntax-highlighted examples (e.g. `code_browser`) work without any extra flags
  when launched from the gallery

### Fixed
- Timer events from a finished session no longer bleed into the next session — stale
  `{:timer, _}` messages are drained from the process mailbox when a new session starts
- `Drafter.run/2` called with `syntax_highlighting: true` from inside a running app
  (gallery → sub-example) now correctly starts `TreeSitterDaemon`; previously the
  tree-sitter daemon was only started for the root `run/2` call, so sub-sessions
  always fell back to plain-text rendering
- `set_interval` called during `on_ready` is now captured synchronously and immune
  to race conditions when the gallery launches two examples in quick succession
- Gauge example `+`/`-` keyboard shortcuts now work (previously only the on-screen
  buttons worked); the `keybindings` hint was declared but the key handlers were missing

## [0.1.28] - 2026-03-20

### Added
- `run_examples.exs` — interactive example gallery; run with `elixir run_examples.exs`
  to browse and launch all bundled examples. Returns to the gallery after each example
  exits. Note: the SSH example terminates the launcher on `Ctrl+C` — this is expected.
- `Gauge` widget — semi-circular arc gauge rendered with braille characters; colour
  transitions through configurable low/mid/high thresholds as value increases.

  ```elixir
  gauge(value: 0.72)
  gauge(value: cpu_usage, label: "CPU", low_threshold: 0.6, high_threshold: 0.8)
  ```

- `CodeView`: `hex_view: true` prop — displays binary files as a hex dump instead of
  attempting text rendering. The `code_browser` example enables this automatically for
  non-text files.

### Fixed
- Calculator keyboard input dropped characters and missed button animations (PR #3,
  nshkrdotcom; follow-up fix for hierarchy state sync)
- Running multiple `Drafter.run/2` calls in sequence (e.g. via `run_examples.exs`)
  no longer causes leftover widget processes, stale renders, or corrupted input from
  a previous app bleeding into the next
- `{:stop, :normal}` returned from a widget `on_select` / `on_click` callback now
  correctly stops the application
- Tree-sitter "No language found" messages no longer bleed into the TUI output
- `StyleHelpers`: stylesheet detection broken for apps using `use Drafter.App` with
  CSS (fixes #1)
- `widgets.exs` example crashed on text input

## [0.1.22] - 2026-03-17
### Added
- `Chart`: `area_fill: :inverted` option for area charts — fills from the baseline upward (braille dots at bottom, empty space above); default behaviour (dots at top) is unchanged

### Fixed
- `Chart`: `area_fill` prop was silently overwritten to `:default` on every re-render because `ComponentRenderer` always passed a default value; now passes `nil` when unspecified so `update/2` preserves the mounted value

## [0.1.21] - 2026-03-16
### Added
- `ScrollableContainer`: `click_to_scroll: true` opt-in mode — scroll events are claimed by the parent container by default; `Ctrl+Click` inside the viewport toggles scroll-lock on that container (border highlights to show active state); clicking outside clears the lock. Nested scroll containers register themselves as exceptions at mount time so the per-event routing check only runs when exceptions exist (zero overhead when no nesting).

### Fixed
- `WidgetHierarchy`: `find_scroll_container_at` now consults `scroll_exceptions` — a non-`click_to_scroll` inner container (e.g. `DataTable`'s internal scroller) is skipped when an outer `click_to_scroll` container has it registered as an exception and is not scroll-locked; Ctrl+Click locking the outer container restores normal inner-scroll behaviour
- `app_event_loop`: first keypress after closing a modal no longer dropped — when `dispatch_event_sync` causes all screens to pop, `render_app` is called immediately to produce a fresh, consistent `widget_hierarchy`; previously the stale hierarchy caused a spurious `phash2` mismatch that set `consumed = true` and silently swallowed the event
- `ComponentRenderer`: auto-generated widget IDs are now namespaced by `app_module` (e.g. `ThemeSandbox_button_1` vs `InputModal_button_1`), eliminating ETS strip collisions between base-app and modal hierarchies that caused base-app widgets (e.g. the "Open Modal" button) to visually disappear when a modal was opened
- `Drafter.App`: `on_scroll_active/1` optional callback — fires once on the first scroll event of a gesture; return updated state (e.g. `%{state | scrolling: true}`)
- `Drafter.App`: `on_scroll_idle/1` optional callback — fires when the 150 ms debounce settles after the last scroll event; return updated state (e.g. flush pending data, clear scrolling flag)
- `Drafter.App`: `on_message/2` optional callback — receives any process message not recognised by the drafter event loop (PubSub, `send/2`, GenServer casts, etc.); return updated state. Previously all such messages were silently dropped.
- `Drafter.run/2` / `run_session/3`: `scroll_optimization: false` opt-out — disables the fast render/debounce path and triggers a full `render_app` on every scroll tick. Default is `true`.

```elixir
def on_scroll_active(state), do: %{state | scrolling: true}

def on_scroll_idle(state) do
  state = if state.pending_data, do: apply_pending_data(state), else: state
  %{state | scrolling: false, pending_data: nil}
end

def on_message({:data_refreshed, _uid, payload}, state), do: %{state | rows: payload.rows}

Drafter.run(MyApp, scroll_optimization: false)
```

### Fixed
- Modal focus isolation: base app widgets are now defocused (blurred) whenever a modal/screen is active — the button that opened the modal no longer retains focus styling or responds to keyboard events while the modal is open; focus is restored to the first focusable widget after the modal closes
- `ScreenManager`: `meaningful_hierarchy_change?` now compares widget state hashes (`phash2`), so text input changes inside modals are correctly detected as meaningful and the updated hierarchy is persisted
- `WidgetServer`: `event_sync` no longer calls `notify_render_needed` — the event loop renders after `event_sync` returns; calling it again was flooding the mailbox with one `{:widget_render_needed}` per scroll tick
- `WidgetHierarchy`: `update_widget` no longer blocks on `WidgetServer.get_state/1` after casting `update_props` — `update_props` is now a true fire-and-forget cast; ETS has the authoritative strips so rendering is unaffected
- `app_event_loop` / `shared_session_loop`: `{:widget_render_needed}` handler drains all pending notifications before doing a single `render_hierarchy`, eliminating N-fold duplicate composites when multiple widgets fire at once
- `app_event_loop` / `shared_session_loop`: `:scroll_debounce_render` handler drains all accumulated debounce messages before triggering one `render_app`, preventing update debt accumulation during slow/continuous scrolling
- `render_hierarchy` (fast scroll path): modals, popovers, and toasts are now correctly composited during scroll — previously the fast path painted only base app widgets, overwriting any open modal. Now reads screen and toast layers from stored ETS/hierarchy state with no `ComponentRenderer` re-run.
- Removed `sync_widget_states/1` — no longer needed; `render_hierarchy` reads strips directly from ETS

## [0.1.19] - 2026-03-16
### Changed
- `WidgetServer`: each widget owns its strip buffer via `WidgetStripCache` (ETS, public, `read_concurrency: true`) — rendering happens inside the widget's own GenServer process and results are written to ETS; `create_widget_layers_from_hierarchy` reads from ETS directly (no inter-process messaging, no round-trips)
- `WidgetServer`: `update_props` renders and writes to ETS when state changes but does **not** send `{:widget_render_needed}` — only autonomous widget state changes (events, timers) notify the event loop, eliminating redundant re-composites after `render_app`
- `WidgetServer`: `update_props` with identical resulting state is a no-op (no render, no ETS write)
- `ScrollableContainer`: scroll events use a fast render path — `render_hierarchy` re-clips ETS-cached strips without running `ComponentRenderer`; 150 ms debounce fires `render_app` once after scroll settles
- `MouseProcessor`: `mouse_move` while a button is held routes to the `mouse_down_widget` regardless of cursor position, enabling drag-out-of-bounds behaviour; `mouse_up` after drag-release outside the originating widget notifies the `mouse_down_widget` so it can clear drag state

### Added
- `WidgetStripCache`: ETS-backed strip store keyed by widget ID; lock-free reads from any process
- `ScrollableContainer`: click on scrollbar track jumps one viewport page toward the thumb
- `ScrollableContainer`: drag the scrollbar thumb — `mouse_down` on thumb begins drag, `mouse_move` continuously updates scroll offset, `mouse_up` ends drag

## [0.1.18] - 2026-03-15
### Fixed
- `DataTable`: click and Enter now toggle selection in both `:single` and `:multiple` modes — clicking or pressing Enter on an already-selected row deselects it; previously `change_selection/3` always set selection, while Space already toggled correctly via `action_toggle_selection`
- `DataTable`: arrow key navigation no longer inadvertently toggles selection in `:multiple` mode — `action_cursor_up/down` now pass `trigger_select: false` so moving the cursor never changes the selected set; only Enter, Space, and click change selection
- `Collapsible`: hidden children no longer receive mouse events — `find_widget_at` now excludes `hidden_widgets` from hit testing, preventing clicks intended for widgets beneath a collapsed section (e.g. a `DataTable` header) from being intercepted by invisible child widgets
- `Collapsible`: widget content (list) no longer renders over siblings below it — two root causes fixed:
  - `Collapsible.update/2` was resetting `content_height` to the default (10) on every re-render when only `content` was passed in `updated_props`, corrupting the stored height after the first render
  - `get_child_vertical_spec` / `get_preferred_height` ignored the `expanded:` and `content_height:` options when the widget was not yet in the hierarchy (first render), always returning height 1 and placing the next sibling at the wrong y position

## [0.1.17] - 2026-03-15
### Added
- `Digits`: `bg_data:` prop renders a braille line chart (4× vertical resolution per terminal row) behind the digit glyphs; `color:` sets the line colour; digits take priority where glyphs overlap braille dots
- `Sparkline`: `orientation: :horizontal` renders each data point as a left-to-right bar using left-aligned eighth-block characters (`▏▎▍▌▋▊▉█`)
- `Chart`: `pixel_style: :quadrant` option for line and scatter charts — uses quadrant block characters (`▖▗▘▝▚▞▛▜▟▙▀▄▌▐█`) at 2×2 pixel resolution per cell, giving larger/more visible dots than braille

## [0.1.16] - 2026-03-15
### Changed
- `Digits`: improved `B` glyph in both large and small sizes — more distinguishable from `8` and `6`; large uses flat `├` spine with `╲`/`╱` bump sides, small uses `╲` divider in the middle row

### Added
- `Rule`: new widget — horizontal/vertical divider line with optional embedded title, `title_align`, and `line_style` (`:solid`, `:double`, `:dashed`, `:thick`)
- `Tree`: `on_node_highlight:` callback fires whenever cursor moves to a new node; `Shift+←`/`Shift+→` navigates to previous/next sibling at the same depth
- `SelectionList`: `on_item_toggle:` callback fires with `{index, selected?}` on each individual item toggle; `Home`/`End` jump to first/last item; `Ctrl+A` toggles select-all / deselect-all in `:multiple` mode
- `MaskedInput`: `on_submit:` callback fires with the raw unmasked value on `Enter`
- `TextArea`: text selection (`Shift+Arrow`, `Ctrl+A`), copy/cut/paste (`Ctrl+C`/`X`/`V`), undo/redo (`Ctrl+Z`/`Y`), `read_only:`, `tab_behavior:` (`:focus` or `:indent`), `tab_size:`, `max_checkpoints:`, word navigation (`Ctrl+←`/`→`), page up/down, `highlight_cursor_line:`

## [0.1.15] - 2026-03-15
### Added
- `DataTable`: per-cell background colouring via `color_fn: (raw_value -> {r,g,b} | nil)` on column definitions; applied when the row is not selected
- `DataTable`: 3-state column sort cycle — click cycles ascending → descending → unsorted (restores original data order); `↕` indicator shown on all sortable-but-unsorted columns when `sortable: true`
- `DataTable`: table-level `sortable: false` option disables all sort indicators and click-to-sort
- `DataTable`: column width drag-resize — drag a column header to resize (when `locked: true`, the default); minimum 3 characters
- `DataTable`: column reorder — `Shift+←` / `Shift+→` moves the cursor column; drag a header while `locked: false` swaps columns live
- `DataTable`: `locked:` option — `true` (default) makes header-drag resize; `false` makes header-drag reorder
- `DataTable`: `on_layout_change:` callback — fires with `%{col_widths: [...], col_order: [...]}` after any resize or reorder
- `DataTable`: `col_widths:` and `col_order:` mount/update props to restore a previously saved layout
- `DataTable`: keyboard resize (`+`/`-`) fires `on_layout_change` after each step
- `DataTable`: `FocusRegistry` integration — footer key-binding bar updates dynamically when the table gains focus
- `FocusRegistry`: new `GenServer` tracking the focused widget's key bindings; consumed by `Footer` for dynamic display
- `EventRouter`: `{:key, key, mods}` events now dispatch to `handle_key/3` if exported, falling back to `handle_key/2`

## [0.1.14] - 2026-03-14
### Fixed
- Timer-driven re-renders skipped when `on_timer/2` returns state unchanged (`===`);
  applies to both `app_event_loop` and `shared_session_loop`. Eliminates redundant
  `render_app` / widget tree traversal on poll timers that find no new data.
- `{:widget_render_needed}` (fired by widget-internal timers such as the header clock)
  no longer triggers `ComponentRenderer.render_tree`. It now calls `render_hierarchy`
  which re-composites directly from the already-synced widget states, avoiding
  `update_widget` calls — and therefore `filter_list` — on every clock tick.

## [0.1.13] - 2026-03-14 *
### Added
- Multi-series line charts: pass a list of series (list of lists) to `chart_type: :line`
- Multi-series scatter charts: pass a list of point-lists to `chart_type: :scatter`
- `:clustered_bar` chart type — grouped multi-series bars with half-block resolution
- `:stacked_bar` chart type — series stack from baseline; supports mixed positive/negative values
- `:range_bar` chart type — each bar spans a `[low, high]` range
- Negative value support documented and verified across all chart types
- `multi_series_charts.exs` example demonstrating all new chart variants

### Fixed
- Area chart crash (`ArithmeticError`) when passed multi-series data; now dispatches to
  `render_multi_series` matching the same guard added to line chart

### Changed
- `Chart` moduledoc expanded with sections for negative values, multi-series API, and all bar types

## [0.1.11] - 2026-03-14 ★
### Added
- Scrollable viewport culling: off-screen children skipped during `render_component` calls,
  reducing GenServer traffic per frame for large scrollable lists

### Changed
- `count_component_slots/1` introduced to advance the ID counter for culled components,
  preserving auto-generated widget IDs for on-screen widgets

## [0.1.10] - 2026-03-14
### Fixed
- Chart axis labels: float concatenation crash in `format_axis_value/1` for values ≥ 1000

## [0.1.9] - 2026-03-14
### Fixed
- Binding resolution: `Checkbox` now reads `:checked` from opts at mount (was always `false`)
- `ComponentRenderer` checkbox update path now syncs `:checked` and `:on_change` on re-render
- `ComponentRenderer` `radio_set` update path now passes `:options` and `:selected` (was only
  `:on_change` and `:classes`, leaving options frozen after mount)
- `RadioSet.update/2` no longer resets `highlighted_index` on every timer-driven re-render

## [0.1.8] - 2026-03-14 ★
### Added
- Differential rendering in compositor: row-level dirty detection via `Strip.cache_key`
  (`:erlang.phash2` hash); unchanged rows skipped each frame, drastically reducing
  terminal output on static or partially-static screens
- Stale test cleanup: removed 10 test files referencing renamed/removed modules

### Fixed
- `TextInput`: scroll offset was double-subtracting border width, causing scroll to
  trigger 2 characters early
- `TextInput`: typed text no longer reset on re-render when widget has no `:bind` or
  `:value` prop

## [0.1.6] - 2026-03-14 ★
### Fixed
- `RadioSet`: options passed as raw tuples were not normalised at mount; now always
  stored as `%{id: _, label: _}` maps
- `RadioSet`: options not updating on re-render after first mount
- `RadioSet`: `highlighted_index` frozen after navigating before first selection

## [0.1.5] - 2026-03-14 ★
### Added
- `Collapsible` widget now supports interactive child widgets (buttons, inputs, etc.)
  inside the expanded body, not just plain text

### Fixed
- `Collapsible.update/2`: `content_height` no longer inherits stale value when content
  type changes between renders

## [0.1.4] - 2026-03-13 ★
### Fixed
- SSH: reverse entry bug introduced when SSH support was added
- Local startup issues with terminal initialisation

## [0.1.3] - 2026-03-13 ★
### Fixed
- Input handling cleanup following SSH integration

## [0.1.2] - 2026-03-13 ★
### Added
- Guide: Remote TUI over SSH/Telnet (`guides/remote_tui.md`)

## [0.1.1] - 2026-03-13 ★
### Added
- SSH and Telnet remote TUI support via `Drafter.Server`
- Remote client connects over standard SSH; full terminal interaction over the wire

### Fixed
- Theme switching between light and dark modes

## [0.1.0] - 2026-03-12 ★
### Added
- Initial public release
- Core framework: `Drafter.App` behaviour, widget lifecycle, event system
- Widget library: Label, Button, TextInput, TextArea, Checkbox, Switch, RadioSet,
  SelectionList, OptionList, MaskedInput, Link, DataTable, Tree, DirectoryTree,
  Chart, Sparkline, ProgressBar, LoadingIndicator, Pretty, Digits, Log, RichLog,
  Rule, Placeholder, Markdown, CodeView, Collapsible, TabbedContent, Card,
  Container, ScrollableContainer, Grid, Header, Footer
- Theming system with light/dark built-in themes and custom theme support
- Braille-dot chart rendering with line, area, bar, scatter, and candlestick types
- Layout engine: vertical, horizontal, scrollable containers with flex sizing
- Focus management: tab and arrow-key geometric navigation
- Multi-screen navigation stack with modal support
- Toast notification system with 9 positions and stack limiting
- Tree-sitter syntax highlighting integration (opt-in)
- Windows terminal support
- Dynamic actions and native alert/confirm dialogs
- Custom action handler API
