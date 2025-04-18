import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:googleapis/drive/v3.dart';
import 'package:hive/hive.dart';
import '../main.dart';
import 'drive_service.dart';
import 'drive_services_provider.dart';
import 'package:drivenotes/services/local/local_storage_service.dart';

import 'local/sync_service.dart';

class NotesNotifier extends AsyncNotifier<List<File>> {
  late final LocalStorageService _localStorage;
  DriveService? get _driveService => ref.read(driveServiceProvider);
  bool _isOnline = true;

  @override
  Future<List<File>> build() async {
    _localStorage = ref.read(localStorageServiceProvider);

    // Initialize connectivity listener
    _initConnectivityListener();

    // Load combined notes (local + remote)
    return await _loadCombinedNotes();
  }
  final connectivityStatusProvider = StreamProvider<bool>((ref) {
    return ref.watch(syncServiceProvider).connectivityStream;
  });

  void _initConnectivityListener() {
    ref.listen<AsyncValue<bool>>(
      connectivityStatusProvider,
          (_, connectivityStatus) {
        if (connectivityStatus.hasValue) {
          final wasOnline = _isOnline;
          _isOnline = connectivityStatus.value!;

          if (_isOnline && !wasOnline) {
            // When coming back online, trigger sync
            _syncNotes();
          }
        }
      },
    );
  }

  Future<List<File>> _loadCombinedNotes() async {
    try {
      if (_isOnline && _driveService != null) {
        // Get fresh notes from Drive and sync any local changes
        final remoteNotes = await _driveService!.getNotes();
        await _syncLocalNotesWithRemote(remoteNotes);
        return remoteNotes;
      } else {
        // Offline mode - get locally cached notes
        final localNotes = await _localStorage.getAllLocalNotes();
        return localNotes.map((note) {
          return File()
            ..id = note['id']
            ..name = note['title']
            ..modifiedTime = DateTime.parse(note['modifiedAt']);
        }).toList(); // <-- This ensures it's a List<File>, not Iterable<File>
      }
    } catch (e) {
      debugPrint('Error loading notes: $e');
      rethrow;
    }
  }


  Future<void> _syncLocalNotesWithRemote(List<File> remoteNotes) async {
    final localNotes = await _localStorage.getUnsyncedNotes();
    for (final localNote in localNotes) {
      try {
        if (localNote['id'].startsWith('local_')) {
          // Create new note in Drive
          final newFile = await _driveService!.createNote(
            localNote['title'],
            localNote['content'],
          );
          // Update local reference
          await _localStorage.deleteLocalNote(localNote['id']);
          await _localStorage.saveNoteLocally(
            id: newFile.id!,
            title: localNote['title'],
            content: localNote['content'],
            isSynced: true,
            modifiedAt: newFile.modifiedTime?.toIso8601String() ?? DateTime.now().toIso8601String(),
          );

// And for updates:
          await _localStorage.markAsSynced(
            localNote['id'],
            modifiedAt: DateTime.now().toIso8601String(),
          );
        } else {
          // Update existing note in Drive
          await _driveService!.updateNote(
            localNote['id'],
            localNote['title'],
            localNote['content'],
          );
          await _localStorage.markAsSynced(localNote['id'], modifiedAt: '');
        }
      } catch (e) {
        debugPrint('Sync error for note ${localNote['id']}: $e');
      }
    }
  }

  Future<void> _syncNotes() async {
    if (!_isOnline || _driveService == null) return;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _syncLocalNotesWithRemote(await _driveService!.getNotes());
      return await _loadCombinedNotes();
    });
  }

  Future<void> refreshNotes() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_loadCombinedNotes);
  }

  Future<void> createNote(String title, String content) async {
    state = const AsyncValue.loading();
    try {
      final localId = 'local_${DateTime.now().millisecondsSinceEpoch}';
      final timestamp = DateTime.now().toIso8601String();
      final driveService = ref.read(driveServiceProvider);
      final isOnline = _isOnline && driveService != null;

      // 1. Always save locally first
      await _localStorage.saveNoteLocally(
        id: localId,
        title: title,
        content: content,
        isSynced: !isOnline, // false if offline, true if online
        modifiedAt: timestamp,
      );

      // 2. If online, sync to Drive
      if (isOnline) {
        try {
          final newFile = await driveService!.createNote(title, content);

          // 3. Update local reference with Drive ID
          await _localStorage.deleteLocalNote(localId);
          await _localStorage.saveNoteLocally(
            id: newFile.id!,
            title: title,
            content: content,
            isSynced: true,
            modifiedAt: newFile.modifiedTime?.toIso8601String() ?? timestamp,
          );
        } catch (e) {
          debugPrint('Drive sync failed: $e');
          // Mark as unsynced if Drive fails
          await _localStorage.markNoteAsUnsynced(localId);
        }
      }

      state = await AsyncValue.guard(_loadCombinedNotes);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      rethrow;
    }
  }

  Future<void> updateNote(String fileId, String title, String content) async {
    state = const AsyncValue.loading();
    debugPrint('Attempting update for file: $fileId');
    try {
      await _driveService!.updateNote(fileId, title, content);
      debugPrint('Drive update succeeded');
    } catch (e) {
      debugPrint('Drive update failed: $e ${e}');
      rethrow;
    }

    try {
      final timestamp = DateTime.now().toIso8601String();

      // 1. Save locally first
      await _localStorage.saveNoteLocally(
        id: fileId,
        title: title,
        content: content,
        isSynced: _driveService == null ? false : _isOnline,
        modifiedAt: timestamp,
      );

      // 2. Sync to Drive if online
      if (_isOnline && _driveService != null) {
        try {
          await _driveService!.updateNote(fileId, title, content);
          await _localStorage.markAsSynced(fileId, modifiedAt: timestamp);
        } catch (e) {
          debugPrint('Drive update failed: $e');
          await _localStorage.markNoteAsUnsynced(fileId);
          rethrow;
        }
      }

      state = await AsyncValue.guard(_loadCombinedNotes);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  Future<void> deleteNote(String fileId) async {
    state = const AsyncValue.loading();
    try {
      // Delete locally first
      await _localStorage.deleteLocalNote(fileId);

      // If online, delete from Drive
      if (_isOnline && _driveService != null) {
        await _driveService?.deleteNote(fileId);
      }

      state = await AsyncValue.guard(_loadCombinedNotes);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }
}

final notesProvider = AsyncNotifierProvider<NotesNotifier, List<File>>(() {
  return NotesNotifier();
});


