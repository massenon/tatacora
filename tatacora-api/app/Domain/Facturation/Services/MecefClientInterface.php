<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Services;

use App\Domain\Facturation\Models\Facture;

/**
 * Contrat Laravel interne de certification MECeF (MECEF_INTEGRATION_SPEC.md §6).
 *
 * L'implementation reelle sera completee avec le contrat exact une fois la
 * documentation technique DGI recue apres inscription. Cette interface fixe le
 * contrat INTERNE des maintenant, ce qui permet de developper et tester
 * EmissionFactureService sans attendre la resolution de PA-17.
 */
interface MecefClientInterface
{
    public function certifier(Facture $facture): CertificationMecefResultat;

    /**
     * Le mode reel engage juridiquement l'entreprise ; le mode demonstration
     * produit des factures SANS valeur fiscale. Toute interface et tout PDF
     * doivent pouvoir distinguer les deux (MECEF_INTEGRATION_SPEC.md §7.4).
     */
    public function estModeReel(): bool;
}
