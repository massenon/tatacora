<!DOCTYPE html>
<html lang="fr">
<head>
{{-- PA-185 (11/09/2026) : l'onglet reprend le <h1> (« Connexion Internet
     requise »), comme sur tout écran de la PWA — c'est le <h1> qui dit ce qui
     manque, « Hors connexion » n'en était qu'un second nom. --}}
@include('pwa.partials.tete', ['titre' => __('pwa.hors_connexion.titre_page')])
<style>
  .fond-splash { background: linear-gradient(180deg, rgba(20,33,61,.55) 0%, rgba(20,33,61,.88) 75%, #14213D 100%), url('{{ asset('assets/img/gite-cover.jpg') }}'); background-size: cover; background-position: center; }
</style>
</head>

<body class="h-screen w-screen fond-splash flex flex-col items-center justify-center text-white overflow-hidden px-6">

  <div class="mb-6">
    {{-- Logo PNG paysage (decision du PO du 14/10/2026, D392) : cadre garde,
         `object-contain` au lieu d'`object-cover` (qui rognait). PA-210. --}}
    <img src="{{ asset('assets/img/logo.png') }}" alt="{{ __('pwa.alt_logo') }}" class="w-20 h-20 rounded-2xl ring-4 ring-[var(--gold)]/60 object-contain shadow-2xl">
  </div>

  {{-- Deux variantes (directive PO du 02/09/2026), choisies par le drapeau
       local `pwa-session-active` pose par les deux layouts : une session
       ouverte sur ce poste change le titre et retire « Se connecter » — se
       reconnecter par-dessus une session vivante la remplacerait. AUCUN
       formulaire de mot de passe ici : hors reseau, rien ne peut le
       verifier ; le VRAI formulaire de deverrouillage (VerrouSession)
       s'affiche de lui-meme au rechargement si la session s'est verrouillee.
       Le JavaScript est inline : cette page est servie depuis le cache du
       service worker, elle ne peut dependre d'aucune ressource reseau. --}}
  <h1 id="titre-hors-connexion" class="text-2xl md:text-3xl font-bold tracking-tight text-center">{{ __('pwa.hors_connexion.titre') }}</h1>
  <p id="explication-hors-connexion" class="text-white/70 text-[15px] mt-3 max-w-md text-center leading-relaxed">{{ __('pwa.hors_connexion.explication') }}</p>
  <p class="text-white/70 text-[15px] mt-3 max-w-md text-center leading-relaxed">{!! __('pwa.hors_connexion.orientation') !!}</p>

  <div class="flex items-center gap-3 mt-8">
    <button type="button" onclick="window.location.reload()" class="px-5 py-2.5 rounded-lg bg-[var(--gold)] text-white text-sm font-bold hover:brightness-110 shadow-lg transition-all">
      {{ __('pwa.hors_connexion.reessayer') }}
    </button>
    <a id="lien-se-connecter" href="{{ route('pwa.connexion') }}" class="px-5 py-2.5 rounded-lg border border-white/30 text-white/90 text-sm font-semibold hover:bg-white/10 transition-colors">
      {{ __('pwa.hors_connexion.se_connecter') }}
    </a>
  </div>

  <template id="variante-session">
    <span data-titre>{{ __('pwa.hors_connexion.session_titre') }}</span>
    <span data-explication>{{ __('pwa.hors_connexion.session_explication') }}</span>
  </template>
  <script>
    (function () {
        let sessionActive = false;
        try { sessionActive = localStorage.getItem('pwa-session-active') === '1'; } catch (e) { /* sans stockage : variante non connectee */ }
        if (!sessionActive) return;

        const gabarit = document.getElementById('variante-session');
        document.getElementById('titre-hors-connexion').textContent = gabarit.content.querySelector('[data-titre]').textContent;
        document.getElementById('explication-hors-connexion').textContent = gabarit.content.querySelector('[data-explication]').textContent;
        document.getElementById('lien-se-connecter').remove();
    })();
  </script>

  <p class="absolute bottom-8 text-white/25 text-[12px]">{{ __('pwa.mention_pied_menu') }}</p>
</body>
</html>
