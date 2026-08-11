import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'localizations.dart';

enum StudySoundSourceType { asset, network, file, uri }

class StudySoundTrack {
  const StudySoundTrack.asset({
    required this.id,
    required this.label,
    required String path,
  }) : sourceType = StudySoundSourceType.asset,
       source = path;

  const StudySoundTrack.network({
    required this.id,
    required this.label,
    required String url,
  }) : sourceType = StudySoundSourceType.network,
       source = url;

  const StudySoundTrack.file({
    required this.id,
    required this.label,
    required String path,
  }) : sourceType = StudySoundSourceType.file,
       source = path;

  const StudySoundTrack.uri({
    required this.id,
    required this.label,
    required String uri,
  }) : sourceType = StudySoundSourceType.uri,
       source = uri;

  final String id;
  final String label;
  final StudySoundSourceType sourceType;
  final String source;

  static const builtIns = [
    StudySoundTrack.asset(
      id: 'rain',
      label: 'Rain',
      path: 'assets/audio/rain.wav',
    ),
    StudySoundTrack.asset(
      id: 'white_noise',
      label: 'White noise',
      path: 'assets/audio/white_noise.wav',
    ),
    StudySoundTrack.asset(
      id: 'cafe',
      label: 'Cafe',
      path: 'assets/audio/cafe.wav',
    ),
    StudySoundTrack.asset(
      id: 'library',
      label: 'Library',
      path: 'assets/audio/library.wav',
    ),
    StudySoundTrack.asset(
      id: 'keyboard',
      label: 'Keyboard',
      path: 'assets/audio/keyboard.wav',
    ),
  ];
}

abstract class StudySoundPlayer {
  Future<void> play(StudySoundTrack track, {double volume = 0.5});

  Future<void> pause();

  Future<void> setVolume(double volume);

  Future<void> dispose();
}

class JustAudioStudySoundPlayer implements StudySoundPlayer {
  JustAudioStudySoundPlayer({AudioPlayer? player})
    : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Future<void> play(StudySoundTrack track, {double volume = 0.5}) async {
    await _player.setLoopMode(LoopMode.one);
    await _player.setVolume(volume.clamp(0.0, 1.0));
    switch (track.sourceType) {
      case StudySoundSourceType.asset:
        await _player.setAsset(track.source, package: 'study_room_ui');
      case StudySoundSourceType.network:
        await _player.setUrl(track.source);
      case StudySoundSourceType.file:
        await _player.setFilePath(track.source);
      case StudySoundSourceType.uri:
        await _player.setAudioSource(AudioSource.uri(Uri.parse(track.source)));
    }
    unawaited(_player.play());
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> setVolume(double volume) =>
      _player.setVolume(volume.clamp(0.0, 1.0));

  @override
  Future<void> dispose() => _player.dispose();
}

class BackgroundSoundView extends StatefulWidget {
  const BackgroundSoundView({
    this.tracks = StudySoundTrack.builtIns,
    this.soundPlayer,
    super.key,
  });

  final List<StudySoundTrack> tracks;
  final StudySoundPlayer? soundPlayer;

  @override
  State<BackgroundSoundView> createState() => _BackgroundSoundViewState();
}

class _BackgroundSoundViewState extends State<BackgroundSoundView> {
  late final StudySoundPlayer _player =
      widget.soundPlayer ?? JustAudioStudySoundPlayer();
  late StudySoundTrack? _selected = widget.tracks.isEmpty
      ? null
      : widget.tracks.first;
  var _playing = false;
  var _volume = 0.5;

  @override
  void dispose() {
    if (widget.soundPlayer == null) {
      _player.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.tracks
                .map((track) {
                  return ChoiceChip(
                    label: Text(_localizedTrackLabel(track, localizations)),
                    selected: _selected?.id == track.id,
                    onSelected: (_) => setState(() => _selected = track),
                  );
                })
                .toList(growable: false),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton.filled(
                tooltip: localizations.play,
                icon: const Icon(Icons.play_arrow),
                onPressed: _selected == null
                    ? null
                    : () async {
                        await _player.play(_selected!, volume: _volume);
                        if (mounted) {
                          setState(() => _playing = true);
                        }
                      },
              ),
              IconButton(
                tooltip: localizations.pause,
                icon: const Icon(Icons.pause),
                onPressed: !_playing
                    ? null
                    : () async {
                        await _player.pause();
                        if (mounted) {
                          setState(() => _playing = false);
                        }
                      },
              ),
              Expanded(
                child: Slider(
                  value: _volume,
                  onChanged: (value) {
                    setState(() => _volume = value);
                    _player.setVolume(value);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _localizedTrackLabel(
  StudySoundTrack track,
  StudyRoomLocalizations localizations,
) {
  final builtIn = StudySoundTrack.builtIns.any(
    (candidate) => identical(candidate, track),
  );
  if (!builtIn) return track.label;
  return switch (track.id) {
    'rain' => localizations.soundRain,
    'white_noise' => localizations.soundWhiteNoise,
    'cafe' => localizations.soundCafe,
    'library' => localizations.soundLibrary,
    'keyboard' => localizations.soundKeyboard,
    _ => track.label,
  };
}
