<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Models;

use App\Domain\Crm\Models\Client;
use App\Domain\Facturation\Observers\FactureObserver;
use App\Domain\Numerotation\Services\SequenceDocumentService;
use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Attributes\ObservedBy;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Carbon;

/**
 * Facture normalisée MECeF (M2).
 *
 * @see EF-M2-01 Émission de facture
 * @see RG-03 Immutabilité — une facture certifiée ne peut plus être modifiée
 *      ni supprimée ; la seule correction possible est un avoir. L'Observer
 *      qui bloque UPDATE/DELETE post-certification relève du sprint M2,
 *      hors périmètre du Sprint 0 (infrastructure uniquement).
 * @see RG-15 Journalisation (trait Auditable)
 *
 * @property string $id
 * @property string|null $numero_mecef Null tant que la certification MECeF n'a pas eu lieu
 * @property string $client_id
 * @property \Illuminate\Support\Carbon $date_emission
 * @property string $montant_ht
 * @property string $montant_tva
 * @property string $montant_ttc
 * @property string $statut
 * @property string|null $qr_code_fiscal
 */
#[ObservedBy(FactureObserver::class)]
class Facture extends Model
{
    use Auditable;
    use HasUuids;

    protected $table = 'factures';

    protected $fillable = [
        'id',
        'numero',
        'origine',
        'numero_mecef',
        'client_id',
        'date_emission',
        'montant_ht',
        'montant_tva',
        'montant_ttc',
        'statut',
        'qr_code_fiscal',
    ];

    protected function casts(): array
    {
        return [
            'date_emission' => 'date',
            // Montants : DECIMAL(15,2). Toute comparaison passe par bccomp(),
            // jamais une égalité flottante directe (A1_MASTER_PROMPT.md §2.5).
            'montant_ht' => 'decimal:2',
            'montant_tva' => 'decimal:2',
            'montant_ttc' => 'decimal:2',
            'date_creation' => 'datetime',
            'date_modification' => 'datetime',
        ];
    }

    /**
     * La facture est-elle définitivement figée (RG-03) ?
     *
     * C'est un état du CYCLE DE VIE, pas une affirmation fiscale : une facture
     * certifiée en mode démonstration est figée elle aussi, et c'est voulu.
     * La laisser modifiable ferait que le chemin d'immuabilité ne serait jamais
     * emprunté en Développement ni en Recette — le défaut que la campagne
     * PA-59 → PA-99 a démonté sous toutes ses formes : un chemin qui n'a
     * jamais tourné est un chemin dont personne ne sait s'il fonctionne.
     *
     * Pour savoir si une facture a une valeur fiscale, c'est
     * {@see estCertifiee()} qu'il faut appeler — jamais celle-ci.
     */
    /**
     * Lot F5c (décision PO du 17/10/2026) : le numéro continu `F-AAAA-NNNNN`,
     * alloué à la création, à l'année de l'ÉMISSION — un seul point pour la
     * PWA et la synchronisation. La création doit avoir lieu dans une
     * transaction (le verrou de la séquence y est tenu).
     */
    protected static function booted(): void
    {
        static::creating(static function (Facture $facture): void {
            $facture->numero ??= app(SequenceDocumentService::class)->suivant(
                'factures',
                'F',
                $facture->date_emission === null ? null : (int) Carbon::parse($facture->date_emission)->format('Y'),
            );
        });
    }

    public function estFigee(): bool
    {
        return $this->statut === 'certifiee';
    }

    /**
     * La facture porte-t-elle une certification fiscale RÉELLE ?
     *
     * **Ce prédicat rendait `true` en mode démonstration jusqu'au 20/08/2026**,
     * parce qu'il ne lisait que `statut`, que le job de rejeu met à `certifiee`
     * même quand `MecefClientFake` a produit un numéro `MECEF-DEMO-`. Il n'était
     * appelé que pour figer la facture, donc rien ne se voyait — mais le premier
     * badge, en-tête de PDF ou état qui l'aurait consulté pour dire « certifiée »
     * aurait annoncé une certification fiscale qui n'a pas eu lieu.
     *
     * C'est **PA-61 mot pour mot** : le badge MECeF dérivait `active` de la
     * configuration seule, alors que seul le client réellement lié décrit un
     * fait. La règle est la même ici et ne souffre pas d'exception
     * (`MECEF_INTEGRATION_SPEC.md` §7.4) : **un indicateur d'état se dérive de
     * ce qui est réellement en place, jamais de ce qui est prévu de l'être.**
     *
     * Le nom porte donc désormais ce qu'un lecteur y comprend. Celui qui veut
     * l'état du cycle de vie appelle {@see estFigee()}, et il doit le vouloir
     * explicitement.
     */
    public function estCertifiee(): bool
    {
        return $this->estFigee() && ! $this->estCertificationDemonstration();
    }

