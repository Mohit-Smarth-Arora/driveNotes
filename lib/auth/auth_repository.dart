import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart';
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

import '../services/local/local_storage_service.dart';

class AuthRepository {
  final GoogleSignIn _googleSignIn;
  static const List<String> _scopes = [DriveApi.driveFileScope];

  // Stream to track authentication state changes
  Stream<GoogleSignInAccount?> get authStateChanges => _googleSignIn.onCurrentUserChanged;

  AuthRepository({GoogleSignIn? googleSignIn})
      : _googleSignIn = googleSignIn ?? GoogleSignIn.standard(scopes: _scopes);

  Future<AuthClient?> signInWithGoogle() async {
    try {

      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final googleAuth = await googleUser.authentication;

      // Create credentials with proper token handling
      final credentials = AccessCredentials(
        AccessToken(
          'Bearer',
          googleAuth.accessToken!,
          DateTime.now().toUtc().add(const Duration(hours:1440 )),
        ),
        null, // or googleAuth.refreshToken, if available
        _scopes,
        idToken: googleAuth.idToken,
      );


      // Create an auto-refreshing client
      final authClient = await authenticatedClient(
        http.Client(),
        credentials,
      );

      return authClient;
    } catch (e) {
      debugPrint('Google Sign-In Error: $e');
      rethrow;
    }
  }



  Future<void> signOut() async {
    try {
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
        // Clear local data
        final localStorage = LocalStorageService();
        await localStorage.clearAllData();

        // Invalidate all providers
        debugPrint('User signed out and app reset complete');
        try {
          await _googleSignIn.disconnect(); // Disconnect only if needed
        } catch (e) {
          debugPrint('Optional disconnect failed: $e'); // Don't let this crash
        }
      }
    } catch (e) {
      debugPrint('Sign-Out Error: $e');
    }
  }


  Future<bool> isSignedIn() async {
    try {
      return await _googleSignIn.isSignedIn();
    } catch (e) {
      debugPrint('isSignedIn Error: $e');
      return false;
    }
  }

  Future<GoogleSignInAccount?> getCurrentUser() async {
    try {
      return _googleSignIn.currentUser;
    } catch (e) {
      debugPrint('getCurrentUser Error: $e');
      return null;
    }
  }

  // Get the current auth client if available
  Future<AuthClient?> getCurrentAuthClient() async {
    if (!await isSignedIn()) return null;
    return signInWithGoogle(); // This will return the existing session if already signed in
  }
}
