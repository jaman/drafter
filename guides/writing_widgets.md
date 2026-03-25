# Writing Widgets & Widget Libraries

This guide covers everything you need to build a custom Drafter widget,
package it as a reusable library, and publish it so other developers can
drop it into their own apps.

## Contents

- [How widgets work](#how-widgets-work)
- [Minimal widget](#minimal-widget)
- [Rendering](#rendering)
- [Event handling](#event-handling)
- [Composable traits](#composable-traits)
- [Declaring capabilities](#declaring-capabilities)
- [The component DSL bridge](#the-component-dsl-bridge)
- [Packaging a widget library](#packaging-a-widget-library)
- [Using a widget library](#using-a-widget-library)

---

## How widgets work

A widget is a `GenServer` process managed by Drafter. The framework calls
your module's callbacks to mount, render, update, and unmount the widget as
the application runs. Rendering produces a list of `Drafter.Draw.Strip`
values — one per terminal row — that Drafter composites onto the screen.

---

## Minimal widget

```elixir
defmodule MyWidget do
  use Drafter.Widget

  defstruct [:label]

  @impl Drafter.Widget
  def mount(props) do
    %__MODULE__{label: Map.get(props, :label, "hello")}
  end

  @impl Drafter.Widget
  def render(state, _rect) do
    alias Drafter.Draw.{Segment, Strip}
    [Strip.new([Segment.new(state.label, %{fg: {255, 255, 255}})])]
  end

  def component_tag, do: :my_widget

  def from_component_opts(_args, opts) do
    %{label: Keyword.get(opts, :label, "hello")}
  end
end
```

That is a complete, runnable widget. The two functions at the bottom —
`component_tag/0` and `from_component_opts/2` — are the bridge to Drafter's
component DSL and are covered in detail [below](#the-component-dsl-bridge).

---

## Rendering

`render/2` receives the current widget state and a `rect` describing the
screen area allocated to the widget:

```elixir
%{x: integer, y: integer, width: integer, height: integer}
```

It must return a list of `Drafter.Draw.Strip` values. Return one strip per
row you want to paint; Drafter clips and pads automatically.

```elixir
alias Drafter.Draw.{Segment, Strip}
alias Drafter.ThemeManager

@impl Drafter.Widget
def render(state, rect) do
  theme = ThemeManager.get_current_theme()
  bg    = theme.background
  fg    = theme.foreground

  Enum.map(0..(rect.height - 1), fn row ->
    text = if row == 0, do: state.title, else: ""
    Strip.new([Segment.new(String.pad_trailing(text, rect.width), %{fg: fg, bg: bg})])
  end)
end
```

### Segments

`Drafter.Draw.Segment.new(text, style)` — `style` is a map with optional keys:

| Key | Type | Description |
|-----|------|-------------|
| `:fg` | `{r, g, b}` or theme atom | Foreground colour |
| `:bg` | `{r, g, b}` or theme atom | Background colour |
| `:bold` | `boolean` | Bold text |
| `:italic` | `boolean` | Italic text |
| `:underline` | `boolean` | Underlined text |
| `:strikethrough` | `boolean` | Strikethrough text |

Theme colour atoms (`:foreground`, `:background`, `:accent`, `:success`,
`:warning`, `:error`, `:text_muted`) are resolved to RGB at render time so
your widget respects the active theme automatically.

---

## Event handling

### Option A — composable traits (recommended)

See [Composable traits](#composable-traits) below for the preferred
approach. Traits handle common capabilities like focus management,
scrolling, and selection automatically.

### Option B — declarative `handles:`

Declare which event types your widget cares about in `use Drafter.Widget`.
Drafter routes each event to the matching callback automatically.

```elixir
defmodule MyWidget do
  use Drafter.Widget,
    handles: [:keyboard, :scroll, :click],
    focusable: true

  defstruct [:value, :focused]

  @impl Drafter.Widget
  def handle_key(:up,   state), do: {:ok, %{state | value: state.value + 1}}
  def handle_key(:down, state), do: {:ok, %{state | value: state.value - 1}}
  def handle_key(_key,  state), do: {:ok, state}

  @impl Drafter.Widget
  def handle_scroll(:up,   state), do: {:ok, %{state | value: state.value + 5}}
  def handle_scroll(:down, state), do: {:ok, %{state | value: state.value - 5}}

  @impl Drafter.Widget
  def handle_press(_x, _y, state), do: {:ok, state}
end
```

Available `handles:` values and their callbacks:

| Value | Callback |
|-------|----------|
| `:keyboard` | `handle_key(key, state)` |
| `:scroll` | `handle_scroll(direction, state)` |
| `:click` | `handle_press(x, y, state)` |
| `:drag` | `handle_drag(x, y, state)` |
| `:hover` | `handle_hover(x, y, state)` |

Setting `focusable: true` (or including `:keyboard` in `handles:`) adds the
widget to the tab-order and geometric arrow-key navigation.

### Option C — low-level `handle_event/2`

Override `handle_event/2` directly to intercept the raw event term:

```elixir
@impl Drafter.Widget
def handle_event({:key, :enter}, state) do
  {:ok, %{state | submitted: true}}
end

def handle_event({:mouse, %{type: :scroll, direction: :up}}, state) do
  {:ok, %{state | offset: max(0, state.offset - 3)}}
end

def handle_event(_event, state), do: {:bubble, state}
```

Return values:

| Return | Meaning |
|--------|---------|
| `{:ok, new_state}` | Event handled; widget re-renders |
| `{:noreply, state}` | Event ignored; no re-render |
| `{:bubble, state}` | Pass event up to the parent / app |
| `{:error, reason}` | Log and continue |

### Notifying the application

Emit a callback to the parent app with `{:app_callback, event_name, data}`:

```elixir
def handle_key(:enter, state) do
  {:ok, state, [{:app_callback, :item_selected, state.highlighted}]}
end
```

The app receives it in `handle_event/3`:

```elixir
def handle_event(:item_selected, item, state) do
  {:ok, %{state | selection: item}}
end
```

---

## Composable traits

Traits are reusable capabilities that you compose onto a widget. Each trait
manages its own state fields, handles specific events, and can decorate
rendering via pre/post render hooks. This is the preferred way to build
interactive widgets.

### Basic usage

```elixir
defmodule MyList do
  use Drafter.Widget,
    traits: [:focusable],
    handles: [:keyboard]

  defstruct [:items, :focused, :cursor]

  @impl Drafter.Widget
  def mount(props) do
    %__MODULE__{
      items: Map.get(props, :items, []),
      focused: false,
      cursor: 0
    }
  end

  @impl Drafter.Widget
  def handle_key(:up, state), do: {:ok, %{state | cursor: max(0, state.cursor - 1)}}
  def handle_key(:down, state), do: {:ok, %{state | cursor: state.cursor + 1}}
  def handle_key(_key, state), do: {:bubble, state}
end
```

The `:focusable` trait injects `focused: false` into default state and
handles `{:focus}` / `{:blur}` events automatically. The `handles:`
option declares additional event types the widget processes itself.

### Available built-in traits

| Trait | Injected state | Events handled |
|-------|---------------|----------------|
| `:focusable` | `focused` | focus, blur |
| `:scrollable` | `_scroll_offset_y`, `_scroll_offset_x`, `_viewport_height`, `_content_height` | scroll, keyboard (arrows, page up/down, home/end) |
| `:selectable` | `_cursor_index`, `_selected_indices`, `_selection_mode` | keyboard (arrows, space) |
| `:editable` | `_text`, `_cursor_position`, `_selection_start`, `_selection_end` | keyboard, char |
| `:collapsible` | `_expanded` | keyboard (enter/space), click |
| `:resizable` | `_resize_dragging`, `_resize_edge`, `_min_width`, `_min_height` | drag, press, mouse_up, hover |
| `:draggable` | `_drag_active`, `_drag_offset_x`, `_drag_offset_y` | press, drag, mouse_up |
| `:animatable` | `_render_timestamp` | (passive — updated each render cycle) |

### Combining traits

Traits compose naturally. Each trait's event handler runs in declaration
order. If a trait handles an event, the next trait still gets a chance
unless the event is explicitly consumed.

```elixir
defmodule ScrollableList do
  use Drafter.Widget,
    traits: [:focusable, :scrollable, :selectable],
    scroll: [direction: :vertical, step: 1]
end
```

### Trait event pipeline

Events pass through each trait in order. Each trait returns one of:

| Return | Meaning |
|--------|---------|
| `{:ok, new_trait_state}` | Handled; update state, continue pipeline |
| `{:pass, trait_state}` | Not handled; pass to next trait |
| `{:consume, new_trait_state}` | Handled; stop pipeline, skip widget handler |

After all traits process, the event reaches the widget's own handler
(unless consumed).

### Trait dependencies

Some traits depend on others. Dependencies are resolved automatically:

- `:selectable` depends on `:focusable`
- `:editable` depends on `:focusable`
- `:collapsible` depends on `:focusable`
- `:resizable` depends on `:focusable`
- `:draggable` depends on `:focusable`

If you declare `traits: [:selectable]`, the `:focusable` trait is
added automatically.

### Pre/post render hooks

Traits can modify the render rect before your `render/2` runs
(via `pre_render/3`) and decorate the output strips after (via
`post_render/4`). For example, the `:scrollable` trait reduces
rect width by one column for the scrollbar in `pre_render`, then
clips content and appends the scrollbar in `post_render`.

### Custom traits

Define a custom trait by implementing the `Drafter.Widget.Trait`
behaviour:

```elixir
defmodule MyApp.Trait.Highlightable do
  @behaviour Drafter.Widget.Trait

  defstruct __spark_metadata__: nil

  @impl true
  def name, do: :highlightable

  @impl true
  def default_state, do: %{_highlighted: false}

  @impl true
  def dependencies, do: [:focusable]

  @impl true
  def handles, do: [:keyboard]

  @impl true
  def render_affecting_fields, do: [:_highlighted]

  @impl true
  def layout_static?, do: true

  @impl true
  def handle_event({:key, :h}, trait_state, _widget_state) do
    {:ok, %{trait_state | _highlighted: !trait_state._highlighted}}
  end

  def handle_event(_event, trait_state, _widget_state) do
    {:pass, trait_state}
  end
end
```

Reference custom traits by full module name:

```elixir
use Drafter.Widget,
  traits: [:focusable, MyApp.Trait.Highlightable]
```

---

## Declaring capabilities

### `update/2`

Called whenever the parent re-renders and passes new props to the widget.
Return the updated state. Only update fields that are actually present in the
new props to avoid clobbering internal widget state:

```elixir
@impl Drafter.Widget
def update(props, state) do
  state
  |> maybe_put(:label, props)
  |> maybe_put(:color, props)
end

defp maybe_put(state, key, props) do
  case Map.fetch(props, key) do
    {:ok, value} -> Map.put(state, key, value)
    :error -> state
  end
end
```

### `unmount/1`

Called when the widget is removed from the hierarchy. Use it to cancel
timers, close ports, or release any other resources:

```elixir
@impl Drafter.Widget
def unmount(state) do
  if state.timer_ref, do: :timer.cancel(state.timer_ref)
  :ok
end
```

### `preferred_height/2`

Return the number of terminal rows this widget wants when height is not
explicitly specified:

```elixir
def preferred_height(_args, opts) do
  Keyword.get(opts, :height, 5)
end
```

---

## The component DSL bridge

Two functions connect your widget to Drafter's render DSL so users can write
`my_widget(label: "hi")` inside `render/1`:

### `component_tag/0`

Returns a unique atom that identifies your widget in the component renderer.
Choose something that will not clash with built-in tags or other libraries:

```elixir
def component_tag, do: :acme_heatmap
```

### `from_component_opts/2`

Converts the keyword list passed by the user into the `props` map that
`mount/1` and `update/2` receive. `args` is the first positional argument
(if any); `opts` is the keyword list.

```elixir
def from_component_opts(_args, opts) do
  %{
    data:   Keyword.get(opts, :data, []),
    color:  Keyword.get(opts, :color, {100, 200, 255}),
    height: Keyword.get(opts, :height, 8)
  }
end
```

### `update_props_from_mount/3`

Controls which fields are forwarded to `update/2` on each re-render.
Returning only the fields your widget accepts prevents unrelated app state
from polluting `update/2`:

```elixir
def update_props_from_mount(mount_props, _existing_state, _opts) do
  Map.take(mount_props, [:data, :color])
end
```

---

## Packaging a widget library

Once you have one or more widgets, wrap them in a library module using
`Drafter.WidgetLibrary`:

```elixir
defmodule AcmeWidgets do
  use Drafter.WidgetLibrary,
    widgets: [
      AcmeWidgets.Heatmap,
      AcmeWidgets.Sparkbar,
      AcmeWidgets.Timeline
    ]

  @doc "Render a heatmap grid."
  def heatmap(opts \\ []),  do: {AcmeWidgets.Heatmap,  Map.new(opts)}

  @doc "Render an inline sparkbar chart."
  def sparkbar(opts \\ []), do: {AcmeWidgets.Sparkbar, Map.new(opts)}

  @doc "Render a horizontal timeline."
  def timeline(opts \\ []), do: {AcmeWidgets.Timeline, Map.new(opts)}
end
```

`use Drafter.WidgetLibrary` generates two functions on your module:

- `__widget_library__/0` — returns the widget module list
- `register/0` — makes all widgets available to the framework

Users never need to call these directly; Drafter calls them automatically.

### `mix.exs` for a library

```elixir
def project do
  [
    app: :acme_widgets,
    version: "0.1.0",
    deps: [{:drafter, "~> 0.2"}]
  ]
end
```

No additional application configuration is required.

---

## Using a widget library

### Registering widgets

Pass the library (or individual widget modules) to `Drafter.run/2`:

```elixir
# Register all widgets from a library
Drafter.run(MyApp, widget_libraries: [AcmeWidgets])

# Cherry-pick individual widget modules
Drafter.run(MyApp, widget_libraries: [AcmeWidgets.Heatmap, AcmeWidgets.Sparkbar])

# Mix widgets from multiple libraries
Drafter.run(MyApp, widget_libraries: [AcmeWidgets, OtherLib.Canvas])
```

Both full library modules and individual widget modules are accepted in the
same list. Drafter inspects each entry and registers accordingly.

### Importing constructor functions

Import the library module inside your app to bring the constructor functions
into scope for `render/1`:

```elixir
defmodule MyApp do
  use Drafter.App
  import AcmeWidgets

  def render(state) do
    vertical([
      heatmap(data: state.matrix, height: 10),
      sparkbar(values: state.series, color: {100, 255, 150})
    ])
  end
end

Drafter.run(MyApp, widget_libraries: [AcmeWidgets])
```

When cherry-picking, import only the modules you want:

```elixir
defmodule MyApp do
  use Drafter.App
  import AcmeWidgets.Heatmap

  def render(state) do
    vertical([heatmap(data: state.matrix)])
  end
end

Drafter.run(MyApp, widget_libraries: [AcmeWidgets.Heatmap])
```

> Individual widget modules expose their constructor function through their
> own `import`-friendly module. Name the function to match
> `component_tag/0` so it is discoverable.

### Widgets inside a running app (gallery / sub-session)

When pushing a sub-session with `Drafter.run/2` from inside a running app
(e.g. an example gallery), pass `:widget_libraries` in the same call:

```elixir
def handle_event(:open_acme_demo, _data, state) do
  Task.start(fn ->
    Drafter.run(AcmeDemo, widget_libraries: [AcmeWidgets])
  end)
  {:ok, state}
end
```

Drafter registers the libraries before pushing the new session, so no
additional setup is needed.
