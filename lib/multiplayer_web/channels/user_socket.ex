defmodule MultiplayerWeb.UserSocket do
  use Phoenix.Socket
  require Logger
  alias MultiplayerWeb.ChannelsAuthorization

  ## Channels
  channel "room:*", MultiplayerWeb.RoomChannel
  channel "realtime:*", MultiplayerWeb.RealtimeChannel

  @landing_host "multiplayer.red"

  @impl true
  def connect(params, socket, %{uri: %{host: @landing_host}}) do
    {_, params} = Map.pop(params, "vsn")
    params = for {key, val} <- params, into: %{}, do: {String.to_atom(key), val}
    {:ok, assign(socket, :params, params)}
  end

  def connect(params, socket, connect_info) do
    if Application.fetch_env!(:multiplayer, :secure_channels) do
      %{uri: %{host: host}, x_headers: headers} = connect_info
      #  , hooks = Multiplayer.Api.get_hooks_by_tenant_id(tenant.id)
      with tenant when tenant != nil <- Multiplayer.Api.get_tenant_by_host(host),
           token when token != nil <- access_token(params, headers),
           {:ok, claims} <- authorize_conn(token, tenant.jwt_secret) do
        assigns = %{
          scope: tenant.id,
          claims: claims,
          params: %{
            # hooks: hooks,
            ref: make_ref()
          }
        }

        Ewalrus.start(
          tenant.id,
          tenant.db_host,
          tenant.db_name,
          tenant.db_user,
          tenant.db_password
        )

        {:ok, assign(socket, assigns)}
      else
        _ ->
          Logger.error("Auth error")
          :error
      end
    end
  end

  def access_token(params, headers) do
    case :proplists.lookup("x-api-key", headers) do
      :none -> Map.get(params, "apikey")
      token -> token
    end
  end

  @impl true
  def id(_socket), do: nil

  defp authorize_conn(token, secret) do
    case ChannelsAuthorization.authorize(token, secret) do
      # TODO: check necessary fields
      {:ok, %{"role" => _} = claims} ->
        {:ok, claims}

      _ ->
        :error
    end
  end
end
