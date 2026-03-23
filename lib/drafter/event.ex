defmodule Drafter.Event do
  @moduledoc """
  Event system for TUI applications.

  Defines event types and provides utilities for event handling
  in the TUI framework.

  ## Event Representation

  Events can be represented in two ways:

  1. **Tuple-based (legacy)**: `{:key, :enter}`, `{:mouse, %{...}}`
  2. **Object-based (new)**: `%Drafter.Event.Object{type: :key, data: :enter, ...}`

  The object-based representation supports advanced features like event capture
  phase, propagation control, and default prevention.

  See `Drafter.Event.Object` for the new event object API.
  """

  alias Drafter.Event.Object, as: EventObject

  @type key :: atom()
  @type modifiers :: [atom()]
  @type mouse_action :: :click | :press | :release | :move | :scroll_up | :scroll_down
  @type resize_info :: {width :: pos_integer(), height :: pos_integer()}

  @type t ::
    {:key, key()} |
    {:key, key(), modifiers()} |
    {:mouse, %{action: mouse_action(), x: non_neg_integer(), y: non_neg_integer(), button: atom()}} |
    {:resize, resize_info()} |
    {:focus, widget_id :: term()} |
    {:blur, widget_id :: term()} |
    {:focus_in, widget_id :: term()} |
    {:focus_out, widget_id :: term()} |
    {:mount, widget_id :: term()} |
    {:unmount, widget_id :: term()} |
    {:show, widget_id :: term()} |
    {:hide, widget_id :: term()} |
    {:load, widget_id :: term()} |
    {:timer, timer_id :: term()} |
    {:custom, term()}

  @doc "Create a key event"
  @spec key(key(), modifiers()) :: t()
  def key(key, modifiers \\ []) do
    if modifiers == [] do
      {:key, key}
    else
      {:key, key, modifiers}
    end
  end

  @doc "Create a mouse event"
  @spec mouse(mouse_action(), non_neg_integer(), non_neg_integer(), atom()) :: t()
  def mouse(action, x, y, button \\ :left) do
    {:mouse, %{action: action, x: x, y: y, button: button}}
  end

  @doc "Create a resize event"
  @spec resize(pos_integer(), pos_integer()) :: t()
  def resize(width, height) do
    {:resize, {width, height}}
  end

  @doc "Create a focus event"
  @spec focus(term()) :: t()
  def focus(widget_id) do
    {:focus, widget_id}
  end

  @doc "Create a blur event"
  @spec blur(term()) :: t()
  def blur(widget_id) do
    {:blur, widget_id}
  end

  @doc "Create a focus_in event (descendant gained focus)"
  @spec focus_in(term()) :: t()
  def focus_in(widget_id) do
    {:focus_in, widget_id}
  end

  @doc "Create a focus_out event (descendant lost focus)"
  @spec focus_out(term()) :: t()
  def focus_out(widget_id) do
    {:focus_out, widget_id}
  end

  @doc "Create a mount event"
  @spec mount(term()) :: t()
  def mount(widget_id) do
    {:mount, widget_id}
  end

  @doc "Create an unmount event"
  @spec unmount(term()) :: t()
  def unmount(widget_id) do
    {:unmount, widget_id}
  end

  @doc "Create a show event (widget became visible)"
  @spec show(term()) :: t()
  def show(widget_id) do
    {:show, widget_id}
  end

  @doc "Create a hide event (widget became hidden)"
  @spec hide(term()) :: t()
  def hide(widget_id) do
    {:hide, widget_id}
  end

  @doc "Create a load event (widget finished loading)"
  @spec load(term()) :: t()
  def load(widget_id) do
    {:load, widget_id}
  end

  @doc "Create a timer event"
  @spec timer(term()) :: t()
  def timer(timer_id) do
    {:timer, timer_id}
  end

  @doc "Create a custom event"
  @spec custom(term()) :: t()
  def custom(data) do
    {:custom, data}
  end

  @doc "Check if event is a key event"
  @spec key_event?(t()) :: boolean()
  def key_event?({:key, _}), do: true
  def key_event?({:key, _, _}), do: true
  def key_event?(_), do: false

  @doc "Check if event is a mouse event"
  @spec mouse_event?(t()) :: boolean()
  def mouse_event?({:mouse, _}), do: true
  def mouse_event?(_), do: false

  @doc "Check if event is a resize event"
  @spec resize_event?(t()) :: boolean()
  def resize_event?({:resize, _}), do: true
  def resize_event?(_), do: false

  @doc "Extract key from key event"
  @spec get_key(t()) :: {key(), modifiers()} | nil
  def get_key({:key, key}), do: {key, []}
  def get_key({:key, key, modifiers}), do: {key, modifiers}
  def get_key(_), do: nil

  @doc "Extract mouse data from mouse event"
  @spec get_mouse(t()) :: map() | nil
  def get_mouse({:mouse, data}), do: data
  def get_mouse(_), do: nil

  @doc "Extract resize data from resize event"
  @spec get_resize(t()) :: resize_info() | nil
  def get_resize({:resize, size}), do: size
  def get_resize(_), do: nil

  defdelegate from_tuple(event_tuple), to: EventObject
  defdelegate to_tuple(event_object), to: EventObject
  defdelegate prevent_default(event_object), to: EventObject
  defdelegate stop_propagation(event_object), to: EventObject
  defdelegate stop_immediate_propagation(event_object), to: EventObject
end
