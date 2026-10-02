import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/categories/data/category_repository.dart';
import '../../models/category.dart';
import '../../state/category_provider.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/section_header.dart';
import 'category_icon_options.dart';
import 'widgets/category_form_dialog.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  List<Category> _selectableParentsFor(CategoryProvider provider, Category? editing) {
    if (editing == null) return provider.categories;
    final excluded = {editing.id, ...provider.descendantsOf(editing.id)};
    return provider.categories.where((c) => !excluded.contains(c.id)).toList();
  }

  Future<void> _addCategory(BuildContext context, CategoryProvider provider, {String? parentId}) async {
    final result = await showCategoryFormDialog(
      context,
      selectableParents: _selectableParentsFor(provider, null),
      initialParentId: parentId,
      suggestedColor: provider.nextSuggestedColor(),
    );
    if (result == null) return;
    await provider.addCategory(
      name: result.name,
      description: result.description,
      parentId: result.parentId,
      icon: result.icon,
      color: result.color,
    );
  }

  Future<void> _editCategory(BuildContext context, CategoryProvider provider, Category category) async {
    final result = await showCategoryFormDialog(
      context,
      selectableParents: _selectableParentsFor(provider, category),
      existing: category,
    );
    if (result == null) return;
    await provider.updateCategory(
      Category(
        id: category.id,
        name: result.name,
        description: result.description,
        parentId: result.parentId,
        icon: result.icon,
        color: result.color,
      ),
    );
  }

  Future<void> _deleteCategory(BuildContext context, CategoryProvider provider, Category category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar categoría'),
        content: Text('¿Seguro que deseas eliminar "${category.name}"?'),
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

    final result = await provider.deleteCategory(category.id);
    if (result.isSuccess || !context.mounted) return;

    final message = result.error == DeleteCategoryError.hasChildren
        ? 'No se puede eliminar: tiene subcategorías dentro. Elimínalas o muévelas primero.'
        : 'No se puede eliminar: hay productos usando esta categoría.';
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No se pudo eliminar'),
        content: Text(message),
        actions: [
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Entendido')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CategoryProvider>();
    final tree = provider.tree;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Categorías',
            subtitle: '${provider.categories.length} categorías registradas',
            actions: [
              FilledButton.icon(
                onPressed: () => _addCategory(context, provider),
                icon: const Icon(Icons.add),
                label: const Text('Nueva categoría'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: tree.isEmpty
                ? const EmptyState(icon: Icons.category_outlined, message: 'No hay categorías todavía.')
                : ListView(
                    children: [
                      for (final node in tree)
                        _CategoryNodeTile(
                          node: node,
                          onAddChild: (parent) => _addCategory(context, provider, parentId: parent.id),
                          onEdit: (c) => _editCategory(context, provider, c),
                          onDelete: (c) => _deleteCategory(context, provider, c),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _CategoryNodeTile extends StatelessWidget {
  const _CategoryNodeTile({
    required this.node,
    required this.onAddChild,
    required this.onEdit,
    required this.onDelete,
  });

  final CategoryNode node;
  final ValueChanged<Category> onAddChild;
  final ValueChanged<Category> onEdit;
  final ValueChanged<Category> onDelete;

  @override
  Widget build(BuildContext context) {
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: 'Agregar subcategoría',
          onPressed: () => onAddChild(node.category),
        ),
        IconButton(
          icon: const Icon(Icons.edit_outlined),
          tooltip: 'Editar',
          onPressed: () => onEdit(node.category),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Eliminar',
          onPressed: () => onDelete(node.category),
        ),
      ],
    );

    if (node.children.isEmpty) {
      return ListTile(
        leading: Icon(
          iconDataFor(node.category.icon),
          color: Color(context.read<CategoryProvider>().colorValueFor(node.category.id)),
        ),
        title: Text(node.category.name),
        subtitle: node.category.description != null ? Text(node.category.description!) : null,
        trailing: actions,
      );
    }

    return ExpansionTile(
      leading: Icon(
          iconDataFor(node.category.icon),
          color: Color(context.read<CategoryProvider>().colorValueFor(node.category.id)),
        ),
      title: Text(node.category.name),
      subtitle: node.category.description != null ? Text(node.category.description!) : null,
      trailing: actions,
      children: [
        for (final child in node.children)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: _CategoryNodeTile(
              node: child,
              onAddChild: onAddChild,
              onEdit: onEdit,
              onDelete: onDelete,
            ),
          ),
      ],
    );
  }
}
