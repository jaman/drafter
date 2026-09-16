defmodule Drafter.Terminal.NifLoadErrorTest do
  @moduledoc """
  A native library that did not load says why.

  The loader leaves the Elixir fallbacks in place rather than stopping the module
  from loading, so the functions that have no fallback are the ones that report the
  absence — at a call site far from the load. Without the reason recorded, that
  report is `:nif_not_loaded` and nothing else.
  """

  use ExUnit.Case, async: false

  alias Drafter.Pty
  alias Drafter.Terminal.TermiosNif

  describe "load_error/0" do
    test "is nil once the library is in use" do
      assert TermiosNif.load_error() == nil
    end

    test "reads back whatever the loader recorded" do
      key = TermiosNif.load_error_key()
      restore = :persistent_term.get(key, nil)

      :persistent_term.put(key, "no such file")

      try do
        assert TermiosNif.load_error() == "no such file"
      after
        if restore, do: :persistent_term.put(key, restore), else: :persistent_term.erase(key)
      end
    end
  end

  describe "spawn/2 without the library" do
    setup do
      key = TermiosNif.load_error_key()
      restore = :persistent_term.get(key, nil)
      :persistent_term.put(key, "priv/termios_nif.so: image not found")

      on_exit(fn ->
        if restore, do: :persistent_term.put(key, restore), else: :persistent_term.erase(key)
      end)
    end

    test "reports the load failure rather than raising" do
      assert {:error, {:nif_unavailable, reason}} = Pty.spawn("/bin/cat")
      assert reason =~ "image not found"
    end
  end
end
