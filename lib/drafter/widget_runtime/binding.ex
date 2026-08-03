defmodule Drafter.Binding do
  @moduledoc false

  defp send_app_callback(session_pid, callback_name, data) do
    case Drafter.ScreenManager.get_active_screen() do
      nil ->
        send(session_pid, {:app_event, callback_name, data})

      _screen ->
        send(session_pid, {:tui_event, {:app_callback, callback_name, data}})
    end
  end

  @doc """
  The value a widget should display, given its options and the app state.

  With `:bind` set to an atom, reads that key out of `app_state`. Without it, falls
  back to the `:value` option. `default` is used when neither is present, and
  defaults to `nil`.

  Raises `FunctionClauseError` when `:bind` is present but is not an atom.
  """
  @spec get_bound_value(keyword(), map(), term()) :: term()
  def get_bound_value(opts, app_state, default \\ nil) do
    case Keyword.get(opts, :bind) do
      nil -> Keyword.get(opts, :value, default)
      key when is_atom(key) -> Map.get(app_state, key, default)
    end
  end

  @doc """
  A one-argument change callback for a widget, or `nil` when it needs none.

  With `:bind` set, the returned function sends `{:bound_state_update, key, value}`
  to the calling process and, when `:on_change` is also set, fires that app callback
  too. Without `:bind`, returns a function that only fires `:on_change`, or `nil` when
  `:on_change` is absent as well.

  The `value_key` argument is accepted and ignored; the bound key comes from `:bind`.
  """
  @spec create_bound_callback(keyword(), atom()) :: (term() -> term()) | nil
  def create_bound_callback(opts, _value_key) do
    session_pid = self()
    build_bound_callback(session_pid, Keyword.get(opts, :bind), opts)
  end

  defp build_bound_callback(_session_pid, nil, opts) do
    on_change = Keyword.get(opts, :on_change)

    if on_change do
      session_pid = self()
      fn value -> send_app_callback(session_pid, on_change, value) end
    end
  end

  defp build_bound_callback(session_pid, bind_key, opts) when is_atom(bind_key) do
    on_change = Keyword.get(opts, :on_change)

    fn value ->
      send(session_pid, {:bound_state_update, bind_key, value})
      if on_change, do: send_app_callback(session_pid, on_change, value)
    end
  end

  @doc """
  As `create_bound_callback/2`, but for a text input's `{text, validation_result}` pair.

  Only the text is written back to the bound key; the whole pair is passed to
  `:on_change`.
  """
  @spec create_text_input_callback(keyword()) :: ({String.t(), term()} -> term()) | nil
  def create_text_input_callback(opts) do
    session_pid = self()
    build_text_input_callback(session_pid, Keyword.get(opts, :bind), opts)
  end

  defp build_text_input_callback(_session_pid, nil, opts) do
    on_change = Keyword.get(opts, :on_change)

    if on_change do
      session_pid = self()
      fn {text, vr} -> send_app_callback(session_pid, on_change, {text, vr}) end
    end
  end

  defp build_text_input_callback(session_pid, bind_key, opts) when is_atom(bind_key) do
    on_change = Keyword.get(opts, :on_change)

    fn {text, vr} ->
      send(session_pid, {:bound_state_update, bind_key, text})
      if on_change, do: send_app_callback(session_pid, on_change, {text, vr})
    end
  end

  @doc "Whether `opts` carries a `:bind` key, even one set to `nil`."
  @spec has_binding?(keyword()) :: boolean()
  def has_binding?(opts) do
    Keyword.has_key?(opts, :bind)
  end

  @doc "The app-state key named by `:bind`, or `nil` when unbound."
  @spec get_binding_key(keyword()) :: atom() | nil
  def get_binding_key(opts) do
    Keyword.get(opts, :bind)
  end
end
