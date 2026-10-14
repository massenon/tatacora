<!DOCTYPE html>
<html lang="fr">
<head>
{{-- `$title` est la variable que Livewire alimente (`#[Title]` et le second
     argument de `->layout()`) ; `$titre` n'est posée par personne. Voir le
     bloc du même sujet dans `layouts/pwa.blade.php`. --}}
@include('pwa.partials.tete', ['titre' => $titre ?? $title ?? __('pwa.connexion.titre_page')])

{!! $styles ?? '' !!}
@livewireStyles
</head>
<body class="{{ $classeBody ?? 'h-screen flex' }}" style="{{ $styleBody ?? 'background:var(--fond-clair)' }}">
    {{ $slot }}
    @livewireScripts
<script>
    // Surface non authentifiee : la page de repli hors connexion lit ce
    // drapeau pour choisir sa variante (« Se connecter » plutot que le
    // rappel de session). Pose ici et remis a 1 par la coquille : c'est un
    // indice d'affichage, jamais une donnee d'authentification.
    try { localStorage.setItem('pwa-session-active', '0'); } catch (e) { /* sans stockage : variante non connectee par defaut */ }
</script>
</body>
</html>
