import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// App-bar back control for trip section screens — pops to dashboard or goes there.
class TripSectionBackButton extends StatelessWidget {
  const TripSectionBackButton({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: () {
        if (context.canPop()) {
          context.pop();
          return;
        }
        context.go(AppRoutes.trip(tripId));
      },
    );
  }
}
