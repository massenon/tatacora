<?php

declare(strict_types=1);

namespace App\Shared\Audit\Traits;

use App\Shared\Audit\Models\JournalAudit;

/**
 * Traçabilité intégrale des actions sensibles — RG-15.
 *
 * Deux responsabilités distinctes, volontairement portées par le même trait
 * pour qu'un modèle ne puisse pas hériter de l'une sans l'autre :
 *
 *  1. Renseigner les colonnes d'audit de la table elle-même
 *     (utilisateur_creation_id, date_creation, utilisateur_modification_id,
 *     date_modification) — 03_DATABASE_ENGINEERING.md §15.
 *  2. Écrire une entrée `journal_audit` à chaque sauvegarde, avec les valeurs
 *     avant/après — c'est ce qui permet de répondre à « qui a changé quoi,
 *     quand » sans reconstituer l'historique a posteriori.
 *
 * Appliqué aux modèles transactionnels depuis le Sprint 0, et aux quinze
 * référentiels (articles, cartes, parc, circuits, plannings…) depuis le
 * 28/08/2026 (PA-159, migration `2026_08_28_000001_ajouter_audit_referentiels`).
 * La liste à jour se mesure : `grep -rl "use Auditable;" app/` — ne pas la
 * recopier ici, elle vieillirait (PA-144).
 *
 * @property string|null $utilisateur_creation_id
 * @property \Illuminate\Support\Carbon|null $date_creation
 * @property string|null $utilisateur_modification_id
 * @property \Illuminate\Support\Carbon|null $date_modification
 *
 * @mixin \Illuminate\Database\Eloquent\Model
 */
trait Auditable
{
    public static function bootAuditable(): void
    {
        // `self` dans un trait se resout en la classe utilisatrice : les
        // fermetures voient donc Reservation/Facture, pas un Model generique.
        static::creating(function (self $modele): void {
            $modele->utilisateur_creation_id ??= auth()->id();
            $modele->date_creation ??= now();
        });

        static::updating(function (self $modele): void {
            $modele->utilisateur_modification_id = auth()->id();
            $modele->date_modification = now();
        });

        static::created(function (self $modele): void {
            $modele->enregistrerAudit('creation', null, $modele->getAttributes());
        });

        static::updated(function (self $modele): void {
            // getOriginal() ne renvoie que l'état d'avant sur les attributs modifiés :
            // journaliser l'objet entier noierait le changement réel dans le bruit.
            $modifies = array_keys($modele->getChanges());

            $avant = [];
            foreach ($modifies as $attribut) {
                $avant[$attribut] = $modele->getOriginal($attribut);
            }

            $modele->enregistrerAudit('modification', $avant, $modele->getChanges());
        });

        static::deleted(function (self $modele): void {
            // Aucune suppression n'est attendue sur les tables sensibles
            // (03_DATABASE_ENGINEERING.md §15) — si l'événement survient malgré
            // tout, il doit laisser une trace plutôt que de passer inaperçu.
            $modele->enregistrerAudit('suppression', $modele->getOriginal(), null);
        });
    }

    /**
     * @param  array<string, mixed>|null  $avant
     * @param  array<string, mixed>|null  $apres
     */
    public function enregistrerAudit(string $action, ?array $avant, ?array $apres): void
    {
        JournalAudit::create([
            'utilisateur_id' => auth()->id(),
            'action' => $action,
            'entite_concernee' => $this->getTable(),
            'entite_id' => $this->getKey(),
            'valeur_avant' => $avant === null ? null : $this->masquerChampsSensibles($avant),
            'valeur_apres' => $apres === null ? null : $this->masquerChampsSensibles($apres),
            'adresse_poste' => request()->ip(),
        ]);
    }

    /**
     * Un hash de mot de passe n'a rien à faire en clair dans un journal
     * consultable — le journal d'audit ne doit pas devenir une seconde
     * surface d'exposition des secrets.
     *
     * @param  array<string, mixed>  $valeurs
     * @return array<string, mixed>
     */
    private function masquerChampsSensibles(array $valeurs): array
    {
        foreach (['mot_de_passe_hash', 'password', 'remember_token'] as $champ) {
            if (array_key_exists($champ, $valeurs)) {
                $valeurs[$champ] = '***';
            }
        }

        return $valeurs;
    }
}
