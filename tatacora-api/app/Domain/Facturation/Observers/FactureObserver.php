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
    private const CHAMPS_DE_CERTIFICATION = [
        'numero_mecef', 'qr_code_fiscal', 'statut',
        // Facturation normalisée (07/11/2026) : écrits par la normalisation elle-même.
        'normalisation_statut', 'normalisation_motif', 'normalisation_mode',
        'normalisation_compteur', 'code_mecef', 'normalisee_le',
        'emecef_uid', 'emecef_uid_le', 'emecef_prochain_essai_le',
    ];

    public function updating(Facture $facture): void
    {
        if (! $this->etaitCertifiee($facture)) {
            return;
        }

        $champsModifies = array_keys($facture->getDirty());
        $tolerees = self::CHAMPS_DE_CERTIFICATION;

        // L'ACHETEUR (IFU et nom saisis, 07/11/2026) reste complétable tant que la facture
        // n'est PAS normalisée : la facture simple attend sa normalisation. Une facture
        // normalisée est figée, acheteur compris.
        if ($facture->getOriginal('normalisation_statut') !== 'normalisee') {
            $tolerees = [...$tolerees, 'acheteur_ifu', 'acheteur_nom'];
        }

        // `date_modification` et `utilisateur_modification_id` : le bornage d'audit que `Auditable`
        // pose à CHAQUE mise à jour. Sans eux, toute écriture sur une facture figée est refusée dès
        // que l'horloge a avancé (les tests figeaient l'heure : le défaut ne se voyait pas, et une
        // facture SIMPLE, figée à l'émission, n'aurait jamais pu être normalisée ensuite).
        $interdits = array_diff($champsModifies, $tolerees, ['updated_at', 'date_modification', 'utilisateur_modification_id']);

        if ($interdits !== []) {
            throw new FactureImmuableException($facture->id, $interdits);
        }

        // Même sur les champs de certification : une facture déjà certifiée ne
        // se re-certifie pas. Autoriser un second passage permettrait d'écraser
        // un NIM réel par un NIM de démonstration.
        //
        // Une seule exception, et dans le SENS qui ne trompe personne : un numéro de
        // DÉMONSTRATION (`MECEF-DEMO-`, sans valeur fiscale) peut être remplacé par
        // une vraie normalisation — le mode a changé depuis. Jamais l'inverse, et
        // jamais un numéro réel remplacé.
        if (in_array('numero_mecef', $champsModifies, true)) {
            // Sans numéro (facture SIMPLE, 07/11/2026) ou de démonstration (sans valeur fiscale) :
            // seule une vraie normalisation prend la place.
            $avant = (string) $facture->getOriginal('numero_mecef');
            $etaitDemo = $avant === '' || str_starts_with($avant, 'MECEF-DEMO-');
            // « Réel » = écrit PAR une normalisation (statut posé dans la même écriture) et de la
            // forme « NIM-compteur » : une valeur quelconque ne remplace jamais une démonstration.
            $devientReel = $facture->normalisation_statut === 'normalisee'
                && in_array('normalisation_statut', $champsModifies, true)
                && preg_match('/^[A-Za-z0-9]+-[0-9]+$/', (string) $facture->numero_mecef) === 1;

            if (! ($etaitDemo && $devientReel)) {
                throw new FactureImmuableException($facture->id, ['numero_mecef']);
            }
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
