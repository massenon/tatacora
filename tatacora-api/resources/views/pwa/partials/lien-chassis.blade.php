@if ($url !== null)
<a href="{{ $url }}" wire:navigate class="{{ $classes }}"{!! $attributStyle !!}>
@if ($icone !== null)
  <svg width="{{ $taille }}" height="{{ $taille }}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">{!! $icone !!}</svg>
@endif
  {{ $libelle }}
</a>
@else
<span aria-disabled="true" title="{{ __($titre) }}" class="{{ $classes }}"{!! $attributStyle !!}>
@if ($icone !== null)
  <svg width="{{ $taille }}" height="{{ $taille }}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">{!! $icone !!}</svg>
@endif
  {{ $libelle }}
</span>
@endif
