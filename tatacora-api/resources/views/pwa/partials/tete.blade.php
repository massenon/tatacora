
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{{ $titre ?? __('pwa.marque') }}</title>
{{-- Favicon televerse (onglet Logo & Apparence, 02/09/2026), actif livre en repli. --}}
<link rel="icon" href="{{ app(\App\Shared\Parametres\Services\ApparenceEtablissementService::class)->urlFavicon() }}">
<link rel="manifest" href="{{ asset('manifest.json') }}">
<meta name="theme-color" content="#14213D">
{{-- Apercu social (partage d'un lien : WhatsApp, Facebook, LinkedIn, Messages) : image 1280x640 versee dans public/assets/img. --}}
<meta property="og:type" content="website">
<meta property="og:site_name" content="{{ __('pwa.marque') }}">
<meta property="og:title" content="{{ $titre ?? __('pwa.marque') }}">
<meta property="og:description" content="{{ __('pwa.apercu_social_description') }}">
<meta property="og:image" content="{{ asset('assets/img/social-preview.png') }}">
<meta property="og:image:width" content="1280">
<meta property="og:image:height" content="640">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:image" content="{{ asset('assets/img/social-preview.png') }}">
<script src="{{ asset('assets/js/vendor/tailwind-play-cdn.js') }}"></script>
<script>tailwind.config = { theme: { extend: { colors: { navy:'#14213D', gold:'#B8891E' } } } };</script>
<link rel="stylesheet" href="{{ asset('assets/css/app.css') }}">
{{-- Le service worker s'enregistre ICI, sur TOUTES les surfaces, depuis le
     02/09/2026 (directive PO : la page de repli doit s'afficher hors
     connexion a la place de l'erreur du navigateur). Il ne vivait que dans
     le layout authentifie : un poste qui n'avait jamais depasse l'ecran de
     connexion n'avait AUCUN repli — le defaut exact que le PO a constate.
     Auteur unique : ce partial ; ne pas le reenregistrer ailleurs. --}}
<script>
    if ('serviceWorker' in navigator) {
        window.addEventListener('load', () => navigator.serviceWorker.register('/sw.js'));
    }
</script>
