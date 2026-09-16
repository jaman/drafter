defmodule Drafter.AccountsTest do
  use ExUnit.Case, async: true

  alias Drafter.Accounts

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "drafter_accounts_#{System.os_time(:nanosecond)}_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    path = Path.join(dir, "accounts.bin")
    {:ok, accounts} = Accounts.start_link(path: path, iterations: 1_000)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, accounts: accounts, path: path}
  end

  describe "register/4" do
    test "creates an account that then authenticates", %{accounts: accounts} do
      assert :ok = Accounts.register(accounts, "alice", "correct horse")

      assert {:ok, %{username: "alice", props: %{}}} =
               Accounts.authenticate(accounts, "alice", "correct horse")
    end

    test "keeps the props given", %{accounts: accounts} do
      assert :ok = Accounts.register(accounts, "alice", "correct horse", %{pulse_port: 24_713})

      assert {:ok, %{props: %{pulse_port: 24_713}}} =
               Accounts.authenticate(accounts, "alice", "correct horse")
    end

    test "refuses a name already taken, whatever its case", %{accounts: accounts} do
      :ok = Accounts.register(accounts, "Alice", "correct horse")
      assert {:error, :taken} = Accounts.register(accounts, "alice", "other password")
    end

    test "refuses names outside letters, digits, underscore and dash, or over 32 chars",
         %{accounts: accounts} do
      assert {:error, :invalid_username} = Accounts.register(accounts, "", "correct horse")
      assert {:error, :invalid_username} = Accounts.register(accounts, "al ice", "correct horse")
      assert {:error, :invalid_username} = Accounts.register(accounts, "ali/ce", "correct horse")

      assert {:error, :invalid_username} =
               Accounts.register(accounts, String.duplicate("a", 33), "correct horse")

      assert :ok = Accounts.register(accounts, "al-ice_9", "correct horse")
    end

    test "refuses a password under eight characters", %{accounts: accounts} do
      assert {:error, :weak_password} = Accounts.register(accounts, "alice", "short")
    end
  end

  describe "authenticate/4" do
    test "refuses a wrong password and an unknown user alike", %{accounts: accounts} do
      :ok = Accounts.register(accounts, "alice", "correct horse")
      assert :error = Accounts.authenticate(accounts, "alice", "wrong horse")
      assert :error = Accounts.authenticate(accounts, "nobody", "correct horse")
    end

    test "takes as long for an unknown user as for a wrong password", %{accounts: accounts} do
      :ok = Accounts.register(accounts, "alice", "correct horse")

      {known, :error} =
        :timer.tc(fn -> Accounts.authenticate(accounts, "alice", "wrong horse") end)

      {unknown, :error} =
        :timer.tc(fn -> Accounts.authenticate(accounts, "nobody", "wrong horse") end)

      assert unknown > known / 3
    end

    test "is case-insensitive on the name and returns the registered spelling",
         %{accounts: accounts} do
      :ok = Accounts.register(accounts, "Alice", "correct horse")

      assert {:ok, %{username: "Alice"}} =
               Accounts.authenticate(accounts, "ALICE", "correct horse")
    end

    test "locks a peer out after repeated failures, without touching the hash",
         %{accounts: accounts} do
      :ok = Accounts.register(accounts, "alice", "correct horse")
      peer = {{10, 0, 0, 7}, 51_000}

      for _ <- 1..5, do: :error = Accounts.authenticate(accounts, "alice", "wrong", peer: peer)

      {elapsed, result} =
        :timer.tc(fn -> Accounts.authenticate(accounts, "alice", "correct horse", peer: peer) end)

      assert result == {:error, :locked}
      assert elapsed < 5_000

      assert {:ok, _} =
               Accounts.authenticate(accounts, "alice", "correct horse", peer: {{10, 0, 0, 8}, 1})
    end
  end

  describe "props" do
    test "put_props/3 merges into the account", %{accounts: accounts} do
      :ok = Accounts.register(accounts, "alice", "correct horse", %{pulse_port: 1})
      assert :ok = Accounts.put_props(accounts, "alice", %{team: :red})

      assert {:ok, %{props: %{pulse_port: 1, team: :red}}} =
               Accounts.authenticate(accounts, "alice", "correct horse")

      assert {:error, :unknown} = Accounts.put_props(accounts, "nobody", %{})
    end
  end

  describe "default props" do
    test "an account is given the props the store's function makes from its number, under what registration passes",
         %{path: path} do
      {:ok, accounts} =
        Accounts.start_link(
          path: path <> ".defaults",
          iterations: 1_000,
          default_props: fn n -> %{sound_port: 24_713 + n, colour: :blue} end
        )

      :ok = Accounts.register(accounts, "first", "first password")
      :ok = Accounts.register(accounts, "second", "second password", %{colour: :red})

      assert {:ok, %{props: %{sound_port: 24_713, colour: :blue}}} =
               Accounts.fetch(accounts, "first")

      assert {:ok, %{props: %{sound_port: 24_714, colour: :red}}} =
               Accounts.fetch(accounts, "second")

      assert {:ok, %{props: %{sound_port: 24_714, colour: :red}}} =
               Accounts.authenticate(accounts, "second", "second password")
    end

    test "accounts from before numbering are numbered on load, in name order, and get the defaults too",
         %{path: path} do
      file = path <> ".legacy"
      {:ok, first} = Accounts.start_link(path: file, iterations: 1_000)
      :ok = Accounts.register(first, "zed", "zeds password")
      :ok = Accounts.register(first, "amy", "amys password")
      GenServer.stop(first)

      {:ok, records} = :file.consult(file)

      legacy =
        Map.new(records, fn record ->
          {String.downcase(record.username), Map.delete(record, :number)}
        end)

      File.write!(file, :erlang.term_to_binary(legacy))

      {:ok, again} =
        Accounts.start_link(
          path: file,
          iterations: 1_000,
          default_props: fn n -> %{sound_port: 24_713 + n} end
        )

      assert {:ok, %{props: %{sound_port: 24_713}}} = Accounts.fetch(again, "amy")
      assert {:ok, %{props: %{sound_port: 24_714}}} = Accounts.fetch(again, "zed")
      :ok = Accounts.register(again, "new", "news password")
      assert {:ok, %{props: %{sound_port: 24_715}}} = Accounts.fetch(again, "new")
    end
  end

  describe "the file" do
    test "is text, one Erlang term per account, that file:consult reads and grep can search", %{
      accounts: accounts,
      path: path
    } do
      :ok =
        Accounts.register(accounts, "alice", "correct horse", %{
          team: :red,
          keys: [{:mouse, :left}]
        })

      text = File.read!(path)
      assert text =~ "username: \"alice\"" or text =~ "username => <<\"alice\">>"
      assert {:ok, [record]} = :file.consult(path)
      assert record.username == "alice"
      assert record.number == 0
      assert record.props == %{team: :red, keys: [{:mouse, :left}]}
      assert is_binary(record.hash) and is_binary(record.salt)
    end

    test "a binary file from before is read and written back as text", %{path: path} do
      file = path <> ".was_binary"
      record = %{username: "old", props: %{}, hash: <<1, 2>>, salt: <<3, 4>>, iterations: 1_000}
      File.write!(file, :erlang.term_to_binary(%{"old" => record}))

      {:ok, accounts} = Accounts.start_link(path: file, iterations: 1_000)
      assert {:ok, %{username: "old"}} = Accounts.fetch(accounts, "old")
      assert {:ok, [%{username: "old", number: 0}]} = :file.consult(file)
    end
  end

  describe "change_password/4" do
    test "needs the current password", %{accounts: accounts} do
      :ok = Accounts.register(accounts, "alice", "correct horse")
      assert :error = Accounts.change_password(accounts, "alice", "wrong", "new password")
      assert :ok = Accounts.change_password(accounts, "alice", "correct horse", "new password")
      assert {:ok, _} = Accounts.authenticate(accounts, "alice", "new password")
      assert :error = Accounts.authenticate(accounts, "alice", "correct horse")
    end
  end

  describe "persistence" do
    test "accounts survive a restart", %{accounts: accounts, path: path} do
      :ok = Accounts.register(accounts, "alice", "correct horse", %{pulse_port: 5})
      GenServer.stop(accounts)

      {:ok, reopened} = Accounts.start_link(path: path, iterations: 1_000)

      assert {:ok, %{props: %{pulse_port: 5}}} =
               Accounts.authenticate(reopened, "alice", "correct horse")
    end

    test "the file holds no plaintext password", %{accounts: accounts, path: path} do
      :ok = Accounts.register(accounts, "alice", "correct horse")
      refute File.read!(path) =~ "correct horse"
    end
  end
end
