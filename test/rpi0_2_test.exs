defmodule CameritaTest do
  use ExUnit.Case
  doctest Camerita

  test "greets the world" do
    assert Camerita.hello() == :world
  end
end
