<?php

declare(strict_types=1);

namespace App\Shared\Parametres\Http\Requests;

use App\Shared\Parametres\Data\RegistreParametres;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Validation de forme du lot soumis — la cohérence, elle, appartient au
 * service (elle porte sur l'état résultant, que la requête ne connaît pas).
 *
 * Les règles sont **dérivées du registre**, jamais réécrites : une seconde
 * liste finirait par accepter ici ce que le service refuse là, et l'écart
 * n'apparaîtrait qu'en production, sur un champ précis.
 */
class EnregistrerParametresRequest extends FormRequest
{
    /**
     * Le RBAC est porté par le middleware `module:PARAM,C` sur la route —
     * un seul endroit, la même source que partout ailleurs.
     */
    public function authorize(): bool
    {
        return true;
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        $regles = [
            'parametres' => ['required', 'array', 'min:1'],
            // Une clé hors registre est refusée ICI, avec le nom du champ, et
            // non par une exception générique : l'écran doit pouvoir dire
            // lequel des champs soumis pose problème.
            'parametres.*' => ['nullable'],
        ];

        foreach (RegistreParametres::definitions() as $definition) {
            $champ = 'parametres.' . $definition->cle;

            // `nullable` sur TOUS les types : vider un parametre est un etat
            // voulu, pas un oubli. L'IFU vide fait disparaitre la mention du
            // document plutot que d'imprimer un exemple de format ; le taux de
            // risques professionnels vide fait publier la charge patronale en
            // fourchette. Sans `nullable`, `numeric` refuserait `null` et ces
            // deux etats deviendraient inatteignables une fois renseignes.
            $regles[$champ] = match ($definition->type) {
                'booleen' => ['sometimes', 'boolean'],
                'choix' => ['sometimes', 'nullable', 'string', Rule::in($definition->choix)],
                default => ['sometimes', 'nullable', ...array_values(array_filter(
                    $definition->regles,
                    static fn (string $regle): bool => $regle !== 'nullable',
                ))],
            };
        }

        return $regles;
    }

    /**
     * Les clés inconnues sont écartées avant validation plutôt qu'ignorées
     * silencieusement : une faute de frappe sur `taux_tva` doit se voir, sans
     * quoi l'écran confirmerait un enregistrement qui n'a rien changé.
     */
    public function withValidator(\Illuminate\Validation\Validator $validator): void
    {
        $validator->after(function ($validator): void {
            /** @var array<string, mixed> $soumis */
            $soumis = (array) $this->input('parametres', []);

            foreach (array_keys($soumis) as $cle) {
                if (! RegistreParametres::existe((string) $cle)) {
                    $validator->errors()->add(
                        'parametres.' . $cle,
                        __('parametres.cle_inconnue', ['cle' => (string) $cle]),
                    );
                }
            }
        });
    }
}
