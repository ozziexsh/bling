defmodule Bling.Customers do
  @moduledoc """
  Module for interacting with Bling customers. Each method expects the first argument to be an ecto struct.
  """

  alias Bling.PaymentMethod
  alias Bling.Subscriptions

  @default_plan "default"

  import Ecto.Changeset, only: [change: 2]

  @doc """
  Fetches all subscriptions for a customer.
  """
  def subscriptions(customer) do
    repo = Bling.repo()

    customer
    |> repo.preload(subscriptions: [:subscription_items])
    |> Map.get(:subscriptions, [])
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
  end

  @doc """
  Fetches a single subscription for a customer by plan name.

  ## Examples
      # gets subscription with name "default"
      subscription = Bling.Customers.subscription(customer)

      # gets subscription with specific name
      subscription = Bling.Customers.subscription(customer, plan: "pro")
  """
  def subscription(customer, opts \\ []) do
    name = plan_from_opts(opts)
    customer |> subscriptions() |> Enum.find(&(&1.name == name))
  end

  @doc """
  Returns whether or not the customer is subscribed to a plan, and that plan is valid.

  ## Examples
      # checks if the customer is subscribed to the default plan
      Bling.Customers.subscribed?(customer)

      # checks if the customer is subscribed to a specific plan
      Bling.Customers.subscribed?(customer, plan: "pro")
  """
  def subscribed?(customer, opts \\ []) do
    name = plan_from_opts(opts)

    customer
    |> subscriptions()
    |> Enum.filter(&Subscriptions.valid?/1)
    |> Enum.map(& &1.name)
    |> Enum.member?(name)
  end

  @doc """
  Returns whether or not the customer is subscribed to a specific product and the subscription is valid.

  ## Examples
      # checks if the customer is subscribed to a product on the default plan
      Bling.Customers.subscribed_to_product?(customer, "prod_123")

      # checks if the customer is subscribed to a product on a specific plan
      Bling.Customers.subscribed_to_product?(customer, "prod_123", plan: "pro")
  """
  def subscribed_to_product?(customer, product, opts \\ []) do
    name = plan_from_opts(opts)

    customer
    |> subscriptions()
    |> Enum.filter(&Subscriptions.valid?/1)
    |> Enum.filter(&(&1.name == name))
    |> Enum.flat_map(fn sub -> Enum.map(sub.subscription_items, & &1.stripe_product_id) end)
    |> Enum.member?(product)
  end

  @doc """
  Returns whether or not the customer is subscribed to a specific price and the subscription is valid.

  ## Examples
      # checks if the customer is subscribed to a price on the default plan
      Bling.Customers.subscribed_to_price?(customer, "price_123")

      # checks if the customer is subscribed to a price on a specific plan
      Bling.Customers.subscribed_to_price?(customer, "price_123", plan: "pro")
  """
  def subscribed_to_price?(customer, price, opts \\ []) do
    name = plan_from_opts(opts)

    customer
    |> subscriptions()
    |> Enum.filter(&Subscriptions.valid?/1)
    |> Enum.filter(&(&1.name == name))
    |> Enum.flat_map(fn sub -> Enum.map(sub.subscription_items, & &1.stripe_price_id) end)
    |> Enum.member?(price)
  end

  @doc """
  Returns true if the customer is on a generic trial or if the specified subscription is on a trial.

  ## Examples

      # checks trial_ends_at on customer and "default" subscription plan
      Bling.Customers.trial?(customer)

      # checks trial_ends_at on customer and "swimming" subscription plan
      Bling.Customers.trial?(customer, plan: "swimming")
  """
  def trial?(customer, opts \\ []) do
    subscription = subscription(customer, opts)

    cond do
      generic_trial?(customer) -> true
      is_nil(subscription) -> false
      Subscriptions.trial?(subscription) -> true
      true -> false
    end
  end

  @doc """
  Returns whether the customer is on a generic trial.

  Checks the `trial_ends_at` column on the customer.
  """
  def generic_trial?(%{trial_ends_at: nil} = _customer), do: false

  def generic_trial?(customer) do
    ends_at = DateTime.compare(customer.trial_ends_at, DateTime.utc_now())

    ends_at == :gt
  end

  @doc """
  Creates a customer in stripe from the given database customer. If `to_stripe_params/1` is present on your Bling module,
  the map returned there will be merged with the params passed to stripe.

  ## Examples
      # Can pass any valid Stripe.customer.create/1 params.
      customer = Bling.Customers.create_stripe_customer(current_user, stripe: %{ name: "Jane Doe" })
  """
  def create_stripe_customer(customer, opts \\ []) do
    stripe_params = stripe_params(opts)
    bling = Bling.bling()
    customer_metadata = Bling.Util.maybe_call({bling, :to_stripe_params, [customer]}, %{})

    params = Map.merge(customer_metadata, stripe_params)

    {:ok, stripe_customer} = Stripe.Customer.create(params)

    repo = Bling.repo()
    customer |> change(%{stripe_id: stripe_customer.id}) |> repo.update!()
  end

  @doc """
  Returns the stripe customer for the given database customer.
  """
  def as_stripe_customer(customer) do
    {:ok, stripe_customer} = Stripe.Customer.retrieve(customer.stripe_id)
    stripe_customer
  end

  @doc """
  Creates a setup intent for the given customer. Defaults to off_session usage.

  ## Examples
      intent = Bling.Customers.create_setup_intent(current_user)

      # Can pass any valid Stripe.SetupIntent.create/1 params.
      intent = Bling.Customers.create_setup_intent(current_user, stripe: %{ payment_method_types: ["card"] })
  """
  def create_setup_intent(customer, opts \\ []) do
    stripe_params = stripe_params(opts)

    params =
      Map.merge(
        %{
          customer: customer.stripe_id,
          usage: "off_session"
        },
        stripe_params
      )

    {:ok, intent} = Stripe.SetupIntent.create(params)

    intent
  end

  @doc """
  Returns the defauly payment method for a customer, or nil. The payment method returned is a Bling.PaymentMethod struct.
  """
  def default_payment_method(customer) do
    result =
      Stripe.Customer.retrieve(customer.stripe_id,
        expand: ["default_source", "invoice_settings.default_payment_method"]
      )

    case result do
      {:ok, stripe_customer} ->
        with payment_method when not is_nil(payment_method) <-
               stripe_customer.invoice_settings.default_payment_method do
          PaymentMethod.from_source(payment_method)
        else
          _ ->
            if is_nil(stripe_customer.default_source) do
              nil
            else
              PaymentMethod.from_source(stripe_customer.default_source)
            end
        end

      _ ->
        nil
    end
  end

  @doc """
  Updates the customer's default payment method with the one stored in stripe.
  """
  def update_default_payment_method_from_stripe(customer) do
    repo = Bling.repo()
    payment_method = default_payment_method(customer)

    case payment_method do
      nil ->
        customer
        |> change(%{
          payment_id: nil,
          payment_type: nil,
          payment_last_four: nil
        })
        |> repo.update!()

      _ ->
        customer
        |> change(%{
          payment_id: payment_method.id,
          payment_type: payment_method.type,
          payment_last_four: payment_method.last_four
        })
        |> repo.update!()
    end
  end

  @doc """
  Updates the customers default payment method with the provided payment_method_id.
  """
  def update_default_payment_method(customer, payment_method_id) do
    repo = Bling.repo()

    Stripe.Customer.update(customer.stripe_id, %{
      invoice_settings: %{default_payment_method: payment_method_id}
    })

    payment_method = default_payment_method(customer)

    customer
    |> change(%{
      payment_id: payment_method.id,
      payment_type: payment_method.type,
      payment_last_four: payment_method.last_four
    })
    |> repo.update!()
  end

  @doc """
  Returns whether the customer has a default payment method.
  """
  def has_default_payment_method?(customer) do
    !!customer.payment_id
  end

  @doc """
  Creates a subscription in stripe and stores it in the database. Tries to confirm the payment immediately.
  If the payment requires further authentication or errors, the subscription will be marked as incomplete and you
  must use the payment intent to confirm the payment on your frontend.

  https://stripe.com/docs/billing/subscriptions/overview

  ## Examples
      result =
        create_subscription(
          current_user,
          return_url: "http://localhost:4000/billing/user/1/finalize", # the route you configured during installation
          prices: [{price_id, quantity}],
          plan: "default", # can be omitted
          stripe: %{ coupon: "coupon_id" }, # any valid Stripe.Subscription.create/1 params
        )

      case result do
        {:ok, subscription} -> # success, db subscription
        {:requires_action, payment_intent} -> # payment requires further authentication
        {:error, error} -> # Stripe.Error, card could have been declined
      end
  """
  def create_subscription(customer, opts \\ []) do
    name = plan_from_opts(opts)
    stripe_params = stripe_params(opts)
    return_url = opts[:return_url]
    repo = Bling.repo()
    prices = opts[:prices]

    items = prices |> Enum.map(fn {id, quantity} -> %{price: id, quantity: quantity} end)

    params =
      %{
        customer: customer.stripe_id,
        items: items,
        payment_behavior: "default_incomplete",
        metadata: %{"name" => name},
        default_payment_method: customer.payment_id,
        expand: ["latest_invoice"]
      }
      |> Map.merge(stripe_params)
      |> maybe_add_tax(customer)

    case Stripe.Subscription.create(params) do
      {:error, errors} ->
        {:error, errors}

      {:ok, stripe_subscription} ->
        case maybe_confirm(stripe_subscription, return_url) do
          {:error, error} ->
            {:error, error}

          {:ok, %{status: "requires_action"} = payment_intent} ->
            {:requires_action, payment_intent}

          {:ok, _payment_intent} ->
            # "subscription created" webhook may have already been handled by here
            # need to reload the subscription after payment intent confirmation
            {:ok, stripe_subscription} = Stripe.Subscription.retrieve(stripe_subscription.id)
            subscription = maybe_create_subscription(customer, stripe_subscription)

            {:ok, subscription |> repo.preload(:subscription_items)}
        end
    end
  end

  @doc """
  Returns all Stripe.Invoice structs for a customer.

  ## Examples
      invoices = invoices(current_user)

      # Can pass any valid Stripe.Invoice.list/1 params.
      invocies = invoices(current_user, stripe: %{ limit: 10 })
  """
  def invoices(customer, opts \\ []) do
    stripe_params = stripe_params(opts)
    params = Map.merge(stripe_params, %{customer: customer.stripe_id})

    {:ok, invoices} = Stripe.Invoice.list(params)

    invoices.data
  end

  @doc """
  Creates and returns a url to the stripe billing portal.

  ## Examples

      url = billing_portal_url(customer, stripe: %{ return_url: "http://localhost:4000/users/settings" } })
  """
  def billing_portal_url(customer, opts \\ []) do
    stripe_params = stripe_params(opts)

    params =
      Map.merge(
        %{
          customer: customer.stripe_id
        },
        stripe_params
      )

    {:ok, %Stripe.BillingPortal.Session{} = session} = Stripe.BillingPortal.Session.create(params)

    session.url
  end

  @doc """
  Creates and returns a url to make a new subscription using stripe checkout.

  ## Examples
      url = subscription_checkout_url(customer,
        plan: "default",
        prices: [{price_id, quantity}]
        stripe: %{
          cancel_url: "http://localhost:4000/users/settings",
          success_url: "http://localhost:4000/users/settings"
      })
  """
  def subscription_checkout_url(customer, opts \\ []) do
    name = plan_from_opts(opts)
    stripe_params = stripe_params(opts)

    line_items =
      opts
      |> Keyword.get(:prices, [])
      |> Enum.map(fn {price, quantity} -> %{price: price, quantity: quantity} end)

    provided_sub_data = stripe_params |> Map.get(:subscription_data, %{})
    provided_meta = provided_sub_data |> Map.get(:metadata, %{})

    metadata =
      Map.merge(provided_meta, %{
        "name" => name
      })

    subscription_data =
      provided_sub_data |> maybe_add_tax(customer) |> Map.merge(%{metadata: metadata})

    default_params = %{
      customer: customer.stripe_id,
      mode: "subscription",
      line_items: line_items,
      subscription_data: subscription_data
    }

    params = Map.merge(stripe_params, default_params)

    {:ok, %Stripe.Checkout.Session{} = session} = Stripe.Checkout.Session.create(params)

    session.url
  end

  defp maybe_confirm(%{latest_invoice: %{payment_intent: nil}}, _return_url), do: {:ok, nil}

  defp maybe_confirm(%{status: "incomplete"} = stripe_subscription, return_url) do
    Stripe.PaymentIntent.confirm(stripe_subscription.latest_invoice.payment_intent, %{
      return_url: return_url
    })
  end

  defp maybe_confirm(stripe_subscription, _) do
    Stripe.PaymentIntent.retrieve(stripe_subscription.latest_invoice.payment_intent, %{})
  end

  defp maybe_create_subscription(customer, stripe_subscription) do
    repo = Bling.repo()
    existing = subscriptions(customer) |> Enum.find(&(&1.stripe_id == stripe_subscription.id))

    if existing do
      existing
    else
      subscription =
        customer
        |> Ecto.build_assoc(:subscriptions)
        |> Subscriptions.subscription_struct_from_stripe_subscription(stripe_subscription)
        |> repo.insert!()

      subscription_items =
        Subscriptions.subscription_item_structs_from_stripe_items(
          stripe_subscription.items.data,
          subscription
        )

      Enum.each(subscription_items, fn item -> repo.insert!(item) end)

      subscription
    end
  end

  defp build_opts(opts, defaults \\ %{}) do
    opts = opts |> Enum.into(%{})

    Map.merge(defaults, opts)
  end

  defp plan_from_opts(opts), do: Keyword.get(opts, :plan, @default_plan)

  defp stripe_params(opts), do: opts |> Keyword.get(:stripe, []) |> build_opts()

  defp maybe_add_tax(params, customer) do
    bling = Bling.bling()
    tax_rates = Bling.Util.maybe_call({bling, :tax_rate_ids, [customer]}, [])

    cond do
      is_list(tax_rates) && tax_rates != [] -> Map.merge(params, %{default_tax_rates: tax_rates})
      true -> params
    end
  end
end
