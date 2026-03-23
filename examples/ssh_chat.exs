Mix.install([{:drafter, path: Path.join(__DIR__, "..")}, {:elixir_make, "~> 0.9"}])

defmodule ChatApp do
  use Drafter.App
  import Drafter.App

  def mount(props) do
    username = Map.get(props, :username, "guest")

    %{
      messages: [
        %{user: "system", text: "Welcome to Drafter Chat. Type a message and press Enter."}
      ],
      input: "",
      username: username
    }
  end

  def on_ready(state) do
    Drafter.focus(:message_input)
    Drafter.set_interval(30_000, :heartbeat)
    state
  end

  def on_timer(:heartbeat, state), do: state
  def on_timer(_, state), do: state

  def render(state) do
    message_rows =
      Enum.map(state.messages, fn msg ->
        case msg.user do
          "system" ->
            label("  \u25cf #{msg.text}", style: %{fg: :bright_black}, flex: 1)

          user when user == state.username ->
            horizontal([
              label("", flex: 1),
              label(" #{msg.user} \u25b6: #{msg.text} ", style: %{fg: :green})
            ])

          _other ->
            label(" \u25c0 #{msg.user}: #{msg.text}", style: %{fg: :yellow}, flex: 1)
        end
      end)

    vertical([
      label(" Drafter Chat  \u00b7  #{state.username}", style: %{fg: :cyan, bold: true}),
      rule(),
      scrollable(message_rows, flex: 1),
      rule(),
      horizontal([
        label(" #{state.username} \u25b6: ", style: %{fg: :green}),
        text_input(id: :message_input, bind: :input, on_submit: :send_message, keep_focus: true, flex: 1, placeholder: "Type a message...")
      ])
    ])
  end

  def handle_event(:send_message, _text, state) do
    text = String.trim(state.input)

    if text == "" do
      {:noreply, state}
    else
      msg = %{user: state.username, text: text}
      {:ok, %{state | messages: state.messages ++ [msg], input: ""}}
    end
  end

  def handle_event({:key, :c, [:ctrl]}, _state), do: {:stop, :normal}
  def handle_event(_event, state), do: {:noreply, state}
end

ip = System.get_env("CHAT_IP", "127.0.0.1")

ip_tuple =
  ip
  |> String.split(".")
  |> Enum.map(&String.to_integer/1)
  |> List.to_tuple()

IO.puts("""
Starting Drafter Chat SSH server on #{ip}:2222.

Connect with:  ssh -p 2222 alice@#{ip}
Password:      pass

Press Ctrl+C twice to stop the server.
""")

:application.ensure_all_started(:ssh)

{:ok, _} =
  Drafter.Server.start_ssh(ChatApp,
    port: 2222,
    ip: ip_tuple,
    mode: :shared,
    auth: [
      {"alice", "pass"},
      {"bob", "pass"},
      {"carol", "pass"},
      {"guest", "pass"}
    ]
  )

Process.sleep(:infinity)
