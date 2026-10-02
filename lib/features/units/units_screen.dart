import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/unit.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/section_header.dart';
import '../../state/unit_provider.dart';
import 'widgets/unit_form_dialog.dart';

class UnitsScreen extends StatelessWidget {
  const UnitsScreen({super.key});

  Future<void> _addUnit(BuildContext context, UnitProvider provider) async {
    final result = await showUnitFormDialog(context, nameTaken: provider.nameTaken);
    if (result == null) return;
    await provider.addUnit(
      name: result.name,
      abbreviation: result.abbreviation,
      allowsDecimals: result.allowsDecimals,
    );
  }

  Future<void> _editUnit(BuildContext context, UnitProvider provider, Unit unit) async {
    final result = await showUnitFormDialog(context, nameTaken: provider.nameTaken, existing: unit);
    if (result == null) return;
    await provider.updateUnit(
      Unit(
        id: unit.id,
        name: result.name,
        abbreviation: result.abbreviation,
        allowsDecimals: result.allowsDecimals,
      ),
    );
  }

  Future<void> _deleteUnit(BuildContext context, UnitProvider provider, Unit unit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar unidad'),
        content: Text('¿Seguro que deseas eliminar "${unit.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await provider.deleteUnit(unit.id);
    if (result.isSuccess || !context.mounted) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No se pudo eliminar'),
        content: const Text('Hay productos usando esta unidad. Cámbialos a otra unidad primero.'),
        actions: [
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Entendido')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UnitProvider>();
    final scheme = Theme.of(context).colorScheme;
    final units = provider.units;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Unidades',
            subtitle: '${units.length} unidades registradas',
            actions: [
              FilledButton.icon(
                onPressed: () => _addUnit(context, provider),
                icon: const Icon(Icons.add),
                label: const Text('Nueva unidad'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: units.isEmpty
                ? const EmptyState(icon: Icons.straighten_outlined, message: 'No hay unidades todavía.')
                : Card(
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: scheme.outlineVariant),
                    ),
                    child: ListView.separated(
                      itemCount: units.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final unit = units[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: scheme.primaryContainer,
                            foregroundColor: scheme.onPrimaryContainer,
                            child: Text(
                              unit.label,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          title: Text(unit.name),
                          subtitle: Text(unit.allowsDecimals ? 'Permite decimales' : 'Solo cantidades enteras'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'Editar',
                                onPressed: () => _editUnit(context, provider, unit),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_outline, color: scheme.error),
                                tooltip: 'Eliminar',
                                onPressed: () => _deleteUnit(context, provider, unit),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
