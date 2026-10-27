<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Transverse;

use App\Domain\Comptabilite\Services\CalculTvaService;
use App\Domain\Facturation\Providers\MecefServiceProvider;
use App\Domain\Hebergement\Models\CanalReservation;
use App\Domain\Hebergement\Services\CanalReservationService;
use App\Domain\Ventes\Models\TableSalle;
use App\Domain\Ventes\Services\TableSalleService;
use App\Models\User;
use App\Pwa\Livewire\Concerns\FormulaireModal;
use App\Shared\Mail\Services\ConfigurationMailService;
use App\Shared\Parametres\Data\DefinitionParametre;
use App\Shared\Parametres\Data\RegistreParametres;
use App\Shared\Parametres\Services\ApparenceEtablissementService;
use App\Shared\Parametres\Services\EnregistrerParametreService;
use App\Shared\Parametres\Services\OptionsSystemeService;
use App\Shared\Parametres\Services\ParametreSystemeService;
use App\Shared\ReportEngine\Services\ReportHeaderService;
use App\Shared\Secrets\Services\SecretsConfigurationService;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Mail;
use Illuminate\View\View;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use Livewire\WithFileUploads;
use RuntimeException;
use Throwable;

/**
 * Paramètres — maitre : `prototype_v2/pages/parametres.html`.
 *
 * ## L'ÉCRAN EST PILOTÉ PAR LE REGISTRE SERVEUR, ET C'EST CE QUI L'EMPÊCHE DE
 * MENTIR (PA-125)
 *
 * Champs, types, choix, aides et règles viennent tous de
 * `RegistreParametres::definitions()` : une clé ajoutée côté serveur apparaît
 * ici sans livraison. La version précédente portait vingt propriétés publiques
 * écrites à la main, et avec elles **des valeurs de démonstration en dur** —
 * un IFU (`3202612345678`), un RCCM, un numéro MECeF (`DGI-MECEF-88493`), trois
 * canaux de réservation et trois tables de restaurant inventés. Ces chaînes
 * s'affichaient comme des données réelles sur l'écran où l'on renseigne
 * l'identité fiscale de l'établissement ; le numéro MECeF en particulier est
 * l'identifiant qui figure sur les factures.
 *
 * Elle portait aussi `testerSmtp()`, qui répondait « Email de test envoyé avec
 * succès » **sans envoyer quoi que ce soit** : PA-59/60/61 dans sa forme la
 * plus directe — un indicateur qui dit que tout va bien pendant que rien n'a
 * lieu, sur le geste dont le seul but est de vérifier qu'une chose marche.
 * Et un champ `smtp_motdepasse` : un mot de passe SMTP dans
 * `parametres_systeme`, table lisible par tout profil ayant accès à l'écran,
 * ce que les six règles du dépôt interdisent sans exception.
 *
 * ## CHAQUE ONGLET SERT SES GROUPES, ET EUX SEULS (corrigé le 01/09/2026)
 *
 * La version précédente rendait les quatre groupes du registre sous TOUS les
 * onglets à la fois — cliquer sur un onglet changeait sa mise en surbrillance
 * sans jamais changer le contenu affiché, défaut relevé par l'audit
 * navigateur du Product Owner. `ongletDe()` loge chaque définition sous
 * l'onglet où le maître la place visuellement : les groupes `entreprise`
 * (hors « Site web ») et `fiscalite` sous « Identité & Légal », qui porte
 * déjà la sous-section « Informations légales & fiscales » où la TVA
 * prolonge naturellement IFU/RCCM ; « Site web » sous « Communication »,
 * seule exception au découpage par groupe (le maître l'y place, l.75) ;
 * `social` et `exploitation` sous « Activation & Sécurité », le seul onglet à
 * portée transverse — ce qui referme la décision n° 2 de
 * `DIRECTIVE_CONFORMITE_100.md` (aucun groupe réel ne disparaît derrière
 * aucun onglet) SANS les rendre tous en même temps. `taux_cnss_risques_professionnels`
 * reste rendu, sous « Activation & Sécurité » désormais.
 *
 * ⚠ La phrase qui vivait ici — « "Nom du promoteur", "Régime fiscal", tout
 * Communication/Email/Apparence/Tables ne sont couverts par aucune clé » — a
 * cessé d'être vraie le 02/09/2026 (directive PO, les sept onglets réels) :
 * ces champs sont des clés du registre (`entreprise_promoteur`,
 * `fiscalite_regime`, `communication_whatsapp`, `email_smtp_*`), lues par
 * `ReportHeaderService` (en-tête des états) et `ConfigurationMailService`
 * (envois réels). Seuls les DEUX SECRETS du maître restent refusés (clé API
 * WhatsApp, mot de passe SMTP — `.env`), plus son « Message de bienvenue »,
 * couvert par les modèles M12 et non par un paramètre.
 *
 * « Canaux de réservation » n'est plus un onglet vide : `canaux_reservation`
 * est un référentiel réel depuis PA-163 (01/09/2026) — l'onglet lit les
 * canaux existants. Leur gestion (ajout, renommage, désactivation) est
 * ouverte le jour même par `CanalReservationService`, derrière le même
 * contrat que `enregistrerParametre()` : le refus du service est un
 * `RuntimeException` traduit, affiché sous le champ. Le jeton
 * `maitre-refuse:parametres.html#canaux` qui couvrait ces trois gestes est
 * retiré — un motif de refus qui a cessé d'être vrai transforme une décision
 * en oubli (PA-144).
 *
 * ## LES BADGES VIENNENT DES ÉTATS DÉRIVÉS, JAMAIS DES COMMUTATEURS (PA-61)
 *
 * `CalculTvaService::etatTva()` et `MecefServiceProvider::etatConfiguration()`
 * nomment l'état RÉEL. Dériver « TVA active » de la seule présence de
 * `tva_active` afficherait un badge vert pendant que l'émission de facture
 * lève au comptoir faute de taux (PA-62).
 *
 * ## L'ÉCRITURE PASSE PAR `EnregistrerParametreService`, ET PAR LUI SEUL
 *
 * La version précédente faisait `DB::table('parametres_systeme')->updateOrInsert()`
 * sur seize clés en `entreprise.raison_sociale`, `fiscalite.ifu`, `smtp.hote`…
 * — un espace de noms **qui n'est celui d'aucun lecteur** : le registre déclare
 * `entreprise_raison_sociale`, `entreprise_ifu`. Elle écrivait donc seize clés
 * que personne ne lit, en confirmant l'enregistrement. Le service refuse
 * désormais toute clé hors registre, et contrôle la cohérence de l'état
 * RÉSULTANT (PA-124).
 *
 * ⚠ Une seule clé est envoyée par geste : renvoyer le formulaire entier
 * annulerait en silence le changement d'un autre Administrateur.
 *
 *
 * ## PLUS AUCUNE SECTION DE REFUS N'EST AFFICHEE (directive du 31/08/2026)
 *
 * Cet ecran portait un panneau qui enumerait, pour l'utilisateur, ce qu'il ne
 * fait pas. Le Product Owner l'a retire : un ecran ne catalogue pas ses
 * absences. Les motifs eux-memes n'ont pas bouge de place ; les jetons
 * ci-dessous les rendent MESURABLES par `t-trois-sources.js`, ce qui est la
 * seule chose qui distingue une decision d'un oubli.
 *
 * ⚠ Rien n'est rendu inerte a la place : ce qui n'est pas porte est ABSENT,
 * pas grise (Article 3.3).
 *
 * Refus declares (residuels — la vague du 02/09/2026 a rendu les sept
 * onglets REELS, quatre des six refus anterieurs sont LEVES : #email par
 * `envoyerEmailTest()`, #apparence par le televersement `WithFileUploads`,
 * #tables par le referentiel `tables_salle`, et les bascules d'#activation
 * par le groupe `activation` du registre) :
 *   maitre-refuse:parametres.html#identite       (deux invites d'exemple IFU/RCCM —
 *                                                 l'ecran affiche des valeurs, pas des champs)
 *   maitre-refuse:parametres.html#communication  (invite du secret WhatsApp API — .env)
 *   (#email LEVE le 19/10/2026 : « Mot de passe SMTP » saisi, chiffre en base)
 *   maitre-refuse:parametres.html#activation     (pied « Annuler / Enregistrer les
 *                                                 parametres » : une cle par geste, et
 *                                                 trois bascules sans consommateur serveur,
 *                                                 motifs dates dans la vue)
 * @see RG-10 paramétrage sans déploiement
 * @see RG-16 RBAC à 3 niveaux
 * @see DIRECTIVE_CONFORMITE_100.md Articles 4.5, 6, 7, 8
 */
