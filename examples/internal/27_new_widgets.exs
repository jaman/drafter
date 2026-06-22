Mix.install([
  {:drafter, path: Path.join(__DIR__, "../..")},
  {:elixir_make, "~> 0.9"},
  {:spark, "~> 2.6"}
])

defmodule NewWidgetsDemo do
  use Drafter.App
  import Drafter.App

  @sales_data [
    {"Electronics", 34.2},
    {"Clothing", 22.8},
    {"Food & Bev", 18.5},
    {"Home & Garden", 12.1},
    {"Sports", 7.9},
    {"Other", 4.5}
  ]

  @nav_items [
    {"Home", :home},
    {"Products", :products},
    {"Electronics", :electronics},
    {"Laptops", :laptops}
  ]

  def mount(_props) do
    Process.put(:cpu_val, 0.45)
    Process.put(:mem_val, 0.62)
    Process.put(:disk_val, 0.78)

    %{
      selected_date: Date.utc_today(),
      nav_path: @nav_items,
      last_action: "None"
    }
  end

  def on_ready(state) do
    Drafter.set_interval(5, :fps)
    state
  end

  def on_timer(:fps, state) do
    cpu = clamp(Process.get(:cpu_val, 0.5) + (:rand.uniform() - 0.5) * 0.08, 0.05, 0.95)
    mem = clamp(Process.get(:mem_val, 0.6) + (:rand.uniform() - 0.5) * 0.03, 0.3, 0.95)
    disk = clamp(Process.get(:disk_val, 0.78) + (:rand.uniform() - 0.5) * 0.01, 0.5, 0.99)

    Process.put(:cpu_val, cpu)
    Process.put(:mem_val, mem)
    Process.put(:disk_val, disk)

    Drafter.push_data(:cpu_meter, cpu)
    Drafter.push_data(:mem_meter, mem)
    Drafter.push_data(:disk_meter, disk)

    state
  end

  keybinding :tab, "focus next" do
    {:noreply, state}
  end

  keybinding :q, "quit" do
    {:stop, :normal}
  end

  def render(state) do
    vertical([
      header("New Widgets Showcase"),
      horizontal(
        [
          render_left_panel(state),
          render_center_panel(state),
          render_right_panel(state)
        ],
        flex: 1,
        gap: 1
      ),
      footer("Last action: #{state.last_action}")
    ])
  end

  defp render_left_panel(state) do
    vertical(
      [
        box(
          [
            pie_chart(
              @sales_data,
              show_legend: true,
              show_percentages: true
            )
          ],
          title: "Sales by Category"
        ),
        box(
          [
            label("CPU", style: %{bold: true}),
            meter(id: :cpu_meter, buffer: 1, thresholds: default_thresholds()),
            label(""),
            label("Memory", style: %{bold: true}),
            meter(id: :mem_meter, buffer: 1, thresholds: default_thresholds()),
            label(""),
            label("Disk", style: %{bold: true}),
            meter(
              id: :disk_meter,
              buffer: 1,
              thresholds: [
                {0.7, {80, 200, 100}},
                {0.85, {255, 200, 0}},
                {1.0, {255, 60, 60}}
              ]
            )
          ],
          title: "System Meters"
        )
      ],
      width: 32
    )
  end

  defp render_center_panel(state) do
    vertical([
      box(
        [
          breadcrumb(
            state.nav_path,
            on_click: :nav_clicked,
            separator: " › "
          )
        ],
        title: "Navigation"
      ),
      box(
        [
          calendar(
            selected_date: state.selected_date,
            on_select: :date_selected
          )
        ],
        title: "Calendar",
        flex: 1
      )
    ])
  end

  defp render_right_panel(_state) do
    vertical(
      [
        box(
          [
            pie_chart(
              [
                {"Elixir", 42, {148, 94, 207}},
                {"Rust", 28, {222, 110, 55}},
                {"Go", 18, {0, 173, 216}},
                {"Python", 12, {55, 118, 171}}
              ],
              show_legend: true,
              show_percentages: true
            )
          ],
          title: "Language Usage"
        ),
        box(
          [
            label("Vertical Meters:", style: %{bold: true}),
            label(""),
            horizontal(
              [
                meter(value: 0.35, label: "A", orientation: :vertical, height: 8),
                meter(value: 0.62, label: "B", orientation: :vertical, height: 8),
                meter(value: 0.88, label: "C", orientation: :vertical, height: 8),
                meter(value: 0.45, label: "D", orientation: :vertical, height: 8),
                meter(value: 0.71, label: "E", orientation: :vertical, height: 8)
              ],
              gap: 2
            )
          ],
          title: "Vertical Meters",
          flex: 1
        )
      ],
      width: 30
    )
  end

  def handle_event(:date_selected, date, state) do
    {:ok, %{state | selected_date: date, last_action: "Selected date: #{date}"}}
  end

  def handle_event(:nav_clicked, id, state) do
    idx = Enum.find_index(state.nav_path, fn {_, nav_id} -> nav_id == id end)

    new_path =
      if idx do
        Enum.take(state.nav_path, idx + 1)
      else
        state.nav_path
      end

    {:ok, %{state | nav_path: new_path, last_action: "Navigated to: #{id}"}}
  end

  def handle_event(_event, state), do: {:noreply, state}

  defp default_thresholds do
    [{0.6, {80, 200, 100}}, {0.8, {255, 200, 0}}, {1.0, {255, 60, 60}}]
  end

  defp clamp(val, lo, hi), do: max(lo, min(hi, val))
end

Drafter.run(NewWidgetsDemo)
