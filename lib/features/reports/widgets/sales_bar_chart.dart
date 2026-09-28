import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/format/formatters.dart';

class SalesBarChart extends StatelessWidget {
  const SalesBarChart({super.key, required this.data});

  /// Lista de (día, total vendido) en orden cronológico.
  final List<MapEntry<DateTime, double>> data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxValue = data.map((e) => e.value).fold<double>(0, (a, b) => a > b ? a : b);
    final maxY = maxValue <= 0 ? 100.0 : maxValue * 1.2;

    return BarChart(
      BarChartData(
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 56,
              getTitlesWidget: (value, meta) => Text(
                formatCurrency(value),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= data.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(weekdayFormat.format(data[index].key), style: Theme.of(context).textTheme.bodySmall),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (int i = 0; i < data.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: data[i].value,
                  color: scheme.primary,
                  width: 22,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
