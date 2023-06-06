defmodule Bling.Stripe.Controllers.BlingController do
  @moduledoc false

  use Phoenix.Controller,
    formats: [:html, :json],
    layouts: [html: Bling.Stripe.Controllers.Layouts]

  plug(Bling.Stripe.Plugs.AssignCustomer)

  def finalize(conn, _params) do
    props = get_props(conn)

    if props.payment_intent || props.setup_intent do
      conn
      |> assign(:props, props)
      |> render(:finalize)
    else
      redirect(conn, to: "/")
    end
  end

  def store_payment_method(conn, params) do
    customer =
      conn.assigns.customer
      |> Bling.Stripe.Customers.update_default_payment_method(params["payment_method_id"])

    conn |> assign(:customer, customer) |> json(%{props: get_props(conn)})
  end

  defp get_props(conn) do
    router = conn.assigns.route_helpers
    customer_type = conn.params["customer_type"]
    customer_id = conn.params["customer_id"]
    finalize_url = router.bling_finalize_url(conn, :finalize, customer_type, customer_id)
    base_url = String.replace_trailing(finalize_url, "/finalize", "")

    %{
      finalize_url: finalize_url,
      base_url: base_url,
      return_to: "/",
      payment_intent: maybe_get_payment_intent(conn),
      setup_intent: maybe_get_setup_intent(conn),
      payment_method: get_payment_method(conn.assigns.customer)
    }
  end

  defp maybe_get_setup_intent(conn) do
    id = Map.get(conn.params, "setup_intent")

    with id when not is_nil(id) <- id,
         {:ok, intent} <- Stripe.SetupIntent.retrieve(id, %{}),
         true <- intent.customer == conn.assigns.customer.stripe_id do
      Map.take(intent, [:id, :client_secret, :status, :payment_method])
    else
      _ -> nil
    end
  end

  defp maybe_get_payment_intent(conn) do
    id = Map.get(conn.params, "payment_intent")

    with id when not is_nil(id) <- id,
         {:ok, intent} <- Stripe.PaymentIntent.retrieve(id, %{}),
         true <- intent.customer == conn.assigns.customer.stripe_id do
      Map.take(intent, [:id, :client_secret, :amount, :currency, :status])
    else
      _ -> nil
    end
  end

  defp get_payment_method(%{payment_id: nil}), do: nil

  defp get_payment_method(customer),
    do: Map.take(customer, [:payment_id, :payment_type, :payment_last_four])
end
