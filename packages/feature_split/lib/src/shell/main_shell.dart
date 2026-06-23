import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../expenses/expense_trip_picker_sheet.dart';

/// Bottom nav shell — Trips · Activity · Add · Expenses · Profile.
class MainShell extends ConsumerWidget {
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
  static const addNavIndex = 2;

  void _onTab(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  int _branchToNavIndex(int branchIndex, {required bool showPrimaryAction}) {
    if (!showPrimaryAction) return branchIndex;
    return switch (branchIndex) {
      tripBranch => 0,
      activityBranch => 1,
      expensesBranch => 3,
      profileBranch => 4,
      _ => 0,
    };
  }

  int? _navIndexToBranch(
    int navIndex, {
    required bool showPrimaryAction,
  }) {
    if (!showPrimaryAction) return navIndex;
    return switch (navIndex) {
      0 => tripBranch,
      1 => activityBranch,
      3 => expensesBranch,
      4 => profileBranch,
      _ => null,
    };
  }

  void _onNavSelected(BuildContext context, WidgetRef ref, int navIndex) {
    final showPrimaryAction = _hasPrimaryAction(navigationShell.currentIndex);
    if (showPrimaryAction && navIndex == addNavIndex) {
      if (_hasPrimaryAction(navigationShell.currentIndex)) {
        _openPrimaryAction(context, ref);
      }
      return;
    }
    final branch = _navIndexToBranch(
      navIndex,
      showPrimaryAction: showPrimaryAction,
    );
    if (branch != null) _onTab(branch);
  }

  bool _hasPrimaryAction(int branchIndex) => branchIndex != activityBranch;

  String _primaryActionTooltip(int branchIndex) =>
      branchIndex == expensesBranch ? labels.addExpense : labels.createTrip;

  void _openPrimaryAction(BuildContext context, WidgetRef ref) {
    if (!_hasPrimaryAction(navigationShell.currentIndex)) return;
    if (navigationShell.currentIndex == expensesBranch) {
      openAddExpenseFromShell(
        context: context,
        ref: ref,
        pickerTitle: labels.addExpensePickerTitle,
        lastUsedLabel: labels.addExpenseLastUsed,
      );
      return;
    }
    context.push(AppRoutes.tripCreate);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = navigationShell.currentIndex;
    final colors = context.vamoColors;
    final showPrimaryAction = _hasPrimaryAction(index);

    return Scaffold(
      extendBody: true,
      body: navigationShell,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: showPrimaryAction
          ? FloatingActionButton(
              heroTag: 'main_shell_primary_action',
              tooltip: _primaryActionTooltip(index),
              backgroundColor: AppColors.goLime,
              foregroundColor: AppColors.ink,
              elevation: 1,
              shape: const CircleBorder(),
              onPressed: () => _openPrimaryAction(context, ref),
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        height: 68,
        selectedIndex:
            _branchToNavIndex(index, showPrimaryAction: showPrimaryAction),
        onDestinationSelected: (navIndex) =>
            _onNavSelected(context, ref, navIndex),
        backgroundColor: colors.surface,
        indicatorColor: AppColors.jadeTeal.withValues(alpha: 0.14),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.luggage_outlined),
            selectedIcon: const Icon(Icons.luggage),
            label: labels.trips,
          ),
          NavigationDestination(
            icon: const Icon(Icons.timeline_outlined),
            selectedIcon: const Icon(Icons.timeline),
            label: labels.activity,
          ),
          if (showPrimaryAction)
            NavigationDestination(
              icon: const SizedBox.square(dimension: 24),
              selectedIcon: const SizedBox.square(dimension: 24),
              label: labels.add,
            ),
          NavigationDestination(
            icon: const Icon(Icons.receipt_long_outlined),
            selectedIcon: const Icon(Icons.receipt_long),
            label: labels.expenses,
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: labels.profile,
          ),
        ],
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
    required this.add,
    required this.createTrip,
    required this.addExpense,
    required this.addExpensePickerTitle,
    required this.addExpenseLastUsed,
  });

  final String trips;
  final String activity;
  final String expenses;
  final String profile;
  final String add;
  final String createTrip;
  final String addExpense;
  final String addExpensePickerTitle;
  final String addExpenseLastUsed;
}
