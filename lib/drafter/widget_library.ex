defmodule Drafter.WidgetLibrary do
  @moduledoc """
  Macro for packaging and registering collections of Drafter widgets.

  Use this module when authoring a widget library that other developers
  will pull in as a dependency. It handles runtime registration of your
  widgets with Drafter's component renderer and provides a clean API for
  both all-at-once and selective adoption.

  ## Quick start

      defmodule AcmeWidgets do
        use Drafter.WidgetLibrary,
          widgets: [
            AcmeWidgets.Heatmap,
            AcmeWidgets.Sparkbar,
            AcmeWidgets.Timeline
          ]

        def heatmap(opts \\\\ []),   do: {AcmeWidgets.Heatmap,   Map.new(opts)}
        def sparkbar(opts \\\\ []),  do: {AcmeWidgets.Sparkbar,  Map.new(opts)}
        def timeline(opts \\\\ []),  do: {AcmeWidgets.Timeline,  Map.new(opts)}
      end

  ## In the user's application

      # All widgets at once
      Drafter.run(MyApp, widget_libraries: [AcmeWidgets])

      # Or cherry-pick individual widget modules
      Drafter.run(MyApp, widget_libraries: [AcmeWidgets.Heatmap])

      # Mix libraries freely
      Drafter.run(MyApp, widget_libraries: [AcmeWidgets, OtherLib.Canvas])

  Constructor functions are imported in `render/1` via a normal `import`:

      defmodule MyApp do
        use Drafter.App
        import AcmeWidgets

        def render(state) do
          vertical([
            heatmap(data: state.matrix),
            sparkbar(values: state.series)
          ])
        end
      end

  See the `guides/writing_widgets.md` guide for a full walkthrough.
  """

  @doc """
  Returns the list of widget modules declared in the library.

  Available on any module that `use Drafter.WidgetLibrary`.
  """
  @callback __widget_library__() :: [module()]

  @doc """
  Makes all widgets in the library available to the framework.

  Called automatically by `Drafter.run/2` when the library is listed
  under `:widget_libraries`. You can also call it manually at any point
  after the Drafter system has started.
  """
  @callback register() :: :ok

  @doc """
  Define a widget library on the calling module.

  Implements `c:__widget_library__/0` and `c:register/0` for it. `register/0` is
  `defoverridable`, so a library that needs extra start-up work can wrap it.

  ## Options

    * `:widgets` - list of widget modules the library exports. Default: `[]`, which
      makes `register/0` a no-op.

  """
  defmacro __using__(opts) do
    widgets = Keyword.get(opts, :widgets, [])

    quote do
      @behaviour Drafter.WidgetLibrary

      @impl Drafter.WidgetLibrary
      def __widget_library__, do: unquote(widgets)

      @impl Drafter.WidgetLibrary
      def register do
        Enum.each(__widget_library__(), &Drafter.Widget.Registry.register/1)
        :ok
      end

      defoverridable register: 0
    end
  end
end
