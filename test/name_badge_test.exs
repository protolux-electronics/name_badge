defmodule NameBadgeTest do
  use ExUnit.Case
  doctest NameBadge

  test "greets the world" do
    assert NameBadge.hello() == :world
  end
end
