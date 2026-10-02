import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/brand.dart';
import '../models/car.dart';
import '../models/car_query.dart';
import '../models/client.dart';
import '../models/client_query.dart';
import '../models/entity_query.dart';
import '../models/mechanic.dart';
import '../models/service_item.dart';
import '../models/with_cars.dart';
import '../repositories/brand_repository.dart';
import '../repositories/car_repository.dart';
import '../repositories/client_repository.dart';
import '../repositories/data_changes.dart';
import '../repositories/mechanic_repository.dart';
import '../repositories/service_repository.dart';
import '../screens/car_detail_screen.dart';
import '../screens/car_list_screen.dart';
import '../screens/client_detail_screen.dart';
import '../screens/client_list_screen.dart';
import '../screens/forms/car_form_screen.dart';
import '../screens/forms/client_form_screen.dart';
import '../screens/forms/reference_form_screens.dart';
import '../screens/not_found_screen.dart';
import '../screens/reference_screens.dart';
import '../state/detail_notifier.dart';
import '../widgets/app_shell.dart';
import '../widgets/entity_form/leave_guard.dart';

/// Маршруты приложения. У каждой из пяти сущностей одинаковый набор:
///
///   /cars            список
///   /cars/new        форма создания
///   /cars/:id        карточка
///   /cars/:id/edit   форма изменения — тот же экран, что и создание
GoRouter createRouter({
  String initialLocation = '/cars',
  required LeaveGuard guard,
}) {
  // Уход с формы (боковое меню, ссылка, кнопка «назад» браузера)
  // сначала спрашивает форму, нет ли несохранённых изменений.
  Future<bool> onExit(BuildContext context, GoRouterState state) =>
      guard.canLeave();

  List<RouteBase> entityRoutes({
    required Widget Function(GoRouterState state) form,
    required Widget Function(int id) edit,
    required Widget Function(BuildContext context, int id) detail,
  }) => [
    // «new» объявлен раньше «:id», иначе адрес /cars/new разобрался бы
    // как карточка с идентификатором «new».
    GoRoute(
      path: 'new',
      onExit: onExit,
      builder: (context, state) => form(state),
    ),
    GoRoute(
      path: ':id',
      builder: (context, state) {
        final id = int.tryParse(state.pathParameters['id']!);
        if (id == null) return NotFoundScreen(location: state.uri.toString());
        return detail(context, id);
      },
      routes: [
        GoRoute(
          path: 'edit',
          onExit: onExit,
          builder: (context, state) {
            final id = int.tryParse(state.pathParameters['id']!);
            if (id == null) {
              return NotFoundScreen(location: state.uri.toString());
            }
            // Ключ по id: при переходе с одной формы на другую экран
            // создаётся заново и загружает свою запись.
            return KeyedSubtree(key: ValueKey('edit-$id'), child: edit(id));
          },
        ),
      ],
    ),
  ];

  return GoRouter(
    initialLocation: initialLocation,
    errorBuilder: (context, state) =>
        NotFoundScreen(location: state.uri.toString()),
    redirect: (context, state) => state.uri.path == '/' ? '/cars' : null,
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/cars',
            // Условия отбора берутся из адреса — аналог @RequestParam.
            builder: (context, state) => CarListScreen(
              query: CarQuery.fromQueryParameters(state.uri.queryParameters),
            ),
            routes: entityRoutes(
              form: (_) => const CarFormScreen(),
              edit: (id) => CarFormScreen(id: id),
              detail: (context, id) => _detail<Car>(
                'car-$id',
                context,
                () => context.read<CarRepository>().findById(id),
                CarDetailScreen(id: id),
              ),
            ),
          ),
          GoRoute(
            path: '/clients',
            builder: (context, state) => ClientListScreen(
              query: ClientQuery.fromQueryParameters(state.uri.queryParameters),
            ),
            routes: entityRoutes(
              form: (_) => const ClientFormScreen(),
              edit: (id) => ClientFormScreen(id: id),
              detail: (context, id) => _detail<WithCars<Client>>(
                'client-$id',
                context,
                () => _withCars(
                  context,
                  context.read<ClientRepository>().findById(id),
                  CarQuery(clientId: id, size: 50),
                ),
                ClientDetailScreen(id: id),
              ),
            ),
          ),
          GoRoute(
            path: '/brands',
            builder: (context, state) => BrandListScreen(
              query: EntityQuery.fromQueryParameters(
                Queries.brands,
                state.uri.queryParameters,
              ),
            ),
            routes: entityRoutes(
              form: (_) => const BrandFormScreen(),
              edit: (id) => BrandFormScreen(id: id),
              detail: (context, id) => _detail<WithCars<Brand>>(
                'brand-$id',
                context,
                () => _withCars(
                  context,
                  context.read<BrandRepository>().findById(id),
                  CarQuery(brandId: id, size: 20),
                ),
                BrandDetailScreen(id: id),
              ),
            ),
          ),
          GoRoute(
            path: '/mechanics',
            builder: (context, state) => MechanicListScreen(
              query: EntityQuery.fromQueryParameters(
                Queries.mechanics,
                state.uri.queryParameters,
              ),
            ),
            routes: entityRoutes(
              form: (_) => const MechanicFormScreen(),
              edit: (id) => MechanicFormScreen(id: id),
              detail: (context, id) => _detail<WithCars<Mechanic>>(
                'mechanic-$id',
                context,
                () => _withCars(
                  context,
                  context.read<MechanicRepository>().findById(id),
                  CarQuery(mechanicId: id, size: 20),
                ),
                MechanicDetailScreen(id: id),
              ),
            ),
          ),
          GoRoute(
            path: '/services',
            builder: (context, state) => ServiceListScreen(
              query: EntityQuery.fromQueryParameters(
                Queries.services,
                state.uri.queryParameters,
              ),
            ),
            routes: entityRoutes(
              form: (_) => const ServiceFormScreen(),
              edit: (id) => ServiceFormScreen(id: id),
              detail: (context, id) => _detail<WithCars<ServiceItem>>(
                'service-$id',
                context,
                () => _withCars(
                  context,
                  context.read<ServiceRepository>().findById(id),
                  CarQuery(serviceId: id, size: 20),
                ),
                ServiceDetailScreen(id: id),
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

/// Состояние карточки живёт, пока открыт экран. После изменений на
/// сервере (сохранили форму, удалили связанную запись) карточка
/// перечитывается сама.
Widget _detail<T>(
  String key,
  BuildContext context,
  Future<T?> Function() loader,
  Widget child,
) => ChangeNotifierProvider(
  key: ValueKey(key),
  create: (context) =>
      DetailNotifier<T>(loader, changes: context.read<DataChanges>())..load(),
  child: child,
);

Future<WithCars<T>?> _withCars<T>(
  BuildContext context,
  Future<T?> item,
  CarQuery query,
) async {
  final cars = context.read<CarRepository>();
  final found = await item;
  if (found == null) return null;
  final page = await cars.find(query);
  return WithCars(item: found, cars: page.items, total: page.total);
}
