defmodule Ricochet do
  use Application

  def start(_type, _args) do
    urls = System.get_env("RICOCHET_URLS")
        |> String.split
        |> Enum.map(&parse_url/1)
    dispatch = :cowboy_router.compile(
      [{:_, [{:_, Ricochet.Handler, urls}]}]
    )
    port = System.get_env("PORT")
    port = if port do
             String.to_integer port
           else
             8080
           end
    {:ok, _} = :cowboy.start_clear(:ricochet_listener, [port: port], %{env: %{dispatch: dispatch}})
  end

  def parse_url(url) do
    url = URI.parse url
    host = url.host
    path = url.path || ""
    path = if String.ends_with?(path, "/"), do: String.slice(path, 0..-2), else: path
    query = url.query
    {transport, port} =
      case url.scheme do
        "http" -> {:tcp, url.port}
        "https" -> {:ssl, url.port}
        nil -> {:ssl, url.port || 443}
      end
    {transport, host, port, path, query}
  end
end
