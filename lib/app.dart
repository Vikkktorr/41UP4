import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/api_client.dart';
import 'core/router.dart';
import 'repositories/api_brand_repository.dart';
import 'repositories/api_car_repository.dart';
import 'repositories/api_client_repository.dart';
import 'repositories/api_mechanic_repository.dart';
import 'repositories/api_service_repository.dart';
import 'repositories/brand_repository.dart';
import 'repositories/car_repository.dart';
import 'repositories/client_repository.dart';
import 'repositories/data_changes.dart';
import 'repositories/mechanic_repository.dart';
import 'repositories/network_simulator.dart';
import 'repositories/service_repository.dart';
import 'state/car_list_notifier.dart';
import 'state/client_list_notifier.dart';
import 'state/lookup_notifier.dart';
import 'state/reference_list_notifiers.dart';
import 'widgets/entity_form/leave_guard.dart';

/// Собирает зависимости приложения. Вынесено из main, чтобы можно было
/// подставить свою имитацию сети и начальный адрес.
Widget buildApp({NetworkSimulator? network, String initialLocation = '/cars'}) {
  final net = network ?? NetworkSimulator();
  final changes = DataChanges();
  final guard = LeaveGuard();

  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: net),
      ChangeNotifierProvider.value(value: changes),
      Provider.value(value: guard),
      Provider<Dio>(
        create: (_) => buildDio(debugQuery: () => net.queryParameters),
      ),
      // Единственное место, где меняется приложение целиком: было
      // Persistent*Repository (localStorage), стало Api*Repository.
      // Экраны получают репозитории через интерфейс и не меняются.
      ProxyProvider<Dio, CarRepository>(
        update: (_, dio, _) => ApiCarRepository(dio, changes: changes),
      ),
      ProxyProvider<Dio, ClientRepository>(
        update: (_, dio, _) => ApiClientRepository(dio, changes: changes),
      ),
      ProxyProvider<Dio, BrandRepository>(
        update: (_, dio, _) => ApiBrandRepository(dio, changes: changes),
      ),
      ProxyProvider<Dio, MechanicRepository>(
        update: (_, dio, _) => ApiMechanicRepository(dio, changes: changes),
      ),
      ProxyProvider<Dio, ServiceRepository>(
        update: (_, dio, _) => ApiServiceRepository(dio, changes: changes),
      ),
      ChangeNotifierProvider(
        create: (context) =>
            CarListNotifier(context.read<CarRepository>(), changes: changes),
      ),
      ChangeNotifierProvider(
        create: (context) => ClientListNotifier(
          context.read<ClientRepository>(),
          changes: changes,
        ),
      ),
      ChangeNotifierProvider(
        create: (context) => BrandListNotifier(
          context.read<BrandRepository>(),
          changes: changes,
        ),
      ),
      ChangeNotifierProvider(
        create: (context) => MechanicListNotifier(
          context.read<MechanicRepository>(),
          changes: changes,
        ),
      ),
      ChangeNotifierProvider(
        create: (context) => ServiceListNotifier(
          context.read<ServiceRepository>(),
          changes: changes,
        ),
      ),
      ChangeNotifierProvider(
        create: (context) => LookupNotifier(
          context.read<BrandRepository>(),
          context.read<ClientRepository>(),
          context.read<MechanicRepository>(),
          context.read<ServiceRepository>(),
          changes: changes,
        )..load(),
      ),
    ],
    child: AutoServiceApp(
      router: createRouter(initialLocation: initialLocation, guard: guard),
    ),
  );
}

class AutoServiceApp extends StatefulWidget {
  const AutoServiceApp({
    super.key,
    required this.router,
    this.notices = const [],
  });

  final GoRouter router;

  /// Сообщения хранилища после запуска: миграция или сброс данных.
  final List<String> notices;

  @override
  State<AutoServiceApp> createState() => _AutoServiceAppState();
}

class _AutoServiceAppState extends State<AutoServiceApp> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    if (widget.notices.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _messenger.currentState?.showMaterialBanner(
          MaterialBanner(
            leading: const Icon(Icons.info_outline),
            content: Text(widget.notices.join('\n')),
            actions: [
              TextButton(
                onPressed: () =>
                    _messenger.currentState?.hideCurrentMaterialBanner(),
                child: const Text('Понятно'),
              ),
            ],
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Автосервис',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messenger,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F5FAD)),
        useMaterial3: true,
      ),
      // Подписи стандартных виджетов (подсказки, диалоги) — по-русски.
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // Широкую таблицу можно прокрутить вбок, перетащив мышью.
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
        },
      ),
      routerConfig: widget.router,
    );
  }
}
