{{--
    M5 — CARTE DU BAR.

    Maître : prototype_v2/pages/m5-bar-carte.html, dont le corps est rendu par
    prototype_v2/pages/carte-module.js — le MÊME fichier que la carte du
    restaurant. Le corps partagé vit dans `pwa/carte/corps.blade.php` ; il ne
    reste ici que ce qui distingue réellement le rayon : titre, sous-titre,
    icône, bandeau, refus.

    ## Le sous-titre était CELUI DU RESTAURANT

    La vue livrée affichait « Composition, disponibilité du jour et lien au
    stock » — la phrase de `m4-restaurant-carte.html` l.33. C'est exactement
    la dérive que le maître annonce l.7 quand il refuse deux écrans jumeaux.

    ## Deux refus, tous nommés à l'écran — le troisième a été LEVÉ

    « Délier » (`cartes_boisson.article_id` est NOT NULL) et « Rapprocher
    automatiquement » (inerte par construction, pour la même raison).

    Le troisième, « Prix provisoires », disait qu'aucune colonne au schéma ne
    le portait. PA-161 (b) l'a créée : le filtre, l'indicateur et les deux
    marques de ligne sont rendus, et le motif est retiré plutôt que laissé à
    vieillir. Un motif de refus qu'on ne voit plus redevient un oubli ; un
    motif devenu faux qu'on laisse en place est pire, parce qu'il ferme la
    question (PA-144).

    Déclarations pour la garde des trois sources : aucun bloc du maître n'est
    refusé ici — les trois écarts ci-dessus portent sur des CONTRÔLES, et
    chacun est nommé en toutes lettres dans `lang/fr/carte_pwa.php`.
--}}
@include('pwa.carte.corps', [
    'page' => [
        'titre' => __('carte_pwa.bar.titre'),
        'sous_titre' => __('carte_pwa.bar.sous_titre'),
        // Onglet AJOUTÉ le 03/09/2026 (Product Owner) : le code le nomme
        // neutralement (`ventes`), le libellé est celui du RAYON.
        'onglet_ventes' => __('carte_pwa.bar.onglet_ventes'),
        // maître — m5-bar-carte.html l.29
        'icone' => '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M5 3h14l-1 9a6 6 0 01-12 0L5 3zM12 15v6M8 21h8"/></svg>',
        // maître — carte-module.js l.66-74 : encadré « gris ».
        'bandeau' => [
            'fond' => '#F8FAFC',
            'bord' => '#E2E8F0',
            'texte' => '#334155',
            'titre' => __('carte_pwa.bar.bandeau_titre'),
            'corps' => __('carte_pwa.bar.bandeau_texte', [
                'lies' => $indicateurs['lies'],
                'total' => $indicateurs['articles'],
            ]),
        ],
        // `cartes_boisson.article_id` est NOT NULL : le lien se REMPLACE.
        // Cle d'accordeon PROPRE A L'ECRAN (PO 03/09/2026) : replier la
        // bande du bar ne replie pas celle du restaurant.
        'cle_kpis' => 'pwa_kpis_carte_bar',
        // Creation de boisson : PROPRE AU BAR (PO 03/09/2026). Le restaurant
        // cree ses plats sur « Plats & menus », ou menu et fiche technique
        // sont obligatoires — un bouton ici lui ouvrirait un formulaire
        // incapable de produire un plat valide.
        'creation_boisson' => true,
        'categories' => \App\Pwa\Livewire\Bar\CarteBar::CATEGORIES,
        'delier' => false,
        'point_absent' => __('carte_pwa.bar.point_absent'),
        'export_titre' => __('carte_pwa.bar.export_titre'),
        // L'export porte sur l'ONGLET COURANT (PO 03/09/2026) : la modale
        // nomme ce qu'elle produira, carte ou ventes du rayon.
        'export_titre_ventes' => __('carte_pwa.bar.export_titre_ventes'),
    ],
])
