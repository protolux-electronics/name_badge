defmodule NameBadge do
  @moduledoc """
  Documentation for `NameBadge`.
  """

  @doc """
  Hello world.

  ## Examples

      iex> NameBadge.hello()
      :world

  """
  def hello do
    :world
  end

  def ssh_check_pass(_provided_username, provided_password) do
    correct_password = Application.get_env(:name_badge, :password, "nerves")

    provided_password == to_charlist(correct_password)
  end

  def ssh_show_prompt(_peer, _username, _service) do
    {:ok, name} = :inet.gethostname()

    msg = """
    https://github.com/protolux-electronics/name_badge

    ssh nerves@#{name}.local # Use password "nerves"
    """

    {~c"Protolux Goatmire Name Badge", to_charlist(msg), ~c"Password: ", false}
  end

end
