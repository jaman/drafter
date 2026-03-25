defmodule Drafter.Widget.Trait.Dsl do
  @moduledoc """
  Spark DSL definition for the widget traits system.

  Provides the `traits` DSL block used in widget definitions
  with compile-time option validation.
  """

  @traits_section %Spark.Dsl.Section{
    name: :traits,
    top_level?: true,
    schema: [],
    entities: [
      %Spark.Dsl.Entity{
        name: :focusable,
        describe: "Makes the widget focusable via tab/arrow navigation",
        schema: [
          tab_index: [
            type: :integer,
            required: false,
            doc: "Explicit tab ordering index"
          ]
        ],
        target: Drafter.Widget.Trait.Focusable,
        args: []
      },
      %Spark.Dsl.Entity{
        name: :scrollable,
        describe: "Adds scrolling capability to the widget",
        schema: [
          direction: [
            type: {:in, [:vertical, :horizontal, :both]},
            default: :vertical,
            doc: "Scroll direction"
          ],
          step: [
            type: :pos_integer,
            default: 1,
            doc: "Lines to scroll per step"
          ],
          show_scrollbar: [
            type: {:in, [:auto, :always, :never]},
            default: :auto,
            doc: "When to show scrollbar"
          ]
        ],
        target: Drafter.Widget.Trait.Scrollable,
        args: []
      },
      %Spark.Dsl.Entity{
        name: :selectable,
        describe: "Adds item selection capability",
        schema: [
          mode: [
            type: {:in, [:none, :single, :multiple]},
            default: :single,
            doc: "Selection mode"
          ]
        ],
        target: Drafter.Widget.Trait.Selectable,
        args: []
      },
      %Spark.Dsl.Entity{
        name: :editable,
        describe: "Adds text editing capability",
        schema: [],
        target: Drafter.Widget.Trait.Editable,
        args: []
      },
      %Spark.Dsl.Entity{
        name: :collapsible_trait,
        describe: "Adds expand/collapse capability",
        schema: [
          initially_expanded: [
            type: :boolean,
            default: false,
            doc: "Whether the widget starts expanded"
          ]
        ],
        target: Drafter.Widget.Trait.Collapsible,
        args: []
      },
      %Spark.Dsl.Entity{
        name: :resizable,
        describe: "Adds resize capability via drag handles",
        schema: [
          edges: [
            type: {:list, {:in, [:right, :bottom, :left, :top]}},
            default: [:right, :bottom],
            doc: "Which edges can be dragged to resize"
          ],
          min_width: [
            type: :pos_integer,
            default: 1,
            doc: "Minimum width constraint"
          ],
          min_height: [
            type: :pos_integer,
            default: 1,
            doc: "Minimum height constraint"
          ]
        ],
        target: Drafter.Widget.Trait.Resizable,
        args: []
      },
      %Spark.Dsl.Entity{
        name: :draggable,
        describe: "Adds drag-and-drop capability",
        schema: [],
        target: Drafter.Widget.Trait.Draggable,
        args: []
      },
      %Spark.Dsl.Entity{
        name: :animatable,
        describe: "Provides render timestamp for animation frames",
        schema: [],
        target: Drafter.Widget.Trait.Animatable,
        args: []
      }
    ]
  }

  use Spark.Dsl.Extension, sections: [@traits_section]

  alias Spark.Dsl.Extension, as: SparkExt

  @spec get_trait_modules(module()) :: [module()]
  def get_trait_modules(module) do
    module
    |> SparkExt.get_entities([:traits])
    |> Enum.map(fn entity -> entity.__struct__ end)
  rescue
    _ -> []
  end
end
