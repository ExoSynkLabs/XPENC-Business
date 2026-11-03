import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../core/widgets/money_text.dart';
import 'biz_book.dart';

/// One month's income and costs.
typedef MonthFlow = ({DateTime month, Money income, Money costs});

/// Income (sales + other income) and costs (purchases + every expense) for
/// the [count] months ending with [end]'s month.
List<MonthFlow> monthlyFlows(BizBook book, DateTime end, {int count = 6}) => [
  for (var i = count - 1; i >= 0; i--)
    () {
      final m = DateTime(end.year, end.month - i);
      final pl = book.profitAndLoss(BizPeriod.month(m));
      return (
        month: m,
        income:
            pl.sales.total + pl.directIncome.total + pl.indirectIncome.total,
        costs:
            pl.purchase.total +
            pl.directExpense.total +
            pl.indirectExpense.total,
      );
    }(),
];

// Categorical slots 1 & 2 (blue, orange), validated as a pair for CVD and
// normal-vision separation and ≥ 3:1 against the app's light (#FFFFFF) and
// dark (#17171A) card surfaces. Dark mode uses its own steps, not a flip.
const _incomeLight = Color(0xFF2A78D6);
const _costsLight = Color(0xFFEB6834);
const _incomeDark = Color(0xFF3987E5);
const _costsDark = Color(0xFFD95926);

/// Grouped columns: income vs costs per month. Tap a month to read its
/// values; the latest month is read out by default. One axis, recessive
/// grid, legend always present (two series), values in text ink.
class TrendChart extends StatefulWidget {
  const TrendChart({required this.flows, super.key});
  final List<MonthFlow> flows;

  @override
  State<TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<TrendChart> {
  late int _selected = widget.flows.length - 1;

  @override
  void didUpdateWidget(TrendChart old) {
    super.didUpdateWidget(old);
    if (_selected >= widget.flows.length) _selected = widget.flows.length - 1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final income = dark ? _incomeDark : _incomeLight;
    final costs = dark ? _costsDark : _costsLight;
    final flows = widget.flows;
    final sel = flows[_selected];
    final net = sel.income - sel.costs;
    final muted = theme.textTheme.labelSmall?.copyWith(
      color: cs.onSurfaceVariant,
    );

    Widget swatch(Color c, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.labelMedium),
      ],
    );

    final summary = flows
        .map(
          (f) =>
              '${DateFormat('MMMM').format(f.month)}: income ${MoneyFormat.symbol(f.income)}, '
              'costs ${MoneyFormat.symbol(f.costs)}',
        )
        .join('; ');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                swatch(income, 'Income'),
                const SizedBox(width: 16),
                swatch(costs, 'Costs'),
              ],
            ),
            const SizedBox(height: 10),
            // Read-out for the tapped month — text ink, not series colour.
            Wrap(
              spacing: 14,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  DateFormat('MMMM yyyy').format(sel.month),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                _ReadOut(label: 'Income', amount: sel.income),
                _ReadOut(label: 'Costs', amount: sel.costs),
                _ReadOut(
                  label: net.isNegative ? 'Loss' : 'Surplus',
                  amount: net.abs,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Semantics(
              label: 'Income and costs by month. $summary',
              child: LayoutBuilder(
                builder: (context, c) {
                  final groupW = c.maxWidth / flows.length;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => setState(
                      () => _selected = (d.localPosition.dx ~/ groupW).clamp(
                        0,
                        flows.length - 1,
                      ),
                    ),
                    child: CustomPaint(
                      size: Size(c.maxWidth, 140),
                      painter: _ColumnsPainter(
                        flows: flows,
                        selected: _selected,
                        income: income,
                        costs: costs,
                        grid: cs.outline,
                        highlight: cs.onSurface.withValues(alpha: 0.06),
                        surface: theme.cardTheme.color ?? cs.surface,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (var i = 0; i < flows.length; i++)
                  Expanded(
                    child: Text(
                      DateFormat('MMM').format(flows[i].month),
                      textAlign: TextAlign.center,
                      style: muted?.copyWith(
                        fontWeight: i == _selected
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: i == _selected
                            ? cs.onSurface
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadOut extends StatelessWidget {
  const _ReadOut({required this.label, required this.amount});
  final String label;
  final Money amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label ',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        MoneyText(
          amount,
          compact: true,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ColumnsPainter extends CustomPainter {
  _ColumnsPainter({
    required this.flows,
    required this.selected,
    required this.income,
    required this.costs,
    required this.grid,
    required this.highlight,
    required this.surface,
  });

  final List<MonthFlow> flows;
  final int selected;
  final Color income;
  final Color costs;
  final Color grid;
  final Color highlight;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = flows.fold<int>(
      0,
      (m, f) =>
          [m, f.income.paise, f.costs.paise].reduce((a, b) => a > b ? a : b),
    );
    final top = 6.0;
    final base = size.height - 1;
    final plotH = base - top;
    final groupW = size.width / flows.length;

    // Selected-month band, then a recessive grid: quarter lines + baseline.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(groupW * selected + 2, 0, groupW - 4, size.height),
        const Radius.circular(8),
      ),
      Paint()..color = highlight,
    );
    final gridPaint = Paint()
      ..color = grid.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (final f in const [0.25, 0.5, 0.75]) {
      final y = base - plotH * f;
      for (var x = 0.0; x < size.width; x += 6) {
        canvas.drawLine(Offset(x, y), Offset(x + 3, y), gridPaint);
      }
    }
    canvas.drawLine(
      Offset(0, base),
      Offset(size.width, base),
      Paint()
        ..color = grid
        ..strokeWidth = 1,
    );
    if (maxV == 0) return;

    // Two thin columns per month, a 2px surface gap between them, 4px
    // rounded data-ends anchored to the baseline.
    final barW = ((groupW - 16) / 2).clamp(4.0, 18.0);
    const gap = 2.0;
    for (var i = 0; i < flows.length; i++) {
      final cx = groupW * i + groupW / 2;
      void bar(double left, int paise, Color c) {
        if (paise <= 0) return;
        final h = (plotH * paise / maxV).clamp(2.0, plotH);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(left, base - h, barW, h),
            topLeft: const Radius.circular(4),
            topRight: const Radius.circular(4),
          ),
          Paint()..color = c,
        );
      }

      bar(cx - gap / 2 - barW, flows[i].income.paise, income);
      bar(cx + gap / 2, flows[i].costs.paise, costs);
    }
  }

  @override
  bool shouldRepaint(_ColumnsPainter old) =>
      old.flows != flows ||
      old.selected != selected ||
      old.income != income ||
      old.grid != grid;
}
