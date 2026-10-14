<?php

declare(strict_types=1);

namespace App\Domain\Rh\Services;

use App\Domain\Rh\Models\BulletinPaie;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Collection as EloquentCollection;

/**
 * Livre de paie et déclarations d'une période — LECTURE seule.
 *
 * Maître : `prototype_v2/pages/m13-paie.html`, onglets « Livre de paie » et
 * « Déclarations » ; moteur `assets/js/paie-engine.js`.
 *
 * ## Aucune écriture, aucune formule de paie
 *
 * Ce service ADDITIONNE des colonnes déjà figées sur les bulletins. Il ne
 * recalcule ni la CNSS ni l'ITS : les reprendre aux taux d'aujourd'hui ferait
 * diverger le livre du bulletin qu'il totalise, et c'est la ligne du livre que
 * le Comptable reporterait sur sa déclaration.
 *
 * ## Un bulletin ANNULÉ ne compte nulle part
 *
 * Ni au livre, ni aux déclarations, ni à l'effectif payé. Il reste au dossier
 * du salarié : c'est la différence entre annuler et supprimer, et c'est aussi
 * pourquoi le total du livre ne peut jamais se relire comme un compte de
 * bulletins existants.
 *
 * ## Les déclarations portent un état, pas une promesse
 *
 * Trois déclarations, deux « arrêtées » et une « incomplète » :
 *
 * - **VPS** : arrêté. Taxe employeur de 4 % sur le brut total, sans plafond,
 *   exigible au plus tard le 10 du mois suivant. Le service en donne
 *   l'échéance, calculée, jamais saisie.
 * - **ITS** : arrêté. Retenu à la source, reversé à la DGI.
 * - **CNSS** : **incomplet**, et il le dit. Le montant additionne la part
 *   salariale, la pension et les prestations familiales — il EXCLUT les
 *   risques professionnels, dont le taux (« 1 % à 4 % selon l'activité »)
 *   n'est pas confirmé pour l'hôtellerie-restauration (PA-53). Présenter ce
 *   montant comme arrêté ferait déclarer une cotisation minorée.
 *
 * Aucun état « déclaré » ou « télédéclaré » n'existe : rien ne transmet ces
 * déclarations, et un badge qui l'affirmerait serait PA-59/60/61.
 *
 * ## Ce qui n'est PAS porté ici, avec sa raison datée
 *
 * L'« Écriture comptable proposée » du maître et son bouton « Comptabiliser
 * la paie ». Vérifié le 31/08/2026 : `create_rh.php` annonce lui-même un
 * « listener GenererEcritureDepuisPaie » — il n'existe nulle part dans le
 * dépôt. Écrire la pièce depuis M13 doublerait `PasserEcritureService`, seul
 * point d'entrée d'écriture comptable (RG-11 vit dans
 * `EcritureComptableObserver`, jamais dans un service appelant). Le refus est
 * nommé à l'écran plutôt que rendu en bouton inerte.
 *
 * @see EF-M13-07 Calcul de la paie conforme à la réglementation béninoise
 */
class LivreDePaieService
{
    private const PRECISION = 2;

    public function __construct(
        private readonly BulletinPaieService $bulletins,
        private readonly CalculPaieService $calcul,
    ) {
    }

