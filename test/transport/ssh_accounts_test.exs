defmodule Drafter.Transport.SSHAccountsTest do
  @moduledoc """
  Serving an app against a `Drafter.Accounts` store: a stranger connects as the
  registration user, fills in the form, and is playing under the new name before
  the connection ends; the account then works for later logins and nothing else does.
  """

  use ExUnit.Case, async: false

  alias Drafter.Accounts

  @moduletag :ssh
  @moduletag timeout: 60_000

  defmodule Whoami do
    @moduledoc false
    use Drafter.App

    def mount(props), do: %{props: props}
    def render(state), do: vertical([label("user=#{state.props.username}")])
    def handle_event({:key, :c, [:ctrl]}, _state), do: {:stop, :normal}
    def handle_event(_event, state), do: {:noreply, state}
  end

  setup do
    :ssh.start()

    dir =
      Path.join(
        System.tmp_dir!(),
        "drafter_ssh_accounts_#{System.os_time(:nanosecond)}_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    {:ok, accounts} = Accounts.start_link(path: Path.join(dir, "accounts.bin"), iterations: 1_000)
    :ok = Accounts.register(accounts, "bob", "bobs password", %{seat: 24})

    port = 39_000 + :rand.uniform(900)

    {:ok, daemon} =
      Drafter.Server.start_ssh(Whoami,
        port: port,
        auth: {:accounts, accounts},
        register_as: "new"
      )

    Process.sleep(500)

    on_exit(fn ->
      :ssh.stop_daemon(daemon)
      File.rm_rf!(dir)
    end)

    {:ok, port: port, accounts: accounts}
  end

  defp connect(port, user, password) do
    :ssh.connect(
      ~c"127.0.0.1",
      port,
      [
        user: to_charlist(user),
        password: to_charlist(password),
        silently_accept_hosts: true,
        user_interaction: false,
        auth_methods: ~c"password"
      ],
      5000
    )
  end

  defp open_shell(conn) do
    {:ok, channel} = :ssh_connection.session_channel(conn, 5000)
    :ssh_connection.ptty_alloc(conn, channel, term: ~c"xterm", width: 80, height: 24)
    :ok = :ssh_connection.shell(conn, channel)
    channel
  end

  defp collect_until(conn, channel, marker, seen \\ "") do
    receive do
      {:ssh_cm, ^conn, {:data, ^channel, 0, data}} ->
        seen = seen <> data

        if String.contains?(seen, marker),
          do: {:ok, seen},
          else: collect_until(conn, channel, marker, seen)

      {:ssh_cm, ^conn, _other} ->
        collect_until(conn, channel, marker, seen)
    after
      5_000 -> {:timeout, seen}
    end
  end

  defp answer_probe(conn, channel) do
    {:ok, _} = collect_until(conn, channel, FrenchCurve.Capability.probe())
    :ssh_connection.send(conn, channel, "\e[?62;22c")
  end

  test "a stranger registers on first connection and plays under the new name",
       %{port: port, accounts: accounts} do
    {:ok, conn} = connect(port, "new", "anything")
    channel = open_shell(conn)
    answer_probe(conn, channel)

    assert {:ok, _} = collect_until(conn, channel, "Create an account")

    :ssh_connection.send(conn, channel, "alice\tcorrect horse\tcorrect horse\r")

    assert {:ok, _} = collect_until(conn, channel, "user=alice")
    assert {:ok, %{username: "alice"}} = Accounts.authenticate(accounts, "alice", "correct horse")

    :ssh_connection.send(conn, channel, "\x03")
    :ssh.close(conn)
  end

  test "an account logs in with its props in the mount props", %{port: port} do
    {:ok, conn} = connect(port, "bob", "bobs password")
    channel = open_shell(conn)
    answer_probe(conn, channel)

    assert {:ok, _} = collect_until(conn, channel, "user=bob")

    :ssh_connection.send(conn, channel, "\x03")
    :ssh.close(conn)
  end

  test "a wrong password and an unknown user are both refused as a denial, not a server error", %{
    port: port
  } do
    assert {:error, reason} = connect(port, "bob", "not bobs password")
    refute to_string(reason) =~ "Internal error"
    assert {:error, reason} = connect(port, "nobody", "bobs password")
    refute to_string(reason) =~ "Internal error"
    assert {:ok, conn} = connect(port, "bob", "bobs password")
    :ssh.close(conn)
  end

  test "cancelling registration ends the session", %{port: port} do
    {:ok, conn} = connect(port, "new", "anything")
    channel = open_shell(conn)
    answer_probe(conn, channel)
    assert {:ok, _} = collect_until(conn, channel, "Create an account")

    :ssh_connection.send(conn, channel, "\e")

    assert_receive {:ssh_cm, ^conn, {:closed, ^channel}}, 5_000
    :ssh.close(conn)
  end
end
