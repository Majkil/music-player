import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import 'package:home_widget/home_widget.dart';

class MusicAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  final ConcatenatingAudioSource _playlist = ConcatenatingAudioSource(children: []);

  MusicAudioHandler() {
    _init();
  }

  Future<void> _init() async {
    // Broadcast playback state changes
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);

    // Listen for current index changes to update mediaItem
    _player.currentIndexStream.listen((index) {
      if (index != null && index < queue.value.length) {
        mediaItem.add(queue.value[index]);
        _updateWidget();
      }
    });

    // Listen for processing state to auto-advance
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        // Handled by loopMode / auto-advance
      }
    });
  }

  AudioPlayer get player => _player;

  /// Load a list of MediaItems as the queue
  Future<void> loadQueue(List<MediaItem> items, {int initialIndex = 0}) async {
    queue.add(items);

    final audioSources = items.map((item) {
      return AudioSource.file(item.id, tag: item);
    }).toList();

    await _playlist.clear();
    await _playlist.addAll(audioSources);
    await _player.setAudioSource(_playlist, initialIndex: initialIndex);

    if (initialIndex < items.length) {
      mediaItem.add(items[initialIndex]);
    }
  }

  @override
  Future<void> play() async {
    await _player.play();
    _updateWidget();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _updateWidget();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
    _updateWidget();
    return super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    if (_player.hasNext) {
      await _player.seekToNext();
      _updateWidget();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
      _updateWidget();
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index >= 0 && index < queue.value.length) {
      await _player.seek(Duration.zero, index: index);
      mediaItem.add(queue.value[index]);
      _updateWidget();
    }
  }

  /// Stream of position, buffered position, and duration for the seek bar
  Stream<PositionData> get positionDataStream =>
      Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
        _player.positionStream,
        _player.bufferedPositionStream,
        _player.durationStream,
        (position, bufferedPosition, duration) => PositionData(
          position,
          bufferedPosition,
          duration ?? Duration.zero,
        ),
      );

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    );
  }

  Future<void> _updateWidget() async {
    try {
      final currentItem = mediaItem.value;
      await HomeWidget.saveWidgetData<String>(
        'song_title',
        currentItem?.title ?? 'No song playing',
      );
      await HomeWidget.saveWidgetData<String>(
        'song_artist',
        currentItem?.artist ?? '',
      );
      await HomeWidget.saveWidgetData<bool>(
        'is_playing',
        _player.playing,
      );
      await HomeWidget.updateWidget(
        androidName: 'MusicWidgetProvider',
      );
    } catch (_) {
      // Widget update failed, non-critical
    }
  }
}

class PositionData {
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;

  PositionData(this.position, this.bufferedPosition, this.duration);
}
