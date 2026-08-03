# Drafter Examples

Examples are grouped by the API style they use:

- **`spark/`** — the flat, Phoenix-like surface: `use Drafter`, declarative `state`,
  unqualified widgets, and named callbacks via `handle_event/3`. The recommended style.
- **`reducer/`** — the Elm-style runtime: `use Drafter, runtime: :reducer`. Define a single
  `update/2` message handler returning new state (or `{:stop, reason}` to quit) — see
  `04_counter`, `02_ticker`, `03_form`, `05_settings` for the idiomatic style. Every other
  example here is the same app as in `internal/` run under the reducer runtime unchanged:
  the reducer **falls back to the callback API** when an app doesn't define `update/2`, so any
  app runs either way and `update/2` is adopted incrementally. (That's the point — there's no
  app the reducer runtime can't run.)
- **`internal/`** — the original `use Drafter.App` examples (the lower-level surface the
  flat DSL is built on). Kept for reference and full feature coverage.

Run any example with:

```bash
elixir examples/spark/04_counter.exs
elixir examples/reducer/04_counter.exs
```

Or browse them all in the gallery: `elixir run_examples.exs`.

## `internal/` index

| Example | Description |
|---------|-------------|
| `01_hello_world.exs` | Minimal app — a good starting point |
| `02_clock.exs` | Live clock using the Digits widget |
| `03_digits.exs` | Large ASCII art number display |
| `04_counter.exs` | Stateful counter with increment/decrement buttons |
| `05_calculator.exs` | Calculator with keyboard and mouse input |
| `06_collapsible.exs` | Expandable/collapsible sections |
| `07_todo.exs` | Todo list with text input and scrollable list |
| `08_animation.exs` | Color animation with static, pulse, and rainbow modes |
| `09_hsl_colors.exs` | HSL, RGB, and hex color format demo |
| `10_themes.exs` | Theme switcher using Switch widgets |
| `11_data_table.exs` | Sortable, scrollable DataTable with 100 rows |
| `12_key_inspector.exs` | Live view of all keyboard, mouse, and resize events — useful when building keybindings |
| `13_syntax_highlight.exs` | Tree-sitter syntax highlighting in code_view |
| `14_code_browser.exs` | File browser with syntax-highlighted code preview |
| `15_screens.exs` | Modal dialogs and toast notifications |
| `16_custom_actions.exs` | Custom action handlers via `Drafter.ActionHandler` — adds a new action type without touching the framework; also demonstrates native desktop notifications (macOS, Linux, Windows) |
| `17_charts.exs` | Line, bar, area, candlestick, and scatter charts with live simulation |
| `18_chart_perf.exs` | Chart rendering performance benchmark |
| `19_gauge.exs` | Gauge widget demo |
| `20_multi_series_charts.exs` | Multi-series line, clustered bar, stacked bar, and scatter charts |
| `21_theme_sandbox.exs` | Full widget gallery with live theme switching |
| `22_skin_sandbox.exs` | Character set / skin customization |
| `23_split_pane.exs` | Resizable split pane layout |
| `24_dashboard.exs` | Dashboard layout with multiple widgets |
| `25_file_picker.exs` | File picker dialog |
| `26_braille_area.exs` | Braille-dot area chart rendering |
| `ssh_chat.exs` | Shared multi-user chat app served over SSH |
| `widgets.exs` | Showcase of common widgets: buttons, text input, checkbox, switch, option list, progress bar |

## `spark/` extras

| Example | Description |
|---------|-------------|
| `32_slider.exs` | Sliders: bound values, integer steps, formatted readouts, a vertical mixer, and the text / braille / graphics renderers |
