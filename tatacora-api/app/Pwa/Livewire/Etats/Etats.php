<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Etats;

use App\Domain\Etats\Services\CatalogueEtatsService;
use App\Pwa\Livewire\PageMetier;
use App\Shared\ReportEngine\Models\EtatGenere;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Facades\Auth;
use Illuminate\View\View;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;

/**
 * Etats, Rapports & Exports — maitre : `prototype_v2/pages/m14-etats.html`.
 *
 * En-tete (l.27-42), grille des etats `grid grid-cols-1 md:grid-cols-2
 * xl:grid-cols-3 gap-4 mb-8` (l.44), puis la carte « Historique des editions »
 * (l.46-63). Le corps de la grille et de l'historique est produit par le
 * `<script>` de fin de page (l.114-166).
 *
 * ## ⚠ CETTE PAGE SE DECLARE ELLE-MEME REMPLACEE, ET SON BANDEAU EST PORTE
 *
 * `m14-etats.html` l.15-21 : « **Ecran remplace.** Cette page reste
 * consultable comme maquette validee par le client, mais elle n'est plus au
 * menu : la version fonctionnelle est *Etats & Rapports* ». C'est le meme
 * dispositif que `m3-crm.html`, `m4-restaurant.html` et `m10-comptabilite.html`
 * — a une difference pres, qui commande le traitement : ces trois-la sont
 * declarees NON SERVIES par ce depot, cette page-ci figure au perimetre du
 * lot. Elle est donc servie AVEC son bandeau, et son entree de menu pointe
 * vers `m14-etats-studio`, la version fonctionnelle — exactement ce que le
 * bandeau du maitre indique de faire.
 *
 * ⚠ Une CINQUIEME page du maitre porte le meme bandeau : `m11-pilotage.html`
 * (l.46-59), remplacee par un onglet du tableau de bord. Le chiffre de trois
 * pages « qui se declarent elles-memes remplacees », ecrit dans
 * `LARAVEL_PWA.md` §2, est donc INEXACT — il y en a cinq. Remonte au rapport,
 * pas tranche seul.
 *
 * ## LE CATALOGUE EST CELUI DU SERVEUR, PAS LES HUIT CARTES DU MAITRE
 *
 * ECART DELIBERE — `m14-etats.html` l.114-123 (`ETATS_DISPONIBLES`, huit
 * cartes)
 * Le maitre : huit etats ECRITS EN DUR dans son `<script>`, avec leur
 * description.
 * Ici : les etats reellement editables par l'utilisateur connecte, rendus par
 * `CatalogueEtatsService::pourUtilisateur()` — trois au registre, filtres par
 * le RBAC de leur module SOURCE.
 * Raison : Article 6 — « un compteur, un badge ou un total ECRIT EN DUR dans
 * le HTML » ne se porte jamais. Recopier les huit ferait promettre cinq etats
 * que le moteur ne saurait pas honorer : `CatalogueEtatsService` le dit
 * lui-meme, « trois sont livres (M6, M8, M11), les dix autres dependent de
 * domaines non implementes ». Le decompte reel est affiche pour que l'ecart
 * se VOIE.
 *
 * ## L'HISTORIQUE EST REEL — il lit `etats_generes`
 *
 * ECART DELIBERE — `m14-etats.html` l.135-139 (`HISTORIQUE`, trois lignes de
 * demonstration)
 * Le maitre : trois editions fictives, nom et emetteur compris.
 * Ici : les lignes reelles de `etats_generes` (EF-M14-06).
 * Raison : meme Article 6. Et le nom du Product Owner porte sur une edition
 * qui n'a jamais eu lieu serait pire qu'un tableau vide — c'est un journal
 * d'audit.
 *
 * ## UN CONSTAT DE SCHEMA, RELEVE EN PORTANT CETTE PAGE
 *
 * `etats_generes.utilisateur_id` est `constrained()` SANS `nullable()`
 * (`2026_08_01_001300_create_etats.php` l.20) : toute edition a un emetteur.
 * La colonne « Emetteur » n'a donc AUCUN repli — un `?->` serait du code que
 * rien n'exerce (meme defaut que PA-150).
 *
 * Consequence a signaler, hors perimetre de ce lot :
 * `GenerateurEtatService` l.85 ecrit `'utilisateur_id' => $auteur?->id`, donc
 * potentiellement `null`, dans cette colonne NOT NULL. Le `?->` y est
 * inatteignable — `verifierAcces()` l.113 leve deja sur un auteur nul —, mais
 * il DECRIT un chemin que le schema refuserait, et c'est precisement celui
 * d'EF-M14-05 (etats recurrents planifies). Remonte au rapport, non corrige
 * ici : `app/Shared/` n'est pas au perimetre.
 *
 * ## Ce qui n'est PAS porte — Article 8, chaque motif verifie le 27/08/2026
 *
 * ECART DELIBERE — `m14-etats.html` l.129 (le bouton « Generer » de chaque
 * carte), l.66-93 (la modale « Generer un etat » : « Periode », « Format
 * d'export », « Annuler », « Generer et telecharger »)
 * Le maitre : on genere et on telecharge depuis cette page.
 * Ici : ni le bouton, ni la modale.
 * Raison : `GenerateurEtatService::generer()` l.78-92 ECRIT une ligne dans
 * `etats_generes` — `DB::transaction(fn (): EtatGenere => EtatGenere::create(...))`,
 * l'archivage horodate d'EF-M14-06. `LARAVEL_PWA.md` §2 fait du Hub M14 « la
 * seule exception a la lecture stricte » au motif que generer serait « une
 * lecture agregee, pas une ecriture transactionnelle » : la justification est
 * fausse sur ce point precis, mesuree contre le code. Ne pas archiver serait
 * pire — un document remis sans trace, ce qu'EF-M14-06 interdit. Le porter
 * suppose donc une decision du Product Owner sur le §2, pas une decision
 * d'agent.
 *
 * ECART DELIBERE — `m14-etats.html` l.156-160 (l'action de ligne
 * « Reteledecharger » de l'historique)
 * Le maitre : on retelecharge une edition passee.
 * Ici : la colonne « Actions » est rendue et vaut « — ».
 * Raison : DEUX motifs, et le second seul suffirait.
 *   1. Retelecharger passe par le meme generateur, donc archive a nouveau.
 *   2. `etats_generes.chemin_fichier_archive` vaut TOUJOURS `null` — PA-48,
 *      l'archive physique n'est pas implementee, et
 *      `GenerateurEtatService` l.88-91 l'ecrit en toutes lettres : « `null`
 *      plutot qu'un chemin fictif ». Il n'y a aucun fichier a retelecharger.
 *      Le maitre, lui, refabrique un CSV a la volee depuis les trois champs
 *      de sa ligne : ce n'est pas le document d'origine, c'est un nouveau
 *      document qui lui ressemble.
 *
 * ECART DELIBERE — `m14-etats.html` l.36-41 (« Du », « Au » et le bouton
 * « Actualiser »)
 * Le maitre : la periode filtre l'historique des editions (l.142-144).
 * Ici : les trois controles ne sont pas rendus.
 * Raison : « Actualiser » est sans objet — chaque rendu Livewire relit la
 * base, il n'y a rien a rafraichir a la main. Et les deux bornes ne peuvent
 * pas etre rendues sans lui sans devenir un filtre qui n'a pas de bouton,
 * c'est-a-dire un controle dont on ne sait pas s'il s'applique. Les rendre
 * comme filtre vif changerait le declencheur du maitre (Article 4.4).
 * Arbitrage au rapport.
 *
 * ## PLUS AUCUNE SECTION DE REFUS N'EST AFFICHEE (directive du 31/08/2026)
 *
 * L'ecran portait, sous son en-tete, un panneau de cinq lignes qui enumerait
 * ce qu'il ne fait pas. Le Product Owner l'a retire : un ecran ne catalogue
 * pas ses absences pour l'utilisateur. Les cinq motifs sont ci-dessus, mot
 * pour mot, et les jetons ci-dessous les rendent MESURABLES — c'est la seule
 * chose qui distingue une decision d'un oubli.
 *
 * ⚠ Aucun des controles refuses n'est rendu inerte pour autant : « Du »,
 * « Au », « Actualiser », « Generer » et « Reteledecharger » sont ABSENTS,
 * pas grises (Article 3.3).
 *
 * Refus declares :
 *   maitre-refuse:m14-etats.html#modale-generer-etat
 *   maitre-refuse:m14-etats.html#periode
 *   maitre-refuse:m14-etats.html#generer
 *   maitre-refuse:m14-etats.html#retelecharger
 *
 * @see EF-M14-02 Bibliotheque d'etats standards par module
 * @see EF-M14-06 Archivage horodate
 * @see RG-19 Moteur d'etats
 * @see LARAVEL_PWA.md §1, §2, §3
 */
