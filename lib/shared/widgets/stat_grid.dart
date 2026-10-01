import 'package:flutter/material.dart';

/// Grilla responsiva de [StatCard]s: ajusta el número de columnas al ancho
/// disponible en vez de usar un conteo fijo, evitando overflow en pantallas
/// angostas.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 188,
      ),
      itemCount: children.length,
      itemBuilder: (context, index) => children[index],
    );
  }
}
