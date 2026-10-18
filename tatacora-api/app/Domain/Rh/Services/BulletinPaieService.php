<?php

declare(strict_types=1);

namespace App\Domain\Rh\Services;

use App\Domain\Rh\Models\BulletinPaie;
use App\Domain\Rh\Models\Employe;
use Illuminate\Database\Eloquent\Collection as EloquentCollection;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Établissement des bulletins de paie — UNIQUE point d'écriture sur
 * `bulletins_paie`.
 *
 * Maître : `prototype_v2/pages/m13-paie.html` et `m13-paie.js`, onglet
 * « Bulletins de paie » ; moteur d'affichage `assets/js/paie-engine.js`.
 *
 * ## Ce service N'A AUCUNE formule de paie, et c'est délibéré
 *
 * Tout le calcul appartient à `CalculPaieService` : cotisation CNSS salariale,
 * barème ITS progressif, part confirmée de la charge patronale. Réécrire ici
 * la moindre de ces formules produirait deux vérités sur le même bulletin, et
 * c'est la copie affichée qui tromperait le Comptable. Ce service ORCHESTRE :
 * il lit le salaire, demande le calcul, et fige le résultat.
 *
 * ## Le refus de calculer est le livrable (PA-53), et il remonte tel quel
 *
 * Deux refus du service de calcul traversent celui-ci sans être adoucis :
 *
 * 1. Le **total** de charge patronale n'existe pas. Le taux CNSS de risques
 *    professionnels est « 1 % à 4 % selon l'activité » et n'est pas confirmé
 *    pour l'hôtellerie-restauration. `fourchetteRisquesProfessionnels()`
 *    publie l'écart ; retenir 2,5 % « au milieu » serait exactement
 *    l'hypothèse que le projet refuse. Sur une masse salariale annuelle,
 *    l'écart entre 1 % et 4 % est un redressement.
 * 2. Le **barème ITS au-delà de 500 000 F** n'est pas tranché (deux sources
 *    divergent). Le moteur du maître porte la même note. Un bulletin est
 *    alors REFUSÉ, avec le message du service de calcul rendu mot pour mot —
 *    l'établir avec une extrapolation produirait une retenue à la source
 *    fausse sur un document conservé sans limitation de durée.
 *
 * ## Pourquoi `etatReferentiel()` existe avant tout calcul
 *
 * `CalculPaieService` lève dès qu'un taux manque — et sur ce dépôt, **aucun
 * taux n'est en base** : `PaieReferentielSeeder` existe, il est documenté,
 * et il n'est appelé par personne (mesuré le 31/08/2026, `grep` à zéro hors
 * autoload). C'est exactement le défaut PA-161 : un seeder écrit, décroché de
 * `DatabaseSeeder`, donc jamais exécuté.
 *
 * L'écran doit donc pouvoir DIRE que le référentiel est vide, sans provoquer
 * une exception au rendu. `etatReferentiel()` répond à cette question par une
 * lecture pure — c'est le même geste qu'`etatTva()`, qui nomme l'état réel
 * pour que l'incohérence se voie **avant** d'atteindre une opération (PA-62).
 *
 * @see EF-M13-07 Calcul de la paie conforme à la réglementation béninoise
 * @see RG-15 Journalisation des opérations
 */
class BulletinPaieService
{
    private const PRECISION = 2;

    public function __construct(
        private readonly CalculPaieService $calcul,
    ) {
    }

    // =====================================================================
    // État du référentiel — lecture pure, aucun calcul déclenché
    // =====================================================================

