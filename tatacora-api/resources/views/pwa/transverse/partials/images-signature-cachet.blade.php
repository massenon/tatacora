{{-- Signature et cachet des factures A4 et proformas (PO, 07/11 puis 10/11/2026) : l'import est
     rendu JUSTE SOUS l'interrupteur « Afficher la signature et le cachet sur les factures »
     (Identité & Légal), et reste dans Logo & Apparence. Images réduites à 400 Ko, type lu des
     OCTETS (jamais de l'extension). --}}
@foreach (['signature' => $apercuSignature, 'cachet' => $apercuCachet] as $typeImage => $apercuImage)
  <div data-image-document="{{ $typeImage }}">
    <p class="block text-[15px] font-semibold text-slate-700 mb-2">{{ __('pwa.parametres.apparence_'.$typeImage.'_titre') }}</p>
    <div class="flex items-center gap-4">
      @if ($apercuImage !== null)
        <img src="{{ $apercuImage }}" class="w-20 h-20 rounded-xl object-contain ring-2 ring-slate-100" alt="{{ __('pwa.parametres.apparence_'.$typeImage.'_titre') }}">
      @else
        <p class="text-[13px] text-slate-400">{{ __('pwa.parametres.apparence_image_absente') }}</p>
      @endif
      @if ($peutEcrire)
        <div class="flex flex-wrap gap-2">
          <button type="button" wire:click="ouvrirChangement{{ ucfirst($typeImage) }}"
                  class="btn px-3.5 py-2 rounded-lg border border-slate-200 text-[15px] font-semibold">{{ __('pwa.parametres.apparence_'.$typeImage.'_bouton') }}</button>
          @if ($apercuImage !== null)
            <button type="button" wire:click="retirer{{ ucfirst($typeImage) }}"
                    class="btn px-3.5 py-2 rounded-lg border border-slate-200 text-[15px] font-semibold text-slate-600">{{ __('pwa.parametres.apparence_retirer') }}</button>
          @endif
        </div>
      @endif
    </div>
  </div>
@endforeach
