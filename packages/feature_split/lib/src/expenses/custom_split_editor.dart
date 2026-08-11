import 'package:flutter/material.dart';

import 'expense_models.dart';
import 'money_format.dart';

/// Editor for explicit per-member shares in the trip base currency.
class CustomSplitEditor extends StatefulWidget {
  const CustomSplitEditor({
    super.key,
    required this.members,
    required this.baseCents,
    required this.currency,
    required this.initialShareCents,
  });

  final List<TripMemberView> members;
  final int baseCents;
  final String currency;
  final Map<String, int> initialShareCents;

  @override
  State<CustomSplitEditor> createState() => _CustomSplitEditorState();
}

class _CustomSplitEditorState extends State<CustomSplitEditor> {
  late final Map<String, TextEditingController> _controllers = {
    for (final member in widget.members)
      member.userId: TextEditingController(
        text: ((widget.initialShareCents[member.userId] ?? 0) / 100)
            .toStringAsFixed(2),
      ),
  };

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  int get _allocatedCents => _controllers.values.fold<int>(
        0,
        (total, controller) =>
            total + (parseAmountToCents(controller.text) ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    final remaining = widget.baseCents - _allocatedCents;
    final valid = remaining == 0 &&
        _controllers.values.every(
          (controller) => parseAmountToCents(controller.text) != null,
        );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Custom split',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Allocate ${formatMoneyFromCents(widget.baseCents, widget.currency)} across everyone in this trip.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              for (final member in widget.members)
                Padding(
                  padding: const EdgeInsetsDirectional.only(bottom: 12),
                  child: TextFormField(
                    key: Key('customSplitAmount_${member.userId}'),
                    controller: _controllers[member.userId],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: member.displayName,
                      prefixText: '${widget.currency} ',
                    ),
                  ),
                ),
              Text(
                remaining == 0
                    ? 'Split total matches the expense.'
                    : '${remaining > 0 ? 'Left to allocate' : 'Over by'} ${formatMoneyFromCents(remaining.abs(), widget.currency)}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: valid ? Colors.teal.shade700 : Colors.red.shade700,
                    ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('customSplitSave'),
                onPressed: valid
                    ? () => Navigator.of(context).pop({
                          for (final member in widget.members)
                            member.userId: parseAmountToCents(
                                  _controllers[member.userId]!.text,
                                ) ??
                                0,
                        })
                    : null,
                child: const Text('Use custom split'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
