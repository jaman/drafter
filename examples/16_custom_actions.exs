Mix.install([{:drafter, path: Path.join(__DIR__, "..")}])

defmodule Example.DesktopNotify do
  @spec send(String.t(), String.t()) :: :ok
  def send(title, message) do
    case :os.type() do
      {:unix, :darwin} ->
        script = ~s(display notification "#{escape(message)}" with title "#{escape(title)}")
        System.cmd("osascript", ["-e", script], stderr_to_stdout: true)
        :ok

      {:unix, _} ->
        System.cmd("notify-send", [title, message], stderr_to_stdout: true)
        :ok

      {:win32, _} ->
        ps_script = windows_toast_script(escape(title), escape(message))

        System.cmd("powershell", ["-NoProfile", "-NonInteractive", "-Command", ps_script],
          stderr_to_stdout: true
        )

        :ok
    end
  end

  defp escape(str), do: String.replace(str, ~s("), ~s(\\"))

  defp windows_toast_script(title, message) do
    """
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    $template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
    $nodes = $template.GetElementsByTagName('text')
    $nodes.Item(0).AppendChild($template.CreateTextNode('#{title}')) | Out-Null
    $nodes.Item(1).AppendChild($template.CreateTextNode('#{message}')) | Out-Null
    $toast = [Windows.UI.Notifications.ToastNotification]::new($template)
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Drafter').Show($toast)
    """
  end
end

defmodule Example.EventFeedHandler do
  @behaviour Drafter.ActionHandler

  @max_events 100

  @impl true
  def handle_action({:add_event, message, level}, acc_state) do
    if level == :critical do
      Example.DesktopNotify.send("Drafter Alert", message)
    end

    event = %{message: message, level: level, at: DateTime.utc_now()}
    events = [event | Map.get(acc_state, :events, [])] |> Enum.take(@max_events)

    {:ok, %{acc_state | events: events}}
  end

  def handle_action(_action, _acc_state), do: :unhandled
end

Drafter.ActionRegistry.register(Example.EventFeedHandler)

defmodule EventFeedApp do
  use Drafter.App
  import Drafter.App

  def mount(_props), do: %{events: []}

  def render(state) do
    rows =
      state.events
      |> Enum.map(fn event ->
        {color, tag} =
          case event.level do
            :info -> {:cyan, " INFO "}
            :success -> {:green, "  OK  "}
            :warning -> {:yellow, " WARN "}
            :error -> {:red, " ERR  "}
            :critical -> {:bright_red, " CRIT "}
          end

        time = Calendar.strftime(event.at, "%H:%M:%S")

        horizontal([
          label(time, style: %{fg: :bright_black}),
          label(" "),
          label(tag, style: %{fg: color, bold: true}),
          label("  #{event.message}")
        ])
      end)

    feed =
      if rows == [],
        do: [label("No events yet. Use the buttons below.", style: %{fg: :bright_black})],
        else: rows

    vertical([
      header("Event Feed  ·  Custom Action Handler Demo"),
      scrollable(feed, flex: 1),
      rule(),
      label("Fire an event:", style: %{fg: :bright_black}),
      horizontal(
        [
          button("Info", on_click: :fire_info),
          button("Success", on_click: :fire_success, variant: :success),
          button("Warning", on_click: :fire_warning, variant: :warning),
          button("Error", on_click: :fire_error, variant: :error),
          button("Critical", on_click: :fire_critical, variant: :error)
        ],
        gap: 1
      ),
      label(
        "Critical level also triggers a native desktop notification.",
        style: %{fg: :bright_black}
      ),
      footer(bindings: [{"q", "quit"}])
    ])
  end

  def handle_event(:fire_info, _data, _state),
    do: {:add_event, "Informational event fired", :info}

  def handle_event(:fire_success, _data, _state),
    do: {:add_event, "Operation completed successfully", :success}

  def handle_event(:fire_warning, _data, _state),
    do: {:add_event, "Something may need your attention", :warning}

  def handle_event(:fire_error, _data, _state),
    do: {:add_event, "An error occurred in the subsystem", :error}

  def handle_event(:fire_critical, _data, _state),
    do: {:add_event, "CRITICAL: immediate action required", :critical}

  def handle_event(_widget_event, _data, state), do: {:noreply, state}

  def handle_event({:key, :q}, _state), do: {:stop, :normal}
  def handle_event(_event, state), do: {:noreply, state}
end

Drafter.run(EventFeedApp)
