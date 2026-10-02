import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/breakpoints.dart';
import '../repositories/network_simulator.dart';

/// Общий каркас экранов с адаптивной навигацией.
///
/// Узкое окно — нижняя панель, как на телефоне; среднее — боковая полоса
/// со значками; широкое — раскрытая полоса с подписями.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  static const _sections = [
    (title: 'Автомобили', path: '/cars', icon: Icons.directions_car_outlined),
    (title: 'Клиенты', path: '/clients', icon: Icons.people_outline),
    (title: 'Марки', path: '/brands', icon: Icons.sell_outlined),
    (title: 'Мастера', path: '/mechanics', icon: Icons.engineering_outlined),
    (title: 'Услуги', path: '/services', icon: Icons.build_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final size = screenSizeOf(context);
    final location = GoRouterState.of(context).uri.path;
    final selected = _sections.indexWhere(
      (s) => location == s.path || location.startsWith('${s.path}/'),
    );
    void onSelect(int index) => context.go(_sections[index].path);

    if (size == ScreenSize.compact) {
      return Scaffold(
        appBar: AppBar(title: const _Logo(), actions: const [_NetworkMenu()]),
        body: _Content(child: child),
        bottomNavigationBar: NavigationBar(
          selectedIndex: selected < 0 ? 0 : selected,
          onDestinationSelected: onSelect,
          destinations: [
            for (final s in _sections)
              NavigationDestination(icon: Icon(s.icon), label: s.title),
          ],
        ),
      );
    }

    final extended = size == ScreenSize.expanded;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selected < 0 ? null : selected,
            onDestinationSelected: onSelect,
            extended: extended,
            // extended и labelType, отличный от none, вместе задавать нельзя.
            labelType: extended
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: extended
                  ? const _Logo()
                  : Icon(
                      Icons.car_repair,
                      color: Theme.of(context).colorScheme.primary,
                    ),
            ),
            trailing: const Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: _NetworkMenu(),
                ),
              ),
            ),
            destinations: [
              for (final s in _sections)
                NavigationRailDestination(
                  icon: Icon(s.icon),
                  label: Text(s.title),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _Content(child: child)),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.car_repair, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text('Автосервис', style: theme.textTheme.titleMedium),
      ],
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final compact = screenSizeOf(context) == ScreenSize.compact;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: Breakpoints.contentMaxWidth,
        ),
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 24),
          child: child,
        ),
      ),
    );
  }
}

/// Меню отладки: учебные параметры сервера ?__fail=500 и ?__delay=1500,
/// чтобы принудительно проверить экраны ошибки и загрузки.
class _NetworkMenu extends StatelessWidget {
  const _NetworkMenu();

  @override
  Widget build(BuildContext context) {
    final net = context.watch<NetworkSimulator>();
    return PopupMenuButton<void>(
      tooltip: 'Отладка',
      icon: Icon(
        net.failing
            ? Icons.wifi_off
            : net.slow
            ? Icons.hourglass_bottom
            : Icons.bug_report_outlined,
        color: net.failing ? Theme.of(context).colorScheme.error : null,
      ),
      itemBuilder: (context) => [
        CheckedPopupMenuItem<void>(
          checked: net.failing,
          onTap: () => net.failing = !net.failing,
          child: const Text('Ошибка сервера 500'),
        ),
        CheckedPopupMenuItem<void>(
          checked: net.slow,
          onTap: () => net.slow = !net.slow,
          child: const Text('Задержка ответа 1,5 с'),
        ),
      ],
    );
  }
}
