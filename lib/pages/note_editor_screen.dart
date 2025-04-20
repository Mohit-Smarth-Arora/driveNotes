import 'package:drivenotes/pages/notes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:googleapis/drive/v3.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../main.dart';
import '../services/drive_services_provider.dart';
import '../services/local/local_storage_service.dart';
import '../services/local/sync_service.dart';
import '../services/notes_provider.dart';

class NoteEditorScreen extends ConsumerStatefulWidget {
  final File? note;

  const NoteEditorScreen({super.key, this.note});

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  bool _isLoading = false;
  bool _isPreview = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _contentController = TextEditingController();
    _loadNote();

    // Listen for changes
    _titleController.addListener(_checkForChanges);
    _contentController.addListener(_checkForChanges);
  }


  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _checkForChanges() {
    if (widget.note == null) {
      setState(() => _hasChanges = _titleController.text.isNotEmpty ||
          _contentController.text.isNotEmpty);
    } else {
      // For existing notes, only mark as changed if content is different
      setState(() => _hasChanges = true);
    }
  }

  Future<void> _loadNote() async {
    if (widget.note == null) return;

    setState(() => _isLoading = true);
    try {
      final localStorage = ref.read(localStorageServiceProvider);
      final driveService = ref.read(driveServiceProvider);

      // Try loading from local storage first
      final localNote = await localStorage.getNote(widget.note!.id!);

      if (localNote != null) {
        _titleController.text = localNote['title'] ?? '';
        _contentController.text = localNote['content'] ?? '';
      }
      // Fallback to remote if not found locally
      else if (driveService != null) {
        final content = await driveService.getNoteContent(widget.note!.id!);
        _titleController.text = widget.note!.name?.replaceAll('.txt', '') ?? '';
        _contentController.text = content;

        // Cache remote note locally
        await localStorage.saveNoteLocally(
          id: widget.note!.id!,
          title: _titleController.text,
          content: content,
          isSynced: true,
          modifiedAt: widget.note!.modifiedTime?.toIso8601String() ??
              DateTime.now().toIso8601String(),
        );
      }
    } catch (e) {
      _showError('Failed to load note: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasChanges = false;
        });
      }
    }
  }




  Future<void> _saveNote() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    final connectivityStatusProvider = StreamProvider<bool>((ref) {
      return ref.watch(syncServiceProvider).connectivityStream;
    });


    if (title.isEmpty) {
      _showError('Title cannot be empty');
      return;
    }

    setState(() => _isLoading = true);
    try {

      final notesNotifier = ref.read(notesProvider.notifier);
      final isOnline = ref.read(connectivityStatusProvider).value ?? false;

      if (widget.note == null) {
        await notesNotifier.createNote(title, content);
      } else {
        await notesNotifier.updateNote(widget.note!.id!, title, content);
      }

      if (mounted) {
        // Only navigate if we're online or don't need sync
        if (isOnline || widget.note == null) {
          Navigator.pop(context);
        } else {
          // For offline updates, show success but stay in editor
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Saved locally - will sync when online')),
          );
          setState(() {
            _isLoading = false;
            _hasChanges = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to save note: ${e.toString()}');
        setState(() => _isLoading = false);
      }
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasChanges) return true;

    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard changes?'),
            content: const Text(
                'You have unsaved changes. Are you sure you want to discard them?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (!_hasChanges) return true;
        return await _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          title: TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              hintText: 'Note title',
              border: InputBorder.none,
            ),
            style: Theme.of(context).textTheme.titleLarge,
            enabled: !_isLoading,
          ),
          actions: [
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.save,color: Colors.blue,),
                onPressed: _hasChanges
                    ? () async{
                  await _saveNote();                  // Your note saving logic
                  // Navigator.push(context, MaterialPageRoute(builder: (context) => const NotesScreen()));       // Go back after saving
                }
                    : null,
                tooltip: 'Save',
              ),

              // IconButton(
              //   icon: const Icon(Icons.save),
              //   onPressed: _hasChanges ? _saveNote  : null,
              //   tooltip: 'Save',
              // ),


            IconButton(
              icon: Icon(_isPreview ? Icons.edit : Icons.preview),
              onPressed: () => setState(() => _isPreview = !_isPreview),
              tooltip: _isPreview ? 'Edit mode' : 'Preview mode',
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())   // can put notesscreen here to avoid loading indicator


            : _isPreview
                ? Markdown(
                    data: _contentController.text,
                    padding: const EdgeInsets.all(16),
                  )
                : Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TextField(
                      controller: _contentController,
                      maxLines: null,
                      expands: true,
                      decoration: const InputDecoration(
                        hintText: 'Start writing...',
                        border: InputBorder.none,
                      ),
                      enabled: !_isLoading,
                    ),
                  ),

      ),
    );
  }
}
