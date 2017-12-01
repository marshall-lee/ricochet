defmodule Ricochet.Handler do
  require Logger

  def init(req, urls) do
    method = :cowboy_req.method(req)
    path = :cowboy_req.path(req)
    headers = :cowboy_req.headers(req)

    Logger.info "started method=#{method} path=#{path}"
    Logger.debug "request_headers=#{inspect headers}"


    request_id = headers["x-request-id"]
              || Base.hex_encode32(:crypto.strong_rand_bytes(20), case: :lower)
    Logger.metadata(request_id: request_id)

    state = %{
      method: method,
      path: path,
      headers: headers,
      main_stream: nil,
      streams: Map.new
    }

    state = Enum.reduce urls, state,
            fn ({transport, host, port, super_path, _}, state) ->
              state |> add_stream(
                         transport,
                         host,
                         port,
                         method,
                         super_path <> path,
                         headers
                       )
            end
    req = if :cowboy_req.has_body(req) do
            transmit_body(req, state.streams)
          else
            req
          end

    {:cowboy_loop, req, state}
  end

  def info({:gun_error, _conn, stream, error}, req, state) do
    Logger.error "gun error: #{inspect error}"
    {:ok, req, remove_stream(state, stream)}
  end

  def info({:gun_down, _conn, _protocol, reason, killed_streams, unprocessed_streams}, req, state) do
    all_streams = killed_streams ++ unprocessed_streams
    state = Enum.reduce all_streams, state, fn (stream, state) ->
      state |> remove_stream(stream)
    end
    try_finish(req, state)
  end

  def info({:gun_up, _conn, _protocol}, req, state) do
    {:ok, req, state}
  end

  def info({:gun_response, _conn, stream, is_fin, status, headers}, req, state) do
    stream_info = state.streams[stream]
    Logger.debug "#{format_stream(stream_info)} - response_status=#{status} response_headers=#{inspect headers}"
    {is_redirected, state} = try_redirect(state, status, headers)
    {state, req} =
      cond do
        is_redirected ->
          IO.puts "redirecting..."
          {state, req}
        !state.main_stream ->
          cowboy_headers = headers
                        |> Enum.group_by(fn {x,_} -> x end, fn {_,y} -> y end)
          stream_info = state.streams[stream]
          Logger.info "#{format_stream(stream_info)} - choosen as a main response"
          {
            %{state | main_stream: stream},
            :cowboy_req.stream_reply(status, cowboy_headers, req)
          }
        true ->
          {state, req}
      end
    case is_fin do
      :fin -> handle_fin(stream, req, state)
      :nofin -> {:ok, req, state}
    end
  end

  def info({:gun_data, _conn, stream, is_fin, data}, req, state) do
    stream_info = state.streams[stream]
    Logger.debug "#{format_stream(stream_info)} - response_data=#{inspect data}"
    if stream == state.main_stream do
      :ok = :cowboy_req.stream_body(data, :nofin, req)
    end
    case is_fin do
      :fin -> handle_fin(stream, req, state)
      :nofin -> {:ok, req, state}
    end
  end

  defp transmit_body(req, streams) do
    {is_enough, data, req} = :cowboy_req.read_body(req)
    Logger.debug "request_body_read=#{inspect data}"
    is_fin =
      case is_enough do
        :ok -> :fin
        :more -> :nofin
      end
    for {stream, stream_info} <- streams do
      :gun.data(stream_info.conn, stream, is_fin, data)
    end
    case is_enough do
      :ok ->
        Logger.info "request body has been transmitted to every endpoint"
        req
      :more ->
        transmit_body(req, streams)
    end
  end

  defp try_redirect(state, status, headers) do
    cond do
      status in [301, 302, 303, 307, 308] ->
        {true, do_redirect(state, status, headers)}
      true ->
        {false, state}
    end
  end

  defp do_redirect(state, status, headers) do
    method = if status == 303, do: "GET", else: state.method
    uri = headers |> List.keyfind("location", 0) |> elem(1)
    {transport, host, port, path, query} = Ricochet.parse_url(uri)
    path = if query, do: "#{path}?#{query}", else: path
    state |> add_stream(transport, host, port, method, path, state.headers)
  end

  defp handle_fin(stream, req, state) do
    stream_info = state.streams[stream]
    :gun.shutdown(stream_info.conn)
    Logger.info "#{format_stream(stream_info)} - fin"
    state = state |> remove_stream(stream)
    try_finish(req, state)
  end

  defp try_finish(req, state) do
    if Enum.empty?(state.streams) do
      Logger.info "finished"
      {:stop, req, state}
    else
      {:ok, req, state}
    end
  end

  defp add_stream(state, transport, host, port, method, path, headers) do
    {:ok, conn} = :gun.open(to_charlist(host), port, %{transport: transport})
    headers = headers |> Map.put("host", host) |> Enum.into([])
    stream = :gun.request(conn, method, path, headers)
    stream_info = %{
      conn: conn,
      host: host,
      port: port,
      path: path
    }
    Logger.info "#{format_stream(stream_info)} - open"
    %{state | streams: state.streams |> Map.put(stream, stream_info)}
  end

  defp remove_stream(state, stream) do
    %{state | streams: state.streams |> Map.delete(stream)}
  end

  defp format_stream(stream_info) do
    "#{stream_info.host}:#{stream_info.port}#{stream_info.path}"
  end
end
