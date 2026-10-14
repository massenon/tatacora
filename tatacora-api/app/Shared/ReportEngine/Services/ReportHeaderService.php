<?php

declare(strict_types=1);

namespace App\Shared\ReportEngine\Services;

use App\Models\User;
use App\Shared\Parametres\Data\RegistreParametres;
use App\Shared\Parametres\Services\ApparenceEtablissementService;
use App\Shared\Parametres\Services\ParametreSystemeService;
use App\Shared\ReportEngine\Data\EnTeteRapport;

/**
 * Génération de l'en-tête normalisée — **point d'entrée unique** (RG-19).
 *
 * @see RG-19 Entête normalisée obligatoire sur tout état édité
 * @see EF-M14-01
 *
 * ## Pourquoi ce service est unique et pourquoi ça compte
 *
 * `05_MODULE_SPECIFICATIONS.md` §M14 : « interdiction absolue de dupliquer la
 * génération d'en-tête par contrôleur ». `RESPECT_TABLEAU_RAPPORT.md` §4 en
 * donne la raison observée : « Développeur (ou IA) pressé, "plus simple de
 * copier l'en-tête existante" ». Une en-tête copiée diverge à la première
 * évolution — et un état d'un module affiche alors une adresse ou un IFU
 * différent d'un autre, sur des documents opposables.
 *
 * Le seul recours structurel est que rien d'autre ne sache la construire :
 * `EtatInterface` n'a aucun accès à ce service, et `GenerateurEtatService` est
 * le seul appelant.
 *
 * ## Valeurs d'entreprise : paramétrées, avec repli documenté
 *
 * `DIRECTIVE_EXPORT_PDF.md` §1 distingue deux catégories :
 *
 * - **Confirmées** (raison sociale, adresse, téléphone, email, site) — vérifiées
 *   contre `parametres.html` du prototype. Elles servent de valeur par défaut
 *   pour qu'un état reste éditable avant tout paramétrage, mais restent
 *   surchargeables depuis `parametres_systeme` : l'adresse d'un gîte change,
 *   un redéploiement pour la corriger serait absurde.
 * - **Non confirmées** (IFU, RCCM) — le prototype ne montre qu'un
 *   `placeholder="Ex. 3202612345678"`, jamais une vraie valeur. **Aucun repli
 *   n'est fourni** : imprimer un exemple de format sur un document fiscal
 *   serait pire que de ne rien imprimer. La ligne disparaît tant que le Gérant
 *   n'a pas renseigné la vraie valeur.
 */
class ReportHeaderService
{
    // Clés de paramétrage — surchargent les valeurs par défaut ci-dessous.
    public const CLE_RAISON_SOCIALE = 'entreprise_raison_sociale';

    public const CLE_ADRESSE = 'entreprise_adresse';

    public const CLE_TELEPHONE = 'entreprise_telephone';

    public const CLE_EMAIL = 'entreprise_email';

    public const CLE_SITE_WEB = 'entreprise_site_web';

    /** Sans repli : jamais de valeur devinée sur une mention fiscale. */
    public const CLE_IFU = 'entreprise_ifu';

    public const CLE_RCCM = 'entreprise_rccm';

    /*
     * Onglets « Identité & Légal » et « Communication » du maître, portés au
     * registre le 02/09/2026 (directive Product Owner). Trois valeurs
     * d'identité de plus, mêmes règles que IFU/RCCM : SANS repli — un
     * promoteur, un numéro WhatsApp ou un régime fiscal devinés seraient des
     * mentions inventées sur des documents remis.
     */
    public const CLE_PROMOTEUR = 'entreprise_promoteur';

    public const CLE_WHATSAPP = 'communication_whatsapp';

    /** Valeur stockée = code fermé (`reel_normal`…) ; le libellé du maître vient du registre. */
    public const CLE_REGIME_FISCAL = 'fiscalite_regime';

