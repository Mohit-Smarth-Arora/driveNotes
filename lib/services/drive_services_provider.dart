import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:googleapis_auth/googleapis_auth.dart';
import '../auth/auth_repository_provider.dart';
import 'drive_service.dart';
// import 'auth_repository.dart';

final authClientProvider = FutureProvider<AuthClient?>((ref) async {
  final authRepo = ref.read(authRepositoryProvider);
  if (await authRepo.isSignedIn()) {
    return await authRepo.signInWithGoogle();
  }
  return null;
});

// final driveServiceProvider = Provider<DriveService>((ref) {
//   final authClientAsync = ref.watch(authClientProvider);
//
//   return authClientAsync.when(
//     data: (authClient) {
//       if (authClient == null) {
//         throw Exception('Cannot create DriveService - not authenticated');
//       }
//       return DriveService(authClient);
//     },
//     loading: () => throw Exception('Auth still loading'),
//     error: (error, stackTrace) => throw error,
//   );
// });

final driveServiceProvider = Provider<DriveService?>((ref) {
  final authClientAsync = ref.watch(authClientProvider);

  return authClientAsync.when(
    data: (authClient) => authClient != null ? DriveService(authClient) : null,
    loading: () => null, // Return null instead of throwing
    error: (error, _) => null, // Optionally log error
  );
});