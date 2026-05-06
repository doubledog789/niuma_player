import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/presentation/core/pip_lifecycle_observer.dart';

void main() {
  test('inactive + shouldEnter()=true → enter() 调一次', () {
    var enterCalled = 0;
    final obs = PipLifecycleObserver(
      shouldEnter: () => true,
      enter: () async {
        enterCalled++;
        return true;
      },
    );
    obs.didChangeAppLifecycleState(AppLifecycleState.inactive);
    expect(enterCalled, 1);
  });

  test('inactive + shouldEnter()=false → enter() 不调', () {
    var enterCalled = 0;
    final obs = PipLifecycleObserver(
      shouldEnter: () => false,
      enter: () async {
        enterCalled++;
        return true;
      },
    );
    obs.didChangeAppLifecycleState(AppLifecycleState.inactive);
    expect(enterCalled, 0);
  });

  test('resumed → 不调', () {
    var enterCalled = 0;
    final obs = PipLifecycleObserver(
      shouldEnter: () => true,
      enter: () async {
        enterCalled++;
        return true;
      },
    );
    obs.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(enterCalled, 0);
  });

  test('paused → 不调（仅 inactive 触发）', () {
    var enterCalled = 0;
    final obs = PipLifecycleObserver(
      shouldEnter: () => true,
      enter: () async {
        enterCalled++;
        return true;
      },
    );
    obs.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(enterCalled, 0);
  });

  test('detached → 不调', () {
    var enterCalled = 0;
    final obs = PipLifecycleObserver(
      shouldEnter: () => true,
      enter: () async {
        enterCalled++;
        return true;
      },
    );
    obs.didChangeAppLifecycleState(AppLifecycleState.detached);
    expect(enterCalled, 0);
  });

  test('hidden → 不调', () {
    var enterCalled = 0;
    final obs = PipLifecycleObserver(
      shouldEnter: () => true,
      enter: () async {
        enterCalled++;
        return true;
      },
    );
    obs.didChangeAppLifecycleState(AppLifecycleState.hidden);
    expect(enterCalled, 0);
  });
}
