<?php

declare(strict_types=1);

namespace Database\Seeders;

use App\Domain\Notifications\Models\ModeleNotification;
use App\Domain\Notifications\Services\ModeleNotificationService;
use Illuminate\Database\Seeder;
use RuntimeException;

/**
 * Les modèles de message de M12 — auteur UNIQUE de `modeles_notification`.
 *
 * Maître : `prototype_v2/assets/js/notifications-engine.js` l.234-276,
 * `MODELES_SOCLE` — « Modèles livrés. Le Comptable et le Gérant peuvent les
 * amender. » **10 modèles**, pas neuf : la répartition rapide du brief
 * d'audit en comptait un de moins (mesuré par relecture de la constante le
 * 02/09/2026, `grep -c "code:" assets/js/notifications-engine.js` sur les
 * lignes 234-276 — ne pas recopier ce chiffre sans le remesurer).
 *
 * ## Pourquoi ce seeder passe par `ModeleNotificationService::creerModele()`
 *
 * `modeles_notification` n'est pas une table gardée par un verrou pessimiste
 * de plage comme les réservations ou les contrats de location, mais elle EST
 * gardée par deux registres fermés (`RegistreDeclencheurs`, `RegistreCanaux`)
 * et une contrainte d'unicité `(evenement, canal)`. Écrire en `DB::table()`
 * ici contournerait la même garantie que `DatabaseSeeder` a fermée sur les
 * réservations, les contrats et les commandes d'achat le 02/09/2026 : une
 * insertion directe qui poserait un jour un code hors registre ne serait
 * détectée par personne, puisque c'est justement le service qui le refuse.
 *
 * ## Idempotent par le COUPLE (évènement, canal) — le libellé exact du maître
 *
 * `evenement` et `canal` sont des codes techniques, pas des libellés : le
 * risque « deux auteurs, deux libellés » de PA-160/PA-161 ne joue pas ici de
 * la même façon, mais la règle reste — un seul seeder écrit cette table, et
 * relancer `db:seed` ne double rien (la contrainte unique du schéma le
 * garantirait de toute façon, mais le contrôle explicite NOMME le doublon
 * plutôt que de le laisser remonter en exception SQL).
 *
 * Dév/Recette UNIQUEMENT — jamais en pipeline Production
 * (`SEEDER_TEST_LARAVEL.md`).
 *
 * @see EF-M12-01 Modèles de notification paramétrables par événement et canal
 */
class NotificationsModelesSeeder extends Seeder
{
    /**
     * Les dix modèles du maître, dans son ordre. Colonnes : évènement
     * (déclencheur), canal, actif au maître, objet (`null` pour WhatsApp —
     * le maître n'en pose aucun sur ce canal), contenu.
     *
     * @return list<array{evenement: string, canal: string, actif: bool, objet: string|null, contenu: string}>
     */
    public static function modeles(): array
    {
        return [
            [
                'evenement' => 'sejour_demain',
                'canal' => 'whatsapp',
                'actif' => true,
                'objet' => null,
                'contenu' => 'Bonjour {client}, votre séjour au Gîte Chez Noël commence demain '
                    . '{date_arrivee} pour {nuits} nuit(s), jusqu\'au {date_depart}. Nous vous '
                    . 'attendons à Natitingou. À très bientôt !',
            ],
            [
                'evenement' => 'sejour_depart',
                'canal' => 'whatsapp',
                'actif' => true,
                'objet' => null,
                'contenu' => 'Bonjour {client}, merci d\'avoir séjourné au Gîte Chez Noël. Solde '
                    . 'restant à ce jour : {reste_du}. Nous espérons vous revoir bientôt.',
            ],
            [
                'evenement' => 'creance_echue',
                'canal' => 'whatsapp',
                'actif' => true,
                'objet' => null,
                'contenu' => 'Bonjour {client}, sauf erreur de notre part, un solde de {montant} '
                    . 'reste ouvert depuis {anciennete} jours. Merci de nous indiquer la date de '
                    . 'règlement prévue. Gîte Chez Noël — Natitingou.',
            ],
            [
                'evenement' => 'creance_echue',
                'canal' => 'email',
                'actif' => false,
                'objet' => 'Solde en attente — Gîte Chez Noël',
                'contenu' => 'Madame, Monsieur {client},' . "\n\n"
                    . 'Sauf erreur de notre part, un solde de {montant} demeure ouvert depuis '
                    . '{anciennete} jours.' . "\n\n"
                    . 'Nous vous remercions de bien vouloir nous indiquer la date de règlement '
                    . 'envisagée.' . "\n\n"
                    . 'Cordialement,' . "\n" . 'Gîte Chez Noël — Natitingou',
            ],
            [
                'evenement' => 'creance_douteuse',
                'canal' => 'android',
                'actif' => true,
                'objet' => 'Créances à plus de 90 jours',
                'contenu' => '{montant} de créances dépassent 90 jours, soit {part} % du total, sur '
                    . '{nb_clients} client(s). Une provision pour dépréciation est à envisager.',
            ],
            [
                'evenement' => 'stock_sous_seuil',
                'canal' => 'android',
                'actif' => true,
                'objet' => 'Réapprovisionnement',
                'contenu' => 'Stock bas : {article} au {point}. Il reste {stock}, le seuil est de {seuil}.',
            ],
            [
                'evenement' => 'depart_circuit_demain',
                'canal' => 'whatsapp',
                'actif' => true,
                'objet' => null,
                'contenu' => 'Bonjour {client}, votre départ pour {circuit} est prévu demain {date} '
                    . 'pour {personnes} personne(s). Votre guide sera {guide}. Prévoyez de l\'eau et '
                    . 'de bonnes chaussures.',
            ],
            [
                'evenement' => 'restitution_vehicule',
                'canal' => 'whatsapp',
                'actif' => true,
                'objet' => null,
                'contenu' => 'Bonjour {client}, la restitution du véhicule {vehicule} est prévue '
                    . 'aujourd\'hui {date}. Solde à régler : {reste_du}. Merci.',
            ],
            [
                'evenement' => 'bulletin_disponible',
                'canal' => 'email',
                'actif' => true,
                'objet' => 'Votre bulletin de paie — {periode}',
                'contenu' => 'Bonjour {employe},' . "\n\n"
                    . 'Votre bulletin de paie de {periode} est disponible. Net à payer : {net}.'
                    . "\n\n" . 'Service Ressources humaines' . "\n" . 'Gîte Chez Noël',
            ],
            [
                'evenement' => 'echeance_vps',
                'canal' => 'android',
                'actif' => true,
                'objet' => 'Échéance VPS',
                'contenu' => 'VPS de {periode} : {montant} à déclarer et payer au plus tard le {echeance}.',
            ],
        ];
    }

    public function run(): void
    {
        $service = app(ModeleNotificationService::class);

        foreach (self::modeles() as $modele) {
            $existe = ModeleNotification::query()
                ->where('evenement', $modele['evenement'])
                ->where('canal', $modele['canal'])
                ->exists();

            if ($existe) {
                continue;
            }

            try {
                $service->creerModele([
                    'evenement' => $modele['evenement'],
                    'canal' => $modele['canal'],
                    'objet' => $modele['objet'],
                    'contenu_template' => $modele['contenu'],
                    'actif' => $modele['actif'],
                ]);
            } catch (RuntimeException $refus) {
                // Message d'exploitation, jamais affiché à un utilisateur :
                // un couple déjà posé entre le contrôle ci-dessus et l'appel
                // (relance concurrente du seeder) ne doit pas faire échouer
                // `db:seed` entier pour les référentiels qui le suivent.
                report($refus);
            }
        }
    }
}
