defmodule Camerita.BLE do
  @moduledoc """
    Camerita Bluetooth connection manager
  """

  use GenServer
  require Logger

  alias BlueHeron.HCI.Command.{
    ControllerAndBaseband.WriteLocalName,
    LEController.SetScanEnable
  }

  alias BlueHeron.HCI.Event.{
    LEMeta.ConnectionComplete,
    DisconnectionComplete,
    LEMeta.AdvertisingReport,
    LEMeta.AdvertisingReport.Device
  }

  # Sets the name of the BLE device
  @write_local_name %WriteLocalName{name: "Camerita Printer"}

  @default_uart_config %{
    device: "ttyS0",
    uart_opts: [speed: 115_200],
    init_commands: [@write_local_name]
  }

  def start_link(config) do
    config = struct(BlueHeronTransportUART, Map.merge(@default_uart_config, config))
    GenServer.start_link(__MODULE__, config, [name: __MODULE__])
  end

  def write(data) do
    GenServer.call(__MODULE__, {:write, data})
  end
  def get_info() do
    GenServer.call(__MODULE__, :get_info)
  end
  def set_handle(handle) do
    GenServer.call(__MODULE__, {:set_handle, handle})
  end
  def apply(f), do: GenServer.call(__MODULE__, {:apply, f})

  @impl GenServer
  def init(config) do
    # Create a context for BlueHeron to operate with
    {:ok, ctx} = BlueHeron.transport(config)

    # Subscribe to HCI and ACL events
    BlueHeron.add_event_handler(ctx)

    # Start the ATT Client (this is what we use to read/write data with)
    {:ok, conn} = BlueHeron.ATT.Client.start_link(ctx)

    {:ok,
     %{conn: conn,
       ctx: ctx,
       connected?: false,
       printer_reachable?: false,
       printer_address: nil,
       connection_handle: nil,
       write_handle: 0x000c}}
  end

  @impl GenServer

  # Sent when a transport connection is established
  def handle_info({:BLUETOOTH_EVENT_STATE, :HCI_STATE_WORKING}, state) do
    # Enable BLE Scanning. This will deliver messages to the process mailbox
    # when other devices broadcast
    BlueHeron.hci_command(state.ctx, %SetScanEnable{le_scan_enable: true})
    {:noreply, state}
  end

  def handle_info(
        {:HCI_EVENT_PACKET,
         %AdvertisingReport{devices: [%Device{address: addr, data: ["\tcameritaprinter" <> _]}]}},
        %{printer_reachable?: false} = state
      ) do
    Logger.info("Trying to connect to CameritaPrinter.BLE #{inspect(addr)} #{inspect(addr, base: :hex)}")
    :ok = BlueHeron.ATT.Client.create_connection(state.conn, peer_address: addr)
    {:noreply, %{state | printer_address: addr, printer_reachable?: true}}
  end

  # ignore other HCI Events, including further advertising from printer
  def handle_info({:HCI_EVENT_PACKET, %AdvertisingReport{}}, state), do: {:noreply, state}
  def handle_info({:HCI_EVENT_PACKET, event}, state) do
    Logger.info "HCI Event: #{inspect event}"
    {:noreply, state}
  end

  # ignore other HCI ACL data (ATT handles this for us)
  def handle_info({:HCI_ACL_DATA_PACKET, data}, state) do
    Logger.info("ACL Data Packet #{inspect(data)}")
    {:noreply, state}
  end

  # Sent when create_connection/2 is complete
  def handle_info({BlueHeron.ATT.Client, conn, %ConnectionComplete{connection_handle: handle} = msg}, %{conn: conn} = state) do
    Logger.info("CameritaPrinter.BLE connection established #{inspect(msg)}")
    {:noreply, %{state | connected?: true, connection_handle: handle}}
  end

  # Sent if a connection is dropped
  def handle_info({BlueHeron.ATT.Client, _, %DisconnectionComplete{reason_name: reason}}, state) do
    Logger.warning("CameritaPrinter.BLE connection dropped: #{reason}")
    {:noreply, %{state | connected?: false}}
  end

  # Ignore other ATT data
  def handle_info({BlueHeron.ATT.Client, _, event}, state) do
    Logger.info("ATT Event #{inspect event}")
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:get_info, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call({:set_handle, handle}, _from, state) do
    {:reply, :ok, %{state | write_handle: handle}}
  end

  def handle_call({:apply, f}, _from, state) do
    reply = case apply(f, [state]) do
      :ok -> :ok
      {:ok, thing} -> {:ok, thing}
      error -> {:error, error}
    end
    {:reply, reply, state}
  end

  def handle_call({:write, _}, _from, %{connected?: false} = state) do
    Logger.warning("Not currently connected to printer: cannot write")
    {:reply, {:error, :disconnected}, state}
  end

  def handle_call({:write, data}, _from, state) do
    Logger.info "Trying to send data: #{inspect data} / handle: #{state.write_handle}"
    case BlueHeron.ATT.Client.write(state.conn, state.write_handle, data) do
      :ok ->
        Logger.info("Data Sent")
        {:reply, :ok, state}

      error ->
        Logger.info("Failed to send data to printer")
        {:reply, error, state}
    end
  end

  @impl true
  def terminate(reason, state) do
    Logger.info "BLE terminates with reason #{inspect reason}"
    state
  end

end
