defmodule Drafter.Widget.Callback do
  @moduledoc """
  Wraps atom event names or functions into closures for widget callback wiring.

  `wrap_0/1`, `wrap_1/1`, and `wrap_2/1` each accept `nil`, a bare function of
  the matching arity, or an atom name. When given an atom, the returned closure
  dispatches the event to the app loop as `{:app_event, name, data}` when no
  modal screen is active, or as `{:tui_event, {:app_callback, name, data}}`
  when a modal is on top.

  Anything that is neither `nil` nor a function of the matching arity is treated as
  a name, including a function of the wrong arity.

  `wrap_0/1`, `wrap_1/1` and `wrap_2/1` capture `self()` at wrap time, so they must
  be called from the process that runs the app loop — normally inside a widget's
  `from_component_opts/2`. `wrap_1_with_pid/2` takes the target pid explicitly for
  callers that cannot guarantee that.

  A dispatching closure returns the message it sent, not the app's reply, because
  `send/2` returns its own message. Widgets that turn a callback result into an
  action therefore only ever see an `{:app_callback, _, _}` tuple when the caller
  supplied a plain function that builds one.
  """
  defp dispatch(session_pid, name, data) do
    case Drafter.ScreenManager.get_active_screen() do
      nil -> send(session_pid, {:app_event, name, data})
      _screen -> send(session_pid, {:tui_event, {:app_callback, name, data}})
    end
  end

  @doc """
  Wraps a zero-arity callback option.

  Returns `nil` for `nil`, the function itself for a function of arity 0, and
  otherwise a new zero-arity closure that dispatches `name` with `nil` data to
  `self()`.

      iex> Drafter.Widget.Callback.wrap_0(nil)
      nil

      iex> f = fn -> :clicked end
      iex> Drafter.Widget.Callback.wrap_0(f) == f
      true

      iex> is_function(Drafter.Widget.Callback.wrap_0(:clicked), 0)
      true
  """
  @spec wrap_0(nil | (-> any()) | atom()) :: (-> any()) | nil
  def wrap_0(nil), do: nil
  def wrap_0(f) when is_function(f, 0), do: f

  def wrap_0(name) do
    session_pid = self()
    fn -> dispatch(session_pid, name, nil) end
  end

  @doc """
  Wraps a one-arity callback option.

  Returns `nil` for `nil`, the function itself for a function of arity 1, and
  otherwise a new one-arity closure that dispatches `name` with its argument as the
  data to `self()`.

      iex> Drafter.Widget.Callback.wrap_1(nil)
      nil

      iex> is_function(Drafter.Widget.Callback.wrap_1(:changed), 1)
      true
  """
  @spec wrap_1(nil | (term() -> any()) | atom()) :: (term() -> any()) | nil
  def wrap_1(nil), do: nil
  def wrap_1(f) when is_function(f, 1), do: f

  def wrap_1(name) do
    session_pid = self()
    fn data -> dispatch(session_pid, name, data) end
  end

  @doc """
  Like `wrap_1/1`, but dispatches to `session_pid` instead of to `self()`.

  Use this when the wrapping happens outside the process that runs the app loop.

      iex> Drafter.Widget.Callback.wrap_1_with_pid(nil, self())
      nil

      iex> is_function(Drafter.Widget.Callback.wrap_1_with_pid(:changed, self()), 1)
      true
  """
  @spec wrap_1_with_pid(nil | (term() -> any()) | atom(), pid()) :: (term() -> any()) | nil
  def wrap_1_with_pid(nil, _pid), do: nil
  def wrap_1_with_pid(f, _pid) when is_function(f, 1), do: f

  def wrap_1_with_pid(name, session_pid) do
    fn data -> dispatch(session_pid, name, data) end
  end

  @doc """
  Wraps a two-arity callback option.

  Returns `nil` for `nil`, the function itself for a function of arity 2, and
  otherwise a new two-arity closure that dispatches `name` with its two arguments
  packed into the tuple `{a, b}` as the data.

      iex> Drafter.Widget.Callback.wrap_2(nil)
      nil

      iex> is_function(Drafter.Widget.Callback.wrap_2(:moved), 2)
      true
  """
  @spec wrap_2(nil | (term(), term() -> any()) | atom()) :: (term(), term() -> any()) | nil
  def wrap_2(nil), do: nil
  def wrap_2(f) when is_function(f, 2), do: f

  def wrap_2(name) do
    session_pid = self()
    fn a, b -> dispatch(session_pid, name, {a, b}) end
  end
end
