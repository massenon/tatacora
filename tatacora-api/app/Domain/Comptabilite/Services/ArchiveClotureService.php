<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Services;

use App\Domain\Comptabilite\Models\ClotureExercice;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Models\User;
use App\Shared\ReportEngine\Data\EnTeteRapport;
use App\Shared\ReportEngine\Services\ReportHeaderService;
use Barryvdh\DomPDF\Facade\Pdf;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use RuntimeException;
use ZipArchive;

/**
 * L'ARCHIVE LÉGALE d'un exercice clôturé (lot 4, 20/10/2026) — décision du
 * PO : « export du fichier des écritures et PDF des états de clôture avec
 * empreinte d'intégrité », au format SYSCOHADA révisé / DGI Bénin.
 *
 * Une archive par clôture (`ClotureExercice`), dans
 * `storage/app/private/archives/exercices/<annee>/<id de la clôture>/` :
 *
 *  - `ecritures.csv` : le fichier des écritures de l'exercice, une ligne par
 *    ligne d'écriture, colonnes du fichier des écritures comptables (FEC)
 *    adaptées au SYSCOHADA (centre de coût, statut, contre-passation) ;
 *    UTF-8 avec BOM, séparateur `;`, dates AAAAMMJJ, montants à virgule ;
 *  - `balance.csv` : la balance générale de clôture (avant solde des comptes
 *    de gestion) ;
 *  - `etats-cloture.pdf` : balance, compte de résultat, bilan, et les pièces
 *    de clôture et d'à-nouveaux ;
 *  - `manifeste.json` : l'empreinte SHA-256 et la taille de chaque fichier.
 *
 * L'EMPREINTE de l'archive est le SHA-256 du manifeste : elle est écrite sur
 * la clôture (`archive_empreinte`) et imprimée à l'écran — qui la note peut
 * prouver plus tard qu'aucun fichier n'a bougé (`verifier()`).
 *
 * L'archive est IMMUABLE : on ne la régénère jamais (`archiver()` rend celle
 * qui existe). Une réouverture suivie d'une nouvelle clôture crée une
 * nouvelle `ClotureExercice`, donc une nouvelle archive ; l'ancienne reste.
 *
 * ⚠ Le format exact attendu par la DGI du Bénin (colonnes, encodage) reste à
 * confirmer avec l'expert-comptable : les colonnes sont nommées ici, une à
 * une, pour qu'un ajustement ne touche que `COLONNES_ECRITURES`.
 */
class ArchiveClotureService
{
    public const DISQUE = 'local';

    public const FICHIER_ECRITURES = 'ecritures.csv';

    public const FICHIER_BALANCE = 'balance.csv';

    public const FICHIER_ETATS = 'etats-cloture.pdf';

    public const FICHIER_MANIFESTE = 'manifeste.json';

    /** @var list<string> */
    public const COLONNES_ECRITURES = [
        'JournalCode',
        'JournalLib',
        'EcritureNum',
        'EcritureDate',
        'CompteNum',
        'CompteLib',
        'CentreCout',
        'EcritureLib',
        'Debit',
        'Credit',
        'Statut',
        'EcritureContrepassee',
        'DateSaisie',
        'SaisiPar',
    ];

    /** @var list<string> */
    public const COLONNES_BALANCE = [
        'CompteNum',
        'CompteLib',
        'Classe',
        'TotalDebit',
        'TotalCredit',
        'SoldeDebiteur',
        'SoldeCrediteur',
    ];

    public function __construct(
        private readonly BalanceGeneraleService $balance,
        private readonly CompteResultatService $compteResultat,
        private readonly BilanService $bilan,
        private readonly ReportHeaderService $entete,
    ) {
    }

