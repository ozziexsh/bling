# Upgrading

## 0.2.0 -> 0.3.0

0.3.0 removed the need to have `use Bling` inside of your local `lib/my_app/bling.ex` module. This simplifies things by moving everything to a config key where it is more easily accessible.

1. Move your `use Bling` config from your `lib/my_app/bling.ex` module to `config/config.exs`:

```diff
defmodule MyApp.Bling do
-  use Bling,
-    repo: MyApp.Repo,
-    customers: [user: MyApp.Accounts.User],
-    subscription: MyApp.Subscriptions.Subscription,
-    subscription_item: MyApp.Subscriptions.SubscriptionItem
end
```

```elixir
config :bling,
  bling: MyApp.Bling, # Make sure to add this line as well
  repo: MyApp.Repo,
  customers: [user: MyApp.Accounts.User],
  subscription: MyApp.Subscriptions.Subscription,
  subscription_item: MyApp.Subscriptions.SubscriptionItem
```

2. Remove the `Bling.Plug` plug from your routes file

```diff
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug :fetch_live_flash
  plug :put_root_layout, {BankrollCheckoutWeb.Layouts, :root}
  plug :protect_from_forgery
  plug :put_secure_browser_headers
  plug :fetch_current_user
- plug Bling.Plug, bling: MyApp.Bling
end
```

3. Delete your local `my_app_web/stripe_webhook_handler.ex` and replace the reference in `my_app_web/endpoint.ex` with the bling version:

```diff
plug Stripe.WebhookPlug,
    at: "/webhooks/stripe",
-   handler: MyApp.StripeWebhookHandler,
+   handler: Bling.StripeWebhookHandler,
    secret: {Application, :get_env, [:stripity_stripe, :webhook_secret]}
```

4. Replace any references to `MyApp.Bling.module_from_customer_type`, `MyApp.Bling.customer_type_from_struct`, and `MyApp.Bling.customer_from_stripe_id` with `Bling.module_from_customer_type`, `Bling.customer_type_from_struct`, and `Bling.customer_from_stripe_id` respectively.

5. Implement the `Bling` behaviour in `lib/my_app/bling.ex` to ensure you have all of the proper callbacks.

```elixir
defmodule MyApp.Bling do
  @behaviour Bling
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
