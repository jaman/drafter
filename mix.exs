defmodule Drafter.MixProject do
  use Mix.Project

  def project do
    [
      app: :drafter,
      version: "0.2.11",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:elixir_make | Mix.compilers()],
      make_targets: ["all"],
      make_clean: ["clean"],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "An Elixir Terminal User Interface framework",
      package: package(),
      consolsdate_protocols: true,
      source_url: "https://github.com/jaman/drafter",
      homepage_url: "https://github.com/jaman/drafter",
      plumb: [readme: :exact],
      docs: [
        main: "Drafter",
        extras: [
          "README.md",
          "CHANGELOG.md",
          "guides/remote_tui.md": [title: "Remote TUI"],
          "guides/writing_widgets.md": [title: "Writing Widgets & Libraries"],
          "guides/large_text.md": [title: "Large Text"],
          "guides/design_notes.md": [title: "Design Notes"]
        ],
        groups_for_modules: [
          "Remote Servers": [Drafter.Server],
          Core: [
            Drafter,
            Drafter.App,
            Drafter.Widget,
            Drafter.Widget.Trait,
            Drafter.WidgetLibrary,
            Drafter.Screen,
            Drafter.Layout
          ],
          Events: [
            Drafter.Event,
            Drafter.Event.Object,
            Drafter.Event.Delegation
          ],
          Theming: [
            Drafter.Theme,
            Drafter.ThemeManager,
            Drafter.Color,
            Drafter.Style,
            Drafter.SkinManager,
            Drafter.CharacterSet
          ],
          Terminal: [
            Drafter.Clipboard,
            Drafter.CharacterWidth,
            Drafter.Terminal.Probe,
            Drafter.Pty
          ],
          Sessions: [Drafter.Session.Context, Drafter.CellSession],
          Utilities: [Drafter.Format, Drafter.Validation, Drafter.Text, Drafter.ScrollMath],
          Drawing: [Drafter.Draw.Segment, Drafter.Draw.Strip, Drafter.Draw.Canvas],
          "Display Widgets": [
            Drafter.Widget.Label,
            Drafter.Widget.Markdown,
            Drafter.Widget.CodeView,
            Drafter.Widget.Digits,
            Drafter.Widget.Digits.Font,
            Drafter.Widget.Digits.Figlet,
            Drafter.Widget.ProgressBar,
            Drafter.Widget.LoadingIndicator,
            Drafter.Widget.Sparkline,
            Drafter.Widget.Pretty,
            Drafter.Widget.Log,
            Drafter.Widget.RichLog,
            Drafter.Widget.Rule,
            Drafter.Widget.Placeholder,
            Drafter.Widget.Gauge,
            Drafter.Widget.Meter,
            Drafter.Widget.Breadcrumb
          ],
          "Input Widgets": [
            Drafter.Widget.Button,
            Drafter.Widget.TextInput,
            Drafter.Widget.TextArea,
            Drafter.Widget.Checkbox,
            Drafter.Widget.Switch,
            Drafter.Widget.Slider,
            Drafter.Widget.RadioSet,
            Drafter.Widget.SelectionList,
            Drafter.Widget.MaskedInput,
            Drafter.Widget.OptionList,
            Drafter.Widget.Link,
            Drafter.Widget.Calendar,
            Drafter.Widget.FilePicker
          ],
          "Data Widgets": [
            Drafter.Widget.DataTable,
            Drafter.Widget.Tree,
            Drafter.Widget.DirectoryTree,
            Drafter.Widget.Chart,
            Drafter.Widget.PieChart
          ],
          "Layout Widgets": [
            Drafter.Widget.Container,
            Drafter.Widget.ScrollableContainer,
            Drafter.Widget.Grid,
            Drafter.Widget.Box,
            Drafter.Widget.Card,
            Drafter.Widget.Header,
            Drafter.Widget.Footer,
            Drafter.Widget.Collapsible,
            Drafter.Widget.TabbedContent,
            Drafter.Widget.SplitPaneDivider
          ],
          Testing: [Drafter.Test, Drafter.Test.Harness, Drafter.WidgetHierarchy],
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
      {:french_curve, github: "jaman/french_curve"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:plumb, "~> 0.1", only: :dev, runtime: false},
      {:phoenix_pubsub, "~> 2.1"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Drafter"],
      files: ~w(lib c_src guides Makefile mix.exs .formatter.exs README.md CHANGELOG.md),
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/jaman/drafter"}
    ]
  end
end