#[Title('États, Rapports & Exports — TATACORA AFRIQUE')]
class Etats extends PageMetier
{
    /**
     * Plafond de lignes d'historique — meme choix qu'en `Achats` et
     * `JournalAudit` : `WithPagination` ajouterait SEPT methodes publiques,
     * donc sept actions Livewire, sur le chemin que `ForcerLectureSeule` ne
     * couvre pas (PA-67).
     */
    public const PLAFOND = 200;

    /**
     * Recherche + filtre de l'Historique des éditions (décision du Product
     * Owner, 01/09/2026) — filtrage SERVEUR réel, jamais du JS client.
     *
     * ⚠ Ce n'est PAS le refus « Du/Au/Actualiser » documenté plus haut : ce
     * refus visait une plage de dates calquée sur le maître, qui exigeait un
     * bouton déclencheur absent (« un filtre qui n'a pas de bouton »). Une
     * recherche `wire:model.live.debounce` n'a pas ce problème — elle
     * S'APPLIQUE elle-même, il n'y a rien à déclencher. Les deux refus
     * restent en vigueur pour ce qu'ils couvrent réellement : la plage de
     * dates et « Actualiser ».
     */
    #[Url(as: 'q')]
    public string $recherche = '';

    #[Url(as: 'module')]
    public string $moduleFiltre = '';

