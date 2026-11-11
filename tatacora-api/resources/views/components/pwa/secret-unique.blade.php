{{--
    UN SECRET AFFICHÉ UNE SEULE FOIS — mot de passe temporaire ou code de secours
    (décision du PO du 29/10/2026).

    Le secret est rendu en clair dans une boîte monospace, avec « Copier » et
    (si demandé) « Imprimer ». Il n'est écrit nulle part ailleurs : fermer la
    fenêtre le détruit côté serveur (propriété Livewire vidée), et rien ne le
    remet au journal d'audit ni aux logs.

    « Imprimer » ouvre une petite fenêtre qui ne contient QUE le titre, le
    secret et la consigne : imprimer la page entière imprimerait aussi le menu
    et le reste du compte. Le texte est posé par `textContent`, jamais par
    `innerHTML` : le secret ne peut pas injecter de balise.

    Props :
      secret      — le texte à montrer
      id          — préfixe des identifiants HTML (un par usage)
      consigne    — la phrase qui dit quoi en faire
      imprimable  — afficher « Imprimer » (défaut : non)
      titre       — titre de la page imprimée
--}}
@props([
    'secret',
    'id' => 'secret',
    'consigne' => '',
    'imprimable' => false,
    'titre' => '',
])
<div x-data="{
       copie: false,
       copier() {
         const texte = @js($secret);
         const fait = () => { this.copie = true; setTimeout(() => this.copie = false, 2500); };
         if (navigator.clipboard && navigator.clipboard.writeText) {
           navigator.clipboard.writeText(texte).then(fait, () => this.repli(texte, fait));
         } else {
           this.repli(texte, fait);
         }
       },
       repli(texte, fait) {
         const zone = document.createElement('textarea');
         zone.value = texte;
         zone.setAttribute('readonly', '');
         zone.style.position = 'fixed';
         zone.style.opacity = '0';
         document.body.appendChild(zone);
         zone.select();
         try { document.execCommand('copy'); fait(); } catch (e) { /* copie impossible : le secret reste lisible */ }
         document.body.removeChild(zone);
       },
       imprimer() {
         const fenetre = window.open('', '_blank', 'width=640,height=420');
         if (!fenetre) return;
         const doc = fenetre.document;
         doc.title = @js($titre);
         const style = doc.createElement('style');
         style.textContent = 'body{font-family:sans-serif;padding:32px}h1{font-size:20px}p{font-size:14px}.secret{font-family:monospace;font-size:26px;letter-spacing:2px;border:2px solid #000;padding:16px;margin:24px 0;word-break:break-all}';
         doc.head.appendChild(style);
         const h1 = doc.createElement('h1'); h1.textContent = @js($titre); doc.body.appendChild(h1);
         const code = doc.createElement('div'); code.className = 'secret'; code.textContent = @js($secret); doc.body.appendChild(code);
         const p = doc.createElement('p'); p.textContent = @js($consigne); doc.body.appendChild(p);
         fenetre.focus(); fenetre.print(); fenetre.close();
       }
     }" class="space-y-3">
  <div id="{{ $id }}-valeur" data-secret-unique
       class="rounded-lg border-2 border-dashed px-4 py-3 text-center font-mono text-lg font-bold tracking-wider select-all break-all"
       style="border-color:var(--gold);background:var(--fond-clair);color:var(--navy)">{{ $secret }}</div>
  @if ($consigne !== '')
    <p class="text-[13px] text-slate-600">{{ $consigne }}</p>
  @endif
  <div class="flex flex-wrap gap-2">
    <button id="{{ $id }}-copier" type="button" @click="copier()"
            class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50 font-semibold">
      <span x-show="!copie">{{ __('pwa.secret_unique.copier') }}</span>
      <span x-show="copie" x-cloak role="status">{{ __('pwa.secret_unique.copie') }}</span>
    </button>
    @if ($imprimable)
      <button id="{{ $id }}-imprimer" type="button" @click="imprimer()"
              class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50 font-semibold">{{ __('pwa.secret_unique.imprimer') }}</button>
    @endif
  </div>
</div>
