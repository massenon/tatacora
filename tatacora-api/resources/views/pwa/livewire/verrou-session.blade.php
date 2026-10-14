{{--
    LE VOILE DE VERROUILLAGE — voir le docblock complet de
    `App\Pwa\Livewire\Transverse\VerrouSession`.

    Le minuteur d'inactivité est ENTIÈREMENT côté client (Alpine) : aucun
    aller-retour serveur tant que rien ne se passe. `localStorage`, et non
    `sessionStorage`, porte l'horodatage — le verrou doit tenir compte de
    l'inactivité même à travers un rechargement complet de page (F5), pas
    seulement à travers la navigation SPA de `wire:navigate`.

    ⚠ CE COMPOSANT NE FERME RIEN. Le voile est une couche visuelle
    par-dessus la page ; en dessous, rien n'est détruit — un panier de POS
    resterait intact si l'utilisateur pouvait le voir (il ne peut pas, le
    voile bloque tout clic et toute frappe grâce au `@click.stop`/`@keydown.stop`
    posés sur son propre conteneur, pas par un `pointer-events:none` sur le
    reste de la page qui laisserait passer le clavier).
--}}
<div
    x-data="{
        verrouille: false,
        cleActivite: 'tatacora_derniere_activite',
        seuilMs: {{ \App\Pwa\Livewire\Transverse\VerrouSession::INACTIVITE_SECONDES * 1000 }},

        init() {
            this.verrouille = this.inactifDepuisTropLongtemps();
            this.enregistrerActivite();

            ['mousemove', 'mousedown', 'keydown', 'scroll', 'touchstart', 'wheel'].forEach((evenement) => {
                window.addEventListener(evenement, () => {
                    if (!this.verrouille) this.enregistrerActivite();
                }, { passive: true });
            });

            setInterval(() => {
                if (!this.verrouille && this.inactifDepuisTropLongtemps()) {
                    this.verrouille = true;
                    this.$nextTick(() => this.$refs.champMotDePasse?.focus());
                }
            }, 5000);
        },

        inactifDepuisTropLongtemps() {
            const derniere = Number(localStorage.getItem(this.cleActivite) || 0);
            if (!derniere) return false;
            return (Date.now() - derniere) >= this.seuilMs;
        },

        enregistrerActivite() {
            localStorage.setItem(this.cleActivite, String(Date.now()));
        },
    }"
    {{--
        ⚠ `@@` est OBLIGATOIRE ici, et ce n'est pas un caprice de style.
        `@session-deverrouillee.window="..."` est un ecouteur Alpine.js
        (equivalent a `x-on:session-deverrouillee.window`, l'evenement
        personnalise emis par `VerrouSession::deverrouiller()` via
        `$this->dispatch('session-deverrouillee')`) — RIEN a voir avec la
        directive Blade `@session('cle') ... @endsession`. Ecrit sans
        l'echappement, Blade reconnaissait quand meme `@session` comme SA
        propre directive (le tiret qui suit n'empeche pas le parseur de
        directives de la capturer), la compilait en
        `if (session()->has($__sessionArgs[0])) :` SANS argument valide et
        SANS `@endsession` en face — un `if` jamais ferme qui cassait la
        compilation de TOUT le fichier (« unexpected end of file, expecting
        endif »), et donc le layout entier qui le monte. `@@` force Blade a
        rendre un `@` litteral et laisse Alpine lire l'attribut normalement.
    --}}
    @@session-deverrouillee.window="verrouille = false; enregistrerActivite()"
>
    <div
        x-show="verrouille"
        x-cloak
        x-transition.opacity
        class="fixed inset-0 z-[9999] flex items-center justify-center p-4"
        style="background:rgba(15,23,42,0.72);backdrop-filter:blur(2px)"
        role="dialog"
        aria-modal="true"
        aria-labelledby="verrou-session-titre"
        @keydown.window.escape.prevent.stop=""
    >
        <div class="bg-white rounded-2xl shadow-2xl w-full max-w-[380px] p-6" @click.stop>
            <div class="flex flex-col items-center text-center mb-5">
                <div class="w-14 h-14 rounded-full flex items-center justify-center mb-3" style="background:var(--fond-clair)">
                    <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0110 0v4"/></svg>
                </div>
                <h2 id="verrou-session-titre" class="text-base font-bold" style="color:var(--navy)">{{ __('pwa.verrou.titre') }}</h2>
                <p class="text-[13px] font-semibold text-slate-700 mt-1">{{ __('pwa.verrou.message') }}</p>
                <p class="text-[12px] text-slate-400 mt-1">{{ __('pwa.verrou.sous_message') }}</p>
            </div>

            <form wire:submit="deverrouiller">
                <label class="block text-[12px] font-semibold text-slate-600 mb-1.5">{{ __('pwa.verrou.mot_de_passe') }}</label>
                <div class="relative" x-data="{ motDePasseVisible: false }">
                    <input type="password" :type="motDePasseVisible ? 'text' : 'password'" wire:model="motDePasse" x-ref="champMotDePasse" autocomplete="current-password"
                           x-bind:required="verrouille"
                           class="w-full text-[14px] border border-slate-300 rounded-lg px-3 py-2.5 pr-11 focus:border-[var(--gold)] focus:outline-none">
                    <button type="button" @click="motDePasseVisible = !motDePasseVisible" :aria-label="motDePasseVisible ? '{{ __('pwa.connexion.masquer_mot_de_passe') }}' : '{{ __('pwa.connexion.afficher_mot_de_passe') }}'"
                            class="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600">
                        <svg x-show="!motDePasseVisible" width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>
                        <svg x-show="motDePasseVisible" x-cloak width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17.94 17.94A10.94 10.94 0 0112 20c-7 0-11-8-11-8a21.62 21.62 0 015.06-6.94M9.9 4.24A10.94 10.94 0 0112 4c7 0 11 8 11 8a21.6 21.6 0 01-2.66 3.94M14.12 14.12a3 3 0 11-4.24-4.24"/><path d="M1 1l22 22"/></svg>
                    </button>
                </div>
                @error('motDePasse')
                    <p class="text-[12px] text-red-600 mt-1.5">{{ $message }}</p>
                @enderror

                <button type="submit" wire:loading.attr="disabled" wire:target="deverrouiller"
                        class="w-full mt-4 text-[14px] font-semibold px-4 py-2.5 rounded-lg text-white"
                        style="background:var(--navy)">
                    {{ __('pwa.verrou.deverrouiller') }}
                </button>
            </form>
        </div>
    </div>
</div>
