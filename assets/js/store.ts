import { writable } from 'svelte/store';
import type { Props } from './types';

export let props = writable<Props>({
  payment_method: null,
  base_url: '',
  return_to: '/',
  finalize_url: '',
  payment_intent: null,
  setup_intent: null,
});
