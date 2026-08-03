defmodule Drafter.WidgetValue do
  @moduledoc """
  Reads and writes a widget's primary value by the shape of its state.

  There is no per-widget-type table: `extract/1` tries the shapes below in order and
  takes the first one the state satisfies, and `update_props/2` maps a new value back
  onto the props that set it. `Drafter.get_widget_value/1`,
  `Drafter.set_widget_value/2` and the app loop's own value lookup all come through
  here, so every path answers alike.

  Recognised shapes, in order:

    * `:text` — that string. `text_input`, `text_area`, `label`, `button`, `link`,
      `loading_indicator`, `digits`, `placeholder`.
    * `:checked` — a boolean. `checkbox`.
    * `:state` holding `:on` or `:off` — `true` for `:on`. `switch`.
    * `:selected_index` with `:options` — the id of the option at that index.
      `radio_set`, `option_list`.
    * `:selected_indices` with `:options` — the ids of those options. `selection_list`.
    * `:expanded` — a boolean. `collapsible`.
    * `:active_tab` — the active tab index. `tabbed_content`.
    * `:selected_rows` — that `MapSet` as a list. `data_table`.
    * `:selected_nodes` — that `MapSet` as a list. `tree`.
    * `:value` with `:min`, `:max` and `:step` — that number. `slider`.

  Anything else reads as `nil`.
  """

  @doc """
  The primary value held in `state`, or `nil` when no shape matches and for `nil`.

      iex> Drafter.WidgetValue.extract(%{text: "hello"})
      "hello"

      iex> Drafter.WidgetValue.extract(%{state: :on})
      true

      iex> Drafter.WidgetValue.extract(%{value: 0.5, min: 0.0, max: 1.0, step: nil})
      0.5

      iex> Drafter.WidgetValue.extract(%{selected_index: 1, options: [%{id: :a}, %{id: :b}]})
      :b

      iex> Drafter.WidgetValue.extract(nil)
      nil
  """
  @spec extract(map() | struct() | nil) :: term() | nil
  def extract(nil), do: nil
  def extract(%{text: text}), do: text
  def extract(%{checked: checked}), do: checked
  def extract(%{state: on_or_off}) when on_or_off in [:on, :off], do: on_or_off == :on
  def extract(%{selected_index: index, options: options}), do: option_id_at(options, index)

  def extract(%{selected_indices: indices, options: options}) do
    indices
    |> MapSet.to_list()
    |> Enum.map(&option_id_at(options, &1))
    |> Enum.reject(&is_nil/1)
  end

  def extract(%{expanded: expanded}), do: expanded
  def extract(%{active_tab: tab}), do: tab
  def extract(%{selected_rows: rows}), do: MapSet.to_list(rows)
  def extract(%{selected_nodes: nodes}), do: MapSet.to_list(nodes)
  def extract(%{value: value, min: _min, max: _max, step: _step}), do: value
  def extract(_state), do: nil

  @doc """
  The props that write `value` into `state`, or `nil` when it cannot be written.

  Only three of the shapes `extract/1` reads are writable, and the value must match
  the field's type.

      iex> Drafter.WidgetValue.update_props(%{text: "old"}, "new")
      %{text: "new"}

      iex> Drafter.WidgetValue.update_props(%{value: 0.5, min: 0.0, max: 1.0, step: nil}, 0.9)
      %{value: 0.9}

      iex> Drafter.WidgetValue.update_props(%{checked: false}, "yes")
      nil
  """
  @spec update_props(map() | struct() | nil, term()) :: map() | nil
  def update_props(nil, _value), do: nil
  def update_props(%{text: _}, value) when is_binary(value), do: %{text: value}
  def update_props(%{checked: _}, value) when is_boolean(value), do: %{checked: value}

  def update_props(%{value: _, min: _, max: _, step: _}, value) when is_number(value),
    do: %{value: value}

  def update_props(_state, _value), do: nil

  defp option_id_at(options, index) do
    case Enum.at(options, index) do
      %{id: id} -> id
      _option -> nil
    end
  end
end