    /**
     * Valeurs vérifiées contre `parametres.html` du prototype
     * (`DIRECTIVE_EXPORT_PDF.md` §1, tableau « Confirmé »).
     */
    private const DEFAUTS = [
        self::CLE_RAISON_SOCIALE => 'TATACORA AFRIQUE',
        self::CLE_ADRESSE => 'Quartier Sountichirantikou, Natitingou, Bénin',
        self::CLE_TELEPHONE => '+229 01 97 35 59 74',
        self::CLE_EMAIL => 'nabogounoel@yahoo.fr',
        self::CLE_SITE_WEB => 'www.tatacora.com',
    ];

    /**
     * Le logo livré, sous `public/` — le même fichier que la barre supérieure
     * ({@see ApparenceEtablissementService::ACTIF_LIVRE}), jamais un second.
     *
     * Décision du Product Owner du 14/10/2026 (ticket D392) : nouveau logo,
     * PNG. `DIRECTIVE_EXPORT_PDF.md` §1 écrivait `img/logo.jpg` (chemin du
     * prototype) et refusait `images/logo.png` : sa note visait un chemin
     * INVENTÉ, pas le format — le fichier réel est désormais
     * `assets/img/logo.png`, lu par dompdf depuis `public_path()` (PNG 24 bits
     * sans canal alpha, décodé nativement).
     */
    private const CHEMIN_LOGO = ApparenceEtablissementService::ACTIF_LIVRE;

    public function __construct(
        private readonly ParametreSystemeService $parametres,
    ) {
    }

    public function genererEnTete(
        string $typeRapport,
        string $periode,
        ?User $auteur,
    ): EnTeteRapport {
        [$raisonSociale, $enseigne] = $this->identite();

        return new EnTeteRapport(
            logo: $this->logo(),
            raisonSociale: $raisonSociale,
            enseigne: $enseigne,
            // L'enseigne (minuscules) reste la premiere ligne du bloc de
            // coordonnees des etats M14 — meme identite sur tous les papiers.
            sousTitre: $enseigne."\n".__('rapports.entete.localisation'),
            adresse: $this->valeur(self::CLE_ADRESSE),
            telephone: $this->valeur(self::CLE_TELEPHONE),
            email: $this->valeur(self::CLE_EMAIL),
            siteWeb: $this->valeur(self::CLE_SITE_WEB),
            ifu: $this->mentionFiscale(self::CLE_IFU),
            rccm: $this->mentionFiscale(self::CLE_RCCM),
            typeRapport: $typeRapport,
            periode: $periode,
            auteur: $this->auteur($auteur),
            dateEdition: now()->format('d/m/Y \à H:i'),
            mentionInstitutionnelle: __('rapports.entete.mention_institutionnelle'),
            promoteur: $this->mentionFiscale(self::CLE_PROMOTEUR),
            whatsapp: $this->mentionFiscale(self::CLE_WHATSAPP),
            regimeFiscal: $this->regimeFiscal(),
        );
    }

    /**
     * Nom et fonction de l'utilisateur RBAC **réellement connecté**.
     *
     * `RESPECT_TABLEAU_RAPPORT.md` §4 recense « Auteur affiché = "Administrateur"
     * par défaut au lieu du vrai utilisateur connecté » comme non-conformité
     * fréquente, d'origine « valeur de test laissée en dur ». On ne fabrique
     * donc aucun nom : sans utilisateur, la ligne le dit.
     *
     * Un compte technique sans fiche employé (import, job planifié) tombe sur
     * son `login` — identifiant réel et traçable, pas un libellé inventé.
     */
    private function auteur(?User $utilisateur): string
    {
        if ($utilisateur === null) {
            return __('rapports.entete.auteur_inconnu');
        }

        $employe = $utilisateur->employe;
        // `utilisateurs.role_id` est NOT NULL et protégé par `restrictOnDelete()` :
        // un compte a toujours un rôle, aucun repli n'a de sens ici.
        $role = $utilisateur->role->libelle;

        $nom = $employe === null
            ? $utilisateur->login
            : trim($employe->prenom . ' ' . $employe->nom);

        return trim($nom) . ' — ' . $role;
    }

    private function valeur(string $cle): string
    {
        $configuree = $this->parametres->get($cle);

        return filled($configuree) ? $configuree : self::DEFAUTS[$cle];
    }

