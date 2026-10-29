<?php

declare(strict_types=1);

namespace App\Console\Commands;

use App\Models\User;
use App\Shared\Auth\Services\MotDePassePerduService;
use Illuminate\Console\Command;
use RuntimeException;

/**
 * `php artisan tatacora:code-secours [login]` — génère le CODE DE SECOURS d'un
 * administrateur et l'affiche UNE seule fois (décision du PO du 29/10/2026).
 *
 * C'est le chemin du PREMIER administrateur du serveur (aucun écran d'amorçage
 * n'existe côté web) et celui de tout administrateur d'avant ce lot, qui n'a pas
 * de code. Seule l'empreinte du code est stockée ; relancer la commande en
 * remplace le code (l'ancien cesse de fonctionner).
 *
 * Sans argument : s'il n'existe qu'UN administrateur actif, c'est lui ;
 * autrement la commande refuse et demande le login (jamais un choix au hasard).
 */
final class CodeSecoursCommand extends Command
{
    protected $signature = 'tatacora:code-secours {login? : Le nom d\'utilisateur de l\'administrateur}';

    protected $description = 'Génère le code de secours à usage unique d\'un administrateur et l\'affiche une seule fois.';

    public function handle(MotDePassePerduService $service): int
    {
        $administrateur = $this->administrateur((string) ($this->argument('login') ?? ''));

        if ($administrateur === null) {
            return self::FAILURE;
        }

        try {
            $code = $service->poserCodeDeSecours($administrateur, null);
        } catch (RuntimeException $refus) {
            $this->error($refus->getMessage());

            return self::FAILURE;
        }

        $this->newLine();
        $this->info('Code de secours de « '.$administrateur->login.' » :');
        $this->newLine();
        $this->line('    '.$code);
        $this->newLine();
        $this->warn('Ce code ne sera plus jamais affiché. Notez-le ou imprimez-le et rangez-le au coffre.');
        $this->line('Il ne sert qu\'une fois : après usage, un nouveau code est remis.');

        return self::SUCCESS;
    }

    private function administrateur(string $login): ?User
    {
        $requete = User::query()->with('role')->where('statut', 'actif');

        if ($login !== '') {
            $trouve = (clone $requete)->where('login', $login)->first();

            if ($trouve === null || ! $trouve->estAdministrateur()) {
                $this->error('Aucun administrateur actif ne porte ce nom d\'utilisateur.');

                return null;
            }

            return $trouve;
        }

        $administrateurs = $requete->get()->filter(static fn (User $u): bool => $u->estAdministrateur())->values();

        if ($administrateurs->count() !== 1) {
            $this->error($administrateurs->isEmpty()
                ? 'Aucun administrateur actif.'
                : 'Plusieurs administrateurs actifs : précisez le nom d\'utilisateur.');

            return null;
        }

        /** @var User $seul */
        $seul = $administrateurs->first();

        return $seul;
    }
}
