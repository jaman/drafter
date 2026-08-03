defmodule Drafter.Widget.Footer do
  @moduledoc """
  Renders a single-row key-binding bar, typically anchored to the bottom of a screen.

  Bindings are `{key_label, description}` tuples displayed as styled `[key] action`
  pairs separated by a configurable separator string. When no `:bindings` list is
  provided the widget calls `keybindings/0` on the currently active screen module
  automatically.

  Each binding is clickable: hovering highlights the binding, and clicking dispatches
  the associated key event as if the user pressed that key.

  ## Component tag

  Tag `:footer`, built by `Drafter.App` as `{:footer, opts}`:

      footer(opts)

  There is no positional argument; every prop comes from `opts`. `:app_module`
  is supplied by the renderer.

  ## Options

    * `:bindings` - list of `{key, description}` tuples. Default `nil`, in which
      case the widget calls `keybindings/0` on the active screen module, falling
      back to `:app_module`, and then to `[]` when neither exports it
    * `:separator` - `t:String.t/0` placed between binding pairs. Default `" "`
    * `:style` - style map applied to description text. Default `nil`, which uses
      the computed `:footer` theme style
    * `:key_style` - style map applied to key label text. Default `nil`, which uses
      the computed `:footer` `:key` part style
    * `:app_module` - module used for theme resolution and as the fallback source of
      `keybindings/0`, passed by the renderer as `:__app_module__`. Default `nil`

  `update/2` re-reads every option, and passing `bindings: nil` explicitly restores
  the "ask the active screen" behaviour. All of them are live-updatable through the
  component tree.

  ## Widget value

  `Drafter.get_widget_value/1` is not implemented for this widget and returns `nil`.

  ## Events

  The footer is not focusable and handles no keys. A hover moves the highlight to
  the binding under the pointer, and a mouse release on a binding sends the
  corresponding key event through `Drafter.Event.Manager`. A label of one byte
  becomes a `{:char, codepoint}` event, a label in the built-in table becomes its
  `{:key, atom}` event, a label with `+` becomes `{:key, key, modifiers}`, and any
  other label is downcased and converted to an atom.

  ## Usage

      footer(bindings: [{"q", "Quit"}, {"Tab", "Focus next"}, {"Enter", "Select"}])
      footer()
  """

  use Drafter.Widget,
    handles: [:hover, :mouse_up]

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Event
  alias Drafter.Style.Computed

  defstruct [
    :bindings,
    :style,
    :key_style,
    :separator,
    :app_module,
    :hovered_index
  ]

  @type binding :: {String.t(), String.t()}

  @type t :: %__MODULE__{
          bindings: [binding()] | nil,
          style: map() | nil,
          key_style: map() | nil,
          separator: String.t(),
          app_module: module() | nil,
          hovered_index: non_neg_integer() | nil
        }

  @doc """
  Builds the footer state from `props`. `:hovered_index` always starts at `nil`.

      iex> f = Drafter.Widget.Footer.mount(%{bindings: [{"q", "Quit"}]})
      iex> {f.bindings, f.separator, f.style, f.key_style, f.hovered_index}
      {[{"q", "Quit"}], " ", nil, nil, nil}
  """
  @spec mount(Drafter.Widget.props()) :: t()
  @impl Drafter.Widget
  def mount(props) do
    %__MODULE__{
      bindings: Map.get(props, :bindings),
      style: Map.get(props, :style),
      key_style: Map.get(props, :key_style),
      separator: Map.get(props, :separator, " "),
      app_module: Map.get(props, :app_module),
      hovered_index: nil
    }
  end

  @doc """
  Draws the binding bar as a single strip padded or cropped to `rect.width`.

  Each binding takes `" key "` followed by `" description"`, with `:separator`
  between pairs and none after the last. The hovered binding is drawn with
  `reverse: true`. `rect.height` is not consulted.
  """
  @spec render(t(), Drafter.Widget.rect()) :: [Strip.t()]
  @impl Drafter.Widget
  def render(state, rect) do
    bindings = resolve_bindings(state)
    regions = binding_regions(bindings, state.separator)

    computed_opts = if state.app_module, do: [app_module: state.app_module], else: []
    computed = Computed.for_widget(:footer, state, computed_opts)
    key_computed = Computed.for_part(:footer, state, :key, computed_opts)

    style = state.style || Computed.to_segment_style(computed)
    key_style = state.key_style || Computed.to_segment_style(key_computed)

    hovered_style = Map.merge(style, %{reverse: true})
    hovered_key_style = Map.merge(key_style, %{reverse: true})

    segments =
      regions
      |> Enum.with_index()
      |> Enum.flat_map(fn {{key, description, _start, _end}, idx} ->
        key_text = " #{key} "
        desc_text = " #{description}"
        sep_text = state.separator

        {ks, ds} =
          if state.hovered_index == idx do
            {hovered_key_style, hovered_style}
          else
            {key_style, style}
          end

        [
          Segment.new(key_text, ks),
          Segment.new(desc_text, ds),
          Segment.new(sep_text, style)
        ]
      end)

    segments =
      if segments != [] do
        Enum.drop(segments, -1)
      else
        segments
      end

    strip = Strip.new(segments)
    strip_width = Strip.width(strip)

    final_strip =
      if strip_width < rect.width do
        padding = String.duplicate(" ", rect.width - strip_width)
        Strip.new(strip.segments ++ [Segment.new(padding, style)])
      else
        Strip.crop(strip, rect.width)
      end

    [final_strip]
  end

  @doc """
  Folds fresh props into `state`, re-reading `:bindings`, `:style`, `:key_style`,
  `:separator` and `:app_module`. `:hovered_index` is left alone.

  `:bindings` is taken whenever the key is present, so `bindings: nil` restores the
  active-screen lookup rather than being ignored.

      iex> f = Drafter.Widget.Footer.mount(%{bindings: [{"q", "Quit"}]})
      iex> Drafter.Widget.Footer.update(%{bindings: nil}, f).bindings
      nil
  """
  @spec update(Drafter.Widget.props(), t()) :: t()
  @impl Drafter.Widget
  def update(props, state) do
    bindings =
      case Map.fetch(props, :bindings) do
        {:ok, val} -> val
        :error -> state.bindings
      end

    %{
      state
      | bindings: bindings,
        style: Map.get(props, :style, state.style),
        key_style: Map.get(props, :key_style, state.key_style),
        separator: Map.get(props, :separator, state.separator),
        app_module: Map.get(props, :app_module, state.app_module)
    }
  end

  @doc """
  Moves the highlight to the binding spanning column `x`, counted from the left edge
  of the widget.

  Returns `{:ok, state}` with the new `:hovered_index`, which is `nil` when `x`
  falls on a separator or past the last binding, or `{:noreply, state}` when the
  index has not changed.
  """
  @spec handle_hover(integer(), integer(), t()) :: {:ok, t()} | {:noreply, t()}
  @impl Drafter.Widget
  def handle_hover(x, _y, state) do
    bindings = resolve_bindings(state)
    regions = binding_regions(bindings, state.separator)
    idx = region_index_at(regions, x)

    if idx != state.hovered_index do
      {:ok, %{state | hovered_index: idx}}
    else
      {:noreply, state}
    end
  end

  @doc """
  Dispatches the key event for the binding under column `x`.

  On a hit the event is sent through `Drafter.Event.Manager.send_event/1`, exactly
  as if the key had been pressed, and `{:ok, state}` is returned. A release on a
  separator or past the last binding returns `{:noreply, state}`.
  """
  @spec handle_mouse_up(integer(), integer(), t()) :: {:ok, t()} | {:noreply, t()}
  @impl Drafter.Widget
  def handle_mouse_up(x, _y, state) do
    bindings = resolve_bindings(state)
    regions = binding_regions(bindings, state.separator)

    case region_index_at(regions, x) do
      nil ->
        {:noreply, state}

      idx ->
        {key_label, _desc, _s, _e} = Enum.at(regions, idx)
        event = key_label_to_event(key_label)
        Event.Manager.send_event(event)
        {:ok, state}
    end
  end

  @doc "Always `1`: the footer occupies a single row."
  @spec preferred_height(term(), keyword()) :: pos_integer()
  def preferred_height(_args, _opts), do: 1

  @doc """
  The registry tag for this widget.

      iex> Drafter.Widget.Footer.component_tag()
      :footer
  """
  @spec component_tag() :: :footer
  def component_tag, do: :footer

  @doc """
  Turns the `{:footer, opts}` element into a props map for `mount/1`.

  The positional argument is ignored. `:__app_module__` becomes `:app_module`.

      iex> Drafter.Widget.Footer.from_component_opts(nil, bindings: [{"q", "Quit"}])
      %{bindings: [{"q", "Quit"}], separator: " ", style: nil, key_style: nil, app_module: nil}
  """
  @spec from_component_opts(term(), keyword()) :: Drafter.Widget.props()
  def from_component_opts(_args, opts) do
    %{
      bindings: Keyword.get(opts, :bindings),
      separator: Keyword.get(opts, :separator, " "),
      style: Keyword.get(opts, :style),
      key_style: Keyword.get(opts, :key_style),
      app_module: Keyword.get(opts, :__app_module__)
    }
  end

  @doc """
  Returns `mount_props` unchanged, so a re-render passes every option through to
  `update/2`.
  """
  @spec update_props_from_mount(Drafter.Widget.props(), t(), keyword()) :: Drafter.Widget.props()
  def update_props_from_mount(mount_props, _existing_state, _opts), do: mount_props

  defp resolve_bindings(%{bindings: bindings}) when bindings != nil, do: bindings

  defp resolve_bindings(state), do: resolve_module_bindings(state)

  defp resolve_module_bindings(state) do
    active_module =
      case Drafter.ScreenManager.get_active_screen() do
        %{module: mod} when mod != nil -> mod
        _ -> state.app_module
      end

    if active_module && function_exported?(active_module, :keybindings, 0) do
      active_module.keybindings()
    else
      []
    end
  end

  defp binding_regions(bindings, separator) do
    {regions, _offset} =
      Enum.reduce(bindings, {[], 0}, fn {key, description}, {acc, offset} ->
        key_text = " #{key} "
        desc_text = " #{description}"
        region_width = String.length(key_text) + String.length(desc_text)
        region = {key, description, offset, offset + region_width - 1}
        sep_width = String.length(separator)
        {acc ++ [region], offset + region_width + sep_width}
      end)

    regions
  end

  defp region_index_at(regions, x) do
    Enum.find_index(regions, fn {_key, _desc, start_x, end_x} ->
      x >= start_x and x <= end_x
    end)
  end

  @key_label_map %{
    "Enter" => {:key, :enter},
    "Tab" => {:key, :tab},
    "Esc" => {:key, :escape},
    "Escape" => {:key, :escape},
    "Space" => {:key, :" "},
    "Backspace" => {:key, :backspace},
    "Delete" => {:key, :delete},
    "Up" => {:key, :up},
    "Down" => {:key, :down},
    "Left" => {:key, :left},
    "Right" => {:key, :right},
    "Home" => {:key, :home},
    "End" => {:key, :end},
    "PageUp" => {:key, :page_up},
    "PageDown" => {:key, :page_down},
    "F1" => {:key, :f1},
    "F2" => {:key, :f2},
    "F3" => {:key, :f3},
    "F4" => {:key, :f4},
    "F5" => {:key, :f5},
    "F6" => {:key, :f6},
    "F7" => {:key, :f7},
    "F8" => {:key, :f8},
    "F9" => {:key, :f9},
    "F10" => {:key, :f10},
    "F11" => {:key, :f11},
    "F12" => {:key, :f12}
  }

  defp key_label_to_event(label) do
    case Map.fetch(@key_label_map, label) do
      {:ok, event} ->
        event

      :error ->
        parse_key_label(label)
    end
  end

  defp parse_key_label(label) do
    parts = String.split(label, "+")

    case parts do
      [single] when byte_size(single) == 1 ->
        {:char, :binary.first(single)}

      [single] ->
        {:key, String.to_atom(String.downcase(single))}

      modifiers_and_key ->
        {key_part, mod_parts} = List.pop_at(modifiers_and_key, -1)
        mods = Enum.map(mod_parts, &String.to_atom(String.downcase(&1)))
        key = String.to_atom(String.downcase(key_part))
        {:key, key, mods}
    end
  end
end
