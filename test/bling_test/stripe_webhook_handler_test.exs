defmodule BlingTest.StripeWebhookHandlerTest do
  alias Bling.StripeWebhookHandler
  use BlingTest.RepoCase

  test "customer deleted" do
    user =
      create_user(%{
        stripe_id: "cus_1234",
        payment_id: "pm_1234",
        payment_type: "card",
        payment_last_four: "1234"
      })

    subscription = create_subscription(user)

    event = %Stripe.Event{
      type: "customer.deleted",
      data: %{
        object: %Stripe.Customer{
          id: "cus_1234"
        }
      }
    }

    StripeWebhookHandler.handle_event(event, BlingTest.ExampleBling)

    user = BlingTest.Repo.reload(user)

    assert user.stripe_id == nil
    assert user.payment_id == nil
    assert user.payment_type == nil
    assert user.payment_last_four == nil

    subscription = BlingTest.Repo.reload(subscription)

    assert subscription.stripe_status == "canceled"
    assert subscription.ends_at != nil
  end

  test "customer updated" do
    user = create_customer() |> with_default_card_in_stripe_only()

    event = %Stripe.Event{
      type: "customer.updated",
      data: %{
        object: %Stripe.Customer{
          id: user.stripe_id
        }
      }
    }

    StripeWebhookHandler.handle_event(event, BlingTest.ExampleBling)

    user = BlingTest.Repo.reload(user)

    assert user.payment_id != nil
    assert user.payment_type == "card"
    assert user.payment_last_four == "4242"
  end

  test "customer subscription created" do
    user = create_customer() |> with_valid_card()

    event = %Stripe.Event{
      type: "customer.subscription.created",
      data: %{
        object: %Stripe.Subscription{
          id: "sub_1234",
          status: "active",
          customer: user.stripe_id,
          metadata: %{
            "name" => "default"
          },
          items: %{
            data: [
              %Stripe.SubscriptionItem{
                id: "si_1234",
                price: %{
                  product: product_id(:plus),
                  id: price_id(:plus_monthly)
                },
                quantity: 1
              }
            ]
          }
        }
      }
    }

    StripeWebhookHandler.handle_event(event, BlingTest.ExampleBling)

    subscription = BlingTest.Subscription |> BlingTest.Repo.one!()

    assert subscription.stripe_id == "sub_1234"
    assert subscription.stripe_status == "active"
    assert subscription.customer_id == user.id
    assert subscription.customer_type == "user"
    assert subscription.name == "default"
    assert subscription.ends_at == nil
    assert subscription.trial_ends_at == nil

    [item] =
      subscription |> BlingTest.Repo.preload(:subscription_items) |> Map.get(:subscription_items)

    assert item.stripe_id == "si_1234"
    assert item.stripe_price_id == price_id(:plus_monthly)
    assert item.stripe_product_id == product_id(:plus)
    assert item.quantity == 1
  end

  test "customer subscription updated" do
    user = create_user()
    subscription = create_subscription(user)

    # test it deletes incomplete_expired
    # test it adds new items
    # test it updates existing items
    # test it deletes items

    event = %Stripe.Event{
      type: "customer.subscription.updated",
      data: %{
        object: %Stripe.Subscription{
          id: subscription.stripe_id,
          status: "active",
          metadata: %{
            "name" => "default"
          },
          items: %{
            data: [
              %Stripe.SubscriptionItem{
                id: Enum.at(subscription.subscription_items, 0).stripe_id,
                price: %{
                  product: product_id(:plus),
                  id: price_id(:plus_monthly)
                },
                quantity: 2
              },
              %Stripe.SubscriptionItem{
                id: "si_pro",
                price: %{
                  product: product_id(:pro),
                  id: price_id(:pro_monthly)
                },
                quantity: 1
              }
            ]
          }
        }
      }
    }

    StripeWebhookHandler.handle_event(event, BlingTest.ExampleBling)

    subscription =
      BlingTest.Repo.reload(subscription) |> BlingTest.Repo.preload(:subscription_items)

    plus =
      Enum.find(subscription.subscription_items, fn item ->
        item.stripe_price_id == price_id(:plus_monthly)
      end)

    pro =
      Enum.find(subscription.subscription_items, fn item ->
        item.stripe_price_id == price_id(:pro_monthly)
      end)

    assert plus.quantity == 2
    assert pro.quantity == 1

    event = %Stripe.Event{
      type: "customer.subscription.updated",
      data: %{
        object: %Stripe.Subscription{
          id: subscription.stripe_id,
          status: "active",
          metadata: %{
            "name" => "default"
          },
          items: %{
            data: [
              %Stripe.SubscriptionItem{
                id: "si_pro",
                price: %{
                  product: product_id(:pro),
                  id: price_id(:pro_monthly)
                },
                quantity: 1
              }
            ]
          }
        }
      }
    }

    StripeWebhookHandler.handle_event(event, BlingTest.ExampleBling)

    subscription =
      BlingTest.Repo.reload(subscription) |> BlingTest.Repo.preload(:subscription_items)

    plus =
      Enum.find(subscription.subscription_items, fn item ->
        item.stripe_price_id == price_id(:plus_monthly)
      end)

    pro =
      Enum.find(subscription.subscription_items, fn item ->
        item.stripe_price_id == price_id(:pro_monthly)
      end)

    assert plus == nil
    assert pro.quantity == 1

    event = %Stripe.Event{
      type: "customer.subscription.updated",
      data: %{
        object: %Stripe.Subscription{
          id: subscription.stripe_id,
          status: "incomplete_expired"
        }
      }
    }

    StripeWebhookHandler.handle_event(event, BlingTest.ExampleBling)

    assert BlingTest.Repo.all(BlingTest.Subscription) == []
  end

  test "customer subscription deleted" do
    user = create_user()
    subscription = create_subscription(user)

    event = %Stripe.Event{
      type: "customer.subscription.deleted",
      data: %{
        object: %Stripe.Subscription{
          id: subscription.stripe_id
        }
      }
    }

    StripeWebhookHandler.handle_event(event, BlingTest.ExampleBling)

    subscription = BlingTest.Repo.reload(subscription)

    assert subscription.stripe_status == "canceled"
    assert subscription.ends_at != nil
  end
end
