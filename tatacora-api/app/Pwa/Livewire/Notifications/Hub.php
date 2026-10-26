<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Notifications;

use App\Domain\Notifications\Models\MessageNotificationCompose;
use App\Domain\Notifications\Models\ModeleNotification;
use App\Domain\Notifications\Services\EnvoiEmailNotificationService;
use App\Domain\Notifications\Services\FileAttenteNotificationsService;
use App\Domain\Notifications\Services\ModeleNotificationService;
use App\Domain\Notifications\Services\RegistreCanaux;
use App\Domain\Notifications\Services\RegistreDeclencheurs;
use App\Exports\NotificationsExport;
use App\Models\User;
use App\Pwa\Livewire\Concerns\FormulaireModal;
use App\Pwa\Livewire\PageMetier;
use App\Shared\Mail\Services\ConfigurationMailService;
use Barryvdh\DomPDF\Facade\Pdf;
use Illuminate\Database\Eloquent\Collection as EloquentCollection;
use Illuminate\Support\Collection;
use Illuminate\View\View;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use Maatwebsite\Excel\Facades\Excel;
use RuntimeException;

/**
 * M12 — Notifications, en ÉCRITURE sur le RÉFÉRENTIEL **et sur la FILE
 * D'ATTENTE** depuis le 01/09/2026 (directive du Product Owner).
 *
 * Maître : `prototype_v2/pages/m12-notifications-hub.html` et son moteur
 * `prototype_v2/assets/js/notifications-engine.js`.
 *
 * ## Ce que cet écran fait réellement
 *
 * Il tient le référentiel des notifications : les modèles de message (créés,
 * modifiés, activés, désactivés), le registre fermé des événements
 * déclencheurs, le registre fermé des canaux avec ce qui bloque chacun, et le
 * journal des envois — lu sur `notifications_envoyees`, la table réelle.
 *
 * ## La FILE D'ATTENTE (01/09/2026) — cinq déclencheurs sur neuf, réellement détectés
 *
 * « Détecter maintenant » appelle `FileAttenteNotificationsService::
 * detecter()`, qui interroge les vraies données du jour via les classes de
 * `Domain/Notifications/Detecteurs/` (RÉFÉRENCÉES par
 * `RegistreDeclencheurs::detecteur()`) et COMPOSE réellement chaque message
 * — vraies dates, vrais noms, vrais montants — avant de le mettre en file.
 * « Transmis à la main » et « Abandonner » SONT réels : le premier exige un
 * commentaire optionnel et enregistre l'auteur (colonnes d'audit du dépôt,
 * `MessageNotificationCompose::traitePar()`), le second exige un motif.
 *
 * **`declencheur.creance_echue`/`creance_douteuse` (M3), `stock_sous_seuil`
 * (M6) et `depart_circuit_demain` (M9) restent NON DÉTECTÉS** — chacun a SA
 * raison, datée, dans `RegistreDeclencheurs` : les deux premiers parce que
 * PA-20 (balance âgée) n'est toujours pas arbitrée côté serveur, les deux
 * derniers parce que Stocks et Tourisme étaient modifiés en parallèle par
 * d'autres agents au moment de ce lot. Un modèle actif sur l'un de ces
 * quatre déclencheurs reste visible partout ailleurs (Modèles, Déclencheurs)
 * ; il ne compose simplement jamais de message.
 *
 * ## « Envoyer » est RÉEL par e-mail depuis le 01/09/2026 — directive du PO
 *
 * « Pour le moment utilise le SMTP » : `envoyerMessage()` tente un envoi
 * RÉEL via `EnvoiEmailNotificationService` quand — et seulement quand — le
 * message est sur le canal e-mail, qu'une adresse réelle a été résolue par
 * le détecteur qui l'a composé (`email_destinataire`), et qu'un mailer
 * réellement configuré existe (`ConfigurationMailService`, le même contrôle
 * que « Contactez l'éditeur », PA-159). Sans l'une des deux conditions, le
 * bouton « Envoyer » n'apparaît même pas : la raison est affichée à sa place,
 * jamais un bouton grisé (Article 3.3).
 *
 * WhatsApp, Android et SMS restent SANS ce geste : l'API WhatsApp Business
 * n'est pas contractée, l'application Flutter qui porterait le canal Android
 * n'enregistre aucun appareil, et aucun agrégateur SMS n'est retenu. RG-20
 * (diffusion automatique) reste non implémentée pour ces trois canaux — une
 * dépendance externe, pas un développement — et leur ligne de la file porte
 * l'étiquette « à paramétrer au déploiement » à la place du bouton.
 *
 * Le maître écrit la conséquence en tête de son moteur : « un message marqué
 * "envoyé" alors que rien n'est parti est pire que pas de module du tout : le
 * Gérant croit son client prévenu, et il ne l'est pas ». C'est PA-59/60/61 —
 * et c'est pour cela qu'un échec d'envoi (transport injoignable, adresse ou
 * configuration absente) laisse le message EN FILE, jamais un statut qui
 * affirmerait un départ que rien n'a vérifié. « Transmis à la main »/
 * « Abandonner » continuent de ne JAMAIS toucher `notifications_envoyees` :
 * cette table porte désormais aussi les envois e-mail RÉELLEMENT acceptés
 * par le transport, jamais un geste d'écran qui n'a pas réellement délivré.
 *
 * ## Le compteur « Réellement envoyés » est COMPTÉ, pas posé
 *
 * `ModeleNotificationService::nombreEnvoisReels()` interroge la table. Il vaut
 * zéro aujourd'hui parce que rien n'y écrit, pas parce qu'une constante le
 * dit — la nuance est celle du badge MECeF, qui serait passé au vert le jour
 * de l'inscription DGI pendant que chaque facture partait encore en
 * démonstration (PA-61).
 *
 * ## Exporter est une LECTURE
 *
 * `ouvrirExport()` et `genererExport()` n'exigent aucun droit d'écriture : un
 * export ne produit rien de neuf, il rend sur un autre papier ce que l'écran
 * affiche déjà, et le droit de lire est porté par `module:M12,L` sur la route.
 * L'export porte sur CE QUI EST AFFICHÉ et DIT son filtre (PA-119).
 *
 * @see RG-20 Diffusion automatique des notifications (non implémentée)
 * @see EF-M12-01 Modèles de notification paramétrables par événement et canal
 * @see LARAVEL_PWA.md §3, §5
 * @see DIRECTIVE_CONFORMITE_100.md Articles 3.3, 4, 7
 */
