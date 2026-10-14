<?php

declare(strict_types=1);

namespace App\Pwa\Support;

/**
 * Les écarts VOLONTAIRES entre la PWA et le maître — déclarés, datés, signés.
 *
 * ## Pourquoi ce registre existe
 *
 * Une dérogation non déclarée finit par faire désactiver la garde. Le
 * mécanisme du dépôt est écrit dans l'entête de
 * `prototype_v2/tests/t-trois-sources.js` : un refus se DÉCLARE
 * (`maitre-refuse:<page>#<bloc>`) et reste affiché à chaque exécution — un
 * refus qu'on ne voit plus redevient un oubli. Ce fichier est le pendant
 * transverse de ces jetons : les écarts qui ne tiennent à aucune page en
 * particulier n'avaient nulle part où être écrits, et ils vivaient donc dans
 * une conversation.
 *
 * ⚠ Chaque entrée porte SA DATE, et ce n'est pas de la bureaucratie. Un motif
 * de refus qui a cessé d'être vrai transforme une décision en oubli : c'est
 * arrivé trois fois dans ce dépôt (PA-107, PA-120, PA-144), la troisième dans
 * du code, où la vue d'accueil justifiait son refus par « aucun service de
 * domaine M11 n'existe » — vrai à l'écriture, faux depuis, et personne ne
 * rouvrait la question puisque le code disait que c'était impossible.
 *
 * ## Ce que ce registre N'EST PAS
 *
 * Il ne dispense d'aucun jeton. Quand un écart porte sur un BLOC identifiable
 * du maître, le jeton `maitre-refuse:` reste la déclaration qui compte, parce
 * que c'est elle que la garde lit. Le champ `jeton` de chaque entrée dit où
 * elle se trouve — ou pourquoi il n'y en a pas.
 *
 * @see prototype_v2/tests/t-trois-sources.js (entête, §« Ce qu'il compare »)
 * @see docs/DIRECTIVE_CONFORMITE_100.md
 */
