Mix.install([{:drafter, path: Path.join(__DIR__, "../..")}, {:french_curve, github: "jaman/french_curve"}, {:elixir_make, "~> 0.9"}, {:spark, "~> 2.6"}], consolidate_protocols: false)

defmodule WidgetsShowcase do
  use Drafter.App
  import Drafter.App

  keybinding :tab, "focus" do
    {:noreply, state}
  end

  keybinding :q, "quit" do
    {:stop, :normal}
  end

  def mount(_props) do
    %{
      text: "",
      checked: false,
      switch_on: true,
      gain: 0.5,
      selected: nil,
      clicks: 0
    }
  end

  def render(state) do
    vertical([
      header("Widget Showcase"),
      scrollable(
        [
          label("Buttons", style: %{bold: true, fg: :cyan}),
          horizontal(
            [
              button("Default", on_click: :clicked),
              button("Primary", on_click: :clicked, variant: :primary),
              button("Success", on_click: :clicked, variant: :success),
              button("Warning", on_click: :clicked, variant: :warning),
              button("Error", on_click: :clicked, variant: :error)
            ],
            gap: 1
          ),
          label("Clicks: #{state.clicks}"),
          label(""),
          label("Text Input", style: %{bold: true, fg: :cyan}),
          text_input(
            value: state.text,
            placeholder: "Type something...",
            on_change: :text_changed
          ),
          label("Value: #{state.text}"),
          label(""),
          label("Checkbox & Switch", style: %{bold: true, fg: :cyan}),
          horizontal(
            [
              checkbox("Enable feature", checked: state.checked, on_change: :checkbox_changed),
              switch(state.switch_on, on_change: :switch_changed)
            ],
            gap: 4
          ),
          label(""),
          label("Slider", style: %{bold: true, fg: :cyan}),
          slider(bind: :gain, label: "gain ", precision: 2),
          label(""),
          label("Option List", style: %{bold: true, fg: :cyan}),
          option_list(
            [
              {"Elixir", :elixir},
              {"Erlang", :erlang},
              {"Phoenix", :phoenix},
              {"Nerves", :nerves}
            ],
            on_select: :option_selected
          ),
          label("Selected: #{inspect(state.selected)}"),
          label(""),
          label("Progress Bar", style: %{bold: true, fg: :cyan}),
          progress_bar(value: 65, max: 100),
          label(""),
          label("Loading Indicator", style: %{bold: true, fg: :cyan}),
          loading_indicator(running: true),
          label(""),
          label("Rule"),
          rule(),
          label("")
        ],
        flex: 1
      ),
      footer()
    ])
  end

  def handle_event(:clicked, _data, state), do: {:ok, %{state | clicks: state.clicks + 1}}
  def handle_event(:text_changed, {text, _}, state), do: {:ok, %{state | text: text}}
  def handle_event(:text_changed, text, state), do: {:ok, %{state | text: text}}
  def handle_event(:checkbox_changed, value, state), do: {:ok, %{state | checked: value}}
  def handle_event(:switch_changed, value, state), do: {:ok, %{state | switch_on: value}}
  def handle_event(:option_selected, value, state), do: {:ok, %{state | selected: value}}
  def handle_event(_widget_event, _data, state), do: {:noreply, state}

  def handle_event(_event, state), do: {:noreply, state}
end

Drafter.run(WidgetsShowcase)
