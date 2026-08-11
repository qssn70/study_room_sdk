import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:study_room_sdk/study_room_sdk.dart';

import 'audio.dart';

class StudySoundCoordinator extends ChangeNotifier {
  StudySoundCoordinator({
    required this.tracks,
    required StudySoundPlayer? player,
    required StudyFocusSettings settings,
    required this.onChanged,
    required this.onError,
  }) : _ownsPlayer = player == null,
       _player = player ?? JustAudioStudySoundPlayer(),
       _volume = settings.soundVolume {
    _selected = _trackForId(settings.soundTrackId);
  }

  final List<StudySoundTrack> tracks;
  final StudySoundPlayer _player;
  final bool _ownsPlayer;
  final Future<void> Function(String? trackId, double volume) onChanged;
  final void Function(Object error, StackTrace stackTrace) onError;

  StudySoundTrack? _selected;
  bool _playing = false;
  double _volume;

  StudySoundTrack? get selected => _selected;
  bool get playing => _playing;
  double get volume => _volume;

  Future<void> toggle(StudySoundTrack track) async {
    try {
      if (_playing && _selected?.id == track.id) {
        await _player.pause();
        _playing = false;
      } else {
        await _player.play(track, volume: _volume);
        _selected = track;
        _playing = true;
        await onChanged(_selected?.id, _volume);
      }
      notifyListeners();
    } catch (error, stackTrace) {
      onError(error, stackTrace);
    }
  }

  Future<void> pause() async {
    if (!_playing) return;
    try {
      await _player.pause();
      _playing = false;
      notifyListeners();
    } catch (error, stackTrace) {
      onError(error, stackTrace);
    }
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0).toDouble();
    notifyListeners();
    try {
      await _player.setVolume(_volume);
      await onChanged(_selected?.id, _volume);
    } catch (error, stackTrace) {
      onError(error, stackTrace);
    }
  }

  void applySettings(StudyFocusSettings settings) {
    _selected = _trackForId(settings.soundTrackId);
    _volume = settings.soundVolume;
    _playing = false;
    notifyListeners();
  }

  StudySoundTrack? _trackForId(String? id) {
    if (tracks.isEmpty) return null;
    return tracks.firstWhere(
      (track) => track.id == id,
      orElse: () => tracks.first,
    );
  }

  @override
  void dispose() {
    if (_ownsPlayer) unawaited(_player.dispose());
    super.dispose();
  }
}
