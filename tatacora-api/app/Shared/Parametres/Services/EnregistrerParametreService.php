<?php

declare(strict_types=1);

namespace App\Shared\Parametres\Services;

use App\Domain\Comptabilite\Services\CalculTvaService;
use App\Domain\Comptabilite\Services\CorrespondanceComptesService;
use App\Shared\Parametres\Data\DefinitionParametre;
use App\Shared\Parametres\Data\RegistreParametres;
use App\Shared\Parametres\Models\ParametreSysteme;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * LE chemin d'écriture des paramètres — le seul.
 *
 * `ParametreSystemeService` reste en lecture ; il n'existait aucun endroit où
 * écrire, donc aucun endroit où poser les deux gardes que l'audit avait
 * laissées ouvertes (PA-61, PA-62). Elles sont ici.
 *
 * ## L'écriture se fait par LOT, et la cohérence porte sur l'état RÉSULTANT
 *
 * C'est le point de conception du service, et l'erreur naturelle est de
 * contrôler chaque clé séparément contre l'état stocké. Activer la TVA et
 * renseigner son taux dans le même envoi serait alors refusé : au moment où
 * `tva_active = true` est examiné, `taux_tva` est encore vide en base. Un
 * Administrateur devrait deviner qu'il faut deux enregistrements, dans un ordre
 * que rien ne lui indique — et l'écran paraîtrait cassé.
 *
 * On compose donc l'état qui existera **après** l'écriture (stocké, recouvert
 * par le soumis) et c'est lui qu'on vérifie. Le lot est accepté ou refusé
 * entier, dans une transaction : un lot à moitié écrit laisserait précisément
 * l'incohérence que ces gardes existent pour empêcher.
 *
 * ## Ce qui n'a pas changé ne s'écrit pas
 *
 * Eloquent déclenche `updating` même sur un modèle propre ; le trait `Auditable`
 * y pose `utilisateur_modification_id`, ce qui rend le modèle sale et fait
 * naître une entrée `journal_audit` pour une modification qui n'a pas eu lieu.
 * Le vrai changement se noierait dans le bruit — et c'est l'ancienne valeur
 * qu'on vient chercher dans ce journal. On compare donc avant d'écrire.
 *
 * @see RG-10 paramétrage sans déploiement
 * @see RG-15 traçabilité des actions sensibles
 */
class EnregistrerParametreService
{
    public function __construct(
        private readonly ParametreSystemeService $lecture,
        private readonly CorrespondanceComptesService $comptes,
    ) {
    }

    /**
     * @param  array<string, scalar|null>  $valeurs  clé => valeur soumise
     * @return list<string> les clés réellement modifiées
     *
     * @throws RuntimeException clé hors registre, ou état résultant incohérent
     */
    public function enregistrer(array $valeurs): array
    {
        $normalisees = [];

        foreach ($valeurs as $cle => $valeur) {
            $definition = RegistreParametres::definition((string) $cle);

            if ($definition === null) {
                // Créer la clé serait pire que refuser : l'écran confirmerait
                // un enregistrement qu'aucun code ne lit (PA-59/60/61).
                throw new RuntimeException(__('parametres.cle_inconnue', ['cle' => (string) $cle]));
            }

            $normalisees[$definition->cle] = $this->normaliser($definition, $valeur);
        }

        $this->verifierComptes($normalisees);
        $this->verifierCoherence($normalisees);

        $modifiees = [];

        DB::transaction(function () use ($normalisees, &$modifiees): void {
            foreach ($normalisees as $cle => $valeur) {
                $parametre = ParametreSysteme::where('cle', $cle)->first();

                if ($parametre === null) {
                    // Clé du registre encore absente de la base : les seeders
                    // ne posent que les référentiels TVA et paie. La créer est
                    // légitime — elle est déclarée, donc quelque chose la lit.
                    ParametreSysteme::create(['cle' => $cle, 'valeur' => $valeur]);
                    $modifiees[] = $cle;

                    continue;
                }

                if ($parametre->valeur === $valeur) {
                    continue;
                }

                $parametre->valeur = $valeur;
                $parametre->save();
                $modifiees[] = $cle;
            }
        });

        return $modifiees;
    }

