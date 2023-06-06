# Upgrading

## 0.2.0 -> 0.3.0

0.3.0 Introduced support for Paddle so all of the Stripe code has been moved into a new namespace.

This is a breaking change but all that is required is to update module references.

1. Replace any module calls with the following:

- `Bling.Customers` -> `Bling.Stripe.Customers`
- `Bling.Subscriptions` -> `Bling.Stripe.Subscriptions`
- `Bling.Router` -> `Bling.Stripe.Router`
- `Bling.PaymentMethod` -> `Bling.Stripe.PaymentMethod`
- `Bling.StripeWebhookHandler` -> `Bling.Stripe.StripeWebhookHandler`
- `Bling.SubscriptionBuilder` -> `Bling.Stripe.SubscriptionBuilder`

2. (optional) Add `adapter: Bling.Stripe` to your `use Bling` options. This is the default, but it is nice to be explicit.

```elixir
# my_app/lib/bling.ex
defmodule MyApp.Bling do
  use Bling,
    # ... your options
    adapter: Bling.Stripe
end
```

## 0.1.1 -> 0.2.0

0.2.0 introduced a new field `trial_ends_at` to your customer tables to accomodate generic trials.

1. Create a migration to add this to your customer tables

```elixir
alter table(:users) do
  add :trial_ends_at, :utc_datetime, null: true
end
```

2. Add the field to the ecto schema

```elixir
schema "users" do
  # ...

  field :trial_ends_at, :utc_datetime
end
```