#[Layout('layouts.pwa')]
#[Title('Notifications — TATACORA AFRIQUE')]
class Hub extends PageMetier
{
    use FormulaireModal;

    /** Le module RBAC de l'écran — `data-module="M12"` au maître. */
    public const MODULE = 'M12';

    /**
     * Les cinq onglets du maître, TOUS rendus depuis le 01/09/2026.
     *
     * Le jeton `maitre-refuse:m12-notifications-hub.html#bouton-envoyer` est
     * RETIRÉ le 01/09/2026 : le bouton « Envoyer » du maître est désormais
     * rendu, réellement, pour le canal e-mail. Le laisser aurait transformé
     * une fonction levée en refus toujours affirmé (même défaut que PA-107/
     * 120/144 : un motif de refus périmé devient un oubli).
     */
    public const ONGLETS = ['file', 'modeles', 'declencheurs', 'journal', 'canaux'];

    // ---------------------------------------------------------------- filtres

    #[Url(as: 'onglet')]
    public string $onglet = 'file';

    #[Url(as: 'q')]
    public string $recherche = '';

    #[Url(as: 'canal')]
    public string $filtreCanal = '';

    #[Url(as: 'public')]
    public string $filtrePublic = '';

    #[Url(as: 'etat')]
    public string $filtreEtat = '';

    // -------------------------------------------------- formulaire « modèle »

    public ?string $modeleId = null;

    public string $declencheurSaisi = '';

    public string $canalSaisi = RegistreCanaux::WHATSAPP;

    public string $objetSaisi = '';

    public string $contenuSaisi = '';

    public bool $actifSaisi = true;

    // ------------------------------------------- file d'attente — transmission

    public ?string $messageId = null;

    public string $commentaireTransmission = '';

    public string $motifAbandon = '';

    // -------------------------------------------------------------- export

    public string $formatExport = 'pdf';

