<?php

declare(strict_types=1);

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

/**
 * Effectif RÉEL du Gîte Chez Noël — auteur unique du référentiel personnel.
 *
 * Source : `prototype_v2/assets/js/seed-personnel.js` l.23-56 — dix employés,
 * avec leurs postes, leurs services, leurs dates d'embauche, leurs salaires et
 * leurs numéros CNSS.
 *
 * ## Ce qui a été complété le 03/09/2026
 *
 * Le seeder posait déjà les dix fiches, mais laissait trois colonnes du schéma
 * vides alors que le maître en porte la donnée :
 *
 * - **`type_contrat`** — neuf CDI et un CDD. Sans lui, la fiche de Rachidatou
 *   BIO ne se distinguait pas des autres, alors que c'est la seule dont le
 *   contrat a un terme ;
 * - **`date_fin_contrat`** — le 31/12/2026 pour ce CDD, et NULL pour les neuf
 *   CDI. Une échéance de contrat qu'aucune colonne ne porte est une échéance
 *   que personne ne verra passer ;
 * - **`matricule`** — unique au schéma, jamais renseigné. Il est dérivé du
 *   rang d'entrée dans la liste (`EMP-001`…), et c'est une CONVENTION
 *   d'amorçage, pas un matricule relevé : le dossier n'en porte aucun.
 *
 * ## Un employé est volontairement SANS numéro CNSS
 *
 * C'est le cas réel d'une embauche antérieure à l'immatriculation (le maître
 * le nomme, l.48-49) : l'écran doit le signaler sans empêcher le calcul du
 * bulletin. Ne pas « compléter » cette ligne.
 *
 * ## Trois données du maître n'ont AUCUNE colonne, et ne sont pas semées
 *
 * `sexe`, `telephone` et `centre` (centre de coût analytique) n'existent pas
 * sur `employes`. Elles étaient passées à l'insertion et silencieusement
 * filtrées par `array_intersect_key` — un filtrage qui ne dit rien est
 * exactement ce qui fait croire qu'une donnée est en base. Elles sont retirées
 * de la charge utile et l'absence est écrite ici.
 *
 * ⚠ Aucun salaire n'approche le plafond ITS confirmé de 500 000 F : le refus
 * de haut de barème (PA-53) ne bloque personne aujourd'hui, et se déclenchera
 * au premier recrutement de cadre. C'est l'état réel, pas un contournement.
 *
 * Dév/Recette UNIQUEMENT. Idempotent — la clé naturelle est le couple
 * (nom, prénom), jamais un compteur.
 *
 * @see EF-M13-01 Référentiel du personnel
 */
class PersonnelSeeder extends Seeder
{
    /** Les six services du gîte — l'organigramme du maître. */
    public const SERVICES = ['Hébergement', 'Restauration', 'Bar', 'Tourisme', 'Véhicules', 'Administration'];

    /**
     * L'équipe du maître, dans son ordre.
     *
     * Colonnes : nom, prénom, poste, service, date d'embauche, salaire de
     * base, numéro CNSS (null = non immatriculé), type de contrat, fin de
     * contrat (null pour un CDI).
     *
     * @return list<array{string, string, string, string, string, string, string|null, string, string|null}>
     */
    public static function equipe(): array
    {
        return [
            ['KORA', 'Jean-Baptiste', 'Réceptionniste', 'Hébergement', '2023-03-15', '95000', 'BJ-CNSS-0088412', 'CDI', null],
            ['DOSSOU', 'Marie-Chantal', 'Cheffe de cuisine', 'Restauration', '2022-11-02', '130000', 'BJ-CNSS-0077205', 'CDI', null],
            ['ADJOVI', 'Paul', 'Chauffeur-guide', 'Tourisme', '2023-06-01', '120000', 'BJ-CNSS-0091133', 'CDI', null],
            ['TCHAKPE', 'Sylvie', 'Serveuse', 'Restauration', '2024-01-08', '72000', 'BJ-CNSS-0102874', 'CDI', null],
            ['YAROU', 'Ibrahim', 'Barman', 'Bar', '2024-02-19', '78000', 'BJ-CNSS-0104512', 'CDI', null],
            ['SAMBIENI', 'Bertille', 'Femme de chambre', 'Hébergement', '2024-05-06', '62000', 'BJ-CNSS-0110983', 'CDI', null],
            ['N’TCHA', 'Célestin', 'Agent d’entretien et jardinier', 'Administration', '2023-09-11', '58000', 'BJ-CNSS-0095640', 'CDI', null],
            // Embauchée récemment : immatriculation CNSS non encore obtenue,
            // et seul contrat à terme de l'équipe.
            ['BIO', 'Rachidatou', 'Aide-cuisinière', 'Restauration', '2026-04-01', '55000', null, 'CDD', '2026-12-31'],
            ['GNANSOUNOU', 'Éric', 'Mécanicien', 'Véhicules', '2023-12-04', '88000', 'BJ-CNSS-0098771', 'CDI', null],
            ['ASSOGBA', 'Nadège', 'Comptable', 'Administration', '2022-08-16', '145000', 'BJ-CNSS-0071408', 'CDI', null],
        ];
    }

    public function run(): void
    {
        if (! Schema::hasTable('services') || ! Schema::hasTable('employes')) {
            return;
        }

        foreach (self::SERVICES as $libelle) {
            if (DB::table('services')->where('libelle', $libelle)->doesntExist()) {
                DB::table('services')->insert([
                    'id' => (string) Str::uuid(),
                    'libelle' => $libelle,
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);
            }
        }

        $colonnes = Schema::getColumnListing('employes');
        /** @var array<string, string> $services */
        $services = DB::table('services')->pluck('id', 'libelle')->all();

        foreach (self::equipe() as $rang => [$nom, $prenom, $poste, $service, $embauche, $salaire, $cnss, $contrat, $finContrat]) {
            $existant = DB::table('employes')
                ->where('nom', $nom)->where('prenom', $prenom)->first();

            $donnees = [
                // Convention d'amorçage, pas un matricule relevé : la colonne
                // est unique au schéma et le dossier n'en porte aucun.
                'matricule' => sprintf('EMP-%03d', $rang + 1),
                'nom' => $nom,
                'prenom' => $prenom,
                'poste' => $poste,
                'service_id' => $services[$service],
                'date_embauche' => $embauche,
                'salaire_base' => $salaire,
                'numero_cnss' => $cnss,
                'type_contrat' => $contrat,
                'date_fin_contrat' => $finContrat,
                'statut' => 'actif',
                'updated_at' => now(),
            ];

            $donnees = array_intersect_key($donnees, array_flip($colonnes));

            if ($existant === null) {
                $donnees['id'] = (string) Str::uuid();
                $donnees['created_at'] = now();
                DB::table('employes')->insert($donnees);

                continue;
            }

            DB::table('employes')->where('id', $existant->id)->update($donnees);
        }
    }
}
