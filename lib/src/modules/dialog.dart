part of august.modules;

class DialogModule implements ModuleDefinition, HasInterface {
  final name = 'Dialog';

  Dialog create(Run run, Map modules) {
    return new Dialog(run);
  }

  DialogInterface createInterface(Dialog dialog, InterfaceEmit emit) {
    return new DialogInterface(dialog, emit);
  }

  DialogInterfaceHandler createInterfaceHandler(Dialog dialog) {
    return new DialogInterfaceHandler(dialog);
  }
}

class Dialog {
  final Run _run;

  Dialog(this._run);

  Future<DialogEvent> add(String dialog,
          {String from,
          String to,
          Duration delay: Duration.ZERO,
          Replies replies: const _NoReplies()}) =>
      _run.emit(new DialogEvent(dialog, from: from, to: to, replies: replies),
          delay: delay);

  Future<ReplyEvent> reply(String reply, DialogEvent dialogEvent) {
    if (dialogEvent.replies._used != null) {
      throw new StateError("Cannot reply to a dialog more than once; previous "
          "reply was ${dialogEvent.replies._used}.");
    }

    dialogEvent.replies._used = reply;

    return _run.emit(new ReplyEvent(reply, dialogEvent));
  }

  Future<NarrationEvent> narrate(String narration,
          {Duration delay: Duration.ZERO}) =>
      _run.emit(new NarrationEvent(narration), delay: delay);

  Future<ClearDialogEvent> clear() => _run.emit(new ClearDialogEvent());

  Future<DialogEvent> once({String dialog, String from, String to}) {
    var conditions = [];
    if (_notNull(dialog)) conditions.add((e) => e.dialog == dialog);
    if (_notNull(from)) conditions.add((e) => e.from = from);
    if (_notNull(to)) conditions.add((e) => e.to == to);
    return this.dialog.firstWhere((e) => conditions.every((c) => c(e)));
  }

  Future<ReplyEvent> onceReply(
      {String reply,
      String forDialog,
      String forDialogTo,
      String forDialogFrom}) {
    var conditions = [];

    if (_notNull(reply)) conditions.add((e) => e.reply == reply);
    if (_notNull(forDialog)) conditions
        .add((e) => e.dialogEvent.dialog == forDialog);
    if (_notNull(forDialogFrom)) conditions
        .add((e) => e.dialogEvent.to == forDialogTo);
    if (_notNull(forDialogFrom)) conditions
        .add((e) => e.dialogEvent.from == forDialogFrom);

    if (conditions.isEmpty) {
      throw new ArgumentError("Must pass at least one criteria for a reply.");
    }

    return replies.firstWhere((e) => conditions.every((c) => c(e)));
  }

  Stream<DialogEvent> get dialog => _run.every((e) => e is DialogEvent);

  Stream<ReplyEvent> get replies => _run.every((e) => e is ReplyEvent);

  Stream<NarrationEvent> get narration =>
      _run.every((e) => e is NarrationEvent);

  Stream<ClearDialogEvent> get clears =>
      _run.every((e) => e is ClearDialogEvent);
}

class DialogInterface {
  final Dialog _dialog;
  final InterfaceEmit _emit;

  Stream<DialogEvent> get dialog => _dialog.dialog;

  Stream<ReplyEvent> get replies => _dialog.replies;

  Stream<NarrationEvent> get narration => _dialog.narration;

  Stream<ClearDialogEvent> get clears => _dialog.clears;

  DialogInterface(this._dialog, this._emit);

  void reply(String reply, DialogEvent dialogEvent) {
    _emit('reply', {'reply': reply, 'dialogEvent': dialogEvent.toJson()});
  }
}

class DialogInterfaceHandler implements InterfaceHandler {
  final Dialog _dialog;

  DialogInterfaceHandler(this._dialog);

  void handle(String action, Map args) {
    switch (action) {
      case 'reply':
        _dialog.reply(
            args['reply'], new DialogEvent.fromJson(args['dialogEvent']));
    }
  }
}

class DialogEvent {
  final String alias;
  final String dialog;
  final String from;
  final String to;
  final Replies replies;

  DialogEvent(String dialog,
      {String from: "",
      String to: "",
      String alias,
      Replies replies: const _NoReplies()})
      : this.dialog = dialog,
        this.from = from,
        this.to = to,
        this.replies = replies,
        this.alias = alias == null
            ? "From: $from, To: $to, Dialog: $dialog, Replies: $replies"
            : alias;

  DialogEvent.fromJson(Map json)
      : alias = json['alias'],
        dialog = json['dialog'],
        from = json['from'],
        to = json['to'],
        replies = new Replies.fromJson(json['replies']);

  toString() => alias;

  Map toJson() => {
        'alias': alias,
        'dialog': dialog,
        'from': from,
        'to': to,
        'replies': replies.toJson()
      };
}

class Replies {
  final bool modal;
  final List<String> available;
  String _used;

  Replies(this.available, {this.modal: false});

  Replies.fromJson(Map json)
      : modal = json['modal'],
        available = json['replies'],
        _used = json['_used'];

  toString() => "Replies: $available, Modal: $modal";

  Map toJson() => {'modal': modal, 'replies': available, '_used': _used};
}

class NarrationEvent {
  final String alias;
  final String narration;

  NarrationEvent(String narration, {String alias})
      : this.narration = narration,
        this.alias = alias == null ? "Narration: $narration" : alias;

  toString() => alias;
}

class ClearDialogEvent {
  final String alias;

  ClearDialogEvent([this.alias = "Dialog clear"]);

  toString() => alias;
}

class ReplyEvent {
  final DialogEvent dialogEvent;
  final String reply;

  ReplyEvent(this.reply, this.dialogEvent);

  toString() => "Reply: $reply, dialog: $dialogEvent";
}

class _NoReplies implements Replies {
  final bool modal = false;
  final List<String> available = const [];
  String get _used => null;
  void set _used(_) {
    throw new UnsupportedError("");
  }

  const _NoReplies();

  toString() => "Replies: $available, Modal: $modal";

  Map toJson() => {'modal': modal, 'replies': available};
}

bool _notNull(String reply) => reply != null;
