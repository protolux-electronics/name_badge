defmodule NameBadge.ScheduleAPI do
  @url "https://sessionize.com/api/v2/42rcx5he/view/All"
  @save_path "/data/schedule.bin"
  @timezone "Europe/Stockholm"

  def get(opts \\ []) do
    image_size = Keyword.get(opts, :image_size, 32)

    {:ok, %{body: %{"speakers" => speakers, "sessions" => sessions}}} = Req.get(@url)

    speakers =
      for speaker <- speakers, into: %{} do
        img =
          case speaker["profilePicture"] do
            url when is_binary(url) ->
              {:ok, %{body: bytes}} = Req.get(url)

              {:ok, img} = Dither.decode(bytes)
              {:ok, img} = Dither.resize(img, image_size, image_size)
              {:ok, img} = Dither.dither(img, algorithm: :atkinson)
              {:ok, img} = Dither.encode(img)

              Base.encode64(img)

            nil ->
              nil
          end

        {speaker["id"], %{name: speaker["fullName"], photo: img}}
      end

    for session <- sessions do
      %{
        title: session["title"],
        starts_at:
          NaiveDateTime.from_iso8601!(session["startsAt"])
          |> DateTime.from_naive!(@timezone),
        ends_at:
          NaiveDateTime.from_iso8601!(session["endsAt"])
          |> DateTime.from_naive!(@timezone),
        speakers: session["speakers"] |> Enum.map(&speakers[&1])
      }
    end
  end

  def save(schedule) do
    # This is not a good way to do this - definitely a security issue. But
    # time is running out to complete this project and this data structure
    # doesn't want to encode to json for some reason. Sooo... c'est la vie

    content = :erlang.term_to_binary(schedule)
    File.write(@save_path, content, [:write, :binary])
  end

  def load() do
    File.read(@save_path)
    |> case do
      {:error, _reason} -> nil
      {:ok, data} -> :erlang.binary_to_term(data)
    end
  end

  def next_sessions(schedule) do
    now = DateTime.now!(@timezone)

    schedule
    |> Enum.filter(&(DateTime.compare(&1.ends_at, now) == :gt))
    |> Enum.sort_by(& &1.starts_at, DateTime)
  end
end
