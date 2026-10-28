<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Transverse;

use App\Models\User;
use App\Shared\Audit\Models\JournalAudit as EntreeJournalAudit;
use App\Shared\Mail\Support\AdresseEmailFacultative;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;
use Illuminate\View\View;
use Livewire\Attributes\Title;

/**
 * Mon profil — maitre : `prototype_v2/pages/mon-profil.html`.
 *
 * Trois blocs dans l'ordre du maitre : les metadonnees de session (l.27-56),
 * la grille a deux colonnes « Informations personnelles » / « Modifier le mot
 * de passe » (l.58-142) et le journal d'audit personnel (l.144-166).
 *
 * ## DIRECTIVE DU PRODUCT OWNER (01/09/2026) : L'ECRAN DEVIENT EDITABLE
 *
 * Le regime qui refusait les deux formulaires est leve pour ce lot, mais pas
 * de la meme facon pour les deux : `changerMotDePasse()` est desormais une
 * ECRITURE REELLE sur `utilisateurs.mot_de_passe_hash`. « Informations
 * personnelles », elle, RESTE en lecture — pas par refus du canal (qui ecrit
 * desormais ailleurs sur ce depot), mais parce qu'aucune colonne de
 * `utilisateurs` ne porte ce que ce formulaire collecte : voir le bloc dedie
 * ci-dessous, qui distingue les deux raisons.
 *
 * ⚠ MIS À JOUR LE 28/10/2026 (décision du PO) : `utilisateurs.email` existe désormais,
 * FACULTATIF. Le champ « Email » est ÉDITABLE et « Enregistrer les informations »
 * est rendu (`enregistrerInformations()`, l'e-mail du compte courant seul). Seul
 * « Téléphone » reste « — » : ce qui suit, sur l'e-mail, est l'historique.
 *
 * ÉCART DÉLIBÉRÉ — `mon-profil.html` l.61-97 (« Informations personnelles »)
 * Le maitre : quatre champs de saisie — « Nom complet », « Email »,
 * « Téléphone », « Fonction » (deja `readonly` au maitre) — et un bouton
 * « Enregistrer les informations ».
 * Ici : les quatre intitules sont conserves, en LECTURE. « Nom complet » et
 * « Fonction » portent une valeur reelle ; « Email » et « Téléphone » portent
 * « — » et disent pourquoi ; le bouton n'existe pas.
 * Raison, revue le 01/09/2026 — UNE seule raison desormais : `utilisateurs`
 * ne porte NI nom, NI email, NI telephone ; elle porte `login`,
 * `mot_de_passe_hash`, `role_id`, `statut` et `derniere_connexion` (verifie
 * contre `2026_08_01_000020_create_utilisateurs.php` le 01/09/2026). Le nom
 * et la fonction viennent donc de la fiche EMPLOYE rattachee
 * (`employes.nom`, `employes.prenom`, `employes.poste`), qui est nullable au
 * schema : un compte technique n'a pas de fiche RH, et rend « — » plutot
 * qu'un nom fabrique. L'email et le telephone n'existent NULLE PART dans ce
 * depot — ni sur `utilisateurs`, ni sur `employes`. Les rendre en cases
 * vides laisserait croire a un renseignement oublie, alors que la colonne
 * n'existe pas : c'est la difference entre « — » et « 0 » de l'Article 7,
 * portee au schema, et elle est ecrite a l'ecran. « Nom complet »/
 * « Fonction » ne sont pas rendus editables non plus, quoique reels : ce
 * sont des attributs de la fiche RH, pas du compte d'acces, et cet ecran ne
 * porte aucune ecriture sur `employes`.
 *
 * ÉCART LEVE — `mon-profil.html` l.99-141 (« Modifier le mot de passe »)
 * Le maitre : trois champs — « Ancien mot de passe », « Nouveau mot de
 * passe », « Confirmer le nouveau mot de passe » —, une jauge de robustesse et
 * un bouton « Mettre à jour le mot de passe ». Le maitre ecrit lui-meme
 * (l.135) : « Maquette : aucun mot de passe n'est stocke ni compare ici. »
 * Ici : les trois champs et le bouton SONT rendus, derriere une modale
 * (`etatFormulaire === 'mot_de_passe'`), jamais au premier GET
 * (`RefuseLaSaisie` : aucun `type="password"` hors du verrou de session ne
 * doit apparaitre avant l'ouverture). C'est un ecart de MECANISME, pas de
 * contenu — meme raison que chaque autre formulaire d'ecriture de ce depot.
 * `changerMotDePasse()` verifie l'ancien mot de passe par `Auth::validate()`
 * (meme mecanisme que `VerrouSession::deverrouiller()`, jamais
 * `Auth::attempt()`, qui regenererait la session), exige la confirmation a
 * l'identique, refuse un mot de passe identique a l'ancien, hache avec
 * `Hash::make()` et NE TOUCHE JAMAIS a la session : aucun `Auth::logout()`,
 * aucune regeneration — l'utilisateur reste connecte apres son propre
 * changement de mot de passe. La jauge de robustesse du maitre n'est PAS
 * portee (ecart mineur assume) : la regle affichee (min. 8 caracteres) reste
 * la seule contrainte, verifiee reellement cote serveur.
 *
 * ## Aucun droit de module n'encadre `changerMotDePasse()`, et c'est voulu
 *
 * Cette page ne porte AUCUN `data-module` (voir plus bas) : elle n'agit que
 * sur le compte du demandeur lui-meme. Exiger un niveau RBAC sur un module
 * metier pour changer SON PROPRE mot de passe enfermerait dehors, mot de
 * passe compris, un utilisateur dont la matrice de droits est mal
 * configuree — meme famille que `Connexion::seConnecter()` et
 * `VerrouSession::deverrouiller()` (`PwaEcritureAutoriseeTest::
 * ECRITURES_HORS_MODULE` / `METHODES_DE_LECTURE`).
 *
 * ## Ce qui EST rendu vient du serveur, pas du navigateur
 *
 * ÉCART DÉLIBÉRÉ — `mon-profil.html` l.42-45 (« Adresse IP du poste »)
 * Le maitre : l'adresse relevee par le poste, et il ecrit lui-meme (l.53) :
 * « Sur l'application reelle elle vient du serveur : une adresse declaree par
 * le navigateur ne prouve rien et ne doit jamais servir de controle
 * d'acces. »
 * Ici : l'adresse vue par le SERVEUR (`request()->ip()`), c'est-a-dire la
 * remarque du maitre appliquee. C'est un ecart qui va dans le sens de la
 * maquette, pas contre elle.
 *
 * ÉCART DÉLIBÉRÉ — `mon-profil.html` l.47-50 (« Statut du compte »)
 * Le maitre : « Actif », ecrit en dur, en vert.
 * Ici : le statut REEL de `utilisateurs.statut`, avec sa couleur.
 * Raison : Article 6, deuxieme interdit — un badge ecrit en dur dans le HTML
 * ne se porte jamais. Un compte suspendu qui lirait « Actif » sur sa propre
 * fiche chercherait la panne ailleurs.
 *
 * ÉCART DÉLIBÉRÉ — `mon-profil.html` l.153 (colonne « MODULE »)
 * Le maitre : le module d'origine de chaque action tracee.
 * Ici : l'entite concernee, telle que `journal_audit` la porte.
 * Raison : le registre n'a aucune colonne de module. Deduire le module d'un
 * nom de table demanderait une table de passage table -> module, ecrite ici et
 * nulle part ailleurs — une seconde source de verite sur le decoupage
 * fonctionnel, qui divergerait au premier module ajoute. C'est exactement ce
 * que le maitre lui-meme refuse a propos de sa grille de modules
 * (`aide-a-propos.html` l.238).
 *
 * ## Aucun droit de module sur cette page, et c'est le maitre
 *
 * `mon-profil.html` ne porte AUCUN `data-module` sur son `<body>` — verifie le
 * 27/08/2026 —, la ou `roles-permissions.html` porte `ROLES` et
 * `parametres.html` porte `PARAM`. La page ne montre que les donnees du
 * demandeur : son login, son role, sa derniere connexion, ses propres traces.
 * Un profil qui ne pourrait pas consulter sa propre fiche n'aurait aucun moyen
 * de verifier sous quelle identite il est connecte.
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
 * Refus declares :
 *   maitre-refuse:mon-profil.html#enregistrer-infos
 *   maitre-refuse:mon-profil.html#email-telephone
 *   maitre-refuse:mon-profil.html#module
 * @see RG-15 Traçabilité des actions sensibles
 * @see LARAVEL_PWA.md §1, §6
 */
