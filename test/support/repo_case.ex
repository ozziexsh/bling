defmodule BlingTest.RepoCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias BlingTest.Repo
      import BlingTest.RepoCase
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(BlingTest.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  def create_user(data \\ %{}) do
    changes =
      Map.merge(
        %{
          email: Faker.Internet.email()
        },
        data
      )

    %BlingTest.User{}
    |> Ecto.Changeset.change(changes)
    |> BlingTest.Repo.insert!()
  end

  def create_customer(data \\ %{}) do
    data |> create_user() |> Bling.Customers.create_stripe_customer()
  end

  def with_valid_card(customer) do
    {:ok, method} =
      Stripe.PaymentMethod.attach("pm_card_visa", %{customer: customer.stripe_id})

    Bling.Customers.update_default_payment_method(customer, method.id)
  end

  def with_default_card_in_stripe_only(customer) do
    {:ok, method} =
      Stripe.PaymentMethod.attach("pm_card_visa", %{customer: customer.stripe_id})

    Stripe.Customer.update(customer.stripe_id, %{
      invoice_settings: %{default_payment_method: method.id}
    })

    customer
  end

  def create_subscription(customer, data \\ %{}, items \\ []) do
    defaults = %{
      stripe_id: "sub_#{Faker.UUID.v4()}",
      stripe_status: "active",
      ends_at: nil,
      trial_ends_at: nil,
      name: "default"
    }

    default_items = [
      %{
        stripe_id: "si_#{Faker.UUID.v4()}",
        stripe_price_id: price_id(:plus_monthly),
        stripe_product_id: product_id(:plus),
        quantity: 1
      }
    ]

    subscription =
      customer
      |> Ecto.build_assoc(:subscriptions, Map.merge(defaults, data))
      |> BlingTest.Repo.insert!()

    Enum.concat(default_items, items)
    |> Enum.each(fn item ->
      subscription
      |> Ecto.build_assoc(:subscription_items, item)
      |> BlingTest.Repo.insert!()
    end)

    subscription |> BlingTest.Repo.preload(:subscription_items)
  end

  def price_id(price) do
    Application.get_env(:bling, :prices)[price]
  end

  def product_id(product) do
    Application.get_env(:bling, :products)[product]
  end
end
