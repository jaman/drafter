defmodule Drafter.Widget.Footer do
  @moduledoc """
  Renders a single-row key-binding bar, typically anchored to the bottom of a screen.

  Bindings are `{key_label, description}` tuples displayed as styled `[key] action`
  pairs separated by a configurable separator string. When no `:bindings` list is
  provided the widget calls `keybindings/0` on the currently active screen module
  automatically.

  Each binding is clickable: hovering highlights the binding, and clicking dispatches
  the associated key event as if the user pressed that key.

  ## Options

    * `:bindings` - list of `{key, description}` tuples; falls back to the active screen's `keybindings/0` when `nil`
    * `:separator` - string placed between binding pairs (default `" "`)
    * `:style` - style map applied to description text
    * `:key_style` - style map applied to key label text
    * `:app_module` - app module used for theme resolution

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

  def preferred_height(_args, _opts), do: 1

  def component_tag, do: :footer

  def from_component_opts(_args, opts) do
    %{
      bindings: Keyword.get(opts, :bindings),
      separator: Keyword.get(opts, :separator, " "),
      style: Keyword.get(opts, :style),
      key_style: Keyword.get(opts, :key_style),
      app_module: Keyword.get(opts, :__app_module__)
    }
  end

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
    "Space" => {:key, :space},
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
