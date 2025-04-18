import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:googleapis/drive/v3.dart';
import '../auth/auth_repository_provider.dart';
import '../services/drive_services_provider.dart';
import '../services/notes_provider.dart';
import '../themes/theme_provider.dart';
import 'auth_screen.dart';
import 'note_editor_screen.dart';

// import 'notes_provider.dart';
// import 'auth_repository.dart';

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  bool _isCreatingNote = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notesProvider.notifier).refreshNotes();
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeNotifier = ref.watch(themeProvider);
    final notesAsync = ref.watch(notesProvider);
    final currentUser = ref.watch(authRepositoryProvider).getCurrentUser();
    final isAuthReady = ref.watch(authClientProvider.select((s) => !s.isLoading));

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Notes'),
        actions: [
          // ... (existing theme and profile actions)

          Consumer(
            builder: (context, ref, _) {
              final themeNotifier = ref.watch(themeProvider);
              return IconButton(
                icon: Icon(
                  themeNotifier.isDarkMode ? Icons.dark_mode : Icons.light_mode,
                ),
                onPressed: () {
                  ref
                      .read(themeProvider)
                      .ToggleTheme(); // Toggle theme on button press
                },
              );
            },
          ),
          FutureBuilder(
            future: currentUser,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return CircleAvatar(
                  backgroundImage: NetworkImage(snapshot.data!.photoUrl ?? ''),
                  radius: 16,
                );
              }
              return const SizedBox.shrink();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authRepositoryProvider).signOut();
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const AuthScreen()),
                );
              }
            },
          ),

        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: isAuthReady && !_isCreatingNote
            ? () => _createNewNote(context)
            : null,
        child: _isCreatingNote
            ? const CircularProgressIndicator()
            : const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          try {
            await ref.read(notesProvider.notifier).refreshNotes();
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Refresh failed: $e')),
            );
          }
        },
        child: notesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Error loading notes: $error'),
                TextButton(
                  onPressed: () => ref.refresh(notesProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
          data: (notes) {
            if (notes.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('No notes yet. Tap + to create one!'),
                    if (!isAuthReady) ...[
                      const SizedBox(height: 16),
                      const CircularProgressIndicator(),
                      const SizedBox(height: 8),
                      const Text('Waiting for authentication...'),
                    ],
                  ],
                ),
              );
            }
            return ListView.builder(
              itemCount: notes.length,
              itemBuilder: (context, index) {
                final note = notes[index];
                return ListTile(
                  leading: const Icon(Icons.note),
                  title: Text(note.name?.replaceAll('.txt', '') ?? 'Untitled'),
                  subtitle: Text(
                    note.modifiedTime?.toIso8601String() ?? 'No date',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  onTap: () => _openNoteEditor(context, note),
                  onLongPress: () => _deleteNote(context, note),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _createNewNote(BuildContext context) async {
    setState(() => _isCreatingNote = true);
    try {
      final navigator = Navigator.of(context);
      await navigator.push(
        MaterialPageRoute(
          builder: (context) => const NoteEditorScreen(note: null),
        ),
      );
      await ref.read(notesProvider.notifier).refreshNotes();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create note: $e')),
      );
    } finally {
      if (mounted) setState(() => _isCreatingNote = false);
    }
  }

  void _openNoteEditor(BuildContext context, File note) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NoteEditorScreen(note: note),
      ),
    ).then((_) => ref.read(notesProvider.notifier).refreshNotes());
  }

  Future<void> _deleteNote(BuildContext context, File note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Note'),
        content: Text(
            'Are you sure you want to delete "${note.name?.replaceAll('.txt', '')}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Deleting note...')),
      );
      try {
        await ref.read(notesProvider.notifier).deleteNote(note.id!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Note deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete failed: $e')),
          );
        }
      }
    }
  }
}