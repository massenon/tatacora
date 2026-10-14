<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Observers;

use App\Domain\Facturation\Exceptions\FactureImmuableException;
use App\Domain\Facturation\Models\Facture;

/**
 * Immutabilité de la facture certifiée — RG-03.
 *
 * > « Une facture normalisée MECeF, une fois émise, ne peut être ni modifiée ni
 * > supprimée ; seule l'émission d'un avoir permet d'en neutraliser les effets. »
 *
 * L'Observer est le bon endroit pour cette garantie, et non le contrôleur :
 * il couvre TOUS les chemins d'écriture, y compris un `update()` appelé depuis
 * un futur service, un job de synchronisation, ou une commande artisan. Une
 * vérification placée dans le contrôleur ne protégerait que la route HTTP.
 *
 * Ce qui reste modifiable après certification : rien sur la facture elle-même.
 * La correction passe exclusivement par un avoir (`AvoirService`).
 */
class FactureObserver
{
    /**
     * Champs dont la mise à jour reste tolérée après certification, parce
     * qu'ils sont renseignés PAR la certification elle-même et non par un
     * utilisateur. Sans cette exception, la certification ne pourrait pas
     * écrire son propre résultat.
     *
     * @var list<string>
     */
    private const CHAMPS_DE_CERTIFICATION = ['numero_mecef', 'qr_code_fiscal', 'statut'];

    public function updating(Facture $facture): void
    {
        if (! $this->etaitCertifiee($facture)) {
            return;
        }

        $champsModifies = array_keys($facture->getDirty());
        $interdits = array_diff($champsModifies, self::CHAMPS_DE_CERTIFICATION, ['updated_at']);

        if ($interdits !== []) {
            throw new FactureImmuableException($facture->id, $interdits);
        }

        // Même sur les champs de certification : une facture déjà certifiée ne
        // se re-certifie pas. Autoriser un second passage permettrait d'écraser
        // un NIM réel par un NIM de démonstration.
        if (in_array('numero_mecef', $champsModifies, true)) {
            throw new FactureImmuableException($facture->id, ['numero_mecef']);
        }
    }

    public function deleting(Facture $facture): void
    {
        // Une facture ne se supprime jamais, certifiée ou non : même en
        // brouillon, sa disparition créerait un trou dans la numérotation que
        // l'administration fiscale interprète comme une facture dissimulée.
        throw new FactureImmuableException($facture->id, ['suppression']);
    }

    /**
     * On interroge l'état AVANT modification : si le statut passe de
     * `en_attente_certification` à `certifiee` dans cette même écriture, la
     * facture n'était pas encore certifiée et la mise à jour est légitime.
     */
    private function etaitCertifiee(Facture $facture): bool
    {
        return $facture->getOriginal('statut') === 'certifiee';
    }
}
