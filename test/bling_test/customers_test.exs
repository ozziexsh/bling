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
      Stripe.PaymentMethod.attach(%{customer: user.stripe_id, payment_method: "pm_card_visa"})

    user = Customers.update_default_payment_method(user, method.id)
    payment_method = Customers.default_payment_method(user)
    assert %Bling.PaymentMethod{} = payment_method

    {:ok, method} =
      Stripe.PaymentMethod.attach(%{
        customer: user.stripe_id,
        payment_method: "pm_card_mastercard"
      })

    Stripe.Customer.update(user.stripe_id, %{
      invoice_settings: %{default_payment_method: method.id}
    })

    user = Customers.update_default_payment_method_from_stripe(user)
    payment_method = Customers.default_payment_method(user)
    assert %Bling.PaymentMethod{} = payment_method
    assert payment_method.id == method.id
    assert payment_method.card_brand == "mastercard"
  end
end
