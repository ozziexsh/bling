let stripe: any = null;

export function initStripe(pk: string) {
  stripe = (window as any).Stripe(pk);
}

export function getStripe() {
  return stripe;
}