#[Title('Paramètres — LogiReStock — TATACORA AFRIQUE')]
class Parametres extends PageTransverse
{
    use FormulaireModal;
    use WithFileUploads;

    public const MODULE = 'PARAM';

    /**
     * Les SEPT onglets du maître, clé et libellé, dans son ordre
     * (`parametres.html` l.30-36).
     *
     * ⚠ La clé est le `data-onglet` du maître et le libellé son texte, au mot
     * près. `TransversePwaTest` ne compare pas cette constante à elle-même : il
     * PARSE le maître à l'exécution et confronte les deux — permuter deux
     * entrées ici le fait rougir.
     *
     * @var array<string, string>
     */
    public const ONGLETS = [
        'identite' => 'Identité & Légal',
        'communication' => 'Communication',
        'email' => 'Email (SMTP)',
        'apparence' => 'Logo & Apparence',
        'canaux' => 'Canaux de réservation',
        'tables' => 'Espaces & tables',
        'activation' => 'Activation & Sécurité',
    ];

    /**
     * Les groupes du registre serveur, dans l'ordre où il les déclare.
     *
     * Ne commande plus le rendu (chaque groupe loge sous son onglet, voir
     * `ongletDe()`) : reste la liste de référence pour vérifier qu'aucun des
     * quatre ne disparaît, tous onglets confondus.
     *
     * @var array<int, string>
     */
    public const GROUPES_IDENTITE = [
        RegistreParametres::GROUPE_ENTREPRISE,
        RegistreParametres::GROUPE_FISCALITE,
        RegistreParametres::GROUPE_SOCIAL,
        RegistreParametres::GROUPE_EXPLOITATION,
        // Deux groupes de plus le 02/09/2026 (les sept onglets deviennent
        // réels) : SMTP hors secret, et les bascules d'activation.
        RegistreParametres::GROUPE_EMAIL,
        RegistreParametres::GROUPE_ACTIVATION,
    ];

