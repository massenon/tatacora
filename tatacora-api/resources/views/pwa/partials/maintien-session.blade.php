{{--
    MAINTIEN DE SESSION (audit PO du 01/09/2026) — « quand les paniers sont
    actifs, la session ne doit pas se terminer : pas de page expirée tant que
    les paniers ne sont pas fermés et la caisse clôturée. »

    Un panier ouvert n'existe que sur ce poste : une session expirée au
    moment de le clôturer perdrait la seule copie de la saisie (même risque
    que PA-106, la croix de la fenêtre Windows). Ce partial rend un battement
    Livewire (`wire:poll`) qui rafraîchit la session côté serveur toutes les
    quatre minutes — bien sous `SESSION_LIFETIME` — tant que la CONDITION est
    vraie : un panier ouvert, ou une session de caisse non clôturée.

    Il ne se rend PAS quand la condition est fausse : maintenir en vie la
    session d'un écran au repos annulerait l'expiration voulue partout
    ailleurs. Le battement est un `$refresh` du cadre — jamais une méthode
    qui affirmerait autre chose que « je suis encore là » (PA-59/60/61).
--}}
@if ($maintenir)
  <span wire:poll.240s data-maintien-session class="hidden" aria-hidden="true"></span>
@endif
