part of '../august.dart';

// TODO: should use common supertype of T like `Event` or something like that?
class Events<T extends Event> {
  final _stream = _EventStream<T>();

  Stream<T> get stream => _stream;

  /// Schedules the function to run as the next event in the event loop. At that
  /// time, listeners will be scheduled in microtasks to receive the [event]
  /// functions return value.
  ///
  /// Listeners to this future, therefore, are fired before listeners of the
  /// event, because those event listeners are not scheduled until the future
  /// itself runs. Listeners to this future will be scheduled immediately.
  // TODO: should this return a future? It creates a way to listen to the event
  //   that isn't like regular listening mechanism.
  //   however, adds a way to add logic that fires after the event is added to
  //   the stream, without needing [post] parameter functionality.
  Future<T> event(T Function() event) {
    return Future(() {
      T theEvent;
      try {
        theEvent = event();
      } catch (e) {
        _stream._addError(e);
        rethrow;
      }
      _stream._add(theEvent);
      return theEvent;
    });
  }

  Future<T> eventValue(T event) {
    return Future(() {
      _stream._add(event);
      return event;
    });
  }

//  void publishNow(T event) {
//    _stream._add(event);
//  }

  void done() {
    _stream._done();
  }
}

abstract class Event {}

class _EventStream<T> extends Stream<T> {
  // Maintain separate listener lists, as it is important that async listeners
  // are scheduled before sync listeners are run. This is because sync listeners
  // may themselves schedule tasks, which should not become before the original
  // scheduled tasks. Think of this stream itself as the first of the
  // synchronous "reactions" – the listeners to this shouldn't skip ahead.
  var _asyncListeners = <_AsyncEventSubscription>[];
  var _syncListeners = <_SyncEventSubscription>[];

  final bool isBroadcast = true;

  _SynchronousEventStream<T> get asSynchronousStream =>
      _SynchronousEventStream<T>(this);

  @override
  StreamSubscription<T> listen(void Function(T event) onData,
      {Function onError, void Function() onDone, bool cancelOnError}) {
    var sub = _AsyncEventSubscription<T>()
      ..onData(onData)
      ..onDone(onDone);
    if (_asyncListeners != null) {
      _asyncListeners.add(sub);
    }
    return sub;
  }

  void _add(T event) {
    if (_asyncListeners == null) {
      throw StateError('Cannot add event to done stream');
    }
    _asyncListeners.forEach((sub) => sub._add(event));
    _syncListeners.forEach((sub) => sub._add(event));
  }

  void _addError(dynamic error) {
    if (_asyncListeners == null) {
      throw StateError('Cannot add error to done stream');
    }
    _asyncListeners.forEach((sub) => sub._addError(error));
    _syncListeners.forEach((sub) => sub._addError(error));
  }

  void _done() {
    // TODO: not sure if done logic around here is right
    _asyncListeners.forEach((sub) => sub._done());
    _syncListeners.forEach((sub) => sub._done());
    _asyncListeners = null;
    _syncListeners = null;
  }

  bool get _isDone => _asyncListeners == null;
}

class _SynchronousEventStream<T> extends Stream<T> {
  final _EventStream _backing;

  final bool isBroadcast = true;

  _SynchronousEventStream(this._backing);

  @override
  StreamSubscription<T> listen(void Function(T event) onData,
      {Function onError, void Function() onDone, bool cancelOnError}) {
    var sub = _SyncEventSubscription<T>()
      ..onData(onData)
      ..onDone(onDone);
    if (_backing._syncListeners != null) {
      _backing._syncListeners.add(sub);
    }
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
    if (_isCanceled) return;
    _pauses++;
  }

  @override
  void resume() {
    if (!isPaused || _isCanceled) return;
    _pauses--;
    // TODO: reschedule events
    throw UnimplementedError();
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

  void _done() {
    // TODO: is this logic right?
    if (_isDone) return;
    _isDone = true;
    if (_onDone == null) return;
    _dispatch(_onDone);
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
