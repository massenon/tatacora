<?php

declare(strict_types=1);

namespace App\Domain\Achats\Services;

use App\Domain\Achats\Models\CommandeAchat;
use App\Domain\Achats\Models\Fournisseur;
use Illuminate\Support\Collection;
use RuntimeException;

/**
 * Référentiel fournisseurs — création, modification, ARCHIVAGE (M7, EF-M7-01).
 *
 * Extrait de `FournisseurController` (PA-159, lot 0b) : `LARAVEL_PWA.md` §3
 * impose qu'un composant Livewire appelle un Service de domaine — ce service
 * est le point d'entrée commun de l'API et de la PWA, et remplace l'Eloquent
 * nu que la première écriture PWA (`Achats.php`) avait introduit.
 *
 * ## L'archivage, et l'arbitrage qu'il tranche (03/09/2026)
 *
 * ⚠ Ce bloc disait, du 28/08/2026 au 03/09/2026 : « `fournisseurs` n'a aucune
 * colonne `actif` et aucune route `DELETE` n'existe […] l'arbitrage (ajouter
 * la colonne) appartient à l'Architecte ». C'était vrai à l'écriture et ça ne
 * l'est plus : la demande du Product Owner du 03/09/2026 (« mettre le bouton
 * Supprimer sur chaque table ») EST cet arbitrage, et la colonne est arrivée
 * par `2026_09_08_100000_ajouter_archivage_aux_referentiels`. Corrigé du même
 * geste plutôt que laissé à vieillir : un motif de refus périmé transforme une
 * décision en oubli (PA-144).
 *
 * **Supprimer = archiver** : `archiver()` pose `actif = false`, jamais un
 * `delete()` — `BasePolicy::delete()` rend `false` pour les 20 policies, et
 * effacer un fournisseur rendrait illisible chaque commande qui le cite
 * (`commandes_achat.fournisseur_id` est `restrictOnDelete`). Le geste est
 * réversible par `restaurer()`.
 *
 * @see EF-M7-01 Référentiel fournisseurs
 * @see RG-15 Journalisation (trait Auditable sur Fournisseur)
 */
class ReferentielFournisseurService
{
    /**
     * Les commandes qui ENGAGENT le fournisseur — le verrou du maître : un
     * élément engagé ailleurs ne s'archive pas.
     *
     * Une commande RÉCEPTIONNÉE ou CLÔTURÉE n'engage plus rien : elle est
     * derrière nous, et elle reste lisible puisque rien n'est effacé. Ce qui
     * engage, c'est ce qui reste à faire — un brouillon, une commande envoyée,
     * une réception partielle. Archiver sous une commande en cours ferait
     * disparaître le fournisseur du sélecteur au moment même où la réception
     * doit être saisie.
     *
     * @return Collection<int, CommandeAchat>
     */
    public function engagements(Fournisseur $fournisseur): Collection
    {
        return CommandeAchat::query()
            ->where('fournisseur_id', $fournisseur->id)
            ->whereNotIn('statut', ['receptionnee', 'cloturee'])
            ->orderBy('date_commande')
            ->get();
    }

    /**
     * Archive le fournisseur — `actif = false`, jamais un `delete()`.
     *
     * @throws RuntimeException le fournisseur porte une commande en cours
     */
    public function archiver(Fournisseur $fournisseur): void
    {
        // Recontrôlé au moment d'AGIR, pas seulement à l'affichage : entre
        // l'ouverture de la modale et le clic, une commande a pu naître.
        // Preuve par mutation (03/09/2026) : ce bloc retiré, le cas
        // `un_fournisseur_engage_est_refuse_et_reste_intact` d'`ArchivageReferentielsPwaTest` passe au
        // ROUGE — la garde mord.
        $engagements = $this->engagements($fournisseur);

        if ($engagements->isNotEmpty()) {
            throw new RuntimeException(__('achats_pwa.archivage.verrou', [
                'nombre' => $engagements->count(),
            ]));
        }

        // `forceFill` et non `update` : `actif` est délibérément HORS de
        // `$fillable` — ce service est le seul chemin d'archivage, et un
        // formulaire qui recevrait la clé par erreur ne doit pas pouvoir
        // retirer un fournisseur du référentiel sans passer par ce verrou.
        $fournisseur->forceFill(['actif' => false])->save();
    }

    /**
     * Le pendant de l'archivage — sans lui, « reste restaurable » serait une
     * promesse que rien ne tient (PA-59/60/61).
     */
    public function restaurer(Fournisseur $fournisseur): void
    {
        if ((bool) $fournisseur->actif) {
            return;
        }

        $fournisseur->forceFill(['actif' => true])->save();
    }

    /**
     * @param  array<string, mixed>  $donnees données validées par
     *                                        `EnregistrerFournisseurRequest` ou les règles qui en dérivent
     */
    public function creer(array $donnees): Fournisseur
    {
        return Fournisseur::create($donnees);
    }

    /**
     * @param  array<string, mixed>  $donnees
     */
    public function modifier(Fournisseur $fournisseur, array $donnees): Fournisseur
    {
        $fournisseur->update($donnees);

        return $fournisseur->refresh();
    }
}