    /**
     * @return array<string, list<string>>
     */
    protected function formulaires(): array
    {
        return [
            'modele' => [
                'modeleId', 'declencheurSaisi', 'canalSaisi',
                'objetSaisi', 'contenuSaisi', 'actifSaisi',
            ],
            'transmission' => ['messageId', 'commentaireTransmission'],
            'abandon' => ['messageId', 'motifAbandon'],
            'export' => ['formatExport'],
        ];
    }

    // =====================================================================
    // Écritures — la file d'attente (01/09/2026)
    // =====================================================================

    /**
     * « Détecter maintenant » — compose réellement les messages du jour et
     * les met en file. N'envoie RIEN (voir l'en-tête de la classe).
     */
    public function detecterMaintenant(FileAttenteNotificationsService $service): void
    {
        $this->exigerEcriture(self::MODULE);

        $resultat = $service->detecter();

        session()->flash('pwa-succes', $resultat['composes'] > 0
            ? __('notifications_pwa.detection_resultat', ['nombre' => $resultat['composes']])
            : __('notifications_pwa.detection_aucun'));

        foreach ($resultat['echecs'] as $echec) {
            $this->addError('detection', $echec['modele'] . ' : ' . $echec['motif']);
        }

        $this->onglet = 'file';
    }

    /**
     * Ouvre la modale « Message transmis hors du système ».
     */
    public function ouvrirTransmission(string $messageId): void
    {
        $this->ouvrirFormulaire('transmission');
        $this->messageId = $messageId;
    }

    public function enregistrerTransmission(FileAttenteNotificationsService $service): void
    {
        $donnees = $this->validerEcriture([
            'messageId' => ['required', 'string'],
            'commentaireTransmission' => ['nullable', 'string', 'max:500'],
        ]);

        $message = MessageNotificationCompose::findOrFail($donnees['messageId']);

        try {
            $service->marquerTraite($message, $donnees['commentaireTransmission'] ?: null);
        } catch (RuntimeException $refus) {
            $this->addError('messageId', $refus->getMessage());

            return;
        }

        $this->terminerFormulaire(__('notifications_pwa.transmission_faite'));
    }

    /**
     * « Envoyer » — RÉEL par e-mail depuis le 01/09/2026 (directive du
     * Product Owner : « pour le moment utilise le SMTP »). Voir
     * `EnvoiEmailNotificationService` pour les deux conditions et ce que
     * chaque issue écrit (ou n'écrit pas).
     *
     * `exigerEcriture()` est appelé DIRECTEMENT — cette action ne délègue à
     * aucun geste déjà gardé du motif `FormulaireModal`, contrairement à
     * `enregistrerTransmission()`/`enregistrerAbandon()`.
     */
    public function envoyerMessage(string $messageId, EnvoiEmailNotificationService $service): void
    {
        $this->exigerEcriture(self::MODULE);

        $message = MessageNotificationCompose::findOrFail($messageId);

        try {
            // « Renvoyer » après épuisement des relances : le compteur repart.
            if ($message->enEchec()) {
                $service->remettreEnFile($message);
                $message->refresh();
            }

            $resultat = $service->envoyer($message);
        } catch (RuntimeException $refus) {
            session()->flash('pwa-erreur', $refus->getMessage());

            return;
        }

        if ($resultat['envoye']) {
            session()->flash('pwa-succes', __('notifications_pwa.envoi_reussi'));

            return;
        }

        // Aucune écriture n'a eu lieu : le message reste en file. La raison
        // EST affichée — jamais un échec silencieux (PA-59/60/61).
        session()->flash('pwa-erreur', $resultat['motif']);
    }

    /**
     * Ouvre la modale « Abandonner ce message ».
     */
    public function ouvrirAbandon(string $messageId): void
    {
        $this->ouvrirFormulaire('abandon');
        $this->messageId = $messageId;
    }

    public function enregistrerAbandon(FileAttenteNotificationsService $service): void
    {
        $donnees = $this->validerEcriture([
            'messageId' => ['required', 'string'],
            'motifAbandon' => ['required', 'string', 'max:500'],
        ]);

        $message = MessageNotificationCompose::findOrFail($donnees['messageId']);

        try {
            $service->abandonner($message, (string) $donnees['motifAbandon']);
        } catch (RuntimeException $refus) {
            $this->addError('motifAbandon', $refus->getMessage());

            return;
        }

        $this->terminerFormulaire(__('notifications_pwa.abandon_fait'));
    }

