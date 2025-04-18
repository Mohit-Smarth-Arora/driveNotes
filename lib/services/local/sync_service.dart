import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';
import 'package:riverpod/riverpod.dart';

import '../../main.dart';
import '../drive_service.dart';
import '../drive_services_provider.dart';
import 'local_storage_service.dart';

final syncServiceProvider = Provider<SyncService>((ref) {
  final localStorage = ref.read(localStorageServiceProvider);
  final driveService = ref.read(driveServiceProvider);
  return SyncService(localStorage, driveService);
});

class SyncService {
  final LocalStorageService _localStorage;
  final DriveService? _driveService;
  final _lock = Lock();
  bool _isSyncing = false;

  SyncService(this._localStorage, this._driveService);

  Future<bool> syncNotes() async {
    if (_isSyncing || _driveService == null) return false;

    _isSyncing = true;
    try {
      return await _lock.synchronized(() async {
        // Check connectivity
        final connectivity = await Connectivity().checkConnectivity();
        if (connectivity == ConnectivityResult.none) {
          debugPrint('No network connection for sync');
          return false;
        }

        // Verify Drive connection
        try {
          if (!(await _driveService!.checkConnection())) {
            debugPrint('No connection to Google Drive');
            return false;
          }
        } catch (e) {
          debugPrint('Drive connection check failed: $e');
          return false;
        }

        // Get unsynced notes
        final unsyncedNotes = await _localStorage.getUnsyncedNotes();
        if (unsyncedNotes.isEmpty) {
          debugPrint('No unsynced notes to sync');
          return true;
        }

        debugPrint('Starting sync for ${unsyncedNotes.length} notes');

        // Process each note
        for (final note in unsyncedNotes) {
          try {
            final now = DateTime.now().toIso8601String();
            if (note['id'].startsWith('local_')) {
              // New note - create in Drive
              final driveFile = await _driveService!.createNote(
                note['title'],
                note['content'],
              );

              await _localStorage.replaceLocalNote(
                oldId: note['id'],
                newId: driveFile.id!,
                title: note['title'],
                content: note['content'],
                isSynced: true,
                modifiedAt: driveFile.modifiedTime?.toIso8601String() ?? now,
              );
            } else {
              // Existing note - update in Drive
              await _driveService!.updateNote(
                note['id'],
                note['title'],
                note['content'],
              );

              await _localStorage.markAsSynced(
                note['id'],
                modifiedAt: now,
              );
            }
          } catch (e) {
            debugPrint('Sync failed for note ${note['id']}: $e');
            // Continue with next note even if one fails
          }
        }

        debugPrint('Sync completed successfully');
        return true;
      });
    } catch (e) {
      debugPrint('Sync process failed: $e');
      return false;
    } finally {
      _isSyncing = false;
    }
  }

  Stream<bool> get connectivityStream {
    return Connectivity()
        .onConnectivityChanged
        .map((result) => result != ConnectivityResult.none)
        .distinct(); // Only emit when connectivity actually changes
  }
}