import wretch from 'wretch';
import type { Props } from './types';

const el = document.getElementById('__bling-app')!;
const props = JSON.parse(el.dataset.props);

const url = new URL(props.base_url);
url.search = '';

export const api = wretch(url.toString(), { mode: 'cors' }).headers({
  'x-csrf-token': document
    .querySelector('meta[name="csrf-token"]')
    .getAttribute('content'),
});

export function storePaymentMethod(paymentMethodId: string) {
  return api
    .url('/store-payment')
    .post({ payment_method_id: paymentMethodId })
    .json<{ props: Props }>();
}
