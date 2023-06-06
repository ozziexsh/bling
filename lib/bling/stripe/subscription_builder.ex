defmodule Bling.Stripe.SubscriptionBuilder do
  @moduledoc false

  defstruct customer: nil,
            application_fee_percent: nil,
            billing_cycle_anchor: nil,
            billing_thresholds: nil,
            collection_method: nil,
            collection_method_cycle_anchor: nil,
            cancel_at: nil,
            cancel_at_period_end: nil,
            coupon: nil,
            days_until_due: nil,
            items: [],
            default_payment_method: nil,
            default_tax_rates: nil,
            expand: nil,
            metadata: nil,
            payment_behavior: "default_incomplete",
            prorate: nil,
            proration_behavior: nil,
            promotion_code: nil,
            tax_rate: nil,
            trial_end: nil,
            trial_from_plan: nil,
            trial_period_days: nil

  def new(initial \\ %{}) do
    Map.merge(struct(__MODULE__), initial)
  end

  def build(t) do
    t |> Map.from_struct() |> Map.reject(fn {_, v} -> is_nil(v) end)
  end

  def create(t) do
    Stripe.Subscription.create(t)
  end

  def customer(t, customer), do: %{t | customer: customer}

  def application_fee_percent(t, afp), do: %{t | application_fee_percent: afp}

  def billing_cycle_anchor(t, v), do: %{t | billing_cycle_anchor: v}

  def billing_thresholds(t, v), do: %{t | billing_thresholds: v}

  def collection_method(t, v), do: %{t | collection_method: v}

  def collection_method_cycle_anchor(t, v), do: %{t | collection_method_cycle_anchor: v}

  def cancel_at(t, timestamp) when is_integer(timestamp), do: %{t | cancel_at: timestamp}
  def cancel_at(t, datetime), do: cancel_at(t, DateTime.to_unix(datetime))

  def cancel_at_period_end(t, v), do: %{t | cancel_at_period_end: v}

  def coupon(t, v), do: %{t | coupon: v}

  def days_until_due(t, v), do: %{t | days_until_due: v}

  def item(t, item), do: %{t | items: [item | t.items]}

  def items(t, items), do: %{t | items: items}

  def default_payment_method(t, v), do: %{t | default_payment_method: v}

  def default_tax_rates(t, v), do: %{t | default_tax_rates: v}

  def expand(t, v), do: %{t | expand: v}

  def metadata(t, v), do: %{t | metadata: v}

  def payment_behavior(t, v), do: %{t | payment_behavior: v}

  def prorate(t, v), do: %{t | prorate: v}

  def proration_behavior(t, v), do: %{t | proration_behavior: v}

  def promotion_code(t, v), do: %{t | promotion_code: v}

  def tax_rate(t, v), do: %{t | tax_rate: v}

  def trial_end(t, trial_end),
    do: %{t | trial_end: trial_end, trial_from_plan: nil, trial_period_days: nil}

  def trial_days(t, days),
    do: %{t | trial_end: nil, trial_from_plan: nil, trial_period_days: days}

  def trial_until(t, datetime),
    do: %{t | trial_end: DateTime.to_unix(datetime), trial_from_plan: nil, trial_period_days: nil}
end