    #[Url(as: 'onglet')]
    public string $onglet = 'identite';

    /** La clé en cours d'édition — jamais une valeur libre : elle est validée. */
    public string $cleEditee = '';

    public string $valeurEditee = '';

    /**
     * L'identifiant du canal en cours de renommage — vide : la modale ouvre
     * en création (`ajouter()`), renseigné : en renommage (`renommer()`).
     */
    public string $canalCleEditee = '';

    public string $canalNom = '';

    /** Le canal en attente de confirmation de désactivation — modale, jamais `wire:confirm`. */
    public ?string $canalADesactiver = null;

    // ---- Logo & Apparence (02/09/2026) — téléversement réel -------------

    /** @var \Livewire\Features\SupportFileUploads\TemporaryUploadedFile|null */
    public $logoTeleverse = null;

    /** @var \Livewire\Features\SupportFileUploads\TemporaryUploadedFile|null */
    public $faviconTeleverse = null;

    // ---- Espaces & tables (02/09/2026) ----------------------------------

    /** Vide : la modale ouvre en création ; renseigné : en renumérotation. */
    public string $tableIdEditee = '';

    public string $tableEspace = '';

    public string $tableNumero = '';

    public string $tablePlaces = '';

    /** « Rétablir le jeu initial » attend une confirmation — modale, jamais `wire:confirm`. */
    public bool $confirmationRetablirTables = false;

    // ---- Email (SMTP) — résultat RÉEL du dernier test (02/09/2026) -------

    /**
     * `null` tant qu'aucun test n'a été tenté. Jamais un succès simulé :
     * l'ancienne version répondait « envoyé avec succès » sans rien envoyer
     * (PA-59/60/61 sur le geste dont le seul but est de vérifier).
     *
     * @var array{succes: bool, detail: string}|null
     */
    public ?array $resultatTestEmail = null;

    /**
     * Le mot de passe SMTP en cours de SAISIE (19/10/2026, « chiffré en
     * base ») : vidé dès l'enregistrement, jamais rechargé — l'écran ne
     * connaît que l'état du secret, jamais sa valeur.
     */
    public string $motDePasseSmtp = '';

    /**
     * @return array<string, list<string>>
     */
    protected function formulaires(): array
    {
        return [
            'parametre' => ['cleEditee', 'valeurEditee'],
            'canal' => ['canalCleEditee', 'canalNom'],
            'logo' => ['logoTeleverse'],
            'favicon' => ['faviconTeleverse'],
            'table' => ['tableIdEditee', 'tableEspace', 'tableNumero', 'tablePlaces'],
        ];
    }

    /**
     * Ouvre l'édition d'UNE clé du registre.
     *
     * Une clé hors registre est refusée avant tout affichage : proposer un
     * champ pour une clé que le service refusera ferait découvrir le refus
     * après la saisie.
     */
    public function ouvrirEditionParametre(string $cle, ParametreSystemeService $lecture): void
    {
        $this->ouvrirFormulaire('parametre');

        $definition = RegistreParametres::definition($cle);

        if ($definition === null) {
            abort(404);
        }

        $this->cleEditee = $definition->cle;
        $this->valeurEditee = (string) ($lecture->get($definition->cle) ?? '');
    }

    /**
     * ⚠ UNE SEULE CLÉ EST ENVOYÉE, et le refus du service est affiché tel quel.
     *
     * L'écart avec PA-103 (aucun message serveur sur l'écran de connexion) est
     * délibéré et vaut d'être écrit : ces messages-là sont rédigés pour un
     * Administrateur, derrière une authentification et un droit `PARAM = C`.
     * Ils disent pourquoi la cohérence est refusée — activer la TVA sans taux —
     * et les remplacer par un refus générique obligerait à deviner.
     */
    public function enregistrerParametre(EnregistrerParametreService $service): void
    {
        $definition = RegistreParametres::definition($this->cleEditee);

        if ($definition === null) {
            abort(404);
        }

        $this->validerEcriture([
            'valeurEditee' => $this->reglesDe($definition),
        ]);

        try {
            $service->enregistrer([$definition->cle => $this->valeurEditee]);
        } catch (RuntimeException $refus) {
            $this->addError('valeurEditee', $refus->getMessage());

            return;
        }

        $this->terminerFormulaire(__('parametres.enregistre'));
    }

