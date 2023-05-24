<script lang="ts">
import { api } from '../api';
import { props } from '../store';
import { getStripe } from '../stripe';
import type { Props } from '../types';
import Button from './Button.svelte';
import { onMount } from 'svelte';

export let onSuccess: (response: { props: Props }) => void;

export let returnUrl = $props.finalize_url;

enum PaymentStatus {
  GettingClientSecret,
  EnteringCardInfo,
  Submitting,
  Success,
  Error,
}

const stripe = getStripe();
let clientSecret: string | null = null;
let elements;
let setupError = '';
let paymentStatus = PaymentStatus.GettingClientSecret;

onMount(async () => {
  paymentStatus = PaymentStatus.GettingClientSecret;
  await setupPaymentMethod();
  paymentStatus = PaymentStatus.EnteringCardInfo;
});

async function setupPaymentMethod() {
  const response = await api
    .url('/setup-payment')
    .post()
    .json<{ client_secret: string }>();
  clientSecret = response.client_secret;
}

function setupStripeElement(el: HTMLDivElement) {
  elements = stripe.elements({
    clientSecret: clientSecret,
  });
  const paymentElement = elements.create('payment');
  paymentElement.mount(`#${el.id}`);
}

async function submitPaymentMethod() {
  paymentStatus = PaymentStatus.Submitting;

  const { error, setupIntent } = await stripe.confirmSetup({
    elements,
    redirect: 'if_required',
    confirmParams: {
      return_url: returnUrl,
    },
  });

  if (error) {
    paymentStatus = PaymentStatus.Error;
    setupError = error.message;
    return;
  }

  if (!setupIntent) {
    paymentStatus = PaymentStatus.Error;
    setupError = 'Something went wrong. Please try again.';
    return;
  }

  const response = await api
    .url('/store-payment')
    .post({ payment_method_id: setupIntent.payment_method })
    .json<{ props: Props }>();

  onSuccess(response);

  // maybe won't reach if redirected, but some may succeed instantly
  paymentStatus = PaymentStatus.Success;
}
</script>

{#if paymentStatus === PaymentStatus.GettingClientSecret}
  <p>Loading...</p>
{:else if paymentStatus === PaymentStatus.Success}
  <p>Success!</p>
{:else if clientSecret}
  <form on:submit|preventDefault={submitPaymentMethod}>
    <div id="stripe-payment-form" use:setupStripeElement />

    {#if setupError}
      <p class="text-red-600 mt-2">{setupError}</p>
    {/if}

    <div class="mt-4">
      <Button
        type="submit"
        disabled={paymentStatus === PaymentStatus.Submitting}
        class="w-full justify-center"
      >
        Save
      </Button>
    </div>
  </form>
{/if}
