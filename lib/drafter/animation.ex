defmodule Drafter.Animation do
  @moduledoc """
  GenServer that manages timed property animations for widgets.

  Animations interpolate numeric values, RGB color tuples, or discrete values
  between a start and end state over a specified duration. The server ticks at
  60 fps, applies easing, and sends `{:apply_animation, widget_id, property, value}`
  messages to the app loop for each active animation.

  Supported easing atoms: `:linear`, `:ease`, `:ease_in`, `:ease_out`,
  `:ease_in_out`, `:ease_in_quad`, `:ease_out_quad`, `:ease_in_out_quad`,
  `:ease_in_cubic`, `:ease_out_cubic`, `:ease_in_out_cubic`,
  `:ease_in_elastic`, `:ease_out_elastic`, `:ease_out_bounce`,
  `:ease_in_bounce`, `:ease_in_out_bounce`, `:ease_in_back`, `:ease_out_back`.
  """

  use GenServer

  defstruct [
    :id,
    :widget_id,
    :property,
    :start_value,
    :end_value,
    :start_time,
    :duration,
    :easing,
    :on_complete,
    :interpolator,
    :session
  ]

  @type animation :: %__MODULE__{
          id: reference(),
          widget_id: atom(),
          property: atom(),
          start_value: any(),
          end_value: any(),
          start_time: integer(),
          duration: non_neg_integer(),
          easing: atom(),
          on_complete: function() | nil,
          interpolator: function() | nil,
          session: term()
        }

  @default_frame_rate 60
  @frame_duration div(1000, @default_frame_rate)

  @doc """
  Start the animation server, registered under this module's name.

  One runs per node, started by `Drafter.Application`. `opts` are accepted and
  discarded; the tick rate is fixed at 60 fps.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Animate `property` of the widget with id `widget_id` towards `end_value`.

  The starting value is the widget's current value for that property. Numbers are
  interpolated numerically, `{r, g, b}` tuples channel by channel, and any other
  value switches at the end of the duration.

  Options:

    * `:duration` — milliseconds the animation runs for, default `300`
    * `:easing` — one of the easing atoms listed in the module documentation,
      default `:ease_out`
    * `:on_complete` — zero-argument function called once the animation finishes;
      not called when the animation is stopped early

  Returns a reference identifying the animation, which `stop/1` takes. Starting a
  second animation for the same widget and property leaves the first running.
  """
  @spec animate(atom(), atom(), any(), keyword()) :: reference()
  def animate(widget_id, property, end_value, opts \\ []) do
    animation_id = make_ref()
    duration = Keyword.get(opts, :duration, 300)
    easing = Keyword.get(opts, :easing, :ease_out)
    on_complete = Keyword.get(opts, :on_complete)

    GenServer.cast(
      __MODULE__,
      {:animate, animation_id, widget_id, property, end_value, duration, easing, on_complete,
       Drafter.AppRegistry.current_session()}
    )

    animation_id
  end

  @doc """
  Stop the animation started by the call that returned `animation_id`.

  The property keeps whatever value it had reached and `:on_complete` is not run.
  An unknown reference is ignored. Asynchronous.
  """
  @spec stop(reference()) :: :ok
  def stop(animation_id) do
    GenServer.cast(__MODULE__, {:stop, animation_id})
  end

  @doc "Stop every running animation for `widget_id`, as `stop/1` does for one. Asynchronous."
  @spec stop_all(atom()) :: :ok
  def stop_all(widget_id) do
    GenServer.cast(__MODULE__, {:stop_all, widget_id})
  end

  @doc "The animations currently running for `widget_id`, or `[]` if it has none."
  @spec get_animations(atom()) :: [animation()]
  def get_animations(widget_id) do
    GenServer.call(__MODULE__, {:get_animations, widget_id})
  end

  @doc """
  The value `property` has reached in the animation running for `widget_id`.

  Returns `{:ok, value}`, or `:none` when no animation is running for that widget
  and property.
  """
  @spec get_value(atom(), atom()) :: {:ok, any()} | :none
  def get_value(widget_id, property) do
    GenServer.call(__MODULE__, {:get_value, widget_id, property})
  end

  @doc """
  Advance every running animation by one frame immediately.

  The server already ticks itself at 60 fps; calling this only brings the next
  frame forward. Asynchronous.
  """
  @spec tick() :: :ok
  def tick do
    GenServer.cast(__MODULE__, :tick)
  end

  @impl true
  def init(_opts) do
    schedule_tick()
    {:ok, %{animations: %{}, by_widget: %{}}}
  end

  @impl true
  def handle_cast(
        {:animate, id, widget_id, property, end_value, duration, easing, on_complete, session},
        state
      ) do
    current_time = System.monotonic_time(:millisecond)

    start_value = get_current_property_value(session, widget_id, property)

    interpolator = get_interpolator(start_value, end_value)

    animation = %__MODULE__{
      id: id,
      widget_id: widget_id,
      property: property,
      start_value: start_value,
      end_value: end_value,
      start_time: current_time,
      duration: duration,
      easing: easing,
      on_complete: on_complete,
      interpolator: interpolator,
      session: session
    }

    new_animations = Map.put(state.animations, id, animation)

    widget_animations = Map.get(state.by_widget, widget_id, MapSet.new())
    new_widget_animations = MapSet.put(widget_animations, id)
    new_by_widget = Map.put(state.by_widget, widget_id, new_widget_animations)

    {:noreply, %{state | animations: new_animations, by_widget: new_by_widget}}
  end

  def handle_cast({:stop, id}, state) do
    case Map.get(state.animations, id) do
      nil ->
        {:noreply, state}

      animation ->
        new_animations = Map.delete(state.animations, id)

        widget_animations = Map.get(state.by_widget, animation.widget_id, MapSet.new())
        new_widget_animations = MapSet.delete(widget_animations, id)

        new_by_widget =
          if MapSet.size(new_widget_animations) == 0 do
            Map.delete(state.by_widget, animation.widget_id)
          else
            Map.put(state.by_widget, animation.widget_id, new_widget_animations)
          end

        {:noreply, %{state | animations: new_animations, by_widget: new_by_widget}}
    end
  end

  def handle_cast({:stop_all, widget_id}, state) do
    widget_animation_ids = Map.get(state.by_widget, widget_id, MapSet.new())

    new_animations =
      Enum.reduce(widget_animation_ids, state.animations, fn id, acc ->
        Map.delete(acc, id)
      end)

    new_by_widget = Map.delete(state.by_widget, widget_id)

    {:noreply, %{state | animations: new_animations, by_widget: new_by_widget}}
  end

  def handle_cast(:tick, state) do
    current_time = System.monotonic_time(:millisecond)

    {completed, active} =
      Enum.split_with(state.animations, fn {_id, anim} ->
        current_time >= anim.start_time + anim.duration
      end)

    Enum.each(completed, fn {_id, anim} ->
      if anim.on_complete do
        anim.on_complete.()
      end

      apply_animated_value(anim.session, anim.widget_id, anim.property, anim.end_value)
    end)

    Enum.each(active, fn {_id, anim} -> apply_frame(anim, current_time) end)

    completed_ids = Enum.map(completed, fn {id, _} -> id end) |> MapSet.new()

    new_by_widget =
      Enum.reduce(state.by_widget, %{}, fn {widget_id, ids}, acc ->
        remaining = MapSet.difference(ids, completed_ids)

        if MapSet.size(remaining) > 0 do
          Map.put(acc, widget_id, remaining)
        else
          acc
        end
      end)

    new_animations = Map.new(active)

    schedule_tick()
    {:noreply, %{state | animations: new_animations, by_widget: new_by_widget}}
  end

  @impl true
  def handle_call({:get_animations, widget_id}, _from, state) do
    widget_animation_ids = Map.get(state.by_widget, widget_id, MapSet.new())

    animations =
      Enum.map(widget_animation_ids, fn id ->
        Map.get(state.animations, id)
      end)
      |> Enum.filter(&(&1 != nil))

    {:reply, animations, state}
  end

  def handle_call({:get_value, widget_id, property}, _from, state) do
    widget_animation_ids = Map.get(state.by_widget, widget_id, MapSet.new())

    result =
      Enum.find_value(widget_animation_ids, :none, fn id ->
        case Map.get(state.animations, id) do
          %{property: ^property} = anim ->
            current_time = System.monotonic_time(:millisecond)
            progress = calculate_progress(anim, current_time)
            value = interpolate(anim, progress)
            {:ok, value}

          _ ->
            nil
        end
      end)

    {:reply, result, state}
  end

  defp schedule_tick do
    Process.send_after(self(), :do_tick, @frame_duration)
  end

  @impl true
  def handle_info(:do_tick, state) do
    tick()
    {:noreply, state}
  end

  defp get_current_property_value(session, widget_id, property) do
    case get_value_from_widget(session, widget_id, property) do
      {:ok, value} -> value
      :none -> default_value_for_property(property)
    end
  end

  defp get_value_from_widget(session, widget_id, property) do
    Drafter.AppRegistry.send_to_loop(
      session,
      {:get_animated_property, widget_id, property, self()}
    )

    receive do
      {:animated_property, ^widget_id, ^property, value} -> {:ok, value}
    after
      50 -> :none
    end
  end

  defp default_value_for_property(:opacity), do: 1.0
  defp default_value_for_property(:offset_x), do: 0
  defp default_value_for_property(:offset_y), do: 0
  defp default_value_for_property(:background), do: {0, 0, 0}
  defp default_value_for_property(:color), do: {255, 255, 255}
  defp default_value_for_property(_), do: nil

  defp calculate_progress(animation, current_time) do
    elapsed = current_time - animation.start_time
    raw_progress = min(elapsed / animation.duration, 1.0)
    apply_easing(raw_progress, animation.easing)
  end

  defp apply_easing(t, :linear), do: t
  defp apply_easing(t, :ease), do: apply_easing(t, :ease_in_out)
  defp apply_easing(t, :ease_in), do: t * t
  defp apply_easing(t, :ease_out), do: 1 - (1 - t) * (1 - t)

  defp apply_easing(t, :ease_in_out) do
    if t < 0.5 do
      4 * t * t * t
    else
      1 - :math.pow(-2 * t + 2, 3) / 2
    end
  end

  defp apply_easing(t, :ease_in_quad), do: t * t
  defp apply_easing(t, :ease_out_quad), do: 1 - (1 - t) * (1 - t)

  defp apply_easing(t, :ease_in_out_quad) do
    if t < 0.5 do
      2 * t * t
    else
      1 - :math.pow(-2 * t + 2, 2) / 2
    end
  end

  defp apply_easing(t, :ease_in_cubic), do: t * t * t
  defp apply_easing(t, :ease_out_cubic), do: 1 - :math.pow(1 - t, 3)

  defp apply_easing(t, :ease_in_out_cubic) do
    if t < 0.5 do
      4 * t * t * t
    else
      1 - :math.pow(-2 * t + 2, 3) / 2
    end
  end

  defp apply_easing(t, :ease_in_elastic) do
    if t == 0 do
      0.0
    else
      if t == 1 do
        1.0
      else
        -:math.pow(2, 10 * t - 10) * :math.sin((t * 10 - 10.75) * (2 * :math.pi() / 3))
      end
    end
  end

  defp apply_easing(t, :ease_out_elastic) do
    if t == 0 do
      0.0
    else
      if t == 1 do
        1.0
      else
        :math.pow(2, -10 * t) * :math.sin((t * 10 - 0.75) * (2 * :math.pi() / 3)) + 1
      end
    end
  end

  defp apply_easing(t, :ease_out_bounce) do
    n1 = 7.5625
    d1 = 2.75

    cond do
      t < 1 / d1 ->
        n1 * t * t

      t < 2 / d1 ->
        t2 = t - 1.5 / d1
        n1 * t2 * t2 + 0.75

      t < 2.5 / d1 ->
        t2 = t - 2.25 / d1
        n1 * t2 * t2 + 0.9375

      true ->
        t2 = t - 2.625 / d1
        n1 * t2 * t2 + 0.984375
    end
  end

  defp apply_easing(t, :ease_in_bounce) do
    1 - apply_easing(1 - t, :ease_out_bounce)
  end

  defp apply_easing(t, :ease_in_out_bounce) do
    if t < 0.5 do
      (1 - apply_easing(1 - 2 * t, :ease_out_bounce)) / 2
    else
      (1 + apply_easing(2 * t - 1, :ease_out_bounce)) / 2
    end
  end

  defp apply_easing(t, :ease_in_back) do
    c1 = 1.70158
    c3 = c1 + 1
    c3 * t * t * t - c1 * t * t
  end

  defp apply_easing(t, :ease_out_back) do
    c1 = 1.70158
    c3 = c1 + 1
    1 + c3 * :math.pow(t - 1, 3) + c1 * :math.pow(t - 1, 2)
  end

  defp apply_easing(t, _unknown), do: t

  defp get_interpolator(start_value, end_value) do
    cond do
      is_number(start_value) and is_number(end_value) ->
        &interpolate_number/3

      is_tuple(start_value) and is_tuple(end_value) and
        tuple_size(start_value) == 3 and tuple_size(end_value) == 3 ->
        &interpolate_color/3

      true ->
        &interpolate_discrete/3
    end
  end

  defp interpolate(animation, progress) do
    animation.interpolator.(animation.start_value, animation.end_value, progress)
  end

  defp interpolate_number(start, end_val, progress) do
    start + (end_val - start) * progress
  end

  defp interpolate_color({r1, g1, b1}, {r2, g2, b2}, progress) do
    {
      round(r1 + (r2 - r1) * progress),
      round(g1 + (g2 - g1) * progress),
      round(b1 + (b2 - b1) * progress)
    }
  end

  defp interpolate_discrete(_start, end_val, progress) do
    if progress >= 1.0, do: end_val, else: nil
  end

  defp apply_frame(anim, current_time) do
    progress = calculate_progress(anim, current_time)

    case interpolate(anim, progress) do
      nil -> :ok
      value -> apply_animated_value(anim.session, anim.widget_id, anim.property, value)
    end
  end

  defp apply_animated_value(session, widget_id, property, value) do
    Drafter.AppRegistry.send_to_loop(session, {:apply_animation, widget_id, property, value})
  end
end
