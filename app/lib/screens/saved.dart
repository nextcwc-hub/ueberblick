import 'package:flutter/material.dart';

import '../data.dart';
import '../theme.dart';
import '../widgets.dart';
import 'home.dart';

class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final list = app.savedStories;
          return ListView(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text('Gemerkt', style: serif(context, 26, w: FontWeight.w700)),
            ),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 80, 32, 0),
                child: Column(children: [
                  Icon(Icons.bookmark_border, size: 40, color: muted(context)),
                  const SizedBox(height: 12),
                  Text('Tippe in einem Artikel auf das Lesezeichen, um ihn hier offline zu speichern.',
                      textAlign: TextAlign.center, style: sans(context, 14.5, color: muted(context), h: 1.5)),
                ]),
              ),
            for (final (i, s) in list.indexed) ...[
              if (i > 0) const Divider(indent: 16, endIndent: 16),
              Dismissible(
                key: ValueKey(s.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  color: breaking.withValues(alpha: 0.12),
                  child: const Icon(Icons.delete_outline, color: breaking),
                ),
                onDismissed: (_) => app.toggleSaved(s),
                child: StoryTile(s, onTap: () => openStory(context, list, i)),
              ),
            ],
          ]);
        },
      ),
    );
  }
}
