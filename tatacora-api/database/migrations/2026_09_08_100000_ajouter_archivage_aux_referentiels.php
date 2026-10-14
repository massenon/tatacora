<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * L'ARCHIVE des trois référentiels que le Gîte manipule tous les jours —
 * clients (M3), fournisseurs (M7), articles (M6).
 *
 * ## Pourquoi une colonne, alors que le dépôt évite les migrations
 *
 * « Supprimer = archiver » suppose un état où l'élément CESSE d'être proposé
 * sans rien effacer. Trois référentiels du schéma le portaient déjà et ont
 * livré leur geste : `unites_hebergement.statut = hors_service`
 * (`ParcHebergementService`), `vehicules.statut = hors_service`
 * (`ParcVehiculeService`), `employes.statut = parti` (`EmployeService`). Les
 * trois tables d'ici n'ont AUCUNE colonne de cette nature — et le docblock de
 * `ReferentielFournisseurService` l'écrivait noir sur blanc depuis le
 * 28/08/2026 : « `fournisseurs` n'a aucune colonne `actif` […] l'arbitrage
 * (ajouter la colonne) appartient à l'Architecte ». La demande du Product
 * Owner du 03/09/2026 (« mettre le bouton Supprimer sur chaque table ») EST
 * cet arbitrage : la colonne arrive, et le docblock est corrigé du même geste
 * plutôt que laissé à vieillir (PA-144).
 *
 * ## `actif`, et pas `archive_le`
 *
 * C'est la convention DÉJÀ posée par ce schéma : `tables_salle.actif`,
 * `canaux_reservation.actif`, `modeles_notification.actif`. Un second
 * vocabulaire d'archive (`archive_le`, `date_archivage`…) obligerait chaque
 * lecteur à savoir laquelle des deux formes s'applique à la table qu'il a
 * sous les yeux.
 *
 * ## Additive, et sans effet sur une donnée existante
 *
 * `default(true)` : chaque ligne déjà en base reste active, et tout code qui
 * ne connaît pas la colonne continue de fonctionner à l'identique. Le seul
 * changement visible arrive avec les écrans qui filtrent — livrés dans le
 * même lot, jamais après : une colonne que personne n'écrit ni ne lit serait
 * PA-126.
 *
 * ⚠ AUCUNE table financière n'est touchée. `factures`, `lignes_facture`,
 * `avoirs`, `paiements`, `ecritures_comptables`, `ventes`, `lignes_vente`,
 * `depenses`, `lignes_depense`, `mouvements_stock`, `bulletins_paie` et
 * `sessions_caisse` restent sans état d'archive : leur correction est un
 * geste métier (annuler, contre-passer, avoir, mouvement inverse), et une
 * colonne d'archive y serait la porte que ce dépôt ferme depuis PA-159.
 *
 * @see EF-M3-01 Référentiel clients
 * @see EF-M6-01 Référentiel articles
 * @see EF-M7-01 Référentiel fournisseurs
 */
return new class () extends Migration {
    /** @var list<string> */
    private const TABLES = ['clients', 'fournisseurs', 'articles'];

    public function up(): void
    {
        foreach (self::TABLES as $table) {
            Schema::table($table, function (Blueprint $blueprint): void {
                $blueprint->boolean('actif')->default(true);
            });
        }
    }

    public function down(): void
    {
        foreach (self::TABLES as $table) {
            Schema::table($table, function (Blueprint $blueprint): void {
                $blueprint->dropColumn('actif');
            });
        }
    }
};
