import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format/formatters.dart';
import '../../models/customer.dart';
import '../../state/customer_provider.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/section_header.dart';
import 'widgets/customer_form_dialog.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  String _query = '';

  Future<void> _addCustomer(CustomerProvider provider) async {
    final customer = await showCustomerFormDialog(context, nextId: provider.nextId);
    if (customer != null) provider.addCustomer(customer);
  }

  Future<void> _editCustomer(CustomerProvider provider, Customer customer) async {
    final updated = await showCustomerFormDialog(context, existing: customer, nextId: provider.nextId);
    if (updated != null) provider.updateCustomer(updated);
  }

  Future<void> _deleteCustomer(CustomerProvider provider, Customer customer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar cliente'),
        content: Text('¿Seguro que deseas eliminar a "${customer.name}"?'),
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
    if (confirmed == true) provider.deleteCustomer(customer.id);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CustomerProvider>();
    final customers = provider.search(_query);
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Clientes',
            subtitle: '${provider.customers.length} clientes registrados',
            actions: [
              FilledButton.icon(
                onPressed: () => _addCustomer(provider),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Nuevo cliente'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar cliente...'),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: customers.isEmpty
                ? const EmptyState(icon: Icons.people_outline, message: 'No hay clientes que coincidan.')
                : ListView.separated(
                    itemCount: customers.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final customer = customers[index];
                      return ListTile(
                        leading: CircleAvatar(child: Text(customer.name.isNotEmpty ? customer.name[0] : '?')),
                        title: Text(customer.name),
                        subtitle: Text([
                          if (customer.phone != null) customer.phone!,
                          if (customer.email != null) customer.email!,
                        ].join(' · ')),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (customer.balance > 0)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Chip(
                                  label: Text('Debe ${formatCurrency(customer.balance)}'),
                                  backgroundColor: scheme.errorContainer,
                                  labelStyle: TextStyle(color: scheme.onErrorContainer),
                                ),
                              ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _editCustomer(provider, customer),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _deleteCustomer(provider, customer),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
