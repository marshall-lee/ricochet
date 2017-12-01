defmodule RicochetTest do
  use ExUnit.Case
  doctest Ricochet

  test "greets the world" do
    assert Ricochet.hello() == :world
  end
end
