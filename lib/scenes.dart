import 'package:august/august.dart';

class Scenes {
  final _newScenes = new StreamController<Scene>.broadcast(sync: true);

  /// Creates a new scene which will enter at most once.
  Scene oneTime({String title}) => new _OneTimeScene(this);

  ReenterableScene reenterable({String title}) => new ReenterableScene._(this);

  Stream<Scene> get onBegin => _newScenes.stream;
}

abstract class Scene<T extends Scene> extends Scope {
  Future<Scene> enter();
}

class _OneTimeScene extends Scene {
  final _scope = new SettableScope<Scene>.notEntered();
  final Scenes _scenes;

  _OneTimeScene(this._scenes);

  Future<Scene> enter() async {
    _scope.enter(this);
    _scenes._newScenes.add(this);
    _scenes.onBegin.first.then((_) {
      _scope.exit(this);
      _scope.close();
    });
    return this;
  }

  @override
  bool get isEntered => _scope.isEntered;

  @override
  Stream get onEnter => _scope.onEnter;

  @override
  Stream get onExit => _scope.onExit;
}

class ReenterableScene extends Scene<ReenterableScene> {
  final Scenes _scenes;
  final _scope = new SettableScope<ReenterableScene>.entered();
  var _isDone = false;

  ReenterableScene._(this._scenes) {
    _scenes.onBegin.listen((scene) {
      if (scene == this) {
        return;
      }

      if (_scope.isNotClosed) {
        _scope.exit(this);

        if (_isDone) {
          _scope.close();
        }
      }
    });
  }

  void done() {
    _isDone = true;
    if (_scope.isNotEntered) {
      _scope.close();
    }
  }

  /// Fails if the scene is already [done].
  @override
  Future<ReenterableScene> enter() async {
    if (_isDone) {
      throw new StateError("Reenterable scene is done; cannot reenter.");
    }

    _scope.enter(this);
    _scenes._newScenes.add(this);

    return this;
  }

  @override
  bool get isEntered => _scope.isEntered;

  @override
  Stream<ReenterableScene> get onEnter => _scope.onEnter;

  @override
  Stream<ReenterableScene> get onExit => _scope.onExit;
}
