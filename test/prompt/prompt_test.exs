defmodule Drafter.PromptTest do
  use ExUnit.Case, async: true

  alias Drafter.Prompt
  alias Drafter.Prompt.Script

  test "text returns what was typed, or the default for an empty line" do
    {answers, transcript} =
      Script.run(["ada", :enter, :enter], fn ->
        {Prompt.text("Name"), Prompt.text("City", default: "Kyoto")}
      end)

    assert answers == {{:ok, "ada"}, {:ok, "Kyoto"}}
    assert transcript == "✔ Name · ada\n✔ City · Kyoto\n"
  end

  test "a rejected line stays open until it is corrected" do
    validate = fn value -> if String.length(value) >= 3, do: :ok, else: {:error, "Too short"} end

    {answer, _transcript} =
      Script.run(["ab", :enter, "c", :enter], fn -> Prompt.text("Name", validate: validate) end)

    assert answer == {:ok, "abc"}
  end

  test "editing keys act at the cursor" do
    inputs = ["hello world", {:key, :w, [:ctrl]}, "there", :home, "oh ", :enter]

    assert {{:ok, "oh hello there"}, _transcript} =
             Script.run(inputs, fn -> Prompt.text("Say") end)
  end

  test "a password is not shown in what the prompt leaves on screen" do
    {answer, transcript} = Script.run(["hunter2", :enter], fn -> Prompt.password("Secret") end)

    assert answer == {:ok, "hunter2"}
    assert transcript == "✔ Secret · *******\n"
  end

  test "tab inserts the only candidate" do
    words = ["status", "start", "stop"]

    assert {{:ok, "stop"}, "> stop\n"} =
             Script.run(["sto", :tab, :enter], fn -> Prompt.readline("> ", complete: words) end)
  end

  test "tab steps through several candidates and enter keeps the chosen one" do
    words = ["status", "start", "stop"]
    inputs = ["s", :tab, :tab, :tab, :enter, " now", :enter]

    assert {{:ok, "start now"}, _transcript} =
             Script.run(inputs, fn -> Prompt.readline("> ", complete: words) end)
  end

  test "up and down walk the history and come back to the line being typed" do
    history = ["second", "first"]

    assert {{:ok, "first"}, _transcript} =
             Script.run([:up, :up, :up, :enter], fn -> Prompt.readline("> ", history: history) end)

    assert {{:ok, "draft"}, _transcript} =
             Script.run(["draft", :up, :down, :enter], fn ->
               Prompt.readline("> ", history: history)
             end)
  end

  test "number rejects text and numbers outside its bounds" do
    inputs = ["0", :enter, :backspace, "x", :enter, :backspace, "8080", :enter]

    assert {{:ok, 8080}, _transcript} =
             Script.run(inputs, fn -> Prompt.number("Port", min: 1) end)
  end

  test "select returns the highlighted entry's value and steps over a disabled entry" do
    choices = ["One", [label: "Two", disabled: true], {"Three", :three}]

    {answer, transcript} = Script.run([:down, :enter], fn -> Prompt.select("Pick", choices) end)

    assert answer == {:ok, :three}
    assert transcript == "✔ Pick · Three\n"
  end

  test "select starts on its default and wraps past the last entry" do
    choices = ["a", "b", "c"]

    assert {{:ok, "b"}, _transcript} =
             Script.run([:enter], fn -> Prompt.select("Pick", choices, default: "b") end)

    assert {{:ok, "a"}, _transcript} =
             Script.run([:down, :down, :enter], fn ->
               Prompt.select("Pick", choices, default: "b")
             end)
  end

  test "typing narrows a filtered list" do
    colours = ["Red", "Green", "Blue"]

    assert {{:ok, "Green"}, _transcript} =
             Script.run(["gr", :enter], fn -> Prompt.select("Colour", colours, filter: true) end)
  end

  test "search lists what its source returns for the typed text" do
    source = fn query -> Enum.filter(["mix", "hex", "rebar"], &String.starts_with?(&1, query)) end

    assert {{:ok, "hex"}, _transcript} =
             Script.run(["h", :enter], fn -> Prompt.search("Tool", source) end)
  end

  test "multiselect returns the picked values in list order and holds to its minimum" do
    inputs = [:enter, :down, :down, :space, :up, :up, :space, :enter]

    {answer, transcript} =
      Script.run(inputs, fn -> Prompt.multiselect("Extras", ["a", "b", "c"], min: 1) end)

    assert answer == {:ok, ["a", "c"]}
    assert transcript == "✔ Extras · a, c\n"
  end

  test "confirm takes y or n, the default on enter, and the switched answer" do
    {answers, _transcript} =
      Script.run(["n", :enter, :left, :enter], fn ->
        {Prompt.confirm("First?"), Prompt.confirm("Second?"), Prompt.confirm("Third?")}
      end)

    assert answers == {{:ok, false}, {:ok, true}, {:ok, false}}
  end

  test "escape, ctrl+c and the end of input each end a prompt without an answer" do
    {answers, transcript} =
      Script.run([:escape, {:key, :c, [:ctrl]}], fn ->
        {Prompt.text("First"), Prompt.select("Second", ["x"]), Prompt.confirm("Third")}
      end)

    assert answers == {{:error, :cancelled}, {:error, :interrupted}, {:error, :eof}}
    assert transcript == "✖ First\n✖ Second\n✖ Third\n"
  end

  test "form asks in order, hands the answers on and leaves a skipped key out" do
    questions = [
      name: {:text, "Name"},
      kind: {:select, "Kind", ["App", "Library"]},
      port: fn
        %{kind: "App"} -> {:number, "Port", default: 4000}
        _answers -> :skip
      end,
      go: {:confirm, "Go?"}
    ]

    assert {{:ok, %{name: "ada", kind: "Library", go: true}}, _transcript} =
             Script.run(["ada", :enter, :down, :enter, "y"], fn -> Prompt.form(questions) end)

    assert {{:ok, %{name: "ada", kind: "App", port: 4000, go: false}}, _transcript} =
             Script.run(["ada", :enter, :enter, :enter, "n"], fn -> Prompt.form(questions) end)
  end

  test "a bang function raises when the prompt ends without an answer" do
    assert_raise Prompt.Stopped, fn ->
      Script.run([:escape], fn -> Prompt.text!("Name") end)
    end
  end

  test "spinner returns what the work returned and shows its output above the final line" do
    {result, transcript} =
      Script.run([], fn ->
        Prompt.spinner("Building", fn ->
          IO.puts("compiled 3 files")
          :built
        end)
      end)

    assert result == :built
    assert transcript == "compiled 3 files\n✔ Building\n"
  end

  test "a spinner whose work raises passes the error on and gives output back to the caller" do
    group_leader = Process.group_leader()

    assert_raise RuntimeError, "boom", fn ->
      Script.run([], fn -> Prompt.spinner("Building", fn -> raise "boom" end) end)
    end

    assert Process.group_leader() == group_leader
  end

  test "progress calls the work for each item and returns the results" do
    {result, transcript} =
      Script.run([], fn -> Prompt.progress("Squaring", [1, 2, 3], &(&1 * &1)) end)

    assert result == [1, 4, 9]
    assert transcript == "✔ Squaring 3/3\n"
  end
end
