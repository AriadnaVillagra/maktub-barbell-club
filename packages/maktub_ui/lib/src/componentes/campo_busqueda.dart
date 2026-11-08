import 'package:flutter/material.dart';

/// Campo de búsqueda con una X que borra todo lo escrito. La X solo aparece si hay texto.
class CampoBusqueda extends StatefulWidget {
  const CampoBusqueda({super.key, required this.hint, required this.onChanged, this.autofocus = false});

  final String hint;
  final ValueChanged<String> onChanged;
  final bool autofocus;

  @override
  State<CampoBusqueda> createState() => _CampoBusquedaState();
}

class _CampoBusquedaState extends State<CampoBusqueda> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _controller,
        autofocus: widget.autofocus,
        onChanged: (v) {
          setState(() {});
          widget.onChanged(v);
        },
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          hintText: widget.hint,
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  key: const Key('busqueda-borrar'),
                  icon: const Icon(Icons.close),
                  tooltip: 'Borrar búsqueda',
                  onPressed: () {
                    _controller.clear();
                    setState(() {});
                    widget.onChanged('');
                  },
                ),
        ),
      );
}
