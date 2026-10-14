<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Transverse;

use App\Models\User;
use App\Shared\ContactEditeur\Models\MessageEditeur;
use App\Shared\ContactEditeur\Services\MessageEditeurService;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Facades\Auth;
use Illuminate\View\View;
use Livewire\Attributes\Title;
use Livewire\WithFileUploads;

/**
 * Contactez l'éditeur — maitre : `prototype_v2/pages/contact-editeur.html`.
 *
 * ## DIRECTIVE DU PRODUCT OWNER (01/09/2026) : LES DEUX FORMULAIRES ÉCRIVENT
 *
 * `envoyerMessage()`/`signalerBug()` avaient été SUPPRIMÉS le 31/08/2026 :
 * ils écrivaient dans une table `messages_editeur` qui n'existait NULLE
 * PART, `Schema::hasTable()` rendait toujours `false`, et pourtant l'écran
 * annonçait « Votre message a été transmis à l'éditeur ». PA-59/60/61 sous
 * sa forme la plus directe.
 *
 * La table existe désormais (`2026_09_04_100000_create_messages_editeur`),
 * `MessageEditeurService` en est l'unique auteur, et les deux formulaires du
 * maître SONT rendus — chacun derrière une modale
 * (`etatFormulaire === 'message'|'bug'`), jamais au premier GET
 * (`RefuseLaSaisie`). C'est un écart de MÉCANISME, pas de contenu : le
 * maître pose ses deux panneaux en permanence dans le DOM, basculés par des
 * onglets CSS ; ici les deux boutons d'onglet restent visibles et cliquables
 * dès le premier rendu, mais ouvrent une modale au lieu de découvrir un
 * panneau déjà présent — même raison que chaque autre formulaire d'écriture
 * de ce dépôt.
 *
 * ## Aucun droit de module n'encadre ces deux écritures, et c'est voulu
 *
 * `contact-editeur.html` ne porte AUCUN `data-module` : contacter l'éditeur
 * ou signaler un bug n'est pas une opération sur un module métier, c'est un
 * geste que TOUT compte authentifié doit pouvoir faire, y compris un rôle
 * dont la matrice de droits est mal configurée — c'est précisément le genre
 * de compte qui a le plus besoin de pouvoir signaler un problème.
 * `envoyerMessage()`/`signalerBug()` sont donc inscrites dans
 * `PwaEcritureAutoriseeTest::ECRITURES_HORS_MODULE`, jamais gardées par
 * `exigerEcriture()` — même famille que `MonProfil::changerMotDePasse()`.
 *
 * ## L'envoi SMTP est TENTÉ, jamais affirmé
 *
 * `MessageEditeurService::enregistrer()` n'écrit `statut = transmis` que si
 * `Mail::raw()` a réellement réussi. Sans configuration mail réelle (mailer
 * `log`/`array`/`null`, ou `smtp` sans hôte — l'état de ce dépôt en
 * développement), l'enregistrement reste `a_transmettre`, et l'écran l'AFFICHE
 * ainsi : aucune section de refus ne le cache, la colonne « Statut » de
 * « Vos envois » dit la vérité mesurée, pas une promesse.
 *
 * ## Ce qui n'est PAS porté — Article 8
 *
 * ÉCART DÉLIBÉRÉ — `contact-editeur.html` l.148-176 (encart bleu « Sur cette
 * maquette »)
 * Le maître : « Aucun message n'est réellement transmis… ».
 * Ici : non rendu.
 * Raison : la phrase est FAUSSE depuis ce lot — un message est réellement
 * enregistré, et réellement transmis quand la configuration mail le permet.
 * La reproduire mentirait dans l'autre sens.
 *
 * ÉCART DÉLIBÉRÉ — `contact-editeur.html` l.194-203 (« Ce qui accompagne
 * votre envoi »)
 * Le maître : trois puces (nom/rôle, page d'origine, version/navigateur).
 * Ici : NON jointes — voir le bloc dédié plus bas.
 * Raison : « la page depuis laquelle vous écrivez » et « la version du
 * logiciel et le navigateur » sont des faits du POSTE CLIENT, jamais vérifiés
 * côté serveur ; les joindre sans les vérifier reviendrait à afficher une
 * déclaration du navigateur comme un fait (même famille que l'adresse IP de
 * `MonProfil`, où c'est le serveur qui fait foi). L'auteur RÉEL, lui, EST
 * joint — automatiquement, par `Auditable` (`utilisateur_creation_id`), donc
 * jamais une valeur déclarée par le client.
 *
 * Refus déclarés :
 *   maitre-refuse:contact-editeur.html#maquette-encart
 *   maitre-refuse:contact-editeur.html#contexte-navigateur
 * @see RG-15 Traçabilité des actions sensibles
 * @see LARAVEL_PWA.md §1, §3
 */
#[Title("Contactez l'éditeur — TATACORA AFRIQUE")]
class ContactEditeur extends PageTransverse
{
    use WithFileUploads;

