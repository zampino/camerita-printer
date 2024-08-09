defmodule Camerita.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do

    configure_wifi!()

    children =
      [

        {Camerita.Comm, %{url: Nerves.Runtime.KV.get("remote_camera_ws_url")}}

        ] ++ children(Nerves.Runtime.mix_target())

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Camerita.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # List all child processes to be supervised
  defp children(:host) do
    [
      # Children that only run on the host
    ]
  end

  defp children(_target) do
    [
      {Camerita.BLE, %{device: "ttyS0"}}
    ]
  end

  def configure_wifi! do
    unless VintageNet.get_configuration("wlan0") |> VintageNetWiFi.network_configured?() do
      kv = Nerves.Runtime.KV.get_all()
      :ok = VintageNetWiFi.quick_configure(kv["wifi_ssid"], kv["wifi_passphrase"])
      # blink indefinitely
      Delux.render(Delux.Effects.blink(:green, 2))
    end
  end

end