    /**
     * Raison sociale et enseigne — directive PO du 02/09/2026, appliquée ICI
     * et nulle part ailleurs (l'en-tête a UN auteur, RG-19).
     *
     * Ligne 1 : « TATACORA AFRIQUE ». Ligne d'enseigne : « gîte chez noël »
     * EN MINUSCULES — la casse est la volonté du Product Owner, appliquée par
     * `mb_strtolower()` quel que soit ce qui est stocké.
     *
     * Si la raison sociale PARAMÉTRÉE porte l'enseigne après un tiret
     * (« TATACORA AFRIQUE — Gîte Chez Noël »), l'affichage est DÉRIVÉ par
     * séparation sur ce tiret plutôt qu'écrit en dur : le Gérant qui corrige
     * le paramètre corrige les deux lignes d'un seul geste. Sans tiret,
     * l'enseigne vient du repli `rapports.entete.enseigne`.
     *
     * @return array{0: string, 1: string} [raison sociale, enseigne en minuscules]
     */
    private function identite(): array
    {
        $brute = $this->valeur(self::CLE_RAISON_SOCIALE);

        // Tiret cadratin d'abord (la forme documentée), tiret simple entouré
        // d'espaces en secours — jamais le tiret nu, qui couperait un nom
        // composé comme « Sainte-Marie ».
        foreach ([' — ', '—', ' - '] as $separateur) {
            if (str_contains($brute, $separateur)) {
                [$raison, $enseigne] = explode($separateur, $brute, 2);

                return [trim($raison), mb_strtolower(trim($enseigne), 'UTF-8')];
            }
        }

        return [trim($brute), mb_strtolower((string) __('rapports.entete.enseigne'), 'UTF-8')];
    }

    /**
     * IFU / RCCM : jamais de repli. Vide = ligne absente du document.
     */
    private function mentionFiscale(string $cle): ?string
    {
        $valeur = $this->parametres->get($cle);

        return filled($valeur) ? $valeur : null;
    }

    /**
     * Le LIBELLÉ du régime fiscal, jamais son code stocké.
     *
     * La carte code => libellé vit sur la définition du registre
     * (`RegistreParametres`, `choixLibelles`) — un seul auteur, partagé avec
     * l'écran Paramètres. Un code inconnu rend `null` : imprimer un code
     * technique (`reel_normal`) sur un document remis dirait moins que rien.
     */
    private function regimeFiscal(): ?string
    {
        $code = $this->mentionFiscale(self::CLE_REGIME_FISCAL);

        if ($code === null) {
            return null;
        }

        $definition = RegistreParametres::definition(self::CLE_REGIME_FISCAL);

        if ($definition === null || ! in_array($code, $definition->choix, true)) {
            return null;
        }

        return $definition->libelleDuChoix($code);
    }

    /**
     * Chemin absolu du logo, ou `null` s'il n'est pas déployé.
     *
     * Un logo absent ne doit pas faire échouer l'édition d'un état : dompdf
     * lèverait sur un fichier introuvable, et un comptable perdrait son export
     * pour une image manquante. L'en-tête se rend alors sans logo.
     */
    private function logo(): ?string
    {
        // Le logo TÉLÉVERSÉ (onglet « Logo & Apparence », 02/09/2026) prime :
        // c'est la même préséance que la barre supérieure de la PWA, et les
        // deux la lisent au même service — jamais deux règles.
        $televerse = app(ApparenceEtablissementService::class)->cheminLogo();

        if ($televerse !== null) {
            return $televerse;
        }

        // Repli sur l'actif déployé, sous `assets/`. ⚠ Jusqu'au 02/09/2026 le
        // chemin du prototype (`public/img/logo.jpg`, absent de l'arbre public
        // de l'API) était seul essayé : AUCUN état n'a porté de logo, sans un
        // mot (famille PA-59/60/61). Depuis le 14/10/2026 (D392) le chemin
        // écrit est directement celui de l'actif réel.
        $chemin = public_path(self::CHEMIN_LOGO);

        return is_file($chemin) ? $chemin : null;
    }
}
