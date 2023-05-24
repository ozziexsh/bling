<script lang="ts">
import { onMount } from 'svelte';
import { props } from './store';
import type { Props } from './types';
import { getStripe } from './stripe';
import { storePaymentMethod } from './api';
import Modal from './components/Modal.svelte';
import PaymentElement from './components/PaymentElement.svelte';
import Spin from './components/Spin.svelte';

enum SetupPaymentStatus {
  EnterPaymentInfo,
  ConfirmingPayment,
  Success,
  Error,
}

export let _props: Props;

$props = _props;

const stripe = getStripe();

let paymentIntent = $props.payment_intent;
let setupIntent = $props.setup_intent;

let paymentModalStatus: null | SetupPaymentStatus = null;
let paymentModalMessage = '';
let setupModalStatus: null | SetupPaymentStatus = null;
let setupModalMessage = '';

let pageLoading = false;
let pageError = '';

let returnUrl = $props.finalize_url;

onMount(() => {
  checkForSetupIntent();
  checkForPaymentIntent();
});

async function checkForPaymentIntent() {
  if (!paymentIntent) {
    return;
  }
  pageLoading = true;
  if (
    paymentIntent.status === 'requires_confirmation' ||
    paymentIntent.status === 'incomplete'
  ) {
    const response = await stripe.confirmPayment({
      clientSecret: $props.payment_intent.client_secret,
      redirect: 'if_required',
      confirmParams: {
        return_url: returnUrl,
      },
    });
    if (response.error) {
      pageError = response.error.message;
    }
  } else if (paymentIntent.status === 'requires_action') {
    const actionResult = await stripe.handleNextAction({
      clientSecret: paymentIntent.client_secret,
    });
    if (actionResult.error) {
      pageError = actionResult.error.message;
    } else if (actionResult.paymentIntent) {
      paymentIntent = actionResult.paymentIntent;
    }
  }
  pageLoading = false;
}

async function checkForSetupIntent() {
  if (!setupIntent) {
    return;
  }
  pageLoading = true;
  if (setupIntent.status == 'succeeded') {
    await storePaymentMethod(setupIntent.payment_method);
  } else if (setupIntent.status === 'requires_action') {
    const actionResult = await stripe.handleNextAction({
      clientSecret: setupIntent.client_secret,
    });
    if (actionResult.error) {
      pageError = actionResult.error.message;
    } else if (actionResult.setupIntent) {
      if (actionResult.setupIntent.status == 'succeeded') {
        await storePaymentMethod(setupIntent.payment_method);
      }
      setupIntent = actionResult.setupIntent;
    }
  }
  pageLoading = false;
}

function openPaymentModal() {
  paymentModalStatus = SetupPaymentStatus.EnterPaymentInfo;
  paymentModalMessage = '';
}

function closePaymentModal() {
  paymentModalStatus = null;
  paymentModalMessage = '';
}

async function onPaymentSuccess(paymentResult: { props: Props }) {
  paymentModalStatus = SetupPaymentStatus.ConfirmingPayment;
  const response = await stripe.confirmPayment({
    clientSecret: paymentIntent.client_secret,
    redirect: 'if_required',
    confirmParams: {
      return_url: returnUrl,
      payment_method: paymentResult.props.payment_method.payment_id,
    },
  });
  if (response.error) {
    paymentModalStatus = SetupPaymentStatus.Error;
    paymentModalMessage = response.error.message;
    return;
  }
  paymentModalStatus = SetupPaymentStatus.Success;
  paymentModalMessage = 'Payment succeeded. You will be redirected.';
  setTimeout(() => {
    window.location.href = $props.base_url;
  }, 2000);
}

function openSetupModal() {
  setupModalStatus = SetupPaymentStatus.EnterPaymentInfo;
  setupModalMessage = '';
}

function closeSetupModal() {
  setupModalStatus = null;
  setupModalMessage = '';
}

function onSetupSuccess() {
  setupModalStatus = SetupPaymentStatus.Success;
  setupModalMessage =
    'Payment method added successfully. You will now be redirected.';
  setTimeout(() => {
    window.location.href = $props.return_to;
  }, 2000);
}
</script>

