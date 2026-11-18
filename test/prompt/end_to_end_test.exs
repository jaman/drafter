defmodule Drafter.Prompt.EndToEndTest do
  use ExUnit.Case, async: false

  alias Drafter.Pty
  alias Drafter.TestSupport.InlineScreen

  @on_a_terminal """
  {:ok, _started} = Application.ensure_all_started(:drafter)
  {:ok, name} = Drafter.Prompt.text("Name")
  {:ok, kind} = Drafter.Prompt.select("Kind", ["App", "Library"])
  result = Drafter.Prompt.spinner("Working", fn -> IO.puts("step one"); :finished end)
  {:error, reason} = Drafter.Prompt.confirm("Again?")
  IO.puts("ANSWERS " <> inspect({name, kind, result, reason}))
  """

  @through_a_pipe """
  {:ok, _started} = Application.ensure_all_started(:drafter)
  {:ok, name} = Drafter.Prompt.text("Name")
  {:ok, kind} = Drafter.Prompt.select("Kind", ["App", "Library"])
  {:ok, extras} = Drafter.Prompt.multiselect("Extras", ["a", "b", "c"])
  {:ok, go} = Drafter.Prompt.confirm("Go?")
  IO.puts("ANSWERS " <> inspect({name, kind, extras, go}))
  """

  @around_a_full_screen_app """
  {:ok, _started} = Application.ensure_all_started(:drafter)

  defmodule Between do
    use Drafter.App
    import Drafter.App

    def mount(_props), do: %{}

    keybinding :q, "quit" do
      {:stop, :normal}
    end

    def render(_state), do: vertical([label("FULL SCREEN APP")])
    def handle_event(_event, state), do: {:noreply, state}
  end

  {:ok, first} = Drafter.Prompt.text("First")
  :ok = Drafter.run(Between, halt_on_exit: false)
  {:ok, second} = Drafter.Prompt.text("Second")
  IO.puts("ANSWERS " <> inspect({first, second}))
  """

  defp code_paths do
    Mix.Project.build_path()
    |> Path.join("lib/*/ebin")
    |> Path.wildcard()
    |> Enum.flat_map(&["-pa", &1])
  end

  defp await(pty, text, seen \\ "") do
    io = pty.io

    receive do
      {^io, {:data, bytes}} ->
        seen = seen <> bytes
        if String.contains?(seen, text), do: seen, else: await(pty, text, seen)
    after
      10_000 -> flunk("never saw #{inspect(text)}; got #{inspect(seen)}")
    end
  end

  test "on a terminal, prompts in a row read every key and leave their answers on screen" do
    {:ok, pty} =
      Pty.spawn(System.find_executable("elixir"), args: code_paths() ++ ["-e", @on_a_terminal])

    asked = await(pty, "Name")
    Pty.write(pty, "ada\r\e[B\r")
    again = await(pty, "Again?", asked)
    Pty.write(pty, <<3>>)
    output = await(pty, "}\r\n", again)

    lines =
      InlineScreen.new(24)
      |> InlineScreen.write(output)
      |> InlineScreen.lines()
      |> Enum.reject(&(&1 == ""))

    assert lines == [
             "✔ Name · ada",
             "✔ Kind · Library",
             "step one",
             "✔ Working",
             "✖ Again?",
             ~s(ANSWERS {"ada", "Library", :finished, :interrupted})
           ]

    Pty.close(pty)
  end

  test "through a pipe, each question is answered by one line of input" do
    command = ~s(printf 'ada\\n2\\n1,3\\n\\n' | exec "$@")
    arguments = ["-c", command, "sh", System.find_executable("elixir")] ++ code_paths()

    {output, 0} = System.cmd("sh", arguments ++ ["-e", @through_a_pipe])

    assert output =~ ~s(ANSWERS {"ada", "Library", ["a", "c"], true})
  end

  test "a full-screen app between two prompts gets its keys and gives the keyboard back" do
    {:ok, pty} =
      Pty.spawn(System.find_executable("elixir"),
        args: code_paths() ++ ["-e", @around_a_full_screen_app]
      )

    await(pty, "First")
    Pty.write(pty, "one\r")
    await(pty, "FULL SCREEN APP")
    Pty.write(pty, "q")
    await(pty, "Second")
    Pty.write(pty, "two\r")

    assert await(pty, ~s({"one", "two"})) =~ ~s(ANSWERS {"one", "two"})

    Pty.close(pty)
  end
end
