import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../expenses/money_format.dart';
import '../settle/payment_links.dart';
import '../settle/settlements_repository.dart';
import 'balances_models.dart';

/// Bottom sheet: pick payment app, mark settled, open handoff where supported.
Future<void> showMarkSettleSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String tripId,
  required SettlementDisplay display,
}) {
  final methods = paymentMethodsForTrip(display.currency);

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pay ${display.toName}',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        color: AppColors.tealDark,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatMoneyFromCents(display.line.cents, display.currency),
                  style: Theme.of(ctx)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: AppColors.teal),
                ),
                const SizedBox(height: 8),
                Text(
                  'Vamo does not move money — you pay in your app, then we track it here.',
                  style: Theme.of(ctx)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
          for (final method in methods)
            ListTile(
              leading: Icon(_iconFor(method), color: AppColors.teal),
              title: Text(method.label),
              subtitle: Text(
                paymentHandoffSubtitle(
                  method: method,
                  currency: display.currency,
                  cents: display.line.cents,
                ),
              ),
              isThreeLine: true,
              onTap: () => _onPick(
                context: context,
                sheetContext: ctx,
                ref: ref,
                tripId: tripId,
                display: display,
                method: method,
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

IconData _iconFor(PaymentMethod method) {
  switch (method) {
    case PaymentMethod.venmo:
      return Icons.phone_android;
    case PaymentMethod.paypal:
      return Icons.account_balance_wallet_outlined;
    case PaymentMethod.wise:
      return Icons.public;
    case PaymentMethod.cash:
      return Icons.payments_outlined;
  }
}

Future<void> _onPick({
  required BuildContext context,
  required BuildContext sheetContext,
  required WidgetRef ref,
  required String tripId,
  required SettlementDisplay display,
  required PaymentMethod method,
}) async {
  Navigator.of(sheetContext).pop();

  try {
    await ref.read(settlementsRepositoryProvider).markSettled(
          tripId: tripId,
          line: display.line,
          currency: display.currency,
          method: method,
        );

    if (method != PaymentMethod.cash && context.mounted) {
      final opened = await launchPaymentHandoff(
        method: method,
        cents: display.line.cents,
        currency: display.currency,
        note: 'Vamo · ${display.toName}',
      );
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Marked settled. Open ${method.label} and send '
              '${formatMoneyFromCents(display.line.cents, display.currency)} '
              'to ${display.toName}.',
            ),
          ),
        );
      }
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marked as settled.')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      showActionError(
        context,
        ref,
        screen: 'trip_home',
        action: 'mark_settled',
        error: e,
      );
    }
  }
}