#[Title('Mon profil — LogiReStock — TATACORA AFRIQUE')]
class MonProfil extends PageTransverse
{
    /**
     * Le maitre titre « Journal d'audit — 10 dernières actions » (l.148). Le
     * nombre est donc porte ici, et le titre le lit : deux endroits ou ecrire
     * « 10 » finiraient par ne plus dire la meme chose.
     */
    public const DERNIERES_ACTIONS = 10;

    /**
     * Les statuts de `utilisateurs.statut` et leur couleur.
     *
     * Registre FERME : un statut ajoute demain a l'`enum` serait rendu en
     * clair plutot que colore au hasard — jamais un comportement par omission.
     *
     * @var array<string, array{libelle: string, couleur: string}>
     */
    public const STATUTS = [
        'actif' => ['libelle' => 'Actif', 'couleur' => 'var(--succes)'],
        'suspendu' => ['libelle' => 'Suspendu', 'couleur' => 'var(--gold)'],
        'desactive' => ['libelle' => 'Désactivé', 'couleur' => 'var(--erreur)'],
    ];

    /**
     * Le formulaire ouvert — `null` : aucun. UN seul formulaire sur cet
     * ecran (« mot_de_passe »), meme convention que `FormulaireModal`
     * ailleurs dans la PWA, mais ecrite a la main ici : ce trait exige un
     * `MODULE` RBAC, et cette ecriture n'en a delibrement aucun (voir
     * l'entete).
     */
    public ?string $etatFormulaire = null;

