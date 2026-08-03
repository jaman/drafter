defmodule Drafter.Event do
  @moduledoc """
  The event vocabulary: the tagged tuples an application and a widget receive.

  ## What an application receives

  An application module's `handle_event(event, state)` is called with one of these:

    * `{:key, key}` — a named key (`:enter`, `:escape`, `:up`, `:down`, `:left`,
      `:right`, `:tab`, `:backspace`, `:delete`, `:insert`, `:home`, `:end`,
      `:page_up`, `:page_down`, `:f1`..`:f12`) or, for printable ASCII, the
      character itself as an atom (`:a`, `:Z`, `:"1"`, `:" "`).
    * `{:key, key, modifiers}` — the same with a non-empty modifier list, always a
      subset of `[:ctrl, :alt, :shift]` in that order.
    * `{:char, codepoint}` — an integer codepoint outside printable ASCII.
    * `{:mouse, payload}` — see "Mouse payloads" below.
    * `{:bracketed_paste, text}` — pasted text with the delimiters stripped,
      delivered only while `Drafter.Clipboard.paste_enabled?/0` is true.
    * `{:timer, timer_id}` — a timer the application started has fired.
    * `{:app_callback, name, data}` — a widget invoked a named application callback.
    * `{:theme_updated, theme}` — the active theme changed.

  Two events never reach `handle_event/2`: `{:key, :q, [:ctrl]}` stops the
  application, and `{:resize, {cols, rows}}` is consumed by the runtime, which
  passes the new size to the next `render/2` as the screen rect.

  A focused widget is offered an event before the application is. When the widget
  consumes it, `handle_event/2` is not called for that event.

  ## Mouse payloads

  `x` and `y` are zero-based column and row on the screen. `modifiers` is a subset
  of `[:ctrl, :alt, :shift]`.

    * `%{type: :mouse_down | :mouse_up | :drag, button: button, x: x, y: y, modifiers: mods}`
      with `button` one of `:left`, `:middle`, `:right`, `:scroll`, `:unknown`
    * `%{type: :move, x: x, y: y, modifiers: mods}`
    * `%{type: :scroll, direction: :up | :down | :left | :right, x: x, y: y, modifiers: mods}`

  ## Widget lifecycle events

  Widgets additionally receive `{:focus}` and `{:blur}`, and the hierarchy forms
  `{:focus_in, widget_id}`, `{:focus_out, widget_id}`, `{:mount, widget_id}`,
  `{:unmount, widget_id}`, `{:show, widget_id}`, `{:hide, widget_id}` and
  `{:load, widget_id}`.

  ## Constructors and accessors

  The functions here build and inspect those tuples.

      iex> Drafter.Event.key(:q, [:ctrl])
      {:key, :q, [:ctrl]}

      iex> Drafter.Event.key_event?({:key, :enter})
      true

  ## The struct form

  `Drafter.Event.Object` is the same event as a struct carrying dispatch phase and
  propagation flags. `from_tuple/1` and `to_tuple/1` convert between the two forms
  and are delegated to that module, along with `prevent_default/1`,
  `stop_propagation/1` and `stop_immediate_propagation/1`.
  """

  alias Drafter.Event.Object, as: EventObject

  @type key :: atom()
  @type modifiers :: [atom()]
  @type mouse_action :: :click | :press | :release | :move | :scroll_up | :scroll_down
  @type resize_info :: {width :: pos_integer(), height :: pos_integer()}

  @type t ::
          {:key, key()}
          | {:key, key(), modifiers()}
          | {:char, char()}
          | {:mouse, map()}
          | {:bracketed_paste, binary()}
          | {:resize, resize_info()}
          | {:focus, widget_id :: term()}
          | {:blur, widget_id :: term()}
          | {:focus_in, widget_id :: term()}
          | {:focus_out, widget_id :: term()}
          | {:mount, widget_id :: term()}
          | {:unmount, widget_id :: term()}
          | {:show, widget_id :: term()}
          | {:hide, widget_id :: term()}
          | {:load, widget_id :: term()}
          | {:timer, timer_id :: term()}
          | {:custom, term()}

  @doc """
  A key event for `key`, carrying `modifiers` when the list is non-empty.

  Returns `{:key, key}` for the default empty modifier list and
  `{:key, key, modifiers}` otherwise, so a caller matching on `{:key, k}` sees
  unmodified keys only.

  ## Examples

      iex> Drafter.Event.key(:enter)
      {:key, :enter}

      iex> Drafter.Event.key(:q, [:ctrl])
      {:key, :q, [:ctrl]}

  """
  @spec key(key(), modifiers()) :: t()
  def key(key, modifiers \\ []) do
    if modifiers == [] do
      {:key, key}
    else
      {:key, key, modifiers}
    end
  end

  @doc """
  A mouse event as `{:mouse, %{action: action, x: x, y: y, button: button}}`.

  `x` and `y` are zero-based column and row; `button` defaults to `:left`. The
  payload is keyed by `:action` and carries no modifiers, unlike the `:type`-keyed
  payloads the terminal driver produces and documented in the moduledoc.

  ## Examples

      iex> Drafter.Event.mouse(:click, 3, 4)
      {:mouse, %{action: :click, x: 3, y: 4, button: :left}}

      iex> Drafter.Event.mouse(:press, 0, 0, :right)
      {:mouse, %{action: :press, x: 0, y: 0, button: :right}}

  """
  @spec mouse(mouse_action(), non_neg_integer(), non_neg_integer(), atom()) :: t()
  def mouse(action, x, y, button \\ :left) do
    {:mouse, %{action: action, x: x, y: y, button: button}}
  end

  @doc """
  A resize event as `{:resize, {width, height}}`, in cells.

  ## Examples

      iex> Drafter.Event.resize(80, 24)
      {:resize, {80, 24}}

  """
  @spec resize(pos_integer(), pos_integer()) :: t()
  def resize(width, height) do
    {:resize, {width, height}}
  end

  @doc "A `{:focus, widget_id}` event, marking that widget as having gained focus."
  @spec focus(term()) :: t()
  def focus(widget_id) do
    {:focus, widget_id}
  end

  @doc "A `{:blur, widget_id}` event, marking that widget as having lost focus."
  @spec blur(term()) :: t()
  def blur(widget_id) do
    {:blur, widget_id}
  end

  @doc "A `{:focus_in, widget_id}` event, raised on an ancestor when a descendant gains focus."
  @spec focus_in(term()) :: t()
  def focus_in(widget_id) do
    {:focus_in, widget_id}
  end

  @doc "A `{:focus_out, widget_id}` event, raised on an ancestor when a descendant loses focus."
  @spec focus_out(term()) :: t()
  def focus_out(widget_id) do
    {:focus_out, widget_id}
  end

  @doc "A `{:mount, widget_id}` event, raised when that widget enters the hierarchy."
  @spec mount(term()) :: t()
  def mount(widget_id) do
    {:mount, widget_id}
  end

  @doc "An `{:unmount, widget_id}` event, raised when that widget leaves the hierarchy."
  @spec unmount(term()) :: t()
  def unmount(widget_id) do
    {:unmount, widget_id}
  end

  @doc "A `{:show, widget_id}` event, raised when that widget becomes visible."
  @spec show(term()) :: t()
  def show(widget_id) do
    {:show, widget_id}
  end

  @doc "A `{:hide, widget_id}` event, raised when that widget becomes hidden."
  @spec hide(term()) :: t()
  def hide(widget_id) do
    {:hide, widget_id}
  end

  @doc "A `{:load, widget_id}` event, raised when that widget has finished loading."
  @spec load(term()) :: t()
  def load(widget_id) do
    {:load, widget_id}
  end

  @doc """
  A `{:timer, timer_id}` event, delivered when the timer with that id fires.

  ## Examples

      iex> Drafter.Event.timer(:tick)
      {:timer, :tick}

  """
  @spec timer(term()) :: t()
  def timer(timer_id) do
    {:timer, timer_id}
  end

  @doc "A `{:custom, data}` event carrying an application-defined payload."
  @spec custom(term()) :: t()
  def custom(data) do
    {:custom, data}
  end

  @doc """
  Whether `event` is `{:key, _}` or `{:key, _, _}`.

  ## Examples

      iex> Drafter.Event.key_event?({:key, :enter})
      true

      iex> Drafter.Event.key_event?({:key, :q, [:ctrl]})
      true

      iex> Drafter.Event.key_event?({:mouse, %{}})
      false

  """
  @spec key_event?(t()) :: boolean()
  def key_event?({:key, _}), do: true
  def key_event?({:key, _, _}), do: true
  def key_event?(_), do: false

  @doc """
  Whether `event` is `{:mouse, _}`.

  ## Examples

      iex> Drafter.Event.mouse_event?(Drafter.Event.mouse(:click, 1, 1))
      true

      iex> Drafter.Event.mouse_event?({:key, :a})
      false

  """
  @spec mouse_event?(t()) :: boolean()
  def mouse_event?({:mouse, _}), do: true
  def mouse_event?(_), do: false

  @doc """
  Whether `event` is `{:resize, _}`.

  ## Examples

      iex> Drafter.Event.resize_event?({:resize, {80, 24}})
      true

      iex> Drafter.Event.resize_event?({:key, :a})
      false

  """
  @spec resize_event?(t()) :: boolean()
  def resize_event?({:resize, _}), do: true
  def resize_event?(_), do: false

  @doc """
  The key and its modifiers as `{key, modifiers}`, or `nil` for any other event.

  An unmodified `{:key, key}` yields an empty modifier list.

  ## Examples

      iex> Drafter.Event.get_key({:key, :enter})
      {:enter, []}

      iex> Drafter.Event.get_key({:key, :q, [:ctrl]})
      {:q, [:ctrl]}

      iex> Drafter.Event.get_key({:mouse, %{}})
      nil

  """
  @spec get_key(t()) :: {key(), modifiers()} | nil
  def get_key({:key, key}), do: {key, []}
  def get_key({:key, key, modifiers}), do: {key, modifiers}
  def get_key(_), do: nil

  @doc """
  The payload map of a mouse event, or `nil` for any other event.

  ## Examples

      iex> Drafter.Event.get_mouse({:mouse, %{action: :move, x: 1, y: 2}})
      %{action: :move, x: 1, y: 2}

      iex> Drafter.Event.get_mouse({:key, :a})
      nil

  """
  @spec get_mouse(t()) :: map() | nil
  def get_mouse({:mouse, data}), do: data
  def get_mouse(_), do: nil

  @doc """
  The new size as `{width, height}`, or `nil` for any other event.

  ## Examples

      iex> Drafter.Event.get_resize({:resize, {80, 24}})
      {80, 24}

      iex> Drafter.Event.get_resize({:key, :a})
      nil

  """
  @spec get_resize(t()) :: resize_info() | nil
  def get_resize({:resize, size}), do: size
  def get_resize(_), do: nil

  @doc "Wrap an event tuple in a `Drafter.Event.Object`. See `Drafter.Event.Object.from_tuple/1`."
  defdelegate from_tuple(event_tuple), to: EventObject

  @doc "Unwrap a `Drafter.Event.Object` back to an event tuple. See `Drafter.Event.Object.to_tuple/1`."
  defdelegate to_tuple(event_object), to: EventObject

  @doc "Mark an event object as having had its default action prevented."
  defdelegate prevent_default(event_object), to: EventObject

  @doc "Stop an event object travelling to the next widget in the dispatch path."
  defdelegate stop_propagation(event_object), to: EventObject

  @doc """
  Stop an event object travelling further.

  Stronger than `stop_propagation/1`: it also prevents the remaining handlers on the
  current widget from seeing the event.
  """
  defdelegate stop_immediate_propagation(event_object), to: EventObject
end
