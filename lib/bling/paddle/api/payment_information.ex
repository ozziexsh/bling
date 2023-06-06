defmodule Bling.Paddle.Api.PaymentInformation do
  @type t() :: %{
          payment_method: binary(),
          card_type: binary(),
          last_four_digits: binary(),
          expiry_date: binary()
        }

  defstruct payment_method: nil, card_type: nil, last_four_digits: nil, expiry_date: nil

  def from_api(payment_information) do
    %Bling.Paddle.Api.PaymentInformation{
      payment_method: payment_information["payment_method"],
      card_type: payment_information["card_type"],
      last_four_digits: payment_information["last_four_digits"],
      expiry_date: payment_information["expiry_date"]
    }
  end
end