    /**
     * L'e-mail FACULTATIF du compte (28/10/2026, décision du PO) : le champ
     * « Email » des informations personnelles, seul champ du bloc que le compte
     * porte lui-même (`utilisateurs.email`). Destinataire des notifications
     * e-mail adressées à ce compte ; vide = non renseigné.
     */
    public string $emailSaisi = '';

    public string $ancienMotDePasse = '';

    public string $nouveauMotDePasse = '';

    public string $confirmationMotDePasse = '';

    public function mount(): void
    {
        $this->emailSaisi = (string) Auth::user()?->email;
    }

    /**
     * Les phrases de refus de l'e-mail facultatif — celles du poste, mot pour mot.
     *
     * @return array<string, string>
     */
    protected function messages(): array
    {
        return [
            'emailSaisi.email' => __('rh_pwa.email_invalide'),
            'emailSaisi.max' => __('rh_pwa.email_invalide'),
            'emailSaisi.not_regex' => __('rh_pwa.email_invalide'),
        ];
    }

    /**
     * « Enregistrer les informations » — écrit l'e-mail du compte COURANT, et
     * lui seul (jamais celui d'un tiers). Même famille que `changerMotDePasse()` :
     * aucun module RBAC, le geste ne porte que sur le compte qui le fait.
     *
     * Facultatif : vide efface l'adresse. Normalisé (trim, minuscules) puis
     * validé comme la fiche employé (`AdresseEmailFacultative`) ; aucune
     * unicité imposée.
     */
    public function enregistrerInformations(): void
    {
        /** @var User|null $utilisateur */
        $utilisateur = Auth::user();

        if ($utilisateur === null) {
            abort(401, __('auth.requise'));
        }

        $this->emailSaisi = (string) AdresseEmailFacultative::normaliser($this->emailSaisi);

        $donnees = $this->validate(['emailSaisi' => AdresseEmailFacultative::REGLES]);

        $utilisateur->update(['email' => AdresseEmailFacultative::normaliser($donnees['emailSaisi'])]);

        session()->flash('pwa-succes', __('rh_pwa.email_enregistre'));
    }

    /**
     * Ouvre la modale « Modifier le mot de passe ». N'ecrit rien : remet la
     * saisie et les erreurs a zero, comme `FormulaireModal::ouvrirFormulaire()`
     * le fait ailleurs — inscrite en LECTURE (`METHODES_DE_LECTURE`), meme
     * famille que `fermerModales`.
     */
    public function ouvrirFormulaireMotDePasse(): void
    {
        $this->reset(['ancienMotDePasse', 'nouveauMotDePasse', 'confirmationMotDePasse']);
        $this->resetValidation();
        $this->etatFormulaire = 'mot_de_passe';
    }

