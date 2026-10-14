<!DOCTYPE html>
<html lang="fr">
<head>
{{--
    PAGE 404 — aucun équivalent au maître, `prototype_v2/` ne maquette pas
    d'écran d'erreur (voir `lang/fr/pwa.php`, section `erreur_404`).

    Habillée aux couleurs de la coquille PWA plutôt que la page blanche par
    défaut de Laravel, avec les MÊMES assets vendorisés que le reste de
    l'application (`pwa.partials.tete` : logo, Tailwind local, `app.css`) —
    aucune ressource distante, y compris sur une erreur, sur un serveur
    mutualisé cPanel sans garantie de sortie réseau.

    Volontairement LÉGÈRE : ni Livewire, ni session, ni menu latéral — une
    404 peut survenir avant toute authentification, et la coquille complète
    (`layouts.pwa`) suppose un utilisateur connecté pour son menu filtré RBAC.
--}}
@include('pwa.partials.tete', ['titre' => __('pwa.erreur_404.titre_page')])
</head>
<body class="h-screen w-screen flex flex-col items-center justify-center px-6 text-center" style="background:var(--fond-clair)">

  {{-- Logo PNG paysage (decision du PO du 14/10/2026, D392) : cadre garde,
       `object-contain` au lieu d'`object-cover` (qui rognait). PA-210. --}}
  <img src="{{ asset('assets/img/logo.png') }}" alt="{{ __('pwa.alt_logo') }}" class="w-16 h-16 rounded-xl mb-6 ring-2 ring-[var(--gold)] object-contain">

  <p class="text-6xl font-bold tracking-tight" style="color:var(--navy)">404</p>
  <h1 class="text-xl md:text-2xl font-bold mt-3" style="color:var(--navy)">{{ __('pwa.erreur_404.titre') }}</h1>
  <p class="text-slate-500 text-[15px] mt-3 max-w-md leading-relaxed">{{ __('pwa.erreur_404.explication') }}</p>

  <a href="{{ route('pwa.accueil') }}"
     class="mt-8 inline-flex items-center gap-2 px-5 py-2.5 rounded-lg text-white text-sm font-semibold"
     style="background:var(--navy)">
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M19 12H5M12 19l-7-7 7-7"/></svg>
    {{ __('pwa.erreur_404.retour') }}
  </a>

</body>
</html>
