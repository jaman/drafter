# Design Notes

Background on why parts of Drafter are built the way they are. Nothing here is
needed to *use* the framework — the module documentation covers that. This is for
anyone changing the internals, or wondering why an obvious-looking simplification
is not one.

## Contents

- [Processes and lifetimes](#processes-and-lifetimes)
- [Widget identity and state](#widget-identity-and-state)
- [Events](#events)
- [Layout](#layout)
- [Rendering and compositing](#rendering-and-compositing)
- [Scrolling and scrollbars](#scrolling-and-scrollbars)
- [Charts](#charts)
- [Terminal I/O](#terminal-io)

---

## Processes and lifetimes

### ETS tables are owned by a supervised process

An ETS table lives only as long as the process that created it. Creating the
framework's shared tables lazily, from whichever process first needed one, would
tie the strip cache's lifetime to an arbitrary widget server — unmounting that
widget would drop the cache for every widget in every session.
`Drafter.TableOwner` is a supervised process that outlives all of them and
creates the tables at startup, decoupling table lifetime from widget lifetime.
The per-module `create/0` functions remain as idempotent no-ops.

### Widget servers are supervised, not linked

Widgets are started during rendering. Linking them to the app loop would make any
crash in a widget's `mount/1`, `render/2` or event handling fatal to the whole
session. Started under `Drafter.Widget.Supervisor` and unlinked, a faulty widget
takes down only itself and the frame degrades to that widget's last cached
strips. The fallback to a plain link exists for unit tests that drive a widget
directly without the supervisor running.

### Reading widget state must not be fatal

A widget busy rendering something expensive — a large chart, a wide table — will
not service a call promptly. Because these servers are reachable from the app
loop, an unguarded call timeout on the render path would take down the whole
session. `Drafter.WidgetServer.safe_get_state/2` converts that into a `nil`, so
the render path degrades to a stale frame instead.

### Widget state stays in its server

The event router needs to know whether a widget handled an event and what actions
it raised; it does not need the widget's state, which the server owns. Returning
state from a dispatch would copy everything the widget holds — a log buffer, a
table's rows, a shell's scrollback — across the process boundary on every
keystroke, at a cost that scales with the data rather than the interaction. The
same reasoning motivates `get_state_fields/2` alongside `get_state/1`: callers
needing one or two flags should ask for those rather than pay for a full copy.

### Registry keys are qualified by session

Widget ids come from application code, so two concurrent sessions — two SSH
clients of the same app, say — routinely use the same id for different widgets.
`Drafter.WidgetPidRegistry` keys are therefore qualified by the session,
identified by its compositor, so `Drafter.get_widget_value/1` and friends resolve
within the caller's own session rather than whichever session registered last.

For the same reason, `Drafter.AppRegistry` registers each app loop under its
session id. A process that sits outside any session must capture
`Drafter.AppRegistry.current_session/0` inside the session and pass it to
`whereis/1` or `send_to_loop/2`; the "sole registered loop" fallback stops being
answerable as soon as a second session exists.

### Tests address their own session

Resolving the app loop through the global registry asks "which loop is running",
which has no answer while a previous test's session is still shutting down. The
test context already names the process the assertion is about, so assertions send
to that pid directly and fall back to the registry only when no pid is present.

### Runtime backends do not implement `render/1`

`render/1` is deliberately outside the `Drafter.Runtime` behaviour. Every backend
turns an app state into a widget tree the same way, so the renderer calls the
app's `render/1` directly rather than routing it through the backend.

## Widget identity and state

A widget's identity is what its state is retained under between renders. An
explicit `:id` wins. Failing that, a `:key` distinguishes siblings by something
stable in the data rather than by position; keys are strings, so a list keyed by
record id does not mint an atom per record. Failing both, identity falls back to
the widget's position in the render traversal — which is stable only while the
shape of the tree is. Show or hide one earlier widget and every later widget
inherits its neighbour's state.

## Events

### Catch-all clauses must come last

`use` and `defoverridable` cannot supply the fallback clauses an app needs.
Defining a single clause of `handle_event/2` — which the `keybinding` macro does
— replaces the overridable default outright rather than adding to it, leaving the
app with no fallback and crashing the session the first time an unenumerated
event is routed. Hover events alone make that a certainty. Emitting the fallbacks
from `Drafter.App.__before_compile__/1` places them after every user clause.

### Consumption comes from the handler's verdict

Consumption follows what the handler said, not whether the widget's state
happened to change. A button clicked twice inside its active-effect window
produces identical state the second time, but it did handle the click; inferring
consumption from a state diff would report otherwise and the event would go on to
be offered elsewhere.

The same holds for arrow keys and focus. Whether a focused widget acted on an
arrow — or whether focus should move instead — is read from the router's recorded
verdict. A widget whose state is owned by its server never writes to the
hierarchy map at all, so a state diff cannot see it; and a widget that handled
the key without changing state looks idle. Either misreading delivers the arrow a
second time and moves the cursor twice.

### Containers consume only what a child took

A container is a conduit for its children, not a handler in its own right. It
reports `{:ok, state}` only when a child took the event and `{:bubble, state}`
otherwise, so an event no child wanted — an application-level keyboard shortcut,
for instance — keeps travelling up the hierarchy instead of stopping at the
container.

### Every animation tick must reach the widget

A tween that only delivers its final value is not an animation: the intermediate
frames are computed and then discarded, so the property jumps once the duration
elapses. Each tick has to be pushed to the widget for the motion to exist.

## Layout

### Layout units must be honoured, not ignored

Percentages, fractions and `:auto` are declarable in a stylesheet. Accepting them
in the syntax while resolving only integers is worse than not offering them at
all, because the resulting layout silently disagrees with what the author asked
for.

### Docking is a general option, not a footer special case

Docking takes a component out of the normal flow and gives it the full span of
its edge, leaving the remainder for undocked siblings. Recognising only a
hardcoded `:footer` tag would make the feature available to exactly one widget
and invisible to every other, so `Drafter.Layout.dock_edge/1` reads a `:dock`
option from any component.

### Overflow lives on the hierarchy

Overflow is a presentation choice made where a component is declared, but it is
applied where strips meet their rect. Carrying it on the hierarchy keeps it
available to the renderer without every widget having to thread it through its
own state. It is likewise applied once in the renderer rather than inside each
widget: every widget emits strips, and overflow is a property of a strip measured
against its rect.

### Laid-out geometry versus mount-time geometry

`render/2` receives the rect the widget was actually given, but it cannot persist
anything. Scroll arithmetic that runs off stored state — thumb placement, click
and drag mapping — would otherwise keep using the height supplied at mount.
`on_rect_change/2` writes the real viewport height and width back onto the state
so drawing and hit-testing share one geometry.

## Rendering and compositing

### Re-render on every rect update

Every widget is visited on every render pass, and
`Drafter.WidgetHierarchy.update_widget_rect/3` is what re-renders it. That is
also how anything whose appearance changes without its geometry changing stays
current: live data feeds, animation frames, theme and skin changes, spinners.
Skipping the re-render when the rect happens to match would leave those widgets
stale until some unrelated event moved them.

### Translucency is resolved at compositing time

A terminal cell holds a single colour and there is no display-side alpha to defer
to, so translucency has to be resolved where layers meet. The `:opacity` marker
is consumed during compositing and never reaches output.

Opacity is carried on the layer rather than stamped onto each segment. Stamping
it would rebuild every segment and re-derive the strip's width and cache key, at
a cost proportional to the widget's content for every frame of a tween. The layer
carries one value and the compositor applies it as it blends.

A tween also writes its value onto the widget's *recorded* state, which is not
where a widget's own `render/2` looks — the widget produced its strips before the
frame was computed. So offsets move the layer rather than redrawing its contents.

### Partial visibility is still visibility

Visibility is recorded as a rect rather than a boolean because, for an
image-backed widget, the on-screen region is the portion worth generating. A
chart taller than its viewport is never fully visible, so treating "not fully
visible" as "not visible" would erase it outright. A widget clipped by a scroll
viewport still shows the rows that survived clipping, and the image should cover
those rows. Only a widget with nothing left on screen, or one mid-scroll or
mid-resize where the image would lag the text, is skipped.

### Image placement carries no bytes

Terminal-graphics bytes are stored once per generation by
`Drafter.Compositor.put_image/8`, from the widget's async render task, so they
never travel through the render loop. `place_image/3` is then a per-frame update
that only positions the region and marks it visible.

### Layer depth from id prefix

Layer depth is currently keyed off the id's name prefix, so chrome is only lifted
above content for ids literally beginning with `"footer"` or `"header"`.
Component-generated ids are namespaced (`MyApp_footer_3`) and therefore land at
the default depth. Keying depth off the widget module instead would be sounder,
but it reorders existing layouts, so it belongs with a deliberate layering pass.

## Scrolling and scrollbars

### The thumb is sized, so the mapping is not linear in the viewport

The thumb is sized in proportion to the viewport, so it occupies several rows and
travels a track shortened by its own size (`viewport_height - thumb_size`). Code
turning a pointer row back into a scroll offset must use
`Drafter.Widget.Scrollbar.offset_from_row/3`, the exact inverse of `thumb_rows/3`,
rather than mapping the row across the full viewport height as though the thumb
were a single row. The two mappings diverge by up to `thumb_size - 1` rows, and
the divergence grows the further down the bar the pointer travels.

For the same reason a widget must draw and drag its scrollbar through one
geometry. A renderer that draws a single-row thumb while the drag handler maps
against a sized one puts the drawn thumb and the pointer progressively out of
step.

### Holding the grabbed point under the pointer

A drag should move the thumb by the pointer's displacement, not snap the thumb's
top to the pointer. `grab_offset/4` records how far into the thumb the press
landed and `offset_from_drag/4` subtracts it, so a thumb grabbed by its middle
stays grabbed by its middle for the whole drag. A press on the track returns `0`,
which deliberately does snap the thumb's top to the pointer.

### Drags begin on press

A scrollbar drag is started by the mouse-down handler and ended by the release
handler, because the drag events that do the scrolling only arrive while the
button is held. Starting the drag on release would leave the widget in drag mode
with nothing to end it.

## Charts

### Series are anchored to the right edge

Each datum in a candlestick or bar series needs a minimum band width to be
legible, so a series longer than the raster can hold cannot be drawn in full. The
chart keeps the trailing datums that fit and anchors them to the right edge,
which keeps the newest values on screen and lets the chart advance as data
arrives.

### Scatter data accepts the same shapes as every other chart

Scatter points may be given as `{x, y}`, `{x, y, weight}`, `[x, y]`, or
`%{x: x, y: y}`. A bare series of numbers is also accepted and indexed, position
supplying x, so that the same input renders under every chart type rather than
producing an empty image.

### Column-major option layout

`Drafter.Widget.RadioSet` fills its options column-major — the first column top
to bottom, then the next — so a click's row alone does not identify an option once
`:cols` exceeds one. Hit-testing resolves the column from x before combining it
with the row.

## Terminal I/O

### Escape sequences are buffered across reads

A read from the terminal can end part-way through an escape sequence. Feeding
such a chunk to a stateless parser decomposes the fragment into the bytes that
make it up: an arrow key becomes `escape`, `[`, `A`, and a bracketed paste
becomes its literal marker text. `Drafter.Terminal.InputBuffer` holds the partial
tail and carries it into the next read.

A trailing lone `ESC` is genuinely ambiguous — it is both a complete keypress and
the start of every escape sequence — and is resolved by a short timeout.

### Resize is signal-driven

The OS signals a terminal size change the instant it happens. `SIGWINCH` is
relayed by `Drafter.Terminal.SignalWatcher`, which handles only the signals
Drafter cares about and leaves every other signal's default behaviour alone.

### A wheel notch is one event

Terminals differ: some report only the press for a wheel notch, others report a
release too. Classifying the release as another scroll makes those terminals
scroll twice per notch — the list moves two rows for one click of the wheel.

### Window size must be pushed to pty children

A child process on the far side of a pseudoterminal learns its dimensions only
from the kernel, and is signalled with `SIGWINCH` when they change. A multiplexer
or shell that resizes its panes without calling `set_winsize` leaves every child
believing it still has the size it started with.

`Drafter.Terminal.TermiosNif.open_pty/2` deliberately does no forking or
exec'ing: those belong in Elixir, where failures are observable and supervision
applies.

### The pty helper replaces itself with the program

`priv/pty_spawn` puts itself in a new session, acquires the slave as its
controlling terminal, redirects its own standard descriptors onto it, closes
everything it inherited, and then execs the requested program. Because it
replaces itself rather than relaying, no intermediate process remains and the
reported OS pid is the program's own. Setup failures are reported as exit
statuses rather than written to standard error, since until the redirect
completes those descriptors still belong to the emulator.

### Console logging is removed, file logging is opt-in

The `:default` Logger handler is removed during a TUI run because console output
would paint over the rendered frame. Writing a log file is left to the
application rather than defaulted on.
