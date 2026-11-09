{{--
    GABARIT COMMUN DES PAGES D'ERREUR — le seul qui porte le design.

    Chaque `errors/<code>.blade.php` n'est qu'un `@extends` qui nomme son code,
    son pictogramme et ses actions ; tout texte vient de `lang/fr/erreurs.php`.

    Variables (posées par la vue fille) :
      $code          code HTTP (déduit de l'exception si absent : vues 4xx/5xx)
      $pictogramme   recherche | cadenas | horloge | attention | outil | serveur
      $actions       1 à 2 parmi accueil | reessayer | recharger | connexion | reconnexion
      $incident      true : affiche l'identifiant d'incident (erreurs serveur)
      $rafraichir    secondes avant rafraîchissement automatique (503)

    Page AUTONOME par conception : une erreur peut survenir sans base, sans
    session, hors de toute route. Donc ni Livewire, ni Tailwind, ni script,
    ni favicon lu en base (`pwa.partials.tete` en dépend), ni ressource
    distante — la feuille de style est embarquée, le logo et la police Inter
    sont les fichiers locaux de l'application. Aucune donnée de l'exception
    (message, fichier, requête) n'est jamais lue ici.

    Contrastes (WCAG AA, calculés) : marine #14213D sur blanc 15,5:1 ; texte
    secondaire #475569 sur blanc 7,6:1 ; blanc sur marine 15,5:1. L'or #B8891E
    (3,2:1 sur blanc) ne porte QUE des filets et le contour de focus, jamais
    du texte.
--}}
@php
    $statut = (int) ($code ?? (isset($exception) && method_exists($exception, 'getStatusCode') ? $exception->getStatusCode() : 500));
    $cle = \Illuminate\Support\Facades\Lang::has("erreurs.{$statut}")
        ? (string) $statut
        : ($statut >= 500 ? 'generique_5xx' : 'generique_4xx');
    $pictogramme = $pictogramme ?? ($statut >= 500 ? 'serveur' : 'attention');
    $connecte = \App\Http\Support\PageErreur::estConnecte();
    $delai = \App\Http\Support\PageErreur::delaiAvantNouvelEssai($exception ?? null);
    $numeroIncident = ($incident ?? ($statut >= 500 && $statut !== 503)) && isset($exception)
        ? \App\Http\Support\PageErreur::incident($exception)
        : null;

    // « Réessayer » rouvre l'adresse demandée ; « Recharger » (419) rouvre la
    // page d'où l'on vient seulement si elle est de CE site — jamais un lien
    // externe repris d'un en-tête Referer.
    $adresse = request()->fullUrl();
    $origine = url()->previous(route('pwa.accueil'));
    $adresseRechargement = str_starts_with($origine, url('/')) ? $origine : route('pwa.accueil');

    $liens = [];
    foreach (($actions ?? ['accueil']) as $action) {
        if ($action === 'connexion' && $connecte) {
            continue;
        }
        $liens[] = match ($action) {
            'accueil' => ['href' => route('pwa.accueil'), 'texte' => __($connecte ? 'erreurs.actions.accueil_connecte' : 'erreurs.actions.accueil_invite'), 'icone' => 'retour'],
            'reessayer' => ['href' => $adresse, 'texte' => __('erreurs.actions.reessayer'), 'icone' => 'recharger'],
            'recharger' => ['href' => $adresseRechargement, 'texte' => __('erreurs.actions.recharger'), 'icone' => 'recharger'],
            'connexion' => ['href' => route('pwa.connexion'), 'texte' => __('erreurs.actions.connexion'), 'icone' => 'cle'],
            'reconnexion' => ['href' => route('pwa.connexion'), 'texte' => __('erreurs.actions.reconnexion'), 'icone' => 'cle'],
        };
    }
    $liens = array_slice($liens, 0, 2) ?: [['href' => route('pwa.accueil'), 'texte' => __('erreurs.actions.accueil_invite'), 'icone' => 'retour']];
    $titre = __("erreurs.{$cle}.titre");
@endphp
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="robots" content="noindex">
<meta name="theme-color" content="#14213D">
@isset($rafraichir)
<meta http-equiv="refresh" content="{{ (int) $rafraichir }}">
@endisset
<title>{{ __('erreurs.titre_page', ['titre' => $titre]) }}</title>
<link rel="icon" href="{{ asset('assets/img/logo.png') }}">
<link rel="stylesheet" href="{{ asset('assets/css/vendor/fonts.css') }}">
<style>
  :root {
    --navy: #14213D;
    --gold: #B8891E;
    --fond-clair: #F2F2F2;
    --texte-secondaire: #475569;
    --bordure: #E2E8F0;
  }
  * { box-sizing: border-box; }
  html { -webkit-text-size-adjust: 100%; }
  body {
    margin: 0;
    min-height: 100vh;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 24px 16px;
    background: var(--fond-clair);
    color: var(--navy);
    font-family: 'Inter', system-ui, -apple-system, 'Segoe UI', Roboto, Arial, sans-serif;
    line-height: 1.5;
  }
  .carte {
    width: 100%;
    max-width: 560px;
    background: #FFFFFF;
    border-radius: 16px;
    border-top: 4px solid var(--gold);
    box-shadow: 0 1px 2px rgba(20,33,61,.06), 0 12px 32px rgba(20,33,61,.10);
    padding: 32px 24px 28px;
    text-align: center;
  }
  .marque { display: inline-flex; align-items: center; gap: 10px; margin-bottom: 24px; }
  .marque img { width: 48px; height: 48px; object-fit: contain; border-radius: 10px; box-shadow: 0 0 0 2px var(--gold); background: #FFFFFF; }
  .marque span { font-weight: 600; font-size: 15px; letter-spacing: .02em; }
  .pictogramme {
    width: 72px; height: 72px; margin: 0 auto 8px;
    border-radius: 50%;
    background: var(--navy);
    color: #FFFFFF;
    display: flex; align-items: center; justify-content: center;
    box-shadow: 0 0 0 4px #FFFFFF, 0 0 0 6px var(--gold);
  }
  .pictogramme svg { width: 36px; height: 36px; }
  .code { margin: 18px 0 0; font-size: 56px; font-weight: 700; letter-spacing: -.02em; line-height: 1; }
  .filet { width: 48px; height: 4px; border-radius: 2px; background: var(--gold); margin: 14px auto 0; }
  h1 { margin: 16px 0 0; font-size: 22px; line-height: 1.25; font-weight: 700; overflow-wrap: anywhere; }
  .message { margin: 12px auto 0; max-width: 440px; font-size: 15px; color: var(--texte-secondaire); }
  .aide {
    margin: 24px 0 0;
    padding: 16px 18px;
    text-align: left;
    background: var(--fond-clair);
    border-left: 4px solid var(--navy);
    border-radius: 8px;
  }
  .aide h2 { margin: 0 0 8px; font-size: 14px; font-weight: 600; }
  .aide ul { margin: 0; padding-left: 18px; font-size: 14px; color: var(--texte-secondaire); }
  .aide li + li { margin-top: 4px; }
  .note { margin: 16px 0 0; font-size: 13px; color: var(--texte-secondaire); }
  .incident { display: inline-block; margin-top: 4px; padding: 2px 10px; border-radius: 6px; background: var(--fond-clair); color: var(--navy); font-family: 'JetBrains Mono', ui-monospace, Menlo, Consolas, monospace; font-weight: 600; letter-spacing: .04em; user-select: all; }
  .actions { display: flex; flex-wrap: wrap; justify-content: center; gap: 12px; margin-top: 28px; }
  .bouton {
    display: inline-flex; align-items: center; justify-content: center; gap: 8px;
    min-height: 44px; padding: 10px 20px;
    border-radius: 10px; border: 2px solid var(--navy);
    font: inherit; font-size: 14px; font-weight: 600; text-decoration: none;
    background: var(--navy); color: #FFFFFF;
  }
  .bouton.secondaire { background: #FFFFFF; color: var(--navy); }
  .bouton:hover { filter: brightness(1.15); }
  .bouton.secondaire:hover { background: var(--fond-clair); filter: none; }
  .bouton:focus-visible { outline: 3px solid var(--gold); outline-offset: 3px; }
  .bouton svg { width: 16px; height: 16px; flex: none; }
  @media (max-width: 400px) {
    .carte { padding: 24px 16px 20px; border-radius: 12px; }
    .code { font-size: 44px; }
    h1 { font-size: 20px; }
    .actions { flex-direction: column; }
    .bouton { width: 100%; }
  }
  @media (prefers-reduced-motion: no-preference) {
    .carte { animation: apparition .25s ease-out; }
    @keyframes apparition { from { opacity: 0; transform: translateY(6px); } to { opacity: 1; transform: none; } }
  }
</style>
</head>
<body>
<main class="carte" @if ($statut === 503) role="status" @endif>

  <div class="marque">
    <img src="{{ asset('assets/img/logo.png') }}" alt="{{ __('pwa.alt_logo') }}" width="48" height="48">
    <span>{{ __('erreurs.marque') }}</span>
  </div>

  <div class="pictogramme" aria-hidden="true">
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" focusable="false">
      @switch ($pictogramme)
        @case ('recherche')
          <circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3M8.5 11h5"/>
          @break
        @case ('cadenas')
          <rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 018 0v4M12 15v2"/>
          @break
        @case ('horloge')
          <circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>
          @break
        @case ('outil')
          <path d="M14.7 6.3a1 1 0 000 1.4l1.6 1.6a1 1 0 001.4 0l3.77-3.77a6 6 0 01-7.94 7.94l-6.91 6.91a2.12 2.12 0 01-3-3l6.91-6.91a6 6 0 017.94-7.94l-3.76 3.76z"/>
          @break
        @case ('serveur')
          <rect x="3" y="4" width="18" height="6" rx="1.5"/><rect x="3" y="14" width="18" height="6" rx="1.5"/><path d="M7 7h.01M7 17h.01M12 10v4"/>
          @break
        @default
          <path d="M12 3L2 20h20L12 3zM12 10v4M12 17h.01"/>
      @endswitch
    </svg>
  </div>

  <p class="code" aria-label="{{ __('erreurs.code_libelle', ['code' => $statut]) }}">{{ $statut }}</p>
  <div class="filet" aria-hidden="true"></div>

  <h1>{{ $titre }}</h1>
  <p class="message">{{ __("erreurs.{$cle}.message") }}</p>

  @if ($delai !== null)
    <p class="note">{{ __('erreurs.delai', ['secondes' => $delai]) }}</p>
  @endif

  <section class="aide" aria-labelledby="titre-aide">
    <h2 id="titre-aide">{{ __('erreurs.que_faire') }}</h2>
    <ul>
      @foreach ((array) __("erreurs.{$cle}.aide") as $conseil)
        <li>{{ $conseil }}</li>
      @endforeach
    </ul>
  </section>

  @isset($rafraichir)
    <p class="note">{{ __('erreurs.rafraichissement') }}</p>
  @endisset

  @if ($numeroIncident !== null)
    <p class="note">{{ __('erreurs.incident_libelle') }}<br><span class="incident">{{ $numeroIncident }}</span></p>
  @endif

  <nav class="actions">
    @foreach ($liens as $i => $lien)
      <a href="{{ $lien['href'] }}" class="bouton{{ $i > 0 ? ' secondaire' : '' }}">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">
          @if ($lien['icone'] === 'retour')
            <path d="M19 12H5M12 19l-7-7 7-7"/>
          @elseif ($lien['icone'] === 'recharger')
            <path d="M21 12a9 9 0 11-3-6.7M21 4v5h-5"/>
          @else
            <circle cx="8" cy="15" r="4"/><path d="M11 12l9-9M16 7l3 3"/>
          @endif
        </svg>
        {{ $lien['texte'] }}
      </a>
    @endforeach
  </nav>

</main>
</body>
</html>