    /**
     * Écrit l'archive de la clôture, ou rend celle qui existe déjà.
     */
    public function archiver(ClotureExercice $cloture, ?User $auteur = null): ClotureExercice
    {
        if ($cloture->archive_empreinte !== null) {
            return $cloture;
        }

        if (! $cloture->estActive()) {
            throw new RuntimeException(__('comptabilite.archive_cloture_rouverte'));
        }

        /** @var ExerciceComptable $exercice */
        $exercice = $cloture->exercice()->firstOrFail();
        $dossier = 'archives/exercices/'.$exercice->annee.'/'.$cloture->id;
        $disque = Storage::disk(self::DISQUE);

        $entete = $this->entete->genererEnTete(
            __('comptabilite_pwa.archive_titre', ['annee' => $exercice->annee]),
            __('rapports.periode.exercice', ['annee' => $exercice->annee]),
            $auteur,
        );

        $contenus = [
            self::FICHIER_ECRITURES => $this->fichierEcritures($exercice),
            self::FICHIER_BALANCE => $this->fichierBalance($exercice),
            self::FICHIER_ETATS => $this->etatsDeCloture($exercice, $cloture, $entete),
        ];

        $fichiers = [];
        foreach ($contenus as $nom => $contenu) {
            $disque->put($dossier.'/'.$nom, $contenu);
            $fichiers[$nom] = ['sha256' => hash('sha256', $contenu), 'octets' => strlen($contenu)];
        }

        $manifeste = json_encode([
            'etablissement' => $entete->raisonSociale,
            'exercice' => $exercice->annee,
            'periode' => [$exercice->date_debut->format('Y-m-d'), $exercice->date_fin->format('Y-m-d')],
            'referentiel' => 'SYSCOHADA révisé',
            'cloture' => [
                'id' => $cloture->id,
                'le' => $cloture->cloturee_le->format(DATE_ATOM),
                'piece_cloture' => $cloture->piece_cloture,
                'piece_a_nouveaux' => $cloture->piece_a_nouveaux,
                'resultat' => (string) $cloture->resultat,
            ],
            'genere_le' => now()->format(DATE_ATOM),
            'algorithme' => 'sha256',
            'fichiers' => $fichiers,
        ], JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);

        $disque->put($dossier.'/'.self::FICHIER_MANIFESTE, $manifeste);

        $cloture->forceFill([
            'archive_chemin' => $dossier,
            'archive_empreinte' => hash('sha256', $manifeste),
        ])->save();

        return $cloture;
    }

    /**
     * L'archive est-elle intacte ? Le manifeste rend l'empreinte enregistrée,
     * et chaque fichier celle que le manifeste a notée.
     */
    public function verifier(ClotureExercice $cloture): bool
    {
        $disque = Storage::disk(self::DISQUE);
        $chemin = (string) $cloture->archive_chemin;

        if ($cloture->archive_empreinte === null || ! $disque->exists($chemin.'/'.self::FICHIER_MANIFESTE)) {
            return false;
        }

        $manifeste = (string) $disque->get($chemin.'/'.self::FICHIER_MANIFESTE);
        if (! hash_equals($cloture->archive_empreinte, hash('sha256', $manifeste))) {
            return false;
        }

        /** @var array{fichiers: array<string, array{sha256: string}>} $lu */
        $lu = json_decode($manifeste, true, flags: JSON_THROW_ON_ERROR);
        foreach ($lu['fichiers'] as $nom => $fichier) {
            if (! $disque->exists($chemin.'/'.$nom)
                || ! hash_equals($fichier['sha256'], hash('sha256', (string) $disque->get($chemin.'/'.$nom)))) {
                return false;
            }
        }

        return true;
    }

    /**
     * L'archive en un seul fichier ZIP (le téléchargement de l'écran
     * Clôtures) — chemin d'un fichier temporaire, à supprimer après envoi.
     */
    public function zip(ClotureExercice $cloture): string
    {
        if (! $this->verifier($cloture)) {
            throw new RuntimeException(__('comptabilite.archive_alteree'));
        }

        $disque = Storage::disk(self::DISQUE);
        $chemin = tempnam(sys_get_temp_dir(), 'archive_');
        $zip = new ZipArchive();
        if ($chemin === false || $zip->open($chemin, ZipArchive::OVERWRITE) !== true) {
            throw new RuntimeException(__('comptabilite.archive_alteree'));
        }

        foreach ($disque->files((string) $cloture->archive_chemin) as $fichier) {
            $zip->addFromString(basename($fichier), (string) $disque->get($fichier));
        }
        $zip->close();

        return $chemin;
    }

