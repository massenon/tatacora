{{--
    Les DEUX modales d'ouverture de session — maître :
    `prototype_v2/assets/js/alertes-ouverture.js` (`coquille()` et `bloc()`).

    Le CONTENEUR passe par le châssis unique `<x-pwa.modale>` (02/09/2026,
    garde `ChassisModalePwaTest` : aucun conteneur redéclaré à la main — le
    premier jet en portait un, avec le voile doublé et sans borne de hauteur
    que le châssis existe précisément pour empêcher). Ce qui vient du maître
    d'alertes-ouverture est conservé DANS le gabarit du châssis : triangle
    d'avertissement sur fond #FDF3E0 en tête de corps, compteur « i / total »
    dans le sous-titre, blocs colorés (stock #C62828, départs #1D4ED8,
    créances #ED6C02), bouton « Suivant → » puis « J'ai pris connaissance ».

    Rendue UNIQUEMENT quand le drapeau de session de la connexion est présent
    et que la bascule des alertes est ouverte — jamais au GET ordinaire.
--}}
<div>
  @if ($etapes !== [])
    <x-pwa.modale
      :titre="$courante['nom'] === 'stock' ? __('pwa.alertes_ouverture.titre_stock') : __('pwa.alertes_ouverture.titre_operations')"
      :sousTitre="($courante['nom'] === 'stock' ? __('pwa.alertes_ouverture.sous_titre_stock') : __('pwa.alertes_ouverture.sous_titre_operations'))
          . ($total > 1 ? ' — ' . $etape . ' / ' . $total : '')"
      largeur="672px"
      fermer="avancer">

      @error('alerte_ouverture')
        <div class="rounded-lg px-3.5 py-2.5 text-[13px]" style="background:#FDECEC;color:#8C1D1D">{{ $message }}</div>
      @enderror

      @if ($courante['nom'] === 'stock')
        @include('pwa.transverse.partials.bloc-alerte-ouverture', [
          'titre' => __('pwa.alertes_ouverture.bloc_stock_titre'),
          'sousTitre' => __('pwa.alertes_ouverture.bloc_stock_sous_titre'),
          'couleur' => '#C62828',
          'icone' => '<path stroke-linecap="round" stroke-linejoin="round" d="M21 8l-9-5-9 5 9 5 9-5zM3 8v8l9 5 9-5V8M12 13v8"/>',
          'lignes' => $courante['stock'],
          'lien' => route('pwa.stocks.liste'),
          'libelleLien' => __('pwa.alertes_ouverture.lien_stocks'),
          'gabaritAction' => null,
        ])
      @else
        @if (($courante['departs'] ?? []) !== [])
          @include('pwa.transverse.partials.bloc-alerte-ouverture', [
            'titre' => __('pwa.alertes_ouverture.bloc_departs_titre'),
            'sousTitre' => __('pwa.alertes_ouverture.bloc_departs_sous_titre'),
            'couleur' => '#1D4ED8',
            'icone' => '<rect x="3" y="4" width="18" height="18" rx="2"/><path stroke-linecap="round" stroke-linejoin="round" d="M16 2v4M8 2v4M3 10h18"/>',
            'lignes' => $courante['departs'],
            'lien' => route('pwa.hebergement', ['onglet' => 'reservations']),
            'libelleLien' => __('pwa.alertes_ouverture.lien_reservations'),
            'gabaritAction' => 'checkout',
          ])
        @endif
        @if (($courante['creances'] ?? []) !== [])
          @include('pwa.transverse.partials.bloc-alerte-ouverture', [
            'titre' => __('pwa.alertes_ouverture.bloc_creances_titre'),
            'sousTitre' => __('pwa.alertes_ouverture.bloc_creances_sous_titre'),
            'couleur' => '#ED6C02',
            'icone' => '<path stroke-linecap="round" stroke-linejoin="round" d="M12 2v20M17 5H9.5a3.5 3.5 0 000 7h5a3.5 3.5 0 010 7H6"/>',
            'lignes' => $courante['creances'],
            'lien' => route('pwa.clients'),
            'libelleLien' => __('pwa.alertes_ouverture.lien_creances'),
            'gabaritAction' => 'relance',
          ])
        @endif
      @endif

      <x-slot:pied>
        <button type="button" wire:click="avancer"
                class="btn px-5 py-2.5 rounded-lg text-white text-sm font-semibold" style="background:var(--navy)">
          {{ $etape < $total ? __('pwa.alertes_ouverture.suivant') : __('pwa.alertes_ouverture.pris_connaissance') }}
        </button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif
</div>
