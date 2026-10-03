import 'dart:async';

import 'package:flutter/gestures.dart' show kLongPressTimeout;

/// Gap between repeats once a held key is auto-repeating. Backspace and the
/// arrow keys set the pace; anything else that repeats borrows it so every
/// held key feels the same.
const kKeyRepeatInterval = Duration(milliseconds: 40);

/// Auto-repeat for a held key: fires once on [press], then after the
/// long-press delay fires every [kKeyRepeatInterval] until [release].
class KeyRepeater {
  Timer? _delay;
  Timer? _repeat;

  void press(void Function() onFire) {
    release();
    onFire();
    _delay = Timer(kLongPressTimeout, () {
      _delay = null;
      onFire();
      _repeat = Timer.periodic(kKeyRepeatInterval, (_) => onFire());
    });
  }

  void release() {
    _delay?.cancel();
    _delay = null;
    _repeat?.cancel();
    _repeat = null;
  }

  void dispose() => release();
}
