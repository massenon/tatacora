<div class="flex items-start gap-2.5 mb-2">
  <div class="w-9 h-9 rounded-lg flex items-center justify-center shrink-0" style="background:{{ $ouvert ? '#FDF3E0' : '#F3F4F6' }}">
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="{{ $ouvert ? 'var(--gold)' : '#9CA3AF' }}" stroke-width="2">{!! $carte['icone'] !!}</svg>
  </div>
  <div class="min-w-0">
    <p class="text-[15px] font-bold leading-tight {{ $ouvert ? 'text-slate-800' : 'text-slate-400' }}">{{ $carte['nom'] }}</p>
    <p class="text-[12px] font-mono-tatacora {{ $ouvert ? 'text-slate-400' : 'text-slate-300' }}">{{ $carte['code'] }}</p>
  </div>
  @if (! $ouvert)
    <span class="ml-auto shrink-0 text-[10px] font-bold rounded px-1.5 py-0.5 bg-slate-100 text-slate-400">{{ __('pwa.aide.badge_sans_acces') }}</span>
  @elseif ($carte['niveau'] === 'L')
    <span class="ml-auto shrink-0 text-[10px] font-bold rounded px-1.5 py-0.5" style="background:#E8EEFD;color:#1D4ED8">{{ __('pwa.aide.badge_lecture') }}</span>
  @endif
</div>
<p class="text-[13px] leading-relaxed {{ $ouvert ? 'text-slate-500' : 'text-slate-400' }}">{{ $carte['description'] }}</p>