<div class="overflow-hidden rounded-lg bg-white shadow max-w-xl mx-auto mt-24">
  <div class="px-4 py-5 sm:p-6">
    {#if paymentIntent}
      <h2 class="text-base font-semibold leading-6 text-gray-900">
        Payment for {paymentIntent.amount / 100}
        {paymentIntent.currency.toUpperCase()}
      </h2>

      <div class="mt-2 text-sm text-gray-500">
        {#if pageLoading}
          <p>Loading...</p>
        {:else if paymentIntent.status === 'succeeded'}
          <p>This payment was processed successfully.</p>

          <div class="mt-3 text-sm leading-6">
            <a
              href={$props.return_to}
              class="font-semibold text-indigo-600 hover:text-indigo-500"
            >
              Return to our home page
              <span aria-hidden="true">&rarr;</span>
            </a>
          </div>
        {:else if paymentIntent.status === 'requires_payment_method'}
          <p>
            We failed to charge your payment method on file. Please try a
            different payment method and try again.
          </p>
          <div class="mt-5">
            <button
              on:click={openPaymentModal}
              type="button"
              class="inline-flex items-center rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-500"
            >
              Update payment method
            </button>
          </div>
        {:else if paymentIntent.status === 'requires_action'}
          <p>
            Your payment method requires extra verification. You will be
            prompted or redirected shortly.
          </p>
          <div class="mt-5">
            <Spin class="text-gray-600 w-8 h-8" />
          </div>
        {:else if paymentIntent.status === 'processing'}
          <p>This payment is processing. Check back in 24-48 hours.</p>
          <div class="mt-3 text-sm leading-6">
            <a
              href={$props.return_to}
              class="font-semibold text-indigo-600 hover:text-indigo-500"
            >
              Return to our home page
              <span aria-hidden="true">&rarr;</span>
            </a>
          </div>
        {/if}
      </div>
    {/if}

    {#if setupIntent}
      <h2 class="text-base font-semibold leading-6 text-gray-900">
        Setup payment method
      </h2>

      <div class="mt-2 text-sm text-gray-500">
        {#if pageLoading}
          <p>Loading...</p>
        {:else if setupIntent.status === 'succeeded'}
          <p>Payment method successfully added.</p>
          <div class="mt-3 text-sm leading-6">
            <a
              href={$props.return_to}
              class="font-semibold text-indigo-600 hover:text-indigo-500"
            >
              Return to our home page
              <span aria-hidden="true">&rarr;</span>
            </a>
          </div>
        {:else if setupIntent.status === 'requires_payment_method'}
          <p>
            We failed to setup your payment method. Please try a different
            payment method and try again.
          </p>
          <div class="mt-5">
            <button
              on:click={openSetupModal}
              type="button"
              class="inline-flex items-center rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-500"
            >
              Update payment method
            </button>
          </div>
        {:else if setupIntent.status === 'processing'}
          <p>Payment method processing. Check back in 24-48 hours.</p>
          <div class="mt-5">
            <Spin class="text-gray-600 w-8 h-8" />
          </div>
        {/if}
      </div>
    {/if}
  </div>
</div>

<Modal visible={paymentModalStatus !== null} on:close={closePaymentModal}>
  {#if paymentModalStatus === SetupPaymentStatus.EnterPaymentInfo}
    <PaymentElement onSuccess={onPaymentSuccess} />
  {:else if paymentModalStatus === SetupPaymentStatus.ConfirmingPayment}
    <p>
      Payment method updated successfully. Please wait while we try to retry the
      payment.
    </p>
  {:else if paymentModalStatus === SetupPaymentStatus.Success || paymentModalStatus === SetupPaymentStatus.Error}
    <p>{paymentModalMessage}</p>
  {/if}
</Modal>

<Modal visible={setupModalStatus !== null} on:close={closeSetupModal}>
  {#if setupModalStatus === SetupPaymentStatus.EnterPaymentInfo}
    <PaymentElement onSuccess={onSetupSuccess} />
  {:else if setupModalStatus === SetupPaymentStatus.Success || setupModalStatus === SetupPaymentStatus.Error}
    <p>{setupModalMessage}</p>
  {/if}
</Modal>