    // =====================================================================
    // Écritures — le référentiel des modèles
    // =====================================================================

    /**
     * Ouvre « Nouveau modèle » ou « Modifier le modèle ».
     *
     * Le droit est exigé à l'OUVERTURE par `ouvrirFormulaire()` : présenter un
     * formulaire à quelqu'un qui ne pourra pas l'enregistrer lui fait perdre
     * sa saisie et ne lui apprend rien.
     */
    public function ouvrirFormulaireModele(?string $modeleId = null): void
    {
        $this->ouvrirFormulaire('modele');

        if ($modeleId === null) {
            $this->declencheurSaisi = RegistreDeclencheurs::codes()[0];
            $this->canalSaisi = RegistreCanaux::WHATSAPP;
            $this->actifSaisi = true;

            return;
        }

        $modele = ModeleNotification::findOrFail($modeleId);

        $this->modeleId = $modele->getKey();
        $this->declencheurSaisi = $modele->evenement;
        $this->canalSaisi = $modele->canal;
        $this->objetSaisi = (string) $modele->objet;
        $this->contenuSaisi = $modele->contenu_template;
        $this->actifSaisi = $modele->actif;
    }

    /**
     * Enregistre le modèle — le service de domaine porte les deux registres
     * fermés, ce composant ne les revalide pas à sa façon.
     */
    public function enregistrerModele(): void
    {
        $donnees = $this->validerEcriture([
            'declencheurSaisi' => ['required', 'string'],
            'canalSaisi' => ['required', 'string'],
            'objetSaisi' => ['nullable', 'string', 'max:255'],
            'contenuSaisi' => ['required', 'string', 'max:4096'],
            'actifSaisi' => ['boolean'],
        ]);

        $service = app(ModeleNotificationService::class);

        $charge = [
            'evenement' => (string) $donnees['declencheurSaisi'],
            'canal' => (string) $donnees['canalSaisi'],
            'objet' => (string) $donnees['objetSaisi'],
            'contenu_template' => (string) $donnees['contenuSaisi'],
            'actif' => (bool) $donnees['actifSaisi'],
        ];

        try {
            if ($this->modeleId === null) {
                $service->creerModele($charge);
                $message = __('notifications_pwa.modele_cree');
            } else {
                $service->modifierModele(ModeleNotification::findOrFail($this->modeleId), $charge);
                $message = __('notifications_pwa.modele_modifie');
            }
        } catch (RuntimeException $refus) {
            // Le refus du service est RENDU tel quel : c'est lui qui nomme le
            // registre fermé ou la collision d'unicité.
            $this->addError('contenuSaisi', $refus->getMessage());

            return;
        }

        $this->terminerFormulaire($message);
    }

    /**
     * Active ou désactive un modèle — geste « Activer / Désactiver » du maître.
     *
     * Aucune suppression n'existe : `BasePolicy::delete()` rend `false` pour
     * les vingt policies du dépôt, et la désactivation EST le geste métier.
     */
    public function basculerModele(string $modeleId): void
    {
        $this->exigerEcriture(self::MODULE);

        $modele = app(ModeleNotificationService::class)
            ->basculerActivationModele(ModeleNotification::findOrFail($modeleId));

        session()->flash('pwa-succes', $modele->actif
            ? __('notifications_pwa.modele_active')
            : __('notifications_pwa.modele_desactive_fait'));
    }

    // =====================================================================
    // Export — PA-119
    // =====================================================================

    public function ouvrirExport(): void
    {
        $this->reset('formatExport');
        $this->resetValidation();
        $this->etatFormulaire = 'export';
    }

