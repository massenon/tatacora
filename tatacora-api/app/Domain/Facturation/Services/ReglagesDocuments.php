<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Services;

use App\Shared\Parametres\Services\ParametreSystemeService;

/**
 * Réglages des documents commerciaux (factures A4 et proformas) — décisions du PO du 07/11/2026.
 *
 * Source UNIQUE de lecture : activités, page Facebook, ville d'émission, RÉFÉRENCE FACTURE
 * (le « GCN » de `N°0045 FP-GCN/2026`), signataire, interrupteurs de signature et de validité.
 * Les valeurs vivent dans `parametres_systeme` (registre `RegistreParametres`) et descendent aux
 * postes en lecture comme tout paramètre ; l'écran Paramètres > Identité & Légal les édite.
 *
 * Aucune valeur n'est inventée : un texte vide reste vide (la ligne n'est pas imprimée), seuls la
 * référence (GCN), la durée (30 jours) et les interrupteurs (Non) ont un défaut.
 */
class ReglagesDocuments
{
    public const CLE_ACTIVITES = 'entreprise_activites';

    public const CLE_FACEBOOK = 'entreprise_facebook';

    public const CLE_VILLE_EMISSION = 'entreprise_ville_emission';

    public const CLE_REFERENCE_FACTURE = 'facture_reference';

    public const CLE_SIGNATAIRE_NOM = 'signataire_nom';

    public const CLE_SIGNATAIRE_FONCTION = 'signataire_fonction';

    public const CLE_SIGNATURE_AFFICHEE = 'facture_signature_affichee';

    public const CLE_VALIDITE_AFFICHEE = 'proforma_validite_affichee';

    public const CLE_VALIDITE_JOURS = 'proforma_validite_jours';

    /**
     * Les neuf clés : réglées par Paramètres > Identité & Légal (droit `PARAM`), au web ET, depuis le
     * 09/11/2026, sur un poste (décision du PO : « le poste fait ce que le web fait ») ; elles
     * descendent aux autres postes comme tout paramètre.
     *
     * @var list<string>
     */
    public const CLES = [
        self::CLE_ACTIVITES, self::CLE_FACEBOOK, self::CLE_VILLE_EMISSION, self::CLE_REFERENCE_FACTURE,
        self::CLE_SIGNATAIRE_NOM, self::CLE_SIGNATAIRE_FONCTION, self::CLE_SIGNATURE_AFFICHEE,
        self::CLE_VALIDITE_AFFICHEE, self::CLE_VALIDITE_JOURS,
    ];

    public const REFERENCE_PAR_DEFAUT = 'GCN';

    public const VALIDITE_PAR_DEFAUT = 30;

    public function __construct(private readonly ParametreSystemeService $lecture)
    {
    }

    public function texte(string $cle): string
    {
        return trim((string) ($this->lecture->get($cle) ?? ''));
    }

    /** La référence facture : lettres et chiffres, majuscules ; `GCN` tant qu'elle est vide. */
    public function referenceFacture(): string
    {
        $reference = strtoupper($this->texte(self::CLE_REFERENCE_FACTURE));

        return $reference === '' ? self::REFERENCE_PAR_DEFAUT : $reference;
    }

    public function signatureAffichee(): bool
    {
        return $this->booleen(self::CLE_SIGNATURE_AFFICHEE);
    }

    public function validiteAffichee(): bool
    {
        return $this->booleen(self::CLE_VALIDITE_AFFICHEE);
    }

    public function validiteJours(): int
    {
        $valeur = $this->texte(self::CLE_VALIDITE_JOURS);

        return ctype_digit($valeur) && (int) $valeur > 0 ? (int) $valeur : self::VALIDITE_PAR_DEFAUT;
    }

    private function booleen(string $cle): bool
    {
        return filter_var($this->texte($cle), FILTER_VALIDATE_BOOLEAN);
    }
}
