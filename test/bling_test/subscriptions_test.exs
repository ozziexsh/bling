defmodule BlingTest.SubscriptionsTest do
  use BlingTest.RepoCase
  alias Bling.{Subscriptions, Customers}
  alias BlingTest.{Repo, Subscription, SubscriptionItem}

  @return_url "http://localhost:4000/finalize"

  test "single subscription, single price, single quantity" do
    user = create_customer() |> with_valid_card()

    {:ok, subscription} =
      Customers.create_subscription(user,
        prices: [{price_id(:plus_monthly), 1}],
        return_url: @return_url
      )

    assert Enum.count(Repo.all(Subscription)) == 1
    assert Enum.count(Repo.all(SubscriptionItem)) == 1

    [item] = subscription.subscription_items

    assert subscription.name == "default"
    assert subscription.stripe_status == "active"
    assert item.stripe_price_id == price_id(:plus_monthly)
    assert item.quantity == 1
    assert subscription.customer_id == user.id
    assert subscription.customer_type == "user"

    assert_recurring_subscription(subscription)

    assert Subscriptions.has_multiple_prices?(subscription) == false
    assert Subscriptions.has_single_price?(subscription) == true

    assert Customers.subscriptions(user) == [subscription]
    assert Customers.subscription(user) == subscription
    assert Customers.subscribed_to_price?(user, price_id(:plus_monthly)) == true
    assert Customers.subscribed_to_price?(user, price_id(:plus_yearly)) == false
    assert Customers.subscribed_to_product?(user, product_id(:plus)) == true
    assert Customers.subscribed_to_product?(user, product_id(:pro)) == false

    subscription = Subscriptions.cancel(subscription)
    assert_canceled_subscription(subscription)

    subscription = Subscriptions.resume(subscription)
    assert_recurring_subscription(subscription)

    cancel_at_datetime = DateTime.utc_now() |> DateTime.add(7, :day)
    cancel_at_date = DateTime.to_date(cancel_at_datetime)
    subscription = Subscriptions.cancel_at(subscription, cancel_at_datetime)
    assert subscription.stripe_status == "active"
    assert Date.compare(DateTime.to_date(subscription.ends_at), cancel_at_date) == :eq
    assert_canceled_subscription(subscription)

    subscription = Subscriptions.resume(subscription)
    assert_recurring_subscription(subscription)

    subscription =
      Subscriptions.change_prices(subscription, prices: [{price_id(:plus_yearly), 1}])

    [item] = subscription.subscription_items

    assert subscription.name == "default"
    assert item.stripe_price_id == price_id(:plus_yearly)
    assert item.quantity == 1
    assert_recurring_subscription(subscription)

    subscription = Subscriptions.increment(subscription, quantity: 5)
    [item] = subscription.subscription_items

    assert item.quantity == 6
    assert_recurring_subscription(subscription)

    subscription = Subscriptions.decrement(subscription)
    [item] = subscription.subscription_items
    assert item.quantity == 5
    assert_recurring_subscription(subscription)

    subscription = Subscriptions.set_quantity(subscription)
    [item] = subscription.subscription_items
    assert item.quantity == 1
    assert_recurring_subscription(subscription)

    subscription = Subscriptions.cancel_now(subscription)
    assert_ended_subscription(subscription)
  end

  test "multiple prices" do
    user = create_customer() |> with_valid_card()

    {:ok, subscription} =
      Customers.create_subscription(user,
        prices: [
          {price_id(:plus_monthly), 1},
          {price_id(:pro_monthly), 1}
        ],
        return_url: @return_url
      )

    assert Enum.count(Repo.all(Subscription)) == 1
    assert Enum.count(Repo.all(SubscriptionItem)) == 2

    assert subscription.name == "default"
    assert subscription.stripe_status == "active"
    assert subscription.customer_id == user.id
    assert subscription.customer_type == "user"

    assert_recurring_subscription(subscription)

    assert Subscriptions.has_multiple_prices?(subscription) == true
    assert Subscriptions.has_single_price?(subscription) == false

    subscription =
      Subscriptions.increment(subscription, price_id: price_id(:plus_monthly), quantity: 5)

    quantity =
      Enum.find_value(subscription.subscription_items, fn item ->
        if item.stripe_price_id == price_id(:plus_monthly) do
          item.quantity
        else
          nil
        end
      end)

    assert quantity == 6

    subscription =
      Subscriptions.decrement(subscription, price_id: price_id(:plus_monthly), quantity: 2)

    quantity =
      Enum.find_value(subscription.subscription_items, fn item ->
        if item.stripe_price_id == price_id(:plus_monthly) do
          item.quantity
        else
          nil
        end
      end)

    assert quantity == 4

    subscription =
      Subscriptions.set_quantity(subscription, price_id: price_id(:plus_monthly), quantity: 1)

    quantity =
      Enum.find_value(subscription.subscription_items, fn item ->
        if item.stripe_price_id == price_id(:plus_monthly) do
          item.quantity
        else
          nil
        end
      end)

    assert quantity == 1

    subscription = Subscriptions.remove_prices(subscription, prices: [price_id(:pro_monthly)])
    [item] = subscription.subscription_items
    assert_recurring_subscription(subscription)
    assert item.stripe_price_id == price_id(:plus_monthly)
    assert item.quantity == 1
    assert Subscriptions.has_multiple_prices?(subscription) == false
    assert Subscriptions.has_single_price?(subscription) == true
    assert Enum.count(Repo.all(SubscriptionItem)) == 1

    subscription = Subscriptions.add_prices(subscription, prices: [{price_id(:pro_monthly), 1}])
    assert_recurring_subscription(subscription)
    assert Subscriptions.has_multiple_prices?(subscription) == true
    assert Subscriptions.has_single_price?(subscription) == false
    assert Enum.count(Repo.all(SubscriptionItem)) == 2

    subscription =
      Subscriptions.change_prices(subscription, prices: [{price_id(:plus_monthly), 1}])

    assert_recurring_subscription(subscription)
    [item] = subscription.subscription_items
    assert item.stripe_price_id == price_id(:plus_monthly)
    assert item.quantity == 1
    assert Subscriptions.has_multiple_prices?(subscription) == false
    assert Subscriptions.has_single_price?(subscription) == true
    assert Enum.count(Repo.all(SubscriptionItem)) == 1
  end

  test "multiple subscriptions" do
    user = create_customer() |> with_valid_card()

    {:ok, default_subscription} =
      Customers.create_subscription(user,
        prices: [{price_id(:plus_monthly), 1}],
        return_url: @return_url
      )

    {:ok, extra_subscription} =
      Customers.create_subscription(user,
        prices: [{price_id(:plus_monthly), 1}],
        return_url: @return_url,
        plan: "extra"
      )

    assert Enum.count(Repo.all(Subscription)) == 2
    assert Enum.count(Repo.all(SubscriptionItem)) == 2

    assert default_subscription.name == "default"
    assert extra_subscription.name == "extra"

    assert Customers.subscribed?(user) == true
    assert Customers.subscribed?(user, plan: "default") == true
    assert Customers.subscribed?(user, plan: "extra") == true
    assert Customers.subscribed?(user, plan: "doesntexist") == false

    assert Customers.subscription(user) == default_subscription
    assert Customers.subscription(user, plan: "default") == default_subscription
    assert Customers.subscription(user, plan: "extra") == extra_subscription
  end

  test "single subscription, free forever coupon" do
    user = create_customer() |> with_valid_card()

    {:ok, coupon} =
      Stripe.Coupon.create(%{duration: :forever, percent_off: 100.0})

    {:ok, subscription} =
      Customers.create_subscription(user,
        prices: [{price_id(:plus_monthly), 1}],
        return_url: @return_url,
        stripe: %{coupon: coupon.id}
      )

    assert Enum.count(Repo.all(Subscription)) == 1
    assert Enum.count(Repo.all(SubscriptionItem)) == 1

    assert_recurring_subscription(subscription)
  end

  # test incomplete subscriptions

  defp assert_recurring_subscription(subscription) do
    assert subscription.stripe_status == "active"
    assert subscription.ends_at == nil
    assert Subscriptions.active?(subscription) == true
    assert Subscriptions.valid?(subscription) == true
    assert Subscriptions.recurring?(subscription) == true
    assert Subscriptions.ended?(subscription) == false
    assert Subscriptions.canceled?(subscription) == false
    assert Subscriptions.trial?(subscription) == false
    assert Subscriptions.grace_period?(subscription) == false
  end

  defp assert_canceled_subscription(subscription) do
    assert subscription.stripe_status == "active"
    assert subscription.ends_at != nil
    assert Subscriptions.active?(subscription) == true
    assert Subscriptions.valid?(subscription) == true
    assert Subscriptions.recurring?(subscription) == false
    assert Subscriptions.ended?(subscription) == false
    assert Subscriptions.canceled?(subscription) == true
    assert Subscriptions.trial?(subscription) == false
    assert Subscriptions.grace_period?(subscription) == true
  end

  defp assert_ended_subscription(subscription) do
    assert subscription.stripe_status == "canceled"
    assert subscription.ends_at != nil
    assert Subscriptions.active?(subscription) == false
    assert Subscriptions.valid?(subscription) == false
    assert Subscriptions.recurring?(subscription) == false
    assert Subscriptions.ended?(subscription) == true
    assert Subscriptions.canceled?(subscription) == true
    assert Subscriptions.trial?(subscription) == false
    assert Subscriptions.grace_period?(subscription) == false
  end
end
