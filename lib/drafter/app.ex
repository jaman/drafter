defmodule Drafter.App do
  @moduledoc """
  Simplified declarative API for building TUI applications.

  This module provides a Phoenix LiveView-inspired API for creating TUI apps
  with automatic theme management, layout, and event handling.
  """

  alias Drafter.{Event, Widget}

  @type props :: map()
  @type state :: term()
  @type rect :: Widget.rect()

  @doc "Initialize application with props"
  @callback mount(props()) :: state()

  @doc "Render application to component tree"
  @callback render(state()) :: term()

  @doc "Handle events (3-arity version for new API)"
  @callback handle_event(event_name :: atom(), data :: term(), state()) ::
              {:ok, state()} | {:error, term()} | {:noreply, state()} | {:stop, term()}

  @doc "Handle events (2-arity version for old API)"
  @callback handle_event(Event.t(), state()) ::
              {:ok, state()} | {:error, term()} | {:noreply, state()} | {:stop, term()}

  @doc "Update application with new props"
  @callback update(props(), state()) :: state()

  @doc "Called when app is ready and mounted"
  @callback on_ready(state()) :: state()

  @doc "Called on timer intervals"
  @callback on_timer(atom(), state()) :: state()

  @doc "Handle arbitrary process messages (PubSub, GenServer casts, etc.)"
  @callback on_message(msg :: term(), state()) :: state()

  @doc "Called on the first scroll event of a scroll gesture"
  @callback on_scroll_active(state()) :: state()

  @doc "Called when scrolling is idle (debounce settled)"
  @callback on_scroll_idle(state()) :: state()

  @doc "Cleanup application resources"
  @callback unmount(state()) :: :ok

  @callback refresh_rate() :: pos_integer() | String.t() | :unlimited

  @optional_callbacks [
    update: 2,
    unmount: 1,
    on_ready: 1,
    on_timer: 2,
    handle_event: 3,
    on_scroll_active: 1,
    on_scroll_idle: 1,
    on_message: 2,
    refresh_rate: 0
  ]

  defmacro __using__(opts) do
    quote do
      @behaviour Drafter.App
      import Drafter.App
      @before_compile Drafter.App

      @css_path Keyword.get(unquote(opts), :css_path)
      @inline_styles Keyword.get(unquote(opts), :styles, %{})
      @mouse_hover Keyword.get(unquote(opts), :mouse_hover, true)
      @keybinding_hints []

      def mount(_props), do: %{}
      def render(_state), do: []
      def handle_event(_event, state), do: {:noreply, state}
      def update(_props, state), do: state
      def on_ready(state), do: state
      def on_timer(_timer_id, state), do: state
      def unmount(_state), do: :ok
      def keybindings, do: []
      defoverridable keybindings: 0

      def __css_path__, do: @css_path
      def __inline_styles__, do: @inline_styles
      def __mouse_hover__, do: @mouse_hover
      def __theme__(action) when action == :get, do: Drafter.ThemeManager.get_current_theme()

      defoverridable mount: 1,
                     render: 1,
                     handle_event: 2,
                     update: 2,
                     on_ready: 1,
                     on_timer: 2,
                     unmount: 1
    end
  end

  defmacro __before_compile__(env) do
    hints = Module.get_attribute(env.module, :keybinding_hints)
    if hints != [] do
      quote do
        def keybindings, do: Enum.reverse(@keybinding_hints)
      end
    end
  end

  defmacro keybinding(key_spec, hint, do: body) do
    pattern = build_key_pattern(key_spec)
    display = build_key_hint(key_spec)
    quote do
      @keybinding_hints [{unquote(display), unquote(hint)} | @keybinding_hints]
      def handle_event(unquote(pattern), var!(_state)) do
        unquote(body)
      end
    end
  end

  defp build_key_pattern({key, mods}) when is_list(mods) do
    quote do: {:key, unquote(key), unquote(mods)}
  end

  defp build_key_pattern(key) when is_atom(key) do
    quote do: {:key, unquote(key)}
  end

  defp build_key_hint({key, mods}) when is_list(mods) do
    mod_prefix = Enum.map_join(mods, "+", &mod_label/1)
    "#{mod_prefix}+#{key_label(key)}"
  end

  defp build_key_hint(key) when is_atom(key), do: key_label(key)

  defp mod_label(:ctrl), do: "Ctrl"
  defp mod_label(:shift), do: "Shift"
  defp mod_label(:alt), do: "Alt"
  defp mod_label(m), do: to_string(m)

  defp key_label(:escape), do: "Esc"
  defp key_label(:enter), do: "Enter"
  defp key_label(:tab), do: "Tab"
  defp key_label(:space), do: "Space"
  defp key_label(:up), do: "↑"
  defp key_label(:down), do: "↓"
  defp key_label(:left), do: "←"
  defp key_label(:right), do: "→"
  defp key_label(k), do: k |> to_string() |> String.upcase()

  def label(text, opts \\ []) do
    {:label, text, opts}
  end

  def button(text, opts \\ []) do
    {:button, text, opts}
  end

  def checkbox(label, opts \\ []) do
    {:checkbox, label, opts}
  end

  def text_input(opts \\ []) do
    {:text_input, opts}
  end

  def text_area(opts \\ []) do
    {:text_area, opts}
  end

  def data_table(opts \\ []) do
    {:data_table, opts}
  end

  def tree(opts \\ []) do
    {:tree, opts}
  end

  def progress_bar(opts \\ []) do
    {:progress_bar, opts}
  end

  def gauge(opts \\ []) do
    {:gauge, opts}
  end

  def switch(opts \\ []) do
    {:switch, opts}
  end

  def switch(value, opts) when is_list(opts) do
    {:switch, Keyword.put(opts, :value, value)}
  end

  def switch_group(group_name, switches) when is_list(switches) do
    {left_col, right_col} = Enum.split(switches, div(length(switches) + 1, 2))

    left_switches =
      Enum.map(left_col, fn opts ->
        label = Keyword.get(opts, :label)
        value = Keyword.get(opts, :value, label)

        switch(
          Keyword.merge(opts,
            label: label,
            on_change: {:switch_group_changed, group_name, value}
          )
        )
      end)

    right_switches =
      Enum.map(right_col, fn opts ->
        label = Keyword.get(opts, :label)
        value = Keyword.get(opts, :value, label)

        switch(
          Keyword.merge(opts,
            label: label,
            on_change: {:switch_group_changed, group_name, value}
          )
        )
      end)

    horizontal(
      [
        vertical(left_switches, width: 30),
        vertical(right_switches, width: 30)
      ],
      gap: 2
    )
  end

  def theme_selector(opts \\ []) do
    {:theme_selector, opts}
  end

  def option_list(items, opts \\ []) do
    {:option_list, items, opts}
  end

  def horizontal(children, opts \\ []) do
    opts = Keyword.put(opts, :layout, :horizontal)
    container(children, opts)
  end

  def sidebar(left_children, right_children, opts \\ []) do
    sidebar_width = Keyword.get(opts, :sidebar_width, 20)

    horizontal(
      [
        vertical(left_children, width: sidebar_width),
        vertical(right_children, flex: 1)
      ],
      opts
    )
  end

  def container(children, opts \\ []) do
    layout = Keyword.get(opts, :layout, :vertical)
    {:layout, layout, children, opts}
  end

  def vertical(children, opts \\ []) do
    {:layout, :vertical, children, opts}
  end

  def box(children, opts \\ []) do
    {:box, children, opts}
  end

  def card(children, opts \\ []) do
    {:card, children, opts}
  end

  def digits(value, opts \\ []) do
    {:digits, value, opts}
  end

  def markdown(content, opts \\ []) do
    {:markdown, content, opts}
  end

  def rule(opts \\ []) do
    {:rule, opts}
  end

  def placeholder(opts \\ []) do
    {:placeholder, opts}
  end

  def static(content, opts \\ []) do
    {:static, content, opts}
  end

  def loading_indicator(opts \\ []) do
    {:loading_indicator, opts}
  end

  def sparkline(data, opts \\ []) do
    {:sparkline, data, opts}
  end

  def chart(data, opts \\ []) do
    {:chart, data, opts}
  end

  def link(text, opts \\ [])

  def link(text, url) when is_binary(url) do
    {:link, text, [url: url]}
  end

  def link(text, opts) when is_list(opts) do
    {:link, text, opts}
  end

  def masked_input(opts) when is_list(opts) do
    {:masked_input, opts}
  end

  def log(opts \\ []) do
    {:log, opts}
  end

  def rich_log(opts \\ []) do
    {:rich_log, opts}
  end

  def pretty(data, opts \\ []) do
    {:pretty, data, opts}
  end

  def directory_tree(opts \\ []) do
    {:directory_tree, opts}
  end

  def radio_set(options, opts \\ []) do
    {:radio_set, options, opts}
  end

  def selection_list(options, opts \\ []) do
    {:selection_list, options, opts}
  end

  def collapsible(title, content, opts \\ []) do
    {:collapsible, title, content, opts}
  end

  def tabbed_content(tabs, opts \\ []) do
    {:tabbed_content, tabs, opts}
  end

  def header(title, opts \\ []) do
    {:header, title, opts}
  end

  def footer(opts \\ []) do
    {:footer, opts}
  end

  def scrollable(children, opts \\ []) do
    {:scrollable, children, opts}
  end

  def split_pane(children, opts \\ []) do
    {:split_pane, children, opts}
  end

  def code_view(opts \\ []) when is_list(opts) do
    {:code_view, opts}
  end

  def code_view(content, opts) when is_binary(content) and is_list(opts) do
    {:code_view, [source: content] ++ opts}
  end

  def push_screen(screen_module, props \\ %{}, opts \\ []) do
    {:push_screen, screen_module, props, opts}
  end

  def pop_screen(result \\ nil) do
    {:pop, result}
  end

  def replace_screen(screen_module, props \\ %{}, _opts \\ []) do
    {:replace, screen_module, props}
  end

  def show_modal(screen_module, props \\ %{}, opts \\ []) do
    {:show_modal, screen_module, props, opts}
  end

  def show_popover(screen_module, props \\ %{}, opts \\ []) do
    opts = Keyword.put(opts, :type, :popover)
    {:push_screen, screen_module, props, opts}
  end

  def show_panel(screen_module, props \\ %{}, opts \\ []) do
    opts = Keyword.put(opts, :type, :panel)
    {:push_screen, screen_module, props, opts}
  end

  def show_toast(message, opts \\ []) do
    {:show_toast, message, opts}
  end

  def dismiss_modal do
    {:pop, :dismissed}
  end

  def screen_layout(parts) when is_list(parts) do
    header = parts[:header]
    footer = parts[:footer]
    content = parts[:content]

    []
    |> maybe_prepend_header(header)
    |> append_content(content, footer)
    |> maybe_append_footer(footer)
    |> vertical()
  end

  defp maybe_prepend_header(parts, nil), do: parts
  defp maybe_prepend_header(parts, header), do: parts ++ [header]

  defp append_content(parts, nil, _footer), do: parts

  defp append_content(parts, content, footer) when not is_nil(footer) do
    parts ++ [vertical(content, flex: 1)]
  end

  defp append_content(parts, content, _footer) when is_list(content) do
    parts ++ content
  end

  defp append_content(parts, content, _footer) do
    parts ++ [content]
  end

  defp maybe_append_footer(parts, nil), do: parts
  defp maybe_append_footer(parts, footer), do: parts ++ [footer]
end
