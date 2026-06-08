import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../expenses/expense_trip_picker_sheet.dart';

/// Bottom nav shell — Trips · Activity · [FAB] · Expenses · Profile.
class MainShell extends ConsumerWidget {
  const MainShell({
    super.key,
    required this.navigationShell,
    required this.labels,
    this.expensesFabLabels,
  });

  final StatefulNavigationShell navigationShell;
  final MainShellLabels labels;
  final ExpensesFabLabels? expensesFabLabels;

  static const tripBranch = 0;
  static const activityBranch = 1;
  static const expensesBranch = 2;
  static const profileBranch = 3;

  void _onTab(int index) {
    navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex);
  }

  void _onFab(BuildContext context, WidgetRef ref) {
    if (navigationShell.currentIndex == expensesBranch) {
      final fabLabels = expensesFabLabels;
      if (fabLabels == null) return;
      openAddExpenseFromShell(
        context: context,
        ref: ref,
        pickerTitle: fabLabels.pickerTitle,
        lastUsedLabel: fabLabels.pickerLastUsed,
      );
      return;
    }
    context.push(AppRoutes.tripCreate);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = navigationShell.currentIndex;
    final colors = context.vamoColors;

    return Scaffold(
      body: navigationShell,
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.goLime,
        foregroundColor: AppColors.ink,
        onPressed: () => _onFab(context, ref),
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
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
              const SizedBox(width: 56),
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

class ExpensesFabLabels {
  const ExpensesFabLabels({
    required this.pickerTitle,
    required this.pickerLastUsed,
  });

  final String pickerTitle;
  final String pickerLastUsed;
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
