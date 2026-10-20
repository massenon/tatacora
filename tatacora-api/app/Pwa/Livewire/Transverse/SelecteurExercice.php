<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Transverse;

use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Pwa\Support\ExerciceConsulte;
use Illuminate\Contracts\View\View;
use Livewire\Component;

/**
 * Le SÉLECTEUR D'EXERCICE de la barre supérieure
 * (`docs/SPEC_SELECTEUR_EXERCICE.md`, R1/R3 — décisions du PO du
 * 20/10/2026). Composant imbriqué, comme la cloche et la recherche : la barre
 * est rendue par chaque écran, le widget a UN propriétaire.
 *
 * Il n'est affiché que sur les écrans qui le suivent
 * (`ExerciceConsulte::ROUTES`), pour tout rôle qui peut les ouvrir : choisir
 * une année n'écrit rien, ne donne accès à rien — l'écran garde ses droits.
 *
 * Le choix vit dans la SESSION (`ExerciceConsulte`) ; changer d'exercice
 * recharge l'écran courant, sans son `?exercice=` (l'exercice de la session
 * prend la place) ni sa page de liste (`?page=`).
 */
class SelecteurExercice extends Component
{
    public string $exerciceId = '';

    /** Affiché seulement sur un écran qui suit le sélecteur — fixé au montage. */
    public bool $visible = false;

    /** L'écran à recharger — chemin et requête de la page, jamais un hôte. */
    public string $retour = '';

    public function mount(): void
    {
        $this->visible = ExerciceConsulte::suitLeSelecteur();
        $this->exerciceId = (string) ExerciceConsulte::exercice()?->id;
        $this->retour = (string) request()->getRequestUri();
    }

    public function updatedExerciceId(): void
    {
        ExerciceConsulte::choisir($this->exerciceId);
        $this->recharger();
    }

    public function revenir(): void
    {
        ExerciceConsulte::revenirAuDefaut();
        $this->recharger();
    }

    public function render(): View
    {
        $consulte = ExerciceConsulte::exercice();

        return view('pwa.transverse.selecteur-exercice', [
            'exercices' => ExerciceComptable::query()->orderByDesc('annee')->get(),
            'consulte' => $consulte,
            'defaut' => ExerciceConsulte::defaut(),
            'autreQueDefaut' => ExerciceConsulte::estAutreQueDefaut(),
        ]);
    }

    /**
     * Recharge l'écran courant. Seuls le CHEMIN et la requête de `retour` sont
     * repris, l'hôte jamais : la propriété vient du navigateur, et une adresse
     * externe glissée là ferait du sélecteur une redirection ouverte.
     */
    private function recharger(): void
    {
        $chemin = (string) (parse_url($this->retour, PHP_URL_PATH) ?: '/');
        if (! str_starts_with($chemin, '/') || str_starts_with($chemin, '//')) {
            $chemin = '/';
        }

        parse_str((string) parse_url($this->retour, PHP_URL_QUERY), $requete);
        unset($requete['exercice'], $requete['page']);

        $this->redirect(url($chemin).($requete === [] ? '' : '?'.http_build_query($requete)), navigate: true);
    }
}
