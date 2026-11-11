{{--
    Pictogrammes de l'écran de connexion (refonte du 29/10/2026, PO).

    Tracés ÉCRITS pour ce dépôt, dans le style de Lucide (ISC) : fil arrondi de
    2 px sur une grille de 24, `currentColor`. Aucune dépendance, aucun CDN —
    la page doit rester servable hors connexion. Décoratifs : `aria-hidden`.
    Le sens est porté par le libellé voisin ou par l'infobulle du conteneur.

    Paramètres : `nom` (clé du `@switch`), `taille` (px, 24 par défaut).
--}}
@php($taille = $taille ?? 24)
<svg width="{{ $taille }}" height="{{ $taille }}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">
@switch($nom)
  @case('restauration')
    <path d="M6 3v6a3 3 0 0 0 6 0V3"/><path d="M9 3v18"/><path d="M18 21V3c-2.5 1.5-3.5 4.5-3.5 8v2h3.5"/>
    @break
  @case('hebergement')
    <path d="M3 20V7"/><path d="M3 15h18v5"/><path d="M21 15v-2a3 3 0 0 0-3-3h-7v5"/><circle cx="7" cy="12" r="1.5"/>
    @break
  @case('eco_tourisme')
    <path d="m8 3 4 8 5-5 5 15H2z"/><path d="M4.1 15.7 8 10"/>
    @break
  @case('stock')
    <rect width="20" height="5" x="2" y="3" rx="1"/><path d="M4 8v11a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8"/><path d="M10 12h4"/>
    @break
  @case('location')
    <path d="M19 17h2a1 1 0 0 0 1-1v-3a2 2 0 0 0-1.5-1.9C18.7 10.6 16 10 16 10s-1.3-1.4-2.2-2.3A3 3 0 0 0 12 7H5a1.2 1.2 0 0 0-1.1.9l-1.4 2.9A3.7 3.7 0 0 0 2 12v4a1 1 0 0 0 1 1h2"/><circle cx="7" cy="17" r="2"/><path d="M9 17h6"/><circle cx="17" cy="17" r="2"/>
    @break
  @case('caisse')
    <rect width="16" height="20" x="4" y="2" rx="2"/><path d="M8 6h8"/><path d="M8 10h.01M12 10h.01M16 10h.01M8 14h.01M12 14h.01M8 18h.01M12 18h.01"/><path d="M16 14v4"/>
    @break
  @case('comptabilite')
    <path d="M3 3v16a2 2 0 0 0 2 2h16"/><path d="M18 17V9"/><path d="M13 17V5"/><path d="M8 17v-3"/>
    @break
  @case('utilisateur')
    <path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>
    @break
  @case('cadenas')
    <rect width="18" height="11" x="3" y="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>
    @break
  @case('cadenas_ouvert')
    <rect width="18" height="11" x="3" y="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 9.9-1"/>
    @break
  @case('oeil')
    <path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/>
    @break
  @case('oeil_barre')
    <path d="M10.7 5.1A10 10 0 0 1 12 5c6.4 0 10 7 10 7a17 17 0 0 1-2.2 3.2"/><path d="M6.6 6.6A16.5 16.5 0 0 0 2 12s3.6 7 10 7a9.7 9.7 0 0 0 5.4-1.6"/><path d="M14.1 14.1a3 3 0 1 1-4.2-4.2"/><path d="m2 2 20 20"/>
    @break
@endswitch
</svg>
