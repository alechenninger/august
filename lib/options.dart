// Copyright (c) 2015, Alec Henninger. All rights reserved. Use of this source
// is governed by a BSD-style license that can be found in the LICENSE file.

import 'august.dart';
import 'input.dart';
import 'src/events.dart';
import 'src/scope.dart';
import 'src/persistence.dart';

class Options {
  final _availableOptCtrl = StreamController<Option>(sync: true);
  final _options = <Option>[];
  final GetScope _default;

  Options({GetScope defaultScope = getAlways}) : _default = defaultScope;

  Stream<Option> get _onOptionAvailable => _availableOptCtrl.stream;

  Option oneTime(String text, {Scope available, CountScope exclusiveWith}) {
    return limitedUse(text,
        available: available,
        exclusiveWith: exclusiveWith?.withRemaining(1) ?? CountScope(1));
  }

  /// Creates a new limited use option that can be used while [available] and
  /// has remaining uses determined by [exclusiveWith].
  Option limitedUse(String text, {Scope available, CountScope exclusiveWith}) {
    var option = Option._(text,
        uses: exclusiveWith ?? CountScope(1),
        available: available ?? _default());

    _options.addWhile(option, option.availability);

    option
      ..availability.onEnter.listen((e) {
        _options.add(option);
        _availableOptCtrl.add(option);
      })
      ..availability.onExit.listen((e) {
        _options.remove(option);
      });

    if (option.isAvailable) {
      _options.add(option);
      scheduleMicrotask(() => _availableOptCtrl.add(option));
    }

    return option;
  }
}

class Option {
  final String text;

  int get maxUses => uses.max;
  int get useCount => uses.count;

  Scope _available;

  bool get isAvailable => _available.isEntered;

  /// A scope that is entered whenever this option is available.
  Scope get availability => _available;

  // TODO: Consider simply Stream<Option>
  Stream<OptionUsed> get onUse => _onUse.stream;

  final CountScope uses;
  final _onUse = Events<OptionUsed>();

  Option._(this.text, {CountScope uses, Scope available = always})
      : uses = uses ?? CountScope(1) {
    _available = available.and(this.uses);
  }

  /// Schedules option to be used at the end of the current event queue.
  ///
  /// The return future completes with success when the option is used and all
  /// listeners receive it. It completes with an error if the option is not
  /// available to be used.
  Future<OptionUsed> use() async {
    // Wait to check isAvailable until option actually about to be used
    var e = await _onUse.event(() {
      if (!isAvailable) {
        throw OptionNotAvailableException(this);
      }

      return OptionUsed(this);
    });

    // This could be left out of a core implementation, and "uses" could be
    // implemented as an extension by listening to the use() and a modified
    // availability scope, as is done here.
    uses.increment();

    return e;
  }

  String toString() => 'Option{'
      "text='$text',"
      'allowedUseCount=$maxUses,'
      'useCount=$useCount'
      '}';
}

class OptionsUi {
  final Stream<Event> _events;
  final Sink<Action> _interactions;

  OptionsUi(this._events, this._interactions);

  Stream<UiOption> get onOptionAvailable => null; // TODO
}


class UiOption {
  final Option _option;
  final Sink<Action> _interactions;

  String get text => _option.text;

  UiOption(this._interactions, this._option);

  void use() {
    _interactions.add(_UseOption(_option));
  }

  Stream<UiOption> get onUse => _option.onUse.map((e) => this);

  Stream<UiOption> get onUnavailable =>
      _option.availability.onExit.map((e) => this);
}

class _UseOption implements Action<Options> {
  final String moduleName = '$Options';
  final String name = '$_UseOption';
  final Map<String, dynamic> parameters;

  _UseOption(Option option): parameters = {'text': option.text };

  void run(Options options) {
    if (!parameters.containsKey('text')) {
      throw ArgumentError.value(
          parameters,
          'parameters',
          'Expected json to contain '
              '"text" field.');
    }

    var text = parameters['text'];
    var found =
        options._options.firstWhere((o) => o.text == text, orElse: () => null);

    if (found == null) {
      throw StateError('No option found from text "$text".');
    }

    found.use();
  }
}

class OptionUsed extends Event {
  final Option option;

  OptionUsed(this.option);
}

// Not sure if this should be error or exception
// Depends on context, so probably exception
class OptionNotAvailableException implements Exception {
  final Option option;

  OptionNotAvailableException(this.option);
}
