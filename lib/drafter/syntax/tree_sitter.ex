defmodule Drafter.Syntax.TreeSitter do
  @moduledoc false

  use GenServer

  @bin "tree-sitter"

  @language_extensions %{
    bash: "sh", c: "c", cpp: "cpp", c_sharp: "cs", css: "css",
    elixir: "ex", exs: "exs", go: "go", haskell: "hs", html: "html",
    java: "java", javascript: "js", json: "json", lua: "lua",
    ocaml: "ml", python: "py", ruby: "rb", rust: "rs", scala: "scala",
    swift: "swift", toml: "toml", tsx: "tsx", typescript: "ts",
    yaml: "yaml", zig: "zig"
  }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec available?() :: boolean()
  def available? do
    case GenServer.whereis(__MODULE__) do
      nil -> false
      pid -> GenServer.call(pid, :available?)
    end
  end

  @spec highlight(String.t(), atom()) :: [tuple()]
  def highlight(source, language) do
    case GenServer.whereis(__MODULE__) do
      nil -> []
      pid -> GenServer.call(pid, {:highlight, source, language}, 10_000)
    end
  catch
    :exit, _ -> []
  end

  @spec highlight_file(String.t()) :: [tuple()]
  def highlight_file(path) do
    case GenServer.whereis(__MODULE__) do
      nil -> []
      pid -> GenServer.call(pid, {:highlight_file, path}, 10_000)
    end
  catch
    :exit, _ -> []
  end

  @impl true
  def init(_opts) do
    available = System.find_executable(@bin) != nil
    {:ok, %{available: available}}
  end

  @impl true
  def handle_call(:available?, _from, state) do
    {:reply, state.available, state}
  end

  def handle_call({:highlight, _source, _language}, _from, %{available: false} = state) do
    {:reply, [], state}
  end

  def handle_call({:highlight_file, _path}, _from, %{available: false} = state) do
    {:reply, [], state}
  end

  def handle_call({:highlight, source, language}, _from, state) do
    ext = Map.get(@language_extensions, language, to_string(language))
    tmp = Path.join(System.tmp_dir!(), "ts_#{:erlang.unique_integer([:positive])}.#{ext}")
    captures =
      try do
        File.write!(tmp, source)
        run_highlight_path(tmp)
      after
        File.rm(tmp)
      end
    {:reply, captures, state}
  end

  def handle_call({:highlight_file, path}, _from, state) do
    {:reply, run_highlight_path(path), state}
  end

  defp run_highlight_path(path) do
    case System.cmd(@bin, ["highlight", "--html", "--css-classes", path],
           stderr_to_stdout: true
         ) do
      {html, 0} -> parse_html(html)
      _ -> []
    end
  rescue
    _ -> []
  end

  defp parse_html(html) do
    case Regex.run(~r/<table>(.*?)<\/table>/s, html, capture: :all_but_first) do
      [table] -> parse_rows(table)
      _ -> []
    end
  end

  defp parse_rows(table) do
    ~r/<tr>.*?<td class=line-number>(\d+)<\/td><td class=line>(.*?)<\/td><\/tr>/s
    |> Regex.scan(table, capture: :all_but_first)
    |> Enum.flat_map(fn [line_num, line_html] ->
      line = String.to_integer(line_num)
      walk(line_html, line, 0, [], [])
    end)
  end

  defp walk("", _line, _col, _stack, captures), do: Enum.reverse(captures)

  defp walk(<<"<span class='", rest::binary>>, line, col, stack, captures) do
    {classes, rest2} = split_at(rest, ?')
    rest3 = drop_to_gt(rest2)
    name = classes |> String.split(" ") |> Enum.join(".")
    walk(rest3, line, col, [{line, col, name} | stack], captures)
  end

  defp walk(<<"</span>", rest::binary>>, line, col, [{sl, sc, name} | stack], captures) do
    walk(rest, line, col, stack, [{sl, sc, line, col, name} | captures])
  end

  defp walk(<<"</span>", rest::binary>>, line, col, [], captures) do
    walk(rest, line, col, [], captures)
  end

  defp walk(<<"<", rest::binary>>, line, col, stack, captures) do
    walk(drop_to_gt(rest), line, col, stack, captures)
  end

  defp walk(<<"&amp;", rest::binary>>, line, col, stack, captures),
    do: walk(rest, line, col + 1, stack, captures)

  defp walk(<<"&lt;", rest::binary>>, line, col, stack, captures),
    do: walk(rest, line, col + 1, stack, captures)

  defp walk(<<"&gt;", rest::binary>>, line, col, stack, captures),
    do: walk(rest, line, col + 1, stack, captures)

  defp walk(<<"&#39;", rest::binary>>, line, col, stack, captures),
    do: walk(rest, line, col + 1, stack, captures)

  defp walk(<<"&quot;", rest::binary>>, line, col, stack, captures),
    do: walk(rest, line, col + 1, stack, captures)

  defp walk(<<_char::utf8, rest::binary>>, line, col, stack, captures),
    do: walk(rest, line, col + 1, stack, captures)

  defp split_at(binary, char), do: split_at(binary, char, [])
  defp split_at("", _char, acc), do: {IO.iodata_to_binary(Enum.reverse(acc)), ""}
  defp split_at(<<c, rest::binary>>, char, acc) when c == char,
    do: {IO.iodata_to_binary(Enum.reverse(acc)), rest}
  defp split_at(<<c, rest::binary>>, char, acc), do: split_at(rest, char, [c | acc])

  defp drop_to_gt(""), do: ""
  defp drop_to_gt(<<">", rest::binary>>), do: rest
  defp drop_to_gt(<<_c, rest::binary>>), do: drop_to_gt(rest)
end
