<?php

declare(strict_types=1);

namespace Database\Seeders;

use App\Domain\Achats\Models\Fournisseur;
use App\Domain\Achats\Services\ReferentielFournisseurService;
use Illuminate\Database\Seeder;
use Illuminate\Support\Str;

/**
 * Référentiel fournisseurs de démonstration — SEEDER_TEST_LARAVEL.md §6.1,
 * repris tel quel : les 6 fournisseurs du prototype, avec leurs conditions et
 * leurs évaluations (dont un « À revoir », pour que le badge rouge de l'écran
 * M7 ait quelque chose à montrer).
 *
 * ## Ce seeder est l'AUTEUR UNIQUE du référentiel fournisseurs (31/08/2026)
 *
 * `FournisseursCommandesSeeder` en semait quatre autres — trois raisons
 * sociales communes, plus « SODIS Bénin » — en `DB::table()`. C'est le second
 * auteur, et il produisait exactement le défaut corrigé le même jour sur le
 * parc d'hébergement : chacun des deux se croyait idempotent (l'un garde sur
 * `Fournisseur::exists()`, l'autre sur la raison sociale), aucun ne voyait
 * l'autre, et `DatabaseSeeder` n'appelant que le second, le référentiel de
 * démonstration comptait **4 fournisseurs pour les 6 de la spécification**.
 * Il est supprimé ; sa commande d'achat est reprise par
 * {@see \Database\Seeders\AchatsDemonstrationSeeder}, cette fois par le
 * service de domaine.
 *
 * ## Écart assumé : les coordonnées détaillées ne sont pas semées
 *
 * La migration `2026_08_28_210000_add_missing_achats_columns` a ajouté `nom`,
 * `telephone`, `email`, `ville` et `ifu` à la table, mais
 * `Fournisseur::$fillable` ne les porte pas. Les poser exigerait soit de
 * modifier le modèle, soit un `DB::table()` — qui contournerait `Auditable`,
 * donc RG-15, sur un référentiel désormais audité (PA-159). Elles se
 * renseignent par l'écran M7, qui est leur chemin réel. L'IFU en particulier
 * est un identifiant fiscal : un exemple de format semé ici serait un faux
 * (même discipline que l'en-tête des états).
 *
 * Écriture par `ReferentielFournisseurService`, le point d'entrée commun de
 * l'API et de la PWA — jamais un `DB::table()`.
 *
 * Dév/Recette UNIQUEMENT. Idempotent.
 *
 * @see EF-M7-01 Référentiel fournisseurs
 */
class FournisseurSeeder extends Seeder
{
    public function run(): void
    {
        if (Fournisseur::query()->exists()) {
            return;
        }

        $referentiel = app(ReferentielFournisseurService::class);

        $fournisseurs = [
            ['raison_sociale' => 'Grand Marché Natitingou SARL', 'contact' => 'Madame SABI', 'categorie' => 'Denrées alimentaires', 'conditions_paiement' => 'Comptant', 'evaluation' => 'excellent'],
            ['raison_sociale' => 'Bénin Boissons Distribution', 'contact' => 'Service Commercial', 'categorie' => 'Boissons', 'conditions_paiement' => '30 jours', 'evaluation' => 'bon'],
            ['raison_sociale' => 'Atacora Carburants', 'contact' => 'Station Gaz', 'categorie' => 'Carburant', 'conditions_paiement' => 'Comptant', 'evaluation' => 'bon'],
            ['raison_sociale' => 'Auto Pièces Nord-Bénin', 'contact' => 'Mr KORA', 'categorie' => 'Pièces auto', 'conditions_paiement' => '30 jours', 'evaluation' => 'moyen'],
            ['raison_sociale' => 'Coopérative Maraîchère Atacora', 'contact' => 'Madame BIO', 'categorie' => 'Denrées alimentaires', 'conditions_paiement' => 'Comptant', 'evaluation' => 'excellent'],
            ['raison_sociale' => 'Fournitures Générales Bénin', 'contact' => 'Accueil', 'categorie' => 'Fournitures', 'conditions_paiement' => '60 jours', 'evaluation' => 'a_revoir'],
        ];

        foreach ($fournisseurs as $f) {
            $referentiel->creer(array_merge(['id' => (string) Str::uuid()], $f));
        }
    }
}
