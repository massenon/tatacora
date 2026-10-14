<?php

declare(strict_types=1);

namespace App\Domain\Rh\Models;

use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Bulletin de paie d'un salarie pour un mois — EF-M13-07.
 *
 * Maitre : `prototype_v2/pages/m13-paie.html`, onglet « Bulletins de paie ».
 *
 * ## Chaque montant est FIGE a l'etablissement, aucun n'est recalcule
 *
 * `cnss_salarie`, `its`, `net_a_payer` et `charges_patronales_confirmees` sont
 * persistes. Les recalculer a l'affichage les reprendrait aux taux
 * d'AUJOURD'HUI : un bulletin de mars relu en decembre changerait de montant
 * si un taux avait bouge entre-temps, sur un document remis au salarie et
 * conserve sans limitation de duree. C'est le meme raisonnement que
 * `tarif_nuit` fige a la reservation (PA-55).
 *
 * ## Aucun TOTAL de charge patronale, et c'est le livrable (PA-53)
 *
 * `charges_patronales_confirmees` porte 19,4 % du brut — CNSS pension 6,4 %,
 * prestations familiales 9 %, VPS 4 %, tous confirmes sur cnss.bj. Le taux de
 * risques professionnels est « 1 % a 4 % selon l'activite » et n'est pas
 * confirme pour l'hotellerie-restauration : aucune colonne ne l'accueille, et
 * `CalculPaieService::fourchetteRisquesProfessionnels()` publie l'ecart plutot
 * que de le moyenner. Une colonne `charges_patronales_total` appellerait un
 * jour un chiffre, et ce chiffre serait suppose.
 *
 * ## Le VPS n'est JAMAIS une retenue
 *
 * Il est compris dans `charges_patronales_confirmees` et n'entre jamais dans
 * `total_retenues` : c'est une taxe directe a la charge de l'employeur, assise
 * sur le brut sans plafond. L'inscrire en retenue minorerait le net a payer du
 * salarie de 4 % — un bulletin faux, donc une declaration sociale erronee.
 *
 * ## Un bulletin ne se supprime pas : il s'annule, avec un motif
 *
 * `BasePolicy::delete()` rend `false` pour les vingt policies du depot, et le
 * maitre annule avec motif obligatoire en ecrivant « il est conserve et reste
 * tracable : rien n'est efface ». Un bulletin annule sort du livre de paie et
 * des declarations, il ne disparait pas du dossier du salarie (RG-15).
 *
 * @see EF-M13-07 Calcul de la paie conforme a la reglementation beninoise
 * @see RG-15 Journalisation des operations (trait Auditable)
 *
 * @property string $id
 * @property string|null $numero
 * @property string $employe_id
 * @property string $periode
 * @property string $salaire_base
 * @property string $total_primes
 * @property string $total_retenues
 * @property string $cnss_salarie
 * @property string $its
 * @property string $charges_sociales
 * @property string $charges_patronales_confirmees
 * @property string $net_a_payer
 * @property string $statut
 * @property string|null $motif_annulation
 * @property-read Employe $employe
 */
class BulletinPaie extends Model
{
    use Auditable;
    use HasUuids;

    public const STATUT_BROUILLON = 'brouillon';

    public const STATUT_VALIDEE = 'validee';

    public const STATUT_ANNULEE = 'annulee';

    /** Prefixe de numerotation des bulletins — `BUL-AAAA-NNNNN`. */
    public const PREFIXE_NUMERO = 'BUL';

    protected $table = 'bulletins_paie';

    protected $fillable = [
        'id', 'numero', 'employe_id', 'periode',
        'salaire_base', 'total_primes', 'total_retenues',
        'cnss_salarie', 'its',
        'charges_sociales', 'charges_patronales_confirmees',
        'net_a_payer', 'statut', 'motif_annulation',
    ];

    protected function casts(): array
    {
        return [
            'salaire_base' => 'decimal:2',
            'total_primes' => 'decimal:2',
            'total_retenues' => 'decimal:2',
            'cnss_salarie' => 'decimal:2',
            'its' => 'decimal:2',
            'charges_sociales' => 'decimal:2',
            'charges_patronales_confirmees' => 'decimal:2',
            'net_a_payer' => 'decimal:2',
            'date_creation' => 'datetime',
            'date_modification' => 'datetime',
        ];
    }

    /**
     * Le brut soumis a cotisations — salaire de base plus primes.
     *
     * CALCULE, jamais stocke : deux colonnes qui doivent s'additionner pour
     * en donner une troisieme finissent par ne plus s'additionner.
     */
    public function brut(): string
    {
        return bcadd((string) $this->salaire_base, (string) $this->total_primes, 2);
    }

    /**
     * Le revenu imposable — brut moins la cotisation salariale.
     *
     * Meme formule que `CalculPaieService::retenuesSalariales()` : appliquer
     * le bareme au brut surtaxerait chaque bulletin.
     */
    public function revenuImposable(): string
    {
        return bcsub($this->brut(), (string) $this->cnss_salarie, 2);
    }

    /**
     * Les retenues qui ne sont ni la CNSS ni l'ITS — avances, oppositions.
     *
     * Colonne du maitre « Autres retenues ». Elle se DEDUIT du total plutot
     * que de vivre a cote : un total qui ne serait pas la somme de ses parts
     * est le defaut le plus difficile a voir sur un bulletin.
     */
    public function autresRetenues(): string
    {
        $sociales = bcadd((string) $this->cnss_salarie, (string) $this->its, 2);

        return bcsub((string) $this->total_retenues, $sociales, 2);
    }

    public function estAnnule(): bool
    {
        return $this->statut === self::STATUT_ANNULEE;
    }

    /**
     * @return BelongsTo<Employe, $this>
     */
    public function employe(): BelongsTo
    {
        return $this->belongsTo(Employe::class, 'employe_id');
    }
}
