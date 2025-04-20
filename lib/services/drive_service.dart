import 'package:drivenotes/pages/notes_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart';
import 'package:googleapis_auth/googleapis_auth.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:synchronized/synchronized.dart';

class DriveService {
  final DriveApi _driveApi;
  String? _cachedFolderId;
  final _syncLock = Lock();

  DriveService(AuthClient authClient) : _driveApi = DriveApi(authClient);

  static const String _notesFolderName = 'DriveNotesApp';
  static const String _notesFolderMimeType = 'application/vnd.google-apps.folder';
  static const String _fileMimeType = 'text/plain';

  /// Checks if the service has valid connection to Google Drive
  Future<bool> checkConnection() async {
    try {
      await _driveApi.files.list(pageSize: 1);
      return true;
    } catch (e) {
      debugPrint('Connection check failed: $e');
      return false;
    }
  }

  /// Gets or creates the notes folder with retry logic
  Future<String> _getOrCreateNotesFolder() async {
    if (_cachedFolderId != null) return _cachedFolderId!;

    return await _syncLock.synchronized(() async {
      if (_cachedFolderId != null) return _cachedFolderId!;

      try {
        final folderQuery = "mimeType='$_notesFolderMimeType' and name='$_notesFolderName' and trashed=false";
        final folders = await _driveApi.files.list(q: folderQuery);

        if (folders.files != null && folders.files!.isNotEmpty) {
          _cachedFolderId = folders.files!.first.id;
          return _cachedFolderId!;
        }

        final folder = File()
          ..name = _notesFolderName
          ..mimeType = _notesFolderMimeType;

        final createdFolder = await _driveApi.files.create(folder);
        _cachedFolderId = createdFolder.id;
        return _cachedFolderId!;
      } catch (e) {
        debugPrint('Failed to get/create folder: $e');
        rethrow;
      }
    });
  }

  /// Retrieves all notes with enhanced error handling
  Future<List<File>> getNotes() async {
    try {
      final folderId = await _getOrCreateNotesFolder();
      final query = "'$folderId' in parents and trashed=false";
      final response = await _driveApi.files.list(
        q: query,
        $fields: 'files(id,name,modifiedTime,version)',
      );
      return response.files ?? [];
    } catch (e) {
      debugPrint('Error getting notes: $e');
      rethrow;
    }
  }

  /// Creates a new note with retry logic
  Future<File> createNote(String title, String content) async {

    try {
      final folderId = await _getOrCreateNotesFolder();
      final file = File()
        ..name = '$title.txt'
        ..parents = [folderId]
        ..mimeType = _fileMimeType;

      final bytes = utf8.encode(content);
      final media = Media(
        Stream.value(bytes),
        bytes.length,
      );

      return await _driveApi.files.create(file, uploadMedia: media);
    } catch (e) {
      debugPrint('Error creating note: $e');


      // Retry once if fails
      await Future.delayed(const Duration(seconds: 1));
      return createNote(title, content);
    }
  }


  /// Updates an existing note with conflict handling
  Future<File> updateNote(String fileId, String title, String content) async {
    try {
      // 1. Get current file metadata first (critical for version control)
      final currentFile = await _driveApi.files.get(
        fileId,
        $fields: 'parents,version,modifiedTime',
      );
      debugPrint('Current file version: ${currentFile}');

      // 2. Prepare the update with all required metadata
      final file = File()
        ..name = '$title.txt'
        ..mimeType = _fileMimeType;
        // ..addParents = currentFile.parents?.join(',') // String of parent IDs
        // ..keepRevisionForever = true; // Alternative to version control

      // 3. Create media content with proper streaming
      final contentBytes = utf8.encode(content);
      final media = Media(
        Stream.value(contentBytes),
        contentBytes.length,
      );

      debugPrint('Updating file $fileId with ${contentBytes.length} bytes');

      // 4. Execute update with full field response
      final updatedFile = await _driveApi.files.update(
        file,
        fileId,
        uploadMedia: media,
        $fields: 'id,name,modifiedTime,version,parents',
      );

      debugPrint('Successfully updated: ${updatedFile.id} (v${updatedFile.version})');
      return updatedFile;
    } on DetailedApiRequestError catch (e) {
      debugPrint('''
    Drive API Update Failed!
    FileID: $fileId
    Status: ${e.status}
    Message: ${e.message}
    Headers: ${e.errors}
    ''');
      rethrow;
    } catch (e, stack) {
      debugPrint('Update failed: $e\n$stack');
      rethrow;
    }
  }

  /// Deletes a note with error handling
  Future<void> deleteNote(String fileId) async {
    try {
      await _driveApi.files.delete(fileId);
    } catch (e) {
      debugPrint('Error deleting note: $e');
      rethrow;
    }
  }

  /// Gets note content with proper stream handling
  Future<String> getNoteContent(String fileId) async {
    try {
      final media = await _driveApi.files.get(
        fileId,
        downloadOptions: DownloadOptions.fullMedia,
      ) as Media;

      final bytes = await media.stream.fold<Uint8List>(
        Uint8List(0),
            (previous, element) => Uint8List.fromList([...previous, ...element]),
      );

      return utf8.decode(bytes);
    } catch (e) {
      debugPrint('Error getting note content: $e');
      rethrow;
    }
  }

  /// Gets file metadata
  Future<Object> getFileMetadata(String fileId) async {
    try {
      return await _driveApi.files.get(
        fileId,
        $fields: 'id,name,modifiedTime,version',
      );
    } catch (e) {
      debugPrint('Error getting file metadata: $e');
      rethrow;
    }
  }

  /// Checks if file exists in Drive
  Future<bool> fileExists(String fileId) async {
    try {
      await _driveApi.files.get(fileId, $fields: 'id');
      return true;
    } catch (e) {
      return false;
    }
  }
}