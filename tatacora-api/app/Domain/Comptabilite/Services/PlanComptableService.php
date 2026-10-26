<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Services;

use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\ReadModels\PlanComptable;
use RuntimeException;

/**
 * Referentiel du plan comptable SYSCOHADA revise —
 * `m10-plan-comptable.html`, EF-M10-01.
 *
 * @see EF-M10-01 Plan comptable conforme SYSCOHADA revise, parametrable par
 *      centre de cout
 *
 * ## Non pagine, et c'est la regle de l'ecran
 *
 * Le maitre rend le plan entier dans un tableau sans aucun controle de
 * pagination (l.34-41) et affiche son effectif en sous-titre. C'est aussi la
 * conduite deja retenue pour `GET /stocks/points` : un referentiel qui remplit
 * un selecteur se sert entier, une page manquante ferait imputer une ecriture
 * au mauvais compte. Article 4.3 de `DIRECTIVE_CONFORMITE_100.md` : meme
 * pagination que le prototype — ici, aucune.
 *
 * ## `creerCompte()` — ajoutée le 01/09/2026 (Vague E), et la phrase
 * précédente est PÉRIMÉE sur ce point précis
 *
 * ~~« Aucune écriture. »~~ C'était vrai tant que rien n'appelait cette
 * méthode — exactement la garde que PA-63 impose : router une création que
 * rien n'appelle serait un bouton mort dans l'autre sens. Le maître
 * (`m10-syscohada.js` l.396, bouton « + Créer un compte » de l'onglet Plan
 * comptable du hub) pose maintenant son appelant :
 * `App\Pwa\Livewire\Comptabilite\Hub::enregistrerCompte()`. La phrase reste
 * juste pour l'écran `plan-comptable.blade.php` (`PlanComptable::class`),
 * qui n'a toujours aucune action d'écriture — voir son propre docblock.
 */
class PlanComptableService
{
    /** Classe SYSCOHADA des charges — celle qu'une dépense impute. */
    public const CLASSE_CHARGES = '6';

    /**
     * Registre FERMÉ des natures — mesuré le 01/09/2026 sur
     * `ComptabiliteReferentielSeeder::COMPTES`, les seules quatre valeurs que
     * ce dépôt écrit réellement dans `plan_comptable.nature`. Le maître
     * (`m10-syscohada.js` l.402) en porte dix-huit, beaucoup plus fins
     * (`immo_corporelle`, `dette_fiscale`…) — mais `plan_comptable.nature`
     * n'a jamais porté que ces quatre valeurs dans ce dépôt, et un compte créé
     * ici doit rester lisible par le même code que celui qui lit le
     * référentiel semé. Écart nommé, non masqué.
     *
     * @var list<string>
     */
    public const NATURES = ['actif', 'passif', 'charge', 'produit'];

    /**
     * LA règle du numéro d'un compte créé : DEUX À QUATRE chiffres, le premier
     * de 1 à 9. Source unique : le hub (saisie, `maxlength`, invite), ce service
     * et le poste (`MoteurComptable.creerCompte`) la relisent, un test les
     * confronte. Le plan du PO (SYSCOHADA révisé, 1 332 comptes) ne compte
     * aucun numéro de plus de quatre chiffres.
     */
    public const NUMERO_COMPTE_FORMAT = '/^[1-9][0-9]{1,3}$/';

    public const NUMERO_COMPTE_CHIFFRES_MAX = 4;

    /** Numéro valide en exemple (invite du champ) : un compte de charge à quatre chiffres. */
    public const NUMERO_COMPTE_EXEMPLE = '6056';

    /**
     * Les comptes d'une classe, pour remplir un selecteur.
     *
     * Ajoute au lot 0b (PA-159, T4) pour une raison precise : le composant des
     * depenses ecrivait le compte `'601'` EN DUR, a deux endroits. Deux
     * consequences — un numero qui n'existe dans aucun plan comptable du depot
     * (le plan du PO porte `6011`), et une liste de comptes qui
     * aurait diverge du plan des le premier compte ajoute. Une meme donnee, une
     * seule source (Article 10 de `DIRECTIVE_CONFORMITE_100.md`).
     *
     * `consulter()` reste le point d'entree de l'ECRAN du plan comptable : il
     * rend un modele de lecture avec ses decomptes par classe, dont un
     * selecteur n'a que faire. Celle-ci rend la liste, et rien d'autre.
     *
     * Non paginee, comme `consulter()` : un referentiel qui remplit un
     * selecteur se sert entier, une page manquante ferait imputer une ecriture
     * au mauvais compte.
     *
     * @return \Illuminate\Database\Eloquent\Collection<int, CompteComptable>
     */
    public function comptesDeClasse(string $classe): \Illuminate\Database\Eloquent\Collection
    {
        return CompteComptable::query()
            ->where('classe', $classe)
            ->orderBy('numero_compte')
            ->get();
    }

    /**
     * Les comptes de charge (classe 6) — ceux qu'une depense peut imputer.
     *
     * @return \Illuminate\Database\Eloquent\Collection<int, CompteComptable>
     */
    public function comptesDeCharge(): \Illuminate\Database\Eloquent\Collection
    {
        // Comptes imputables uniquement : une division (60, 601…) n'est pas proposée.
        return $this->comptesDeClasse(self::CLASSE_CHARGES)->filter(
            fn (CompteComptable $c): bool => strlen($c->numero_compte) >= 4,
        )->values();
    }

