import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'formato.dart';

/// Campo numérico que se sincroniza con el valor externo (p. ej. al mover el
/// ajuste) salvo mientras el usuario lo está editando.
class CampoNumero extends StatefulWidget {
  const CampoNumero({
    super.key,
    required this.valor,
    required this.sufijo,
    required this.onCambio,
    this.decimales = true,
  });

  final num? valor;
  final String sufijo;
  final ValueChanged<num?> onCambio;
  final bool decimales;

  @override
  State<CampoNumero> createState() => _CampoNumeroState();
}

class _CampoNumeroState extends State<CampoNumero> {
  late final _control = TextEditingController(text: _texto(widget.valor));
  final _foco = FocusNode();

  String _texto(num? v) => v == null ? '' : numeroCorto(v);

  @override
  void didUpdateWidget(CampoNumero anterior) {
    super.didUpdateWidget(anterior);
    if (!_foco.hasFocus && _texto(widget.valor) != _control.text) {
      _control.text = _texto(widget.valor);
    }
  }

  @override
  void dispose() {
    _control.dispose();
    _foco.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _control,
        focusNode: _foco,
        keyboardType: TextInputType.numberWithOptions(decimal: widget.decimales),
        inputFormatters: [
          FilteringTextInputFormatter.allow(widget.decimales ? RegExp(r'[0-9.,]') : RegExp('[0-9]')),
        ],
        textAlign: TextAlign.end,
        decoration: InputDecoration(isDense: true, suffixText: widget.sufijo, border: const OutlineInputBorder()),
        onChanged: (texto) {
          final limpio = texto.replaceAll(',', '.');
          widget.onCambio(limpio.isEmpty ? null : num.tryParse(limpio));
        },
      );
}
