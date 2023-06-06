defmodule Bling.Paddle.UserSubscription do
  @type t() :: %{
          subscription_id: integer(),
          plan_id: integer(),
          user_id: integer(),
          user_email: binary(),
          marketing_consent: boolean(),
          update_url: binary(),
          cancel_url: binary(),
          state: binary(),
          signup_date: binary(),
          last_payment: %{
            amount: integer(),
            currency: binary(),
            date: binary()
          },
          payment_information: Bling.Paddle.Api.PaymentInformation.t(),
          quantity: integer(),
          next_payment: %{
            amount: integer(),
            currency: binary(),
            date: binary()
          }
        }

  defstruct [
    :plan_id,
    :user_id,
    :user_email,
    :marketing_consent,
    :update_url,
    :cancel_url,
    :state,
    :signup_date,
    :last_payment,
    :payment_information,
    :quantity,
    :next_payment
  ]
end
