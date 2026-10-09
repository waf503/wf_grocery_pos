import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format/formatters.dart';
import '../../models/customer.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/feedback_alert.dart';
import '../../shared/widgets/section_header.dart';
import '../../state/cash_provider.dart';
import '../../state/customer_provider.dart';
import 'data/customer_repository.dart';
import 'widgets/customer_form_dialog.dart';
import 'widgets/payment_dialog.dart';
import 'widgets/statement_dialog.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  String _query = '';

  Future<void> _addCustomer(CustomerProvider provider) async {
    final data = await showCustomerFormDialog(context);
    if (data == null) return;
    await provider.addCustomer(name: data.name, phone: data.phone, email: data.email);
  }

  Future<void> _editCustomer(CustomerProvider provider, Customer customer) async {
    final data = await showCustomerFormDialog(context, existing: customer);
    if (data == null) return;
    await provider.updateCustomer(
      Customer(id: customer.id, name: data.name, phone: data.phone, email: data.email),
    );
  }

  Future<void> _registerPayment(CustomerProvider provider, Customer customer) async {
    final cashSession = context.read<CashProvider>().current;
    final payment = await showPaymentDialog(context, customer: customer, cashOpen: cashSession != null);
    if (payment == null) return;
    try {
      await provider.registerPayment(
        customerId: customer.id,
        amountCents: payment.amountCents,
        cashSessionId: payment.inCash ? cashSession?.id : null,
      );
    } on PaymentExceedsBalanceException {
      if (!mounted) return;
      FeedbackAlert.show(context, type: FeedbackType.error, title: 'El abono excede el saldo');
      return;
    }
    if (!mounted) return;
    FeedbackAlert.show(
      context,
      type: FeedbackType.success,
      title: 'Abono registrado',
      message: customer.name,
    );
  }

  Future<void> _deleteCustomer(CustomerProvider provider, Customer customer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar cliente'),
        content: Text('¿Seguro que deseas eliminar a "${customer.name}"? Sus ventas anteriores se conservan.'),
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
    final result = await provider.deleteCustomer(customer.id);
    if (!mounted) return;
    if (result == DeleteCustomerResult.hasBalance) {
      FeedbackAlert.show(
        context,
        type: FeedbackType.error,
        title: 'No se puede eliminar',
        message: '${customer.name} aún debe ${formatCurrency(customer.balance)}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CustomerProvider>();
    final customers = provider.search(_query);
    final scheme = Theme.of(context).colorScheme;
    final receivable = provider.totalReceivableCents / 100;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Clientes',
            subtitle: '${provider.customers.length} clientes · por cobrar ${formatCurrency(receivable)}',
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
                ? EmptyState(
                    icon: Icons.people_outline,
                    message: provider.customers.isEmpty
                        ? 'Aún no hay clientes.\nAgrega uno para poder vender a crédito.'
                        : 'No hay clientes que coincidan.',
                  )
                : ListView.separated(
                    itemCount: customers.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final customer = customers[index];
                      final owes = customer.balanceCents > 0;
                      return ListTile(
                        leading: CircleAvatar(child: Text(customer.name.isNotEmpty ? customer.name[0] : '?')),
                        title: Text(customer.name),
                        subtitle: Text([
                          if (customer.phone != null) customer.phone!,
                          if (customer.email != null) customer.email!,
                        ].join(' · ')),
                        onTap: () => showStatementDialog(context, customer),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (owes)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Chip(
                                  label: Text('Debe ${formatCurrency(customer.balance)}'),
                                  backgroundColor: scheme.errorContainer,
                                  labelStyle: TextStyle(color: scheme.onErrorContainer),
                                ),
                              ),
                            if (owes)
                              FilledButton.tonalIcon(
                                onPressed: () => _registerPayment(provider, customer),
                                icon: const Icon(Icons.payments_outlined, size: 18),
                                label: const Text('Abonar'),
                              ),
                            IconButton(
                              tooltip: 'Estado de cuenta',
                              icon: const Icon(Icons.receipt_long_outlined),
                              onPressed: () => showStatementDialog(context, customer),
                            ),
                            IconButton(
                              tooltip: 'Editar',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _editCustomer(provider, customer),
                            ),
                            IconButton(
                              tooltip: 'Eliminar',
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
