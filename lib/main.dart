import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app.dart';

void main() {
  // Адреса без решётки: /cars?page=2 вместо /#/cars?page=2.
  usePathUrlStrategy();
  runApp(buildApp());
}
