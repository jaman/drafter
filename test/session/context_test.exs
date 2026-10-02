defmodule Drafter.Session.ContextTest do
  use ExUnit.Case, async: false

  alias Drafter.Session.Context

  setup do
    Enum.each(Context.keys(), &Process.delete/1)
    :ok
  end

  test "capture snapshots only the roles that are set" do
    Process.put(:drafter_compositor, self())
    assert Context.capture() == %{drafter_compositor: self()}
  end

  test "adopt re-establishes a captured context in another process" do
    Process.put(:drafter_compositor, self())
    Process.put(:drafter_theme_manager, self())
    captured = Context.capture()
    owner = self()

    task =
      Task.async(fn ->
        Context.adopt(captured)
        {Context.get(:compositor), Context.get(:theme_manager)}
      end)

    assert Task.await(task) == {owner, owner}
  end

  test "the session's own instance wins over a globally registered one" do
    Process.put(:drafter_theme_manager, self())
    assert Context.get(:theme_manager) == self()
  end

  describe "terminal_env" do
    test "falls back to the host environment outside a session" do
      assert Context.terminal_env() == System.get_env()
    end

    test "a session's own environment wins over the host's" do
      Context.put_terminal_env(%{"TERM" => "xterm-kitty"})

      assert Context.terminal_env() == %{"TERM" => "xterm-kitty"}
    end

    test "capture and adopt carry it to another process" do
      Context.put_terminal_env(%{"LC_TERMINAL" => "iTerm2"})
      captured = Context.capture()

      task = Task.async(fn -> Context.adopt(captured) && Context.terminal_env() end)

      assert Task.await(task) == %{"LC_TERMINAL" => "iTerm2"}
    end
  end
end
