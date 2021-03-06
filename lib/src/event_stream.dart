import 'dart:async';
import 'dart:collection';

import 'core.dart';

export 'dart:async';

export 'core.dart' show Event;

// TODO: do we really care that T extends Event?
/// A broadcast [Stream] which
///
/// * May have both standard async or sync listeners simultaneously
/// * Guarantees ordered delivery to all listeners (unless some listeners are
/// paused) of like type (sync or async)
class EventStream<T extends Event> extends Stream<T> implements EventSink<T> {
  // Maintain separate listener lists, as it is important that async listeners
  // are scheduled before sync listeners are run. This is because sync listeners
  // may themselves schedule tasks, which should not become before the original
  // scheduled tasks. Think of this stream itself as the first of the
  // synchronous "reactions" – the listeners to this shouldn't skip ahead.
  var _asyncListeners = <_AsyncEventSubscription>[];
  var _syncListeners = <_SyncEventSubscription>[];
  var _subscriptions = <StreamSubscription>[];
  // Sync should be safe due to completion from other futures (see [close])
  final _done = Completer.sync();

  final bool isBroadcast = true;

  Stream<T> get asSynchronousStream => _SynchronousEventStream<T>(this);

  @override
  StreamSubscription<T> listen(void Function(T event) onData,
      {Function onError, void Function() onDone, bool cancelOnError}) {
    // TODO: implement other args
    var sub = _AsyncEventSubscription<T>()
      ..onData(onData)
      ..onDone(onDone);

    if (isClosed) {
      sub._close();
    } else {
      _asyncListeners.add(sub);
    }

    return sub;
  }

  /// Creates and returns a new [EventStream] which is a _child_ of this event
  /// stream.
  ///
  /// This stream (the parent) will include all events added to the child. The
  /// child is otherwise an independent stream which does not include events
  /// from the parent and has its own type parameter (though it must be
  /// covariant with the parent type parameter).
  EventStream<E> childStream<E extends T>() {
    var child = EventStream<E>();
    includeStream(child);
    return child;
  }

  void add(T event) {
    if (isClosed) {
      throw StateError('stream is closed; cannot add event');
    }
    _asyncListeners.forEach((sub) => sub._add(event));
    _syncListeners.forEach((sub) => sub._add(event));
  }

  void addError(Object error, [StackTrace trace]) {
    if (isClosed) {
      throw StateError('stream is closed; cannot add error');
    }
    _asyncListeners.forEach((sub) => sub._addError(error));
    _syncListeners.forEach((sub) => sub._addError(error));
  }

  void includeStoryElement(StoryElement<T> emitter) {
    includeStream(emitter.events);
  }

  void includeAll(Iterable<Stream<T>> streams) {
    streams.forEach(includeStream);
  }

  void includeStream(Stream<T> stream) {
    if (isClosed) {
      throw StateError('stream is closed; cannot include stream');
    }
    var sub = stream.listen((t) => add(t), onError: (e) => addError(e));
    _subscriptions.add(sub);
  }

  Future close() {
    if (!isClosed) {
      // TODO: not sure if logic around here is right
      var cancellations = <Future>[];
      _subscriptions.forEach(((sub) => cancellations.add(sub.cancel())));
      _asyncListeners.forEach((sub) => sub._close());
      _syncListeners.forEach((sub) => sub._close());

      // Does setting to null have any value?
      _asyncListeners = null;
      _syncListeners = null;
      _subscriptions = null;

      Future.wait(cancellations).then((_) => _done.complete());
    }

    return done;
  }

  Future get done => _done.future;

  bool get isClosed => _asyncListeners == null;
}

class _SynchronousEventStream<T> extends Stream<T> {
  final EventStream _backing;

  final bool isBroadcast = true;

  _SynchronousEventStream(this._backing);

  @override
  StreamSubscription<T> listen(void Function(T event) onData,
      {Function onError, void Function() onDone, bool cancelOnError}) {
    var sub = _SyncEventSubscription<T>()
      ..onData(onData)
      ..onDone(onDone);
    _backing._syncListeners?.add(sub);
    return sub;
  }
}

abstract class _EventSubscription<T> extends StreamSubscription<T> {
  void Function(T) _onData;
  void Function() _onDone;
  var _pauses = 0;
  var _buffer = Queue<T>();
  var _isCanceled = false;
  var _isDone = false;

  @override
  Future<E> asFuture<E>([E futureValue]) {
    // TODO: implement asFuture
    throw UnimplementedError();
  }

  @override
  Future cancel() {
    // TODO: just remove self from listeners list?
    _onData = null;
    _onDone = null;
    _buffer = null;
    _pauses = 0;
    _isCanceled = true;
    return Future.value();
  }

  @override
  bool get isPaused => _pauses > 0;

  @override
  void onData(void Function(T data) handleData) {
    _onData = handleData;
  }

  @override
  void onDone(void Function() handleDone) {
    _onDone = handleDone;
  }

  @override
  void onError(Function handleError) {
    throw UnimplementedError();
  }

  @override
  void pause([Future resumeSignal]) {
    if (_isCanceled || _isDone) return;
    _pauses++;
  }

  @override
  void resume() {
    if (!isPaused || _isCanceled || _isDone) return;
    _pauses--;
    if (!isPaused) {
      while (_buffer.isNotEmpty) {
        _add(_buffer.removeFirst());
      }
    }
  }

  void _addError(dynamic error) {
    throw UnimplementedError('addError. got $error');
  }

  void _add(T event) {
    if (_isCanceled) return;
    if (_onData == null) return;
    if (!isPaused) {
      var cb = _onData;
      _dispatch(() {
        if (!isPaused && !_isCanceled) {
          cb(event);
        }
      });
    } else {
      _buffer.add(event);
    }
  }

  void _close() {
    // TODO: is this logic right?
    if (_isDone) return;

    _onData = null;
    _buffer = null;
    _pauses = 0;
    _isDone = true;

    if (_onDone == null) return;

    _dispatch(_onDone);
    _onDone = null;
  }

  void _dispatch(void Function() fn);
}

class _AsyncEventSubscription<T> extends _EventSubscription<T> {
  void _dispatch(void Function() fn) {
    scheduleMicrotask(fn);
  }
}

class _SyncEventSubscription<T> extends _EventSubscription<T> {
  void _dispatch(Function fn) {
    fn();
  }
}
