{{--
    ENTRÉE DE LA BARRE LATÉRALE, Article 3.1. Transcrite à l'origine de
    `construireSidebar()` de l'ancien prototype ; depuis PA-183 (10/09/2026)
    c'est CETTE vue qui fait foi, pour la PWA comme pour le client Flutter.

    ## L'état actif est UNE classe, et elle est SERVIE

    Le seul marqueur est `actif` (`class="lien-sidebar actif flex …"`). Tout
    ce qu'il donne à voir — fond doré, liseré, couleur de texte et d'icône —
    vient de `.lien-sidebar.actif` dans `public/assets/css/app.css`, et c'est
    pour cela que `la_feuille_de_style_servie_porte_les_regles_de_la_coquille()`
    (`ConformiteMaquettePwaTest`) exige ces sélecteurs.

    ⚠ La version précédente ajoutait `bg-[var(--gold-actif)] font-bold shadow-sm`
    À CÔTÉ de `actif` : trois classes que le maître ne pose pas, qui
    redoublaient la feuille de style au lieu de s'y fier. Le jour où
    `.lien-sidebar.actif` changerait, l'écran garderait l'ancien fond par-dessus
    le nouveau. Retirées.

    Le marqueur est calculé CÔTÉ SERVEUR, pas par un `wire:current` ni par un
    script : la page rend l'entrée courante déjà mise en évidence, sans dépendre
    d'un JavaScript qui, s'il cessait de s'exécuter, ne se plaindrait de rien —
    la famille PA-59/60/61. `EntreeDeMenuActivePwaTest` charge réellement deux
    écrans et vérifie que le marqueur suit.

    ## Deux branches, UNE chaîne de classes

    L'entrée devient un `<span aria-disabled>` quand sa route n'est pas
    déclarée : sans cela, `MenuLateral::pour()` fabriquerait un `href` de repli
    (`/pwa/pwa.quelque-chose`) qui mène à un 404. La règle uniforme de
    l'inertie s'applique : on change de BALISE, on gagne `aria-disabled` et un
    `title`, et on ne change AUCUNE classe. (La garde qui le vérifiait en
    comparant les deux branches au prototype, `les_classes_du_chassis_…()`, a
    été retirée le 10/09/2026 — PA-184 : elle n'avait plus de maître à qui
    comparer. La règle, elle, tient toujours.)
--}}
@php
    $hasRoute = ! empty($item['route']) && Route::has($item['route']);
    $url = $hasRoute ? route($item['route']) : '#';

    // Exacte d'abord, FAMILLE en repli (audit du 01/09/2026) — la règle vit
    // dans `MenuLateral::estActif()`, avec ses deux garde-fous : jamais deux
    // entrées allumées (« Stocks » ne s'allume pas sur « Inventaires &
    // Fiches », qui a sa propre entrée), jamais un choix arbitraire quand
    // deux entrées partagent la famille (les deux POS).
    $routeName = request()->route()?->getName() ?? '';
    $actif = $hasRoute && \App\Pwa\Support\MenuLateral::estActif($item['route'], $routeName) ? 'actif' : '';

    // ⚠ `$item['icone']` EST DÉJÀ LE TRACÉ SVG, pas une clé (31/08/2026).
    //
    // `MenuLateral::pour()` résout l'icône avant de la passer
    // (`'icone' => self::ICONES[$item['icone']] ?? …`). Cette vue la
    // relisait pourtant comme une CLÉ :
    //     ICONES[$svg] ?? ICONES[strtolower($svg)] ?? ICONES['parametres']
    // Les deux premiers indices n'existaient jamais, et le repli s'appliquait
    // à TOUTES les entrées : les vingt-quatre lignes du menu dessinaient
    // l'engrenage des « Paramètres ». Le défaut était invisible aux gardes
    // d'alors, qui comparaient le REGISTRE au prototype, jamais ce que la page
    // rend — et invisible à la relecture, parce que le `??` avait l'air d'une
    // précaution. Depuis PA-184, `les_icones_du_menu_sont_dessinees_depuis_leur_registre()`
    // lit ce que la page REND : ce défaut ferait rougir.
    //
    // Aucun repli n'est rétabli : un tracé introuvable doit faire échouer,
    // pas dessiner autre chose en silence.
    $iconeSvg = $item['icone'];
@endphp

@if ($hasRoute)
  <a href="{{ $url }}" wire:navigate
     class="lien-sidebar {{ $actif }} flex items-center gap-2.5 mx-2 px-3 py-[7px] rounded-lg text-white hover:bg-white/10 text-[14px] font-medium transition-colors">
    <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="shrink-0">{!! $iconeSvg !!}</svg>
    <span class="flex-1 truncate">{{ $item['nom'] }}</span>
    @if (! empty($item['badge']))
      <span class="text-[8px] font-bold bg-[var(--succes)] text-white rounded px-1.5 py-0.5 shrink-0">{{ $item['badge'] }}</span>
    @endif
  </a>
@else
  <span aria-disabled="true" title="{{ __('pwa.coquille.ecran_a_venir') }}"
     class="lien-sidebar {{ $actif }} flex items-center gap-2.5 mx-2 px-3 py-[7px] rounded-lg text-white hover:bg-white/10 text-[14px] font-medium transition-colors">
    <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="shrink-0">{!! $iconeSvg !!}</svg>
    <span class="flex-1 truncate">{{ $item['nom'] }}</span>
    @if (! empty($item['badge']))
      <span class="text-[8px] font-bold bg-[var(--succes)] text-white rounded px-1.5 py-0.5 shrink-0">{{ $item['badge'] }}</span>
    @endif
  </span>
@endif