    /**
     * Une facture certifiée en mode démonstration n'a AUCUNE valeur fiscale.
     * Le distinguer est obligatoire à l'écran comme au PDF
     * (MECEF_INTEGRATION_SPEC.md §7.4).
     *
     * N'avait aucun appelant jusqu'au 20/08/2026 — déclaré, jamais branché.
     * {@see estCertifiee()} le consulte maintenant, ce qui met la distinction
     * sur le chemin par défaut au lieu de la laisser à la vigilance de chacun.
     */
    public function estCertificationDemonstration(): bool
    {
        return str_starts_with((string) $this->numero_mecef, 'MECEF-DEMO-');
    }

    /**
     * Le client débiteur — `factures.client_id` (PA-116, vraie clé
     * étrangère). Manquait jusqu'au 02/09/2026 (PA-165) : le seul lecteur
     * existant (`FacturationExport`) contournait l'absence par une carte
     * préchargée plutôt que par la relation. La colonne « Client » du
     * relevé de recouvrements (M3) la lit par cette relation.
     *
     * @return BelongsTo<Client, $this>
     */
    public function client(): BelongsTo
    {
        return $this->belongsTo(Client::class, 'client_id');
    }

    /**
     * Lignes issues de tous les modules — RG-04.
     *
     * @return HasMany<LigneFacture, $this>
     */
    public function lignes(): HasMany
    {
        return $this->hasMany(LigneFacture::class, 'facture_id');
    }

    /**
     * @return HasMany<Avoir, $this>
     */
    public function avoirs(): HasMany
    {
        return $this->hasMany(Avoir::class, 'facture_id');
    }

    /**
     * @return HasMany<Paiement, $this>
     */
    public function paiements(): HasMany
    {
        return $this->hasMany(Paiement::class, 'facture_id');
    }

    // =====================================================================
    // Créance — PA-165 : UNE formule SQL, écrite ICI et nulle part ailleurs
    // =====================================================================

    /**
     * Somme des encaissements reçus sur la facture.
     *
     * Ces fragments vivaient dans `SoldeClientService` (M3) ; ils remontent
     * sur le modèle avec le premier writer de `paiements` — la créance est un
     * fait de la FACTURE, et deux formules (une SQL côté M3, une PHP côté M2)
     * auraient divergé au premier terme ajouté. `SoldeClientService` et
     * `TableauDeBordService` référencent CES constantes.
     */
    public const SQL_PAIEMENTS_RECUS = 'COALESCE((SELECT SUM(p.montant) FROM paiements p '
        ."WHERE p.facture_id = factures.id AND p.statut = 'actif'), 0)";

    /** Un avoir vient en diminution de la créance — RG-03, l'unique correction. */
    public const SQL_AVOIRS_EMIS = 'COALESCE((SELECT SUM(a.montant) FROM avoirs a '
        .'WHERE a.facture_id = factures.id), 0)';

    /**
     * Les acomptes des réservations que la facture couvre (lignes RG-04 de
     * source M1). Un acompte est versé à la RÉSERVATION, avant l'émission :
     * il n'existe pas en `paiements` — sa trésorerie n'a jamais été
     * enregistrée — mais réclamer un « reste dû » qui l'ignore ferait payer
     * deux fois la même avance (le défaut de la remise de PA-111, sous une
     * autre forme).
     */
    public const SQL_ACOMPTES_LIES = 'COALESCE((SELECT SUM(r.acompte) FROM reservations r '
        ."WHERE r.id IN (SELECT lf.source_id FROM lignes_facture lf "
        ."WHERE lf.facture_id = factures.id AND lf.source_module = 'M1')), 0)";

    /**
     * Le reste dû : TTC − avoirs − encaissements − acomptes liés.
     *
     * SANS plancher : le prédicat « impayée » (`> 0`) et la somme par client
     * l'utilisent tel quel, et un résultat négatif doit se VOIR comme
     * l'anomalie qu'il est — `EncaissementFactureService` refuse tout
     * paiement supérieur au reste dû, précisément pour qu'il n'existe pas.
     */
    public const SQL_RESTE_DU = '(factures.montant_ttc - '.self::SQL_AVOIRS_EMIS
        .' - '.self::SQL_PAIEMENTS_RECUS.' - '.self::SQL_ACOMPTES_LIES.')';

    /**
     * Le reste dû de CETTE facture — la formule SQL exécutée sur sa ligne,
     * jamais une réécriture PHP qui finirait par diverger. Plancher 0 à
     * l'affichage : « rien à réclamer » se dit, un négatif se refuse en amont.
     */
    public function resteDu(): string
    {
        $reste = (string) self::query()
            ->whereKey($this->id)
            ->from('factures')
            ->selectRaw(self::SQL_RESTE_DU.' AS reste')
            ->value('reste');

        return bccomp($reste, '0.00', 2) < 0 ? '0.00' : bcadd($reste, '0', 2);
    }

    public function totalEncaisse(): string
    {
        // Le même prédicat que SQL_PAIEMENTS_RECUS : un paiement ANNULÉ
        // (PA-168) ne compte plus — sa pièce est contre-passée, le garder au
        // total ferait diverger l'écran du grand livre.
        return bcadd((string) ($this->paiements()->where('statut', 'actif')->sum('montant') ?: '0'), '0', 2);
    }

    public function estSoldee(): bool
    {
        return bccomp($this->resteDu(), '0.00', 2) === 0;
    }
}