    /**
     * Le type déclaré au registre commande la forme STOCKÉE.
     *
     * La colonne est un `text` : sans normalisation, `true` (booléen PHP)
     * deviendrait `"1"` et `false` deviendrait `""`. `CalculTvaService::estActive()`
     * lit par `FILTER_VALIDATE_BOOLEAN`, qui accepte `"1"` — mais le seeder
     * écrit `"false"`, et deux écritures de la même intention donneraient deux
     * contenus différents en base. On écrit une seule forme.
     *
     * @param  scalar|null  $valeur
     */
    private function normaliser(DefinitionParametre $definition, mixed $valeur): string
    {
        if ($valeur === null) {
            return '';
        }

        return match ($definition->type) {
            'booleen' => filter_var($valeur, FILTER_VALIDATE_BOOLEAN) ? 'true' : 'false',
            'choix' => strtolower(trim((string) $valeur)),
            default => trim((string) $valeur),
        };
    }

    /**
     * La correspondance rôle -> compte (26/10/2026) : chaque clé `compte_<rôle>`
     * non vide est jugée par {@see CorrespondanceComptesService::verifier()}.
     *
     * Ici, et pas dans l'écran : la synchronisation d'un poste écrit par ce
     * service (`GestionnaireParametres`), et une validation placée seulement
     * dans le composant laisserait un poste imposer un compte absent du plan.
     * Vide : le rôle revient à son défaut, rien à vérifier.
     *
     * @param  array<string, string>  $soumis
     */
    private function verifierComptes(array $soumis): void
    {
        foreach ($soumis as $cle => $valeur) {
            $role = CorrespondanceComptesService::roleDeCle($cle);

            if ($role !== null && $valeur !== '') {
                $this->comptes->verifier($role, $valeur);
            }
        }
    }

    /**
     * Les incohérences que l'écran doit rendre impossibles, sur l'état
     * résultant — jamais sur l'état stocké seul.
     *
     * @param  array<string, string>  $soumis
     */
    private function verifierCoherence(array $soumis): void
    {
        $resultat = fn (string $cle): string => $soumis[$cle]
            ?? (string) ($this->lecture->get($cle) ?? '');

        $tvaActive = filter_var(
            $resultat(CalculTvaService::CLE_PARAMETRE_ACTIVE) ?: 'false',
            FILTER_VALIDATE_BOOLEAN,
        );

        if (! $tvaActive) {
            return;
        }

        // PA-62 — `tva_active` (l'intention) et `taux_tva` (la capacité) sont
        // deux commutateurs indépendants. Leur combinaison incohérente lève une
        // `RuntimeException` à l'ÉMISSION de la facture, c'est-à-dire au
        // comptoir, en présence du client. La refuser ici est le seul moment où
        // elle coûte une correction de formulaire plutôt qu'une vente arrêtée.
        //
        // Les DEUX SENS sont fermés, et le second manquait à la note d'audit :
        // vider le taux pendant que la TVA reste active atteint exactement le
        // même état que l'activer sans taux. Une garde qui ne ferme qu'un des
        // deux chemins ne ferme rien.
        if (blank($resultat(CalculTvaService::CLE_PARAMETRE_TAUX))) {
            throw new RuntimeException(__('parametres.tva_sans_taux', [
                'cle_taux' => CalculTvaService::CLE_PARAMETRE_TAUX,
                'cle_active' => CalculTvaService::CLE_PARAMETRE_ACTIVE,
            ]));
        }

        $convention = $resultat(CalculTvaService::CLE_PARAMETRE_CONVENTION);

        // La convention a un repli côté lecture (`ht`), mais l'écran ne doit
        // pas pouvoir écrire une valeur qui ferait refuser `convention()` : le
        // refus tomberait, là encore, au moment d'émettre.
        if (filled($convention) && ! in_array($convention, [
            CalculTvaService::CONVENTION_HT,
            CalculTvaService::CONVENTION_TTC,
        ], true)) {
            throw new RuntimeException(__('parametres.convention_invalide', [
                'convention' => $convention,
            ]));
        }
    }
}
