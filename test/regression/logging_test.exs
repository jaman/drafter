defmodule Drafter.LoggingTest do
  use ExUnit.Case, async: true

  alias Drafter.Logging

  test "no :log option silences the console and writes no file" do
    assert Logging.plan([]) == :silence
  end

  test "log: false also writes no file" do
    assert Logging.plan(log: false) == :silence
  end

  test "log: true plans a file at drafter.log in the cwd" do
    assert {:file, path, :debug} = Logging.plan(log: true)
    assert String.ends_with?(path, "drafter.log")
  end

  test "log: a path plans a file at that path" do
    assert Logging.plan(log: "/tmp/flagon.log") == {:file, "/tmp/flagon.log", :debug}
  end

  test "level is carried through when file logging is enabled" do
    assert Logging.plan(log: "/tmp/flagon.log", level: :info) == {:file, "/tmp/flagon.log", :info}
  end
end
