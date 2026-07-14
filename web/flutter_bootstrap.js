// Custom bootstrap: pin CanvasKit to the copy shipped in this build instead
// of Google's CDN (the tool's default). Local-first / no-phone-home (golden
// rule #6) — and the app must boot with no network at all.
{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    canvasKitBaseUrl: 'canvaskit/',
  },
});
