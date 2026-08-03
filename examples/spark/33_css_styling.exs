Mix.install([{:drafter, path: Path.join(__DIR__, "../..")}, {:french_curve, github: "jaman/french_curve"}, {:elixir_make, "~> 0.9"}, {:spark, "~> 2.6"}], consolidate_protocols: false)

defmodule CssStyling do
  use Drafter, css_path: Path.join(__DIR__, "33_css_styling.tcss")

  state %{count: 0, text: ""}

  keybinding :q, "quit" do
    {:stop, :normal}
  end

  keybinding :r, "reset" do
    {:ok, %{state | count: 0, text: ""}}
  end

  def render(state) do
    vertical([
      header("CSS Styling"),
      label("Widgets styled by a stylesheet, not by inline options", class: "title"),
      rule(),
      label("A class selects a rule; several classes combine", class: "subtitle"),
      horizontal(
        [
          button("Primary", on_click: :add_ten),
          button("Success", on_click: :add_five, class: "success"),
          button("Warning", on_click: :subtract_five, class: "warning"),
          button("Neon", on_click: :add_one, class: "neon")
        ],
        gap: 1
      ),
      rule(),
      label("Count: #{state.count}", class: counter_class(state.count)),
      label("(passes 5 and the highlight class takes over)", class: "muted"),
      horizontal(
        [
          button("Increment", on_click: :add_one),
          button("Decrement", on_click: :subtract_one),
          button("Reset", id: :reset, on_click: :reset, class: "danger")
        ],
        gap: 1
      ),
      rule(),
      label("An id selector beats a class, and :focus applies while focused", class: "subtitle"),
      text_input(placeholder: "Type something...", bind: :text),
      label("You typed: #{state.text}", class: "muted"),
      rule(),
      label("Inline styles still win over the stylesheet", class: "subtitle"),
      horizontal(
        [
          label("Hex", style: %{fg: "#ff4444"}),
          label("Named", style: %{fg: :green}),
          label("RGB", style: %{fg: "rgb(68, 200, 255)"})
        ],
        gap: 2
      ),
      footer()
    ])
  end

  def handle_event(:add_one, _data, state), do: {:ok, %{state | count: state.count + 1}}
  def handle_event(:subtract_one, _data, state), do: {:ok, %{state | count: state.count - 1}}
  def handle_event(:add_five, _data, state), do: {:ok, %{state | count: state.count + 5}}
  def handle_event(:subtract_five, _data, state), do: {:ok, %{state | count: state.count - 5}}
  def handle_event(:add_ten, _data, state), do: {:ok, %{state | count: state.count + 10}}
  def handle_event(:reset, _data, state), do: {:ok, %{state | count: 0, text: ""}}
  def handle_event(_name, _data, state), do: {:noreply, state}

  defp counter_class(count) when count > 5, do: ["counter", "highlight"]
  defp counter_class(_count), do: "counter"
end

Drafter.run(CssStyling)
