import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format/formatters.dart';
import '../../models/sale.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/feedback_alert.dart';
import '../../shared/widgets/section_header.dart';
import '../../state/cash_provider.dart';
import '../../state/sales_provider.dart';
import 'data/sale_repository.dart';
import 'widgets/sale_detail_dialog.dart';

enum _Period { today, week, month, custom }

enum _StatusFilter { all, completed, voided }

/// Historial de ventas: buscar por folio o cliente, filtrar por período y
/// estado, ver el detalle y anular. Los períodos rápidos y el rango
/// personalizado se leen directo de la base de datos, así que se puede
/// consultar cualquier fecha, con un máximo de [_maxRangeDays] días por
/// consulta para no cargar el historial completo en memoria.
class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  /// Rango máximo de una consulta: un año (inclusive).
  static const int _maxRangeDays = 366;

  /// Fecha más antigua que ofrece el selector.
  static final DateTime _earliestDate = DateTime(2020);

  String _query = '';
  _Period _period = _Period.today;
  _StatusFilter _status = _StatusFilter.all;
  late DateTimeRange _range;
  late Stream<List<Sale>> _stream;

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    _apply(_Period.today, DateTimeRange(start: _today(), end: _today()), notify: false);
  }

  /// Fija el rango (días completos, `end` inclusive) y abre la consulta.
  void _apply(_Period period, DateTimeRange range, {bool notify = true}) {
    void update() {
      _period = period;
      _range = range;
      // El día final es inclusivo: la consulta llega hasta el día siguiente.
      _stream = context.read<SalesProvider>().watchRange(
            range.start,
            DateTime(range.end.year, range.end.month, range.end.day + 1),
          );
    }

    notify ? setState(update) : update();
  }

  void _selectPreset(_Period period) {
    final today = _today();
    final days = switch (period) {
      _Period.today => 0,
      _Period.week => 6,
      _ => 29,
    };
    _apply(period, DateTimeRange(start: today.subtract(Duration(days: days)), end: today));
  }

  /// Rango clásico "Desde / Hasta": cada campo abre un calendario de un solo
  /// día. Si la fecha elegida deja el rango al revés, el otro extremo se
  /// ajusta para que sea ese mismo día.
  Future<void> _pickDate({required bool isStart}) async {
    final current = isStart ? _range.start : _range.end;
    final date = await showDatePicker(
      context: context,
      firstDate: _earliestDate,
      lastDate: _today(),
      initialDate: current,
      helpText: isStart ? 'Fecha inicial' : 'Fecha final',
    );
    if (date == null || !mounted) return;

    final picked = isStart
        ? DateTimeRange(start: date, end: date.isAfter(_range.end) ? date : _range.end)
        : DateTimeRange(start: date.isBefore(_range.start) ? date : _range.start, end: date);
    if (picked.duration.inDays + 1 > _maxRangeDays) {
      FeedbackAlert.show(
        context,
        type: FeedbackType.warning,
        title: 'Rango demasiado largo',
        message: 'Elige un rango de máximo 1 año',
      );
      return;
    }
    _apply(_Period.custom, picked);
  }

  List<Sale> _filtered(List<Sale> all) {
    final query = _query.trim().toLowerCase();
    return all.where((sale) {
      if (_status == _StatusFilter.completed && sale.isVoided) return false;
      if (_status == _StatusFilter.voided && !sale.isVoided) return false;
      if (query.isEmpty) return true;
      return sale.receiptNumber.toLowerCase().contains(query) ||
          (sale.customerName ?? '').toLowerCase().contains(query);
    }).toList();
  }

  String get _rangeLabel => _range.start == _range.end
      ? dateFormatFull.format(_range.start)
      : '${dateFormatFull.format(_range.start)} – ${dateFormatFull.format(_range.end)}';

  Future<void> _open(Sale sale) async {
    final reason = await showSaleDetailDialog(context, sale);
    if (reason == null || !mounted) return;

    final cashSessionId = context.read<CashProvider>().current?.id;
    try {
      await context.read<SalesProvider>().voidSale(
            saleId: sale.id,
            reason: reason,
            cashSessionId: cashSessionId,
          );
    } on CashSessionClosedException {
      if (!mounted) return;
      FeedbackAlert.show(
        context,
        type: FeedbackType.error,
        title: 'Abre la caja para anular',
        message: 'Esta venta fue en efectivo: la devolución sale de la caja',
      );
      return;
    } on SaleAlreadyVoidedException catch (e) {
      if (!mounted) return;
      FeedbackAlert.show(context, type: FeedbackType.warning, title: e.toString());
      return;
    }
    if (!mounted) return;
    FeedbackAlert.show(
      context,
      type: FeedbackType.success,
      title: 'Venta anulada',
      message: '${sale.receiptNumber} · existencias devueltas',
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: StreamBuilder<List<Sale>>(
        stream: _stream,
        builder: (context, snapshot) {
          final sales = _filtered(snapshot.data ?? const []);
          final validTotal = sales.where((s) => !s.isVoided).fold(0.0, (sum, s) => sum + s.total);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: 'Ventas',
                subtitle: '$_rangeLabel · ${sales.length} ventas · ${formatCurrency(validTotal)} vigentes',
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 280,
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Buscar por folio o cliente...',
                      ),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ),
                  SegmentedButton<_Period>(
                    showSelectedIcon: false,
                    emptySelectionAllowed: true,
                    segments: const [
                      ButtonSegment(value: _Period.today, label: Text('Hoy')),
                      ButtonSegment(value: _Period.week, label: Text('7 días')),
                      ButtonSegment(value: _Period.month, label: Text('30 días')),
                    ],
                    // En modo "rango" ningún período rápido queda marcado.
                    selected: _period == _Period.custom ? {} : {_period},
                    onSelectionChanged: (value) {
                      if (value.isNotEmpty) _selectPreset(value.first);
                    },
                  ),
                  _DateField(
                    label: 'Desde',
                    date: _range.start,
                    onTap: () => _pickDate(isStart: true),
                  ),
                  _DateField(
                    label: 'Hasta',
                    date: _range.end,
                    onTap: () => _pickDate(isStart: false),
                  ),
                  SegmentedButton<_StatusFilter>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: _StatusFilter.all, label: Text('Todas')),
                      ButtonSegment(value: _StatusFilter.completed, label: Text('Vigentes')),
                      ButtonSegment(value: _StatusFilter.voided, label: Text('Anuladas')),
                    ],
                    selected: {_status},
                    onSelectionChanged: (value) => setState(() => _status = value.first),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: sales.isEmpty
                    ? const EmptyState(icon: Icons.receipt_long_outlined, message: 'No hay ventas que coincidan.')
                    : ListView.separated(
                        itemCount: sales.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final sale = sales[index];
                          final strike = sale.isVoided
                              ? TextStyle(
                                  decoration: TextDecoration.lineThrough,
                                  color: scheme.onSurfaceVariant,
                                )
                              : null;
                          return ListTile(
                            onTap: () => _open(sale),
                            leading: Icon(
                              sale.isVoided ? Icons.cancel_outlined : Icons.receipt_long_outlined,
                              color: sale.isVoided ? scheme.error : null,
                            ),
                            title: Text(
                              '${sale.receiptNumber} · ${formatQuantity(sale.itemCount)} artículos · ${sale.paymentMethod.label}',
                              style: strike,
                            ),
                            subtitle: Text([
                              dateTimeFormat.format(sale.date),
                              if (sale.customerName != null) sale.customerName!,
                              if (sale.isVoided) 'ANULADA',
                            ].join(' · ')),
                            trailing: Text(
                              formatCurrency(sale.total),
                              style: TextStyle(fontWeight: FontWeight.bold, decoration: strike?.decoration),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Campo de fecha de solo lectura: al tocarlo abre el calendario.
class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.date, required this.onTap});

  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
          ),
          child: Text(dateFormatFull.format(date)),
        ),
      ),
    );
  }
}
