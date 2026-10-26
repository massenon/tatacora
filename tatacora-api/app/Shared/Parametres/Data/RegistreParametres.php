<?php

declare(strict_types=1);

namespace App\Shared\Parametres\Data;

use App\Domain\Achats\Services\ReceptionService;
use App\Domain\Comptabilite\Services\CalculTvaService;
use App\Domain\Comptabilite\Services\CorrespondanceComptesService;
use App\Domain\Comptabilite\Services\PlanComptableService;
use App\Domain\Comptabilite\Support\RolesCorrespondance;
use App\Domain\Hebergement\Services\AnnulationReservationService;
use App\Domain\Rh\Services\CalculPaieService;
use App\Domain\Rh\Services\CongeService;
use App\Shared\Audit\Jobs\PurgerJournalAuditJob;
use App\Shared\Mail\Services\ConfigurationMailService;
use App\Shared\Parametres\Services\OptionsSystemeService;
use App\Shared\ReportEngine\Services\ReportHeaderService;

/**
 * LE registre des paramètres modifiables — fermé, jamais un scan de la table.
 *
 * ## Pourquoi fermé
 *
 * L'écriture aurait pu être générique : `PUT /parametres/{cle}`, la clé
 * arrivant de l'écran. Trois conséquences l'interdisent.
 *
 * 1. **Une clé inconnue serait créée sans que rien ne la lise.** Un
 *    Administrateur qui pose `mecef_actif = true` verrait l'écran confirmer
 *    l'enregistrement pendant qu'aucune ligne de code ne consulte cette clé —
 *    exactement l'indicateur qui affirme un état qu'il n'a pas vérifié
 *    (PA-59/60/61). Le mode réel MECeF dépend de la présence de la clé API en
 *    configuration serveur, et de rien d'autre
 *    ({@see \App\Domain\Facturation\Providers\MecefServiceProvider}).
 * 2. **Une valeur sans forme déclarée n'est validée par personne.** `taux_tva`
 *    est un décimal entre 0 et 100 ; le stocker en `text` ne le dit pas.
 *    « dix-huit » entrerait en base et lèverait au comptoir, en présence du
 *    client.
 * 3. **Aucun secret ne doit pouvoir entrer ici.** La tentation « un seul écran
 *    de paramétrage, c'est plus simple » est nommée dans
 *    {@see \App\Shared\Parametres\Services\ParametreSystemeService} : cette
 *    table est lisible par tout profil ayant accès à l'écran. Le registre n'en
 *    déclare aucun, et un test structurel refuse toute clé qui ressemblerait à
 *    un secret — sans lui, la garde tiendrait aujourd'hui et céderait le jour
 *    où quelqu'un ajouterait une ligne.
 *
 * ## Ce que le registre n'est PAS
 *
 * Ce n'est pas une barrière contre la modification des valeurs réglementaires.
 * `taux_cnss_risques_professionnels` est délibérément **modifiable** : il est
 * absent parce que le taux hôtellerie n'est pas confirmé (PA-53), et l'écran
 * est précisément l'endroit où un Administrateur muni de la source officielle
 * le renseignera. L'interdire signifierait qu'il ne peut arriver que par un
 * seeder — c'est-à-dire par la voie que PA-53 condamne, où un chiffre plausible
 * devient la règle de production sans que personne ne le rouvre.
 *
 * Les clés sont reprises des constantes des services qui les LISENT, jamais
 * réécrites en littéral : renommer une clé sans toucher ici produirait un
 * écran qui écrit dans le vide.
 */
final class RegistreParametres
{
    public const GROUPE_ENTREPRISE = 'entreprise';

    public const GROUPE_FISCALITE = 'fiscalite';

    public const GROUPE_SOCIAL = 'social';

    public const GROUPE_EXPLOITATION = 'exploitation';

    /*
     * Deux groupes ajoutés le 02/09/2026 (directive Product Owner — les sept
     * onglets du maître deviennent réels) : la configuration SMTP hors mot de
     * passe, et les bascules d'activation d'`OptionsSysteme`.
     */
    public const GROUPE_EMAIL = 'email';

