# Bling

> If you'd like a ready-to-go interface for adding subscriptions to your Phoenix applications, check out the free product [Bankroll](https://github.com/ozziexsh/bankroll) which is built on top of this library.

`Bling` gives you an easy way to manage common billing scenarios in your own phoenix app through Stripe, making it a breeze to build custom subscription flows.

This package is almost entirely headless, meaning you are free to implement your subscription management interface however you please. Instead of a prebuilt UI, it provides schemas and functions to handle these common scenarios:

- Creating subscriptions
- Changing plans
- Cancelling & resuming
- Subscription trials
- Multiple subscriptions per customer
- Subscriptions with quantities (per-seat)
- Checking subscription status
  - Is the subscription active?
  - Is it on a trial?
  - Is it still on the grace period?
  - etc
- Saving customers default payment method
- Using any ecto schema as a customer (user, team, etc)
- Responding to failed payment attempts
- Responding to webhooks
- An isolated payment resolution page
  - If a subscription payment fails or needs authentication, you can direct your users here to fix the issues on their own
  - If setting up a payment method that requires a page redirection, you can redirect to this page to handle the result automatically

This package is influenced heavily by the amazing [Laravel Cashier](https://laravel.com/docs/10.x/billing#main-content).

`stripity_stripe` is used under the hood, so most functions accept a `stripe: %{}` parameter that is passed directly to the underlying `Stripe.*.*` function allowing you to override options as needed.

## Table of Contents

- [Installation](#installation)
- [Deploying](#deploying)
- [Bling module](#bling-module)
- [The "finalize" route](#the-finalize-route)
- [Customers](#customers)
  - [Registering customer entities](#registering-a-new-customer-entity)
  - [Payment methods](#payment-methods)
- [Subscriptions](#subscriptions)
  - [Creating subscriptions](#creating-subscriptions)
  - [Subscription quantities](#subscription-quantities)
  - [Trial periods](#trial-periods)
  - [Multiple subscriptions](#multiple-subscriptions)
  - [Changing prices/plans](#changing-prices-plans)
  - [Cancelling & resuming](#cancelling--resuming)
  - [Checking subscription status](#checking-subscription-status)
- [Webhooks](#webhooks)
- [Payment failure notifications](#payment-failure-notifications)

## Installation

> Note: Until Bling reaches `1.0.0`, breaking changes will be pushed as minor version bumps. Make sure to pin the dependency to `~> 0.x.0` to ensure you only get patch releases.

Add the module to your dependencies:

```elixir
def deps do
  [
    {:bling, "~> 0.4.1"},
    {:stripity_stripe, "~> 2.17"}
  ]
end
```

Configure stripe:

```elixir
config :stripity_stripe, api_key: "...", public_key: "...", webhook_secret: "..."
```

Run the install task. This will generate:

- A migration creating the "subscriptions" and "subscription_items" tables
- Subscription/SubscriptionItem schema's
- Bling module
- StripeWebhookHandler
- Assets

```shell
mix bling.install
```

Create a migration to add the required columns to your customer table. The command in the example below uses the "users" table but you could use anything, like "teams".

```shell
mix bling.customer users
```

Once the migration has been ran we can add the following to the corresponding module for the table we provided to the previous command:

```elixir
defmodule MyApp.Accounts.User do
  # ...

  schema "users" do
    # ...

    field :stripe_id, :string
    field :trial_ends_at, :utc_datetime
    field :payment_type, :string
    field :payment_id, :string
    field :payment_last_four, :string

    has_many :subscriptions, MyApp.Subscriptions.Subscription,
      foreign_key: :customer_id,
      where: [customer_type: "user"],
      defaults: [customer_type: "user"]
  end
end
```

We can then register all of our generated modules in the config:

```elixir
config :bling,
  bling: MyApp.Bling,
  repo: MyApp.Repo,
  customers: [user: MyApp.Accounts.User],
  subscription: MyApp.Subscriptions.Subscription,
  subscription_item: MyApp.Subscriptions.SubscriptionItem
```

We must enable route helpers:

```elixir
defmodule MyAppWeb do
  # ...

  def router do
    quote do
      use Phoenix.Router, helpers: true

  # ...
```

Open up your router file and add the Bling routes. The `bling_routes/1` macro registers two routes:

- `GET /billing/:customer_type/:customer_id/finalize` - used to resolve payment and setup issues
- `POST /billing/:customer_type/:customer_id/payment-method` - used to save a payment method to a customer, used by the finalize page

You can optionally pass a prefix to this macro to use instead of `/billing`:

```elixir
defmodule MyAppWeb.Router do
  import Bling.Router

  # ... your routes

  # create this scope separate from all of your other routes
  scope "/" do
    # make sure to authenticate your users for this route
    pipe_through [:browser, :require_authenticated_user]

    bling_routes()
  end
end
```

Open up your endpoint file and add the stripe webhook handler:

```elixir
defmodule MyAppWeb.Endpoint do
  # ...

  # this MUST be added right BEFORE the parser
  plug Stripe.WebhookPlug,
    at: "/webhooks/stripe",
    handler: Bling.StripeWebhookHandler,
    secret: {Application, :get_env, [:stripity_stripe, :webhook_secret]}

  # this should already be present
  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
```

Don't forget to register your endpoint in stripe webhook's dashboard to "/webhooks/stripe" and at least the following events:

- customer.deleted
- customer.updated
- customer.subscription.created
- customer.subscription.updated
- customer.subscription.deleted
- invoice.payment_action_required
- invoice.payment.failed

That is all! Read on to learn how to use everything.

## Deploying

The `mix bling.install` command should only be ran once.

When you are deploying, you should either commit the assets in `priv/static/assets/bling` or run the `mix bling.assets` command during deployment to ensure the required js/css is present.

## Bling module

The Bling module has a few helpful methods for deriving information:

```elixir
MyApp.Accounts.User = Bling.module_from_customer_type("user")
"user" = Bling.customer_type_from_struct(%MyApp.Accounts.User{})

# queries the registered customer modules for a matching stripe_id
%MyApp.Accounts.User{} = Bling.customer_from_stripe_id("cus_1234")
```

## Project Bling module

You will need to implement this method:

- `def can_manage_billing?(conn, customer)`
  - by default returns false, and all requests are unauthorized
  - you will want to return true if the current user (derive it yourself from `conn`) can access the billing routes for the given `customer`.

You should also implement these methods in your `MyApp.Bling` module to extend functionality:

- `def to_stripe_params(customer)`
  - return a map of valid `Stripe.Customer.create/2` params to create/update the customer with.
- `def tax_rate_ids(customer)`
  - return a list of tax rate ids as strings to apply to new subscriptions on a per-customer basis.
- `def handle_stripe_webhook_event(%Stripe.Event{} = event)`
  - handle your own stripe webhook events.

## The "finalize" route

The finalize route is used to resolve payment and setup issues. It was registered during the installation steps above.

When creating a subscription or setting up a payment method you can use this route as a redirect URL and Stripe will automatically add the proper query params.

You can also use this yourself, if you are sending payment failure emails, for example. Make sure to include a `?payment_intent=pi_xxx` or `?setup_intent=si_xxx` in the query string as it will use that to determine how to handle the situation.

If it's a payment intent, it will:

- show a success message if `status = succeeded`
- confirm the payment if `status = incomplete`
- prompt the user to update their payment method if `status = requires_payment_method`
- handle further authentication if `status = requires_action`

If it's a setup intent, it will:

- show a success message if `status = succeeded`
- prompt the user to update their payment method if `status = requires_payment_method`
- handle further authentication if `status = requires_action`

This page by default does not allow anyone to view it. Make sure to configure the `can_manage_billing?/2` function in your `MyApp.Bling` module to return true for the current user. See the "Bling module" section above for more information.

## Customers

Customers represent an entity that can have a subscription and a payment method.

For reference on functions available to customer entities, see the `Bling.Customers` module docs.

### Registering a new customer entity

Create a migration to add the required columns to your customer table. The command in the example below uses the "users" table but you could use anything, like "teams".

```shell
mix bling.customer users
```

Once the migration has been ran we can add the following to the corresponding module for the table we provided to the previous command:

```elixir
defmodule MyApp.Accounts.User do
  # ...

  schema "users" do
    # ...

    field :stripe_id, :string
    field :trial_ends_at, :utc_datetime
    field :payment_type, :string
    field :payment_id, :string
    field :payment_last_four, :string

    has_many :subscriptions, MyApp.Subscriptions.Subscription,
      foreign_key: :customer_id,
      where: [customer_type: "user"],
      defaults: [customer_type: "user"]
  end
end
```

We can then register this customer in our config:

```elixir
config :bling, customers: [user: MyApp.Accounts.User]
```

That's it!

### Creating customers in stripe

To create a customer in stripe from a customer entity:

```elixir
user = MyApp.Accounts.get(1)

Bling.Customers.create_stripe_customer(user)
```

This will merge with the data from the `to_stripe_params/1` method in your Bling module if present.

### Payment methods

A single payment method can be saved to the customer. The required columns were generated when you ran the `mix bling.customer <table>` command.

#### Creating a payment method

Customers can have a single payment method attached to them. To add a payment method, start by creating a setup intent:

```elixir
intent = Bling.Customers.create_setup_intent(customer)
```

You'll then want to forward `intent.client_secret` to your frontend's payment element and collect their payment details.

Upon submitting your setup form you can POST the payment method ID to the billing url to save it to the customer. The billing URL will depend on what you registered in your routes file and the customer type.

```javascript
const { error, setupIntent } = await stripe.confirmSetup({
  elements,
  redirect: 'if_required',
  confirmParams: {
    // you can use the "finalize" route provided by Bling if you wish to let us handle this automatically
    // e.g. example.com/billing/user/1/finalize
    return_url: returnUrl,
  },
});

if (error) {
  // handle erro
  return;
}

const response = await fetch({
  method: 'post',
  url: '/billing/user/1/payment-method',
  body: JSON.stringify({ payment_method_id: setupIntent.payment_method }),
});
```

This payment method will be saved to the customer and used for future subscriptions.

#### Updating payment method

Follow the same steps as create.

#### Getting the customers payment method

```elixir
# returns a Bling.PaymentMethod{} struct or nil
Bling.Customers.default_payment_method(customer)
```

## Subscriptions

### Creating subscriptions

Creating subscriptions is a bit complex since it is a multi-step process on stripe's side.

First, make sure your customer has a payment method configured as per [Payment Methods](#payment-methods) above.

Then we need to fetch the customer and attempt to create the subscription for them. It will create the subscription in stripe, which in return gives us a payment intent. We then attempt to confirm the payment intent. If that succeeds, we're good to go. If it doesn't, we have to handle the error appropriately to ensure the subscription gets activated.

Below is an example of how to deal with this:

```elixir
customer = MyApp.Accounts.get(1)

# you can use your own url but we provide
# a ready to go url to handle payment failures
return_url = url(~p"/billing/user/1/finalize")

result = Bling.Customers.create_subscription(
  customer,
  return_url: return_url,
  prices: [{price_id, quantity}],
  stripe: %{ coupon: "coupon_id" }, # any valid `Stripe.Subscription.create` params
)

case result do
  {:ok, subscription} ->
    # success, returns the created ecto subscription

  {:requires_action, payment_intent} ->
    # payment requires further authentication
    # pass payment_intent.client_secret to your frontend
    # to finish resolving with stripe.js `handleNextAction` method

  {:error, error} ->
    # error is %Stripe.Error{}, card could have been declined
    # pass error.user_message to frontend
end
```

It is important to handle these scenarios. If the subscription error's or requires action, you will be left with a subscription with a status of `incomplete` in your database. Stripe will leave these open for 24h before closing them, which will trigger a webhook event, which will delete it from your database.

Most billing scenarios only have a single price, but if yours has multiple you can pass multiple prices to the `prices` list:

```elixir
Bling.Customers.create_subscription(
  customer,
  return_url: finalize_url,
  prices: [
    {"price_base", 1},
    {"price_support", 1}
  ],
)
```

### Tax rates

You can configure which tax rates automatically apply to subscriptions by implementing the `tax_rate_ids/1` method in your Bling module. It should return a list of string tax rate ids for the given customer:

```elixir
defmodule MyApp.Bling do
  # ...

  def tax_rate_ids(%MyApp.Accounts.User{} = _customer), do: ["tax_rate_user_id"]
  def tax_rate_ids(%MyApp.Accounts.Team{} = _customer), do: ["tax_rate_company_id"]
  def tax_rate_ids(_customer), do: []
end
```

### Subscription quantities

You can specify an initial quantity when creating the subscription, but if you are charging "per seat" you will need to change the quantity at some point.

By default we update the quantity by one. If the subscription only has a single price, you don't need to pass an ID.

> Note: if you try to decrement below 0 you will get an error. Instead, use the `cancel` method if you are working with a single price, or `change_prices` if working with multiple.

```elixir
Bling.Subscriptions.increment(subscription)
Bling.Subscriptions.decrement(subscription)
```

You can change how much to increment/decrement by:

```elixir
Bling.Subscriptions.increment(
  subscription,
  quantity: 5
)
```

If you have multiple prices you must specify a price_id:

```elixir
Bling.Subscriptions.increment(
  subscription,
  price_id: "price_projects",
)
```

If you'd like to specify a specific quantity, you can use the set_quantity method:

```elixir
Bling.Subscriptions.set_quantity(
  subscription,
  price_id: "price_123",
  quantity: 2
)
```

All of these methods also take an optional stripe config that matches the `Stripe.SubscriptionItem.update` method:

```elixir
Bling.Subscriptions.set_quantity(
  subscription,
  price_id: "price_123",
  quantity: 2,
  stripe: %{ prorate: true }
)
```

## Trial periods

Trial periods can be configured by passing `trial_end` or `trial_period_days` as additional stripe config:

```elixir
Bling.Customers.create_subscription(
  customer,
  return_url: finalize_url,
  prices: [{price_id, quantity}],
  stripe: %{ trial_period_days: 7 },
)
```

You can check the status of a trial with these methods:

```elixir
Bling.Subscriptions.trial?(subscription)
Bling.Customers.trial?(customer)

# with explicit plan names
Bling.Subscriptions.trial?(subscription, plan: "default")
Bling.Customers.trial?(customer, plan: "default")
```

## No card upfront trials

Also known as "generic trials".

When creating a subscription with a trial, it requires a payment method to be on the customer. If you'd like to give them a trial without first setting up a payment method, you can set the `trial_ends_at` property on the customer:

```elixir
ends_at = DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.truncate(:second)

customer = MyApp.Accounts.get_by!(1)

customer
|> Ecto.Changeset.change(%{
  trial_ends_at: ends_at
})
|> MyApp.Repo.update!()
```

You can then use the `Customer.trial?/2` and `Customer.generic_trial?/1` methods to check if the customer is on a trial.

`Customer.trial?/2` will check for a generic trial on the customer or if a customer has a subscription on a trial.

`Customer.generic_trial?/1` will only check the `trial_ends_at` on the customer.

### Multiple subscriptions

By default, subscriptions are created under the hood with `plan: "default"` so applications with simple billing flows don't have to think about it.

If your application allows customers to have multiple subscriptions, you can pass a `plan` parameter to give each one a name:

```elixir
Bling.Customers.create_subscription(
  customer,
  return_url: finalize_url,
  prices: [{price_id, quantity}],
  plan: "swimming"
)
```

Then when fetching subscriptions, you can pass the plan name again as an argument:

```elixir
subscription = Bling.Customers.subscription(customer, plan: "swimming")

# also works for other methods
Bling.Customers.subscribed?(customer, plan: "swimming")
```

### Changing prices (plans)

If your customer wishes to upgrade or downgrade their plan, you can simply change the price associated with the subscription:

```elixir
subscription = Bling.Customers.subscription(customer)

Bling.Subscriptions.change_prices(subscription, prices: [{price_id, quantity}])
```

Everything in the `prices` list will act as the new "truth" for the subscription. Meaning, if your subscriptions only have a single price, you would simply put only the new price and quantity in this list. But if you have multiple prices in your subscription, you should make sure to keep the prices you want active in this list, add any new prices, and omit any prices you don't want active anymore.

You can pass extra options to this method to e.g. configure proration:

```elixir
Bling.Subscriptions.change_prices(
  subscription,
  prices: [{price_id, quantity}],
  stripe: %{ prorate: true }
)
```

### Cancelling & resuming

Subscriptions can be cancelled using any of the `cancel` methods. If the subscription is currently on a trial, the subscription will be active until the end date of the trial, not the end of the billing period.

```elixir
# cancel at end of period
Bling.Subscriptions.cancel(subscription)

# cancel immediately
Bling.Subscriptions.cancel_now(subscription)

# cancel at a specific time
Bling.Subscriptions.cancel_at(subscription, DateTime.utc_now() |> DateTime.add(7, :day))
```

### Checking subscription status

See `Bling.Subscriptions` for a full list. Common ones include:

```elixir
Bling.Subscriptions.active?(subscription)
Bling.Subscriptions.trial?(subscription)
Bling.Subscriptions.grace_period?(subscription)
Bling.Subscriptions.ended?(subscription)
```

## Webhooks

During the installation step you installed a stripe webhook handler. This takes care of responding to some events like subscription creation and updating, which are required to use some of the methods provided by this library.

If you want to handle additional events, you can do that in the Bling module. We recommend handling these two events to notify your customers that there was an issue with their payment. You can send them to the `finalize` url with a `?payment_intent=the-payment-intent-id` query string so they can resolve the issues on their own, or you can handle it another way:

```elixir
defmodule MyApp.Bling do
  def handle_stripe_webhook_event(%Stripe.Event{} = event) do
    case event.type do
      "invoice.payment_action_required" ->
        # todo: send email
        nil

      "invoice.payment.failed" ->
        # todo: send email
        nil

      _ ->
        nil
    end

    :ok
  end
end
```

## Payment failure notifications

You likely want to notify your customers when their payment fails. Luckily it's easy with Bling!

The "Webhooks" section above explained how to respond to webhooks, we'll build off of that to send the email when Stripe notifies of us an issue.

Open up your `bling.ex` file:

> Note: You may need to derive your customers email differently than the example here.

```elixir
defmodule MyApp.Bling do
  # ...

  def handle_stripe_webhook_event(%Stripe.Event{} = event) do
    case event.type do
      "invoice.payment_action_required" ->
        send_payment_failure_email(event.data.object)

      "invoice.payment.failed" ->
        send_payment_failure_email(event.data.object)

      _ ->
        nil
    end

    :ok
  end

  defp send_payment_failure_email(%Stripe.Invoice{} = invoice) do
    customer = Demo.Bling.customer_from_stripe_id(invoice.customer)
    type = Demo.Bling.customer_type_from_struct(customer)

    finalize_url = url(~p"/billing/#{type}/#{customer.id}/finalize?payment_intent=#{invoice.payment_intent}")

    email_body = """
    Your payment method requires additional action in order to proceed.

    Please visit the following link to resolve this issue to ensure your subscription remains active:

    #{finalize_url}
    """

    import Swoosh.Email

    new()
    |> to(customer.email)
    |> from({"MyApp", "contact@example.com"})
    |> subject("[Action Required] We failed to process your last payment")
    |> text_body(email_body)
    |> MyApp.Mailer.deliver()

    :ok
  end
end
```

## Contributing

Contributions are always welcome. Please open issues and submit pull requests with proper tests included.

### Running tests

The tests require you to have a `config/test.secret.exs` file setup. It should look like:

```elixir
import Config

config :stripity_stripe, api_key: ""

config :bling, ecto_repos: [BlingTest.Repo]

config :bling, BlingTest.Repo,
  username: "postgres",
  password: "postgres",
  database: "bling_test",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox

config :bling,
  products: [
    pro: "prod_123",
    plus: "prod_456"
  ],
  prices: [
    plus_monthly: "price_123",
    plus_yearly: "price_456",
    pro_monthly: "price_789",
    pro_yearly: "price_abc"
  ]

```

You can use the provided docker container for the test database:

```shell
docker compose up -d
```

The tests hit the real Stripe api so make sure to enter a test api key. This also means the tests may take a bit to run.

You will need two products in stripe, each with monthly and yearly prices. The names of them do not matter, we called them plus/pro, but enter them appropriately into the config above.