    public function fermerModales(): void
    {
        $this->etatFormulaire = null;
        $this->confirmationRetablirTables = false;
        $this->resetValidation();
    }

    /**
     * Ouvre la modale en CRÉATION — `canalCleEditee` reste vide, ce qui est
     * ce qui distingue « ajouter » de « renommer » à l'enregistrement.
     */
    public function ouvrirAjoutCanal(): void
    {
        $this->ouvrirFormulaire('canal');
    }

    /**
     * Ouvre la modale en RENOMMAGE — un identifiant hors référentiel est une
     * erreur d'appel du composant (bouton falsifié), jamais une saisie
     * utilisateur : elle ne mérite pas mieux qu'un refus.
     */
    public function ouvrirRenommageCanal(string $id): void
    {
        $this->ouvrirFormulaire('canal');

        $canal = CanalReservation::find($id);

        if ($canal === null) {
            abort(404);
        }

        $this->canalCleEditee = $canal->id;
        $this->canalNom = $canal->nom;
    }

    /**
     * Le refus du service — nom vide côté serveur en repli, doublon — est un
     * `RuntimeException` traduit, affiché sous le champ : même contrat que
     * `enregistrerParametre()`, deux services d'écriture de cet écran.
     */
    public function enregistrerCanal(CanalReservationService $service): void
    {
        $this->validerEcriture([
            'canalNom' => ['required', 'string', 'max:100'],
        ]);

        try {
            if ($this->canalCleEditee === '') {
                $service->ajouter($this->canalNom);
            } else {
                $service->renommer($this->canalCleEditee, $this->canalNom);
            }
        } catch (RuntimeException $refus) {
            $this->addError('canalNom', $refus->getMessage());

            return;
        }

        $this->terminerFormulaire(__('parametres.canal_enregistre'));
    }

    /**
     * (Dés)active un canal — geste immédiat, hors modale, comme les bascules
     * de l'onglet « Activation & Sécurité » : un réglage qui attend un
     * enregistrement qu'on oublie donne l'illusion d'un état posé qui ne
     * l'est pas.
     *
     * Un canal ne s'efface jamais (`CanalReservationService`) : un identifiant
     * introuvable ici n'est donc pas un état métier possible, seulement un
     * bouton falsifié — même traitement que `ouvrirRenommageCanal()`.
     */
    public function basculerCanal(string $id, CanalReservationService $service): void
    {
        $this->exigerEcriture(self::MODULE);

        if (CanalReservation::find($id) === null) {
            abort(404);
        }

        $service->basculer($id);

        $this->canalADesactiver = null;

        session()->flash('pwa-succes', __('parametres.canal_bascule'));
    }

    /**
     * Confirmation AVANT de désactiver un canal employé — par la modale du
     * dépôt, jamais `wire:confirm` : la boîte native du navigateur est hors
     * charte et `MotifsInterditsPwaTest` la refuse (01/09/2026, trouvé par
     * la garde elle-même). Le maître confirme aussi par SA modale
     * (`Dialogue.confirmer`, `canaux-engine.js`), pas par `confirm()`.
     */
    public function demanderDesactivationCanal(string $id): void
    {
        $this->exigerEcriture(self::MODULE);

        if (CanalReservation::find($id) === null) {
            abort(404);
        }

        $this->canalADesactiver = $id;
    }

    // =====================================================================
    // Activation & Sécurité — les bascules, appliquées IMMÉDIATEMENT
    // =====================================================================

    /**
     * Bascule une option d'activation — au CLIC, jamais au bouton Enregistrer.
     *
     * C'est le contrat du maître (`parametres.html`, commentaire du bloc
     * ACTIVATION & SÉCURITÉ) : « un réglage de sécurité laissé en attente d'un
     * enregistrement que l'utilisateur oublie donne l'illusion d'une
     * protection qui n'est pas posée ». L'écriture passe par
     * `EnregistrerParametreService`, donc par le journal d'audit (RG-15) —
     * chaque changement est tracé, comme au maître (`RBAC.journaliser`).
     */
    public function basculerOption(string $cle, EnregistrerParametreService $service, OptionsSystemeService $options): void
    {
        $this->exigerEcriture(self::MODULE);

        $definition = RegistreParametres::definition($cle);

        // Une clé hors du groupe des bascules est un bouton falsifié, jamais
        // une saisie : refus sec, comme `ouvrirRenommageCanal()`.
        if ($definition === null || $definition->groupe !== RegistreParametres::GROUPE_ACTIVATION) {
            abort(404);
        }

        $nouvelEtat = ! $options->actif($cle);

        $service->enregistrer([$cle => $nouvelEtat ? 'true' : 'false']);

        session()->flash('pwa-succes', __(
            $nouvelEtat ? 'pwa.parametres.bascule_activee' : 'pwa.parametres.bascule_desactivee',
            ['titre' => $definition->libelle],
        ));
    }

