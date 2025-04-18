import 'package:drivenotes/pages/notes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_repository.dart';
import '../auth/auth_repository_provider.dart';
// import 'auth_repository.dart';

class AuthScreen extends ConsumerWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.note_alt, size: 100, color: Colors.blue),
            const SizedBox(height: 24),
            const Text(
              'Drive Notes',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text('Store and sync your notes with Google Drive'),
            const SizedBox(height: 32),
            FilledButton.icon(
              icon: const Icon(Icons.login),
              label: const Text('Sign in with Google'),
              onPressed: () {
                Future.microtask(() async {
                  try {
                    await ref
                        .read(authRepositoryProvider)
                        .signInWithGoogle();
                    if (await ref
                        .read(authRepositoryProvider)
                        .isSignedIn()) {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => NotesScreen(),));
                    }

                  } catch (e) {
                    debugPrint('Sign-in error: $e');
                  }
                });
              },
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
