defmodule Drafter.Event.Object do
  @moduledoc """
  Rich event struct with DOM-like three-phase dispatch and propagation control.

  An `Event.Object` carries an event's type and payload alongside phase tracking,
  propagation control, and a monotonic timestamp. Events travel through
  three phases: `:capture` (root → target), `:target`, then `:bubble`
  (target → root). Any handler may call `prevent_default/1`,
  `stop_propagation/1`, or `stop_immediate_propagation/1` to modify how
  the event continues.

  `from_tuple/1` builds one from a `Drafter.Event` tuple and `to_tuple/1` returns
  that form, for code that pattern-matches on raw tuples. The round trip is not
  lossless: phase, target and propagation flags are dropped by `to_tuple/1`.

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

  @doc """
  Build an event object of `type` carrying `data`.

  Options:

    * `:target` — widget id the event is aimed at, default `nil`
    * `:current_target` — widget id currently handling it, default `nil`
    * `:phase` — `:capture`, `:target` or `:bubble`, default `:bubble`
    * `:timestamp` — default `System.monotonic_time(:millisecond)`

  The propagation flags always start `false`. Nothing is validated: `type` is
  stored as given, even when it is not one of `t:event_type/0`.

  ## Examples

      iex> Drafter.Event.Object.new(:key, :enter, timestamp: 0)
      %Drafter.Event.Object{
        type: :key,
        data: :enter,
        target: nil,
        current_target: nil,
        phase: :bubble,
        default_prevented: false,
        propagation_stopped: false,
        immediate_propagation_stopped: false,
        timestamp: 0
      }

      iex> event = Drafter.Event.Object.new(:key, :enter, target: :save, phase: :capture)
      iex> {event.target, event.phase}
      {:save, :capture}

  """
  @spec new(event_type(), term(), keyword()) :: t()
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

  @doc """
  Mark the event's default action as prevented.

  Does not stop the event travelling; handlers further along still see it and can
  read `:default_prevented`.

  ## Examples

      iex> Drafter.Event.Object.new(:key, :enter)
      ...> |> Drafter.Event.Object.prevent_default()
      ...> |> Map.fetch!(:default_prevented)
      true

  """
  @spec prevent_default(t()) :: t()
  def prevent_default(%__MODULE__{} = event) do
    %{event | default_prevented: true}
  end

  @doc """
  Stop the event travelling to the next widget in the dispatch path.

  Handlers already reached on the current widget are unaffected, and
  `:immediate_propagation_stopped` stays `false`.

  ## Examples

      iex> event = Drafter.Event.Object.stop_propagation(Drafter.Event.Object.new(:key, :enter))
      iex> {event.propagation_stopped, event.immediate_propagation_stopped}
      {true, false}

  """
  @spec stop_propagation(t()) :: t()
  def stop_propagation(%__MODULE__{} = event) do
    %{event | propagation_stopped: true}
  end

  @doc """
  Stop the event travelling further, including to other handlers on the current widget.

  Sets both `:immediate_propagation_stopped` and `:propagation_stopped`.

  ## Examples

      iex> event = Drafter.Event.Object.new(:key, :enter)
      iex> event = Drafter.Event.Object.stop_immediate_propagation(event)
      iex> {event.propagation_stopped, event.immediate_propagation_stopped}
      {true, true}

  """
  @spec stop_immediate_propagation(t()) :: t()
  def stop_immediate_propagation(%__MODULE__{} = event) do
    %{event | immediate_propagation_stopped: true, propagation_stopped: true}
  end

  @doc """
  Wrap an event tuple in an event object.

  Recognised tuples are the ones listed in `Drafter.Event`; a bare atom becomes an
  event of that type with `nil` data, any other two-element tuple becomes an event
  whose type is its first element, and anything else becomes `:custom` carrying the
  whole term. `{:key, key, modifiers}` is folded into `%{key: key, modifiers: mods}`
  data and `{:resize, {w, h}}` into `%{width: w, height: h}`, both of which
  `to_tuple/1` restores.

  The phase starts at `:bubble` and the timestamp is taken now. `:target` and
  `:current_target` are left `nil`, so a caller that needs them must set them
  afterwards.

  ## Examples

      iex> event = Drafter.Event.Object.from_tuple({:key, :enter})
      iex> {event.type, event.data, event.phase}
      {:key, :enter, :bubble}

      iex> Drafter.Event.Object.from_tuple({:key, :a, [:ctrl]}).data
      %{key: :a, modifiers: [:ctrl]}

      iex> Drafter.Event.Object.from_tuple({:resize, {80, 24}}).data
      %{width: 80, height: 24}

      iex> event = Drafter.Event.Object.from_tuple(:tick)
      iex> {event.type, event.data}
      {:tick, nil}

      iex> event = Drafter.Event.Object.from_tuple({:scroll, :up})
      iex> {event.type, event.data}
      {:scroll, :up}

      iex> event = Drafter.Event.Object.from_tuple({:a, :b, :c, :d})
      iex> {event.type, event.data}
      {:custom, {:a, :b, :c, :d}}

  """
  @spec from_tuple(tuple() | atom()) :: t()
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

  @doc """
  Unwrap an event object back to the event tuple form.

  The inverse of `from_tuple/1` for every tuple it recognises. Phase, target and
  propagation flags are dropped, so a caller that needs them must read them from
  the object before converting.

  `:focus`, `:blur`, `:focus_in` and `:focus_out` with `nil` data give the
  one-element tuple `{:focus}` and friends. An event of any type this function does
  not name gives the bare type atom when its data is `nil`, and `{type, data}`
  otherwise. A named type with `nil` data still gives a tuple: `:key` with `nil`
  data is `{:key, nil}`, not `:key`.

  ## Examples

      iex> Drafter.Event.Object.new(:key, %{key: :a, modifiers: [:ctrl]})
      ...> |> Drafter.Event.Object.to_tuple()
      {:key, :a, [:ctrl]}

      iex> Drafter.Event.Object.new(:resize, %{width: 80, height: 24})
      ...> |> Drafter.Event.Object.to_tuple()
      {:resize, {80, 24}}

      iex> Drafter.Event.Object.to_tuple(Drafter.Event.Object.new(:focus, nil))
      {:focus}

      iex> Drafter.Event.Object.to_tuple(Drafter.Event.Object.new(:custom, nil))
      :custom

      iex> Drafter.Event.Object.to_tuple(Drafter.Event.Object.new(:key, nil))
      {:key, nil}

  """
  @spec to_tuple(t()) :: tuple() | atom()
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