    /**
     * Quels taux sont paramétrés, et lesquels manquent.
     *
     * `risques_professionnels` est listé à part : son absence est VOULUE
     * (PA-53) et ne bloque aucun bulletin. Les quatre autres, eux, sont
     * confirmés à la source et leur absence est une installation incomplète.
     *
     * @return array{salarial: bool, patronal: bool, complet: bool, cles_absentes: list<string>, risques_professionnels: bool}
     */
    public function etatReferentiel(): array
    {
        $requis = [
            CalculPaieService::CLE_CNSS_SALARIE,
            CalculPaieService::CLE_CNSS_PENSION_EMPLOYEUR,
            CalculPaieService::CLE_CNSS_PRESTATIONS_FAMILIALES,
            CalculPaieService::CLE_VPS,
        ];

        $absentes = array_values(array_filter(
            $requis,
            fn (string $cle): bool => ! $this->calcul->tauxEstConfigure($cle),
        ));

        $salarial = $this->calcul->tauxEstConfigure(CalculPaieService::CLE_CNSS_SALARIE);

        $patronal = $this->calcul->tauxEstConfigure(CalculPaieService::CLE_CNSS_PENSION_EMPLOYEUR)
            && $this->calcul->tauxEstConfigure(CalculPaieService::CLE_CNSS_PRESTATIONS_FAMILIALES)
            && $this->calcul->tauxEstConfigure(CalculPaieService::CLE_VPS);

        return [
            'salarial' => $salarial,
            'patronal' => $patronal,
            'complet' => $absentes === [],
            'cles_absentes' => $absentes,
            // Volontairement absent tant que la CNSS n'a pas confirmé la
            // catégorie de risque du secteur — ce n'est PAS une anomalie.
            'risques_professionnels' => $this->calcul->tauxEstConfigure(
                CalculPaieService::CLE_CNSS_RISQUES_PROFESSIONNELS,
            ),
        ];
    }

    /**
     * Le coût employeur d'un brut, en FOURCHETTE — jamais un chiffre unique.
     *
     * Rend `null` si les trois taux patronaux confirmés ne sont pas
     * paramétrés : l'écran affiche alors un tiret et dit pourquoi, plutôt que
     * de laisser une exception traverser le rendu.
     *
     * @return array{confirmees: string, rp_min: string, rp_max: string, cout_min: string, cout_max: string, ecart: string}|null
     */
    public function coutEmployeur(string $brut): ?array
    {
        if (! $this->etatReferentiel()['patronal']) {
            return null;
        }

        $confirmees = $this->calcul->chargesPatronalesConfirmees($brut);
        $fourchette = $this->calcul->fourchetteRisquesProfessionnels($brut);

        return [
            'confirmees' => $confirmees['total'],
            'rp_min' => $fourchette['minimum'],
            'rp_max' => $fourchette['maximum'],
            'cout_min' => bcadd(bcadd($brut, $confirmees['total'], self::PRECISION), $fourchette['minimum'], self::PRECISION),
            'cout_max' => bcadd(bcadd($brut, $confirmees['total'], self::PRECISION), $fourchette['maximum'], self::PRECISION),
            'ecart' => $fourchette['ecart'],
        ];
    }

    /**
     * Le détail complet d'un brut — le simulateur de l'onglet « Barèmes ».
     *
     * ⚠ Le `catch` ici ne masque RIEN : il transporte le message de refus de
     * `CalculPaieService` jusqu'à l'écran, mot pour mot. C'est la seule façon
     * de rendre le refus tangible plutôt que théorique, ce que le maître fait
     * aussi (« Calcul refusé. » suivi du message). Le refus est une SORTIE de
     * cette méthode, pas une erreur avalée : la clé `refus` est renseignée, et
     * l'écran l'affiche. Un `return null` silencieux, lui, serait le défaut.
     *
     * @return array{refus: string|null, retenues: array<string, string>|null, cout: array<string, string>|null}
     */
    public function simuler(string $brut): array
    {
        $etat = $this->etatReferentiel();

        if (! $etat['salarial'] || ! $etat['patronal']) {
            return [
                'refus' => __('rh_pwa.referentiel_incomplet_court'),
                'retenues' => null,
                'cout' => null,
            ];
        }

        try {
            $retenues = $this->calcul->retenuesSalariales($brut);
        } catch (RuntimeException $refus) {
            return ['refus' => $refus->getMessage(), 'retenues' => null, 'cout' => null];
        }

        return [
            'refus' => null,
            'retenues' => $retenues,
            'cout' => $this->coutEmployeur($brut),
        ];
    }

    // =====================================================================
    // Écritures
    // =====================================================================

