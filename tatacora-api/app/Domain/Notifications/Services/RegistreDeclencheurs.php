<?php

declare(strict_types=1);

namespace App\Domain\Notifications\Services;

/**
 * Les evenements qui declenchent une notification — registre FERME.
 *
 * Maitre : `prototype_v2/pages/m12-notifications-hub.html`, onglet
 * Declencheurs, et `prototype_v2/assets/js/notifications-engine.js` l.76-232.
 *
 * ## La detection est desormais REELLE pour CINQ declencheurs sur neuf (01/09/2026)
 *
 * Jusqu'a cette date, ce registre portait la CONFIGURATION seule : « compter
 * des occurrences n'aurait aucune consequence tant que rien ne part » — vrai
 * pour l'ENVOI (RG-20 reste non implementee, voir plus bas), faux pour la
 * VALEUR de la file d'attente elle-meme, que le Product Owner a demandee le
 * 01/09/2026 : relire le texte exact d'un message avant qu'un canal soit
 * contracte EST la valeur du module, et elle exige de vraies occurrences.
 *
 * `detecteur()` nomme, pour les declencheurs COUVERTS, la classe qui sait les
 * detecter — meme principe que `Domain/Stocks/Etats/EtatStocks` pour M14 :
 * le code qui interroge un domaine VIT dans ce domaine
 * (`Domain/Notifications/Detecteurs/`), jamais recopie ici. Ce registre ne
 * fait que le NOMMER, exactement comme `module` le fait deja pour
 * l'information d'origine.
 *
 * ## QUATRE declencheurs restent SANS detecteur, et chacun a SA raison
 *
 * `creance_echue` / `creance_douteuse` (M3) — le maitre invente une regle
 * d'anciennete (30 / 90 jours, `notifications-engine.js` l.113-146) que ce
 * depot REFUSE de reproduire cote serveur : PA-20 (balance agee) n'est
 * TOUJOURS PAS arbitree, `m3-clients-creances.html` en bloque deja trois
 * onglets sur quatre pour la meme raison. Inventer ici une regle qu'un autre
 * ecran refuse d'afficher creerait deux verites sur la meme question.
 *
 * `stock_sous_seuil` (M6) / `depart_circuit_demain` (M9) — HORS PERIMETRE de
 * la vague qui a porte ce lot (01/09/2026) : Stocks et Tourisme etaient
 * modifies EN PARALLELE par d'autres agents au moment de ce travail, et lire
 * leurs modeles sans coordination aurait couple ce lot a un chantier
 * concurrent. Ce n'est PAS un refus d'architecture — `stock_sous_seuil`
 * suivrait `StockTheoriqueService::sousSeuilPourAlerte()` (ou equivalent) le
 * jour ou ce couplage sera coordonne — et la date situe le motif pour qu'il
 * se verifie avant de s'y fier (meme regle que PA-107/120/144 : un motif de
 * refus perime devient un oubli).
 *
 * ## Ce qui reste vrai pour les CINQ : le compte n'a AUCUNE consequence d'envoi
 *
 * Composer un message n'aurait aucun effet tant que rien ne part.
 * L'API WhatsApp Business n'est pas contractee, aucun relais SMTP n'est
 * configure, et l'application Flutter qui porterait le canal Android
 * n'enregistre aucun appareil. RG-20 (diffusion automatique) reste la seule
 * des vingt regles de gestion du projet non implementee — c'est une
 * dependance externe, pas un developpement. `DetectionNotificationsService`
 * compose et met en file ; rien n'envoie.
 *
 * ## Le module d'origine est une INFORMATION, pas une dependance NOUVELLE
 *
 * `module` est une chaine (« M1 », « M3 »…), affichee sans jamais charger un
 * modele d'un autre domaine A PARTIR D'ICI — c'est `detecteur()` qui nomme la
 * classe qui, elle, vit dans le domaine concerne et en porte la dependance.
 *
 * @see RG-20 Diffusion automatique des notifications (non implementee)
 * @see \App\Domain\Notifications\Services\DetectionNotificationsService
 */
final class RegistreDeclencheurs
{
    /**
     * Le detecteur REEL de chaque declencheur COUVERT — `null` pour les
     * quatre autres, avec leur raison ci-dessus, jamais une classe factice.
     *
     * @var array<string, class-string<\App\Domain\Notifications\Contracts\DetecteurDeclencheurInterface>|null>
     */
    private const DETECTEURS = [
        'sejour_demain' => \App\Domain\Notifications\Detecteurs\SejourDemainDetecteur::class,
        'sejour_depart' => \App\Domain\Notifications\Detecteurs\SejourDepartDetecteur::class,
        'creance_echue' => null,
        'creance_douteuse' => null,
        'stock_sous_seuil' => null,
        'depart_circuit_demain' => null,
        'restitution_vehicule' => \App\Domain\Notifications\Detecteurs\RestitutionVehiculeDetecteur::class,
        'bulletin_disponible' => \App\Domain\Notifications\Detecteurs\BulletinDisponibleDetecteur::class,
        'echeance_vps' => \App\Domain\Notifications\Detecteurs\EcheanceVpsDetecteur::class,
    ];

