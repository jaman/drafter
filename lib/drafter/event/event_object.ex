defmodule Drafter.Event.Object do
  @moduledoc """
  Rich event struct with DOM-like three-phase dispatch and propagation control.

  An `Event.Object` wraps a legacy event tuple and adds phase tracking,
  propagation control, and a monotonic timestamp. Events travel through
  three phases: `:capture` (root → target), `:target`, then `:bubble`
  (target → root). Any handler may call `prevent_default/1`,
  `stop_propagation/1`, or `stop_immediate_propagation/1` to modify how
  the event continues.

  Convert from a legacy tuple with `from_tuple/1` and back with `to_tuple/1`
  for backward compatibility with code that pattern-matches on raw tuples.

  Struct fields:

  - `:type` — event type atom (`:key`, `:char`, `:mouse`, `:focus`, `:blur`,
    `:focus_in`, `:focus_out`, `:mount`, `:unmount`, `:show`, `:hide`,
    `:load`, `:custom`, `:resize`, `:timer`)
  - `:data` — event payload, format varies by type
  - `:target` — widget id that is the final event target
  - `:current_target` — widget id currently processing the event
  - `:phase` — current dispatch phase (`:capture`, `:target`, or `:bubble`)
  - `:default_prevented` — true after `prevent_default/1`
  - `:propagation_stopped` — true after `stop_propagation/1` or `stop_immediate_propagation/1`
  - `:immediate_propagation_stopped` — true after `stop_immediate_propagation/1`
  - `:timestamp` — `System.monotonic_time(:millisecond)` at creation
  """

  defstruct [
    :type,
    :data,
    :target,
    :current_target,
    phase: :bubble,
    default_prevented: false,
    propagation_stopped: false,
    immediate_propagation_stopped: false,
    timestamp: nil
  ]

  @type event_type ::
          :key
          | :char
          | :mouse
          | :focus
          | :blur
          | :focus_in
          | :focus_out
          | :mount
          | :unmount
          | :show
          | :hide
          | :load
          | :custom
          | :resize
          | :timer

  @type phase :: :capture | :target | :bubble

  @type t :: %__MODULE__{
          type: event_type(),
          data: term(),
          target: atom() | String.t() | nil,
          current_target: atom() | String.t() | nil,
          phase: phase(),
          default_prevented: boolean(),
          propagation_stopped: boolean(),
          immediate_propagation_stopped: boolean(),
          timestamp: integer() | nil
        }

  def new(type, data, opts \\ []) do
    %__MODULE__{
      type: type,
      data: data,
      target: Keyword.get(opts, :target),
      current_target: Keyword.get(opts, :current_target),
      phase: Keyword.get(opts, :phase, :bubble),
      timestamp: Keyword.get(opts, :timestamp, System.monotonic_time(:millisecond))
    }
  end

  def prevent_default(%__MODULE__{} = event) do
    %{event | default_prevented: true}
  end

  def stop_propagation(%__MODULE__{} = event) do
    %{event | propagation_stopped: true}
  end

  def stop_immediate_propagation(%__MODULE__{} = event) do
    %{event | immediate_propagation_stopped: true, propagation_stopped: true}
  end

  def from_tuple({:key, key}) do
    new(:key, key)
  end

  def from_tuple({:key, key, modifiers}) when is_list(modifiers) do
    new(:key, %{key: key, modifiers: modifiers})
  end

  def from_tuple({:char, char}) do
    new(:char, char)
  end

  def from_tuple({:mouse, data}) when is_map(data) do
    new(:mouse, data)
  end

  def from_tuple({:focus}) do
    new(:focus, nil)
  end

  def from_tuple({:focus, widget_id}) do
    new(:focus, widget_id)
  end

  def from_tuple({:blur}) do
    new(:blur, nil)
  end

  def from_tuple({:blur, widget_id}) do
    new(:blur, widget_id)
  end

  def from_tuple({:focus_in}) do
    new(:focus_in, nil)
  end

  def from_tuple({:focus_in, widget_id}) do
    new(:focus_in, widget_id)
  end

  def from_tuple({:focus_out}) do
    new(:focus_out, nil)
  end

  def from_tuple({:focus_out, widget_id}) do
    new(:focus_out, widget_id)
  end

  def from_tuple({:resize, {width, height}}) do
    new(:resize, %{width: width, height: height})
  end

  def from_tuple({:mount, widget_id}) do
    new(:mount, widget_id)
  end

  def from_tuple({:unmount, widget_id}) do
    new(:unmount, widget_id)
  end

  def from_tuple({:show, widget_id}) do
    new(:show, widget_id)
  end

  def from_tuple({:hide, widget_id}) do
    new(:hide, widget_id)
  end

  def from_tuple({:load, widget_id}) do
    new(:load, widget_id)
  end

  def from_tuple({:timer, timer_id}) do
    new(:timer, timer_id)
  end

  def from_tuple({:custom, data}) do
    new(:custom, data)
  end

  def from_tuple(event) when is_atom(event) do
    new(event, nil)
  end

  def from_tuple(event) when is_tuple(event) do
    case tuple_size(event) do
      2 ->
        {type, data} = event
        new(type, data)

      _ ->
        new(:custom, event)
    end
  end

  def to_tuple(%__MODULE__{type: :key, data: key}) when is_atom(key) do
    {:key, key}
  end

  def to_tuple(%__MODULE__{type: :key, data: %{key: key, modifiers: modifiers}}) do
    {:key, key, modifiers}
  end

  def to_tuple(%__MODULE__{type: :char, data: char}) do
    {:char, char}
  end

  def to_tuple(%__MODULE__{type: :mouse, data: data}) do
    {:mouse, data}
  end

  def to_tuple(%__MODULE__{type: :focus, data: nil}) do
    {:focus}
  end

  def to_tuple(%__MODULE__{type: :focus, data: widget_id}) do
    {:focus, widget_id}
  end

  def to_tuple(%__MODULE__{type: :blur, data: nil}) do
    {:blur}
  end

  def to_tuple(%__MODULE__{type: :blur, data: widget_id}) do
    {:blur, widget_id}
  end

  def to_tuple(%__MODULE__{type: :focus_in, data: nil}) do
    {:focus_in}
  end

  def to_tuple(%__MODULE__{type: :focus_in, data: widget_id}) do
    {:focus_in, widget_id}
  end

  def to_tuple(%__MODULE__{type: :focus_out, data: nil}) do
    {:focus_out}
  end

  def to_tuple(%__MODULE__{type: :focus_out, data: widget_id}) do
    {:focus_out, widget_id}
  end

  def to_tuple(%__MODULE__{type: :resize, data: %{width: w, height: h}}) do
    {:resize, {w, h}}
  end

  def to_tuple(%__MODULE__{type: :mount, data: widget_id}) do
    {:mount, widget_id}
  end

  def to_tuple(%__MODULE__{type: :unmount, data: widget_id}) do
    {:unmount, widget_id}
  end

  def to_tuple(%__MODULE__{type: :timer, data: timer_id}) do
    {:timer, timer_id}
  end

  def to_tuple(%__MODULE__{type: :show, data: widget_id}) do
    {:show, widget_id}
  end

  def to_tuple(%__MODULE__{type: :hide, data: widget_id}) do
    {:hide, widget_id}
  end

  def to_tuple(%__MODULE__{type: :load, data: widget_id}) do
    {:load, widget_id}
  end

  def to_tuple(%__MODULE__{type: type, data: nil}) do
    type
  end

  def to_tuple(%__MODULE__{type: type, data: data}) do
    {type, data}
  end
end