    /**
     * Établit le bulletin d'un salarié pour une période `AAAA-MM`.
     *
     * Idempotent par construction : `bulletins_paie` porte
     * `unique(employe_id, periode)`, et un bulletin déjà établi est rendu tel
     * quel plutôt que ré-alloué. Un second appel ne brûle donc aucun numéro —
     * même piège que `FactureDao.numeroSuivant()`, qui ALLOUE et n'est jamais
     * une lecture (PA-101).
     *
     * @throws RuntimeException référentiel incomplet, période mal formée,
     *                          salarié parti, ou barème ITS dépassé
     */
    public function etablirBulletin(Employe $employe, string $periode, ?string $id = null): BulletinPaie
    {
        $this->exigerPeriode($periode);

        $etat = $this->etatReferentiel();

        if (! $etat['complet']) {
            throw new RuntimeException(__('rh_pwa.referentiel_incomplet', [
                'cles' => implode(', ', $etat['cles_absentes']),
            ]));
        }

        if ($employe->statut === 'parti') {
            throw new RuntimeException(__('rh_pwa.employe_parti', ['nom' => $employe->nomComplet()]));
        }

        $brut = (string) $employe->salaire_base;

        // Le calcul est fait AVANT d'ouvrir la transaction : un refus de
        // barème ne doit pas laisser derrière lui un numéro alloué.
        $retenues = $this->calcul->retenuesSalariales($brut);
        $patronales = $this->calcul->chargesPatronalesConfirmees($brut);

        return DB::transaction(function () use ($employe, $periode, $brut, $retenues, $patronales, $id): BulletinPaie {
            $existant = BulletinPaie::query()
                ->where('employe_id', $employe->getKey())
                ->where('periode', $periode)
                ->lockForUpdate()
                ->first();

            if ($existant instanceof BulletinPaie) {
                return $existant;
            }

            return BulletinPaie::create([
                // Audit de couverture (18/10/2026) : l'UUID du poste.
                ...($id !== null ? ['id' => $id] : []),
                'numero' => $this->numeroSuivant($periode),
                'employe_id' => $employe->getKey(),
                'periode' => $periode,
                'salaire_base' => $brut,
                // Aucune prime : `primes_sanctions` n'a ni modèle ni service
                // dans ce dépôt (vérifié le 31/08/2026). Le maître offre un
                // « + Ajouter un élément » qui n'est donc pas rendu, et le
                // refus est nommé à l'écran plutôt que laissé en bouton
                // inerte (DIRECTIVE_CONFORMITE_100.md Article 3.3).
                'total_primes' => '0.00',
                'total_retenues' => $retenues['total_retenues'],
                'cnss_salarie' => $retenues['cnss_salarie'],
                'its' => $retenues['its'],
                // `charges_sociales` est la colonne d'origine du schéma : elle
                // porte la même part confirmée. Les deux sont écrites
                // ensemble pour qu'aucune lecture existante ne trouve zéro.
                'charges_sociales' => $patronales['total'],
                'charges_patronales_confirmees' => $patronales['total'],
                'net_a_payer' => $retenues['net_a_payer'],
                'statut' => BulletinPaie::STATUT_BROUILLON,
            ]);
        });
    }

    /**
     * Établit les bulletins manquants de la période — geste « Générer les
     * bulletins manquants » du maître.
     *
     * Un salarié dont le bulletin est REFUSÉ (barème ITS dépassé) n'interrompt
     * pas les autres : son refus est collecté et rendu, nommé. Échouer le lot
     * entier ferait perdre neuf bulletins corrects pour un cas non tranché.
     *
     * @return array{etablis: int, refus: list<array{employe: string, motif: string}>}
     */
    public function etablirBulletinsManquants(string $periode): array
    {
        $etablis = 0;
        $refus = [];

        foreach ($this->employesSansBulletin($periode) as $employe) {
            try {
                $this->etablirBulletin($employe, $periode);
                $etablis++;
            } catch (RuntimeException $erreur) {
                // Le motif est RENDU, jamais avalé : c'est ce qui distingue un
                // salarié hors barème d'un salarié oublié.
                $refus[] = ['employe' => $employe->nomComplet(), 'motif' => $erreur->getMessage()];
            }
        }

        return ['etablis' => $etablis, 'refus' => $refus];
    }

    /**
     * Annule un bulletin, avec motif obligatoire — jamais une suppression.
     *
     * Le bulletin sort du livre de paie et des déclarations, et reste au
     * dossier du salarié : « il est conservé et reste traçable : rien n'est
     * effacé » (mot du maître). Même geste métier que RG-02 en M1.
     *
     * @throws RuntimeException motif vide, ou bulletin déjà annulé
     */
    public function annulerBulletin(BulletinPaie $bulletin, string $motif): BulletinPaie
    {
        $motif = trim($motif);

        if ($motif === '') {
            throw new RuntimeException(__('rh_pwa.motif_annulation_requis'));
        }

        if ($bulletin->estAnnule()) {
            throw new RuntimeException(__('rh_pwa.bulletin_deja_annule'));
        }

        return DB::transaction(function () use ($bulletin, $motif): BulletinPaie {
            $bulletin->update([
                'statut' => BulletinPaie::STATUT_ANNULEE,
                'motif_annulation' => $motif,
            ]);

            return $bulletin->refresh();
        });
    }

