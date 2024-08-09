defmodule Camerita do

  @esc 0x1b
  @cr 0x0d
  @lf 0x0a

  def test_page, do: << @esc, 0x11, 0x04>>

  def write(data), do: Camerita.BLE.write(data)

  def print(text) do
    write(<< text::binary, @cr, @lf>>)
  end

  def reset() do
    GenServer.stop(Camerita.BLE, :restart)
  end

end