    /**
     * @return \Symfony\Component\HttpFoundation\StreamedResponse|\Symfony\Component\HttpFoundation\BinaryFileResponse|null
     */
    public function genererExport()
    {
        $onglet = $this->ongletValide();
        $lignes = $this->lignesExportables($onglet);

        if ($lignes === []) {
            $this->addError('formatExport', __('notifications_pwa.export_vide'));

            return null;
        }

        $this->etatFormulaire = null;

        if ($this->formatExport === 'excel') {
            return Excel::download(
                new NotificationsExport($onglet, $lignes, $this->descriptionDuFiltre()),
                'notifications_'.$onglet.'_'.now()->format('Ymd_His').'.xlsx',
            );
        }

        $utilisateur = auth()->user();

        $pdf = Pdf::loadView('pdf.notifications', [
            'entete' => $this->enTeteRapport($this->libelleOnglet($onglet), $this->descriptionDuFiltre()),
            'titreDocument' => $this->libelleOnglet($onglet),
            'entetes' => NotificationsExport::entetesDe($onglet),
            'lignes' => $lignes,
            'filtre' => $this->descriptionDuFiltre(),
            'auteur' => $utilisateur instanceof User ? $utilisateur->login : null,
        ])->setPaper('a4', 'landscape');

        return response()->streamDownload(
            static fn () => print ($pdf->output()),
            'notifications_'.$onglet.'_'.now()->format('Ymd_His').'.pdf',
        );
    }

    public function fermerModales(): void
    {
        $this->etatFormulaire = null;
        $this->resetValidation();
    }

    // =====================================================================
    // Lectures
    // =====================================================================

    public function render(
        ModeleNotificationService $service,
        FileAttenteNotificationsService $fileService,
        ConfigurationMailService $configurationMail,
    ): View {
        $modeles = $service->modeles();
        $affiches = $this->modelesAffiches($modeles);

        $variablesInconnues = [];
        $declencheurDuModele = [];

        foreach ($affiches as $modele) {
            $variablesInconnues[$modele->getKey()] = $service->variablesInconnues($modele);
            $declencheurDuModele[$modele->getKey()] = RegistreDeclencheurs::declencheur($modele->evenement);
        }

        $file = $fileService->file();
        $fileAffichee = $this->fileAffichee($file);
        $journalTraitement = $fileService->journalTraitement();

        return view('pwa.notifications.hub', array_merge($this->socle(), [
            'onglet' => $this->ongletValide(),
            'modeles' => $affiches,
            'declencheurs' => $this->declencheursAffiches($modeles),
            'canaux' => RegistreCanaux::tous(),
            'publics' => RegistreDeclencheurs::publics(),
            'journal' => $service->journal(),
            'groupesFile' => $this->grouperParDeclencheur($fileAffichee),
            // La colonne « En file » du maître (onglet Canaux) : le décompte
            // RÉEL des messages composés en attente, par canal — mesuré sur la
            // file déjà chargée, jamais une seconde requête. L'ancien refus
            // (« rien n'en compose ») est périmé depuis que la file existe
            // (vague F) : le garder aurait été la phrase morte de PA-144.
            'enFileParCanal' => $file->groupBy('canal')->map->count(),
            'journalTraitement' => $journalTraitement,
            'variablesInconnues' => $variablesInconnues,
            'declencheurDuModele' => $declencheurDuModele,
            // Les variables offertes par le declencheur ACTUELLEMENT choisi
            // dans la modale : l'aide sous le champ « Message » doit suivre le
            // selecteur, sinon elle propose les variables d'un autre evenement.
            'declencheurDuFormulaire' => RegistreDeclencheurs::declencheur($this->declencheurSaisi),
            'nombreModelesActifs' => $modeles->where('actif', true)->count(),
            'nombreModeles' => $modeles->count(),
            'nombreDeclencheurs' => count(RegistreDeclencheurs::codes()),
            'nombreCanauxBranches' => RegistreCanaux::nombreBranches(),
            'nombreCanaux' => count(RegistreCanaux::codes()),
            'nombreEnvoisReels' => $service->nombreEnvoisReels(),
            'nombreEnAttente' => $file->count(),
            'nombreTraites' => $journalTraitement->where('statut', MessageNotificationCompose::STATUT_TRAITE_MANUELLEMENT)->count(),
            'nombreAbandonnes' => $journalTraitement->where('statut', MessageNotificationCompose::STATUT_ABANDONNE)->count(),
            'peutEcrire' => $this->peutEcrire(),
            // La raison affichée dans la file (`file_sans_configuration`)
            // dépend de CE contrôle, jamais d'une supposition côté vue.
            'mailConfigure' => $configurationMail->estReelle(),
            'titreExport' => __('notifications_pwa.export_titre', [
                'onglet' => $this->libelleOnglet($this->ongletValide()),
            ]),
        ]));
    }

    // ---------------------------------------------------------------- privé