    // =====================================================================
    // Lectures
    // =====================================================================

    /**
     * Les bulletins d'une période, salariés chargés.
     *
     * @return EloquentCollection<int, BulletinPaie>
     */
    public function bulletinsDuMois(string $periode): EloquentCollection
    {
        return BulletinPaie::query()
            ->with('employe.service')
            ->where('periode', $periode)
            ->get()
            ->sortBy(fn (BulletinPaie $b): string => $b->employe->nomComplet())
            ->values();
    }

    /**
     * Les salariés en poste qui n'ont pas encore de bulletin sur la période.
     *
     * Un bulletin ANNULÉ ne rend pas le salarié « manquant » : le
     * réétablir buterait sur `unique(employe_id, periode)` et l'écran
     * afficherait une erreur SQL pour une raison qui n'a rien à voir avec le
     * geste demandé.
     *
     * @return EloquentCollection<int, Employe>
     */
    public function employesSansBulletin(string $periode): EloquentCollection
    {
        $deja = BulletinPaie::query()->where('periode', $periode)->pluck('employe_id');

        return Employe::query()
            ->with('service')
            ->whereIn('statut', ['actif', 'conge'])
            ->whereNotIn('id', $deja)
            ->orderBy('nom')
            ->get();
    }

    /**
     * Le récapitulatif d'un bulletin, tel que le maître l'imprime.
     *
     * Tous les montants viennent des colonnes FIGÉES à l'établissement. Seule
     * la fourchette de risques professionnels est recalculée : elle ne
     * dépend d'aucun taux paramétré (les bornes 1 % et 4 % sont
     * réglementaires) et ne peut donc pas dériver.
     *
     * @return array{brut: string, revenu_imposable: string, cnss_salarie: string, its: string, autres_retenues: string, net_a_payer: string, patronales_confirmees: string, rp_min: string, rp_max: string, cout_min: string, cout_max: string}
     */
    public function recapitulatif(BulletinPaie $bulletin): array
    {
        $brut = $bulletin->brut();
        $fourchette = $this->calcul->fourchetteRisquesProfessionnels($brut);
        $confirmees = (string) $bulletin->charges_patronales_confirmees;
        $base = bcadd($brut, $confirmees, self::PRECISION);

        return [
            'brut' => $brut,
            'revenu_imposable' => $bulletin->revenuImposable(),
            'cnss_salarie' => (string) $bulletin->cnss_salarie,
            'its' => (string) $bulletin->its,
            'autres_retenues' => $bulletin->autresRetenues(),
            'net_a_payer' => (string) $bulletin->net_a_payer,
            'patronales_confirmees' => $confirmees,
            'rp_min' => $fourchette['minimum'],
            'rp_max' => $fourchette['maximum'],
            'cout_min' => bcadd($base, $fourchette['minimum'], self::PRECISION),
            'cout_max' => bcadd($base, $fourchette['maximum'], self::PRECISION),
        ];
    }

    // ------------------------------------------------------------- internes

    /**
     * @throws RuntimeException
     */
    private function exigerPeriode(string $periode): void
    {
        if (preg_match('/^\d{4}-(0[1-9]|1[0-2])$/', $periode) !== 1) {
            throw new RuntimeException(__('rh_pwa.periode_invalide', ['periode' => $periode]));
        }
    }

    /**
     * `BUL-AAAA-NNNNN` — alloué sous verrou dans la transaction appelante.
     *
     * Même garantie que `SequenceDocumentService` : la lecture du maximum
     * sans verrou laisserait deux établissements simultanés rendre le même
     * numéro, et l'index unique le rejetterait sous un message SQL que
     * personne ne rattache au geste.
     */
    private function numeroSuivant(string $periode): string
    {
        $motif = sprintf('%s-%s-', BulletinPaie::PREFIXE_NUMERO, substr($periode, 0, 4));

        $dernier = DB::table('bulletins_paie')
            ->where('numero', 'like', $motif.'%')
            ->orderByDesc('numero')
            ->lockForUpdate()
            ->value('numero');

        $rang = $dernier === null ? 0 : (int) substr((string) $dernier, strlen($motif));

        return $motif.str_pad((string) ($rang + 1), 5, '0', STR_PAD_LEFT);
    }
}
