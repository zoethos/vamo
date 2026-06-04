import '../settle/settle_up.dart';

/// Per-member net position in trip base cents (from `trip_balances` logic).
class MemberBalance {
  const MemberBalance({
    required this.userId,
    required this.netCents,
  });

  final String userId;
  final int netCents;
}

/// Settle-up line with display-ready fields.
class SettlementDisplay {
  const SettlementDisplay({
    required this.line,
    required this.fromName,
    required this.toName,
    required this.currency,
  });

  final SettlementLine line;
  final String fromName;
  final String toName;
  final String currency;
}
