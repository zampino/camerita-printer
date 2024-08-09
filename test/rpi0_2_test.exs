defmodule Rpi02Test do
  use ExUnit.Case
  doctest Rpi02

  test "greets the world" do
    assert Rpi02.hello() == :world
  end
end
