import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'services/app_services.dart';
import 'services/firebase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeFirebase();
  await initializeDateFormatting('ja');
  runApp(FuelApp(services: AppServices.firebase()));
}
