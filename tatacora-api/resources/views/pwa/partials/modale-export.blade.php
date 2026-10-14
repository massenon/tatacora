{{--
    MODALE D'EXPORT UNIFIEE — une seule, pour les onze ecrans qui l'ouvraient.

    ## Ce qu'elle remplace

    Le meme bloc etait recopie a l'identique dans onze vues, sous dix titres
    differents (« Exporter le Rapport Hebergement », « Exporter les Donnees de
    Stock »...). Onze copies d'un formulaire, c'est onze endroits ou corriger
    un libelle, et dix qu'on oubliera.

    ## Usage

        @include('pwa.partials.modale-export', ['titre' => $titreExport])

    ou `titre` resolu par la cle de langue de l'ecran appelant.

    Parametres :
      titre     — titre de l'en-tete (obligatoire) : il NOMME ce qui sera
                  exporte. Le maitre le fait aussi (`crud-ui.js` l.147,
                  « Exporter — <entite au pluriel> ») : un titre generique
                  laisserait douter du perimetre du fichier telecharge.
      sousTitre — optionnel, defaut « Choisissez le format d'exportation
                  certifie ».

    Le composant appelant doit exposer :
      - la propriete `$formatExport` (liee par `wire:model`),
      - l'action `genererExport()`,
      - l'action de fermeture `fermerModales()`.

    ## ⚠ Derogation au maitre — declaree, datee, et non contournee

    `prototype_v2/assets/js/crud-ui.js` l.142-160 n'offre AUCUN choix de
    format : un seul bouton, « Telecharger tous les resultats filtres (.csv) ».
    Le choix radio PDF A4 / Excel vient de `docs/DIRECTIVE_CONFORMITE_100.md`,
    et le Product Owner l'a maintenu le 31/08/2026. C'est un elargissement, pas
    une derive — le CSV du maitre reste servi par la branche « Tableur ».

    Declaration pour la garde des trois sources (`t-trois-sources.js`) :
    maitre-refuse:chassis#modale-export — le bouton unique CSV du maitre n'est
    pas rendu, remplace par le choix de format ci-dessus (31/08/2026, decision
    du Product Owner).

    ## Ce que la modale ne promet pas

    Elle ne dit RIEN de ce que contiendra le fichier : c'est l'ecran appelant
    qui porte le filtre, et PA-119 impose qu'un export porte sur ce qui est
    AFFICHE et qu'il DISE son filtre. Une mention generique ici la rendrait
    fausse sur dix ecrans sur onze.
--}}
@php($sousTitre = $sousTitre ?? __('pwa.export.sous_titre'))
<x-pwa.modale :titre="$titre" :sousTitre="$sousTitre" largeur="448px">
    <div>
        <label class="block text-[13px] font-semibold text-slate-700 mb-2">{{ __('pwa.export.format') }}</label>
        <div class="space-y-2">
            <label class="flex items-center gap-3 p-3 rounded-lg border border-slate-200 hover:bg-slate-50 cursor-pointer">
                <input type="radio" wire:model="formatExport" value="pdf" class="text-[var(--navy)]">
                <div>
                    <p class="text-[13px] font-bold text-slate-800">{{ __('pwa.export.pdf_titre') }}</p>
                    <p class="text-[11px] text-slate-500">{{ __('pwa.export.pdf_detail') }}</p>
                </div>
            </label>

            <label class="flex items-center gap-3 p-3 rounded-lg border border-slate-200 hover:bg-slate-50 cursor-pointer">
                <input type="radio" wire:model="formatExport" value="excel" class="text-[var(--navy)]">
                <div>
                    <p class="text-[13px] font-bold text-slate-800">{{ __('pwa.export.excel_titre') }}</p>
                    <p class="text-[11px] text-slate-500">{{ __('pwa.export.excel_detail') }}</p>
                </div>
            </label>
        </div>
    </div>

    <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="genererExport"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">{{ __('pwa.export.generer') }}</button>
    </x-slot:pied>
</x-pwa.modale>
