defmodule Drafter.Terminal.SignalWatcher do
  @moduledoc """
  Forwards `SIGWINCH` to the terminal driver.

  A `:gen_event` handler for `:erl_signal_server`, which is where OTP delivers a
  signal once `:os.set_signal/2` has marked it as handled. `SIGWINCH` is relayed
  to the driver given to `init/1` as `{:signal, :winch}`. Every other signal is
  ignored.

  Install it with the driver as both the handler argument and the supervising
  process:

      :os.set_signal(:sigwinch, :handle)

      :gen_event.add_sup_handler(
        :erl_signal_server,
        {Drafter.Terminal.SignalWatcher, self()},
        self()
      )
  """

  @behaviour :gen_event

  @typedoc "Where `{:signal, :winch}` is sent: the driver named at installation."
  @type driver :: pid() | atom()

  @doc """
  Keep `driver` as the handler state. `driver` is where signals are relayed.

      iex> Drafter.Terminal.SignalWatcher.init(self())
      {:ok, self()}
  """
  @impl :gen_event
  @spec init(driver()) :: {:ok, driver()}
  def init(driver), do: {:ok, driver}

  @doc """
  Relay `:sigwinch` to the driver as `{:signal, :winch}` and ignore every other signal.

      iex> {:ok, driver} = Drafter.Terminal.SignalWatcher.init(self())
      iex> Drafter.Terminal.SignalWatcher.handle_event(:sigwinch, driver)
      iex> Drafter.Terminal.SignalWatcher.handle_event(:sigterm, driver)
      iex> receive do
      ...>   message -> message
      ...> after
      ...>   0 -> :nothing
      ...> end
      {:signal, :winch}
  """
  @impl :gen_event
  @spec handle_event(term(), driver()) :: {:ok, driver()}
  def handle_event(:sigwinch, driver) do
    send(driver, {:signal, :winch})
    {:ok, driver}
  end

  def handle_event(_signal, driver), do: {:ok, driver}

  @doc "Reply `:ok` to every call, leaving the state unchanged."
  @impl :gen_event
  @spec handle_call(term(), driver()) :: {:ok, :ok, driver()}
  def handle_call(_request, driver), do: {:ok, :ok, driver}

  @doc "Ignore every message."
  @impl :gen_event
  @spec handle_info(term(), driver()) :: {:ok, driver()}
  def handle_info(_message, driver), do: {:ok, driver}

  @doc "Remove the handler without touching the driver."
  @impl :gen_event
  @spec terminate(term(), driver()) :: :ok
  def terminate(_reason, _driver), do: :ok
end
