// Copyright (c) 2015, Alec Henninger. All rights reserved. Use of this source

// is governed by a BSD-style license that can be found in the LICENSE file.

import 'package:august/august.dart';

typedef GetScope = Scope Function();

Scope _getAlways() {
  return always;
}

class Dialog {
  final _addSpeechCtrl = StreamController<Speech>.broadcast(sync: true);
  final _speech = <Speech>[];
  final GetScope _default;

  Dialog({GetScope defaultScope = _getAlways}) : this._default = defaultScope;

  // TODO: figure out defaults
  // TODO: markup should probably be a first class thing?
  //       as in: ui.text("...")
  //       - This allows markup to be up to UI implementation
  //       - UI can also then handle localization
  //       - UI can handle complex elements (say if we want a portrait, or
  //         presentation control like alignment, style, or effects, etc.)
  //       - We'd like scripts to be decoupled from UI implementation, but
  //         interfaces can satisfy this concern.
  //       - On the other hand, we could consider markup to be Dialog specific
  //         here, not UI specific. Then UI decides what to do with the module.
  //         I guess this is what the current architecture is.
  Speech narrate(String markup, {Scope scope}) {
    return add(markup, scope: scope);
  }

  // TODO: figure out default
  //  This might be figured out now...
  Speech add(String markup, {String speaker, String target, Scope<dynamic> scope}) {
    scope = scope ?? _default();

    var speech = Speech(markup, scope, speaker, target);

    scope.onEnter.listen((_) {
      _speech.add(speech);
      _addSpeechCtrl.add(speech);
    });

    scope.onExit.listen((_) {
      _speech.remove(speech);
    });

    if (scope.isEntered) {
      _speech.add(speech);
      _addSpeechCtrl.add(speech);
    }

    return speech;
  }

  Voice voice({String name}) => Voice(name, this);

  Stream<Speech> get _onAddSpeech => _addSpeechCtrl.stream;
}

class Voice {
  String name;

  final Dialog _dialog;

  Voice(this.name, this._dialog);

  Speech say(String markup, {String target, Scope scope}) =>
      _dialog.add(markup, speaker: name, target: target, scope: scope);
}

class Speech {
  final String _markup;
  final Scope _scope;
  final String _speaker;
  final String _target;

  final _replies = <Reply>[];
  final _addReplyCtrl = StreamController<Reply>.broadcast(sync: true);

  /// Lazily initialized scope which all replies share, making them mutually
  /// exclusive by default.
  // TODO: Support non mutually exclusive replies?
  _CountScope _replyUses;

  // TODO: Support target / speaker of types other than String
  // Imagine thumbnails, for example
  // 'Displayable' type of some kind?
  Speech(this._markup, this._scope, this._speaker, this._target);

  Reply addReply(String markup, {Scope scope = const Always()}) {
    if (_replyUses == null) {
      // TODO parameterize max?
      _replyUses = _CountScope(1);
    }

    var reply = Reply(this, markup, _replyUses, scope);

    reply.availability
      ..onEnter.listen((_) {
        _replies.add(reply);
        _addReplyCtrl.add(reply);
      })
      ..onExit.listen((_) {
        _replies.remove(reply);
      });

    if (reply.isAvailable) {
      _replies.add(reply);
      _addReplyCtrl.add(reply);
    }

    return reply;
  }

  Stream<Speech> get _onRemove => _scope.onExit.map((_) => this);

  Stream<Reply> get _onReplyAvailable => _addReplyCtrl.stream;
}

class Reply {
  final Speech speech;

  final String _markup;
  final _CountScope _hasUses;

  final _uses = StreamController<dynamic>.broadcast(sync: true);

  Stream get onUse => _uses.stream;

  ScopeAsValue _available;

  Scope<StateChangeEvent<bool>> get availability => _available.asScope;

  bool get isAvailable => _available.observed.value;

  bool get willBeAvailable => _available.observed.nextValue;

  Reply(this.speech, this._markup, this._hasUses, Scope scope) {
    _available = ScopeAsValue(owner: this)
      ..within(AndScope(_hasUses, scope));
  }

