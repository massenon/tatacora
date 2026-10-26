{{--
    POINT DE VENTE — CLIENTS HEBERGES.

    Maitre : prototype_v2/pages/pos-heberges.html.

    Trois choses a savoir avant d'y toucher :

    1. LE PANIER DE SEJOUR EST UNE TABLE (PA-161, 31/08/2026). Il vivait dans
       la session HTTP, qui expire au bout de 120 minutes, est propre a un
       navigateur et disparait a la deconnexion — pendant que le sous-titre de
       cette page promet un panier ouvert « de l'arrivee au depart ». Il vit
       desormais dans `paniers`, un seul par sejour, garanti par
       `PanierService` sous verrou.
       ⚠ Le bandeau ambre qui avertissait de cette volatilite a ete RETIRE :
       son motif a cesse d'etre vrai, et un avertissement perime fait cloturer
       par prudence un panier qui ne risque rien (PA-144). Ce qui reste vrai
       est dit a sa place. Ne remplacez jamais cette mention par « en attente
       de synchronisation » : ce panier ne part nulle part, et l'annoncer
       serait PA-59/60/61.
    2. Le maitre ne pose AUCUN filtre « Bar / Restaurant » ici, et c'est ecrit
       dans son code (l.132-138) : le client a demande « Bar, Restaurant sur le
       meme panier ; pas de panier different ». Ne pas en ajouter un.
    3. Tourisme et location ne sont PLUS proposes (directive PO du
       26/10/2026) : ni carte, ni pastille, ni mention. Le catalogue ne porte
       que le bar et le restaurant.
--}}
@php
    use App\Pwa\Support\MontantFcfa;
@endphp

