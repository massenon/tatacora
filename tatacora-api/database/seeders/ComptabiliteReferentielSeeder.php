<?php

declare(strict_types=1);

namespace Database\Seeders;

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Models\JournalComptable;
use Illuminate\Database\Seeder;
use Illuminate\Support\Str;

/**
 * Référentiel comptable SYSCOHADA révisé — centres de coût, plan comptable
 * (importé du fichier du PO, `database/data/plan-comptable-syscohada-revise.csv`,
 * UNIQUE auteur depuis le 10/10/2026), journaux, exercice courant.
 *
 * ## Pourquoi ce seeder manquait, et ce que son absence cachait
 *
 * Quatre tables du module M10 — `centres_cout`, `plan_comptable`,
 * `journaux_comptables`, `exercices_comptables` — n'étaient peuplées par aucun
 * seeder (vérifié le 31/08/2026 : `grep` à zéro sur `database/seeders/`).
 * Toute la comptabilité tournait donc à vide en développement, et les tests
 * qui la couvrent construisent leurs propres fixtures — ce qui explique
 * qu'aucun ne l'ait signalé.
 *
 * C'est la seconde moitié du défaut T4 : `PasserEcritureService` n'existait
 * pas, et même s'il avait existé, il n'aurait rien eu à résoudre.
 *
 * ## Plan comptable : un seul auteur (10/10/2026)
 *
 * Les 53 comptes à six chiffres de l'ancien semis (transcription de
 * `ATELIER_PLAN_COMPTABLE.md`) sont REMPLACÉS par le fichier du PO (1332
 * comptes, 1 à 4 chiffres). Le texte qui suit décrit l'ancien semis, conservé
 * pour la traçabilité des règles qu'il avait posées (pas de taux, pas de nature
 * devinée).
 *
 * ## Ancien contenu — n'était PAS deviné
 *
 * Il est la transcription de `docs/ATELIER_PLAN_COMPTABLE.md` (v1.3, PA-14),
 * qui applique le référentiel SYSCOHADA révisé — norme publique, identique
 * dans tout l'espace OHADA — au profil d'activité de TATACORA. Le §6 de ce
 * document annonce nommément « `ComptabiliteReferentielSeeder` » comme sa
 * suite technique directe.
 *
 * **Aucune donnée réglementaire n'est fixée ici.** Les taux CNSS, ITS et le
 * taux d'IS ne figurent pas dans ce seeder et ne doivent jamais y entrer : la
 * leçon de PA-53 est qu'un taux plausible inscrit dans un seeder devient la
 * règle de production, et que personne ne le rouvre. Un numéro de compte n'est
 * pas un taux — c'est une nomenclature publique.
 *
 * ## Un écart réel avec le code antérieur, à connaître
 *
 * (Historique, avant le 10/10/2026.) L'ancien plan documenté portait des comptes
 * à six chiffres (601100, 571000…) ; le plan du PO n'en compte aucun de plus de
 * quatre. `PasserEcritureService` refuse tout numéro absent du plan plutôt que
 * d'imputer au plus proche.
 *
 * @see EF-M10-01 Plan comptable conforme SYSCOHADA révisé
 * @see RG-12 Centre de coût obligatoire — `centre_cout_defaut_id` le pré-remplit
 */
class ComptabiliteReferentielSeeder extends Seeder
{
    /**
     * Les sept centres de coût actés au CdCF.
     *
     * @var array<string, string> libellé => type
     */
    private const CENTRES = [
        'Hébergement' => 'exploitation',
        'Restaurant' => 'exploitation',
        'Bar' => 'exploitation',
        'Tourisme' => 'exploitation',
        'Véhicules' => 'exploitation',
        'RH' => 'support',
        'Structure' => 'support',
    ];

    /**
     * Les cinq journaux de `MODULE_COMPTABILITE_COMPLET.md` §2 — ceux que le
     * poste réplique (`ComptesSyscohada.journaux`).
     *
     * @var array<string, string>
     */
    private const JOURNAUX = [
        'VTE' => 'Journal des ventes',
        'ACH' => 'Journal des achats',
        'BQ' => 'Journal de banque',
        'CAI' => 'Journal de caisse',
        'OD' => 'Journal des opérations diverses',
    ];

    /**
     * Les journaux de la clôture SYSCOHADA (20/10/2026) : le poste n'y saisit
     * jamais — la clôture se fait au serveur — d'où une liste à part.
     *
     * @var array<string, string>
     */
    private const JOURNAUX_DE_CLOTURE = [
        'CL' => 'Journal de clôture',
        'AN' => 'Journal des à-nouveaux',
    ];

    /**
     * Fichier du Product Owner — UNIQUE source du plan comptable (décision du
     * 10/10/2026). `Code;Libellé`, UTF-8, 1332 comptes, 1 à 4 chiffres.
     * Le serveur est la référence ; le client Flutter desktop le réplique.
     */
    public const FICHIER_PLAN = 'data/plan-comptable-syscohada-revise.csv';

    /**
     * Centre de coût PAR DÉFAUT des seuls comptes que le code du serveur
     * mouvemente en dur — le fichier du PO ne porte aucun centre, et
     * `PasserEcritureService::centre()` refuse une ligne sans centre. Ce n'est
     * pas une donnée du plan : c'est la suggestion de saisie TATACORA reprise
     * de l'ancien semis (colonne documentée « suggestion uniquement »).
     * Tout autre compte naît SANS centre : l'écriture doit alors porter le
     * sien (RG-12), rien n'est deviné.
     *
     * Clés : numéro de compte (entier en PHP) ; valeurs : libellé du centre.
     */
    private const CENTRE_PAR_DEFAUT = [
        '131' => 'Structure',
        '139' => 'Structure',
        '4011' => 'Structure',
        '4111' => 'Structure',
        '4191' => 'Hébergement',
        '4431' => 'Structure',
        '4432' => 'Structure',
        '4452' => 'Structure',
        '5211' => 'Structure',
        '552' => 'Structure',
        '5711' => 'Hébergement',
    ];


