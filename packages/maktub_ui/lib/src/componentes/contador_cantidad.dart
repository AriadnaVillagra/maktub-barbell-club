import 'package:flutter/material.dart';

import '../tema/contexto.dart';
import '../tokens/primitivos.dart';

/// Botones − y + con la cantidad en el medio. Sin [onChanged] solo muestra el valor.
class ContadorCantidad extends StatelessWidget {
  const ContadorCantidad({super.key, required this.valor, this.minimo = 1, this.maximo = 99, this.onChanged});

  final int valor;
  final int minimo;
  final int maximo;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final cambiar = onChanged;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Espacio.xs,
      children: [
        if (cambiar != null)
          IconButton(
            key: const Key('cantidad-menos'),
            icon: const Icon(Icons.remove),
            tooltip: 'Quitar uno',
            onPressed: valor > minimo ? () => cambiar(valor - 1) : null,
          ),
        Text('$valor', style: context.numeros.chico),
        if (cambiar != null)
          IconButton(
            key: const Key('cantidad-mas'),
            icon: const Icon(Icons.add),
            tooltip: 'Agregar uno',
            onPressed: valor < maximo ? () => cambiar(valor + 1) : null,
          ),
      ],
    );
  }
}
