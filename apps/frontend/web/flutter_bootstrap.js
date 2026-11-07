{{flutter_js}}
{{flutter_build_config}}

// No `serviceWorkerSettings` on purpose: Flutter's own loader would register
// flutter_service_worker.js (a self-unregistering stub) in the same scope and
// replace ours. The app registers maktub_sw.js from index.html instead.
_flutter.loader.load({});
