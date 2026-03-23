defmodule Drafter.Server do
  @moduledoc """
  Start SSH and Telnet servers for hosting TUI applications over the network.

  Each connecting client gets their own session. Two modes are supported:

  - `:isolated` (default) — each client runs an independent app instance with
    its own state. Ideal for single-user tools, games, and dashboards.

  - `:shared` — all clients share the same app state. Input from any client
    mutates the shared state and all clients re-render. Ideal for collaborative
    apps, multi-player games, and shared dashboards.

  ## SSH Example

      Drafter.Server.start_ssh(ChatApp,
        port: 2222,
        mode: :shared,
        auth: [{"alice", "pass1"}, {"bob", "pass2"}]
      )

  ## Telnet Example

      Drafter.Server.start_telnet(MyApp, port: 2323, mode: :isolated)

  ## Generating SSH host keys

  If no `system_dir:` is provided, host keys are automatically generated and
  cached in a temp directory. For production use, generate persistent keys:

      ssh-keygen -t rsa -b 2048 -f /etc/drafter/ssh_host_rsa_key -N ""

  Then pass `system_dir: "/etc/drafter"`.
  """

  alias Drafter.Transport

  @doc """
  Start an SSH server hosting the given app module.

  ## Options

    - `:port` - TCP port (default: `2222`)
    - `:mode` - `:isolated` or `:shared` (default: `:isolated`)
    - `:auth` - `[{username, password}]` tuples for password authentication
      (default: `[{"admin", "admin"}]`)
    - `:system_dir` - path to SSH host key directory. Auto-generated if omitted.
    - `:mount_props` - map merged into props passed to `mount/1` for each session
  """
  @spec start_ssh(module(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_ssh(app_module, opts \\ []) do
    Transport.SSH.start_link(app_module, opts)
  end

  @doc """
  Start a Telnet server hosting the given app module.

  ## Options

    - `:port` - TCP port (default: `2323`)
    - `:mode` - `:isolated` or `:shared` (default: `:isolated`)
    - `:mount_props` - map merged into props passed to `mount/1` for each session
  """
  @spec start_telnet(module(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_telnet(app_module, opts \\ []) do
    Transport.Telnet.start_link(app_module, opts)
  end
end