    public const GROUPE_ACTIVATION = 'activation';

    /**
     * La correspondance rôle -> compte comptable (26/10/2026). Ses clés
     * `compte_<rôle>` sont déclarées ICI pour que l'écriture, l'audit et la
     * synchronisation des postes passent par le chemin des autres paramètres ;
     * elles ne se montrent PAS dans l'écran Paramètres, qui a son propre écran
     * (« Correspondance des comptes »).
     */
    public const GROUPE_COMPTES = 'comptes';

    /**
     * Motifs interdits dans une clé — le filet du test structurel.
     *
     * @var list<string>
     */
    public const MOTIFS_SECRET = [
        'api_key', 'apikey', 'secret', 'token', 'password', 'mot_de_passe',
        'cle_api', 'private', 'credential',
    ];

    /**
     * @return list<DefinitionParametre>
     */
    public static function definitions(): array
    {
        return array_merge(self::definitionsGenerales(), self::definitionsComptes());
    }

    /**
     * Un paramètre par rôle de {@see RolesCorrespondance::ROLES}.
     *
     * Le texte est un NUMÉRO de compte (`PlanComptableService::NUMERO_COMPTE_FORMAT`,
     * la règle unique) ; son existence au plan et la classe du rôle sont
     * jugées par {@see CorrespondanceComptesService::verifier()}, appelée par
     * `EnregistrerParametreService`. Vide : le rôle revient à son défaut.
     *
     * @return list<DefinitionParametre>
     */
    private static function definitionsComptes(): array
    {
        $definitions = [];

        foreach (RolesCorrespondance::ROLES as $role => $description) {
            $definitions[] = new DefinitionParametre(
                cle: CorrespondanceComptesService::cle($role),
                groupe: self::GROUPE_COMPTES,
                libelle: 'Compte — ' . $description['libelle'],
                type: 'texte',
                regles: ['string', 'regex:' . PlanComptableService::NUMERO_COMPTE_FORMAT],
                aide: $description['aide'] . ' Vide : le compte par défaut (' . RolesCorrespondance::defaut($role)
                    . '). Vaut pour les pièces futures, jamais pour une pièce déjà passée.',
            );
        }

        return $definitions;
    }

