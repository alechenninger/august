import 'package:august/august.dart';
import 'package:august/options.dart';
import 'package:test/test.dart';

main() {
  group("An Option", () {
    Option opt;

    setUp(() {
      opt = Option("");
    });

    test("is eventually available", () {
      expect(opt.availability.onEnter.first, completes);
    });

    group("when made available", () {
      test("enters availability scope", () {
        opt.available(const Always());
        expect(opt.availability.onEnter.first, completes);
      });

      test("is not immediately available", () {
        opt.available(const Always());
        expect(opt.isAvailable, isFalse);
      });

      test("is visibly available to availability listeners", () async {
        opt.available(const Always());
        await opt.availability.onEnter.first;
        expect(opt.isAvailable, isTrue);
      });

      test("emits availability same future as updating isAvailable", () async {
        opt.available(const Always());
        var order = [];
        var future = Future(
            () => order.add("future isAvailable: ${opt.isAvailable}"));
        opt.availability.onEnter.first.then(
            (e) => order.add("availability isAvailable: ${opt.isAvailable}"));

        await future;

        expect(
            order,
            equals([
              "availability isAvailable: true",
              "future isAvailable: true"
            ]));
      });

      group("via scope onEnter listener", () {
        SettableScope customScope;

        setUp(() {
          customScope = SettableScope.notEntered();
          opt.available(customScope);
        });

        test("is not immediately available", () {
          customScope.enter(null);
          expect(opt.isAvailable, isFalse);
        });

        test("emits availability in same future as updating isAvailable",
            () async {
          customScope.enter(null);
          var order = [];
          var future = Future(
              () => order.add("future isAvailable: ${opt.isAvailable}"));
          opt.availability.onEnter.first.then(
              (e) => order.add("availability isAvailable: ${opt.isAvailable}"));
          await future;

          expect(
              order,
              equals([
                "availability isAvailable: true",
                "future isAvailable: true"
              ]));
        });
      });
    });

    group("when used", () {
      setUp(() {
        opt.available(const Always());
        return opt.availability.onEnter.first;
      });

      test("is not immediately made unavailable", () {
        opt.use().catchError((_) {});
        expect(opt.isAvailable, isTrue);
      });

      test("cannot be used again", () async {
        opt.use().catchError((_) {});
        expect(opt.use(), throws);
      });

      test("completes with error if option is scheduled to be unavailable", () {
        opt.available(const Never());
        expect(opt.use(), throws);
      });

      test("completes with error if option is already unavailable", () async {
        opt.available(const Never());
        await opt.availability.onExit.first;
        expect(opt.use(), throws);
      });

      test("fires use listeners", () {
        var listener = opt.onUse.first;
        opt.use();
        expect(listener, completes);
      });

      test("does not fire use listeners if not available to be used", () async {
        opt.available(const Never());
        await opt.availability.onExit.first;
        var listener = opt.onUse.first;
        opt.use().catchError((e) {});
        expect(listener.timeout(const Duration(milliseconds: 250)), throws);
      });
    });
  }, timeout: const Timeout(const Duration(milliseconds: 500)));
}