    public function fermerModales(): void
    {
        $this->etatFormulaire = null;
        $this->reset(['ancienMotDePasse', 'nouveauMotDePasse', 'confirmationMotDePasse']);
        $this->resetValidation();
    }

    /**
     * Change le mot de passe du compte COURANT.
     *
     * Ordre des controles, et pourquoi : la forme d'abord (obligatoire,
     * longueur), puis la confirmation (une faute de frappe ne merite pas de
     * consommer une tentative de l'ancien mot de passe), puis l'ancien mot
     * de passe REELLEMENT verifie par `Auth::validate()` — jamais
     * `Auth::attempt()`, qui regenererait la session Livewire en vol. Rien
     * n'est ecrit avant cette verification.
     */
    public function changerMotDePasse(): void
    {
        /** @var User|null $utilisateur */
        $utilisateur = Auth::user();

        if ($utilisateur === null) {
            abort(401, __('auth.requise'));
        }

        $donnees = $this->validate([
            'ancienMotDePasse' => ['required', 'string'],
            'nouveauMotDePasse' => ['required', 'string', 'min:8'],
            'confirmationMotDePasse' => ['required', 'string'],
        ]);

        if ($donnees['nouveauMotDePasse'] !== $donnees['confirmationMotDePasse']) {
            $this->addError('confirmationMotDePasse', __('pwa.profil.mdp_confirmation_invalide'));

            return;
        }

        if ($donnees['nouveauMotDePasse'] === $donnees['ancienMotDePasse']) {
            $this->addError('nouveauMotDePasse', __('pwa.profil.mdp_identique'));

            return;
        }

        $valide = Auth::validate([
            'login' => $utilisateur->login,
            'password' => $donnees['ancienMotDePasse'],
        ]);

        // Le mot de passe soumis ne survit jamais a l'echec de sa propre
        // verification, meme famille que `VerrouSession::deverrouiller()`.
        $this->reset(['ancienMotDePasse', 'nouveauMotDePasse', 'confirmationMotDePasse']);

        if (! $valide) {
            $this->addError('ancienMotDePasse', __('pwa.profil.mdp_ancien_invalide'));
            $this->etatFormulaire = 'mot_de_passe';

            return;
        }

        $utilisateur->forceFill(['mot_de_passe_hash' => Hash::make($donnees['nouveauMotDePasse'])])->save();

        // Ni `Auth::logout()`, ni regeneration de session : l'utilisateur
        // reste connecte apres avoir change son propre mot de passe.
        $this->etatFormulaire = null;
        session()->flash('pwa-succes', __('pwa.profil.mdp_mise_a_jour'));
    }

    public function render(): View
    {
        /** @var User|null $utilisateur */
        $utilisateur = Auth::user();

        /** @var Collection<int, EntreeJournalAudit> $traces */
        $traces = $utilisateur === null
            ? new Collection()
            : EntreeJournalAudit::query()
                ->where('utilisateur_id', $utilisateur->id)
                ->orderByDesc('date_heure')
                ->limit(self::DERNIERES_ACTIONS)
                ->get();

        // La fiche RH rattachee, si le compte en a une. `utilisateurs.employe_id`
        // est nullable au schema : un compte technique n'en a pas, et c'est un
        // « — », jamais un nom fabrique (Article 7).
        $employe = $utilisateur?->employe;

        return view('pwa.transverse.mon-profil', array_merge($this->socle(), [
            'traces' => $traces,
            // `statut` n'est pas nullable au schema : c'est l'UTILISATEUR qui
            // peut manquer, pas son statut. Un statut hors du registre ferme
            // rend `null` et l'ecran l'affiche EN CLAIR — jamais une couleur
            // choisie au hasard pour une valeur qu'on n'a pas comprise.
            'statut' => $utilisateur === null ? null : (self::STATUTS[$utilisateur->statut] ?? null),
            'nomComplet' => $employe === null ? null : trim($employe->prenom.' '.$employe->nom),
            'fonction' => $employe?->poste,
            // L'adresse vue par le SERVEUR — la remarque du maitre appliquee.
            'adressePoste' => request()->ip(),
        ]))->layout('layouts.pwa', ['title' => __('pwa.profil.titre_page')]);
    }
}