    /**
     * @return class-string<\App\Domain\Notifications\Contracts\DetecteurDeclencheurInterface>|null
     */
    public static function detecteur(string $code): ?string
    {
        return self::DETECTEURS[$code] ?? null;
    }

    /** Les publics vises — jeu ferme, ordre du maitre. */
    public const PUBLICS = ['client', 'personnel', 'interne'];

    /**
     * Le registre, tel que le maitre le pose. Les variables sont celles que
     * le maitre offre a un modele : les changer ferait mentir l'aide
     * « Variables disponibles » de la modale d'edition.
     *
     * @var array<string, array{public: string, module: string, variables: list<string>}>
     */
    private const DECLENCHEURS = [
        'sejour_demain' => [
            'public' => 'client', 'module' => 'M1',
            'variables' => ['client', 'date_arrivee', 'date_depart', 'nuits'],
        ],
        'sejour_depart' => [
            'public' => 'client', 'module' => 'M1',
            'variables' => ['client', 'date_depart', 'reste_du'],
        ],
        'creance_echue' => [
            'public' => 'client', 'module' => 'M3',
            'variables' => ['client', 'montant', 'anciennete'],
        ],
        'creance_douteuse' => [
            'public' => 'interne', 'module' => 'M3',
            'variables' => ['nb_clients', 'montant', 'part'],
        ],
        'stock_sous_seuil' => [
            'public' => 'interne', 'module' => 'M6',
            'variables' => ['article', 'stock', 'seuil', 'point'],
        ],
        'depart_circuit_demain' => [
            'public' => 'client', 'module' => 'M9',
            'variables' => ['client', 'circuit', 'date', 'guide', 'personnes'],
        ],
        'restitution_vehicule' => [
            'public' => 'client', 'module' => 'M8',
            'variables' => ['client', 'vehicule', 'date', 'reste_du'],
        ],
        'bulletin_disponible' => [
            'public' => 'personnel', 'module' => 'M13',
            'variables' => ['employe', 'periode', 'net'],
        ],
        'echeance_vps' => [
            'public' => 'interne', 'module' => 'M13',
            'variables' => ['periode', 'montant', 'echeance'],
        ],
    ];

    /**
     * @return list<string>
     */
    public static function codes(): array
    {
        return array_keys(self::DECLENCHEURS);
    }

    public static function existe(string $code): bool
    {
        return array_key_exists($code, self::DECLENCHEURS);
    }

    /**
     * Un declencheur, libelles resolus — ou `null` si le code est inconnu.
     *
     * Rendre `null` plutot qu'une entree fabriquee est deliberé : un modele
     * dont l'evenement a disparu du registre doit se VOIR a l'ecran, pas se
     * fondre derriere son propre code affiche comme un libelle.
     *
     * @return array{code: string, libelle: string, description: string, public: string, public_libelle: string, module: string, variables: list<string>}|null
     */
    public static function declencheur(string $code): ?array
    {
        if (! self::existe($code)) {
            return null;
        }

        $entree = self::DECLENCHEURS[$code];

        return [
            'code' => $code,
            'libelle' => __('notifications_pwa.declencheur.'.$code.'.libelle'),
            'description' => __('notifications_pwa.declencheur.'.$code.'.description'),
            'public' => $entree['public'],
            'public_libelle' => __('notifications_pwa.public.'.$entree['public']),
            'module' => $entree['module'],
            'variables' => $entree['variables'],
        ];
    }

    /**
     * @return list<array{code: string, libelle: string, description: string, public: string, public_libelle: string, module: string, variables: list<string>}>
     */
    public static function tous(): array
    {
        $tous = [];

        foreach (self::codes() as $code) {
            $declencheur = self::declencheur($code);

            if ($declencheur !== null) {
                $tous[] = $declencheur;
            }
        }

        return $tous;
    }

    /**
     * Les publics, libelles resolus.
     *
     * @return list<array{code: string, libelle: string}>
     */
    public static function publics(): array
    {
        return array_map(
            static fn (string $code): array => [
                'code' => $code,
                'libelle' => __('notifications_pwa.public.'.$code),
            ],
            self::PUBLICS,
        );
    }
}