    /**
     * Les dix-neuf entrées du sélecteur « Module concerné » du maître
     * (l.234-242) — registre FERMÉ, valeurs identiques (chaîne = libellé =
     * valeur soumise, comme au maître). Ni FK ni code : aucune table ne
     * référence un « module concerné » d'un signalement, et deux entrées
     * (« Connexion / navigation générale », « Autre / je ne sais pas ») ne
     * désignent aucun module RBAC.
     *
     * @var list<string>
     */
    public const MODULES = [
        'M1 — Hébergement & Réservations', 'M2 — Facturation', 'M3 — Clients & Créances',
        'M4 — Restaurant', 'M5 — Bar & Point de vente', 'M6 — Stocks',
        'M7 — Achats & Fournisseurs', 'M8 — Véhicules & Locations', 'M9 — Tourisme',
        'M10 — Comptabilité SYSCOHADA', 'M11 — Tableau de bord', 'M12 — Notifications',
        'M13 — Personnel & Paie', 'M14 — États & Rapports',
        'Rôles & Permissions', 'Paramètres', 'Import & Export',
        'Connexion / navigation générale', 'Autre / je ne sais pas',
    ];

    /** 2 Mo — même limite que le maître (l.331). */
    public const CAPTURE_MAX_KO = 2048;

    /** Le formulaire ouvert — `null` : aucun. */
    public ?string $etatFormulaire = null;

    // ------------------------------------------------- « Envoyer un message »
    public string $objetMessage = '';

    public string $corpsMessage = '';

    // --------------------------------------------------- « Signaler un bug »
    public string $moduleBug = '';

    public string $descriptionBug = '';

    public string $etapesBug = '';

    /** @var \Livewire\Features\SupportFileUploads\TemporaryUploadedFile|null */
    public $captureBug = null;

    public function ouvrirFormulaireMessage(): void
    {
        $this->reset(['objetMessage', 'corpsMessage']);
        $this->resetValidation();
        $this->etatFormulaire = 'message';
    }

    public function ouvrirFormulaireBug(): void
    {
        $this->reset(['moduleBug', 'descriptionBug', 'etapesBug', 'captureBug']);
        $this->resetValidation();
        $this->etatFormulaire = 'bug';
    }

    public function fermerModales(): void
    {
        $this->etatFormulaire = null;
        $this->resetValidation();
    }

    public function envoyerMessage(MessageEditeurService $service): void
    {
        $donnees = $this->validate([
            'objetMessage' => ['required', 'string', 'max:255'],
            'corpsMessage' => ['required', 'string', 'max:4096'],
        ]);

        $message = $service->enregistrer([
            'type' => MessageEditeur::TYPE_MESSAGE,
            'objet' => (string) $donnees['objetMessage'],
            'module_concerne' => null,
            'corps' => (string) $donnees['corpsMessage'],
            'etapes' => null,
            'capture_nom' => null,
            'capture_chemin' => null,
        ]);

        $this->etatFormulaire = null;
        session()->flash('pwa-succes', $message->estTransmis()
            ? __('pwa.contact.message_envoye')
            : __('pwa.contact.envoi_en_attente'));
    }

    public function signalerBug(MessageEditeurService $service): void
    {
        $donnees = $this->validate([
            'moduleBug' => ['required', 'string', 'in:' . implode(',', self::MODULES)],
            'descriptionBug' => ['required', 'string', 'max:4096'],
            'etapesBug' => ['nullable', 'string', 'max:4096'],
            'captureBug' => ['nullable', 'image', 'mimes:png,jpg,jpeg', 'max:' . self::CAPTURE_MAX_KO],
        ]);

        $captureNom = null;
        $captureChemin = null;

        if ($this->captureBug !== null) {
            $captureNom = $this->captureBug->getClientOriginalName();
            $chemin = $this->captureBug->store('captures_bug', 'public');
            $captureChemin = is_string($chemin) ? $chemin : null;
        }

        $message = $service->enregistrer([
            'type' => MessageEditeur::TYPE_BUG,
            'objet' => __('pwa.contact.bug_objet', ['module' => (string) $donnees['moduleBug']]),
            'module_concerne' => (string) $donnees['moduleBug'],
            'corps' => (string) $donnees['descriptionBug'],
            'etapes' => filled($donnees['etapesBug']) ? (string) $donnees['etapesBug'] : null,
            'capture_nom' => $captureNom,
            'capture_chemin' => $captureChemin,
        ]);

        $this->etatFormulaire = null;
        session()->flash('pwa-succes', $message->estTransmis()
            ? __('pwa.contact.bug_signale')
            : __('pwa.contact.envoi_en_attente'));
    }

    public function render(): View
    {
        /** @var User|null $utilisateur */
        $utilisateur = Auth::user();

        /** @var Collection<int, MessageEditeur> $envois */
        $envois = $utilisateur === null
            ? new Collection()
            : MessageEditeur::query()
                ->where('utilisateur_creation_id', $utilisateur->id)
                ->orderByDesc('date_creation')
                ->limit(50)
                ->get();

        return view('pwa.transverse.contact-editeur', array_merge($this->socle(), [
            'titrePage' => __('pwa.contact.titre'),
            'envois' => $envois,
        ]))->layout('layouts.pwa', ['title' => __('pwa.contact.titre') . ' — ' . __('pwa.marque')]);
    }
}
