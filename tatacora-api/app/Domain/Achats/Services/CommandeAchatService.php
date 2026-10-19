<?php

declare(strict_types=1);

namespace App\Domain\Achats\Services;

use App\Domain\Achats\Models\CommandeAchat;
use App\Domain\Achats\Models\LigneCommandeAchat;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Émission des commandes d'achat — EF-M7-02, UC-29.
 *
 * ## Pourquoi un Service, et pas trois lignes dans le contrôleur
 *
 * Une commande et ses lignes doivent naître ensemble ou pas du tout : une
 * commande sans ligne est réceptionnable, et sa réception serait déclarée
 * `non_conforme` pour un motif que personne ne pourrait expliquer
 * (`ReceptionService::evaluerConformite()` ne trouve aucune ligne en face).
 * La transaction est donc une règle de gestion, pas de la plomberie, et elle
 * vit ici — `06_DEVELOPMENT_STANDARDS.md` §2.2.
 *
 * ## Les statuts saisissables sont un registre FERMÉ, et il est court
 *
 * L'enum du schéma en compte cinq. Trois d'entre eux — `receptionnee`,
 * `receptionnee_partiellement`, `cloturee` — ne sont **pas** des choix de
 * saisie : ils sont produits par `ReceptionService`, c'est-à-dire par une
 * réception qui a réellement généré ses entrées de stock. Les accepter à la
 * création permettrait d'afficher une commande « Reçue » dont aucune
 * marchandise n'est jamais entrée en stock — un indicateur qui affirme un état
 * qu'il n'a pas vérifié (PA-59/60/61), et la commande sortirait au passage du
 * périmètre réceptionnable puisque `estCloturee()` la refuserait.
 *
 * Le prototype (`m7-achats.html`, formulaire « Commandes d'achat ») offre bien
 * les cinq au formulaire. C'est un écart assumé, et il est visible : le refus
 * est explicite, pas un champ silencieusement ignoré.
 *
 * ## Ce que ce service ne fait pas, et pourquoi
 *
 * - **Aucune modification de commande.** Une commande partiellement reçue dont
 *   on réécrirait les lignes rendrait le rapprochement à trois voies faux
 *   rétroactivement, sans laisser de trace de l'état précédent.
 * - **Aucune annulation.** L'enum `commandes_achat.statut` ne porte pas de
 *   valeur `annulee` (même famille que PA-50 sur `contrats_location`). Inventer
 *   un statut ici obligerait à modifier une contrainte d'intégrité — décision
 *   qui n'appartient pas à ce lot. Signalé à l'Architecte.
 *
 * @see EF-M7-02 Émission de commandes d'achat rattachées à un ou plusieurs articles
 * @see RG-15 Journalisation (trait Auditable sur CommandeAchat)
 */
class CommandeAchatService
{
    /**
     * Registre FERMÉ des statuts qu'un client peut poser lui-même.
     *
     * @var list<string>
     */
    public const STATUTS_SAISISSABLES = ['brouillon', 'envoyee'];

    /**
     * Crée une commande et ses lignes dans la même transaction.
     *
     * ## `id` optionnel — la synchronisation (15/10/2026, lot S3)
     *
     * Un poste hors connexion pose l'UUID de sa commande (décision du Product
     * Owner du 15/10/2026). Une commande qui existe déjà sous cet identifiant
     * est RENDUE telle quelle — vérifié sous verrou DANS la transaction : un
     * rejeu ne crée ni seconde commande ni second engagement fournisseur. La
     * route d'API, elle, continue d'interdire `id` (`CreerCommandeAchatRequest`).
     *
     * @param  array{
     *     id?: string,
     *     fournisseur_id: string,
     *     date_commande: string,
     *     statut?: string,
     *     lignes: list<array{article_id: string, quantite_commandee: string, prix_unitaire: string}>
     * }  $donnees
     */
    public function creer(array $donnees): CommandeAchat
    {
        return DB::transaction(function () use ($donnees): CommandeAchat {
            if (isset($donnees['id'])) {
                $existante = CommandeAchat::query()->whereKey((string) $donnees['id'])->lockForUpdate()->first();

                if ($existante !== null) {
                    return $existante->load(['lignes.article', 'fournisseur']);
                }
            }

            $commande = CommandeAchat::create([
                ...(isset($donnees['id']) ? ['id' => (string) $donnees['id']] : []),
                'fournisseur_id' => $donnees['fournisseur_id'],
                'date_commande' => $donnees['date_commande'],
                'statut' => $donnees['statut'] ?? 'brouillon',
                // L'auteur vient du jeton, jamais du corps de la requête :
                // accepter un `utilisateur_id` permettrait d'attribuer une
                // commande à quelqu'un d'autre, ce que RG-15 existe pour
                // empêcher.
                'utilisateur_id' => auth()->id(),
            ]);

            foreach ($donnees['lignes'] as $ligne) {
                LigneCommandeAchat::create([
                    'commande_id' => $commande->id,
                    'article_id' => $ligne['article_id'],
                    'quantite_commandee' => $ligne['quantite_commandee'],
                    'prix_unitaire' => $ligne['prix_unitaire'],
                ]);
            }

            $commande->load(['lignes.article', 'fournisseur']);

            // ⚠ `montant_total` n'avait AUCUN writer dans tout le dépôt
            // (relevé du 01/09/2026, en exécutant réellement le bouton
            // « Régler ») : la colonne restait à zéro, et
            // `ReglementFournisseurService::resteDu()` refusait tout
            // règlement positif comme sur-paiement. CALCULÉ des lignes par
            // l'UNIQUE formule du modèle (`montantTotal()`), écrit ici dans
            // la même transaction — le motif `recalculerTotaux()` de la
            // facturation, jamais un total saisi (règle n° 3).
            DB::table('commandes_achat')
                ->where('id', $commande->id)
                ->update(['montant_total' => $commande->montantTotal()]);

            return $commande->refresh()->load(['lignes.article', 'fournisseur']);
        });
    }

    /**
     * Émission d'une commande restée en brouillon — EF-M7-02.
     *
     * Sans ce passage, `brouillon` serait un état sans sortie : le prototype
     * l'offre au filtre de sa liste, et une commande y resterait indéfiniment.
     * Le sens unique est délibéré — revenir d'`envoyee` à `brouillon` après
     * qu'un bon est parti chez le fournisseur ne décrirait plus la réalité.
     */
    public function envoyer(CommandeAchat $commande): CommandeAchat
    {
        if ($commande->statut !== 'brouillon') {
            throw new RuntimeException(__('achats.envoi_impossible'));
        }

        $commande->update(['statut' => 'envoyee']);

        return $commande->refresh();
    }
}
