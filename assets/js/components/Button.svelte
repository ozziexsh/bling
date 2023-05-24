<script lang="ts">
import Spin from './Spin.svelte';

type Variant = 'default' | 'danger' | 'danger-ghost' | 'info-ghost' | 'basic';

export let loading: boolean = false;
export let variant: Variant = 'default';

const classMap = {
  default:
    'shadow-sm bg-black text-white hover:bg-gray-800 focus-visible:outline-gray-600',
  danger: 'shadow-sm bg-red-600 text-white hover:bg-red-500',
  'danger-ghost': 'text-red-500 hover:bg-red-200 focus-visible:outline-red-100',
  'info-ghost':
    'text-blue-500 hover:bg-blue-200 focus-visible:outline-blue-100',
  basic:
    'shadow-sm bg-white text-gray-900 ring-1 ring-inset ring-gray-300 hover:bg-gray-50',
};
</script>

<button
  {...$$props}
  disabled={$$props.disabled || loading}
  class={`inline-flex items-center rounded-md px-2.5 py-1.5 text-sm disabled:bg-opacity-70 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 ${classMap[variant]} ${$$props.class}`}
  on:click
>
  {#if loading}
    <Spin class="w-4 h-4 mr-2" />
  {/if}
  <slot />
</button>
