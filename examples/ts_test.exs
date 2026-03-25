Mix.install([{:drafter, path: Path.join(__DIR__, "..")}, {:elixir_make, "~> 0.9"}, {:spark, "~> 2.6"}])

alias Drafter.Syntax.TreeSitter

{:ok, _} = TreeSitter.start_link()

IO.puts("tree-sitter available: #{TreeSitter.available?()}")
IO.puts("")

args = System.argv()

if args == [] do
  IO.puts("Usage: elixir ts_test.exs <file_path>")
  System.halt(1)
end

path = hd(args)

extension_to_language = %{
  "sh" => :bash, "c" => :c, "cpp" => :cpp, "cs" => :c_sharp, "css" => :css,
  "ex" => :elixir, "exs" => :exs, "go" => :go, "hs" => :haskell, "html" => :html,
  "java" => :java, "js" => :javascript, "json" => :json, "lua" => :lua,
  "ml" => :ocaml, "py" => :python, "rb" => :ruby, "rs" => :rust, "scala" => :scala,
  "swift" => :swift, "toml" => :toml, "tsx" => :tsx, "ts" => :typescript,
  "yaml" => :yaml, "zig" => :zig
}

ext = path |> Path.extname() |> String.trim_leading(".")
language = Map.get(extension_to_language, ext, String.to_atom(ext))

IO.puts("--- #{language} captures (#{path}) ---")
captures = TreeSitter.highlight_file(path)
Enum.each(captures, fn {sl, sc, el, ec, name} ->
  IO.puts("  #{name} [#{sl}:#{sc} - #{el}:#{ec}]")
end)
IO.puts("Total: #{length(captures)} captures")
