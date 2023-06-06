defmodule Bling.Stripe.PaymentMethod do
  @moduledoc """
  A struct to normalize stripe sources.
  """

  @type t :: %{
          id: String.t(),
          type: String.t(),
          last_four: String.t() | nil,
          card_brand: String.t() | nil
        }

  defstruct id: nil, type: nil, last_four: nil, card_brand: nil

  @doc """
  Given a stripe source, card, or payment method, returns a Bling.PaymentMethod struct or nil.
  """
  def from_source(%Stripe.Card{} = source) do
    %Bling.Stripe.PaymentMethod{
      id: source.id,
      type: "card",
      last_four: source.last4,
      card_brand: source.brand
    }
  end

  def from_source(%Stripe.Source{} = source) do
    %Bling.Stripe.PaymentMethod{
      id: source.id,
      type: source.type,
      last_four: if(source.type == "card", do: source.card.last4, else: nil),
      card_brand: if(source.type == "card", do: source.card.brand, else: nil)
    }
  end

  def from_source(%Stripe.PaymentMethod{} = source) do
    %Bling.Stripe.PaymentMethod{
      id: source.id,
      type: source.type,
      last_four: if(source.type == "card", do: source.card.last4, else: nil),
      card_brand: if(source.type == "card", do: source.card.brand, else: nil)
    }
  end

  def from_source(_source), do: nil
end
