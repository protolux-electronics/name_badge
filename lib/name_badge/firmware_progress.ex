defmodule NameBadge.FirmwareProgress do
  @moduledoc """
  Tracks firmware update state and notifies subscribers via Registry.

  States: `:idle`, `{:downloading, 0..100}`, `:rebooting`.
  Layout reads `state/0` synchronously during render. Screen processes
  subscribe to `:firmware_progress` for re-render triggers.
  """

  use Agent

  def start_link(_), do: Agent.start_link(fn -> :idle end, name: __MODULE__)

  def state, do: Agent.get(__MODULE__, & &1)

  def set_state(new_state) do
    Agent.update(__MODULE__, fn _ -> new_state end)

    Registry.dispatch(NameBadge.Registry, :firmware_progress, fn pids ->
      for {pid, _} <- pids, do: send(pid, {:firmware_progress, new_state})
    end)
  end

  def subscribe, do: Registry.register(NameBadge.Registry, :firmware_progress, nil)
end