    // =====================================================================
    // Email (SMTP) — le test d'envoi RÉEL
    // =====================================================================

    /**
     * Envoie un VRAI courriel de test à l'adresse de contact paramétrée, et
     * rapporte ce que le transport a réellement répondu.
     *
     * Trois issues, aucune simulée : pas d'adresse de contact — le dire ;
     * aucun transport réel configuré (mailer `log`/`array`, hôte vide) — le
     * dire, plutôt qu'un « envoyé » qui n'a rien envoyé ; échec de transport —
     * le message d'erreur est affiché tel quel, comme les refus serveur de
     * cet écran (écart avec PA-103 délibéré : ces messages s'adressent à un
     * Administrateur authentifié, derrière `PARAM = C`).
     */
    public function envoyerEmailTest(ConfigurationMailService $mail, ParametreSystemeService $lecture): void
    {
        $this->exigerEcriture(self::MODULE);

        $adresse = trim((string) $lecture->get(ReportHeaderService::CLE_EMAIL));

        if ($adresse === '') {
            $this->resultatTestEmail = [
                'succes' => false,
                'detail' => __('pwa.parametres.email_test_sans_adresse'),
            ];

            return;
        }

        // `estReelle()` APPLIQUE d'abord les clés SMTP paramétrées — le test
        // emprunte exactement le chemin des envois réels (notifications M12,
        // Contact éditeur), jamais un chemin de démonstration.
        if (! $mail->estReelle()) {
            $this->resultatTestEmail = [
                'succes' => false,
                'detail' => __('pwa.parametres.email_test_sans_configuration'),
            ];

            return;
        }

        try {
            Mail::raw(__('pwa.parametres.email_test_corps'), static function ($courriel) use ($adresse): void {
                $courriel->to($adresse)->subject(__('pwa.parametres.email_test_objet'));
            });
        } catch (Throwable $erreur) {
            $this->resultatTestEmail = [
                'succes' => false,
                'detail' => __('pwa.parametres.email_test_echec', ['erreur' => $erreur->getMessage()]),
            ];

            return;
        }

        $this->resultatTestEmail = [
            'succes' => true,
            'detail' => __('pwa.parametres.email_test_envoye', ['adresse' => $adresse]),
        ];
    }

    /**
     * Range le mot de passe SMTP saisi, CHIFFRÉ (`secrets_configuration`),
     * décision du Product Owner du 19/10/2026. Réservé aux deux rôles
     * d'administration EN PLUS du droit `PARAM = C` : un secret n'est pas un
     * paramètre métier.
     */
    public function enregistrerMotDePasseSmtp(SecretsConfigurationService $secrets): void
    {
        $this->exigerEcriture(self::MODULE);
        $this->exigerAdministration();

        try {
            $secrets->enregistrer(SecretsConfigurationService::SMTP_MOT_DE_PASSE, $this->motDePasseSmtp, $this->utilisateur());
        } catch (RuntimeException $refus) {
            $this->addError('motDePasseSmtp', $refus->getMessage());

            return;
        }

        $this->motDePasseSmtp = '';
        $this->resetErrorBag('motDePasseSmtp');
        session()->flash('pwa-succes', __('pwa.parametres.email_motdepasse_enregistre'));
    }

    /** Efface le secret : `MAIL_PASSWORD` (`.env`) reprend. */
    public function effacerMotDePasseSmtp(SecretsConfigurationService $secrets): void
    {
        $this->exigerEcriture(self::MODULE);
        $this->exigerAdministration();

        $secrets->effacer(SecretsConfigurationService::SMTP_MOT_DE_PASSE, $this->utilisateur());
        $this->motDePasseSmtp = '';
        session()->flash('pwa-succes', __('pwa.parametres.email_motdepasse_efface'));
    }

    private function exigerAdministration(): void
    {
        abort_unless($this->utilisateur()->estAdministrateur(), 403);
    }

    private function utilisateur(): User
    {
        $compte = auth()->user();
        abort_unless($compte instanceof User, 403);

        return $compte;
    }

    // =====================================================================
    // Logo & Apparence — téléversement réel
    // =====================================================================

    public function ouvrirChangementLogo(): void
    {
        $this->ouvrirFormulaire('logo');
    }

    public function ouvrirChangementFavicon(): void
    {
        $this->ouvrirFormulaire('favicon');
    }