final class DerogationsMaquette
{
    /**
     * Les trois dérogations accordées le 31/08/2026 par le Product Owner, une
     * quatrième le 01/09/2026 (bouton d'export unique) — et la troisième
     * (`entete_tableau`) RENVERSÉE le 01/09/2026 (en-tête navy partout +
     * recherche/filtre par table), conservée dans le registre pour sa
     * traçabilité plutôt que supprimée.
     *
     * @var array<string, array{
     *     statut?: string,
     *     element: string,
     *     maitre: string,
     *     pwa: string,
     *     raison: string,
     *     date: string,
     *     decideur: string,
     *     jeton: string|null,
     *     portee_du_jeton: string
     * }>
     */
    public const DEROGATIONS = [
        /*
         * 1 — LE BANDEAU KPI EN ACCORDÉON, SUR TOUTES LES PAGES.
         *
         * Mesuré : le maître ne pose un accordéon de KPI que sur
         * `tableau-de-bord.html` (l.72-78), et seulement en dessous de `lg`
         * (`class="… lg:hidden"`) : sur un écran de bureau, ses huit cartes
         * sont toujours dépliées. La PWA en pose un sur chaque écran qui porte
         * une bande d'indicateurs, à tous les formats, et retient l'état plié
         * dans `localStorage` sous `pwa_kpis_<écran>`.
         */
        'bandeau_kpi' => [
            'element' => 'Bandeau d\'indicateurs en accordéon, état retenu dans localStorage',
            'maitre' => 'Un seul accordéon, sur `tableau-de-bord.html` l.72-78, replié sous `lg` '
                . 'uniquement (« Indicateurs clés (8) »). Aucun état retenu : la page rouvre '
                . 'toujours dans le même état.',
            'pwa' => 'Un accordéon sur chaque écran portant une bande d\'indicateurs, à tous les '
                . 'formats, sous le libellé « Indicateurs de Performance (KPIs) ». L\'état plié '
                . 'est retenu par écran (`pwa_kpis_<écran>`).',
            'raison' => 'La PWA est consultée au comptoir sur des écrans de portable, où la bande '
                . 'd\'indicateurs pousse le tableau de travail sous la ligne de flottaison. Le '
                . 'geste est réversible, il ne masque aucune donnée et n\'en invente aucune : ce '
                . 'que l\'accordéon cache reste à un clic. L\'état est retenu par POSTE, dans le '
                . 'navigateur — il ne voyage pas, et aucun calcul n\'en dépend.',
            'date' => '31/08/2026',
            'decideur' => 'Product Owner',
            'jeton' => null,
            // ⚠ LE JETON EST ÉPELÉ, ET C'EST LA SUBSTANCE DE CETTE LIGNE.
            //
            // Ce texte contenait la chaîne complète — « maitre-refuse », deux
            // points, « tableau-de-bord.html#page » — écrite d'un seul tenant
            // pour EXPLIQUER qu'il ne faut pas l'écrire. Or le comparateur
            // (`t-trois-sources.js` l.652, 758) cherche cette chaîne dans le
            // code par simple `includes()` : il ne distingue pas une
            // déclaration d'une citation. Le jeton était donc bel et bien émis,
            // et il avalait les onze libellés de la page — exactement l'effet
            // que ce paragraphe décrit comme à éviter.
            //
            // Sans effet le jour où il a été trouvé (la page est portée pour de
            // vrai, tous ses libellés se retrouvent), mais il aurait masqué la
            // prochaine régression, en silence et pour toujours.
            'portee_du_jeton' => 'AUCUN jeton n\'est émis depuis le socle, et c\'est mesuré : sur '
                . '`tableau-de-bord.html`, aucun `data-panneau`, `data-onglet` ni `id="vue-…"` '
                . 'n\'existe — les libellés de la page tombent TOUS dans le bloc `page`. Un jeton '
                . '« maitre-refuse » (épelé ici, jamais écrit d\'un tenant : le comparateur le '
                . 'reconnaîtrait) portant sur cette page et le bloc `page` masquerait du même '
                . 'geste sept titres de section et trois boutons de période qui sont, eux, de '
                . 'vrais restes-à-faire non accordés. Le jeton appartient à l\'écran M11, une '
                . 'fois sa page portée, et pour ce seul libellé.',
        ],

        /*
         * 2 — LA MODALE D'EXPORT AVEC CHOIX DE FORMAT.
         */
        'modale_export' => [
            'element' => 'Modale d\'export offrant un choix PDF A4 / Tableur',
            'maitre' => '`assets/js/crud-ui.js` l.142-160 : un bouton unique, « Télécharger tous '
                . 'les résultats filtrés (.csv) ». Aucun choix de format, aucun PDF.',
            'pwa' => 'Un choix radio « PDF Officiel A4 Imprimable » / « Tableur Excel '
                . '(.xlsx / .csv) », puis « Générer & Télécharger ».',
            'raison' => 'La Directive de conformité impose le PDF A4 imprimable, que le maître '
                . 'n\'offre pas : au Gîte, plusieurs états partent au comptable sur papier. '
                . 'C\'est un ÉLARGISSEMENT et non une dérive — le CSV du maître reste servi par '
                . 'la branche « Tableur ». La convention serveur RG-19 reste tenue : le CSV est '
                . 'produit avec BOM UTF-8 et point-virgule.',
            'date' => '31/08/2026',
            'decideur' => 'Product Owner',
            'jeton' => 'maitre-refuse:chassis#modale-export',
            'portee_du_jeton' => 'Le jeton est écrit dans '
                . '`resources/views/pwa/partials/modale-export.blade.php`, à côté du code qu\'il '
                . 'décrit. Il porte sur le CHÂSSIS et non sur une page : la modale du maître est '
                . 'construite par `crud-ui.js`, donc rattachée à toutes les pages qui le '
                . 'chargent. Une déclaration page par page en aurait fait onze, qui auraient '
                . 'divergé.',
        ],

        /*
         * 3 — L'EN-TÊTE DE TABLEAU UNIQUE. RENVERSÉE LE 01/09/2026 — conservée
         * pour la traçabilité (même principe que PA-107/120/144 : un motif
         * périmé documente au moins QUAND il a cessé d'être vrai). NE PAS
         * relire cette entrée comme la règle en vigueur — voir `statut`.
         */
        'entete_tableau' => [
            'statut' => 'renversee_01_09_2026',
            'element' => 'En-tête de tableau `bg-slate-50` sur tous les écrans '
                . '(RENVERSÉ — voir `entete_tableau_navy` ci-dessous pour la règle actuelle)',
            'maitre' => 'Deux familles cohabitent : la majorité des tableaux ont un en-tête clair, '
                . 'et HUIT pages posent `<thead class="bg-[var(--navy)]">` — `journal-audit`, '
                . '`m1-hebergement`, `roles-permissions` et les cinq pages M10 (`analytique`, '
                . '`balance`, `grand-livre`, `journal`, `plan-comptable`). Le chiffre est mesuré '
                . 'le 31/08/2026 ; la note de cadrage en annonçait trois.',
            'pwa' => 'JUSQU\'AU 01/09/2026 : un seul en-tête, `bg-slate-50`, partout. DEPUIS : '
                . 'l\'inverse — un seul en-tête navy (`bg-[var(--navy)]`, texte `text-white/90`, '
                . '`text-[11px] font-semibold uppercase tracking-wide`), partout, plus une barre '
                . 'de recherche et au moins un filtre par table de données. Ce n\'est donc plus '
                . 'un écart au maître : c\'est un ALIGNEMENT sur lui.',
            'raison' => 'RENVERSÉE — instruction du Product Owner du 01/09/2026 : « En-tête des '
                . 'tableaux sur TOUS les tableaux : bleu nuit comme le maître PARTOUT, ET chaque '
                . 'table avec sa barre de recherche et filtre. » Le motif du 31/08/2026 (les deux '
                . 'familles du maître ne recouvraient aucune distinction métier) n\'a pas été '
                . 'réfuté — la décision du 01/09/2026 le rend simplement sans objet : le Product '
                . 'Owner a tranché pour l\'uniformité NAVY plutôt que pour l\'uniformité CLAIRE.',
            // Date du RENVERSEMENT — c'est elle qui commande la validité de
            // cette entrée depuis cette date. La dérogation initiale
            // (31/08/2026) reste écrite en toutes lettres dans `raison`
            // ci-dessus, pour l'historique.
            'date' => '01/09/2026',
            'decideur' => 'Product Owner',
            'jeton' => null,
            'portee_du_jeton' => 'Sans objet : la dérogation est renversée, il n\'y a plus rien à '
                . 'déclarer comme écart. Les exclusions RESTANTES (grilles de saisie en ligne — '
                . 'commande/réception M7, saisie manuelle M10 — et documents imprimés — ticket '
                . 'thermique, tickets/relevés de vente) sont documentées PAGE PAR PAGE, en '
                . 'commentaire Blade, à côté du tableau concerné : elles tiennent au type de '
                . 'tableau (formulaire éditable, document papier), pas à un écart de maquette.',
        ],

        /*
         * 4 — UN SEUL BOUTON « EXPORTER », PARTOUT OÙ LE MAÎTRE EN POSE DEUX.
         */
        'export_bouton_unique' => [
            'element' => 'Un bouton d\'entrée unique « Exporter », qui ouvre la modale d\'export '
                . 'partagée (dérogation 2 ci-dessus) — sur toute page qui affichait la paire '
                . '« Excel » / « PDF ».',
            'maitre' => 'Deux boutons d\'entrée séparés, un par format — « Export Excel » + '
                . '« Export PDF », ou « Excel » + « PDF » selon l\'écran '
                . '(`m6-stocks.html` l.65-66, `m6-inventaires.html` l.78-79, '
                . '`m7-approvisionnement.html` l.225-226, `depenses.html` l.66-67, '
                . '`tableau-de-bord.html` l.55-63 et l.260-261, `m12-notifications-hub.html` '
                . 'l.49 — un seul bouton « PDF » au maître, `historique-ventes.html` l.50-51, '
                . '`m13-paie.html` l.46-47 ; vague du 02/09/2026, rappel PO du même jour : '
                . '`m3-clients-creances.html` l.64-65, `m2-facturation.html` l.112-113, '
                . '`m5-bar-carte.html` l.38-39, `m4-restaurant-carte.html` l.37-38, '
                . '`m9-tourisme-departs.html` l.40-41, `m8-locations.html` l.40-41).',
            'pwa' => 'Un seul bouton « Exporter », qui ouvre `ouvrirExport()` puis la modale '
                . 'd\'export partagée (dérogation 2) : le format PDF/Excel s\'y choisit, sans '
                . 'présélection imposée — chaque écran conserve son défaut d\'origine '
                . '(`formatExport = \'pdf\'`).',
            'raison' => 'La modale d\'export offre déjà le choix du format depuis le 31/08/2026 '
                . '(dérogation 2) : les deux boutons d\'entrée du maître, qui ne faisaient que '
                . 'présélectionner ce choix, sont devenus redondants avec lui. Le Product Owner a '
                . 'demandé le 01/09/2026 de fusionner l\'entrée en un seul bouton — un geste en '
                . 'moins pour le même résultat, jamais une fonction retirée : les deux formats '
                . 'restent atteignables, dans la modale.',
            'date' => '01/09/2026',
            'decideur' => 'Product Owner',
            'jeton' => null,
            // Aucun jeton unique ne couvre cette dérogation : elle touche
            // QUATORZE pages du maître (huit le 01/09/2026, six de plus le
            // 02/09/2026 sur rappel du Product Owner), chacune avec son
            // propre bloc. Le mettre ICI sous une seule valeur en tairait
            // treize. Chaque vue Blade concernée porte donc SON jeton, à
            // côté du bouton qu'il concerne — c'est cette déclaration-là que
            // la garde lit (`t-trois-sources.js` l.652, 758).
            'portee_du_jeton' => 'Aucune valeur unique dans le champ `jeton` : la dérogation touche '
                . 'quatorze pages, chacune avec son propre bloc, et une seule valeur ici en aurait '
                . 'tu treize. Un jeton « maitre-refuse » (épelé : deux-points, puis la page, dièse, '
                . 'puis le bloc — jamais écrit d\'un tenant ici, le comparateur le reconnaîtrait) '
                . 'est posé directement dans chaque vue concernée, à côté du bouton fusionné : '
                . '`m6-stocks.html` bloc `page`, `m6-inventaires.html` bloc `page` (les deux '
                . 'paires de boutons de cette page), `m7-approvisionnement.html` bloc `besoins`, '
                . '`depenses.html` bloc `page`, `tableau-de-bord.html` bloc `page` (les deux '
                . 'paires), `m12-notifications-hub.html` bloc `page`, `historique-ventes.html` '
                . 'bloc `page`, `m13-paie.html` bloc `page` ; vague du 02/09/2026 : '
                . '`m3-clients-creances.html` bloc `page`, `m2-facturation.html` bloc `page`, '
                . '`m5-bar-carte.html` et `m4-restaurant-carte.html` bloc `page` (vue partagée '
                . '`pwa/carte/corps.blade.php`, les deux jetons au même bouton), '
                . '`m9-tourisme-departs.html` bloc `page`, `m8-locations.html` bloc `page`.',
        ],
    ];
}
