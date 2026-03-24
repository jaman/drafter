Mix.install([{:drafter, path: Path.join(__DIR__, "..")}, {:elixir_make, "~> 0.9"}])

defmodule ChatStore do
  use GenServer

  @table :chat_messages

  def start_link, do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def post(channel, sender, text) do
    GenServer.call(__MODULE__, {:post, channel, sender, text})
  end

  def messages(channel) do
    :ets.select(@table, [{{:_, :_, :"$1", :_, :_}, [{:==, :"$1", channel}], [:"$_"]}])
    |> Enum.sort_by(&elem(&1, 0))
  end

  def messages_since(channel, since_index) do
    :ets.select(@table, [
      {{:"$1", :_, :"$2", :_, :_}, [{:andalso, {:>, :"$1", since_index}, {:==, :"$2", channel}}],
       [:"$_"]}
    ])
    |> Enum.sort_by(&elem(&1, 0))
  end

  def channels do
    :ets.foldl(
      fn {_, _, channel, _, _}, acc -> MapSet.put(acc, channel) end,
      MapSet.new(),
      @table
    )
    |> MapSet.to_list()
    |> Enum.sort()
  end

  @impl true
  def init(_) do
    table = :ets.new(@table, [:ordered_set, :named_table, :public, read_concurrency: true])

    :ets.insert(
      table,
      {0, System.system_time(:millisecond), "lobby", "system",
       "Welcome to Drafter Chat. Type /help for commands."}
    )

    {:ok, %{table: table, counter: 1}}
  end

  @impl true
  def handle_call({:post, channel, sender, text}, _from, state) do
    idx = state.counter
    :ets.insert(@table, {idx, System.system_time(:millisecond), channel, sender, text})
    Phoenix.PubSub.broadcast(Drafter.PubSub, "chat:#{channel}", {:new_message, channel})
    {:reply, idx, %{state | counter: idx + 1}}
  end
end

defmodule ChatApp do
  use Drafter.App
  import Drafter.App

  def mount(props) do
    username = Map.get(props, :username, "guest")
    channel = "lobby"
    Phoenix.PubSub.subscribe(Drafter.PubSub, "chat:#{channel}")

    %{
      username: username,
      channel: channel,
      input: "",
      render_seq: 0
    }
  end

  def on_ready(state) do
    Drafter.focus(:message_input)
    state
  end

  def on_message({:new_message, channel}, state) when channel == state.channel do
    %{state | render_seq: state.render_seq + 1}
  end

  def on_message(_, state), do: state

  def render(state) do
    rows = ChatStore.messages(state.channel)

    message_rows =
      Enum.map(rows, fn {_idx, _ts, _ch, sender, text} ->
        cond do
          sender == "system" ->
            label("  \u25cf #{text}", style: %{fg: :bright_black})

          sender == state.username ->
            horizontal([
              label("", flex: 1),
              label(" #{text} \u25c0 me ", style: %{fg: :green})
            ])

          true ->
            label(" #{sender} \u25b6 #{text}", style: %{fg: :yellow})
        end
      end)

    vertical([
      label(" ##{state.channel}  \u00b7  #{state.username}", style: %{fg: :cyan, bold: true}),
      rule(),
      scrollable(message_rows, flex: 1),
      text_input(
        id: :message_input,
        bind: :input,
        on_submit: :send_message,
        keep_focus: true,
        placeholder: "Type a message... (/help for commands)"
      ),
      footer(bindings: [{"Enter", "Send"}, {"/join #ch", "Switch"}, {"^C", "Quit"}])
    ])
  end

  def handle_event(:send_message, _text, state) do
    text = String.trim(state.input)

    cond do
      text == "" ->
        {:noreply, state}

      String.starts_with?(text, "/join ") ->
        new_channel =
          text |> String.trim_leading("/join ") |> String.trim_leading("#") |> String.trim()

        switch_channel(state, new_channel)

      String.starts_with?(text, "/channels") ->
        channels = ChatStore.channels() |> Enum.map_join(", ", &"##{&1}")
        ChatStore.post(state.channel, "system", "Active channels: #{channels}")
        {:ok, %{state | input: ""}}

      text == "/help" ->
        ChatStore.post(state.channel, "system", "Commands: /join #channel, /channels, /help")
        {:ok, %{state | input: ""}}

      true ->
        ChatStore.post(state.channel, state.username, String.replace(text, "\n", " "))
        {:ok, %{state | input: ""}}
    end
  end

  def handle_event({:key, :c, [:ctrl]}, _state), do: {:stop, :normal}
  def handle_event(_event, state), do: {:noreply, state}

  defp switch_channel(state, new_channel) when new_channel != "" do
    Phoenix.PubSub.unsubscribe(Drafter.PubSub, "chat:#{state.channel}")
    Phoenix.PubSub.subscribe(Drafter.PubSub, "chat:#{new_channel}")
    {:ok, %{state | channel: new_channel, input: "", render_seq: 0}}
  end

  defp switch_channel(state, _), do: {:noreply, state}
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
ChatStore.start_link()

{:ok, _} =
  Drafter.Server.start_ssh(ChatApp,
    port: 2222,
    ip: ip_tuple,
    mode: :isolated,
    auth: [
      {"alice", "pass"},
      {"bob", "pass"},
      {"carol", "pass"},
      {"guest", "pass"}
    ]
  )

Process.sleep(:infinity)