    /**
     * PNG/JPG (l'invite du maître : « Sélectionnez un fichier PNG/JPG,
     * recommandé 512×512px »), 2 Mo au plus — un logo est une vignette, pas
     * une photothèque. L'ancien fichier est REMPLACÉ, jamais accumulé
     * (`ApparenceEtablissementService`).
     */
    public function enregistrerLogo(ApparenceEtablissementService $apparence): void
    {
        $this->validerEcriture([
            'logoTeleverse' => ['required', 'file', 'mimes:png,jpg,jpeg', 'max:2048'],
        ]);

        $apparence->enregistrerLogo($this->logoTeleverse);

        $this->terminerFormulaire(__('pwa.parametres.apparence_logo_enregistre'));
    }

    /** « .ico ou .png 32×32px » au maître — 512 Ko suffisent largement. */
    public function enregistrerFavicon(ApparenceEtablissementService $apparence): void
    {
        $this->validerEcriture([
            'faviconTeleverse' => ['required', 'file', 'mimes:png,jpg,jpeg,ico', 'max:512'],
        ]);

        $apparence->enregistrerFavicon($this->faviconTeleverse);

        $this->terminerFormulaire(__('pwa.parametres.apparence_favicon_enregistre'));
    }

    // =====================================================================
    // Espaces & tables — CRUD réel du référentiel `tables_salle`
    // =====================================================================

    public function ouvrirAjoutTable(): void
    {
        $this->ouvrirFormulaire('table');
    }

    public function ouvrirRenumerotationTable(string $id): void
    {
        $this->ouvrirFormulaire('table');

        $table = TableSalle::find($id);

        if ($table === null) {
            abort(404);
        }

        $this->tableIdEditee = $table->id;
        $this->tableEspace = $table->espace;
        $this->tableNumero = (string) $table->numero;
        $this->tablePlaces = (string) $table->places;
    }

    /**
     * Création (id vide) ou renumérotation — même modale, même contrat que
     * `enregistrerCanal()` : le refus du service (`RuntimeException` traduite
     * — numéro déjà pris, espace inconnu) est affiché sous le champ.
     */
    public function enregistrerTable(TableSalleService $service): void
    {
        $espaces = array_column(
            array_filter(TableSalleService::ESPACES, static fn (array $espace): bool => $espace['avecTables']),
            'cle',
        );

        $this->validerEcriture([
            'tableEspace' => ['required', 'in:' . implode(',', $espaces)],
            'tableNumero' => ['required', 'integer', 'min:1', 'max:999'],
            'tablePlaces' => ['nullable', 'integer', 'min:1', 'max:99'],
        ]);

        try {
            if ($this->tableIdEditee === '') {
                $table = $service->creer(
                    $this->tableEspace,
                    (int) $this->tableNumero,
                    $this->tablePlaces === '' ? null : (int) $this->tablePlaces,
                );

                $this->terminerFormulaire(__('pwa.parametres.table_creee', ['libelle' => $table->libelle]));
            } else {
                $service->renumeroter($this->tableIdEditee, (int) $this->tableNumero);

                $this->terminerFormulaire(__('pwa.parametres.table_renumerotee'));
            }
        } catch (RuntimeException $refus) {
            $this->addError('tableNumero', $refus->getMessage());
        }
    }

    /**
     * (Dés)active une table — geste immédiat, comme les canaux. Le REFUS du
     * maître vit dans le service, jamais recopié ici : une table au panier
     * OUVERT ne se désactive pas (les consommations servies n'auraient plus
     * de table pour les porter jusqu'à l'addition), et il est affiché en
     * bandeau parce qu'aucune modale n'est ouverte à ce moment.
     */
    public function basculerTable(string $id, TableSalleService $service): void
    {
        $this->exigerEcriture(self::MODULE);

        try {
            $service->basculer($id);
        } catch (RuntimeException $refus) {
            session()->flash('pwa-erreur', $refus->getMessage());

            return;
        }

        session()->flash('pwa-succes', __('pwa.parametres.table_basculee'));
    }

    /** Confirmation AVANT le rétablissement — la modale du dépôt, jamais `wire:confirm`. */
    public function ouvrirRetablirTables(): void
    {
        $this->exigerEcriture(self::MODULE);

        $this->confirmationRetablirTables = true;
    }

    /**
     * « Rétablir le jeu initial » — les treize tables du seeder, par LE MÊME
     * `retablirJeuInitial()` que lui (un seul auteur). Les ventes déjà
     * enregistrées ne sont pas touchées ; une table au panier ouvert fait
     * refuser l'opération entière (service).
     */
    public function retablirTables(TableSalleService $service): void
    {
        $this->exigerEcriture(self::MODULE);

        $this->confirmationRetablirTables = false;

        try {
            $service->retablirJeuInitial();
        } catch (RuntimeException $refus) {
            session()->flash('pwa-erreur', $refus->getMessage());

            return;
        }

        session()->flash('pwa-succes', __('pwa.parametres.tables_jeu_retabli'));
    }

