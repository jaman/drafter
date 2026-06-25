Mix.install([{:drafter, path: Path.join(__DIR__, "../..")}, {:french_curve, github: "jaman/french_curve"}, {:elixir_make, "~> 0.9"}, {:spark, "~> 2.6"}])

defmodule Calculator do
  use Drafter, runtime: :reducer

  @key_mappings %{
    :+ => {:op, :+, :btn_plus},
    :- => {:op, :-, :btn_minus},
    :* => {:op, :*, :btn_multiply},
    :/ => {:op, :/, :btn_divide},
    := => {:equals, :btn_equals},
    :. => {:point, :btn_point},
    :% => {:percent, :btn_percent}
  }

  def mount(_props), do: %{value: 0, left: 0, op: nil, entering: false, decimal_places: nil}

  keybinding :q, "quit" do
    {:stop, :normal}
  end

  keybinding :enter, "=" do
    Drafter.activate_widget(:btn_equals)
    {:noreply, state}
  end

  keybinding :c, "clear" do
    Drafter.activate_widget(:btn_clear)
    {:noreply, state}
  end

  def render(state) do
    vertical(
      [
        digits(format(state.value, state.decimal_places), align: :right, size: :small, style: %{bg: {50, 50, 50}}),
        row([
          btn(if(state.entering, do: "C", else: "AC"), :clear, :primary, 1, :btn_clear),
          btn("+/-", :plus_minus, :primary, 1, :btn_plus_minus),
          btn("%", :percent, :primary, 1, :btn_percent),
          btn("÷", {:op, :/}, :warning, 1, :btn_divide)
        ]),
        row([
          btn("7", {:digit, 7}, :default, 1, :btn_7),
          btn("8", {:digit, 8}, :default, 1, :btn_8),
          btn("9", {:digit, 9}, :default, 1, :btn_9),
          btn("×", {:op, :*}, :warning, 1, :btn_multiply)
        ]),
        row([
          btn("4", {:digit, 4}, :default, 1, :btn_4),
          btn("5", {:digit, 5}, :default, 1, :btn_5),
          btn("6", {:digit, 6}, :default, 1, :btn_6),
          btn("-", {:op, :-}, :warning, 1, :btn_minus)
        ]),
        row([
          btn("1", {:digit, 1}, :default, 1, :btn_1),
          btn("2", {:digit, 2}, :default, 1, :btn_2),
          btn("3", {:digit, 3}, :default, 1, :btn_3),
          btn("+", {:op, :+}, :warning, 1, :btn_plus)
        ]),
        row([
          btn("0", {:digit, 0}, :default, 2, :btn_0),
          btn(".", :point, :default, 1, :btn_point),
          btn("=", :equals, :warning, 1, :btn_equals)
        ]),
        footer()
      ],
      gap: 1,
      padding: {1, 2}
    )
  end

  defp row(buttons), do: horizontal(buttons, height: 3, gap: 2)

  defp btn(label, action, type, colspan, id),
    do: button(label, id: id, on_click: action, type: type, colspan: colspan)

  def handle_event(event, _data, state), do: do_handle(event, state)
  def handle_event(event, state), do: do_handle(event, state)

  defp do_handle({:digit, d}, %{decimal_places: dp} = state) when is_integer(dp) do
    new_value = state.value + d / :math.pow(10, dp + 1)
    {:ok, %{state | value: new_value, decimal_places: dp + 1, entering: true}}
  end

  defp do_handle({:digit, d}, %{entering: false} = state),
    do: {:ok, %{state | value: d * 1.0, entering: true, decimal_places: nil}}

  defp do_handle({:digit, d}, state), do: {:ok, %{state | value: state.value * 10 + d}}

  defp do_handle(:point, %{decimal_places: dp} = state) when is_integer(dp), do: {:noreply, state}
  defp do_handle(:point, state), do: {:ok, %{state | value: state.value * 1.0, entering: true, decimal_places: 0}}

  defp do_handle({:op, operator}, state) do
    result =
      if state.op, do: apply(Kernel, state.op, [state.left, state.value]), else: state.value

    {:ok, %{state | left: result, value: result, op: operator, entering: false, decimal_places: nil}}
  end

  defp do_handle(:equals, state) do
    result =
      if state.op, do: apply(Kernel, state.op, [state.left, state.value]), else: state.value

    {:ok, %{state | left: result, value: result, op: nil, entering: false, decimal_places: nil}}
  end

  defp do_handle(:clear, %{entering: false} = state),
    do: {:ok, %{state | value: 0, left: 0, op: nil, decimal_places: nil}}

  defp do_handle(:clear, state), do: {:ok, %{state | value: 0, entering: false, decimal_places: nil}}
  defp do_handle(:plus_minus, state), do: {:ok, %{state | value: state.value * -1, decimal_places: nil}}
  defp do_handle(:percent, state), do: {:ok, %{state | value: state.value / 100, decimal_places: nil}}

  defp do_handle({:key, k}, state) when k in ~w(0 1 2 3 4 5 6 7 8 9)a do
    Drafter.activate_widget(:"btn_#{k}")
    {:noreply, state}
  end

  defp do_handle({:key, key}, state) when is_atom(key) do
    case Map.get(@key_mappings, key) do
      {_action, _param, btn_id} ->
        Drafter.activate_widget(btn_id)
        {:noreply, state}

      {_action, btn_id} ->
        Drafter.activate_widget(btn_id)
        {:noreply, state}

      nil ->
        {:noreply, state}
    end
  end

  defp do_handle(_event, state), do: {:noreply, state}

  defp format(n, nil) when is_integer(n), do: Integer.to_string(n)
  defp format(n, nil) when trunc(n) == n, do: n |> trunc() |> Integer.to_string()
  defp format(n, nil), do: :erlang.float_to_binary(n, [:compact, decimals: 10]) |> String.trim_trailing("0") |> String.trim_trailing(".")
  defp format(n, 0), do: (n |> trunc() |> Integer.to_string()) <> "."
  defp format(n, dp), do: :erlang.float_to_binary(n * 1.0, [{:decimals, dp}])
end

Drafter.run(Calculator)
