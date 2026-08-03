defmodule Drafter.Transport.SessionStartupTest do
  @moduledoc """
  A remote session starts an app the same way a local terminal does.

  `run_isolated_session/3` resolves the app's callbacks through
  `Drafter.Runtime.for_app/1` rather than calling `mount/1` and `on_ready/1` on the
  module directly, so an app whose entry point is `init/1` — a reducer app — connects
  over ssh or telnet as readily as it runs locally. An interval registered in
  `on_ready/1` fires for the remote session, and mount props reach it intact.
  """

  use ExUnit.Case, async: false

  defmodule Ticker do
    @moduledoc false
    use Drafter.App

    def mount(props), do: %{ticks: 0, cwd: Map.get(props, :cwd, "unset")}

    def render(state), do: vertical([label("TICKS=#{state.ticks} CWD=#{state.cwd}")])

    def on_ready(state) do
      Drafter.set_interval(60, :tick)
      state
    end

    def on_timer(:tick, state), do: %{state | ticks: state.ticks + 1}

    def handle_event(_event, state), do: {:noreply, state}
  end

  defmodule Reduced do
    @moduledoc false
    use Drafter, runtime: :reducer

    def init(props), do: %{label: Map.get(props, :label, "unset")}

    def render(state), do: vertical([label("LABEL=#{state.label}")])

    def update(_event, state), do: state
  end

  defp connect(opts), do: connect(Ticker, opts)

  defp connect(app_module, opts) do
    port = 35_000 + :rand.uniform(1500)
    {:ok, server} = Drafter.Server.start_telnet(app_module, [port: port] ++ opts)
    Process.sleep(400)

    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], 2000)

    on_exit(fn ->
      :gen_tcp.close(socket)

      if Process.alive?(server) do
        Process.unlink(server)
        Process.exit(server, :kill)
      end
    end)

    socket
  end

  defp read_until(socket, pattern, attempts \\ 30) do
    Enum.reduce_while(1..attempts, "", fn _attempt, acc ->
      accumulate(:gen_tcp.recv(socket, 0, 400), acc, pattern)
    end)
  end

  defp accumulate({:error, _reason}, acc, _pattern), do: {:cont, acc}

  defp accumulate({:ok, data}, acc, pattern) do
    text = acc <> data
    if text =~ pattern, do: {:halt, text}, else: {:cont, text}
  end

  @tag :telnet
  test "a reducer app can be served remotely, not just run locally" do
    socket = connect(Reduced, mount_props: %{label: "from init"})

    assert read_until(socket, "LABEL=") =~ "LABEL=from init",
           "the session did not mount through the app's runtime backend"
  end

  @tag :telnet
  test "an interval registered in on_ready fires for a remote session" do
    socket = connect([])

    assert read_until(socket, "TICKS=") =~ "TICKS=",
           "the session never painted"

    assert read_until(socket, "TICKS=3") =~ "TICKS=3",
           "on_ready registered an interval that never fired over telnet"
  end

  @tag :telnet
  test "mount props reach a remote session" do
    socket = connect(mount_props: %{cwd: "/remote/dir"})

    assert read_until(socket, "CWD=") =~ "CWD=/remote/dir"
  end
end
