defmodule Bling.Paddle.Controllers.PaddleWebhookController do
  alias Bling.Paddle.Subscriptions
  use Phoenix.Controller

  def webhook(conn, params) do
    # try do
    verify_signature!(conn.body_params)

    handle(params, conn.assigns.bling)

    conn |> json(%{ok: true})
    # rescue
    #   _ -> conn |> json(%{ok: false, message: "invalid signature"})
    # end
  end

  def handle(%{"alert_name" => "payment_succeeded"} = payload, bling) do
    receipt_exists!(payload["order_id"], bling)

    passthrough = verify_passthrough!(payload)

    {:ok, paid_at, _} = "#{payload["event_time"]}Z" |> DateTime.from_iso8601()

    # todo: could create from customer via build_assoc
    bling.receipt()
    |> struct()
    |> Ecto.Changeset.change(%{
      customer_id: passthrough["customer_id"],
      customer_type: passthrough["customer_type"],
      checkout_id: payload["checkout_id"],
      order_id: payload["order_id"],
      amount: payload["sale_gross"],
      tax: payload["payment_tax"],
      currency: payload["currency"],
      quantity: str_int(payload["quantity"]),
      receipt_url: payload["receipt_url"],
      paid_at: paid_at |> DateTime.truncate(:second)
    })
    |> bling.repo().insert!()
  end

  def handle(%{"alert_name" => "subscription_payment_succeeded"} = payload, bling) do
    receipt_exists!(payload["order_id"], bling)

    passthrough = verify_passthrough!(payload)

    {:ok, paid_at, _} = "#{payload["event_time"]}Z" |> DateTime.from_iso8601()

    # todo: could create from customer via build_assoc
    bling.receipt()
    |> struct()
    |> Ecto.Changeset.change(%{
      paddle_subscription_id: str_int(payload["subscription_id"]),
      customer_id: passthrough["customer_id"],
      customer_type: passthrough["customer_type"],
      checkout_id: payload["checkout_id"],
      order_id: payload["order_id"],
      amount: payload["sale_gross"],
      tax: payload["payment_tax"],
      currency: payload["currency"],
      quantity: str_int(payload["quantity"]),
      receipt_url: payload["receipt_url"],
      paid_at: paid_at |> DateTime.truncate(:second)
    })
    |> bling.repo().insert!()
  end

  def handle(%{"alert_name" => "subscription_cancelled"} = payload, bling) do
    subscription = verify_subscription!(payload["subscription_id"], bling)

    ends_at =
      cond do
        is_nil(subscription.ends_at) and Subscriptions.trial?(subscription) ->
          subscription.trial_ends_at

        is_nil(subscription.ends_at) ->
          {:ok, datetime, _} =
            DateTime.from_iso8601("#{payload["cancellation_effective_date"]} 00:00:00Z")

          datetime |> DateTime.truncate(:second)

        true ->
          subscription.ends_at
      end

    subscription
    |> Ecto.Changeset.change(%{
      ends_at: ends_at,
      paused_from: nil,
      paddle_status:
        if(Map.has_key?(payload, "status"),
          do: payload["status"],
          else: subscription.paddle_status
        )
    })
    |> bling.repo().update!()
  end

  def handle(%{"alert_name" => "subscription_updated"} = payload, bling) do
    subscription = verify_subscription!(payload["subscription_id"], bling)

    paused_from =
      if Map.has_key?(payload, "paused_from") do
        {:ok, timestamp, _} = "#{payload["paused_from"]}Z" |> DateTime.from_iso8601()
        timestamp |> DateTime.truncate(:second)
      end

    subscription
    |> Ecto.Changeset.change(%{
      paddle_plan:
        if(Map.has_key?(payload, "subscription_plan_id"),
          do: str_int(payload["subscription_plan_id"]),
          else: subscription.paddle_plan
        ),
      paddle_status:
        if(Map.has_key?(payload, "status"),
          do: payload["status"],
          else: subscription.paddle_status
        ),
      quantity:
        if(Map.has_key?(payload, "new_quantity"),
          do: str_int(payload["new_quantity"]),
          else: subscription.quantity
        ),
      paused_from: paused_from
    })
    |> bling.repo().update!()
  end

  def handle(%{"alert_name" => "subscription_created"} = payload, bling) do
    passthrough = verify_passthrough!(payload)

    trial_ends_at =
      if payload["status"] == "trialing" do
        {:ok, datetime, _} = DateTime.from_iso8601("#{payload["next_bill_date"]} 00:00:00Z")
        datetime |> DateTime.truncate(:second)
      else
        nil
      end

    struct(bling.subscription())
    |> Ecto.Changeset.change(%{
      customer_id: passthrough["customer_id"],
      customer_type: passthrough["customer_type"],
      name: passthrough["subscription_name"],
      paddle_id: str_int(payload["subscription_id"]),
      paddle_plan: str_int(payload["subscription_plan_id"]),
      paddle_status: payload["status"],
      quantity: str_int(payload["quantity"]),
      trial_ends_at: trial_ends_at
    })
    |> bling.repo().insert!()
  end

  defp verify_subscription!(id, bling) do
    bling.repo().get_by!(bling.subscription(), paddle_id: id)
  end

  defp receipt_exists!(receiptId, bling) do
    if bling.repo().get_by(bling.receipt(), order_id: receiptId) do
      raise "Already exists, dont need to handle"
    end
  end

  # todo verify sub name customer id customer type
  defp verify_passthrough!(payload) do
    passthrough = Map.get(payload, "passthrough")

    if passthrough do
      Jason.decode!(passthrough)
    else
      raise "Invalid passthrough"
    end
  end

  defp str_int(value) when is_integer(value), do: value

  defp str_int(value) do
    {parsed, _} = Integer.parse(value)
    parsed
  end

  defp verify_signature!(params) do
    public_key = Application.get_env(:bling, :paddle)[:public_key]
    [public_key] = :public_key.pem_decode(public_key)
    public_key = :public_key.pem_entry_decode(public_key)

    signature = params |> Map.get("p_signature") |> Base.decode64!()

    body =
      params
      |> Map.drop(["p_signature"])
      |> Map.to_list()
      |> Enum.sort_by(fn {k, _v} -> k end, :asc)
      |> PhpSerializer.serialize()

    if :public_key.verify(body, :sha, signature, public_key) do
      true
    else
      raise "Invalid signature"
    end
  end
end
