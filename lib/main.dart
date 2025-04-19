import 'package:drivenotes/restart_widget.dart';
import 'package:drivenotes/services/drive_service.dart';
import 'package:drivenotes/services/drive_services_provider.dart';
import 'package:drivenotes/services/local/local_storage_service.dart';
import 'package:drivenotes/services/local/sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drivenotes/auth/auth_repository.dart';
import 'package:drivenotes/pages/auth_screen.dart';
import 'package:drivenotes/pages/notes_screen.dart';
import 'package:drivenotes/themes/theme_provider.dart';
import 'package:googleapis/authorizedbuyersmarketplace/v1.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'auth/auth_repository_provider.dart';

final localStorageServiceProvider = Provider<LocalStorageService>((ref) {
  throw UnimplementedError('Override in main.dart');
});

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();

  // Initialize services manually
  final localStorage = LocalStorageService();
  await localStorage.init();

  runApp(
    RestartWidget(
      child: ProviderScope(
        overrides: [
          localStorageServiceProvider.overrideWithValue(localStorage),
        ],
        child: const MyApp(),
      ),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {


    final authRepo = ref.watch(authRepositoryProvider);
    final theme = ref.watch(themeProvider).themeData;

    return MaterialApp(
      debugShowCheckedModeBanner: false,

      title: 'Drive Notes',
      theme: theme,
      home: FutureBuilder<bool>(
        future: authRepo.isSignedIn(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return snapshot.data == true
              ? const NotesScreen()
              // ? const AuthScreen()
              : const AuthScreen();
        },
      ),
    );
  }
}
