defmodule Bling.Plugs.AssignCustomer do
  @moduledoc false

  def init(opts), do: opts

  def call(conn, _opts) do
    %{"customer_type" => customer_type, "customer_id" => customer_id} = conn.params
    bling = Bling.bling()
    repo = Bling.repo()

    with schema when not is_nil(schema) <- Bling.module_from_customer_type(customer_type),
         customer when not is_nil(customer) <- repo.get_by(schema, id: customer_id),
         {:auth, true} <-
           {:auth, Bling.Util.maybe_call({bling, :can_manage_billing?, [conn, customer]}, false)},
         customer <- maybe_create_stripe_customer(customer) do
      conn |> Plug.Conn.assign(:customer, customer)
    else
      {:auth, _} ->
        conn
        |> Plug.Conn.put_status(401)
        |> Phoenix.Controller.redirect(to: "/")
        |> Plug.Conn.halt()

      _ ->
        conn
        |> Plug.Conn.put_status(404)
        |> Phoenix.Controller.redirect(to: "/")
        |> Plug.Conn.halt()
    end
  end

  defp maybe_create_stripe_customer(customer) do
    if customer.stripe_id do
      customer
    else
      Bling.Customers.create_stripe_customer(customer)
    end
  end
end