<div class="contents">
  {{-- Session maintenue tant qu'un panier de séjour est ouvert sur ce poste
       (audit PO du 01/09/2026) — voir le partial. --}}
  @include('pwa.partials.maintien-session', ['maintenir' => $paniersParSejour->isNotEmpty()])
  @include('pwa.partials.barre-superieure')

  @if ($toastMessage)
    <div x-data="{ visible: true }" x-show="visible" x-init="setTimeout(() => visible = false, 6000)"
         class="fixed top-5 right-5 z-50 max-w-md flex items-start gap-3 px-4 py-3 rounded-xl shadow-xl text-white text-[13px] font-medium no-print
         {{ $toastType === 'success' ? 'bg-emerald-600' : ($toastType === 'error' ? 'bg-red-600' : 'bg-slate-700') }}">
      <span>{{ $toastMessage }}</span>
      <button type="button" @click="visible = false" class="ml-2 text-white/80 hover:text-white">✕</button>
    </div>
  @endif

  @if (session('pwa-succes'))
    <div x-data="{ visible: true }" x-show="visible" x-init="setTimeout(() => visible = false, 6000)"
         class="fixed top-5 right-5 z-50 max-w-md px-4 py-3 rounded-xl shadow-xl bg-emerald-600 text-white text-[13px] font-medium no-print">
      {{ session('pwa-succes') }}
    </div>
  @endif

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')

    <main class="flex-1 overflow-hidden flex flex-col">

      {{-- EN-TETE — maitre, pos-heberges.html l.22-33 --}}
      <div class="shrink-0 px-5 py-3 border-b border-slate-200 bg-white flex flex-wrap items-start justify-between gap-3">
        <div class="min-w-0">
          <h1 class="text-[15px] font-bold" style="color:var(--navy)">{{ __('pos_pwa.heberges.titre') }}</h1>
          <p class="text-[12px] text-slate-500 mt-0.5 max-w-3xl">{{ __('pos_pwa.heberges.sous_titre') }}</p>
        </div>

        <div class="flex items-center gap-2.5">
          <div class="rounded-lg border border-slate-200 bg-white px-3 py-2 text-right">
            <p class="text-[10px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('pos_pwa.heberges.kpi_paniers') }}</p>
            <p class="text-[15px] font-bold tabular-nums" style="color:var(--navy)">{{ $paniersOuverts }}</p>
          </div>
          <div class="rounded-lg border border-slate-200 bg-white px-3 py-2 text-right">
            <p class="text-[10px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('pos_pwa.heberges.kpi_encours') }}</p>
            <p class="text-[15px] font-bold tabular-nums" style="color:var(--gold)">{{ MontantFcfa::format($encoursSejours) }}</p>
          </div>
        </div>
      </div>

      <div class="flex-1 overflow-hidden flex flex-col xl:flex-row">

        {{-- 1. SEJOURS EN COURS — maitre, pos-heberges.html l.36-42 --}}
        <section class="xl:w-[320px] shrink-0 overflow-y-auto border-b xl:border-b-0 xl:border-r border-slate-200 bg-white">
          <div class="px-4 py-3 border-b border-slate-200 sticky top-0 bg-white z-10">
            <h2 class="text-[13px] font-bold" style="color:var(--navy)">{{ __('pos_pwa.heberges.sejours') }}</h2>
            <p class="text-[11px] text-slate-400 mt-0.5">{{ __('pos_pwa.heberges.sejours_aide') }}</p>
          </div>

          @if ($sejours->isEmpty())
            <p class="px-4 py-10 text-center text-[13px] text-slate-400">{{ __('pos_pwa.heberges.sejours_vide') }}</p>
          @else
            @foreach ($sejours as $sejour)
              @php
                // Le panier REEL du sejour, ou `null`. Le total vient du
                // modele : le recalculer ici donnerait une seconde arithmetique
                // du meme panier.
                $panierSejour = $paniersParSejour[$sejour->id] ?? null;
                $totalSejour = $panierSejour?->total() ?? '0.00';
              @endphp
              <button type="button" wire:click="$set('selectedReservationId', '{{ $sejour->id }}')"
                wire:key="sejour-{{ $sejour->id }}"
                class="w-full text-left px-4 py-3 border-b border-slate-100 border-l-4 {{ $selectedReservationId === $sejour->id ? 'bg-slate-50 border-l-[var(--gold)]' : 'hover:bg-slate-50 border-l-transparent' }}">
                <div class="flex items-start justify-between gap-2">
                  <p class="text-[13px] font-bold min-w-0 truncate" style="color:var(--navy)">
                    {{ $sejour->client?->nom }} {{ $sejour->client?->prenom }}
                  </p>
                  @if ($panierSejour === null)
                    <span class="shrink-0 text-[10px] font-bold px-2 py-0.5 rounded-full bg-slate-100 text-slate-500 border border-slate-200">{{ __('pos_pwa.heberges.badge_aucun_panier') }}</span>
                  @else
                    <span class="shrink-0 text-[10px] font-bold px-2 py-0.5 rounded-full bg-emerald-50 text-emerald-700 border border-emerald-200">{{ __('pos_pwa.heberges.badge_panier_ouvert') }}</span>
                  @endif
                </div>
                <p class="text-[11px] text-slate-500 mt-0.5">
                  {{ $sejour->unite?->numero }} · {{ __('pos_pwa.heberges.depart_prevu', ['date' => $sejour->date_depart->format('d/m/Y')]) }}
                </p>
                @if ($panierSejour !== null)
                  <p class="text-[12px] font-bold mt-1" style="color:var(--gold)">
                    {{ MontantFcfa::format($totalSejour) }}
                    <span class="font-normal text-slate-400">· {{ $panierSejour->lignes->count() }}</span>
                  </p>
                @endif
              </button>
            @endforeach
          @endif
        </section>

        {{-- 2. CATALOGUE MULTI-SERVICES --}}
        <section class="flex-1 overflow-hidden flex flex-col bg-slate-50/50">
          <div class="shrink-0 px-5 pt-4 pb-2 bg-white border-b border-slate-100">
            <input type="search" wire:model.live.debounce.250ms="recherche"
              placeholder="{{ __('pos_pwa.heberges.rechercher') }}"
              class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2 bg-white focus:border-[var(--gold)] focus:outline-none mb-3">

            <div class="flex gap-1.5 overflow-x-auto pb-2">
              @foreach ($categories as $cle => $libelle)
                <button type="button" wire:click="$set('categorieActive', '{{ $cle }}')" wire:key="cath-{{ $cle }}"
                  class="shrink-0 px-3.5 py-1.5 rounded-full text-[12px] font-semibold {{ $categorieActive === $cle ? 'bg-[var(--navy)] text-white' : 'bg-white border border-slate-300 text-slate-600 hover:border-[var(--gold)]' }}">
                  {{ $libelle }}
                </button>
              @endforeach
            </div>
          </div>

          <div class="flex-1 overflow-y-auto px-5 py-4">
            @if ($catalogue->isEmpty())
              <p class="py-16 text-center text-[13px] text-slate-400">{{ __('pos_pwa.commun.catalogue_vide') }}</p>
            @else
              <div class="grid grid-cols-2 md:grid-cols-3 2xl:grid-cols-4 gap-3">
                @foreach ($catalogue as $item)
                  @php
                    $tarifConnu = bccomp((string) $item['prix'], '0.00', 2) > 0;
                    $ajoutable = $tarifConnu && $selectedReservationId !== null;
                  @endphp
                  <button type="button"
                    wire:click="ajouterAuPanier('{{ $item['module'] }}', '{{ $item['reference_id'] }}')"
                    wire:key="art-{{ $item['module'] }}-{{ $item['reference_id'] }}"
                    @disabled(! $ajoutable)
                    class="text-left p-3 rounded-xl border {{ $ajoutable ? 'bg-white border-slate-200 hover:border-[var(--gold)] hover:shadow-sm' : 'bg-slate-50 border-slate-200 opacity-60 cursor-not-allowed' }}">
                    <p class="text-[12px] font-semibold leading-tight" style="color:var(--navy)">{{ $item['nom'] }}</p>
                    <p class="text-[12px] font-bold mt-1.5 {{ $tarifConnu ? '' : 'text-red-600' }}" style="{{ $tarifConnu ? 'color:var(--gold)' : '' }}">
                      {{ $tarifConnu ? MontantFcfa::format((string) $item['prix']) : __('pos_pwa.heberges.tarif_manquant') }}
                    </p>
                    <span class="text-[10px] text-slate-400 mt-0.5 block">{{ $item['famille'] }}</span>
                  </button>
                @endforeach
              </div>
            @endif
          </div>
        </section>

        {{-- 3. PANIER DU SEJOUR --}}
        <section class="w-full xl:w-[380px] shrink-0 overflow-hidden flex flex-col border-t xl:border-t-0 xl:border-l border-slate-200 bg-white">
          <div class="shrink-0 px-4 py-3 border-b border-slate-200 bg-slate-50">
            <h2 class="text-[13px] font-bold" style="color:var(--navy)">
              {{ $reservationActive?->client?->nom ?? __('pos_pwa.heberges.panier') }}
            </h2>
            @if ($reservationActive)
              <p class="text-[11px] text-slate-400 mt-0.5">
                {{ __('pos_pwa.heberges.depart_prevu', ['date' => $reservationActive->date_depart->format('d/m/Y')]) }}
              </p>
            @endif
          </div>

          <div class="flex-1 overflow-y-auto">
            @if (! $selectedReservationId)
              <p class="px-4 py-16 text-center text-[13px] text-slate-400">{{ __('pos_pwa.heberges.panier_aucun_sejour') }}</p>
            @elseif (! $panier || $panier->lignes->isEmpty())
              <p class="px-4 py-16 text-center text-[13px] text-slate-400">{{ __('pos_pwa.heberges.panier_vide') }}</p>
            @else
              @foreach ($panier->lignes as $ligne)
                <div class="px-4 py-2.5 border-b border-slate-100 flex items-center gap-3" wire:key="lp-{{ $ligne->id }}">
                  <div class="flex-1 min-w-0">
                    <p class="text-[12px] font-semibold truncate" style="color:var(--navy)">{{ $ligne->libelle }}</p>
                    <p class="text-[11px] text-slate-400">
                      {{ MontantFcfa::format((string) $ligne->prix_unitaire) }} · {{ $modules[$ligne->module] ?? $ligne->module }}
                    </p>
                  </div>
                  <div class="flex items-center gap-1.5 shrink-0">
                    <button type="button" wire:click="decrementerLigne('{{ $ligne->id }}')"
                            class="w-6 h-6 rounded border border-slate-300 hover:bg-slate-50 font-bold text-[13px] leading-none">−</button>
                    <span class="text-[12px] font-bold w-6 text-center">{{ $ligne->quantite }}</span>
                    <button type="button" wire:click="incrementerLigne('{{ $ligne->id }}')"
                            class="w-6 h-6 rounded border border-slate-300 hover:bg-slate-50 font-bold text-[13px] leading-none">+</button>
                  </div>
                  <p class="text-[12px] font-bold w-20 text-right shrink-0" style="color:var(--navy)">
                    {{ MontantFcfa::format($ligne->montant()) }}
                  </p>
                  <button type="button" wire:click="retirerLigne('{{ $ligne->id }}')"
                          class="text-slate-300 hover:text-red-600 text-lg leading-none shrink-0">✕</button>
                </div>
              @endforeach
            @endif
          </div>

          <div class="shrink-0 border-t border-slate-200 p-4 bg-slate-50">
            @if (count($ventilation) > 1)
              <div class="flex flex-wrap gap-1.5 mb-3">
                @foreach ($ventilation as $moduleVentile => $montantVentile)
                  <span class="text-[10px] px-2 py-0.5 rounded-full bg-slate-100 text-slate-600 font-medium" wire:key="vent-{{ $moduleVentile }}">
                    {{ $modules[$moduleVentile] ?? $moduleVentile }} : {{ MontantFcfa::format($montantVentile) }}
                  </span>
                @endforeach
              </div>
            @endif

            <div class="flex items-center justify-between mb-1">
              <span class="text-[13px] font-semibold text-slate-600">{{ __('pos_pwa.heberges.total_sejour') }}</span>
              <span class="text-[19px] font-bold" style="color:var(--navy)">{{ MontantFcfa::format($totalNet) }}</span>
            </div>

            {{--
                REMISE — ajout hors maitre, directive PO du 02/09/2026
                (structure-ajout:pos-heberges.html#remise). Le montant et le
                net viennent du modele (`Panier::remiseSur()`, auteur unique).
            --}}
            <div class="flex items-center gap-2 mb-1">
              <label for="remise-type-sejour" class="text-[11px] font-semibold text-slate-500 shrink-0">{{ __('pos_pwa.commun.remise') }}</label>
              <select id="remise-type-sejour" wire:model="remiseType" wire:change="appliquerRemise"
                      class="text-[12px] border border-slate-300 rounded-lg px-2 py-1.5 bg-white">
                <option value="aucune">{{ __('pos_pwa.commun.remise_aucune') }}</option>
                <option value="pourcentage">%</option>
                <option value="montant">FCFA</option>
              </select>
              <input id="remise-valeur-sejour" type="number" min="0" wire:model="remiseValeur" wire:change="appliquerRemise"
                     aria-label="{{ __('pos_pwa.commun.remise_valeur') }}"
                     class="w-full text-[12px] border border-slate-300 rounded-lg px-2 py-1.5 bg-white">
            </div>
            @error('remiseValeur')
              <p class="text-[11px] text-red-600 mb-1">{{ $message }}</p>
            @enderror
            @if (bccomp($remisePanier, '0.00', 2) > 0)
              <div class="flex justify-between text-[11.5px] text-slate-500 mb-2">
                <span>{{ __('pos_pwa.commun.remise_appliquee', ['brut' => MontantFcfa::format($totalPanier)]) }}</span>
                <span>- {{ MontantFcfa::format($remisePanier) }}</span>
              </div>
            @else
              <div class="mb-2"></div>
            @endif

            <button type="button" wire:click="ouvrirClotureSejour" @disabled(! $panier || $panier->lignes->isEmpty())
              class="w-full text-[13px] px-4 py-2.5 rounded-lg font-semibold bg-[var(--gold)] text-[var(--navy)] hover:brightness-110 disabled:opacity-40">
              {{ __('pos_pwa.heberges.cloturer') }}
            </button>
          </div>
        </section>

      </div>
    </main>
  </div>

  {{--
      MODALE DE CLOTURE — une cloture anticipee est possible, JAMAIS
      silencieuse (PA-98). Le maitre pose la meme question avant le depart.

      RECAPITULATIF + TOGGLE « Payer separement » — directive PO du
      02/09/2026 (amendement de RG-04 : deux paiements separes, l'hebergement
      sera facture plus tard par son propre chemin). Les montants viennent du
      composant — la MEME source que la facturation, jamais une seconde
      arithmetique de vue.
  --}}
  @if ($etatFormulaire === 'cloture')
    <x-pwa.modale :titre="__('pos_pwa.heberges.cloture_titre')"
                  :sousTitre="__('pos_pwa.heberges.cloture_message')"
                  largeur="520px">
      <p class="text-[12px] text-slate-500">{{ __('pos_pwa.heberges.cloture_detail') }}</p>

      {{-- BLOC HEBERGEMENT — nuitees × tarif, et le toggle. --}}
      <div class="border border-slate-200 rounded-lg p-3">
        <div class="flex items-center justify-between">
          <span class="text-[12px] font-bold uppercase tracking-wide text-slate-500">{{ __('pos_pwa.heberges.cloture_bloc_hebergement') }}</span>
          <span class="text-[13px] font-bold tabular-nums" style="color:var(--navy)">{{ MontantFcfa::format($totalHebergement) }}</span>
        </div>
        <p class="text-[12px] text-slate-500 mt-1">
          {{ __('pos_pwa.heberges.cloture_nuitees', [
              'nuitees' => $nuiteesActives,
              'tarif' => MontantFcfa::format($tarifNuitActif),
          ]) }}
        </p>
        <label class="flex items-center gap-2 mt-2 text-[12px] text-slate-600 cursor-pointer">
          {{-- Coche = TOUT facturer ; decochee = payer separement. Le sens
               est inverse du libelle du toggle, donc le libelle dit
               exactement ce que la case decochee produit. --}}
          <input type="checkbox" wire:model.live="payerSeparement" class="rounded border-slate-300">
          <span>{{ __('pos_pwa.heberges.cloture_payer_separement') }}</span>
        </label>
        @if ($payerSeparement)
          {{-- Le RAPPEL exige par la directive : ce qui restera du, en
               toutes lettres, avant que le doigt ne clique. --}}
          <p class="text-[12px] text-amber-800 bg-amber-50 border border-amber-200 rounded-lg px-3 py-2 mt-2">
            {{ __('pos_pwa.heberges.cloture_rappel_hebergement', [
                'nuitees' => $nuiteesActives,
                'tarif' => MontantFcfa::format($tarifNuitActif),
            ]) }}
          </p>
        @endif
      </div>

      {{-- BLOC CONSOMMATIONS — les lignes du panier, quantites et montants. --}}
      <div class="border border-slate-200 rounded-lg p-3">
        <div class="flex items-center justify-between">
          <span class="text-[12px] font-bold uppercase tracking-wide text-slate-500">{{ __('pos_pwa.heberges.cloture_bloc_consommations') }}</span>
          <span class="text-[13px] font-bold tabular-nums" style="color:var(--navy)">{{ MontantFcfa::format($totalNet) }}</span>
        </div>
        <div class="mt-1.5 space-y-1">
          @if ($panier)
            @foreach ($panier->lignes as $ligneCloture)
              <div class="flex justify-between text-[12px] text-slate-600" wire:key="cl-{{ $ligneCloture->id }}">
                <span class="min-w-0 truncate">{{ $ligneCloture->libelle }} × {{ $ligneCloture->quantite }}</span>
                <span class="tabular-nums shrink-0">{{ MontantFcfa::format($ligneCloture->montant()) }}</span>
              </div>
            @endforeach
          @endif
          @if (bccomp($remisePanier, '0.00', 2) > 0)
            <div class="flex justify-between text-[12px] text-slate-500 border-t border-slate-100 pt-1">
              <span>{{ __('pos_pwa.commun.remise') }}</span>
              <span class="tabular-nums">- {{ MontantFcfa::format($remisePanier) }}</span>
            </div>
          @endif
        </div>
      </div>

      {{-- TOTAL FACTURE — depend du toggle : la modale affiche EXACTEMENT ce
           que la facture portera. bcmath, jamais une addition flottante. --}}
      <div class="flex items-baseline justify-between border-t border-slate-100 pt-3">
        <span class="text-[13px] font-semibold text-slate-600">{{ __('pos_pwa.heberges.cloture_total_facture') }}</span>
        <span class="text-[17px] font-bold" style="color:var(--navy)">
          {{ MontantFcfa::format($payerSeparement ? $totalNet : bcadd($totalHebergement, $totalNet, 2)) }}
        </span>
      </div>

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        {{-- « Facture » — le bouton qui execute (directive PO 02/09/2026). --}}
        <button type="button" wire:click="cloturerEtFacturer"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('pos_pwa.heberges.cloture_facture') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

</div>
