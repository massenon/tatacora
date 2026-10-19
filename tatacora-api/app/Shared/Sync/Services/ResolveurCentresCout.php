<?php

declare(strict_types=1);

namespace App\Shared\Sync\Services;

use App\Domain\Comptabilite\Models\CentreCout;
use App\Shared\Sync\Support\CleNaturelle;

/**
 * Retrouve le centre de coût SERVEUR désigné par un poste — décision du
 * Product Owner du 15/10/2026.
 *
 * ## Pourquoi pas une création synchronisée
 *
 * Les sept centres de coût sont SEMÉS par le serveur
 * (`ComptabiliteReferentielSeeder`) et INSTALLÉS à l'identique par le poste
 * (`installerReferentielComptable`) — mêmes libellés, mais UUID tirés sur
 * chaque poste. Un poste ne crée jamais de centre : en accepter un ferait
 * naître un huitième axe analytique (RG-12) par une saisie de comptoir.
 * `centres_cout` n'est donc PAS au registre ; le poste reçoit les UUID
 * serveur par le flux descendant, et ce résolveur traduit ce qui arrive
 * avant cet alignement (documents S3 citant un UUID local).
 *
 * ## Ordre de résolution
 *
 * 1. l'UUID cité existe côté serveur → lui (cas nominal après
 *    téléchargement) ;
 * 2. sinon le libellé, normalisé comme toutes les clés naturelles
 *    (`CleNaturelle`) ;
 * 3. sinon `null` — l'appelant REFUSE le document plutôt que d'imputer un
 *    centre deviné : une écriture sur le mauvais centre fausse l'analytique
 *    sans que rien ne le signale.
 */
class ResolveurCentresCout
{
    public function resoudre(?string $id, ?string $libelle): ?string
    {
        if ($id !== null && $id !== '' && CentreCout::query()->whereKey($id)->exists()) {
            return $id;
        }

        if ($libelle === null || trim($libelle) === '') {
            return null;
        }

        $cle = CleNaturelle::normaliser($libelle);

        $centre = CentreCout::query()
            ->orderBy('created_at')
            ->orderBy('id')
            ->get(['id', 'libelle'])
            ->first(static fn (CentreCout $c): bool => CleNaturelle::normaliser($c->libelle) === $cle);

        return $centre?->id;
    }
}
