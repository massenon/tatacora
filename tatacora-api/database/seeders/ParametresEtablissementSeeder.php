<?php

declare(strict_types=1);

namespace Database\Seeders;

use App\Shared\Parametres\Models\ParametreSysteme;
use Illuminate\Database\Seeder;

/**
 * Paramètres système INITIAUX de la base vierge — transcription du script SQL
 * fourni par le Product Owner le 14/10/2026 (`SCRIPTSQL_SETTINGS.txt`) :
 * EXACTEMENT ses 20 clés, valeurs et descriptions.
 *
 * Adaptations, et seulement celles-ci :
 *  - `id` / horodatages : générés à l'insertion (UUID du modèle, maintenant) ;
 *  - `utilisateur_creation_id` / `utilisateur_modification_id` : NULL — les
 *    comptes référencés par le script n'existent plus après `migrate:fresh` ;
 *  - `email_smtp_securite` : le script la laisse VIDE, le PO a dit « TLS »
 *    dans sa directive du même jour → `tls` (valeur du registre fermé).
 *
 * Chacune des 20 clés figure au registre fermé `RegistreParametres`
 * (vérifié par `BaseViergeTest`) : aucune clé n'est créée hors registre.
 * Aucun mot de passe SMTP : il vit dans `.env` seulement.
 *
 * Ce seeder passe AVANT `PaieReferentielSeeder` / `TvaReferentielSeeder` dans
 * `DatabaseSeeder` : leurs `firstOrCreate` deviennent sans effet, et ce sont
 * les descriptions du PO qui restent. `firstOrCreate` ici aussi : une valeur
 * déjà corrigée à l'écran Paramètres n'est JAMAIS réécrite par un second
 * `db:seed`.
 *
 * NON appelé par `DemonstrationSeeder` : l'hôte SMTP et les bascules
 * (`activation_suppression`, `reinitialisation_seeders`) changeraient le
 * comportement des tests qui exécutent la démonstration.
 */
class ParametresEtablissementSeeder extends Seeder
{
    /** @var list<array{0: string, 1: string, 2: string|null}> clé, valeur, description */
    public const PARAMETRES = [
        ['taux_cnss_salarie', '3.6', 'Cotisation CNSS part salariale, en % du brut, sans plafond. Source : cnss.bj (branche pension, 10 % dont 3,6 % salarié).'],
        ['taux_cnss_pension_employeur', '6.4', 'Cotisation CNSS pension part employeur, en % du brut. Source : cnss.bj.'],
        ['taux_cnss_prestations_familiales', '9', 'Cotisation CNSS prestations familiales, employeur uniquement, en % du brut. Source : cnss.bj.'],
        ['taux_vps', '4', 'VPS (Versement Patronal sur Salaires), en % du total des salaires bruts, SANS plafond. Taxe a la charge de l\'employeur, jamais retenue sur le salaire. Declaration et paiement au plus tard le 10 du mois suivant. Source : ATELIER_PLAN_COMPTABLE.md.'],
        ['taux_tva', '18.00', 'Taux de TVA en % — fourni par le Consultant Technique le 15/08/2026. Référence au Code Général des Impôts à joindre (voir PA-36).'],
        ['tva_active', 'true', 'Assujettissement à la TVA (true/false). Inactive tant qu\'un Administrateur ne l\'active pas : aucune taxe n\'est ajoutée aux factures.'],
        ['convention_prix', 'ttc', 'Convention des prix du catalogue : `ht` (les tarifs s\'entendent hors taxe, la TVA s\'ajoute) ou `ttc` (les tarifs incluent déjà la TVA, elle en est extraite). Résout PA-37 — à confirmer par le Product Owner et le Comptable.'],
        ['activation_suppression', 'true', null],
        ['entreprise_ifu', '0202011344660', null],
        ['entreprise_rccm', 'RB/NAT/2020-A-137', null],
        ['entreprise_raison_sociale', 'TATACORA AFRIQUE Gîte Chez Noël', null],
        ['entreprise_promoteur', 'NABOGOU Noel', null],
        ['communication_whatsapp', '0197355974', null],
        ['entreprise_site_web', 'https://tatacora.com/', null],
        ['email_smtp_hote', 'mail.logirestock.digitonpro.com', null],
        ['email_smtp_port', '587', null],
        // Vide dans le script ; « TLS » selon la directive PO du 14/10/2026.
        ['email_smtp_securite', 'tls', null],
        ['email_smtp_utilisateur', 'contact@logirestock.digitonpro.com', null],
        ['fiscalite_regime', '', null],
        ['reinitialisation_seeders', 'true', null],
    ];

    public function run(): void
    {
        foreach (self::PARAMETRES as [$cle, $valeur, $description]) {
            ParametreSysteme::firstOrCreate(
                ['cle' => $cle],
                ['cle' => $cle, 'valeur' => $valeur, 'description' => $description],
            );
        }
    }
}
