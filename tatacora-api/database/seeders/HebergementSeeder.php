<?php

declare(strict_types=1);

namespace Database\Seeders;

use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\UniteHebergement;
use Illuminate\Database\Seeder;
use Illuminate\Support\Str;

/**
 * Parc d'hébergement RÉEL du Gîte Chez Noël — auteur unique.
 *
 * ## Ce qui a changé le 03/09/2026 : le catalogue commercial fait foi
 *
 * Ce seeder posait trois catégories génériques (« Bungalow », « Chambre »,
 * « Tente ») et six unités numérotées `BNG-01`, `CH-101`, `TNT-01`… tirées de
 * `SEEDER_TEST_LARAVEL.md` §4. Le parc réel est celui du catalogue commercial
 * imprimé, transcrit en `prototype_v2/assets/js/referentiel-tatacora.js`
 * l.55-123 : **six unités, chacune portant le nom d'un oiseau de l'Atacora**,
 * avec leurs types et leurs tarifs par nuit affichés au client.
 *
 * ⚠ Ce fichier du maître s'annonce lui-même comme « une SOURCE DE VÉRITÉ
 * COMMERCIALE, pas un jeu de démo » : les tarifs ci-dessous sont ceux
 * réellement opposables au client, et ne se modifient que sur présentation
 * d'un catalogue plus récent.
 *
 * ## Une catégorie par type, parce que le tarif vit sur la catégorie
 *
 * `categories_hebergement` porte `tarif_base` et `capacite_max` ; les six
 * unités du catalogue ont six couples (type, tarif) distincts — de 50 000 F la
 * nuit pour le bungalow double communicant à 5 000 F pour les tentes. Trois
 * catégories génériques auraient donc écrasé quatre tarifs sur six.
 *
 * ## Trois écarts au catalogue, NOMMÉS
 *
 * 1. ~~Le demi-bungalow du Calao n'est pas porté.~~ **TRANCHÉ le 01/09/2026
 *    par le Product Owner, en deux temps** : (a) le « demi-bungalow » n'a
 *    jamais existé — le second hébergement de type Bungalow est un bâtiment
 *    INDÉPENDANT, la question RG-01 tombe ; (b) il ne se SEED PAS — les
 *    catégories sont génériques (« Bungalow », « Chambre simple »,
 *    « Suite »…, le détail vit sur l'hébergement), et les hébergements
 *    supplémentaires se créent À L'ÉCRAN (« + Ajouter hébergement », qui
 *    sait désormais créer la catégorie avec son tarif réel). Aucun tarif de
 *    Suite ou de Chambre simple n'existe au catalogue : les seeder aurait
 *    inventé des prix opposables.
 * 2. **Les trois libellés « X ou Y » ne sont pas scindés.** « Amarante du
 *    Sénégal ou Coucal du Sénégal » suggère deux chambres jumelles ; la
 *    transcription en déclare UNE ligne, et son en-tête annonce « 6 unités +
 *    camping » sans lever l'ambiguïté. Les scinder créerait des chambres
 *    réservables dont personne ne sait si elles existent — même discipline que
 *    « Vody / Loco » au bar (depuis scindés, eux, sur décision PO du
 *    01/09/2026 — leur existence séparée a été confirmée, pas devinée).
 * 3. **Les statuts sont des états de DÉMARRAGE**, pas un relevé : le catalogue
 *    n'en porte aucun. Ils ouvrent la démonstration sur un parc vivant (une
 *    unité réservée, une en nettoyage), et `SejourService` les fait évoluer
 *    par ses trois gestes ensuite. ⚠ `statut` est l'état OPÉRATIONNEL — jamais
 *    la source de la disponibilité, qui vient des réservations (RG-02).
 *
 * Sans ce seeder, un environnement de développement reproduit PA-128 côté
 * serveur : « le parc n'a pas encore été renseigné », état honnête dont aucun
 * chemin d'interface ne permettait de sortir.
 *
 * Dév/Recette UNIQUEMENT. Idempotent : relancer `db:seed` ne crée pas un
 * second parc — six chambres dédoublées feraient apparaître libre une unité
 * déjà prise (PA-160).
 *
 * @see EF-M1-01 Référentiel du parc d'hébergement
 */
class HebergementSeeder extends Seeder
{
    /**
     * L'unité qui porte les trois séjours du registre M1, et celle qui porte
     * le séjour du jour.
     *
     * Nommées ici plutôt que recopiées dans les deux seeders d'exploitation :
     * un numéro d'unité écrit à trois endroits finit par diverger, et un
     * séjour posé sur une unité absente lève au milieu d'un `db:seed`.
     */
    public const UNITE_REGISTRE = 'Amarante du Sénégal ou Coucal du Sénégal';

    public const UNITE_SEJOUR_DU_JOUR = 'Diadiac Africain ou Perruche à Collier';

    /**
     * Le parc du catalogue — `referentiel-tatacora.js` l.55-123.
     *
     * Colonnes : nom de l'unité (catalogue), type (= libellé de catégorie),
     * capacité, tarif par nuit, statut opérationnel de démarrage, page du
     * catalogue.
     *
     * @return list<array{string, string, int, string, string, int}>
     */
    public static function parc(): array
    {
        return [
            // Catégorie « Bungalow » TOUT COURT — précision du PO du
            // 01/09/2026 : les catégories sont génériques (Bungalow, Chambre
            // simple, Suite…), le détail vit sur l'hébergement.
            ['Calao à Bec Rouge', 'Bungalow', 4, '50000', 'libre', 11],
            ['La Chouette, le Studio', 'Studio', 2, '40000', 'occupee', 12],
            [self::UNITE_REGISTRE, 'Chambre triple', 3, '30000', 'libre', 13],
            [self::UNITE_SEJOUR_DU_JOUR, 'Chambre twin', 2, '22000', 'reservee', 9],
            ["Rollier d'Abyssinie ou Bulbul des Jardins", 'Chambre double', 2, '12000', 'libre', 14],
            // « à partir de 5 000 » au catalogue : il ne donne aucune grille
            // détaillée pour les tentes, et une grille inventée deviendrait un
            // tarif opposable au client.
            ['Les Tentes', 'Camping aménagé', 3, '5000', 'nettoyage', 15],
        ];
    }

    public function run(): void
    {
        if (CategorieHebergement::query()->exists()) {
            return;
        }

        foreach (self::parc() as [$nom, $type, $capacite, $tarif, $statut]) {
            $categorie = CategorieHebergement::create([
                'id' => (string) Str::uuid(),
                'libelle' => $type,
                'capacite_max' => $capacite,
                'tarif_base' => $tarif,
            ]);

            UniteHebergement::create([
                'id' => (string) Str::uuid(),
                'categorie_id' => $categorie->id,
                // Le nom du catalogue, pas un code : c'est celui que le client
                // lit sur sa confirmation, et celui que la réception emploie.
                'numero' => $nom,
                // État OPÉRATIONNEL uniquement — jamais la source de la
                // disponibilité, qui vient des réservations (RG-02).
                'statut' => $statut,
            ]);
        }
    }
}
