defmodule Camerita.Comm do
  use WebSockex
  require Logger

  @backoff [2, 2, 2, 2, 5, 5, 5, 10, 10]

  def start_link(%{url: nil}) do
    Logger.error("You din't pass a ws endpoint to connect to")
  end
  def start_link(%{url: url}) do
    Logger.info("connecting to remote station: #{url}")
    WebSockex.start_link(url, __MODULE__, %{url: url, backoff: 0, connected?: false}, [name: __MODULE__, async: true, handle_initial_conn_failure: true])
  end

  def handle_connect(_conn, %{url: url} = state) do
    Logger.info("Connected to: #{url}")
    {:ok, %{state | connected?: true}}
  end

  def handle_disconnect(%{attempt_number: n} = _connection_status, state) do
    backoff = if n < 8 do
      Enum.at @backoff, n
    else
      30
    end
    Logger.info("Reconnecting after #{backoff} sec")
    :timer.sleep(backoff * 1000)
    {:reconnect, state}
  end

  def handle_frame({:binary, msg}, state) do
    Logger.info "received binary (size: #{byte_size msg}) / sending to printer"
    Camerita.write msg
    {:ok, state}
  end

  def handle_frame({:text, "reset"}, state) do
    Logger.info "Reset printer"
    Camerita.reset()
    {:ok, state}
  end

  def handle_frame({:text, msg}, state) do
    Logger.info "Ignore nonbinray messages :-) '#{inspect msg}'."
    {:ok, state}
  end

  def handle_cast({:send, {type, msg} = frame}, state) do
    Logger.info "Sending #{type} frame with payload: #{msg}"
    {:reply, frame, state}
  end

  def handle_info(mess, state) do
    Logger.info "Info #{inspect mess}"
    {:ok, state}
  end

  def send(message) do
    WebSockex.cast(__MODULE__, {:send, {:binary, message}})
  end

  def terminate(reason, state) do
    Logger.info "Comm terminates with reason #{inspect reason}"
    state
  end
end
