import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Bottom nav shell — Trips · Activity · Expenses · Profile.
class MainShell extends StatelessWidget {
  const MainShell({
    super.key,
    required this.navigationShell,
    required this.labels,
  });

  final StatefulNavigationShell navigationShell;
  final MainShellLabels labels;

  static const tripBranch = 0;
  static const activityBranch = 1;
  static const expensesBranch = 2;
  static const profileBranch = 3;

  void _onTab(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final index = navigationShell.currentIndex;
    final colors = context.vamoColors;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomAppBar(
        height: 56,
        padding: EdgeInsets.zero,
        color: colors.surface,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavSlot(
                selected: index == tripBranch,
                icon: Icons.luggage_outlined,
                selectedIcon: Icons.luggage,
                label: labels.trips,
                onTap: () => _onTab(tripBranch),
              ),
              _NavSlot(
                selected: index == activityBranch,
                icon: Icons.timeline_outlined,
                selectedIcon: Icons.timeline,
                label: labels.activity,
                onTap: () => _onTab(activityBranch),
              ),
              _NavSlot(
                selected: index == expensesBranch,
                icon: Icons.receipt_long_outlined,
                selectedIcon: Icons.receipt_long,
                label: labels.expenses,
                onTap: () => _onTab(expensesBranch),
              ),
              _NavSlot(
                selected: index == profileBranch,
                icon: Icons.person_outline,
                selectedIcon: Icons.person,
                label: labels.profile,
                onTap: () => _onTab(profileBranch),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MainShellLabels {
  const MainShellLabels({
    required this.trips,
    required this.activity,
    required this.expenses,
    required this.profile,
  });

  final String trips;
  final String activity;
  final String expenses;
  final String profile;
}

class _NavSlot extends StatelessWidget {
  const _NavSlot({
    required this.selected,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final color = selected ? colors.onSurface : colors.onSurfaceMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(selected ? selectedIcon : icon, color: color, size: 22),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: color,
                        fontSize: 10,
                        height: 1.1,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
