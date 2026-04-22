if Mix.target() != :host do
  defmodule NameBadge.FirmwareClient do
    @moduledoc """
    Custom NervesHubLink.Client that pushes firmware download progress
    and reboot state into FirmwareProgress. Delays reboot by 3 seconds
    so the screen can render a "Rebooting..." message first.
    """

    use NervesHubLink.Client

    @impl NervesHubLink.Client
    def handle_fwup_message({:progress, percent}) do
      NameBadge.FirmwareProgress.set_state({:downloading, percent})
    end

    def handle_fwup_message({:ok, 0, _}) do
      NameBadge.FirmwareProgress.set_state(:rebooting)
    end

    def handle_fwup_message(msg), do: super(msg)

    # Called in a spawned process by NervesHubLink.Client.initiate_reboot/0
    # Sleep gives the screen time to render "Rebooting..." before restart
    @impl NervesHubLink.Client
    def reboot do
      Process.sleep(3_000)
      Nerves.Runtime.reboot()
    end
  end
end
