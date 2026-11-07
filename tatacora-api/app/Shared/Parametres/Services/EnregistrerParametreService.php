<?php

declare(strict_types=1);

namespace App\Shared\Parametres\Services;

use App\Domain\Comptabilite\Services\CalculTvaService;
use App\Domain\Comptabilite\Services\CorrespondanceComptesService;
use App\Domain\Facturation\Services\ModeFacturation;
use App\Domain\Facturation\Services\ReglagesMecef;
use App\Domain\Facturation\Services\TraceReglageFacturation;
use App\Shared\Parametres\Data\DefinitionParametre;
use App\Shared\Parametres\Data\RegistreParametres;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\ReportEngine\Services\ReportHeaderService;
use App\Shared\Secrets\Services\SecretsConfigurationService;
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
        $this->exigerAdministrateurPourFacturation($normalisees);
        $this->verifierFacturationNormalisee($normalisees);
        $this->verifierCoherence($normalisees);

        $modifiees = [];
        $avantFacturation = $this->etatFacturation();

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

        $this->tracerFacturation($modifiees, $avantFacturation);

        return $modifiees;
    }

    /**
     * Le mode et l'adresse/opérateur se règlent par un administrateur seulement
     * (décision du PO). Un appel sans utilisateur (seeder, commande) passe ; un
     * poste n'arrive jamais ici avec ces clés (`GestionnaireParametres` les écarte).
     *
     * @param  array<string, string>  $soumis
     */
    private function exigerAdministrateurPourFacturation(array $soumis): void
    {
        if (array_intersect(array_keys($soumis), ReglagesMecef::CLES_ADMINISTRATEUR) === []) {
            return;
        }

        $utilisateur = auth()->user();

        if ($utilisateur !== null && ! $utilisateur->estAdministrateur()) {
            throw new RuntimeException(__('parametres.mecef_reserve_administrateur'));
        }
    }

    /**
     * La cohérence du réglage RÉSULTANT : un mode réel n'est accepté que si ce
     * qu'il exige est là — sinon la première facture partirait en échec devant
     * le client. Aucune valeur secrète n'est citée.
     *
     * @param  array<string, string>  $soumis
     */
    private function verifierFacturationNormalisee(array $soumis): void
    {
        $concerne = array_intersect(array_keys($soumis), [
            ModeFacturation::CLE, ReportHeaderService::CLE_IFU, ReglagesMecef::CLE_API_URL,
            ReglagesMecef::CLE_OPERATEUR_ID, ReglagesMecef::CLE_OPERATEUR_NOM,
        ]);

        if ($concerne === []) {
            return;
        }

        // L'IFU saisi (par un écran, l'API ou un poste) compte 13 chiffres ; vide est permis.
        $ifuSaisi = trim($soumis[ReportHeaderService::CLE_IFU] ?? '');

        if ($ifuSaisi !== '' && ! ReglagesMecef::ifuValide($ifuSaisi)) {
            throw new RuntimeException(__('parametres.mecef_ifu_invalide'));
        }

        $resultat = fn (string $cle): string => trim($soumis[$cle] ?? (string) ($this->lecture->get($cle) ?? ''));
        $mode = ModeFacturation::depuis($resultat(ModeFacturation::CLE));

        if ($mode === ModeFacturation::Desactive) {
            return;
        }

        $manques = [];

        if (! ReglagesMecef::ifuValide($resultat(ReportHeaderService::CLE_IFU))) {
            $manques[] = __('parametres.mecef_manque_ifu');
        }
        if ($resultat(ReglagesMecef::CLE_OPERATEUR_ID) === '' || $resultat(ReglagesMecef::CLE_OPERATEUR_NOM) === '') {
            $manques[] = __('parametres.mecef_manque_operateur');
        }
        if ($mode === ModeFacturation::Emecef) {
            if (! app(SecretsConfigurationService::class)->etat(SecretsConfigurationService::MECEF_JETON)['renseigne']) {
                $manques[] = __('parametres.mecef_manque_jeton');
            }
        }

        if ($manques !== []) {
            throw new RuntimeException(__('parametres.mecef_mode_refuse', [
                'mode' => $mode->libelle(),
                'manques' => implode(' ', $manques),
            ]));
        }
    }

    /** @return array<string, string> */
    private function etatFacturation(): array
    {
        $etat = [];

        foreach ([ModeFacturation::CLE, ReglagesMecef::CLE_API_URL, ReglagesMecef::CLE_OPERATEUR_ID, ReglagesMecef::CLE_OPERATEUR_NOM] as $cle) {
            $etat[$cle] = (string) ($this->lecture->get($cle) ?? '');
        }

        return $etat;
    }

    /**
     * « Réglage de la facturation normalisée modifié » : les CLÉS modifiées et
     * le mode avant → après, jamais un secret (le jeton n'est pas un paramètre).
     *
     * @param  list<string>  $modifiees
     * @param  array<string, string>  $avant
     */
    private function tracerFacturation(array $modifiees, array $avant): void
    {
        $cles = array_values(array_intersect($modifiees, [
            ModeFacturation::CLE, ReglagesMecef::CLE_API_URL, ReglagesMecef::CLE_OPERATEUR_ID,
            ReglagesMecef::CLE_OPERATEUR_NOM, ReportHeaderService::CLE_IFU,
        ]));

        if ($cles === []) {
            return;
        }

        TraceReglageFacturation::tracer(auth()->id() === null ? null : (string) auth()->id(), [
            'cles' => $cles,
            'mode_avant' => ModeFacturation::depuis($avant[ModeFacturation::CLE] ?? '')->value,
            'mode_apres' => ModeFacturation::courant()->value,
        ]);
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
