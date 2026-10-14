{{--
    M4 — CARTE DU RESTAURANT.

    Maître : prototype_v2/pages/m4-restaurant-carte.html, dont le corps est
    rendu par prototype_v2/pages/carte-module.js — le MÊME fichier que la carte
    du bar. Le corps partagé vit dans `pwa/carte/corps.blade.php` ; il ne reste
    ici que ce qui distingue réellement le rayon.

    ## « Délier » n'existe QU'ICI

    `plats.article_id` est nullable et le lien direct est l'EXCEPTION : le
    retirer rend le plat à sa fiche technique, qui est son état normal. Au bar,
    `cartes_boisson.article_id` est NOT NULL et le bouton ne peut pas exister.

    ## Un seul refus, nommé à l'écran — le second a été LEVÉ

    « Rapprocher automatiquement » : le maître ne pose ce bouton que sur la
    carte du bar, et rapprocher un plat par libellé rattacherait « Poulet DG »
    à un article de stock.

    Le second, « Prix provisoires », disait qu'aucune colonne au schéma ne le
    portait. PA-161 (b) a créé `plats.prix_provisoire` et
    `plats.prix_corrige_main` : le filtre, l'indicateur et les deux marques de
    ligne sont rendus, et le motif est retiré plutôt que laissé à vieillir
    (PA-144). Six lignes de sandwicherie du maître portent « corrigé à la
    main » sans être provisoires — une étiquette manuscrite a remplacé
    l'imprimé, et c'est le prix manuscrit qui fait foi.

    Déclarations pour la garde des trois sources : aucun bloc du maître n'est
    refusé ici — l'écart ci-dessus porte sur un CONTRÔLE, et il est nommé en
    toutes lettres dans `lang/fr/carte_pwa.php`.
--}}
@include('pwa.carte.corps', [
    'page' => [
        'titre' => __('carte_pwa.restaurant.titre'),
        'sous_titre' => __('carte_pwa.restaurant.sous_titre'),
        // Onglet AJOUTÉ le 03/09/2026 (Product Owner) : le code le nomme
        // neutralement (`ventes`), le libellé est celui du RAYON.
        'onglet_ventes' => __('carte_pwa.restaurant.onglet_ventes'),
        // maître — m4-restaurant-carte.html l.29
        'icone' => '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M3 2v7c0 1.1.9 2 2 2h1a2 2 0 002-2V2M7 2v20M17 2a5 5 0 00-5 5v6h5m0-11v20"/></svg>',
        // maître — carte-module.js l.76-85 : encadré « amber ».
        'bandeau' => [
            'fond' => '#FFFBEB',
            'bord' => '#FDE68A',
            'texte' => '#78350F',
            'titre' => __('carte_pwa.restaurant.bandeau_titre'),
            'corps' => __('carte_pwa.restaurant.bandeau_texte', [
                'sans_lien' => $indicateurs['sans_lien'],
                'total' => $indicateurs['articles'],
            ]),
        ],
        // Cle d'accordeon PROPRE A L'ECRAN (PO 03/09/2026) : replier la
        // bande du bar ne replie pas celle du restaurant.
        'cle_kpis' => 'pwa_kpis_carte_restaurant',
        // 04/09/2026 — le lien vers l'ecran du catalogue (plats, fiches
        // techniques, menus), qui n'etait atteignable par aucun clic.
        'lien_catalogue' => true,
        'delier' => true,
        'point_absent' => __('carte_pwa.restaurant.point_absent'),
        'export_titre' => __('carte_pwa.restaurant.export_titre'),
        // L'export porte sur l'ONGLET COURANT (PO 03/09/2026) : la modale
        // nomme ce qu'elle produira, carte ou ventes du rayon.
        'export_titre_ventes' => __('carte_pwa.restaurant.export_titre_ventes'),
    ],
])