    /**
     * Les totaux d'une période — bulletins annulés exclus.
     *
     * @return array{
     *     periode: string, effectif: int, sans_numero_cnss: int,
     *     brut: string, cnss_salarie: string, its: string, autres_retenues: string, net: string,
     *     pension: string, familiales: string, vps: string,
     *     patronales_confirmees: string, rp_min: string, rp_max: string,
     *     cout_min: string, cout_max: string
     * }
     */
    public function totaux(string $periode): array
    {
        $actifs = $this->bulletinsRetenus($periode);

        $brut = '0.00';
        $cnss = '0.00';
        $its = '0.00';
        $autres = '0.00';
        $net = '0.00';
        $confirmees = '0.00';
        $sansCnss = 0;

        foreach ($actifs as $bulletin) {
            $brut = bcadd($brut, $bulletin->brut(), self::PRECISION);
            $cnss = bcadd($cnss, (string) $bulletin->cnss_salarie, self::PRECISION);
            $its = bcadd($its, (string) $bulletin->its, self::PRECISION);
            $autres = bcadd($autres, $bulletin->autresRetenues(), self::PRECISION);
            $net = bcadd($net, (string) $bulletin->net_a_payer, self::PRECISION);
            $confirmees = bcadd($confirmees, (string) $bulletin->charges_patronales_confirmees, self::PRECISION);

            if ($bulletin->employe->sansNumeroCnss()) {
                $sansCnss++;
            }
        }

        // La VENTILATION de la part patronale se recalcule sur le brut total :
        // les trois taux sont confirmés, et le bulletin ne stocke que leur
        // somme. Elle reste cohérente avec `charges_patronales_confirmees` —
        // et si un taux venait à changer, l'écart se verrait entre la somme
        // des lignes et le total figé, ce qui est exactement le signal voulu.
        $ventilation = $this->ventilationPatronale($brut);
        $fourchette = $this->calcul->fourchetteRisquesProfessionnels($brut);
        $base = bcadd($brut, $confirmees, self::PRECISION);

        return [
            'periode' => $periode,
            'effectif' => $actifs->count(),
            'sans_numero_cnss' => $sansCnss,
            'brut' => $brut,
            'cnss_salarie' => $cnss,
            'its' => $its,
            'autres_retenues' => $autres,
            'net' => $net,
            'pension' => $ventilation['pension'],
            'familiales' => $ventilation['prestations_familiales'],
            'vps' => $ventilation['vps'],
            'patronales_confirmees' => $confirmees,
            'rp_min' => $fourchette['minimum'],
            'rp_max' => $fourchette['maximum'],
            'cout_min' => bcadd($base, $fourchette['minimum'], self::PRECISION),
            'cout_max' => bcadd($base, $fourchette['maximum'], self::PRECISION),
        ];
    }

    /**
     * Les trois déclarations de la période.
     *
     * @return list<array{code: string, libelle: string, note: string, montant: string, echeance: string|null, complet: bool}>
     */
    public function declarations(string $periode): array
    {
        $t = $this->totaux($periode);

        $cnss = bcadd(bcadd($t['cnss_salarie'], $t['pension'], self::PRECISION), $t['familiales'], self::PRECISION);

        return [
            [
                'code' => 'CNSS',
                'libelle' => __('rh_pwa.declaration_cnss_libelle'),
                'note' => __('rh_pwa.declaration_cnss_note'),
                'montant' => $cnss,
                'echeance' => null,
                // Hors risques professionnels : le montant est un MINIMUM.
                'complet' => false,
            ],
            [
                'code' => 'VPS',
                'libelle' => __('rh_pwa.declaration_vps_libelle'),
                'note' => __('rh_pwa.declaration_vps_note'),
                'montant' => $t['vps'],
                'echeance' => $this->echeanceVps($periode),
                'complet' => true,
            ],
            [
                'code' => 'ITS',
                'libelle' => __('rh_pwa.declaration_its_libelle'),
                'note' => __('rh_pwa.declaration_its_note'),
                'montant' => $t['its'],
                'echeance' => null,
                'complet' => true,
            ],
        ];
    }

    /**
     * L'échéance du VPS : le 10 du mois SUIVANT la période.
     *
     * Calculée, jamais saisie — une date d'échéance recopiée à la main
     * vieillit d'un mois à chaque période et personne ne s'en aperçoit.
     */
    public function echeanceVps(string $periode): ?string
    {
        if (preg_match('/^\d{4}-(0[1-9]|1[0-2])$/', $periode) !== 1) {
            return null;
        }

        return CarbonImmutable::createFromFormat('Y-m-d', $periode.'-01')
            ->addMonth()
            ->setDay(10)
            ->format('d/m/Y');
    }

    /**
     * Les bulletins retenus au livre — annulés exclus.
     *
     * @return EloquentCollection<int, BulletinPaie>
     */
    public function bulletinsRetenus(string $periode): EloquentCollection
    {
        /** @var EloquentCollection<int, BulletinPaie> $retenus */
        $retenus = $this->bulletins->bulletinsDuMois($periode)
            ->reject(fn (BulletinPaie $b): bool => $b->estAnnule())
            ->values();

        return $retenus;
    }

    /**
     * @return array{pension: string, prestations_familiales: string, vps: string, total: string}
     */
    private function ventilationPatronale(string $brut): array
    {
        if (! $this->bulletins->etatReferentiel()['patronal']) {
            return [
                'pension' => '0.00',
                'prestations_familiales' => '0.00',
                'vps' => '0.00',
                'total' => '0.00',
            ];
        }

        return $this->calcul->chargesPatronalesConfirmees($brut);
    }
}
