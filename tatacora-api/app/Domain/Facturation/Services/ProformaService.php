<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Services;

use App\Domain\Crm\Models\Client;
use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Models\LigneProforma;
use App\Domain\Facturation\Models\Proforma;
use App\Domain\Facturation\Support\IfuClient;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * La facture PROFORMA — création, modification, émission (numéro), annulation, conversion en facture.
 * Document NON FISCAL (PO, 07/11/2026) : ce service n'appelle JAMAIS MECeF, n'écrit aucune pièce
 * comptable et ne touche à aucun stock. docs/SPEC_FACTURE_PROFORMA.md.
 *
 * ## Le numéro
 * `N°0045 FP-GCN/2026` : rang à 4 chiffres, RÉFÉRENCE FACTURE (réglage, copiée à l'émission), année.
 * Alloué à l'ÉMISSION seulement, sous verrou, par année : un brouillon abandonné ne laisse aucun trou, une
 * annulée garde son numéro. `(annee, rang)` est unique en base — le dernier rempart.
 *
 * ## Idempotence
 * Émettre une émise, annuler une annulée, convertir une convertie : l'état existant est rendu tel quel
 * (même numéro, même facture) — le rejeu d'une synchronisation ne double rien.
 */
class ProformaService
{
    /** Le module de la LIGNE de facture selon le flux d'origine. */
    public const MODULE_LIGNE = ['libre' => 'M2', 'hebergement' => 'M1', 'evenement' => 'M4', 'location' => 'M8', 'tourisme' => 'M9'];

    public const TOTAL_MAX = 99_999_999_999;

    public function __construct(
        private readonly ReglagesDocuments $reglages,
        private readonly EmissionFactureService $emission,
    ) {
    }

    /** Le numéro imprimé : `N°0045 FP-GCN/2026`. */
    public static function formaterNumero(int $rang, string $reference, int $annee): string
    {
        return sprintf('N°%04d FP-%s/%d', $rang, $reference, $annee);
    }

    /**
     * Crée un BROUILLON (sans numéro). `$id` : l'identifiant né au poste (synchronisation).
     *
     * @param  array{client_id?: ?string, client_nom?: ?string, client_telephone?: ?string, client_ifu?: ?string, objet?: ?string, source_module?: ?string, source_id?: ?string, origine?: ?string, lignes?: list<array{designation: mixed, quantite: mixed, prix_unitaire: mixed}>}  $donnees
     */
    public function creer(array $donnees, ?string $id = null): Proforma
    {
        $lignes = $this->lignesValides($donnees['lignes'] ?? []);
        $client = $this->client($donnees);

        return DB::transaction(function () use ($donnees, $lignes, $client, $id): Proforma {
            $proforma = Proforma::create([
                ...($id !== null ? ['id' => $id] : []),
                'statut' => Proforma::BROUILLON,
                'client_id' => $client['client_id'],
                'client_nom' => $client['nom'],
                'client_telephone' => $client['telephone'],
                'client_ifu' => $client['ifu'],
                'objet' => $this->texte($donnees['objet'] ?? null, 255),
                'total' => 0,
                'source_module' => $this->flux($donnees['source_module'] ?? null),
                'source_id' => $donnees['source_id'] ?? null,
                'origine' => $donnees['origine'] ?? null,
            ]);

            $this->remplacerLignes($proforma, $lignes);

            return $proforma->refresh();
        });
    }

    /**
     * Modifie une proforma NON convertie ni annulée (client, objet, lignes). Chaque modification est
     * inscrite au journal d'audit, lignes comprises (avant / après).
     *
     * @param  array<string, mixed>  $donnees
     */
    public function modifier(Proforma $proforma, array $donnees): Proforma
    {
        return DB::transaction(function () use ($proforma, $donnees): Proforma {
            $proforma = Proforma::query()->lockForUpdate()->findOrFail($proforma->id);
            $this->exigerModifiable($proforma);

            $avant = $this->instantane($proforma);
            $champs = [];

            if (array_key_exists('client_nom', $donnees) || array_key_exists('client_id', $donnees)) {
                $client = $this->client($donnees + ['client_nom' => $proforma->client_nom]);
                $champs = [
                    'client_id' => $client['client_id'], 'client_nom' => $client['nom'],
                    'client_telephone' => $client['telephone'], 'client_ifu' => $client['ifu'],
                ];
            }
            if (array_key_exists('objet', $donnees)) {
                $champs['objet'] = $this->texte($donnees['objet'], 255);
            }

            if (array_key_exists('lignes', $donnees)) {
                $this->remplacerLignes($proforma, $this->lignesValides($donnees['lignes']));
            }

            $proforma->update($champs);
            $proforma->enregistrerAudit('modification_proforma', $avant, $this->instantane($proforma->refresh()));

            return $proforma;
        });
    }

    /**
     * Émet : attribue le numéro, la date, la ville, et la validité si le réglage est sur Oui (calculée ICI,
     * enregistrée). Idempotent. `$dateEmission` : la date du poste (synchronisation) ; sinon aujourd'hui.
     * `$validiteDuPoste` : la synchronisation fournit la validité DÉJÀ décidée au poste (`[valide_jusqu_au => ?date]`,
     * y compris `null` = pas de validité) ; le serveur ne la recalcule alors pas avec SON réglage.
     *
     * @param  array{valide_jusqu_au: ?string}|null  $validiteDuPoste
     */
    public function emettre(Proforma $proforma, ?string $dateEmission = null, ?array $validiteDuPoste = null): Proforma
    {
        return DB::transaction(function () use ($proforma, $dateEmission, $validiteDuPoste): Proforma {
            $proforma = Proforma::query()->lockForUpdate()->findOrFail($proforma->id);

            if ($proforma->numero !== null) {
                return $proforma;
            }
            $this->exigerModifiable($proforma);

            if ($proforma->lignes()->count() === 0) {
                throw new RuntimeException(__('proforma.lignes_requises'));
            }

            $date = $dateEmission === null ? Carbon::today() : Carbon::parse($dateEmission)->startOfDay();
            $annee = (int) $date->format('Y');
            $reference = $this->reglages->referenceFacture();
            $rang = $this->rangSuivant($annee);

            $proforma->update([
                'annee' => $annee,
                'rang' => $rang,
                'reference' => $reference,
                'numero' => self::formaterNumero($rang, $reference, $annee),
                'statut' => Proforma::EMISE,
                'date_emission' => $date->toDateString(),
                'ville' => $this->reglages->texte(ReglagesDocuments::CLE_VILLE_EMISSION) ?: null,
                'valide_jusqu_au' => $validiteDuPoste !== null
                    ? $validiteDuPoste['valide_jusqu_au']
                    : ($this->reglages->validiteAffichee()
                        ? $date->copy()->addDays($this->reglages->validiteJours())->toDateString()
                        : null),
            ]);

            return $proforma->refresh();
        });
    }

    /** Annule avec motif (brouillon ou émise). Idempotent ; une convertie ne s'annule pas. */
    public function annuler(Proforma $proforma, string $motif): Proforma
    {
        $motif = trim($motif);

        return DB::transaction(function () use ($proforma, $motif): Proforma {
            $proforma = Proforma::query()->lockForUpdate()->findOrFail($proforma->id);

            if ($proforma->statut === Proforma::ANNULEE) {
                return $proforma;
            }
            $this->exigerModifiable($proforma);

            if ($motif === '') {
                throw new RuntimeException(__('proforma.motif_requis'));
            }

            $proforma->update(['statut' => Proforma::ANNULEE, 'motif_annulation' => mb_substr($motif, 0, 500)]);

            return $proforma->refresh();
        });
    }

    /**
     * CONVERSION : crée une VRAIE facture par le chemin des factures du poste (`emettreVide`,
     * `ajouterLigne`, `figerEmission`) — mêmes client (+ IFU), lignes et montants. Une seule fois :
     * rejeu = la même facture. Le mode de facturation décide ensuite (jamais de normalisation ici).
     */
    public function convertir(Proforma $proforma): Facture
    {
        return DB::transaction(function () use ($proforma): Facture {
            $proforma = Proforma::query()->lockForUpdate()->findOrFail($proforma->id);

            if ($proforma->statut === Proforma::CONVERTIE && $proforma->facture_id !== null) {
                return Facture::query()->findOrFail($proforma->facture_id);
            }
            if ($proforma->statut === Proforma::ANNULEE) {
                throw new RuntimeException(__('proforma.annulee'));
            }
            if ($proforma->statut === Proforma::BROUILLON) {
                throw new RuntimeException(__('proforma.brouillon_a_convertir'));
            }

            $facture = $this->emission->emettreVide(
                $this->idClientDeFacture($proforma),
                null,
                Carbon::today()->toDateString(),
                $proforma->client_ifu,
                $proforma->client_nom,
            );
            $facture->update(['origine' => 'facture_directe', 'proforma_id' => $proforma->id]);

            $module = self::MODULE_LIGNE[$proforma->source_module] ?? 'M2';

            foreach ($proforma->lignes as $ligne) {
                $this->emission->ajouterLigne(
                    facture: $facture,
                    moduleSource: $module,
                    sourceId: (string) $proforma->id,
                    libelle: $ligne->designation,
                    quantite: (string) $ligne->quantite,
                    prixUnitaire: $ligne->prix_unitaire.'.00',
                );
            }

            $this->emission->figerEmission($facture);
            $proforma->update(['statut' => Proforma::CONVERTIE, 'facture_id' => $facture->id]);

            return $facture->refresh();
        });
    }

    /**
     * Range une conversion FAITE AU POSTE : la facture existe déjà (synchronisée sous l'identifiant du poste), le
     * serveur ne la recrée pas — il lie les deux et passe la proforma à « convertie ». Idempotent : une proforma
     * déjà liée à cette facture est rendue telle quelle ; liée à une AUTRE facture, c'est un refus (une seule conversion).
     */
    public function lier(Proforma $proforma, Facture $facture): Proforma
    {
        return DB::transaction(function () use ($proforma, $facture): Proforma {
            $proforma = Proforma::query()->lockForUpdate()->findOrFail($proforma->id);

            if ($proforma->statut === Proforma::CONVERTIE) {
                if ($proforma->facture_id === $facture->id) {
                    return $proforma;
                }
                throw new RuntimeException(__('proforma.deja_convertie'));
            }
            if ($proforma->statut === Proforma::ANNULEE) {
                throw new RuntimeException(__('proforma.annulee'));
            }
            if ($proforma->statut === Proforma::BROUILLON) {
                throw new RuntimeException(__('proforma.brouillon_a_convertir'));
            }
            if ($facture->proforma_id !== null && $facture->proforma_id !== $proforma->id) {
                throw new RuntimeException(__('proforma.deja_convertie'));
            }

            $facture->update(['proforma_id' => $proforma->id]);
            $proforma->update(['statut' => Proforma::CONVERTIE, 'facture_id' => $facture->id]);

            return $proforma->refresh();
        });
    }

    // =====================================================================

    /** Rang suivant de l'année, sous verrou pessimiste (dans la transaction appelante). */
    private function rangSuivant(int $annee): int
    {
        $dernier = DB::table('proformas')->where('annee', $annee)->lockForUpdate()->max('rang');

        return ((int) $dernier) + 1;
    }

    private function exigerModifiable(Proforma $proforma): void
    {
        if (! $proforma->estModifiable()) {
            throw new RuntimeException(__('proforma.non_modifiable', ['statut' => mb_strtolower(__('proforma.statut.'.$proforma->statut))]));
        }
    }

    /**
     * @param  array<int, mixed>  $brutes
     * @return list<array{designation: string, quantite: int, prix_unitaire: int, montant: int}>
     */
    private function lignesValides(array $brutes): array
    {
        if ($brutes === []) {
            throw new RuntimeException(__('proforma.lignes_requises'));
        }

        $lignes = [];
        $total = 0;

        foreach (array_values($brutes) as $brute) {
            $designation = $this->texte($brute['designation'] ?? null, 255);
            $quantite = $brute['quantite'] ?? null;
            $prix = $brute['prix_unitaire'] ?? null;

            if ($designation === null
                || ! (is_int($quantite) || (is_string($quantite) && ctype_digit($quantite))) || (int) $quantite < 1
                || ! (is_int($prix) || (is_string($prix) && ctype_digit($prix))) || (int) $prix < 0) {
                throw new RuntimeException(__('proforma.ligne_invalide'));
            }

            $montant = (int) $quantite * (int) $prix;
            $total += $montant;
            $lignes[] = ['designation' => $designation, 'quantite' => (int) $quantite, 'prix_unitaire' => (int) $prix, 'montant' => $montant];
        }

        if ($total > self::TOTAL_MAX) {
            throw new RuntimeException(__('proforma.montant_trop_grand'));
        }

        return $lignes;
    }

    /** @param list<array{designation: string, quantite: int, prix_unitaire: int, montant: int}> $lignes */
    private function remplacerLignes(Proforma $proforma, array $lignes): void
    {
        $proforma->lignes()->delete();

        foreach ($lignes as $position => $ligne) {
            LigneProforma::create(['proforma_id' => $proforma->id, 'position' => $position, ...$ligne]);
        }

        $proforma->update(['total' => array_sum(array_column($lignes, 'montant'))]);
    }

    /**
     * @param  array<string, mixed>  $donnees
     * @return array{client_id: ?string, nom: string, telephone: ?string, ifu: ?string}
     */
    private function client(array $donnees): array
    {
        $fiche = empty($donnees['client_id']) ? null : Client::query()->find($donnees['client_id']);
        $nom = $this->texte($donnees['client_nom'] ?? null, 150)
            ?? ($fiche === null ? null : trim(($fiche->prenom ?? '').' '.($fiche->nom ?? '')));

        if ($nom === null || $nom === '') {
            throw new RuntimeException(__('proforma.client_requis'));
        }

        $ifu = IfuClient::nettoyer($donnees['client_ifu'] ?? $fiche?->ifu);

        if (! IfuClient::valide($ifu)) {
            throw new RuntimeException(__('proforma.ifu_invalide'));
        }

        return [
            'client_id' => $fiche?->id,
            'nom' => $nom,
            'telephone' => $this->texte($donnees['client_telephone'] ?? $fiche?->telephone, 40),
            'ifu' => $ifu,
        ];
    }

    private function idClientDeFacture(Proforma $proforma): string
    {
        if ($proforma->client_id !== null && Client::query()->whereKey($proforma->client_id)->exists()) {
            return (string) $proforma->client_id;
        }

        return (string) Client::query()->firstOrCreate(
            ['nom' => 'Client de passage', 'telephone' => '-'],
            ['type_client' => 'particulier'],
        )->id;
    }

    private function flux(?string $flux): string
    {
        return array_key_exists((string) $flux, self::MODULE_LIGNE) ? (string) $flux : 'libre';
    }

    private function texte(mixed $valeur, int $max): ?string
    {
        $net = trim((string) $valeur);

        return $net === '' ? null : mb_substr($net, 0, $max);
    }

    /** @return array<string, mixed> */
    private function instantane(Proforma $proforma): array
    {
        return [
            'client_nom' => $proforma->client_nom, 'client_telephone' => $proforma->client_telephone,
            'client_ifu' => $proforma->client_ifu, 'objet' => $proforma->objet, 'total' => $proforma->total,
            'lignes' => $proforma->lignes()->get()->map(fn (LigneProforma $l): array => [
                'designation' => $l->designation, 'quantite' => $l->quantite, 'prix_unitaire' => $l->prix_unitaire,
            ])->all(),
        ];
    }
}