    public function render(
        ParametreSystemeService $lecture,
        CalculTvaService $tva,
        TableSalleService $tablesSalle,
        OptionsSystemeService $options,
        ApparenceEtablissementService $apparence,
        SecretsConfigurationService $secrets,
    ): View {
        $groupes = [];
        $groupesParOnglet = [];

        foreach (RegistreParametres::definitions() as $definition) {
            // La correspondance rôle -> compte (26/10/2026) a son PROPRE écran
            // (« Correspondance des comptes », hub de la comptabilité) : ses
            // quinze clés ne se montrent pas ici, où elles noieraient l'onglet
            // Identité & Légal.
            if ($definition->groupe === RegistreParametres::GROUPE_COMPTES) {
                continue;
            }

            $ligne = [
                'definition' => $definition,
                // ⚠ ARTICLE 7 — « — » quand la clé n'est PAS renseignée, « 0 »
                // quand elle vaut zéro. Les confondre ferait croire l'arbitrage
                // de PA-53 rendu : un taux absent publie une fourchette, un
                // taux à 0 % serait une charge patronale nulle.
                'valeur' => $lecture->estRenseigne($definition->cle)
                    ? (string) $lecture->get($definition->cle)
                    : null,
            ];

            // $groupes : la vue d'ensemble, tous onglets confondus (aucun
            // groupe réel ne disparaît — voir le test qui le mesure).
            $groupes[$definition->groupe][] = $ligne;
            // $groupesParOnglet : ce que SERT l'onglet actif, et lui seul.
            $groupesParOnglet[self::ongletDe($definition)][$definition->groupe][] = $ligne;
        }

        return view('pwa.transverse.parametres', array_merge($this->socle(), [
            'titrePage' => __('pwa.parametres.titre'),
            'groupes' => $groupes,
            'groupesOnglet' => $groupesParOnglet[$this->onglet] ?? [],
            // Chargés QUEL QUE SOIT l'onglet actif depuis le 02/09/2026 : la
            // vue rend le tableau des canaux sur CHAQUE onglet — visible sur
            // « Canaux de réservation », en ombre `hidden` ailleurs (même
            // partiel, voir `partials/tableau-canaux.blade.php`) — pour que
            // ses entêtes existent dès le premier GET (G5). Une requête sur
            // un référentiel de quelques lignes, jamais un coût.
            'canaux' => $this->canauxReels(),
            // Les états DÉRIVÉS, jamais les commutateurs bruts (PA-61).
            'etatTva' => $tva->etatTva(),
            'etatMecef' => MecefServiceProvider::etatConfiguration(),
            'definitionEditee' => RegistreParametres::definition($this->cleEditee),
            'peutEcrire' => $this->peutEcrire(),
            // Espaces & tables : le référentiel réel, occupation DÉDUITE des
            // paniers ouverts — jamais un drapeau (tables-engine.js, PA-126).
            'espacesTables' => $this->espacesTables($tablesSalle),
            'tableEditee' => $this->tableIdEditee === '' ? null : TableSalle::find($this->tableIdEditee),
            // Activation & Sécurité : l'état EFFECTIF de chaque bascule
            // (défaut du maître quand rien n'est stocké), jamais un tiret.
            'bascules' => $this->bascules($options),
            // Logo & Apparence : ce que la coquille affiche RÉELLEMENT — le
            // téléversé s'il existe, l'actif livré sinon (même service).
            'urlLogo' => $apparence->urlLogo(),
            'urlFavicon' => $apparence->urlFavicon(),
            // Email (SMTP) : l'ÉTAT du mot de passe (renseigné, quand, par
            // qui), jamais sa valeur ; la saisie n'est offerte qu'aux deux
            // rôles d'administration.
            'etatMotDePasseSmtp' => $secrets->etat(SecretsConfigurationService::SMTP_MOT_DE_PASSE),
            'peutSaisirSecret' => $this->peutEcrire() && (auth()->user()?->estAdministrateur() ?? false),
        ]))->layout('layouts.pwa', ['title' => __('pwa.parametres.titre_page')]);
    }