    private function peutEcrire(): bool
    {
        $utilisateur = auth()->user();

        return $utilisateur instanceof User
            && $utilisateur->estActif()
            && $utilisateur->niveauSurModule(self::MODULE) === 'C';
    }

    private function ongletValide(): string
    {
        return in_array($this->onglet, self::ONGLETS, true) ? $this->onglet : 'file';
    }

    private function libelleOnglet(string $onglet): string
    {
        return match ($onglet) {
            'modeles' => __('notifications_pwa.onglet_modeles'),
            'declencheurs' => __('notifications_pwa.onglet_declencheurs'),
            'journal' => __('notifications_pwa.onglet_journal'),
            'canaux' => __('notifications_pwa.onglet_canaux'),
            default => __('notifications_pwa.onglet_file'),
        };
    }

    /**
     * Les messages en file retenus par les filtres affichés — même portée
     * que `modelesAffiches()` : canal, public (dérivé du déclencheur, la
     * file ne stocke pas cette information — voir la migration) et recherche
     * sur destinataire + contenu + code du modèle.
     *
     * @param  EloquentCollection<int, MessageNotificationCompose>  $file
     * @return Collection<int, MessageNotificationCompose>
     */
    private function fileAffichee(EloquentCollection $file): Collection
    {
        $terme = mb_strtolower(trim($this->recherche));

        return $file
            ->when($this->filtreCanal !== '', fn (Collection $c) => $c->where('canal', $this->filtreCanal))
            ->when($this->filtrePublic !== '', function (Collection $c) {
                return $c->filter(function (MessageNotificationCompose $m): bool {
                    $declencheur = RegistreDeclencheurs::declencheur($m->modele->evenement);

                    return $declencheur !== null && $declencheur['public'] === $this->filtrePublic;
                });
            })
            ->when($terme !== '', fn (Collection $c) => $c->filter(
                static fn (MessageNotificationCompose $m): bool => str_contains(
                    mb_strtolower($m->destinataire . ' ' . $m->contenu . ' ' . $m->modele->evenement),
                    $terme,
                ),
            ))
            ->values();
    }

    /**
     * Regroupe les messages de la file par déclencheur — le maître les lit
     * ainsi, « c'est ainsi qu'on relit une campagne, pas message par
     * message » (`m12-notifications-hub.js` l.58-59).
     *
     * @param  Collection<int, MessageNotificationCompose>  $messages
     * @return list<array{declencheur: array<string, mixed>|null, code: string, messages: Collection<int, MessageNotificationCompose>}>
     */
    private function grouperParDeclencheur(Collection $messages): array
    {
        $groupes = [];

        foreach ($messages as $message) {
            $code = $message->modele->evenement;
            $groupes[$code] ??= [
                'declencheur' => RegistreDeclencheurs::declencheur($code),
                'code' => $code,
                'messages' => new Collection(),
            ];
            $groupes[$code]['messages']->push($message);
        }

        return array_values($groupes);
    }

    /**
     * Les modèles retenus par les filtres affichés.
     *
     * @param  EloquentCollection<int, ModeleNotification>  $modeles
     * @return Collection<int, ModeleNotification>
     */
    private function modelesAffiches(EloquentCollection $modeles): Collection
    {
        $terme = mb_strtolower(trim($this->recherche));

        return $modeles
            ->when($this->filtreCanal !== '', fn (Collection $c) => $c->where('canal', $this->filtreCanal))
            ->when($this->filtreEtat !== '', fn (Collection $c) => $c->where(
                'actif',
                $this->filtreEtat === 'actif',
            ))
            ->when($this->filtrePublic !== '', fn (Collection $c) => $c->filter(
                fn (ModeleNotification $m): bool => (RegistreDeclencheurs::declencheur($m->evenement)['public'] ?? null)
                    === $this->filtrePublic,
            ))
            ->when($terme !== '', fn (Collection $c) => $c->filter(
                static fn (ModeleNotification $m): bool => str_contains(
                    mb_strtolower($m->evenement.' '.$m->contenu_template.' '.(string) $m->objet),
                    $terme,
                ),
            ))
            ->values();
    }

