Mix.install([
  {:drafter, path: Path.join(__DIR__, "../..")}, {:french_curve, github: "jaman/french_curve"},
  {:elixir_make, "~> 0.9"},
  {:spark, "~> 2.6"}
], consolidate_protocols: false)

defmodule Dashboard do
  use Drafter

  @skins [
    {:graphical, "Graphical", "1"},
    {:classic, "Classic", "2"},
    {:retro, "Retro", "3"},
    {:wireframe, "Wireframe", "4"},
    {:ascii, "ASCII", "5"}
  ]

  @services [
    %{name: "api-gateway", status: "up", latency: "12ms", req_s: "4821"},
    %{name: "auth-service", status: "up", latency: "8ms", req_s: "2103"},
    %{name: "data-store", status: "up", latency: "34ms", req_s: "1892"},
    %{name: "cache", status: "WARN", latency: "91ms", req_s: "3441"},
    %{name: "message-queue", status: "up", latency: "5ms", req_s: "9812"},
    %{name: "worker-pool", status: "DOWN", latency: "-", req_s: "0"},
    %{name: "metrics", status: "up", latency: "18ms", req_s: "441"},
    %{name: "notifier", status: "WARN", latency: "142ms", req_s: "228"}
  ]

  @log_messages [
    "[INFO]  api-gateway: 200 GET /api/users (12ms)",
    "[INFO]  auth-service: token validated for user 9921",
    "[WARN]  cache: latency spike detected (91ms)",
    "[INFO]  message-queue: processed 128 messages",
    "[ERROR] worker-pool: connection refused",
    "[INFO]  api-gateway: 201 POST /api/orders (18ms)",
    "[WARN]  notifier: retry attempt 3 for job #8812",
    "[INFO]  data-store: checkpoint complete",
    "[ERROR] worker-pool: health check failed",
    "[INFO]  auth-service: session created for user 1204",
    "[WARN]  cache: eviction rate above threshold",
    "[INFO]  api-gateway: 200 GET /api/stats (9ms)",
    "[INFO]  metrics: exported 412 series to backend",
    "[WARN]  notifier: queue depth 842 (high)",
    "[INFO]  data-store: index rebuilt in 2.3s"
  ]

  def mount(_props) do
    Process.put(:dash_memory, 61)
    Process.put(:dash_log_index, 8)
    %{current_skin: :graphical}
  end

  def on_ready(state) do
    Drafter.set_interval(24, :fps)
    seed_buffers()
    state
  end

  defp seed_buffers do
    Enum.each(gen_hist(60, 10, 60), &Drafter.push_data(:cpu_spark, &1))
    Enum.each(gen_hist(60, 45, 30), &Drafter.push_data(:mem_spark, &1))
    Enum.each(gen_hist(60, 5, 80), &Drafter.push_data(:rx_spark, &1))
    Enum.each(gen_hist(60, 2, 40), &Drafter.push_data(:tx_spark, &1))
    Enum.each(Enum.take(@log_messages, 8), &Drafter.push_data(:event_log, &1))
  end

  keybinding :"1", "Graphical skin" do
    {:ok, apply_skin(:graphical, state)}
  end

  keybinding :"2", "Classic skin" do
    {:ok, apply_skin(:classic, state)}
  end

  keybinding :"3", "Retro skin" do
    {:ok, apply_skin(:retro, state)}
  end

  keybinding :"4", "Wireframe skin" do
    {:ok, apply_skin(:wireframe, state)}
  end

  keybinding :"5", "ASCII skin" do
    {:ok, apply_skin(:ascii, state)}
  end

  keybinding :tab, "focus next" do
    {:noreply, state}
  end

  keybinding :q, "quit" do
    {:stop, :normal}
  end

  def on_timer(:fps, state) do
    prev_mem = Process.get(:dash_memory, 61)
    cpu = clamp(:rand.uniform(100), 5, 95)
    memory = clamp(prev_mem + :rand.uniform(7) - 3, 30, 90)
    rx = clamp(:rand.uniform(100), 5, 99)
    tx = clamp(:rand.uniform(60), 2, 60)

    Process.put(:dash_memory, memory)

    Drafter.push_data(:cpu_spark, cpu)
    Drafter.push_data(:cpu_meter, cpu / 100)
    Drafter.push_data(:mem_spark, memory)
    Drafter.push_data(:mem_meter, memory / 100)
    Drafter.push_data(:rx_spark, rx)
    Drafter.push_data(:rx_meter, rx / 100)
    Drafter.push_data(:tx_spark, tx)
    Drafter.push_data(:tx_meter, tx / 100)

    log_idx = Process.get(:dash_log_index, 8)
    msg = Enum.at(@log_messages, rem(log_idx, length(@log_messages)))
    Drafter.push_data(:event_log, timestamp_prefix() <> msg)
    Process.put(:dash_log_index, log_idx + 1)

    state
  end

  def render(state) do
    vertical([
      header("System Dashboard  — skins: 1 graphical  2 classic  3 retro  4 wireframe  5 ascii"),
      breadcrumb(
        [{"Home", :home}, {"Infrastructure", :infra}, {"Dashboard", :dash}],
        separator: " › "
      ),
      split_pane(
        [
          split_pane(
            [
              render_left(state),
              render_center(state)
            ],
            orientation: :horizontal,
            ratio: 0.32,
            id: :inner_split,
            resize_mode: :quick
          ),
          render_right(state)
        ],
        orientation: :horizontal,
        ratio: 0.7,
        id: :outer_split,
        flex: 1,
        resize_mode: :live
      ),
      footer()
    ])
  end

  defp render_left(state) do
    vertical([
      box(
        [
          label("CPU", style: %{bold: true}),
          meter(id: :cpu_meter, buffer: 1),
          label(""),
          label("Memory", style: %{bold: true}),
          meter(id: :mem_meter, buffer: 1),
          label(""),
          label("Net RX", style: %{bold: true}),
          meter(id: :rx_meter, buffer: 1),
          label(""),
          label("Net TX", style: %{bold: true}),
          meter(id: :tx_meter, buffer: 1)
        ],
        title: "Resources"
      ),
      box(
        [
          label("Uptime  #{format_uptime(93_847)}"),
          label("Nodes   3 / 3 online"),
          label("Alerts  2 active"),
          label("Tasks   14 running"),
          label(""),
          calendar()
        ],
        title: "Overview",
        flex: 1
      ),
      box(
        [
          scrollable(
            [
              label("Skin:", style: %{bold: true}),
              option_list(
                Enum.map(@skins, fn {id, label, key} -> {"#{key} #{label}", id} end),
                on_select: :skin_selected,
                selected: state.current_skin
              ),
              label(""),
              label("Controls:", style: %{bold: true}),
              checkbox("Auto-refresh", checked: true),
              checkbox("Alerts enabled", checked: false),
              switch(label: "Maintenance", enabled: false),
              switch(label: "Dark mode", enabled: true),
              radio_set(
                [{"Low", :low}, {"Med", :med}, {"High", :high}],
                selected: :med,
                height: 3
              )
            ],
            flex: 1
          )
        ],
        title: "Skin & Controls",
        flex: 1
      )
    ])
  end

  defp render_center(_state) do
    split_pane(
      [
        box(
          [
            label("CPU", style: %{bold: true}),
            sparkline(
              id: :cpu_spark,
              buffer: :auto,
              height: 1,
              min_color: {80, 200, 100},
              max_color: {215, 60, 60}
            ),
            label(""),
            label("Memory", style: %{bold: true}),
            sparkline(
              id: :mem_spark,
              buffer: :auto,
              height: 1,
              min_color: {80, 140, 215},
              max_color: {215, 60, 60}
            ),
            label(""),
            label("Net RX", style: %{bold: true}),
            sparkline(
              id: :rx_spark,
              buffer: :auto,
              height: 1,
              min_color: {80, 200, 140},
              max_color: {80, 200, 140}
            ),
            label("Net TX", style: %{bold: true}),
            sparkline(
              id: :tx_spark,
              buffer: :auto,
              height: 1,
              min_color: {215, 140, 60},
              max_color: {215, 140, 60}
            )
          ],
          title: "History"
        ),
        box(
          [
            data_table(
              columns: [
                %{key: :name, label: "Service", width: 15},
                %{key: :status, label: "Status", width: 6},
                %{key: :latency, label: "Latency", width: 8, align: :right},
                %{key: :req_s, label: "Req/s", width: 6, align: :right}
              ],
              data: @services
            )
          ],
          title: "Services"
        )
      ],
      orientation: :vertical,
      ratio: 0.6,
      id: :center_split,
      resize_mode: :live
    )
  end

  defp render_right(_state) do
    vertical([
      box(
        [
          log(id: :event_log, buffer: 200)
        ],
        title: "Event Log",
        flex: 1
      )
    ])
  end

  defp clamp(v, lo, hi), do: max(lo, min(hi, v))

  defp gen_hist(count, base, spread) do
    Enum.map(1..count, fn _ -> clamp(:rand.uniform(spread) + base, 0, 100) end)
  end

  defp format_uptime(secs) do
    d = div(secs, 86_400)
    h = div(rem(secs, 86_400), 3600)
    m = div(rem(secs, 3600), 60)
    s = rem(secs, 60)
    "#{d}d #{h}h #{m}m #{s}s"
  end

  defp timestamp_prefix do
    {{_, _, _}, {h, m, s}} = :calendar.local_time()
    :io_lib.format("~2..0B:~2..0B:~2..0B ", [h, m, s]) |> to_string()
  end

  defp apply_skin(skin, state) do
    Drafter.set_skin(skin)
    Drafter.set_theme(Drafter.CharacterSet.preferred_theme(skin))
    %{state | current_skin: skin}
  end

  def handle_event(:skin_selected, skin, state), do: {:ok, apply_skin(skin, state)}
  def handle_event(_event, state), do: {:noreply, state}
end

Drafter.run(Dashboard)