    /**
     * Toutes les lignes d'écriture de l'exercice — journal de clôture compris,
     * contre-passations comprises : l'archive dit tout ce qui a été passé.
     */
    private function fichierEcritures(ExerciceComptable $exercice): string
    {
        $lignes = DB::table('ecritures_comptables as e')
            ->join('journaux_comptables as j', 'j.id', '=', 'e.journal_id')
            ->join('plan_comptable as p', 'p.id', '=', 'e.compte_id')
            ->join('centres_cout as c', 'c.id', '=', 'e.centre_id')
            ->leftJoin('ecritures_comptables as o', 'o.id', '=', 'e.ecriture_contrepassee_id')
            ->leftJoin('utilisateurs as u', 'u.id', '=', 'e.utilisateur_creation_id')
            ->where('e.exercice_id', $exercice->id)
            ->orderBy('e.date_ecriture')
            ->orderBy('j.code')
            ->orderBy('e.numero_piece')
            ->orderBy('e.date_creation')
            ->orderBy('e.id')
            ->get([
                'j.code as journal_code', 'j.libelle as journal_libelle', 'e.numero_piece',
                'e.date_ecriture', 'p.numero_compte', 'p.libelle as compte_libelle',
                'c.libelle as centre', 'e.libelle', 'e.debit', 'e.credit', 'e.statut',
                'o.numero_piece as piece_contrepassee', 'e.date_creation', 'u.login',
            ]);

        $csv = [self::COLONNES_ECRITURES];
        foreach ($lignes as $l) {
            $csv[] = [
                $l->journal_code,
                $l->journal_libelle,
                (string) $l->numero_piece,
                str_replace('-', '', substr((string) $l->date_ecriture, 0, 10)),
                $l->numero_compte,
                $l->compte_libelle,
                $l->centre,
                $l->libelle,
                $this->montant($l->debit),
                $this->montant($l->credit),
                $l->statut,
                (string) $l->piece_contrepassee,
                str_replace('-', '', substr((string) $l->date_creation, 0, 10)),
                (string) $l->login,
            ];
        }

        return $this->csv($csv);
    }

    private function fichierBalance(ExerciceComptable $exercice): string
    {
        $balance = $this->balance->genererPourExercice($exercice->id, ['validee']);

        $csv = [self::COLONNES_BALANCE];
        foreach ($balance->lignes as $ligne) {
            $csv[] = [
                $ligne->numeroCompte,
                $ligne->libelle,
                $ligne->classe,
                $this->montant($ligne->totalDebit),
                $this->montant($ligne->totalCredit),
                $this->montant($ligne->soldeDebiteur),
                $this->montant($ligne->soldeCrediteur),
            ];
        }

        return $this->csv($csv);
    }

    private function etatsDeCloture(ExerciceComptable $exercice, ClotureExercice $cloture, EnTeteRapport $entete): string
    {
        return Pdf::loadView('pdf.comptabilite-etats-cloture', [
            'entete' => $entete,
            'exercice' => $exercice,
            'cloture' => $cloture,
            'balance' => $this->balance->genererPourExercice($exercice->id, ['validee']),
            'compteResultat' => $this->compteResultat->genererPourExercice($exercice->id, ['validee']),
            'bilan' => $this->bilan->genererPourExercice($exercice->id, ['validee']),
        ])->setPaper('a4', 'portrait')->output();
    }

    /**
     * @param  list<list<string>>  $lignes
     */
    private function csv(array $lignes): string
    {
        $flux = fopen('php://temp', 'r+');
        if ($flux === false) {
            throw new RuntimeException('php://temp');
        }

        fwrite($flux, "\xEF\xBB\xBF");
        foreach ($lignes as $ligne) {
            fputcsv($flux, $ligne, ';', '"', '');
        }
        rewind($flux);
        $contenu = (string) stream_get_contents($flux);
        fclose($flux);

        return $contenu;
    }

    private function montant(mixed $valeur): string
    {
        return str_replace('.', ',', bcadd((string) $valeur, '0', 2));
    }
}