    /**
     * @param  string|null  $recherche  Filtre PWA (barre de recherche par table,
     *      décision du Product Owner du 01/09/2026) — sur le numéro DE COMPTE ou
     *      le libellé. Sans effet sur les décomptes (voir plus bas) : un plan
     *      comptable n'a ni total ni équilibre à préserver, contrairement aux
     *      états M10 générés par écritures (Journal, Balance, Grand Livre).
     */
    public function consulter(?string $classe = null, ?string $recherche = null): PlanComptable
    {
        $comptes = CompteComptable::query()
            ->when(
                $classe !== null,
                fn ($requete) => $requete->where('classe', $classe),
            )
            ->when(
                $recherche !== null && $recherche !== '',
                fn ($requete) => $requete->where(
                    fn ($sous) => $sous->where('numero_compte', 'like', '%'.$recherche.'%')
                        ->orWhere('libelle', 'like', '%'.$recherche.'%'),
                ),
            )
            ->orderBy('numero_compte')
            ->get();

        // Les decomptes portent sur TOUT le referentiel, jamais sur le filtre :
        // « 8 comptes » affiche sur un plan qui en compte 52 serait faux, et
        // les boutons de classe doivent annoncer ce qu'ils ouvriront.
        $parClasse = CompteComptable::query()
            ->selectRaw('classe, COUNT(*) AS total')
            ->groupBy('classe')
            ->pluck('total', 'classe');

        $ecran = [];

        foreach (CompteComptable::CLASSES_ECRAN as $classeEcran) {
            // Zero EXPLICITE : une classe absente de la reponse serait
            // indiscernable d'une classe vide, et le maitre affiche les sept
            // boutons quoi qu'il arrive (Article 7).
            $ecran[$classeEcran] = (int) $parClasse->get($classeEcran, 0);
        }

        $horsEcran = [];

        foreach ($parClasse as $classeTrouvee => $total) {
            $classeTrouvee = (string) $classeTrouvee;

            if (! in_array($classeTrouvee, CompteComptable::CLASSES_ECRAN, true)) {
                // Classes 8 (HAO) et 9 (analytique) : le schema les admet,
                // l'ecran n'a aucun bouton pour les atteindre. Les taire
                // rendrait des comptes reels invisibles sous un plan qui aurait
                // l'air complet.
                $horsEcran[$classeTrouvee] = (int) $total;
            }
        }

        ksort($horsEcran);

        return new PlanComptable(
            comptes: $comptes,
            total: (int) CompteComptable::query()->count(),
            comptesParClasse: $ecran,
            comptesParClasseHorsEcran: $horsEcran,
            // `plan_comptable.nature` est nullable. Le maitre indexe un badge
            // de couleur dessus (l.80) : une nature absente n'y produit rien du
            // tout. Comptee, elle devient un defaut de referentiel visible.
            sansNature: (int) CompteComptable::query()->whereNull('nature')->count(),
            filtresAppliques: ['classe' => $classe],
        );
    }

    /**
     * Crée un compte au plan — maître : `m10-syscohada.js` l.396-458, modale
     * « Créer un compte ».
     *
     * ## Le numéro fait DEUX À QUATRE CHIFFRES — écart au motif du maître, pas au fond
     *
     * `m10-syscohada.js` l.418 accepte `[1-9][0-9]{1,7}` (2 à 8 chiffres). Le
     * plan du PO (`database/data/plan-comptable-syscohada-revise.csv`) compte des
     * numéros de 1 à 4 chiffres ; un compte créé ici est un compte de MOUVEMENT
     * (2 à 4 chiffres : le chiffre unique est la classe). Une garde plus large
     * accepterait `"6"` ou `"60110099"` — un format qu'aucun compte du plan ne porte.
     *
     * ## La classe est DÉRIVÉE, jamais saisie
     *
     * `classe = substr($numero, 0, 1)`, comme `ComptabiliteReferentielSeeder`
     * — deux colonnes qui pourraient diverger (un numéro « 601100 » avec une
     * classe « 2 » saisie par erreur) sont ici structurellement impossibles.
     *
     * @throws RuntimeException numéro déjà pris, nature hors registre, libellé absent
     */
    public function creerCompte(string $numero, string $libelle, string $nature): CompteComptable
    {
        if (! preg_match(self::NUMERO_COMPTE_FORMAT, $numero)) {
            throw new RuntimeException(__('comptabilite.compte_numero_invalide', ['numero' => $numero]));
        }

        $libelle = trim($libelle);

        if ($libelle === '') {
            throw new RuntimeException(__('comptabilite.compte_libelle_requis'));
        }

        if (! in_array($nature, self::NATURES, true)) {
            throw new RuntimeException(__('comptabilite.compte_nature_invalide', ['nature' => $nature]));
        }

        if (CompteComptable::query()->where('numero_compte', $numero)->exists()) {
            throw new RuntimeException(__('comptabilite.compte_deja_existant', ['numero' => $numero]));
        }

        return CompteComptable::create([
            'numero_compte' => $numero,
            'libelle' => $libelle,
            'classe' => substr($numero, 0, 1),
            'nature' => $nature,
        ]);
    }
}
