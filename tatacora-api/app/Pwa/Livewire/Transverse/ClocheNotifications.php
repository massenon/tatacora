<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Transverse;

use App\Pwa\Support\AlertesOuverture;
use Illuminate\Contracts\View\View;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Livewire\Component;

/**
 * La cloche de la barre supérieure — panneau du maître (`shell.js`
 * l.128-146), branché sur les ALERTES D'OUVERTURE (audit du 01/09/2026).
 *
 * ## Ce qui a changé, et pourquoi le refus antérieur est levé
 *
 * Le bouton « Tout marquer comme lu » et le badge étaient refusés
 * (`maitre-refuse:coquille#bouton-tout-marquer-lu`, 31/08/2026) au motif
 * qu'« aucun canal n'écrit de notification » — vrai pour M12 (RG-20 ouverte),
 * mais l'audit du 01/09/2026 demande des alertes d'OUVERTURE : stock sous
 * seuil, rupture, caisse non clôturée, arrivées du jour, créances anciennes.
 * Ces alertes ont une source réelle — les tables opérationnelles — et sont
 * DÉRIVÉES à la lecture (`AlertesOuverture`), jamais stockées : le badge ne
 * peut pas affirmer un état qu'il n'a pas vérifié (PA-59/60/61). Le motif du
 * refus a cessé d'être vrai, il est levé — pas contourné.
 *
 * ## Seul composant IMBRIQUÉ de la PWA (premier du genre)
 *
 * La barre supérieure est un partial inclus par chaque page ; ses gestes
 * (« marquer lu ») sont des écritures et doivent passer par une action
 * Livewire — les poser sur chaque composant de page dupliquerait la méthode
 * sur quarante classes. Le widget est donc un composant à part entière,
 * monté dans le partial. Les ids du maître (`#bouton-cloche-notifications`,
 * `#menu-notifications`…) sont conservés : le JS de coquille qui ouvre et
 * ferme le panneau continue de fonctionner tel quel.
 *
 * ## L'écriture est HORS MODULE, et c'est déclaré
 *
 * `marquerToutLu` / `marquerLu` n'écrivent que l'état « vu » du compte QUI
 * FAIT LE GESTE (`alertes_vues`), jamais une donnée métier — même famille
 * que `MonProfil::changerMotDePasse` (voir `ECRITURES_HORS_MODULE` dans
 * `PwaEcritureAutoriseeTest`). Le RBAC s'applique en LECTURE : chaque alerte
 * est filtrée par le module qu'elle concerne, via la même source que le menu
 * (`MenuLateral::moduleAccessible`).
 */
class ClocheNotifications extends Component
{
    /** Filtre du maître : `toutes` | `non-lues`. */
    public string $filtre = 'toutes';

    public function marquerToutLu(): void
    {
        $utilisateur = auth()->user();
        if ($utilisateur === null) {
            return;
        }

        foreach (AlertesOuverture::pour($utilisateur) as $alerte) {
            if ($alerte['vue']) {
                continue;
            }

            DB::table('alertes_vues')->insertOrIgnore([
                'id' => (string) Str::uuid(),
                'utilisateur_id' => $utilisateur->id,
                'cle_alerte' => $alerte['cle'],
                'date_vue' => now(),
            ]);
        }
    }

    /** Marque UNE alerte vue — appelé au clic sur sa ligne, avant navigation. */
    public function marquerLu(string $cle): void
    {
        $utilisateur = auth()->user();
        if ($utilisateur === null) {
            return;
        }

        // La clé doit désigner une alerte réellement dérivée pour ce compte :
        // accepter n'importe quelle chaîne laisserait remplir la table de
        // lignes orphelines.
        $connues = array_column(AlertesOuverture::pour($utilisateur), 'cle');
        if (! in_array($cle, $connues, true)) {
            return;
        }

        DB::table('alertes_vues')->insertOrIgnore([
            'id' => (string) Str::uuid(),
            'utilisateur_id' => $utilisateur->id,
            'cle_alerte' => $cle,
            'date_vue' => now(),
        ]);
    }

    public function render(): View
    {
        $alertes = AlertesOuverture::pour(auth()->user());

        $nonLues = array_values(array_filter($alertes, static fn (array $a): bool => ! $a['vue']));

        return view('pwa.transverse.cloche-notifications', [
            'alertes' => $this->filtre === 'non-lues' ? $nonLues : $alertes,
            'nonLuesCompte' => count($nonLues),
            // Le pied du panneau reprend le lien de châssis du maître — même
            // source RBAC que la barre supérieure, jamais un second calcul.
            'liensChassis' => \App\Pwa\Support\MenuLateral::liensChassis(auth()->user()),
        ]);
    }
}
