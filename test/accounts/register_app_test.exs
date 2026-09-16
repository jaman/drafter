defmodule Drafter.Accounts.RegisterAppTest do
  use ExUnit.Case, async: false

  alias Drafter.Accounts
  alias Drafter.Accounts.RegisterApp
  alias Drafter.Test, as: DT

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "drafter_register_#{System.os_time(:nanosecond)}_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    {:ok, accounts} = Accounts.start_link(path: Path.join(dir, "accounts.bin"), iterations: 1_000)

    ctx = DT.start_headless(RegisterApp, %{accounts: accounts, notify: self()}, size: {60, 24})

    on_exit(fn ->
      DT.stop(ctx)
      File.rm_rf!(dir)
    end)

    {:ok, ctx: ctx, accounts: accounts}
  end

  defp type(ctx, text) do
    for <<char <- text>>, do: DT.send_key(ctx, String.to_atom(<<char>>))
  end

  defp fill(ctx, username, password, confirm) do
    type(ctx, username)
    DT.send_key(ctx, :tab)
    type(ctx, password)
    DT.send_key(ctx, :tab)
    type(ctx, confirm)
  end

  test "a filled form creates the account and reports it", %{ctx: ctx, accounts: accounts} do
    fill(ctx, "alice", "correct horse", "correct horse")
    DT.send_key(ctx, :enter)

    assert_receive {:drafter_registration, {:ok, %{username: "alice"}}}, 2_000
    assert {:ok, _} = Accounts.authenticate(accounts, "alice", "correct horse")
  end

  test "mismatched passwords are refused with the fields kept", %{ctx: ctx} do
    fill(ctx, "alice", "correct horse", "wrong horse")
    DT.send_key(ctx, :enter)

    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "do not match" end)
    assert DT.get_state(ctx).username == "alice"
    refute_receive {:drafter_registration, _}, 100
  end

  test "a taken name is refused", %{ctx: ctx, accounts: accounts} do
    :ok = Accounts.register(accounts, "alice", "correct horse")
    fill(ctx, "alice", "correct horse", "correct horse")
    DT.send_key(ctx, :enter)

    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "already taken" end)
  end

  test "escape cancels", %{ctx: ctx} do
    DT.send_key(ctx, :escape)
    assert_receive {:drafter_registration, :cancelled}, 2_000
  end

  test "passwords are not shown", %{ctx: ctx} do
    fill(ctx, "alice", "correct horse", "correct horse")
    DT.sync(ctx)
    refute DT.screen_text(ctx) =~ "correct horse"
  end
end
