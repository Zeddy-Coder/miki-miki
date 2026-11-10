import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import '../models/media_models.dart';
import '../services/remote_driver.dart';
import 'app_animation_kit.dart';
import 'side_panel.dart';

class SidePanelDrawer extends StatelessWidget {
  final double scale;
  final SidePanelType? activeSidePanel;
  final Player player;
  final List<Media> playlistItems;
  final int currentPlaylistIndex;
  final List<VideoChapter> chapters;
  final VoidCallback onClose;
  final VoidCallback onAddMedia;
  final ValueChanged<int> onEpisodeSelected;
  final ValueChanged<Duration> onChapterSelected;
  final void Function(int from, int to) onQueueReorder;
  final ValueChanged<int> onQueueRemove;
  final VoidCallback onQueueClear;

  /// Серії із сайту (див. [SidePanel.remote])
  final RemoteDriver? remote;

  const SidePanelDrawer({
    super.key,
    required this.scale,
    required this.activeSidePanel,
    required this.player,
    required this.playlistItems,
    required this.currentPlaylistIndex,
    required this.chapters,
    required this.onClose,
    required this.onAddMedia,
    required this.onEpisodeSelected,
    required this.onChapterSelected,
    required this.onQueueReorder,
    required this.onQueueRemove,
    required this.onQueueClear,
    this.remote,
  });

  @override
  Widget build(BuildContext context) {
    return AppSlideReveal(
      isOpen: activeSidePanel != null,
      extent: 380.0 * scale,
      child: AppFadeSwitcher(
        expand: true,
        child: activeSidePanel != null
            ? SidePanel(
                key: ValueKey(activeSidePanel),
                scale: scale,
                type: activeSidePanel!,
                player: player,
                playlistItems: playlistItems,
                currentPlaylistIndex: currentPlaylistIndex,
                chapters: chapters,
                onClose: onClose,
                onAddMedia: onAddMedia,
                onEpisodeSelected: onEpisodeSelected,
                onChapterSelected: onChapterSelected,
                onQueueReorder: onQueueReorder,
                onQueueRemove: onQueueRemove,
                onQueueClear: onQueueClear,
                remote: remote,
              )
            : const SizedBox.shrink(key: ValueKey('panel-none')),
      ),
    );
  }
}