  Future use() {
    if (_available.observed.nextValue == false) {
      return Future.error(ReplyNotAvailableException(this));
    }

    _hasUses.increment();

    return Future(() {
      var event = UseReplyEvent(this);
      _uses.add(event);
      return event;
    });
  }
}

class DialogUi {
  final Dialog _dialog;
  final Sink<Interaction> _interactions;

  DialogUi(this._dialog, this._interactions);

  Stream<UiSpeech> get onAdd =>
      _dialog._onAddSpeech.map((d) => UiSpeech(d, _interactions));
}

/*
need a stream of json -> persist
need to read json -> pick a specific action and use it

ui.action("
 */

class DialogInteractor extends Interactor {
  static const _moduleName = "Dialog";

  final moduleName = _moduleName;
  final Dialog _dialog;

  DialogInteractor(this._dialog);

  void run(String action, Map<String, dynamic> parameters) {
    switch (action) {
      case _UseReplyAction._name:
        _UseReplyAction.run(parameters, _dialog);
        break;
      default:
        throw UnsupportedError("Unsupported action $action");
    }
  }
}

class UiSpeech {
  final Speech _speech;
  final Sink<Interaction> _interactions;

  UiSpeech(this._speech, this._interactions);

  String get markup => _speech._markup;

  String get speaker => _speech._speaker;

  String get target => _speech._target;

  Stream<UiSpeech> get onRemove => _speech._onRemove.map((_) => this);

  Stream<UiReply> get onReplyAvailable =>
      _speech._onReplyAvailable.map((r) => UiReply(r, _interactions));
}

class UiReply {
  final Reply _reply;
  final Sink<Interaction> _interactions;

  UiReply(this._reply, this._interactions);

  String get markup => _reply._markup;

  Stream<UiReply> get onRemove => _reply.availability.onExit.map((_) => this);

  void use() {
    _interactions.add(new _UseReplyAction(_reply));
  }
}

class _UseReplyAction implements Interaction {
  static const _name = 'UseReply';

  final Reply _reply;

  _UseReplyAction(this._reply);

  static void run(Map<String, dynamic> parameters, Dialog dialog) {
    var matchingSpeech = dialog._speech
        .where((s) => s._markup == parameters['speech']['markup']);

    if (matchingSpeech.isEmpty) {
      throw StateError("No matching available speech found for reply: "
          "$parameters");
    }

    if (matchingSpeech.length > 1) {
      throw StateError("Multiple matching available speech found for "
          "reply: $parameters");
    }

    var matchingReplies = matchingSpeech.first._replies
        .where((r) => r._markup == parameters['markup']);

    if (matchingReplies.isEmpty) {
      throw StateError("No matching available replies found for reply: "
          "$parameters");
    }

    if (matchingReplies.length > 1) {
      throw StateError("Multiple matching available replies found for "
          "reply: $parameters");
    }

    matchingReplies.first.use();
  }

  final moduleName = DialogInteractor._moduleName;
  final name = _name;

  Map<String, dynamic> get parameters => {
        // TODO maybe represent objects by hash instead
        'speech': {'markup': _reply.speech._markup},
        'markup': _reply._markup
      };
}

class ReplyNotAvailableException implements Exception {
  final Reply reply;

  ReplyNotAvailableException(this.reply);
}

class UseReplyEvent {
  final Reply reply;

  UseReplyEvent(this.reply);
}

// A simple scope that is entered until incremented a maximum number of times.
// TODO: consider generalizing this a bit to be able to produce scopes off of
// various counts which all share the same counter
class _CountScope extends Scope<int> {
  final int max;

  var _current = 0;

  int get current => _current;

  final SettableScope<int> _scope;

  bool get isEntered => _scope.isEntered;

  Stream<int> get onEnter => _scope.onEnter;

  Stream<int> get onExit => _scope.onExit;

  _CountScope(int max)
      : this.max = max,
        _scope = max > 0
            ? SettableScope<int>.entered()
            : SettableScope<int>.notEntered();

  void increment() {
    if (_current == max) {
      throw StateError("Max of $max already met, cannot increment.");
    }

    _current++;

    if (_current == max) {
      _scope.exit(_current);
      _scope.close();
    }
  }
}
