defmodule BlingTest.User do
  use Ecto.Schema

  schema "users" do
    field(:email, :string)

    field(:stripe_id, :string)
    field(:trial_ends_at, :utc_datetime)
    field(:payment_type, :string)
    field(:payment_id, :string)
    field(:payment_last_four, :string)

    has_many(:subscriptions, BlingTest.Subscription,
      foreign_key: :customer_id,
      where: [customer_type: "user"],
      defaults: [customer_type: "user"]
    )

    timestamps()
  end
end
