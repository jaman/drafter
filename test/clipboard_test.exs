defmodule Drafter.ClipboardTest do
  @moduledoc """
  Copying reaches the terminal the user is actually looking at, and pasted text
  cannot carry escape sequences into a widget.
  """

  use ExUnit.Case, async: false

  alias Drafter.Clipboard
  alias Drafter.Compositor
  alias Drafter.Event

  defmodule RecordingDriver do
    @moduledoc false
    use GenServer

    def start_link(parent), do: GenServer.start_link(__MODULE__, parent)
    def write(server, data), do: GenServer.cast(server, {:write, data})
    def get_size(_server), do: {80, 24}

    @impl true
    def init(parent), do: {:ok, parent}

    @impl true
    def handle_cast({:write, data}, parent) do
      send(parent, {:written, IO.iodata_to_binary(data)})
      {:noreply, parent}
    end
  end

  setup do
    original = Application.get_env(:drafter, :clipboard)

    on_exit(fn ->
      case original do
        nil -> Application.delete_env(:drafter, :clipboard)
        value -> Application.put_env(:drafter, :clipboard, value)
      end
    end)

    :ok
  end

  defp with_recording_compositor(fun) do
    {:ok, driver} = RecordingDriver.start_link(self())
    {:ok, em} = Event.Manager.start_link(name: nil)

    {:ok, comp} =
      Compositor.start_link(
        name: nil,
        terminal_driver: {RecordingDriver, driver},
        event_manager: em
      )

    Process.put(:drafter_compositor, comp)

    try do
      fun.()
    after
      GenServer.stop(comp, :normal, 1000)
      GenServer.stop(em, :normal, 1000)
      GenServer.stop(driver, :normal, 1000)
    end
  end

  describe "osc52/2" do
    test "encodes the text for the clipboard selection" do
      assert Clipboard.osc52("hi") == "\e]52;c;#{Base.encode64("hi")}\a"
    end

    test "addresses the primary selection when asked" do
      assert Clipboard.osc52("hi", :primary) == "\e]52;p;#{Base.encode64("hi")}\a"
    end

    test "survives a round trip through base64" do
      text = "multi\nline — with ünicode"

      assert ["\e]52;c;" <> rest] = [Clipboard.osc52(text)]
      payload = rest |> String.trim_trailing("\a")

      assert Base.decode64!(payload) == text
    end
  end

  describe "copy/2" do
    test "writes the sequence to this session's terminal, not the server's tty" do
      with_recording_compositor(fn ->
        assert Clipboard.copy("remote text") == :ok

        assert_receive {:written, data}, 1000
        assert data == Clipboard.osc52("remote text")
      end)
    end

    test "is a no-op that says so when clipboard access is off" do
      Application.put_env(:drafter, :clipboard, false)

      with_recording_compositor(fn ->
        assert Clipboard.copy("nope") == {:error, :disabled}
        refute_receive {:written, _}, 200
      end)
    end

    test "refuses text past what an OSC 52 sequence can carry" do
      with_recording_compositor(fn ->
        assert Clipboard.copy(String.duplicate("x", 80_000)) == {:error, :too_large}
        refute_receive {:written, _}, 200
      end)
    end

    test "does not raise when there is no compositor for the session" do
      Process.delete(:drafter_compositor)

      assert Clipboard.copy("no session") == :ok
    end
  end

  describe "paste/0" do
    test "reports disabled rather than reading when clipboard access is off" do
      Application.put_env(:drafter, :clipboard, false)

      assert Clipboard.paste() == {:error, :disabled}
    end

    test "returns a string or a reason, never raises" do
      assert match?({:ok, text} when is_binary(text), Clipboard.paste()) or
               Clipboard.paste() == {:error, :unavailable}
    end
  end

  describe "sanitize/1" do
    test "strips the escape sequences that would turn a paste into keystrokes" do
      assert Clipboard.sanitize("be\e[31mfore\e]52;c;x\aafter") == "be[31mfore]52;c;xafter"
    end

    test "keeps newlines and tabs" do
      assert Clipboard.sanitize("one\ntwo\tthree") == "one\ntwo\tthree"
    end

    test "normalises carriage returns so a paste does not double-space" do
      assert Clipboard.sanitize("one\r\ntwo\rthree") == "one\ntwo\nthree"
    end

    test "leaves ordinary text alone, including unicode" do
      assert Clipboard.sanitize("héllo — 世界 🎉") == "héllo — 世界 🎉"
    end

    test "removes DEL and other control bytes" do
      assert Clipboard.sanitize("a\x7Fb\x01c") == "abc"
    end
  end

  describe "blocking paste" do
    defp subscribed_manager do
      {:ok, manager} = Event.Manager.start_link(name: nil)
      Event.Manager.subscribe_to(manager, self(), :all)
      on_exit(fn -> if Process.alive?(manager), do: GenServer.stop(manager, :normal, 1000) end)
      manager
    end

    defp send_paste(manager) do
      GenServer.cast(manager, {:event, {:bracketed_paste, "pasted"}})
      Event.Manager.sync(manager)
    end

    test "pasted text reaches subscribers by default" do
      Application.delete_env(:drafter, :clipboard)
      send_paste(subscribed_manager())

      assert_receive {:tui_event, {:bracketed_paste, "pasted"}}, 500
    end

    test "no subscriber sees the text when paste is switched off" do
      Application.put_env(:drafter, :clipboard, paste: false)
      send_paste(subscribed_manager())

      refute_receive {:tui_event, {:bracketed_paste, _}}, 300
    end

    test "switching off copy alone leaves paste flowing" do
      Application.put_env(:drafter, :clipboard, copy: false)
      send_paste(subscribed_manager())

      assert_receive {:tui_event, {:bracketed_paste, "pasted"}}, 500
      refute Clipboard.enabled?()
      assert Clipboard.paste_enabled?()
    end

    test "switching everything off blocks both directions" do
      Application.put_env(:drafter, :clipboard, false)

      refute Clipboard.enabled?()
      refute Clipboard.paste_enabled?()
    end

    test "other events are unaffected by the paste switch" do
      Application.put_env(:drafter, :clipboard, paste: false)
      manager = subscribed_manager()

      GenServer.cast(manager, {:event, {:key, :a}})
      Event.Manager.sync(manager)

      assert_receive {:tui_event, {:key, :a}}, 500
    end
  end

  describe "key bindings" do
    test "the defaults match the shape a terminal actually produces" do
      Application.delete_env(:drafter, :clipboard_keys)

      assert Clipboard.key(:copy) == {:c, [:ctrl]}
      assert Clipboard.key?(:copy, :c, [:ctrl])
      refute Clipboard.key?(:copy, :c, [])
    end

    test "an override replaces the default and frees the old key" do
      Application.put_env(:drafter, :clipboard_keys, copy: {:y, [:ctrl, :shift]})

      assert Clipboard.key(:copy) == {:y, [:ctrl, :shift]}
      assert Clipboard.key?(:copy, :y, [:shift, :ctrl])
      refute Clipboard.key?(:copy, :c, [:ctrl])

      Application.delete_env(:drafter, :clipboard_keys)
    end

    test "false unbinds an action entirely" do
      Application.put_env(:drafter, :clipboard_keys, copy: false)

      assert Clipboard.key(:copy) == nil
      refute Clipboard.key?(:copy, :c, [:ctrl])

      Application.delete_env(:drafter, :clipboard_keys)
    end

    test "overriding one action leaves the others at their defaults" do
      Application.put_env(:drafter, :clipboard_keys, copy: {:y, [:ctrl]})

      assert Clipboard.key(:cut) == {:x, [:ctrl]}
      assert Clipboard.key(:paste) == {:v, [:ctrl]}

      Application.delete_env(:drafter, :clipboard_keys)
    end
  end

  describe "enabled?/0" do
    test "defaults to on" do
      Application.delete_env(:drafter, :clipboard)

      assert Clipboard.enabled?()
    end

    test "is off only for an explicit false" do
      Application.put_env(:drafter, :clipboard, false)
      refute Clipboard.enabled?()

      Application.put_env(:drafter, :clipboard, true)
      assert Clipboard.enabled?()
    end
  end
end
