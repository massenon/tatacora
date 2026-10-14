{{--
    STYLES de l'en-tête de rapport et de la zone de signatures — à inclure
    DANS LE <style> de chaque document qui les emploie :

        <style>
          …styles propres au document…
          @include('pdf.partials.entete-rapport-styles')
        </style>

    Pourquoi un partiel de styles séparé : dompdf ne partage aucune feuille
    entre documents distincts, et chaque PDF porte son propre <style>. Écrire
    ces règles dans chaque gabarit, c'est la copie d'en-tête que
    `RESPECT_TABLEAU_RAPPORT.md` §4 recense comme non-conformité n° 1 — ici,
    sa version CSS. Préfixe `er-` : aucune collision avec les classes du
    document hôte.

    Jetons de `04_UIUX_DESIGN_SYSTEM.md` §2.1, repris de `rapports/document`.
--}}
.er-entete { border-bottom: 2px solid #14213D; padding-bottom: 8px; }
/* Les documents hôtes stylent souvent TOUT `td` (bordure, remplissage) pour
   leur tableau de données : l'en-tête ne doit pas en hériter. */
.er-entete td, .er-bloc-titre td { border: none; padding: 0 4px 0 0; background: none; }
.er-entete td { vertical-align: top; }
/* Hauteur AUTO (14/10/2026, D392) : le logo livre est un PNG paysage
   735 x 403 ; `height: 48px` l'ETIRAIT en carre (dompdf ignore object-fit).
   Largeur gardee, proportions respectees : 48 x 26 px. */
.er-logo { width: 48px; height: auto; }
.er-raison-sociale { font-size: 14pt; font-weight: bold; color: #14213D; margin: 0; }
.er-coordonnees { font-size: 8pt; color: #6B7280; line-height: 1.45; }
.er-mentions-legales { font-size: 8pt; color: #262626; margin-top: 2px; }
.er-bloc-titre { border-bottom: 1px solid #E5E7EB; padding: 8px 0; margin-bottom: 10px; }
.er-type-rapport { font-size: 12pt; font-weight: bold; color: #14213D; }
.er-periode { font-size: 9pt; color: #262626; }
.er-edition { font-size: 8pt; color: #6B7280; margin-top: 3px; }
.er-signatures { width: 100%; margin-top: 30px; page-break-inside: avoid; }
.er-signatures td { width: 50%; text-align: center; font-size: 8.5pt; border: none; }
.er-pied {
    position: fixed; bottom: -14mm; left: 0; right: 0;
    font-size: 7.5pt; color: #6B7280;
    border-top: 1px solid #E5E7EB; padding-top: 4px;
}
.er-pied td { border: none; padding: 0; font-size: 7.5pt; }
.er-pied .er-pagination:after { content: counter(page) " / " counter(pages); }
