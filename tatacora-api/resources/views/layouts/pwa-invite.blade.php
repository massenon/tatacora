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
    {{-- « Votre session a expiré » : caché par défaut, montré par
         `pwa.partials.session-expiree` (rechargement après un 419) ou par le
         drapeau posé par le gestionnaire d'exceptions (419 hors Livewire). --}}
    <div id="bandeau-session-expiree" role="alert" @unless (session('session_expiree')) hidden @endunless
         style="position:fixed;top:12px;left:50%;transform:translateX(-50%);z-index:50;max-width:calc(100vw - 32px);padding:10px 16px;border-radius:8px;background:var(--navy);color:white;font-size:14px">
        {{ __('pwa.connexion.session_expiree') }}
    </div>
    {{ $slot }}
    @livewireScripts
    @include('pwa.partials.session-expiree')
<script>
    // Surface non authentifiee : la page de repli hors connexion lit ce
    // drapeau pour choisir sa variante (« Se connecter » plutot que le
    // rappel de session). Pose ici et remis a 1 par la coquille : c'est un
    // indice d'affichage, jamais une donnee d'authentification.
    try { localStorage.setItem('pwa-session-active', '0'); } catch (e) { /* sans stockage : variante non connectee par defaut */ }
</script>
</body>
</html>
