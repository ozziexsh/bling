defmodule Bling.Plug do
  @moduledoc """
  Adds the `MyApp.Bling` module to `conn.assigns.bling`.
  """

  def init(opts), do: opts

  def call(conn, opts) do
    Plug.Conn.assign(conn, :bling, opts[:bling])
  end
end
