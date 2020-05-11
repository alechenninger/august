// Copyright (c) 2015, Alec Henninger. All rights reserved. Use of this source

// is governed by a BSD-style license that can be found in the LICENSE file.

import 'package:august/src/scoped_object.dart';

import 'august.dart';
import 'input.dart';
import 'src/story.dart';
import 'src/scope.dart';
import 'src/persistence.dart';
import 'src/events.dart';

class Dialog extends Emitter {
  final _speech = ScopedEmitters<Speech, SpeechKey>();
  final GetScope _default;
  final Story _story;

  Dialog(this._story, {GetScope defaultScope = getAlways})
      : _default = defaultScope;

  Stream<Event> get events => _speech.events;

  // TODO: figure out defaults
  // TODO: markup should probably be a first class thing?
  //       as in: ui.text('...')
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
  Speech add(String markup,
      {String speaker, String target, Scope<dynamic> scope}) {
    scope = scope ?? _default();

    var speech = Speech(markup, scope, speaker, target, _story);

    _speech.add(speech, speech._scope,
        key: speech._key,
        onAvailable: () => SpeechAvailable.fromSpeech(speech),
        onUnavailable: () => SpeechUnavailable.fromSpeech(speech));

    return speech;
  }

  Voice voice({String name}) => Voice(name, this);
}

abstract class Speaks {
  Speech say(String markkup, {String target, Scope scope});
}

class Voice implements Speaks {
  String name;

  final Dialog _dialog;

  Voice(this.name, this._dialog);

  Speech say(String markup, {String target, Scope scope}) =>
      _dialog.add(markup, speaker: name, target: target, scope: scope);
}

class SpeechKey {
  final String markup;
  final String speaker;

  SpeechKey(this.markup, this.speaker);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpeechKey &&
          runtimeType == other.runtimeType &&
          markup == other.markup &&
          speaker == other.speaker;

  @override
  int get hashCode => markup.hashCode ^ speaker.hashCode;
}

class Speech extends Emitter {
  final String _markup;
  final Scope _scope;
  final String _speaker;
  final String _target;
  final Story _story;
  final SpeechKey _key;

  final _events = Events();
  Stream<Event> get events => _events.stream;

  final _replies = ScopedEmitters<Reply, String>();

  /// Lazily initialized scope which all replies share, making them mutually
  /// exclusive by default.
  // TODO: Support non mutually exclusive replies?
  CountScope _replyUses;

  // TODO: Support target / speaker of types other than String
  // Imagine thumbnails, for example
  // 'Displayable' type of some kind?
  Speech(this._markup, this._scope, this._speaker, this._target, this._story)
      : _key = SpeechKey(_markup, _speaker) {
    _events.includeEmitter(_replies);
  }

  Reply addReply(String markup, {Scope available = const Always()}) {
    _replyUses ??= CountScope(1);

    var reply = Reply(this, markup, _replyUses, available, _story);

    _replies.add(reply, reply.availability,
        key: reply._markup,
        onAvailable: () => ReplyAvailable(_key, markup),
        onUnavailable: () => ReplyUnavailable(_key, markup));

    return reply;
  }
}

class ReplyKey {
  final SpeechKey speech;
  final String markup;

  ReplyKey(this.speech, this.markup);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplyKey &&
          runtimeType == other.runtimeType &&
          speech == other.speech &&
          markup == other.markup;

  @override
  int get hashCode => speech.hashCode ^ markup.hashCode;
}

class Reply extends Emitter {
  final Speech speech;

  final String _markup;
  final ReplyKey _key;

  final CountScope uses;

  final Events<Replied> _onUse;

  Stream<Event> get events => onUse;
  Stream<Replied> get onUse => _onUse.stream;

  final Scope _available;

  Scope get availability => _available;

  bool get isAvailable => _available.isEntered;

  Reply(this.speech, this._markup, this.uses, Scope available, Story story)
      : _onUse = story.newEventStream(),
        _available = available.and(uses),
        _key = ReplyKey(speech._key, _markup);

  Future use() async {
    var e = await _onUse.event(() {
      if (!isAvailable) {
        throw ReplyNotAvailableException(this);
      }

      return Replied(this);
    });

    uses.increment();

    return e;
  }
}

class UseReply extends Action<Dialog> {
  final SpeechKey speech;
  final String reply;

  UseReply(this.speech, this.reply);

  void run(Dialog dialog) {
    var matchedSpeech = dialog._speech.available[speech];

    if (matchedSpeech == null) {
      throw StateError('No matching available speech found for reply: '
          '$parameters');
    }

    var matchedReply = matchedSpeech._replies.available[reply];

    if (matchedReply == null) {
      throw StateError('No matching available replies found for reply: '
          '$parameters');
    }

    matchedReply.use();
  }

  Map<String, dynamic> get parameters => {
        // TODO maybe represent objects by hash instead
        'speech': {'markup': speech.markup, 'speaker': speech.speaker},
        'markup': reply
      };
}

class ReplyNotAvailableException implements Exception {
  final Reply reply;

  ReplyNotAvailableException(this.reply);
}

class SpeechAvailable extends Event {
  final String speaker;
  final String markup;
  final String target;

  SpeechAvailable.fromSpeech(Speech s) : this(s._speaker, s._markup, s._target);

  SpeechAvailable(this.speaker, this.markup, this.target);
}

class SpeechUnavailable extends Event {
  final String speaker;
  final String markup;

  SpeechUnavailable.fromSpeech(Speech s): this(s._speaker, s._markup);

  SpeechUnavailable(this.speaker, this.markup);
}

class ReplyAvailable extends Event {
  final SpeechKey speech;
  final String markup;

  ReplyAvailable(this.speech, this.markup);
}

class ReplyUnavailable extends Event {
  final SpeechKey speech;
  final String markup;

  ReplyUnavailable(this.speech, this.markup);
}

class Replied extends Event {
  final Reply reply;

  Replied(this.reply);
}