    /**
     * L'onglet du maître où loge CETTE définition du registre.
     *
     * Une seule exception au découpage par groupe, documentée et isolée ici :
     * `ReportHeaderService::CLE_SITE_WEB` est du groupe `entreprise` (c'est
     * l'en-tête des états) mais le maître pose son champ « Site web » sous
     * l'onglet « Communication » (`parametres.html` l.75).
     *
     * Éprouvé par mutation le 01/09/2026 : réduire le corps à `return
     * 'identite';` fait rougir trois cas de `TransversePwaTest`
     * (`aucun_groupe_du_registre_serveur_ne_disparait_derriere_un_onglet`,
     * `un_onglet_ne_sert_pas_les_groupes_d_un_autre_onglet`,
     * `un_parametre_non_renseigne_rend_un_tiret_et_un_zero_reste_zero`) —
     * restauré ensuite.
     */
    public static function ongletDe(DefinitionParametre $definition): string
    {
        // Deux exceptions au découpage par groupe, toutes deux du groupe
        // `entreprise` (l'en-tête des états) et posées par le maître sous
        // « Communication » : « Site web » (l.75) et « Numéro WhatsApp
        // Business » (l.71).
        if (in_array($definition->cle, [ReportHeaderService::CLE_SITE_WEB, ReportHeaderService::CLE_WHATSAPP], true)) {
            return 'communication';
        }

        return match ($definition->groupe) {
            RegistreParametres::GROUPE_SOCIAL,
            RegistreParametres::GROUPE_EXPLOITATION,
            RegistreParametres::GROUPE_ACTIVATION => 'activation',
            RegistreParametres::GROUPE_EMAIL => 'email',
            default => 'identite',
        };
    }

    /**
     * Les espaces du maître avec leurs tables réelles — TOUTES, désactivées
     * comprises (une table absente de l'écran laisserait croire qu'elle
     * n'existe pas), occupation lue des paniers ouverts.
     *
     * @return list<array{cle: string, libelle: string, prefixe: string, avecTables: bool, tables: list<array{table: TableSalle, occupee: bool}>}>
     */
    private function espacesTables(TableSalleService $service): array
    {
        $parEspace = $service->parEspace();

        $resultat = [];

        foreach (TableSalleService::ESPACES as $espace) {
            $tables = [];

            foreach ($parEspace[$espace['cle']] ?? [] as $table) {
                $tables[] = [
                    'table' => $table,
                    'occupee' => $service->estOccupee($table->id),
                ];
            }

            $resultat[] = $espace + ['tables' => $tables];
        }

        return $resultat;
    }

    /**
     * Les bascules d'activation : titre et détail du REGISTRE (libellé et
     * aide de la définition — les mots du maître, un seul auteur), pastille
     * de risque du maître, état EFFECTIF.
     *
     * @return list<array{cle: string, titre: string, detail: string, risque: string, actif: bool}>
     */
    private function bascules(OptionsSystemeService $options): array
    {
        $liste = [];

        foreach (RegistreParametres::definitions() as $definition) {
            if ($definition->groupe !== RegistreParametres::GROUPE_ACTIVATION) {
                continue;
            }

            // Le risque du maître (`options-systeme.js`, LIBELLES.*.risque) —
            // un `match` à clés LITTÉRALES, jamais une concaténation.
            $risque = match ($definition->cle) {
                OptionsSystemeService::CLE_SUPPRESSION => 'moyen',
                OptionsSystemeService::CLE_REINITIALISATION_SEEDERS => 'eleve',
                OptionsSystemeService::CLE_ALERTES_OUVERTURE => 'faible',
                default => 'eleve',
            };

            $liste[] = [
                'cle' => $definition->cle,
                'titre' => $definition->libelle,
                'detail' => (string) $definition->aide,
                'risque' => $risque,
                'actif' => $options->actif($definition->cle),
            ];
        }

        return $liste;
    }

    /**
     * Les canaux de réservation réels, avec leur nombre d'utilisations.
     *
     * `canaux_reservation` est un référentiel administrable depuis PA-163
     * (01/09/2026), et sa gestion (ajout, renommage, désactivation) vit SUR
     * cet écran depuis le même jour (`CanalReservationService`) — la phrase
     * qui disait ici l'inverse a été retirée le 02/09/2026 (PA-144).
     *
     * @return Collection<int, CanalReservation>
     */
    private function canauxReels(): Collection
    {
        return CanalReservation::query()
            ->withCount('reservations')
            ->orderBy('created_at')
            ->get();
    }

    /**
     * Les règles du REGISTRE, jamais une seconde liste.
     *
     * Le type déclaré commande la forme ; les règles déclarées commandent le
     * domaine. Les réécrire ici produirait un champ que l'écran accepte et que
     * le service refuse — la divergence exacte que `DefinitionParametre` existe
     * pour empêcher.
     *
     * @return list<string>
     */
    private function reglesDe(DefinitionParametre $definition): array
    {
        $regles = match ($definition->type) {
            'booleen' => ['in:true,false'],
            'entier' => ['integer'],
            'decimal' => ['numeric'],
            'choix' => ['in:'.implode(',', $definition->choix)],
            default => ['string'],
        };

        return array_merge(['nullable'], $regles, $definition->regles);
    }

    /** Le niveau réel — même source que le middleware `module:`. */
    private function peutEcrire(): bool
    {
        $utilisateur = auth()->user();

        return $utilisateur !== null
            && $utilisateur->estActif()
            && $utilisateur->niveauSurModule(self::MODULE) === 'C';
    }
}
