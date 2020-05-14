// Copyright (c) 2015, Alec Henninger. All rights reserved. Use of this source

// is governed by a BSD-style license that can be found in the LICENSE file.

library august.dialog;

import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';
import 'package:meta/meta.dart';

import 'august.dart';
import 'modules.dart';

part 'dialog.g.dart';

@SerializersFor([
  UseReply,
  ReplyKey,
  ReplyAvailable,
  ReplyUnavailable,
  SpeechKey,
  SpeechAvailable,
  SpeechUnavailable
])
final Serializers dialogSerializers = _$dialogSerializers;

class Dialog extends StoryModule {
  final _speech = StoryElements<Speech, SpeechKey>();
  final GetScope _default;

  Dialog({GetScope defaultScope = getAlways}) : _default = defaultScope;

  Serializers get serializers => dialogSerializers;
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

    var speech = Speech(markup, scope, speaker, target);

    _speech.add(speech, speech._scope,
        key: speech._key,
        onAvailable: () => SpeechAvailable.fromSpeech(speech),
        onUnavailable: () => SpeechUnavailable.fromSpeech(speech));

    return speech;
  }

  Voice voice({String name}) => Voice(name, this);
}

abstract class Speaks {
  Speech say(String markup, {String target, Scope scope});
}

class Voice implements Speaks {
  String name;

  final Dialog _dialog;

  Voice(this.name, this._dialog);

  Speech say(String markup, {String target, Scope scope}) =>
      _dialog.add(markup, speaker: name, target: target, scope: scope);
}

abstract class SpeechKey implements Built<SpeechKey, SpeechKeyBuilder> {
  static Serializer<SpeechKey> get serializer => _$speechKeySerializer;

  String get markup;
  @nullable
  String get speaker;

  factory SpeechKey({@required String markup, String speaker}) =>
      _$SpeechKey._(markup: markup, speaker: speaker);
  SpeechKey._();
}

class Speech extends StoryElement {
  final String _markup;
  final Scope _scope;
  final String _speaker;
  final String _target;
  final SpeechKey _key;

  final _events = Events();
  Stream<Event> get events => _events.stream;

  final _replies = StoryElements<Reply, String>();

  /// Lazily initialized scope which all replies share, making them mutually
  /// exclusive by default.
  // TODO: Support non mutually exclusive replies?
  CountScope _replyUses;

  // TODO: Support target / speaker of types other than String
  // Imagine thumbnails, for example
  // 'Displayable' type of some kind?
  Speech(this._markup, this._scope, this._speaker, this._target)
      : _key = SpeechKey(speaker: _speaker, markup: _markup) {
    _events.includeEmitter(_replies);
  }

  Reply addReply(String markup, {Scope available = const Always()}) {
    _replyUses ??= CountScope(1);

    var reply = Reply(this, markup, _replyUses, available);

    _replies.add(reply, reply.availability,
        key: reply._markup,
        onAvailable: () => ReplyAvailable(_key, markup),
        onUnavailable: () => ReplyUnavailable(reply._key));

    return reply;
  }
}

abstract class ReplyKey implements Built<ReplyKey, ReplyKeyBuilder> {
  static Serializer<ReplyKey> get serializer => _$replyKeySerializer;
  SpeechKey get speech;
  String get markup;

  factory ReplyKey(SpeechKey speech, String markup) =>
      _$ReplyKey._(speech: speech, markup: markup);
  ReplyKey._();
}

class Reply extends StoryElement {
  final Speech speech;

  final String _markup;
  final ReplyKey _key;

  final CountScope uses;

  final Events<Replied> _onUse = Events<Replied>();

  Stream<Event> get events => onUse;
  Stream<Replied> get onUse => _onUse.stream;

  final Scope _available;

  Scope get availability => _available;

  bool get isAvailable => _available.isEntered;

  Reply(this.speech, this._markup, this.uses, Scope available)
      : _available = available.and(uses),
        _key = ReplyKey(speech._key, _markup);

  Future use() async {
    var e = await _onUse.event(() {
      if (!isAvailable) {
        throw ReplyNotAvailableException(this);
      }

      return Replied(_key);
    });

    uses.increment();

    return e;
  }
}

abstract class UseReply
    with Action<Dialog>
    implements Built<UseReply, UseReplyBuilder> {
  static Serializer<UseReply> get serializer => _$useReplySerializer;

  ReplyKey get reply;

  factory UseReply(ReplyKey key) => _$UseReply._(reply: key);
  UseReply._();

  void run(Dialog dialog) {
    var matchedSpeech = dialog._speech.available[reply.speech];

    if (matchedSpeech == null) {
      throw StateError('No matching available speech found for reply: '
          '${reply.speech}');
    }

    var matchedReply = matchedSpeech._replies.available[reply];

    if (matchedReply == null) {
      throw StateError('No matching available replies found for reply: '
          '$reply');
    }

    matchedReply.use();
  }
}

class ReplyNotAvailableException implements Exception {
  final Reply reply;

  ReplyNotAvailableException(this.reply);
}

abstract class SpeechAvailable
    with Event
    implements Built<SpeechAvailable, SpeechAvailableBuilder> {
  static Serializer<SpeechAvailable> get serializer =>
      _$speechAvailableSerializer;
  String get speaker;
  String get markup;
  String get target;
  SpeechKey get key => SpeechKey(markup: markup, speaker: speaker);

  factory SpeechAvailable.fromSpeech(Speech s) =>
      SpeechAvailable(s._speaker, s._markup, s._target);

  factory SpeechAvailable(String speaker, String markup, String target) =>
      _$SpeechAvailable._(speaker: speaker, markup: markup, target: target);
  SpeechAvailable._();
}

abstract class SpeechUnavailable
    with Event
    implements Built<SpeechUnavailable, SpeechUnavailableBuilder> {
  static Serializer<SpeechUnavailable> get serializer =>
      _$speechUnavailableSerializer;

  SpeechKey get key;

  factory SpeechUnavailable.fromSpeech(Speech s) => SpeechUnavailable(s._key);
  factory SpeechUnavailable(SpeechKey key) => _$SpeechUnavailable._(key: key);
  SpeechUnavailable._();
}

abstract class ReplyAvailable
    with Event
    implements Built<ReplyAvailable, ReplyAvailableBuilder> {
  static Serializer<ReplyAvailable> get serializer =>
      _$replyAvailableSerializer;
  SpeechKey get speech;
  String get markup;
  ReplyKey get key => ReplyKey(speech, markup);

  factory ReplyAvailable(SpeechKey speech, String markup) =>
      _$ReplyAvailable._(speech: speech, markup: markup);
  ReplyAvailable._();
}

abstract class ReplyUnavailable
    with Event
    implements Built<ReplyUnavailable, ReplyUnavailableBuilder> {
  static Serializer<ReplyUnavailable> get serializer =>
      _$replyUnavailableSerializer;

  ReplyKey get reply;

  factory ReplyUnavailable(ReplyKey key) => _$ReplyUnavailable._(reply: key);
  ReplyUnavailable._();
}

abstract class Replied with Event implements Built<Replied, RepliedBuilder> {
  static Serializer<Replied> get serializer => _$repliedSerializer;

  ReplyKey get reply;

  factory Replied(ReplyKey reply) => _$Replied._(reply: reply);
  Replied._();
}
