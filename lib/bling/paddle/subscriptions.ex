defmodule Bling.Paddle.Subscriptions do
  alias Bling.Entity
  alias Bling.Paddle.Api.PaymentInformation
  alias Bling.Paddle.Api

  @status_active "active"
  @status_trialing "trialing"
  @status_past_due "past_due"
  @status_paused "paused"
  @status_deleted "deleted"

  def has_plan?(subscription, plan) do
    subscription.paddle_plan == plan
  end

  def valid?(subscription) do
    active?(subscription) or trial?(subscription) or paused_grace_period?(subscription) or
      grace_period?(subscription)
  end

  def active?(subscription) do
    (is_nil(subscription.ends_at) or grace_period?(subscription) or
       paused_grace_period?(subscription)) and
      (!Bling.Paddle.deactivate_past_due?() or subscription.paddle_status != @status_past_due) and
      subscription.paddle_status != @status_paused
  end

  def past_due?(subscription) do
    subscription.paddle_status == @status_past_due
  end

  def recurring?(subscription) do
    !trial?(subscription) && !paused?(subscription) && !paused_grace_period?(subscription) &&
      !cancelled?(subscription)
  end

  def paused?(subscription) do
    subscription.paddle_status == @status_paused
  end

  def paused_grace_period?(subscription) do
    paused_from =
      subscription.paused_from &&
        DateTime.compare(subscription.paused_from, DateTime.utc_now())

    paused_from == :gt
  end

  def cancelled?(subscription) do
    not is_nil(subscription.ends_at)
  end

  def ended?(subscription) do
    cancelled?(subscription) and not grace_period?(subscription)
  end

  def trial?(subscription) do
    ends_at =
      subscription.trial_ends_at &&
        DateTime.compare(subscription.trial_ends_at, DateTime.utc_now())

    ends_at == :gt
  end

  def expired_trial?(subscription) do
    ends_at =
      subscription.trial_ends_at &&
        DateTime.compare(subscription.trial_ends_at, DateTime.utc_now())

    subscription.trial_ends_at && ends_at == :lt
  end

  def grace_period?(subscription) do
    ends_at =
      subscription.ends_at &&
        DateTime.compare(subscription.ends_at, DateTime.utc_now())

    ends_at == :gt
  end

  def swap(subscription, opts) do
    guard_against_updates!(subscription)

    bling = Entity.bling(subscription)
    plan = opts[:plan_id]

    params = opts |> Enum.into(%{})

    update_paddle(subscription, params)

    subscription
    |> Ecto.Changeset.change(%{
      paddle_plan: plan
    })
    |> bling.repo().update!()
  end

  def swap_and_invoice(subscription, opts) do
    opts = Keyword.merge(opts, bill_immediately: true)
    swap(subscription, opts)
  end

  def pause(subscription) do
    bling = Entity.bling(subscription)
    update_paddle(subscription, %{pause: true})

    info = paddle_info(subscription)

    {:ok, paused_from, _} = DateTime.from_iso8601("#{info["paused_from"]}Z")

    subscription
    |> Ecto.Changeset.change(%{
      paddle_status: info["state"],
      paused_from: paused_from |> DateTime.truncate(:second)
    })
    |> bling.repo().update!()
  end

  def unpause(subscription) do
    bling = Entity.bling(subscription)
    update_paddle(subscription, %{pause: false})

    subscription
    |> Ecto.Changeset.change(%{
      paddle_status: @status_active,
      ends_at: nil,
      paused_from: nil
    })
    |> bling.repo().update!()
  end

  def cancel(subscription) do
    if grace_period?(subscription) do
      subscription
    else
      ends_at =
        if paused_grace_period?(subscription) or paused?(subscription) do
          future? = DateTime.compare(subscription.paused_from, DateTime.utc_now()) == :gt

          if future?,
            do: subscription.paused_from,
            else: DateTime.utc_now() |> DateTime.truncate(:second)
        else
          if trial?(subscription) do
            subscription.trial_ends_at
          else
            info = paddle_info(subscription)
            {:ok, date, _} = DateTime.from_iso8601("#{info["next_payment"]["date"]}Z")
            DateTime.truncate(date, :second)
          end
        end

      cancel_at(subscription, ends_at)
    end
  end

  def cancel_now(subscription) do
    cancel_at(subscription, DateTime.utc_now())
  end

  def cancel_at(subscription, datetime) do
    bling = Entity.bling(subscription)

    Api.cancel_subscription(%{
      subscription_id: subscription.paddle_id
    })

    subscription
    |> Ecto.Changeset.change(%{
      paddle_status: @status_deleted,
      ends_at: datetime |> DateTime.truncate(:second)
    })
    |> bling.repo().update!()
  end

  def update_url(subscription) do
    subscription
    |> paddle_info()
    |> Map.get("update_url")
  end

  def cancel_url(subscription) do
    subscription
    |> paddle_info()
    |> Map.get("cancel_url")
  end

  def payment_information(subscription) do
    subscription
    |> paddle_info()
    |> Map.get("payment_information")
    |> PaymentInformation.from_api()
  end

  def charge(subscription, opts) do
    name = opts[:charge_name] || ""

    if String.length(name) > 50 do
      raise "Charge name has a maximum length of 50 characters."
    end

    Api.charge_subscription(subscription, Enum.into(opts, %{}))
  end

  def increment(subscription, opts) do
    quantity = Keyword.get(opts, :quantity, 1)

    update_quantity(subscription, quantity: subscription.quantity + quantity)
  end

  def increment_and_invoice(subscription, opts) do
    quantity = Keyword.get(opts, :quantity, 1)

    update_quantity(subscription,
      quantity: subscription.quantity + quantity,
      bill_immediately: true
    )
  end

  def decrement(subscription, opts) do
    quantity = Keyword.get(opts, :quantity, 1)

    update_quantity(subscription, quantity: subscription.quantity - quantity)
  end

  def update_quantity(subscription, opts) do
    guard_against_updates!(subscription)
    bling = Entity.bling(subscription)
    quantity = opts[:quantity]

    if quantity < 1 do
      raise "Paddle does not allow subscriptions to have a quantity of zero."
    end

    update_paddle(subscription, Enum.into(opts, %{}))

    subscription
    |> Ecto.Changeset.change(%{
      quantity: quantity
    })
    |> bling.repo().update!()
  end

  def paddle_info(subscription) do
    %{subscription_id: subscription.paddle_id}
    |> Api.subscription_users()
    |> List.first()
  end

  def update_paddle(subscription, params) do
    %{subscription_id: subscription.paddle_id}
    |> Map.merge(params)
    |> Api.update_subscription_user()
  end

  defp guard_against_updates!(subscription) do
    if trial?(subscription) do
      raise "Cannot update while on trial."
    end

    if paused?(subscription) or paused_grace_period?(subscription) do
      raise "Cannot update paused subscriptions."
    end

    if cancelled?(subscription) or grace_period?(subscription) do
      raise "Cannot update cancelled subscriptions"
    end

    if past_due?(subscription) do
      raise "Cannot update past due subscriptions."
    end
  end
end
