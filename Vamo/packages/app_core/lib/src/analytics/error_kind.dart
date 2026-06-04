/// Coarse error bucket for [VamoEvent.errorShown] and [VamoEvent.actionFailed].
enum AnalyticsErrorKind {
  network('network'),
  server('server'),
  auth('auth'),
  unknown('unknown');

  const AnalyticsErrorKind(this.value);
  final String value;
}
