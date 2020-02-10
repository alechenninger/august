part of 'august.dart';

class InteractionManager implements Sink<Interaction> {
  final _interactorsByModule = <String, Interactor>{};
  final Persistence _persistence;
  final Clock _clock;

  FastForwarder _ff;

  InteractionManager(
      this._clock, this._persistence, Iterable<Interactor> interactors) {
    _ff = FastForwarder(_clock);

    for (var interactor in interactors) {
      if (_interactorsByModule.containsKey(interactor.moduleName)) {
        throw ArgumentError.value(
            interactors,
            'interactors',
            'List of interactors contained multiple interactors for the same '
                'module name: ${interactor.moduleName}');
      }

      _interactorsByModule[interactor.moduleName] = interactor;
    }
  }

  Duration get currentOffset => _ff.currentOffset;

  @override
  void add(Interaction interaction) {
    _persistInteraction(interaction);
    _runInteraction(interaction);
  }

  @override
  void close() {}

  // TODO: We need a way to pause running timers, allow UI to pause
  void run(Function script) {
    if (_persistence.savedInteractions.isNotEmpty) {
      _ff.runFastForwardable((ff) {
        script();
        var saved = _persistence.savedInteractions;
        saved.forEach((interaction) {
          Future.delayed(interaction.offset, () {
            _runInteraction(interaction);
          });
        });
        ff.fastForward(saved.last.offset);
      });
    } else {
      script();
    }
  }

  void _persistInteraction(Interaction interaction) {
    _persistence.saveInteraction(currentOffset, interaction.moduleName,
        interaction.name, interaction.parameters);
  }

  void _runInteraction(Interaction interaction) {
    var interactor = _interactorsByModule[interaction.moduleName];

    if (interactor == null) {
      throw StateError('No interactor configured for module: '
          '${interaction.moduleName}. Include one when constructing an'
          'InteractionManager for this module.');
    }

    interactor.run(interaction.name, interaction.parameters);
  }
}

abstract class Interaction {
  String get moduleName;
  String get name;
  Map<String, dynamic> get parameters;
}

abstract class Interactor {
  /// The name of the module this interactor supports.
  String get moduleName;
  void run(String action, Map<String, dynamic> parameters);
}

Future<Null> delay({int minutes = 0, int seconds = 0, int milliseconds = 0}) {
  return Future.delayed(Duration(
      minutes: minutes, seconds: seconds, milliseconds: milliseconds));
}

class Interactable {
  final Sink<Interaction> _interactions;

  Interactable(this._interactions);

  void add(Interaction interaction) {
    _interactions.add(interaction);
  }
}

// Experimenting with generalization of an interaction that modules could reuse
// as component instead of reimplementing common capabilities (like visibility
// vs availability).
class Usable {
  Scope<Usable> _visible;
  Scope<Usable> _available;


}