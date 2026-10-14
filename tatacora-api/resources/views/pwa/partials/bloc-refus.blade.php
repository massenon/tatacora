@if ($refus !== [])
  <div class="rounded-xl p-3.5 mb-4" style="background:#F8FAFC;border:1px solid #E2E8F0">
    <p class="text-[13px] font-bold mb-1.5" style="color:#334155">{{ __('pwa.refus_titre') }}</p>
    <ul class="list-disc pl-5 space-y-1">
      @foreach ($refus as $ligne)
        <li class="text-[12px]" style="color:#334155">{{ $ligne }}</li>
      @endforeach
    </ul>
  </div>
@endif
