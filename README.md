# Drafter

An Elixir Terminal User Interface framework inspired by Python's Textual. Build rich, interactive terminal applications with a declarative API similar to Phoenix LiveView.

[![asciicast](https://asciinema.org/a/uSauYhLa8aW4fHPq.svg)](https://asciinema.org/a/uSauYhLa8aW4fHPq)

## Features

- **Declarative API** - Phoenix LiveView-inspired component model
- **Rich Widget Library** - 30+ widgets including DataTable, Tree, Charts, Inputs
- **Event-Driven Architecture** - Keyboard, mouse, and custom events
- **Flexible Layout System** - Vertical, horizontal, grid, and scrollable layouts
- **Multi-Screen Navigation** - Push/pop screens, modals, toasts, panels
- **Theming System** - Built-in themes with customization support
- **Animation Support** - Smooth property animations with easing functions
- **Remote TUI** - Serve apps over SSH or Telnet with isolated or shared sessions (see [Remote TUI](guides/remote_tui.md))
- **Minimal Dependencies** - Elixir implementation with NIF-based terminal I/O

## Requirements

- Elixir ~> 1.18
- Erlang/OTP 28 or later

Drafter relies on OTP 28's raw terminal mode (`-noshell` raw input), improved ANSI escape sequence handling, and lazy input reading. Earlier OTP versions will not handle keyboard input or screen updates correctly.

## Installation

Add `drafter` to your `mix.exs`:

```elixir
def deps do
  [
    {:drafter, "~> 0.1"}
  ]
end
```

## Quick Start

```elixir
defmodule MyApp do
  use Drafter.App

  def mount(_props) do
    %{counter: 0}
  end

  def render(state) do
    vertical([
      header("My App"),
      label("Counter: #{state.counter}"),
      horizontal([
        button("Decrement", on_click: :decrement),
        button("Increment", on_click: :increment)
      ], gap: 2),
      footer(bindings: [{"q", "Quit"}])
    ])
  end

  def handle_event(:increment, _data, state) do
    {:ok, %{state | counter: state.counter + 1}}
  end

  def handle_event(:decrement, _data, state) do
    {:ok, %{state | counter: state.counter - 1}}
  end

  def handle_event({:key, :q}, _state), do: {:stop, :normal}
  def handle_event({:key, :c, [:ctrl]}, _state), do: {:stop, :normal}
  def handle_event(_event, state), do: {:noreply, state}
end
```

Run your app:

```bash
mix run -e "Drafter.run(MyApp)"
```

## Core Concepts

### Application Structure

Every TUI application implements the `Drafter.App` behaviour:

```elixir
defmodule MyApp do
  use Drafter.App

  @callback mount(props :: map()) :: state :: map()
  @callback render(state :: map()) :: component_tree :: tuple()
  @callback handle_event(event :: term(), state :: map()) :: result :: term()
  @callback on_ready(state :: map()) :: state :: map()
  @callback on_timer(timer_id :: atom(), state :: map()) :: state :: map()
end
```

### Widget Types

#### Display Widgets
- `label(text, opts)` - Text display
- `markdown(content, opts)` - Markdown rendering
- `digits(value, opts)` - Large ASCII art numbers
- `sparkline(data, opts)` - Mini inline charts
- `chart(data, opts)` - Full charts (line, bar, pie)
- `progress_bar(opts)` - Progress indication
- `loading_indicator(opts)` - Animated spinner
- `rule(opts)` - Horizontal/vertical dividers

#### Input Widgets
- `button(text, opts)` - Clickable button
- `text_input(opts)` - Single-line text input
- `text_area(opts)` - Multi-line text editor
- `checkbox(label, opts)` - Boolean toggle
- `switch(opts)` - On/off switch
- `radio_set(options, opts)` - Mutually exclusive options
- `selection_list(options, opts)` - Multi-select list
- `option_list(items, opts)` - Single-select list
- `masked_input(opts)` - Formatted input (phone, date, etc.)

#### Data Widgets
- `data_table(opts)` - Full-featured table with sorting, selection
- `tree(opts)` - Hierarchical data display
- `directory_tree(opts)` - File system browser

#### Layout Widgets
- `vertical(children, opts)` - Vertical stack
- `horizontal(children, opts)` - Horizontal row
- `container(children, opts)` - Generic container
- `scrollable(children, opts)` - Scrollable area
- `grid(children, opts)` - CSS Grid-like layout
- `sidebar(left, right, opts)` - Two-column layout

#### Container Widgets
- `card(children, opts)` - Bordered card
- `box(children, opts)` - Simple box
- `collapsible(title, content, opts)` - Expandable section
- `tabbed_content(tabs, opts)` - Tab navigation
- `header(title, opts)` - App header
- `footer(opts)` - App footer with keybindings

### Event Handling

Events are handled in the `handle_event/2` callback:

```elixir
def handle_event(:button_clicked, _data, state) do
  {:ok, %{state | clicked: true}}
end

def handle_event({:key, :enter}, state) do
  {:ok, state}
end

def handle_event({:key, :q}, _state) do
  {:stop, :normal}
end

def handle_event({:key, :c, [:ctrl]}, _state) do
  {:stop, :normal}
end
```

#### Event Return Values

- `{:ok, new_state}` - Update state and re-render
- `{:noreply, state}` - No re-render needed
- `{:stop, reason}` - Exit the application
- `{:show_modal, module, props, opts}` - Display a modal
- `{:show_toast, message, opts}` - Show a toast notification
- `{:push, module, props, opts}` - Push a new screen
- `{:pop, result}` - Pop current screen

### Custom Action Handlers

By default, return values from `handle_event/3` are handled by Drafter's built-in
dispatcher. You can extend this system without modifying any framework code by
implementing the `Drafter.ActionHandler` behaviour.

This is the right approach for third-party widgets or plugins that introduce new
action shapes — no changes to the base library required.

**1. Implement the behaviour:**

```elixir
defmodule MyApp.DrawerHandler do
  @behaviour Drafter.ActionHandler

  @impl true
  def handle_action({:open_drawer, id}, acc_state) do
    {:ok, %{acc_state | open_drawer: id}}
  end

  def handle_action({:close_drawer}, acc_state) do
    {:ok, %{acc_state | open_drawer: nil}}
  end

  def handle_action(_action, _acc_state), do: :unhandled
end
```

**2. Register before `Drafter.run/2`:**

```elixir
Drafter.ActionRegistry.register(MyApp.DrawerHandler)
Drafter.run(MyApp)
```

**3. Return custom actions from any event handler:**

```elixir
def handle_event(:open_settings, _data, state) do
  {:open_drawer, :settings}
end
```

Handlers are checked in registration order. Returning `{:ok, new_state}` stops
dispatch; returning `:unhandled` passes control to the next handler. The built-in
handler runs last and covers all standard return values.

See `examples/16_custom_actions.exs` for a complete working example that demonstrates
custom action types, state mutation, and native desktop notifications.

### Screens and Navigation

Create multi-screen applications with modals and toasts:

```elixir
defmodule MainScreen do
  use Drafter.Screen

  def mount(_props), do: %{items: []}

  def render(state) do
    vertical([
      label("Main Screen"),
      button("Open Modal", on_click: :open_modal),
      button("Show Toast", on_click: :show_toast)
    ])
  end

  def handle_event(:open_modal, _state) do
    {:show_modal, MyModal, %{title: "Info"}, [width: 50, height: 15]}
  end

  def handle_event(:show_toast, _state) do
    {:show_toast, "Hello!", [variant: :success]}
  end
end

defmodule MyModal do
  use Drafter.Screen

  def mount(props), do: %{title: props.title}

  def render(state) do
    vertical([
      label(state.title),
      button("Close", on_click: :close)
    ])
  end

  def handle_event(:close, _state), do: {:pop, :closed}
  def handle_event({:key, :escape}, _state), do: {:pop, :dismissed}
end
```

### Screen Types

- **Default** - Full-screen content
- **Modal** - Centered dialog with overlay
- **Popover** - Anchored popup
- **Panel** - Side panel
- **Toast** - Auto-dismissing notification

### Toast Variants

```elixir
{:show_toast, "Info message", [variant: :info]}
{:show_toast, "Success!", [variant: :success]}
{:show_toast, "Warning!", [variant: :warning]}
{:show_toast, "Error!", [variant: :error]}
```

Toast positions: `:top_left`, `:top_center`, `:top_right`, `:middle_left`, `:middle_center`, `:middle_right`, `:bottom_left`, `:bottom_center`, `:bottom_right`

### Widget State Binding

Bind widget values directly to app state:

```elixir
def mount(_props) do
  %{username: "", remember: false}
end

def render(state) do
  vertical([
    text_input(placeholder: "Username", bind: :username),
    checkbox("Remember me", bind: :remember),
    button("Submit", on_click: :submit)
  ])
end

def handle_event(:submit, _data, state) do
  IO.puts("Username: #{state.username}")
  {:ok, state}
end
```

### Accessing Widget State

```elixir
Drafter.get_widget_value(:my_input)
Drafter.get_widget_state(:my_checkbox)
Drafter.query_one("#submit")
Drafter.query_all("Button")
```

### Timers

```elixir
def on_ready(state) do
  Drafter.set_interval(1000, :tick)
  state
end

def on_timer(:tick, state) do
  %{state | seconds: state.seconds + 1}
end
```

### Animations

```elixir
Drafter.animate(:my_widget, :opacity, 0.5, duration: 500, easing: :ease_out)
Drafter.animate(:my_label, :background, {255, 0, 0}, duration: 1000)
```

Available easing functions: `:linear`, `:ease`, `:ease_in`, `:ease_out`, `:ease_in_out`, `:ease_in_quad`, `:ease_out_quad`, `:ease_in_cubic`, `:ease_out_cubic`, `:ease_in_elastic`, `:ease_out_elastic`, `:ease_in_bounce`, `:ease_out_bounce`

## Complete Example

```elixir
Mix.install([{:drafter, "~> 0.1"}, {:elixir_make, "~> 0.9"}])
defmodule TodoApp do
  use Drafter.App

  def mount(_props) do
    %{
      todos: ["Learn Drafter", "Build awesome CLI apps"],
      new_todo: ""
    }
  end

  def render(state) do
    todo_items =
      Enum.map(state.todos, fn todo ->
        label("  • #{todo}")
      end)

    vertical([
      header("Todo App"),
      scrollable(todo_items, flex: 1),
      horizontal(
        [
          text_input(
            id: :new_todo_input,
            placeholder: "Add todo...",
            bind: :new_todo,
            on_submit: :add_todo,
            keep_focus: true,
            flex: 1
          ),
          button("Add", on_click: :add_todo)
        ],
        gap: 1
      ),
      footer(bindings: [{"q", "Quit"}, {"Enter", "Add"}])
    ])
  end

  def handle_event(:add_todo, _data, state) do
    if String.trim(state.new_todo) != "" do
      {:ok, %{state | todos: state.todos ++ [state.new_todo], new_todo: ""}}
    else
      {:noreply, state}
    end
  end

  def handle_event({:key, :q}, _state), do: {:stop, :normal}
  def handle_event(_event, state), do: {:noreply, state}
end

Drafter.run(TodoApp)
```

## Syntax Highlighting

Drafter supports syntax highlighting via the [`tree-sitter`](https://tree-sitter.github.io/tree-sitter/) CLI. This is entirely optional — if you don't need it, no setup is required.

### If you already have tree-sitter installed

Nothing to do. Pass `syntax_highlighting: true` when starting your app:

```elixir
Drafter.run(MyApp, syntax_highlighting: true)
```

Then use `code_view` with a file path:

```elixir
code_view(path: "/path/to/file.rs", show_line_numbers: true, flex: 1)
```

Language is detected automatically from the file extension. Highlighting quality depends on which grammars you have installed in your tree-sitter environment.

### If you don't have tree-sitter

Skip `syntax_highlighting: true` (or don't pass it). The `code_view` widget will still work — Elixir files get built-in highlighting, all other files render as plain text.

### Installing tree-sitter

```bash
# macOS
brew install tree-sitter

# Or via npm
npm install -g tree-sitter-cli
```

After installing, set up grammars for the languages you want to highlight by following the [tree-sitter getting started guide](https://tree-sitter.github.io/tree-sitter/). The more grammars you have installed, the more languages `code_view` will highlight.

### Supported in code_view

```elixir
code_view(
  path: state.selected_file,   # preferred — tree-sitter reads the file directly
  show_line_numbers: true,
  flex: 1
)

code_view(
  source: some_string,         # also works — uses a temp file under the hood
  language: :python,
  flex: 1
)
```

When `path:` is given, tree-sitter reads the file directly (one system call, no temp file). When only `source:` is given, a temp file is created, highlighted, then deleted.

## Running Examples

Standalone scripts in the `examples/` directory can be run directly with `elixir`:

```bash
elixir examples/01_hello_world.exs
elixir examples/02_clock.exs
elixir examples/03_digits.exs
elixir examples/04_counter.exs
elixir examples/05_calculator.exs
elixir examples/06_collapsible.exs
elixir examples/07_todo.exs
elixir examples/08_animation.exs
elixir examples/09_hsl_colors.exs
elixir examples/10_themes.exs
elixir examples/11_data_table.exs
elixir examples/12_key_inspector.exs
elixir examples/13_syntax_highlight.exs
elixir examples/14_code_browser.exs
elixir examples/15_screens.exs
elixir examples/16_custom_actions.exs
elixir examples/17_charts.exs
elixir examples/18_chart_perf.exs
elixir examples/19_gauge.exs
elixir examples/20_multi_series_charts.exs
elixir examples/21_theme_sandbox.exs
elixir examples/22_skin_sandbox.exs
elixir examples/23_split_pane.exs
elixir examples/24_dashboard.exs
elixir examples/25_file_picker.exs
elixir examples/26_braille_area.exs
```

Examples that are compiled into the library can be run via `mix run`:

```bash
mix run -e "Drafter.run(Drafter.Examples.ScreenDemo)"
mix run -e "Drafter.run(Drafter.Examples.DeclarativeSandbox)"
mix run -e "Drafter.run(Drafter.Examples.ThemeSandbox)"
mix run -e "Drafter.run(Drafter.Examples.ChartDemo)"
```

## Keyboard Shortcuts

- `Ctrl+C` or `Ctrl+Q` - Quit application
- `Tab` - Next focusable widget
- `Shift+Tab` - Previous focusable widget
- Arrow keys - Navigate within widgets
- `Enter` - Activate/confirm
- `Escape` - Dismiss modals

## License

MIT
