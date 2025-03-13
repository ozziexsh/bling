defmodule BlingTest.CustomersTest do
  alias Bling.Customers

  use BlingTest.RepoCase

  test "interacting with customers" do
    user = create_customer()
    assert user.stripe_id != nil

    stripe_customer = Customers.as_stripe_customer(user)
    assert %Stripe.Customer{} = stripe_customer

    setup_intent = Customers.create_setup_intent(user)
    assert %Stripe.SetupIntent{} = setup_intent

    payment_method = Customers.default_payment_method(user)
    assert payment_method == nil

    {:ok, method} =
      Stripe.PaymentMethod.attach("pm_card_visa", %{customer: user.stripe_id})

    user = Customers.update_default_payment_method(user, method.id)
    payment_method = Customers.default_payment_method(user)
    assert %Bling.PaymentMethod{} = payment_method

    {:ok, method} =
      Stripe.PaymentMethod.attach("pm_card_mastercard", %{customer: user.stripe_id})

    Stripe.Customer.update(user.stripe_id, %{
      invoice_settings: %{default_payment_method: method.id}
    })

    user = Customers.update_default_payment_method_from_stripe(user)
    payment_method = Customers.default_payment_method(user)
    assert %Bling.PaymentMethod{} = payment_method
    assert payment_method.id == method.id
    assert payment_method.card_brand == "mastercard"
  end

  test "customer trials" do
    customer = create_user()

    assert Customers.trial?(customer) == false
    assert Customers.generic_trial?(customer) == false

    trial_ends_at = DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.truncate(:second)

    customer =
      customer
      |> Ecto.Changeset.change(%{trial_ends_at: trial_ends_at})
      |> BlingTest.Repo.update!()

    assert Customers.trial?(customer) == true
    assert Customers.generic_trial?(customer) == true

    expired_trial = DateTime.utc_now() |> DateTime.add(-7, :day) |> DateTime.truncate(:second)

    customer =
      customer
      |> Ecto.Changeset.change(%{trial_ends_at: expired_trial})
      |> BlingTest.Repo.update!()

    assert Customers.trial?(customer) == false
    assert Customers.generic_trial?(customer) == false

    subscription = create_subscription(customer, %{trial_ends_at: trial_ends_at})

    assert Customers.trial?(customer) == true
    assert Customers.generic_trial?(customer) == false

    swimming = create_subscription(customer, %{name: "swimming", trial_ends_at: trial_ends_at})
    lifting = create_subscription(customer, %{name: "lifting", trial_ends_at: nil})

    assert Customers.trial?(customer) == true
    assert Customers.trial?(customer, plan: "swimming") == true
    assert Customers.trial?(customer, plan: "lifting") == false
  end
end
