import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:study_room_sdk/study_room_sdk.dart';

/// Package-internal reactive bridge shared by independently compiled focus
/// modules. It is intentionally not exported from the package barrel.
class StudyStoreListenableBuilder<T> extends StatefulWidget {
  const StudyStoreListenableBuilder({
    required this.store,
    required this.dependency,
    required this.changeKinds,
    required this.load,
    required this.builder,
    super.key,
  });

  final StudyStore store;
  final Object dependency;
  final Set<StudyStoreChangeKind> changeKinds;
  final Future<T> Function() load;
  final AsyncWidgetBuilder<T> builder;

  @override
  State<StudyStoreListenableBuilder<T>> createState() =>
      _StudyStoreListenableBuilderState<T>();
}

class _StudyStoreListenableBuilderState<T>
    extends State<StudyStoreListenableBuilder<T>> {
  StreamSubscription<StudyStoreChange>? _subscription;
  AsyncSnapshot<T> _snapshot = const AsyncSnapshot.waiting();
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    _subscribe();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant StudyStoreListenableBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      unawaited(_subscription?.cancel());
      _subscribe();
    }
    if (oldWidget.store != widget.store ||
        oldWidget.dependency != widget.dependency) {
      unawaited(_load(clear: true));
    }
  }

  @override
  void dispose() {
    ++_generation;
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _subscribe() {
    _subscription = widget.store.changes.listen((change) {
      if (mounted && widget.changeKinds.contains(change.kind)) {
        unawaited(_load());
      }
    });
  }

  Future<void> _load({bool clear = false}) async {
    final generation = ++_generation;
    if (clear && mounted) {
      setState(() => _snapshot = const AsyncSnapshot.waiting());
    }
    try {
      final value = await widget.load();
      if (!mounted || generation != _generation) {
        return;
      }
      setState(
        () => _snapshot = AsyncSnapshot.withData(ConnectionState.done, value),
      );
    } catch (error, stackTrace) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(
        () => _snapshot = AsyncSnapshot.withError(
          ConnectionState.done,
          error,
          stackTrace,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _snapshot);
}