    /**
     * Les déclencheurs du registre, avec le comptage de leurs modèles.
     *
     * @param  EloquentCollection<int, ModeleNotification>  $modeles
     * @return list<array<string, mixed>>
     */
    private function declencheursAffiches(EloquentCollection $modeles): array
    {
        $service = app(ModeleNotificationService::class);
        $terme = mb_strtolower(trim($this->recherche));
        $affiches = [];

        foreach (RegistreDeclencheurs::tous() as $declencheur) {
            if ($this->filtrePublic !== '' && $declencheur['public'] !== $this->filtrePublic) {
                continue;
            }

            if ($terme !== '' && ! str_contains(
                mb_strtolower($declencheur['libelle'].' '.$declencheur['description'].' '.$declencheur['code']),
                $terme,
            )) {
                continue;
            }

            $affiches[] = $declencheur + [
                'comptage' => $service->comptageParDeclencheur($modeles, $declencheur['code']),
            ];
        }

        return $affiches;
    }

    /**
     * Les lignes RÉELLEMENT AFFICHÉES de l'onglet — PA-119.
     *
     * @return list<array<int, string>>
     */
    private function lignesExportables(string $onglet): array
    {
        $service = app(ModeleNotificationService::class);
        $modeles = $service->modeles();

        if ($onglet === 'file') {
            $fileService = app(FileAttenteNotificationsService::class);
            $fileAffichee = $this->fileAffichee($fileService->file());

            return $fileAffichee->map(static function (MessageNotificationCompose $m): array {
                $declencheur = RegistreDeclencheurs::declencheur($m->modele->evenement);

                return [
                    $m->destinataire,
                    $declencheur['libelle'] ?? $m->modele->evenement,
                    RegistreCanaux::existe($m->canal) ? RegistreCanaux::canal($m->canal)['libelle'] : $m->canal,
                    (string) $m->objet,
                    $m->contenu,
                    'non',
                ];
            })->values()->all();
        }

        if ($onglet === 'declencheurs') {
            return array_map(static fn (array $d): array => [
                $d['libelle'],
                $d['public_libelle'],
                $d['module'],
                $d['comptage']['actifs'].' / '.$d['comptage']['total'],
                implode(' ', array_map(static fn (string $v): string => '{'.$v.'}', $d['variables'])),
            ], $this->declencheursAffiches($modeles));
        }

        if ($onglet === 'canaux') {
            return array_map(static fn (array $c): array => [
                $c['libelle'],
                $c['branche']
                    ? __('notifications_pwa.canal_branche')
                    : __('notifications_pwa.canal_non_branche'),
                $c['blocage'],
                $c['limite'] === null
                    ? '—'
                    : __('notifications_pwa.canal_caracteres', ['limite' => $c['limite']]),
                $c['cible'],
            ], RegistreCanaux::tous());
        }

        if ($onglet === 'journal') {
            return $service->journal()->map(static fn ($envoi): array => [
                $envoi->date_envoi->format('d/m/Y H:i'),
                $envoi->destinataire,
                (string) ($envoi->modele->evenement ?? ''),
                (string) ($envoi->modele->canal ?? ''),
                $envoi->statut_remise,
            ])->values()->all();
        }

        return $this->modelesAffiches($modeles)->map(static function (ModeleNotification $m): array {
            $declencheur = RegistreDeclencheurs::declencheur($m->evenement);

            return [
                $declencheur['libelle'] ?? $m->evenement,
                RegistreCanaux::existe($m->canal) ? RegistreCanaux::canal($m->canal)['libelle'] : $m->canal,
                (string) $m->objet,
                $m->contenu_template,
                $m->actif
                    ? __('notifications_pwa.modele_actif')
                    : __('notifications_pwa.modele_desactive'),
            ];
        })->values()->all();
    }

    private function descriptionDuFiltre(): string
    {
        $morceaux = [__('notifications_pwa.filtre_onglet').' '.$this->libelleOnglet($this->ongletValide())];

        if ($this->filtreCanal !== '' && RegistreCanaux::existe($this->filtreCanal)) {
            $morceaux[] = __('notifications_pwa.filtre_canal').' '
                .RegistreCanaux::canal($this->filtreCanal)['libelle'];
        }

        if (trim($this->recherche) !== '') {
            $morceaux[] = __('notifications_pwa.filtre_recherche').' '.trim($this->recherche);
        }

        return implode(' · ', $morceaux);
    }
}
