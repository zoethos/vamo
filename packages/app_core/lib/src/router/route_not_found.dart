import 'package:go_router/go_router.dart';

import '../auth/auth_urls.dart';
import '../invites/invite_urls.dart';

/// Catalogued copy for unmatched deep links — never raw [GoException] text.
const routeNotFoundUserMessage = "Couldn't open that link.";

/// Analytics-safe location label — token values never included.
String routeNotFoundLocationShape(GoRouterState state) {
  final uri = state.uri;
  if (uri.scheme == AuthUrls.appScheme || uri.scheme == InviteUrls.appScheme) {
    return customSchemeLocationShape(uri);
  }

  final loc = state.matchedLocation;
  if (loc.contains('token=')) {
    return loc.replaceAll(RegExp(r'token=[^&/#]*'), 'token=*');
  }
  return loc.split('?').first;
}

/// Shape for custom-scheme URIs (testable without [GoRouterState]).
String customSchemeLocationShape(Uri uri) {
  final queryKeys = uri.queryParameters.keys.toList()..sort();
  final queryShape = queryKeys
      .map((key) => key == 'token' ? 'token=*' : '$key=*')
      .join('&');
  final queryPart = queryShape.isEmpty ? '' : '?$queryShape';
  return '${uri.scheme}://${uri.host}${uri.path}$queryPart';
}
