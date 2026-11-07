<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Services;

use App\Shared\Parametres\Services\ApparenceEtablissementService;

/**
 * Le bloc signature des documents A4 (factures et proformas) — décision du PO du 07/11/2026.
 *
 * Interrupteur « Afficher la signature et le cachet sur les factures » : Non = `null`, le bloc
 * n'apparaît pas (ni nom ni images). Oui sans image déposée = nom et fonction seulement. Le ticket
 * n'appelle jamais ce service. Le poste applique la MÊME règle (`bloc_signature.dart`).
 */
class BlocSignature
{
    public function __construct(
        private readonly ReglagesDocuments $reglages,
        private readonly ApparenceEtablissementService $apparence,
    ) {
    }

    /**
     * @return array{nom: string, fonction: string, signature: ?string, cachet: ?string}|null
     */
    public function donnees(): ?array
    {
        if (! $this->reglages->signatureAffichee()) {
            return null;
        }

        return [
            'nom' => $this->reglages->texte(ReglagesDocuments::CLE_SIGNATAIRE_NOM),
            'fonction' => $this->reglages->texte(ReglagesDocuments::CLE_SIGNATAIRE_FONCTION),
            'signature' => $this->apparence->dataUriImageDocument('signature'),
            'cachet' => $this->apparence->dataUriImageDocument('cachet'),
        ];
    }
}
