type PaymentIntentStatus =
  | 'requires_confirmation'
  | 'requires_payment_method'
  | 'requires_action'
  | 'succeeded'
  | 'processing'
  | 'incomplete';

export interface PaymentIntent {
  id: string;
  client_secret: string;
  amount: number;
  status: PaymentIntentStatus;
  currency: string;
}

export type SetupIntentStatus =
  | 'succeeded'
  | 'requires_payment_method'
  | 'requires_action'
  | 'processing';

export interface SetupIntent {
  id: string;
  status: SetupIntentStatus;
  payment_method: string | null;
  client_secret: string | null;
}

export interface Props {
  base_url: string;
  finalize_url: string;
  return_to: string;
  payment_intent: null | PaymentIntent;
  setup_intent: null | SetupIntent;
  payment_method: null | {
    payment_id: string;
    payment_type: string;
    payment_last_four: string;
  };
}
