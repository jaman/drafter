defmodule Drafter.MixProject do
  use Mix.Project

  def project do
    compile_nif()

    [
      app: :drafter,
      version: "0.2.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "An Elixir Terminal User Interface framework",
      package: package(),
      consolidate_protocols: true,
      source_url: "https://github.com/jaman/drafter",
      homepage_url: "https://github.com/jaman/drafter",
      docs: [
        main: "Drafter",
        extras: [
          "README.md",
          "CHANGELOG.md",
          "guides/remote_tui.md": [title: "Remote TUI"],
          "guides/writing_widgets.md": [title: "Writing Widgets & Libraries"]
        ],
        groups_for_modules: [
          "Remote Servers": [Drafter.Server],
          Core: [Drafter, Drafter.App, Drafter.Widget, Drafter.WidgetLibrary, Drafter.Screen],
          Events: [
            Drafter.Event,
            Drafter.Event.Object,
            Drafter.Event.CustomRegistry,
            Drafter.Event.Delegation
          ],
          Theming: [
            Drafter.Theme,
            Drafter.ThemeManager,
            Drafter.Color,
            Drafter.SkinManager,
            Drafter.CharacterSet
          ],
          Drawing: [Drafter.Draw.Segment, Drafter.Draw.Strip, Drafter.Draw.Canvas],
          "Display Widgets": [
            Drafter.Widget.Label,
            Drafter.Widget.Markdown,
            Drafter.Widget.CodeView,
            Drafter.Widget.Digits,
            Drafter.Widget.ProgressBar,
            Drafter.Widget.LoadingIndicator,
            Drafter.Widget.Sparkline,
            Drafter.Widget.Pretty,
            Drafter.Widget.Log,
            Drafter.Widget.RichLog,
            Drafter.Widget.Rule,
            Drafter.Widget.Placeholder
          ],
          "Input Widgets": [
            Drafter.Widget.Button,
            Drafter.Widget.TextInput,
            Drafter.Widget.TextArea,
            Drafter.Widget.Checkbox,
            Drafter.Widget.Switch,
            Drafter.Widget.RadioSet,
            Drafter.Widget.SelectionList,
            Drafter.Widget.MaskedInput,
            Drafter.Widget.OptionList,
            Drafter.Widget.Link
          ],
          "Data Widgets": [
            Drafter.Widget.DataTable,
            Drafter.Widget.Tree,
            Drafter.Widget.DirectoryTree,
            Drafter.Widget.Chart
          ],
          "Layout Widgets": [
            Drafter.Widget.Container,
            Drafter.Widget.ScrollableContainer,
            Drafter.Widget.Grid,
            Drafter.Widget.Card,
            Drafter.Widget.Header,
            Drafter.Widget.Footer,
            Drafter.Widget.Collapsible,
            Drafter.Widget.TabbedContent,
            Drafter.Widget.SplitPaneDivider
          ],
          Testing: [Drafter.Test, Drafter.Test.Harness],
          Animation: [Drafter.Animation]
        ]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :ssh],
      mod: {Drafter.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:phoenix_pubsub, "~> 2.1"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Drafter"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/jaman/drafter"}
    ]
  end

  defp compile_nif do
    case :os.type() do
      {:unix, _} -> do_compile_nif()
      _ -> :ok
    end
  end

  defp do_compile_nif do
    priv_dir = Path.join([__DIR__, "priv"])
    File.mkdir_p!(priv_dir)

    source = Path.join([__DIR__, "c_src", "termios_nif.c"])
    target = Path.join(priv_dir, "termios_nif.so")

    if needs_recompile?(source, target) do
      include_path = erts_include_path()
      {cflags, ldflags} = platform_flags()

      args = cflags ++ ["-I#{include_path}", "-o", target, source] ++ ldflags

      case System.cmd("cc", args, stderr_to_stdout: true) do
        {_, 0} ->
          Mix.shell().info("Compiled termios NIF")
          :ok

        {output, _} ->
          Mix.raise("Failed to compile termios NIF:\n#{output}")
      end
    else
      :ok
    end
  end

  defp needs_recompile?(source, target) do
    not File.exists?(target) or
      File.stat!(source).mtime > File.stat!(target).mtime
  end

  defp erts_include_path do
    version = :erlang.system_info(:version) |> List.to_string()
    Path.join([:code.root_dir(), "erts-#{version}", "include"])
  end

  defp platform_flags do
    case :os.type() do
      {:unix, :darwin} ->
        {["-fPIC", "-O2"], ["-dynamiclib", "-undefined", "dynamic_lookup"]}

      {:unix, _} ->
        {["-fPIC", "-O2"], ["-shared"]}

      _ ->
        {[], []}
    end
  end
end
