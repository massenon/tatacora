<!DOCTYPE html>
<html lang="fr">
<head>
{{-- Le titre nomme l'ÉCRAN puis la marque, comme les quarante-neuf autres
     pages du maître. L'écart avec `splash.html`, seule page à inverser les
     deux, est motivé dans `lang/fr/coquille_pwa.php`. --}}
@include('pwa.partials.tete', ['titre' => __('coquille_pwa.demarrage_titre_page')])
<style>
  .fond-splash { background: linear-gradient(180deg, rgba(20,33,61,.55) 0%, rgba(20,33,61,.88) 75%, #14213D 100%), url('{{ asset('assets/img/gite-cover.jpg') }}'); background-size: cover; background-position: center; }
  @keyframes apparition { from { opacity: 0; transform: translateY(12px); } to { opacity: 1; transform: translateY(0); } }
  .anim-1 { animation: apparition .6s ease forwards; }
  .anim-2 { animation: apparition .6s ease .2s forwards; opacity: 0; }
  .anim-3 { animation: apparition .6s ease .4s forwards; opacity: 0; }
  .anim-4 { animation: apparition .6s ease .6s forwards; opacity: 0; }
  @keyframes rotation { to { transform: rotate(360deg); } }
</style>
</head>

<body class="h-screen w-screen fond-splash flex flex-col items-center justify-center text-white overflow-hidden">

  <div class="anim-1 mb-6">
    {{-- Logo PNG paysage (decision du PO du 14/10/2026, D392) : cadre garde,
         `object-contain` au lieu d'`object-cover` (qui rognait). PA-210. --}}
    <img src="{{ asset('assets/img/logo.png') }}" alt="{{ __('pwa.alt_logo') }}" class="w-24 h-24 rounded-2xl ring-4 ring-[var(--gold)]/60 object-contain shadow-2xl">
  </div>

  <h1 class="anim-2 text-3xl md:text-4xl font-bold tracking-tight text-center">{{ __('pwa.marque') }}</h1>
  <p class="anim-2 text-[var(--gold)] text-sm font-semibold mt-1 tracking-wide">{{ __('pwa.demarrage.enseigne') }}</p>
  {{-- DÉCISION DU PRODUCT OWNER DU 13/10/2026 (PA-208, ticket D385) : la
       ligne disait « Natitingou, Bénin — » suivi du nom d'un autre produit ;
       elle rend la clé de localisation des états, la même que la barre
       supérieure (D373) — un seul auteur pour l'écran et le papier. --}}
  <p class="anim-2 text-white/50 text-[15px] mt-1">{{ __('rapports.entete.localisation') }}</p>

  <div class="anim-3 w-full max-w-xs mt-10">
    <div class="h-1.5 w-full bg-white/10 rounded-full overflow-hidden">
      <div id="barre-progression" class="h-full bg-[var(--gold)] rounded-full transition-all duration-100 ease-linear" style="width:0%"></div>
    </div>
    <p id="texte-progression" class="text-center text-white/50 text-[13px] mt-3 tracking-wide">{{ __('pwa.demarrage.etapes.0') }}</p>
  </div>

  <div class="anim-4 absolute bottom-8 flex flex-col items-center gap-2">
    <p class="text-white/30 text-[12px] uppercase tracking-widest">{{ __('pwa.demarrage.cadre') }}</p>
    <div class="flex items-center gap-4">
      <span class="text-white/70 text-[15px] font-bold border border-white/20 rounded-md px-3 py-1.5">PAEB</span>
      <span class="text-white/30 text-[15px]">×</span>
      <span class="text-white/70 text-[15px] font-bold border border-white/20 rounded-md px-3 py-1.5">FAGUEZ SARL</span>
    </div>
    <p class="text-white/25 text-[12px] mt-1">{{ __('pwa.demarrage.programme') }}</p>
  </div>

<script>
  // Étapes affichées : source unique côté serveur (lang/fr/pwa.php), jamais
  // recopiées ici — un libellé dupliqué diverge sans que rien ne le signale.
  const etapes = @json(__('pwa.demarrage.etapes'), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
  const destination = @json(route('pwa.accueil'), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);

  const barre = document.getElementById('barre-progression');
  const texte = document.getElementById('texte-progression');
  let progression = 0;

  const minuteur = setInterval(() => {
    progression += 4;
    barre.style.width = Math.min(progression, 100) + '%';
    const etapeIndex = Math.min(Math.floor(progression / 22), etapes.length - 1);
    texte.textContent = etapes[etapeIndex];
    if (progression >= 100) {
      clearInterval(minuteur);
      // SECURITY_STRICT.md §12bis : aucune session n'est fabriquée ici. On
      // redirige vers l'accueil, dont le middleware `auth` renvoie un invité
      // vers le formulaire de connexion réel.
      setTimeout(() => { window.location.href = destination; }, 300);
    }
  }, 60);
</script>
</body>
</html>
