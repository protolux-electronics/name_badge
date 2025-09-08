defmodule NameBadge.ScheduleUpdater do
  use GenServer

  alias NameBadge.ScheduleAPI

  require Logger

  def start_link(args \\ []), do: GenServer.start_link(__MODULE__, args, name: __MODULE__)

  @impl true
  def init(_opts) do
    # every 5 minutes
    timer = :timer.send_interval(5 * 60 * 1000, :update)

    if is_nil(ScheduleAPI.load()) do
      Logger.error("No previously saved schedule found. Loading the default")

      default_schedule =
        Application.app_dir(:name_badge, "priv/default_schedule.bin")
        |> File.read!()
        |> :erlang.binary_to_term()

      ScheduleAPI.save(default_schedule)
    end

    {:ok, %{timer: timer}}
  end

  @impl true
  def handle_info(:update, state) do
    # This will either succeed if connected, or it
    # will crash and fail.
    # However, since it is a task, it shouldn't kill the whole application
    Task.start(fn ->
      Logger.info("Attempting to update schedule")

      NameBadge.ScheduleAPI.get()
      |> NameBadge.ScheduleAPI.save()
    end)

    {:noreply, state}
  end
end