    public function run(): void
    {
        $centres = $this->semerCentres();
        $this->semerJournaux();
        $this->semerComptes($centres);
        $this->semerExerciceCourant();
    }

    /**
     * @return array<string, string> libellé => identifiant
     */
    private function semerCentres(): array
    {
        $identifiants = [];

        foreach (self::CENTRES as $libelle => $type) {
            $centre = CentreCout::firstOrCreate(['libelle' => $libelle], ['type' => $type]);
            $identifiants[$libelle] = $centre->id;
        }

        return $identifiants;
    }

    private function semerJournaux(): void
    {
        foreach ([...self::JOURNAUX, ...self::JOURNAUX_DE_CLOTURE] as $code => $libelle) {
            JournalComptable::firstOrCreate(['code' => $code], ['libelle' => $libelle]);
        }
    }

    /**
     * Importe le fichier du PO. Idempotent : crée les comptes absents, aligne
     * le libellé et la classe des présents sur le fichier, ne supprime JAMAIS
     * un compte (un compte hérité peut porter des écritures, RESTRICT).
     *
     * `nature` n'est dérivée que là où une règle écrite la donne : classe 6 =
     * charge, classe 7 = produit (définition SYSCOHADA). Ailleurs elle reste
     * NULL (la colonne est nullable) : les classes 1, 4 et 5 mêlent actif et
     * passif, et deviner ferait une nature fausse sur un état financier.
     * Une nature déjà posée n'est jamais écrasée.
     *
     * @param  array<string, string>  $centres
     */
    private function semerComptes(array $centres): void
    {
        $existants = CompteComptable::query()
            ->get(['id', 'numero_compte', 'libelle', 'classe', 'nature', 'centre_cout_defaut_id'])
            ->keyBy('numero_compte');
        $maintenant = now();
        $aInserer = [];

        foreach (self::lireFichier() as [$numero, $libelle]) {
            // La classe est le PREMIER chiffre du numéro.
            $classe = substr($numero, 0, 1);
            $centre = isset(self::CENTRE_PAR_DEFAUT[$numero]) ? $centres[self::CENTRE_PAR_DEFAUT[$numero]] : null;
            $nature = match ($classe) {
                '6' => 'charge',
                '7' => 'produit',
                default => null,
            };

            $compte = $existants->get($numero);
            if ($compte === null) {
                $aInserer[] = [
                    'id' => (string) Str::uuid(),
                    'numero_compte' => $numero,
                    'libelle' => $libelle,
                    'classe' => $classe,
                    'nature' => $nature,
                    'centre_cout_defaut_id' => $centre,
                    'created_at' => $maintenant,
                    'updated_at' => $maintenant,
                ];

                continue;
            }

            $compte->libelle = $libelle;
            $compte->classe = $classe;
            $compte->nature ??= $nature;
            $compte->centre_cout_defaut_id ??= $centre;
            if ($compte->isDirty()) {
                $compte->save();
            }
        }

        foreach (array_chunk($aInserer, 300) as $lot) {
            CompteComptable::query()->insert($lot);
        }
    }

    /**
     * Lit le fichier du PO — seul point de lecture, réutilisé par les tests.
     *
     * @return list<array{0: string, 1: string}> numéro, libellé
     */
    public static function lireFichier(): array
    {
        $chemin = database_path(self::FICHIER_PLAN);
        $poignee = fopen($chemin, 'rb');
        if ($poignee === false) {
            throw new \RuntimeException(__('comptabilite.plan_fichier_illisible'));
        }

        $comptes = [];
        $ligneNo = 0;
        while (($ligne = fgetcsv($poignee, 0, ';', '"', '')) !== false) {
            $ligneNo++;
            if ($ligneNo === 1) {
                continue; // en-tête « Code;Libellé »
            }
            $numero = trim((string) ($ligne[0] ?? ''));
            $libelle = trim((string) ($ligne[1] ?? ''));
            if (preg_match('/^[1-9][0-9]*$/', $numero) !== 1 || $libelle === '' || count($ligne) !== 2) {
                fclose($poignee);
                throw new \RuntimeException(__('comptabilite.plan_fichier_ligne_invalide', ['ligne' => $ligneNo]));
            }
            $comptes[] = [$numero, $libelle];
        }
        fclose($poignee);

        return $comptes;
    }

    /**
     * L'exercice de l'année en cours, ouvert.
     *
     * Sans lui, aucune écriture ne peut être passée : `ecritures_comptables`
     * porte `exercice_id` NOT NULL. Ce n'est pas une donnée métier inventée,
     * c'est le cadre annuel que toute comptabilité pose — et son absence était
     * l'une des raisons pour lesquelles la moindre dépense aurait été refusée.
     *
     * Les exercices suivants sont ouverts par le geste de clôture
     * (EF-M10-07), jamais par un seeder qui les créerait d'avance.
     */
    private function semerExerciceCourant(): void
    {
        $annee = (int) now()->format('Y');

        ExerciceComptable::firstOrCreate(
            ['annee' => $annee],
            [
                'date_debut' => $annee.'-01-01',
                'date_fin' => $annee.'-12-31',
                'statut' => 'ouvert',
            ],
        );
    }
}