    /**
     * @return list<DefinitionParametre>
     */
    private static function definitionsGenerales(): array
    {
        return [
            // --- Identité de l'établissement : en-tête de tous les états.
            new DefinitionParametre(
                cle: ReportHeaderService::CLE_RAISON_SOCIALE,
                groupe: self::GROUPE_ENTREPRISE,
                libelle: 'Raison sociale',
                type: 'texte',
                regles: ['string', 'max:150'],
            ),
            new DefinitionParametre(
                cle: ReportHeaderService::CLE_PROMOTEUR,
                groupe: self::GROUPE_ENTREPRISE,
                libelle: 'Nom du promoteur',
                type: 'texte',
                regles: ['string', 'max:150'],
                aide: 'Imprimé sous la raison sociale dans l’en-tête des états '
                    . 'quand il est renseigné — jamais un nom deviné.',
            ),
            new DefinitionParametre(
                cle: ReportHeaderService::CLE_ADRESSE,
                groupe: self::GROUPE_ENTREPRISE,
                libelle: 'Adresse du siège d\'exploitation',
                type: 'texte',
                regles: ['string', 'max:255'],
            ),
            new DefinitionParametre(
                cle: ReportHeaderService::CLE_TELEPHONE,
                groupe: self::GROUPE_ENTREPRISE,
                libelle: 'Téléphone principal',
                type: 'texte',
                // La validation du maître (`data-regle-tel`, validation.js) :
                // chiffres, espaces, indicatif — un libellé libre imprimerait
                // n'importe quoi en en-tête de chaque état.
                regles: ['string', 'max:40', 'regex:/^\+?[0-9 ().\-]{6,}$/'],
            ),
            new DefinitionParametre(
                cle: ReportHeaderService::CLE_EMAIL,
                groupe: self::GROUPE_ENTREPRISE,
                libelle: 'Email de contact',
                type: 'texte',
                // `nullable` sur la règle `email` : vider le champ est permis,
                // mais une valeur présente doit être une adresse valide.
                regles: ['nullable', 'email:rfc', 'max:150'],
            ),
            new DefinitionParametre(
                cle: ReportHeaderService::CLE_WHATSAPP,
                groupe: self::GROUPE_ENTREPRISE,
                libelle: 'Numéro WhatsApp Business',
                type: 'texte',
                regles: ['nullable', 'string', 'max:40', 'regex:/^\+?[0-9 ().\-]{6,}$/'],
                // La CLÉ D'API WhatsApp Business du maître, elle, n'entrera
                // jamais ici : secret technique, `.env` seulement — même
                // partage que le n° contribuable MECeF face à sa clé d'API.
                aide: 'Le numéro, pas la clé d’API — celle-ci vit en configuration '
                    . 'serveur. Imprimé dans l’en-tête des états quand il est renseigné.',
            ),
            new DefinitionParametre(
                cle: ReportHeaderService::CLE_SITE_WEB,
                groupe: self::GROUPE_ENTREPRISE,
                libelle: 'Site web',
                type: 'texte',
                regles: ['string', 'max:150'],
            ),
            new DefinitionParametre(
                cle: ReportHeaderService::CLE_IFU,
                groupe: self::GROUPE_ENTREPRISE,
                libelle: 'IFU (Identifiant Fiscal Unique)',
                type: 'texte',
                regles: ['string', 'max:30'],
                // Première phrase : l'aide du maître (`data-regle-requis`,
                // parametres.html l.57). La clé reste effaçable malgré tout —
                // MECeF est `en_attente_implementation`, et interdire de vider
                // une valeur fausse serait pire que la laisser vide.
                aide: 'L’IFU est obligatoire pour la facturation MECeF. Laissé vide, '
                    . 'la mention n’apparaît sur aucun document : imprimer un exemple '
                    . 'de format serait un faux identifiant fiscal.',
            ),
            new DefinitionParametre(
                cle: ReportHeaderService::CLE_RCCM,
                groupe: self::GROUPE_ENTREPRISE,
                libelle: 'RCCM',
                type: 'texte',
                regles: ['string', 'max:30'],
                aide: 'Même règle que l’IFU : absent tant qu’il n’est pas renseigné.',
            ),
            new DefinitionParametre(
                cle: self::CLE_NUMERO_MECEF,
                groupe: self::GROUPE_ENTREPRISE,
                libelle: 'N° Contribuable MECeF',
                type: 'texte',
                regles: ['string', 'max:30'],
                // « Fourni par la DGI » est l'invite du maître
                // (`prototype_v2/pages/parametres.html` l.66) : elle dit OÙ se
                // trouve la valeur, ce qu'aucun autre texte de l'écran ne dit.
                aide: 'Fourni par la DGI. Identifiant, donc paramétrable — la '
                    . 'CLÉ D’API MECeF, elle, vit en configuration serveur et '
                    . 'n’apparaîtra jamais ici.',
            ),

            // --- Fiscalité.
            new DefinitionParametre(
                cle: CalculTvaService::CLE_PARAMETRE_ACTIVE,
                groupe: self::GROUPE_FISCALITE,
                libelle: 'Assujettissement à la TVA',
                type: 'booleen',
                aide: 'Ne peut pas être activé tant que le taux n’est pas renseigné : '
                    . 'la facture lèverait au comptoir.',
            ),
            new DefinitionParametre(
                cle: CalculTvaService::CLE_PARAMETRE_TAUX,
                groupe: self::GROUPE_FISCALITE,
                libelle: 'Taux de TVA (%)',
                type: 'decimal',
                regles: ['numeric', 'min:0', 'max:100'],
            ),
            new DefinitionParametre(
                cle: CalculTvaService::CLE_PARAMETRE_CONVENTION,
                groupe: self::GROUPE_FISCALITE,
                libelle: 'Convention des prix du catalogue',
                type: 'choix',
                choix: [CalculTvaService::CONVENTION_HT, CalculTvaService::CONVENTION_TTC],
                // Libellés d'affichage (02/09/2026, passage navigateur : la
                // valeur brute « ttc » sortait telle quelle à l'écran).
                choixLibelles: [
                    CalculTvaService::CONVENTION_HT => 'HT — la TVA s’ajoute aux tarifs',
                    CalculTvaService::CONVENTION_TTC => 'TTC — la TVA est extraite des tarifs',
                ],
                aide: '« ht » : la TVA s’ajoute aux tarifs. « ttc » : elle en est extraite.',
            ),
            new DefinitionParametre(
                cle: ReportHeaderService::CLE_REGIME_FISCAL,
                groupe: self::GROUPE_FISCALITE,
                libelle: 'Régime fiscal',
                type: 'choix',
                // Les TROIS valeurs du maître (parametres.html l.64), et
                // aucune autre : un régime libre serait une mention fiscale
                // inventée sur les documents qui l'impriment.
                choix: ['reel_normal', 'reel_simplifie', 'tpu'],
                choixLibelles: [
                    'reel_normal' => 'Réel normal',
                    'reel_simplifie' => 'Réel simplifié',
                    'tpu' => 'Taxe Professionnelle Unique',
                ],
                aide: 'Imprimé avec l’IFU et le RCCM dans les mentions légales des états '
                    . 'quand il est renseigné.',
            ),

            // --- Charges sociales. Modifiables, et c'est le point (PA-53).
            new DefinitionParametre(
                cle: CalculPaieService::CLE_CNSS_SALARIE,
                groupe: self::GROUPE_SOCIAL,
                libelle: 'CNSS part salariale (%)',
                type: 'decimal',
                regles: ['numeric', 'min:0', 'max:100'],
            ),
            new DefinitionParametre(
                cle: CalculPaieService::CLE_CNSS_PENSION_EMPLOYEUR,
                groupe: self::GROUPE_SOCIAL,
                libelle: 'CNSS pension, part patronale (%)',
                type: 'decimal',
                regles: ['numeric', 'min:0', 'max:100'],
            ),
            new DefinitionParametre(
                cle: CalculPaieService::CLE_CNSS_PRESTATIONS_FAMILIALES,
                groupe: self::GROUPE_SOCIAL,
                libelle: 'CNSS prestations familiales (%)',
                type: 'decimal',
                regles: ['numeric', 'min:0', 'max:100'],
            ),
            new DefinitionParametre(
                cle: CalculPaieService::CLE_VPS,
                groupe: self::GROUPE_SOCIAL,
                libelle: 'Versement Patronal sur Salaires (%)',
                type: 'decimal',
                regles: ['numeric', 'min:0', 'max:100'],
                aide: 'Assiette : total des bruts, sans plafond. Jamais une retenue salariale.',
            ),
            new DefinitionParametre(
                cle: CalculPaieService::CLE_CNSS_RISQUES_PROFESSIONNELS,
                groupe: self::GROUPE_SOCIAL,
                libelle: 'CNSS risques professionnels (%)',
                type: 'decimal',
                regles: [
                    'numeric',
                    'min:' . CalculPaieService::RISQUES_PROFESSIONNELS_TAUX_MIN,
                    'max:' . CalculPaieService::RISQUES_PROFESSIONNELS_TAUX_MAX,
                ],
                aide: 'Non confirmé pour l’hôtellerie : la charge patronale reste '
                    . 'publiée en fourchette tant qu’il est vide. Bornes réglementaires '
                    . CalculPaieService::RISQUES_PROFESSIONNELS_TAUX_MIN . ' à '
                    . CalculPaieService::RISQUES_PROFESSIONNELS_TAUX_MAX . ' %.',
            ),

            // --- Exploitation.
            new DefinitionParametre(
                cle: ReceptionService::CLE_TOLERANCE,
                groupe: self::GROUPE_EXPLOITATION,
                libelle: 'Tolérance de réception (%)',
                type: 'decimal',
                regles: ['numeric', 'min:0', 'max:100'],
                // Arbitrage (e) du 31/08/2026 : cette clé se SAISIT ici et
                // n'est semée nulle part. L'aide dit ce que le seuil décide —
                // sans elle, l'Administrateur voit un pourcentage sans savoir
                // qu'il arbitre l'acceptation d'une livraison, donc une
                // créance sur le fournisseur. Tant qu'elle est vide,
                // `ReceptionService` REFUSE de réceptionner et nomme la clé :
                // c'est le comportement voulu, pas une panne.
                aide: 'RG-10 — écart de quantité toléré entre le bon de commande '
                    . 'et la réception, en % : au-delà, la réception est refusée. '
                    . 'Tant que ce champ est vide, aucune réception n’est possible — '
                    . 'une tolérance devinée ferait accepter ou refuser des livraisons '
                    . 'sur un critère arbitraire.',
            ),
            new DefinitionParametre(
                cle: AnnulationReservationService::CLE_TAUX_MOINS_24H,
                groupe: self::GROUPE_EXPLOITATION,
                libelle: 'Taux d’annulation — moins de 24h avant la prestation (%)',
                type: 'decimal',
                regles: ['numeric', 'min:0', 'max:100'],
                // Séance client du 18 et 20/08/2026 (§4.4, §6.3) : le taux de
                // référence est 50 %, PARAMÉTRABLE — ce champ pré-remplit le
                // formulaire d'annulation, il reste modifiable ligne par
                // ligne à chaque annulation.
                aide: 'Pré-remplit le formulaire d’annulation d’une réservation à moins de '
                    . '24h de la prestation (référence client : 50 %). Reste modifiable au '
                    . 'cas par cas dans le formulaire — ce paramètre ne change jamais une '
                    . 'annulation déjà enregistrée.',
            ),
            new DefinitionParametre(
                cle: CongeService::CLE_PREAVIS,
                groupe: self::GROUPE_EXPLOITATION,
                libelle: 'Préavis de congé (jours)',
                type: 'entier',
                regles: ['integer', 'min:0', 'max:365'],
            ),
            new DefinitionParametre(
                cle: CongeService::CLE_COUVERTURE,
                groupe: self::GROUPE_EXPLOITATION,
                libelle: 'Effectif minimal présent par service',
                type: 'entier',
                regles: ['integer', 'min:0', 'max:100'],
            ),
            new DefinitionParametre(
                cle: PurgerJournalAuditJob::CLE_RETENTION,
                groupe: self::GROUPE_EXPLOITATION,
                libelle: 'Rétention du journal d’audit (jours)',
                type: 'entier',
                regles: ['integer', 'min:0', 'max:3650'],
                aide: 'Vide ou 0 : aucune purge n’a lieu. La durée contractuelle '
                    . 'n’est pas tranchée (PA-08) — la renseigner DÉMARRE la '
                    . 'suppression définitive de traces d’audit.',
            ),

            // --- Email (SMTP) — onglet du maître porté le 02/09/2026. Les
            // quatre clés NON secrètes seulement : le mot de passe SMTP vit en
            // `.env` (`MAIL_PASSWORD`), jamais dans cette table lisible par
            // tout profil ayant accès à l'écran. Lecteur unique :
            // `ConfigurationMailService`, qui superpose ces clés à la
            // configuration d'environnement à chaque envoi réel.
            new DefinitionParametre(
                cle: ConfigurationMailService::CLE_SMTP_HOTE,
                groupe: self::GROUPE_EMAIL,
                libelle: 'Serveur SMTP',
                type: 'texte',
                regles: ['nullable', 'string', 'max:150'],
                aide: 'Vide : la configuration serveur (.env) reste seule maîtresse. '
                    . 'Renseigné, il prend la main sur elle pour tous les envois.',
            ),
            new DefinitionParametre(
                cle: ConfigurationMailService::CLE_SMTP_PORT,
                groupe: self::GROUPE_EMAIL,
                libelle: 'Port',
                type: 'entier',
                regles: ['integer', 'min:1', 'max:65535'],
            ),
            new DefinitionParametre(
                cle: ConfigurationMailService::CLE_SMTP_SECURITE,
                groupe: self::GROUPE_EMAIL,
                libelle: 'Sécurité',
                type: 'choix',
                choix: [
                    ConfigurationMailService::SECURITE_TLS,
                    ConfigurationMailService::SECURITE_SSL,
                    ConfigurationMailService::SECURITE_AUCUNE,
                ],
                choixLibelles: [
                    ConfigurationMailService::SECURITE_TLS => 'TLS',
                    ConfigurationMailService::SECURITE_SSL => 'SSL',
                    ConfigurationMailService::SECURITE_AUCUNE => 'Aucune',
                ],
            ),
            new DefinitionParametre(
                cle: ConfigurationMailService::CLE_SMTP_UTILISATEUR,
                groupe: self::GROUPE_EMAIL,
                libelle: 'Utilisateur SMTP',
                type: 'texte',
                regles: ['nullable', 'email:rfc', 'max:150'],
                aide: 'Le mot de passe SMTP, lui, reste en configuration serveur '
                    . '(.env) et n’apparaîtra jamais ici.',
            ),

            // --- Activation & Sécurité — les bascules d'`OptionsSysteme` du
            // maître qui ont un CONSOMMATEUR serveur, et elles seules
            // (02/09/2026). Lecteur unique des trois : `OptionsSystemeService`,
            // qui porte aussi leurs défauts. Les trois bascules restantes du
            // maître (duplication, suppression groupée, sauvegarde
            // hebdomadaire) ne sont PAS déclarées : rien ne les lirait —
            // motifs datés dans la vue de l'écran Paramètres.
            new DefinitionParametre(
                cle: OptionsSystemeService::CLE_SUPPRESSION,
                groupe: self::GROUPE_ACTIVATION,
                libelle: 'Suppression d\'un enregistrement',
                type: 'booleen',
                aide: 'Affiche le bouton Supprimer dans tous les modules. La suppression '
                    . 'reste un archivage : l\'élément part aux archives et peut être restauré.',
            ),
            new DefinitionParametre(
                cle: OptionsSystemeService::CLE_REINITIALISATION_SEEDERS,
                groupe: self::GROUPE_ACTIVATION,
                libelle: 'Réinitialisation des données de test',
                type: 'booleen',
                aide: 'Ouvre l\'onglet qui vide les jeux de démonstration. À laisser fermé '
                    . 'dès que l\'exploitation réelle a commencé.',
            ),
            new DefinitionParametre(
                cle: OptionsSystemeService::CLE_ALERTES_OUVERTURE,
                groupe: self::GROUPE_ACTIVATION,
                libelle: 'Alertes à l\'ouverture de session',
                type: 'booleen',
                aide: 'Affiche les stocks critiques et les créances échues dès la connexion.',
            ),
        ];
    }

    /**
     * Clé du numéro contribuable MECeF.
     *
     * Déclarée ici faute de constante côté
     * {@see \App\Domain\Facturation\Providers\MecefServiceProvider}, qui la lit
     * en littéral. Une seule des deux doit exister à terme ; en attendant, un
     * test structurel vérifie qu'elles disent la même chose.
     */
    public const CLE_NUMERO_MECEF = 'entreprise_numero_mecef';

    public static function existe(string $cle): bool
    {
        return self::definition($cle) !== null;
    }

    public static function definition(string $cle): ?DefinitionParametre
    {
        foreach (self::definitions() as $definition) {
            if ($definition->cle === $cle) {
                return $definition;
            }
        }

        return null;
    }

    /**
     * @return list<string>
     */
    public static function cles(): array
    {
        return array_map(static fn (DefinitionParametre $d): string => $d->cle, self::definitions());
    }
}
