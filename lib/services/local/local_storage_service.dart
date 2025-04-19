// local_storage_service.dart
import 'package:flutter/cupertino.dart';
import 'package:riverpod/riverpod.dart';
import 'package:hive/hive.dart';

class LocalStorageService {
  static const _notesBox = 'offline_notes';
  late final Box<Map> _box;
  bool _isInitialized = false;

  Future<void> init() async {
    await Hive.openBox<Map>(_notesBox);
  }

  Future<void> saveNoteLocally({
    required String id,
    required String title,
    required String content,
    bool isSynced = false, required String modifiedAt,
  }) async {
    final box = Hive.box<Map>(_notesBox);
    await box.put(id, {
      'id': id,
      'title': title,
      'content': content,
      'isSynced': isSynced,
      'modifiedAt': DateTime.now().toIso8601String(),
    });
  }

  Future<Map<String, dynamic>?> getNote(String id) async {
    final _box = Hive.box<Map>(_notesBox);
    if (!_box.isOpen) await init(); // Ensure box is open
    return _box.get(id)?.cast<String, dynamic>();
  }

  Future<List<Map>> getUnsyncedNotes() async {
    final box = Hive.box<Map>(_notesBox);
    return box.values.where((note) => note['isSynced'] == false).toList();
  }

  Future<void> clearAllData() async {
    final box = Hive.box<Map>(_notesBox);
    await box.clear();
    debugPrint('All local data cleared');
  }


  Future<void> markNoteAsUnsynced(String id) async {
    final note = await getNote(id);
    if (note != null) {
      await saveNoteLocally(
        id: id,
        title: note['title'],
        content: note['content'],
        isSynced: false,
        modifiedAt: DateTime.now().toIso8601String(),
      );
    }
  }


  Future<void> replaceLocalNote({

    required String oldId,
    required String newId,
    required String title,
    required String content,
    bool isSynced = true,
    String? modifiedAt,
  }) async {
    // 1. Delete the old note if it exists
    if (_box.containsKey(oldId)) {
      await _box.delete(oldId);
    }

    // 2. Save the new version
    await _box.put(newId, {
      'id': newId,
      'title': title,
      'content': content,
      'isSynced': isSynced,
      'modifiedAt': modifiedAt ?? DateTime.now().toIso8601String(),
    });
  }

  // Also update markAsSynced to accept modifiedAt
  Future<void> markAsSynced(String id, {String? modifiedAt}) async {
    final note = _box.get(id);
    if (note != null) {
      await _box.put(id, {
        ...note,
        'isSynced': true,
        'modifiedAt': modifiedAt ?? DateTime.now().toIso8601String(),
      });
    }
  }


  Future<List<Map>> getAllLocalNotes() async {
    final _notesBox = 'offline_notes';
    final box = Hive.box<Map>(_notesBox);
    return box.values.toList();
  }

  Future<void> deleteLocalNote(String id) async {
    final _notesBox = 'offline_notes';
    final box = Hive.box<Map>(_notesBox);
    await box.delete(id);
  }
//
// final localStorageServiceProvider = Provider<LocalStorageService>((ref)  {
//   final service = LocalStorageService();
//   await service.init(); // Make sure it's ready before usage
//   return service;
// });
}