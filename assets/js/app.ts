import '../css/app.css';
import Finalize from './Finalize.svelte';
import { initStripe } from './stripe';

const el = document.getElementById('__bling-app')!;
const props = JSON.parse(el.dataset.props);

initStripe(
  document.querySelector('meta[name="stripe-pk"]').getAttribute('content'),
);

new Finalize({
  target: el,
  props: { _props: props },
});
