defmodule Drafter.Widget.Footer do
  @moduledoc """
  Renders a single-row key-binding bar, typically anchored to the bottom of a screen.

  Bindings are `{key_label, description}` tuples displayed as styled `[key] action`
  pairs separated by a configurable separator string. When no `:bindings` list is
  provided the widget calls `keybindings/0` on the currently active screen module
  automatically.

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

  use Drafter.Widget

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed

  defstruct [
    :bindings,
    :style,
    :key_style,
    :separator,
    :app_module
  ]

  def mount(props) do
    bindings = Map.get(props, :bindings)

    %__MODULE__{
      bindings: bindings,
      style: Map.get(props, :style),
      key_style: Map.get(props, :key_style),
      separator: Map.get(props, :separator, " "),
      app_module: Map.get(props, :app_module)
    }
  end

  def render(state, rect) do
    bindings = resolve_bindings(state)

    computed_opts = if state.app_module, do: [app_module: state.app_module], else: []
    computed = Computed.for_widget(:footer, state, computed_opts)
    key_computed = Computed.for_part(:footer, state, :key, computed_opts)

    style = state.style || Computed.to_segment_style(computed)
    key_style = state.key_style || Computed.to_segment_style(key_computed)

    segments =
      bindings
      |> Enum.flat_map(fn {key, description} ->
        key_text = " #{key} "
        desc_text = " #{description}"
        sep_text = state.separator

        [
          Segment.new(key_text, key_style),
          Segment.new(desc_text, style),
          Segment.new(sep_text, style)
        ]
      end)

    segments =
      if length(segments) > 0 do
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

  def update(props, state) do
    bindings = case Map.fetch(props, :bindings) do
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

  def handle_event(_event, state) do
    {:noreply, state}
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

  defp resolve_bindings(state) do
    cond do
      state.bindings != nil ->
        state.bindings

      true ->
        focused = Drafter.FocusRegistry.get()

        if focused != [] do
          focused
        else
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
    end
  end
end
