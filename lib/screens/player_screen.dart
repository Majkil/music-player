import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import '../services/audio_handler.dart';

class PlayerScreen extends StatelessWidget {
  final MusicAudioHandler audioHandler;

  const PlayerScreen({super.key, required this.audioHandler});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Now Playing',
          style: TextStyle(fontWeight: FontWeight.w400, fontSize: 16),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down, size: 30),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<MediaItem?>(
        stream: audioHandler.mediaItem,
        builder: (context, snapshot) {
          final mediaItem = snapshot.data;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                const Spacer(flex: 1),
                // Album art placeholder
                _AlbumArt(mediaItem: mediaItem),
                const Spacer(flex: 1),
                // Song info
                _SongInfo(mediaItem: mediaItem),
                const SizedBox(height: 32),
                // Seek bar
                _SeekBar(audioHandler: audioHandler),
                const SizedBox(height: 24),
                // Controls
                _PlaybackControls(audioHandler: audioHandler),
                const Spacer(flex: 2),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AlbumArt extends StatelessWidget {
  final MediaItem? mediaItem;
  const _AlbumArt({required this.mediaItem});

  @override
  Widget build(BuildContext context) {
    if (mediaItem?.artUri != null) {
      return Container(
        width: 280,
        height: 280,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          image: DecorationImage(
            image: FileImage(File(mediaItem!.artUri!.toFilePath())),
            fit: BoxFit.cover,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(120),
              blurRadius: 40,
              spreadRadius: 5,
              offset: const Offset(0, 10),
            ),
          ],
        ),
      );
    }

    final title = mediaItem?.title ?? '';
    final hash = title.hashCode;
    final hue1 = (hash % 360).abs().toDouble();
    final hue2 = ((hash ~/ 360) % 360).abs().toDouble();

    return Container(
      width: 280,
      height: 280,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            HSLColor.fromAHSL(1, hue1, 0.6, 0.4).toColor(),
            HSLColor.fromAHSL(1, hue2, 0.5, 0.25).toColor(),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: HSLColor.fromAHSL(0.3, hue1, 0.6, 0.4).toColor(),
            blurRadius: 40,
            spreadRadius: 5,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: const Center(
        child: Icon(
          Icons.music_note_rounded,
          color: Colors.white54,
          size: 80,
        ),
      ),
    );
  }
}

class _SongInfo extends StatelessWidget {
  final MediaItem? mediaItem;
  const _SongInfo({this.mediaItem});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          mediaItem?.title ?? 'No song selected',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        Text(
          mediaItem?.artist ?? 'Unknown Artist',
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 16,
            fontWeight: FontWeight.w400,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _SeekBar extends StatelessWidget {
  final MusicAudioHandler audioHandler;
  const _SeekBar({required this.audioHandler});

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PositionData>(
      stream: audioHandler.positionDataStream,
      builder: (context, snapshot) {
        final positionData = snapshot.data ??
            PositionData(Duration.zero, Duration.zero, Duration.zero);
        final position = positionData.position;
        final duration = positionData.duration;

        return Column(
          children: [
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: const Color(0xFF6C63FF),
                inactiveTrackColor: Colors.white.withAlpha(25),
                thumbColor: const Color(0xFF6C63FF),
                overlayColor: const Color(0xFF6C63FF).withAlpha(30),
              ),
              child: Slider(
                min: 0,
                max: duration.inMilliseconds.toDouble(),
                value: min(
                  position.inMilliseconds.toDouble(),
                  duration.inMilliseconds.toDouble(),
                ),
                onChanged: (value) {
                  audioHandler.seek(Duration(milliseconds: value.toInt()));
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(position),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  Text(
                    _formatDuration(duration),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PlaybackControls extends StatelessWidget {
  final MusicAudioHandler audioHandler;
  const _PlaybackControls({required this.audioHandler});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackState>(
      stream: audioHandler.playbackState,
      builder: (context, snapshot) {
        final playing = snapshot.data?.playing ?? false;
        final processingState = snapshot.data?.processingState;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Previous button
            IconButton(
              icon: const Icon(Icons.skip_previous_rounded),
              iconSize: 42,
              color: Colors.white,
              onPressed: audioHandler.skipToPrevious,
            ),
            const SizedBox(width: 16),
            // Play/Pause button
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF4A42D4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6C63FF).withAlpha(100),
                    blurRadius: 20,
                    spreadRadius: 2,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: processingState == AudioProcessingState.loading ||
                      processingState == AudioProcessingState.buffering
                  ? const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      ),
                    )
                  : IconButton(
                      icon: Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      iconSize: 40,
                      color: Colors.white,
                      onPressed: playing
                          ? audioHandler.pause
                          : audioHandler.play,
                    ),
            ),
            const SizedBox(width: 16),
            // Next button
            IconButton(
              icon: const Icon(Icons.skip_next_rounded),
              iconSize: 42,
              color: Colors.white,
              onPressed: audioHandler.skipToNext,
            ),
          ],
        );
      },
    );
  }
}