    /**
     * Les etats REELLEMENT editables — 1er niveau RBAC, par module SOURCE.
     *
     * @return list<array{code: string, module: string, libelle: string, niveau: string}>
     */
    protected function catalogue(CatalogueEtatsService $catalogue): array
    {
        return $catalogue->pourUtilisateur(Auth::user());
    }

    public function render(CatalogueEtatsService $catalogue): View
    {
        $requete = EtatGenere::query()->with('utilisateur');

        // Le decompte total (pour « decompte »/« tronque ») porte sur la
        // MEME portee que ce qui est affiche — recherche et filtre compris —
        // sans quoi « X affiches sur Y » comparerait deux ensembles
        // differents (meme raisonnement que PA-119 : l'export porte sur ce
        // qui est affiche, jamais sur le registre entier).
        $requete
            ->when(
                $this->recherche !== '',
                fn ($q) => $q->where('nom_etat', 'like', '%'.$this->recherche.'%'),
            )
            ->when(
                $this->moduleFiltre !== '',
                fn ($q) => $q->where('module', $this->moduleFiltre),
            );

        $total = (clone $requete)->count();

        /** @var Collection<int, EtatGenere> $editions */
        $editions = $requete
            ->orderByDesc('date_edition')
            // Depart STABLE : deux editions a la meme seconde se partageraient
            // sinon un rang indetermine.
            ->orderBy('id')
            ->limit(self::PLAFOND)
            ->get();

        return view('pwa.etats.etats', array_merge($this->socle(), [
            'catalogue' => $this->catalogue($catalogue),
            'editions' => $editions,
            'total' => $total,
            'tronque' => $total > self::PLAFOND,
            // Registre fermé du filtre — les modules réellement présents à
            // l'historique, jamais les seize modules de l'ERP dont la
            // plupart n'a jamais généré d'état.
            'modulesHistorique' => EtatGenere::query()->distinct()->orderBy('module')->pluck('module'),
            // `data-module="M14"` — celui du `<body>` du maitre (l.12).
        ]))->layout('layouts.pwa', ['module' => 'M14']);
    }
}
