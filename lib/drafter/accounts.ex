defmodule Drafter.Accounts do
  @moduledoc """
  A file-backed store of user accounts for a served application.

  Passwords are kept as PBKDF2-HMAC-SHA256 hashes with a random salt per account;
  the file never holds a password. Usernames are unique without regard to case
  and are returned in the spelling they were registered with. Each account carries
  a `props` map the application owns.

      {:ok, accounts} = Drafter.Accounts.start_link(path: "/var/lib/game/accounts.terms")
      :ok = Drafter.Accounts.register(accounts, "alice", "correct horse")
      {:ok, %{username: "alice", props: %{}}} = Drafter.Accounts.authenticate(accounts, "alice", "correct horse")

  `authenticate/4` costs the same for an unknown name as for a wrong password, and
  refuses a peer outright, without hashing, once it has failed five times in
  fifteen minutes.

  ## Rules

    * a username is 1 to 32 characters from `A-Z`, `a-z`, `0-9`, `_` and `-`
    * a password is at least 8 characters
    * every change is written to the file before the call returns, by writing a
      sibling file and renaming it over the old one
    * the file is text: one Erlang term per account, in registration order, that
      `:file.consult/1` reads — `%{username: "alice", number: 0, props: %{…}, hash:
      <<…>>, salt: <<…>>, iterations: 300000}` — so it can be read and searched as it
      is; a file written as `:erlang.term_to_binary/1` by an earlier version is read and
      written back as text
  """

  use GenServer

  alias Drafter.Accounts.Throttle

  @type username :: String.t()
  @type account :: %{username: username(), props: map()}
  @type register_error :: :taken | :invalid_username | :weak_password

  @default_iterations 300_000
  @hash_bytes 32
  @salt_bytes 16
  @min_password 8
  @username_pattern ~r/\A[A-Za-z0-9_-]{1,32}\z/

  @doc """
  Start the store, loading `path` if it exists.

  ## Options

    * `:path` - the file to load and write. Required.
    * `:name` - a GenServer name. Default: none.
    * `:iterations` - PBKDF2 rounds for new hashes. Default `300_000`. An account
      keeps the count it was hashed with, so raising this later affects only new
      passwords.
    * `:throttle` - options for `Drafter.Accounts.Throttle.new/1`. Default `[]`.
    * `:default_props` - a function from an account's number (0 for the first
      registered, then 1, 2, …; accounts from a file without numbers are numbered in
      name order when loaded) to props every account has unless its own props say
      otherwise. Default: none.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Create an account. Returns `:ok`, or `{:error, reason}` with `:taken`,
  `:invalid_username` or `:weak_password`.
  """
  @spec register(GenServer.server(), username(), String.t(), map()) ::
          :ok | {:error, register_error()}
  def register(server, username, password, props \\ %{}) do
    with :ok <- validate_username(username),
         :ok <- validate_password(password) do
      GenServer.call(server, {:register, username, password, props})
    end
  end

  @doc """
  Check a username and password.

  Returns `{:ok, account}`, `:error` for a wrong password or unknown name, or
  `{:error, :locked}` for a peer that has failed too often.

  ## Options

    * `:peer` - the caller's address, any term, counted by the throttle. Default
      `nil`, which is never locked.
  """
  @spec authenticate(GenServer.server(), username(), String.t(), keyword()) ::
          {:ok, account()} | :error | {:error, :locked}
  def authenticate(server, username, password, opts \\ []) do
    GenServer.call(
      server,
      {:authenticate, username, password, Keyword.get(opts, :peer)},
      :infinity
    )
  end

  @doc "Merge `props` into the account's props. `{:error, :unknown}` for no such account."
  @spec put_props(GenServer.server(), username(), map()) :: :ok | {:error, :unknown}
  def put_props(server, username, props) when is_map(props) do
    GenServer.call(server, {:put_props, username, props})
  end

  @doc "Replace the password, given the current one. `:error` when it does not match."
  @spec change_password(GenServer.server(), username(), String.t(), String.t()) ::
          :ok | :error | {:error, :weak_password}
  def change_password(server, username, current, new_password) do
    with :ok <- validate_password(new_password) do
      GenServer.call(server, {:change_password, username, current, new_password}, :infinity)
    end
  end

  @doc "The account under `username`, without checking a password."
  @spec fetch(GenServer.server(), username()) :: {:ok, account()} | :error
  def fetch(server, username), do: GenServer.call(server, {:fetch, username})

  @impl GenServer
  def init(opts) do
    path = Keyword.fetch!(opts, :path)

    state = %{
      path: path,
      iterations: Keyword.get(opts, :iterations, @default_iterations),
      accounts: load(path),
      throttle: Throttle.new(Keyword.get(opts, :throttle, [])),
      default_props: Keyword.get(opts, :default_props, fn _number -> %{} end),
      decoy: %{
        salt: :crypto.strong_rand_bytes(@salt_bytes),
        iterations: Keyword.get(opts, :iterations, @default_iterations)
      }
    }

    case numbered(state.accounts) do
      same when same == state.accounts -> {:ok, state}
      renumbered -> {:ok, store(state, renumbered)}
    end
  end

  defp numbered(accounts) do
    next =
      accounts
      |> Map.values()
      |> Enum.map(&Map.get(&1, :number, -1))
      |> Enum.max(fn -> -1 end)
      |> Kernel.+(1)

    accounts
    |> Enum.sort_by(fn {key, _record} -> key end)
    |> Enum.reduce({accounts, next}, fn {key, record}, {acc, n} ->
      if Map.has_key?(record, :number),
        do: {acc, n},
        else: {Map.put(acc, key, Map.put(record, :number, n)), n + 1}
    end)
    |> elem(0)
  end

  @impl GenServer
  def handle_call({:register, username, password, props}, _from, state) do
    key = key_of(username)

    if Map.has_key?(state.accounts, key) do
      {:reply, {:error, :taken}, state}
    else
      number =
        state.accounts
        |> Map.values()
        |> Enum.map(& &1.number)
        |> Enum.max(fn -> -1 end)
        |> Kernel.+(1)

      record = new_record(username, password, props, number, state.iterations)
      {:reply, :ok, store(state, Map.put(state.accounts, key, record))}
    end
  end

  def handle_call({:authenticate, username, password, peer}, _from, state) do
    now = System.monotonic_time(:millisecond)

    cond do
      peer != nil and Throttle.locked?(state.throttle, peer, now) ->
        {:reply, {:error, :locked}, state}

      verify(state, username, password) ->
        {:reply, {:ok, public(Map.fetch!(state.accounts, key_of(username)), state)},
         %{state | throttle: Throttle.succeeded(state.throttle, peer)}}

      true ->
        {:reply, :error, %{state | throttle: note_failure(state.throttle, peer, now)}}
    end
  end

  def handle_call({:put_props, username, props}, _from, state) do
    case Map.fetch(state.accounts, key_of(username)) do
      {:ok, record} ->
        updated = %{record | props: Map.merge(record.props, props)}
        {:reply, :ok, store(state, Map.put(state.accounts, key_of(username), updated))}

      :error ->
        {:reply, {:error, :unknown}, state}
    end
  end

  def handle_call({:change_password, username, current, new_password}, _from, state) do
    if verify(state, username, current) do
      key = key_of(username)
      record = Map.fetch!(state.accounts, key)
      rehashed = Map.merge(record, hash_fields(new_password, state.iterations))
      {:reply, :ok, store(state, Map.put(state.accounts, key, rehashed))}
    else
      {:reply, :error, state}
    end
  end

  def handle_call({:fetch, username}, _from, state) do
    case Map.fetch(state.accounts, key_of(username)) do
      {:ok, record} -> {:reply, {:ok, public(record, state)}, state}
      :error -> {:reply, :error, state}
    end
  end

  defp note_failure(throttle, nil, _now), do: throttle
  defp note_failure(throttle, peer, now), do: Throttle.failed(throttle, peer, now)

  defp verify(state, username, password) do
    case Map.fetch(state.accounts, key_of(username)) do
      {:ok, record} ->
        :crypto.hash_equals(derive(password, record.salt, record.iterations), record.hash)

      :error ->
        _ = derive(password, state.decoy.salt, state.decoy.iterations)
        false
    end
  end

  defp new_record(username, password, props, number, iterations) do
    Map.merge(
      %{username: username, props: props, number: number},
      hash_fields(password, iterations)
    )
  end

  defp hash_fields(password, iterations) do
    salt = :crypto.strong_rand_bytes(@salt_bytes)
    %{salt: salt, iterations: iterations, hash: derive(password, salt, iterations)}
  end

  defp derive(password, salt, iterations) do
    :crypto.pbkdf2_hmac(:sha256, password, salt, iterations, @hash_bytes)
  end

  defp public(record, state) do
    %{
      username: record.username,
      props: Map.merge(state.default_props.(record.number), record.props)
    }
  end

  defp key_of(username), do: String.downcase(username)

  defp validate_username(username) when is_binary(username) do
    if Regex.match?(@username_pattern, username), do: :ok, else: {:error, :invalid_username}
  end

  defp validate_username(_username), do: {:error, :invalid_username}

  defp validate_password(password)
       when is_binary(password) and byte_size(password) >= @min_password,
       do: :ok

  defp validate_password(_password), do: {:error, :weak_password}

  defp load(path) do
    case :file.consult(path) do
      {:ok, records} -> Map.new(records, fn record -> {key_of(record.username), record} end)
      {:error, :enoent} -> %{}
      {:error, _not_terms} -> path |> File.read!() |> :erlang.binary_to_term()
    end
  end

  defp store(state, accounts) do
    tmp = state.path <> ".tmp"
    File.mkdir_p!(Path.dirname(state.path))
    File.write!(tmp, text(accounts))
    File.rename!(tmp, state.path)
    %{state | accounts: accounts}
  end

  defp text(accounts) do
    accounts
    |> Map.values()
    |> Enum.sort_by(& &1.number)
    |> Enum.map(fn record -> :io_lib.format("~p.~n", [record]) end)
  end
end
