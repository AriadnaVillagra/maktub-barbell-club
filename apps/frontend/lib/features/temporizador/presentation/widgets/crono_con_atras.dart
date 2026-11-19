import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/web/browser_history.dart';
import '../controllers/crono_controller.dart';

/// With a timer open, the phone's back closes the timer and stays on the screen, instead of leaving the screen with
/// the timer still running (Ari, 2026-11-19).
///
/// In the browser (the PWA) back is a step in the browser's history, which only the router hears. So opening a timer
/// adds a step to it: the same screen with `?crono=1`. Going back from there lands on the same screen without the
/// mark, and that closes the timer. Closing the timer otherwise (its ✕, or it ends) takes that step back, so no empty
/// step is left. Leaving the screen with the timer open keeps it running, as before. Outside the browser the
/// system's back button closes it directly.
class CronoConAtras extends ConsumerStatefulWidget {
  const CronoConAtras({
    super.key,
    required this.child,
    this.enNavegador = kIsWeb,
    this.volverAtras = browserHistoryBack,
  });

  final Widget child;

  /// Whether back is the browser's history (the PWA). Tests set it.
  final bool enNavegador;

  /// Takes one step back in that history. Tests replace it.
  final void Function() volverAtras;

  /// The query parameter that marks the step a timer added.
  static const marca = 'crono';

  @override
  ConsumerState<CronoConAtras> createState() => _CronoConAtrasState();
}

class _CronoConAtrasState extends ConsumerState<CronoConAtras> {
  GoRouter? _router;

  /// The path of the screen where the step was added, while it is there.
  String? _marcada;

  Uri get _actual => _router!.routeInformationProvider.value.uri;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.of(context);
    if (identical(router, _router)) return;
    _router?.routeInformationProvider.removeListener(_alCambiarRuta);
    _router = router..routeInformationProvider.addListener(_alCambiarRuta);
  }

  @override
  void dispose() {
    _router?.routeInformationProvider.removeListener(_alCambiarRuta);
    super.dispose();
  }

  void _marcar() {
    if (!widget.enNavegador) return;
    final uri = _actual;
    if (uri.queryParameters.containsKey(CronoConAtras.marca)) return;
    _marcada = uri.path;
    _router!.go(uri.replace(queryParameters: {...uri.queryParameters, CronoConAtras.marca: '1'}).toString());
  }

  /// The timer closed by itself or from its ✕: the step it added goes away.
  void _desmarcar() {
    if (_marcada == null) return;
    final enElPaso = _actual.queryParameters.containsKey(CronoConAtras.marca) && _actual.path == _marcada;
    _marcada = null;
    if (enElPaso) widget.volverAtras();
  }

  void _alCambiarRuta() {
    final marcada = _marcada;
    if (marcada == null || _actual.queryParameters.containsKey(CronoConAtras.marca)) return;
    _marcada = null;
    // Back from the step: same screen without the mark. Anything else is leaving the screen; the timer goes on.
    if (_actual.path == marcada && ref.read(cronoControllerProvider) != null) {
      ref.read(cronoControllerProvider.notifier).detener();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(cronoControllerProvider, (antes, ahora) {
      if (antes == null && ahora != null) _marcar();
      if (antes != null && ahora == null) _desmarcar();
    });
    final abierto = ref.watch(cronoControllerProvider) != null;
    return BackButtonListener(
      onBackButtonPressed: () async {
        if (!abierto) return false;
        ref.read(cronoControllerProvider.notifier).detener();
        return true;
      },
      child: widget.child,
    );
  }
}
