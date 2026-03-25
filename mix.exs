defmodule Drafter.MixProject do
  use Mix.Project

  def project do
    [
      app: :drafter,
      version: "0.2.4",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:elixir_make | Mix.compilers()],
      make_targets: ["all"],
      make_clean: ["clean"],
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
      {:elixir_make, "~> 0.9"},
      {:spark, "~> 2.6"},
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
end
