defmodule Bling do
  @moduledoc """
  Retreives config values and provides helper methods.
  """

  @type customer :: any
  @type conn :: Plug.Conn.t()
  @type event :: Stripe.Event.t()

  @callback can_manage_billing?(conn, customer) :: boolean
  @callback to_stripe_params(customer) :: map
  @callback tax_rate_ids(customer) :: [binary]
  @callback handle_stripe_webhook_event(event) :: any

  def bling do
    Application.get_env(:bling, :bling)
  end

  def repo do
    Application.get_env(:bling, :repo)
  end

  def customers do
    Application.get_env(:bling, :customers, [])
  end

  def subscription do
    Application.get_env(:bling, :subscription)
  end

  def subscription_item do
    Application.get_env(:bling, :subscription_item)
  end

  def module_from_customer_type(type) do
    Enum.find_value(customers(), fn {name, mod} ->
      if to_string(name) == to_string(type), do: mod, else: nil
    end)
  end

  def customer_type_from_struct(customer) do
    Enum.find_value(customers(), fn {name, mod} ->
      if customer.__struct__ == mod, do: to_string(name), else: nil
    end)
  end

  def customer_from_stripe_id(stripe_id) do
    Enum.find_value(customers(), fn {_, schema} ->
      repo().get_by(schema, stripe_id: stripe_id)
    end)
  end
end
