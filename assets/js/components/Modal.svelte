<script lang="ts">
import { createEventDispatcher } from 'svelte';
import { scale, fade } from 'svelte/transition';

type Size = 'sm' | 'md' | 'lg' | 'xl' | '2xl' | '3xl' | '4xl';

export let visible;
export let size: Size = 'lg';

let sizeMap = {
  sm: 'sm:max-w-sm',
  md: 'sm:max-w-md',
  lg: 'sm:max-w-lg',
  xl: 'sm:max-w-xl',
  '2xl': 'sm:max-w-2xl',
  '3xl': 'sm:max-w-3xl',
  '4xl': 'sm:max-w-4xl',
};

const dispatch = createEventDispatcher();
</script>

{#if visible}
  <div
    class="relative z-10"
    aria-labelledby="modal-title"
    role="dialog"
    aria-modal="true"
  >
    <div
      class="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity"
      transition:fade={{ duration: 250 }}
    />

    <div class="fixed inset-0 z-10 overflow-y-auto">
      <!-- svelte-ignore a11y-click-events-have-key-events -->
      <div
        class="flex min-h-full items-end justify-center p-4 text-center sm:items-center sm:p-0"
        on:click={() => dispatch('close')}
      >
        <div
          transition:scale={{ duration: 250 }}
          class={`relative transform overflow-hidden rounded-lg bg-white px-4 pb-4 pt-5 text-left shadow-xl transition-all sm:my-8 sm:w-full ${sizeMap[size]} sm:p-6`}
          on:click={e => e.stopPropagation()}
        >
          <slot />
        </div>
      </div>
    </div>
  </div>
{/if}
