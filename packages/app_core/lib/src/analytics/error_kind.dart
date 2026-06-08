/// Coarse error bucket for [VamoEvent.errorShown] and [VamoEvent.actionFailed].
enum AnalyticsErrorKind {
  network('network'),
  server('server'),
  auth('auth'),
  file('file'),
  db('db'),
  app('app'),
  unknown('unknown');

  const AnalyticsErrorKind(this.value);
  final String value;
}
