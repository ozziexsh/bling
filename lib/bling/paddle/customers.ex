defmodule Bling.Paddle.Customers do
  alias Bling.Util
  alias Bling.Entity
  alias Bling.Paddle.Subscriptions

  @default_name "default"

  @doc """
  Fetches all subscriptions for a customer.
  """
  def subscriptions(customer) do
    repo = Entity.repo(customer)

    customer
    |> repo.preload(subscriptions: [:subscription_items])
    |> Map.get(:subscriptions, [])
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
  end

  @doc """
  Fetches a single subscription for a customer by plan name.

  ## Examples
      # gets subscription with name "default"
      subscription = Bling.Paddle.Customers.subscription(customer)

      # gets subscription with specific name
      subscription = Bling.Paddle.Customers.subscription(customer, plan: "pro")
  """
  def subscription(customer, opts \\ []) do
    name = name_from_opts(opts)
    customer |> subscriptions() |> Enum.find(&(&1.name == name))
  end

  @doc """
  Returns whether or not the customer is subscribed to a plan, and that plan is valid.

  ## Examples
      # checks if the customer is subscribed to the default plan
      Bling.Paddle.Customers.subscribed?(customer)

      # checks if the customer is subscribed to a specific plan
      Bling.Paddle.Customers.subscribed?(customer, plan: "pro")
  """
  def subscribed?(customer, opts \\ []) do
    name = name_from_opts(opts)

    customer
    |> subscriptions()
    |> Enum.filter(&Subscriptions.valid?/1)
    |> Enum.map(& &1.name)
    |> Enum.member?(name)
  end

  @doc """
  Returns true if the customer is on a generic trial or if the specified subscription is on a trial.

  ## Examples

      # checks trial_ends_at on customer and "default" subscription plan
      Bling.Paddle.Customers.trial?(customer)

      # checks trial_ends_at on customer and "swimming" subscription plan
      Bling.Paddle.Customers.trial?(customer, plan: "swimming")
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
  create_subscription(
    customer,
    name: "default",
    product_id: "abcd",
    quantity: 1,
    return_url: "http://localhost/return",
    coupon_code: "abcd",
    passthrough: %{},
    prices: ["USD:123", "CAD:321"],
    trial_days: 0,
    ...extra
  )
  """
  def create_subscription(customer, opts) do
    name = name_from_opts(opts)
    payload = Keyword.drop(opts, [:name])
    metadata = Keyword.get(opts, :passthrough, %{})

    passthrough =
      Map.merge(
        %{
          subscription_name: name
        },
        metadata
      )

    payload =
      payload
      |> Keyword.merge(passthrough: passthrough)
      |> maybe_add_trial()
      |> maybe_add_prices()

    generate_pay_link(customer, payload)
  end

  def generate_pay_link(customer, opts) do
    bling = Entity.bling(customer)
    customer_params = Util.maybe_call({bling, :paddle_customer_info, [customer]}, %{})

    passthrough =
      opts
      |> Keyword.get(:passthrough, %{})
      |> Map.put(:customer_id, customer.id)
      |> Map.put(:customer_type, bling.customer_type_from_struct(customer))
      |> Jason.encode!()

    opts
    |> Keyword.put_new(:customer_email, Map.get(customer_params, :email))
    |> Keyword.put_new(:customer_country, Map.get(customer_params, :country))
    |> Keyword.put_new(:customer_postcode, Map.get(customer_params, :postcode))
    |> Keyword.merge(passthrough: passthrough)
    |> Enum.into(%{})
    |> IO.inspect()
    |> Bling.Paddle.Api.generate_pay_link()
    |> Map.get("url")
  end

  defp maybe_add_trial(payload) do
    trial_days = Keyword.get(payload, :trial_days, nil)

    cond do
      not is_nil(trial_days) -> Keyword.put(payload, :trial_days, trial_days)
      true -> payload
    end
  end

  # Paddle will immediately charge the plan price for the trial days so we'll
  # need to explicitly set the prices to 0 for the first charge. If there's
  # no trial, we use the recurring_prices to charge the user immediately.
  defp maybe_add_prices(payload) do
    cond do
      Keyword.has_key?(payload, :prices) ->
        payload

      not Keyword.has_key?(payload, :trial_days) ->
        payload

      true ->
        plan = Map.get(payload[:passthrough], :subscription_name)
        trialing? = payload[:trial_days] != 0
        response = Bling.Paddle.Api.subscription_plans(%{plan: plan}) |> List.first()
        key = if trialing?, do: "initial_price", else: "recurring_price"
        prices = Map.get(response, key, %{})

        prices =
          prices
          |> Enum.reduce([], fn {currency, price}, acc ->
            amount = if trialing?, do: 0, else: price
            ["#{currency}:#{amount}" | acc]
          end)
          |> Enum.reverse()

        Keyword.put(payload, :prices, prices)
    end
  end

  defp name_from_opts(opts), do: Keyword.get(opts, :name, @default_name)
end
