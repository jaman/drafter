defmodule Drafter.Accounts.RegisterApp do
  @moduledoc """
  The form a new user fills in to create an account.

  Asks for a username, a password and its confirmation, creates the account in
  the `Drafter.Accounts` server given in `props.accounts`, and stops. The outcome
  is sent to `props.notify` (default: the loop process) as
  `{:drafter_registration, {:ok, account}}` or `{:drafter_registration, :cancelled}`.

  Tab moves between fields, Enter submits, Escape or ctrl+c cancels. A refusal from the
  store is shown above the form and the fields stay filled.

  ## Props

    * `:accounts` - the `Drafter.Accounts` server. Required.
    * `:notify` - the pid told the outcome. Default `self()` at mount.
    * `:title` - the heading. Default `"Create an account"`.
  """

  use Drafter.App, mouse_hover: false

  @impl true
  def mount(props) do
    %{
      accounts: Map.fetch!(props, :accounts),
      notify: Map.get(props, :notify, self()),
      title: Map.get(props, :title, "Create an account"),
      username: "",
      password: "",
      confirm: "",
      error: nil
    }
  end

  @impl true
  def on_ready(state) do
    Drafter.focus(:username)
    state
  end

  @impl true
  def render(state) do
    vertical(
      [
        label(state.title, style: %{bold: true}),
        rule(),
        label("Username  (letters, digits, _ and -; up to 32)"),
        text_input(id: :username, bind: :username),
        label("Password  (at least 8 characters)"),
        text_input(id: :password, bind: :password, password: true),
        label("Confirm password"),
        text_input(id: :confirm, bind: :confirm, password: true),
        error_line(state.error),
        horizontal([
          button("Register", on_click: :submit, variant: :primary),
          button("Cancel", on_click: :cancel)
        ]),
        footer(bindings: [{"Tab", "Next field"}, {"Enter", "Register"}, {"Esc", "Cancel"}])
      ],
      gap: 1
    )
  end

  @impl true
  def handle_event(:submit, _data, state) do
    case attempt(state) do
      {:ok, account} ->
        send(state.notify, {:drafter_registration, {:ok, account}})
        {:stop, :normal}

      {:error, message} ->
        {:ok, %{state | error: message}}
    end
  end

  def handle_event(:cancel, _data, state), do: cancel(state)
  def handle_event(_name, _data, state), do: {:noreply, state}

  @impl true
  def handle_event({:key, :enter}, state), do: handle_event(:submit, nil, state)
  def handle_event({:key, :escape}, state), do: cancel(state)
  def handle_event({:key, :c, [:ctrl]}, state), do: cancel(state)
  def handle_event(_event, state), do: {:noreply, state}

  defp cancel(state) do
    send(state.notify, {:drafter_registration, :cancelled})
    {:stop, :normal}
  end

  defp attempt(%{password: password, confirm: confirm}) when password != confirm do
    {:error, "The passwords do not match."}
  end

  defp attempt(state) do
    case Drafter.Accounts.register(state.accounts, state.username, state.password) do
      :ok ->
        Drafter.Accounts.fetch(state.accounts, state.username)

      {:error, :taken} ->
        {:error, "That name is already taken."}

      {:error, :invalid_username} ->
        {:error, "A username is 1 to 32 letters, digits, underscores or dashes."}

      {:error, :weak_password} ->
        {:error, "A password needs at least 8 characters."}
    end
  end

  defp error_line(nil), do: label("")
  defp error_line(message), do: label(message, style: %{fg: :red})
end
