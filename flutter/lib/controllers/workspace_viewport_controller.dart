import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Owns annotation viewport zoom, pan offset, and zoom-lock state.
class WorkspaceViewportController extends ChangeNotifier {
  double _zoom = 100;
  Offset _offset = Offset.zero;
  bool _zoomLocked = false;

  double get zoom => _zoom;
  Offset get offset => _offset;
  bool get zoomLocked => _zoomLocked;

  bool setZoom(double value) {
    if (_zoomLocked) {
      return false;
    }
    final next = value.clamp(25, 400).toDouble();
    if (next == _zoom) {
      return false;
    }
    _zoom = next;
    notifyListeners();
    return true;
  }

  bool adjustZoom(double delta) => setZoom(_zoom + delta);

  bool setOffset(Offset value) {
    if (_offset == value) {
      return false;
    }
    _offset = value;
    notifyListeners();
    return true;
  }

  bool reset() {
    if (_zoomLocked || (_zoom == 100 && _offset == Offset.zero)) {
      return false;
    }
    _zoom = 100;
    _offset = Offset.zero;
    notifyListeners();
    return true;
  }

  void forceReset() {
    if (_zoom == 100 && _offset == Offset.zero) {
      return;
    }
    _zoom = 100;
    _offset = Offset.zero;
    notifyListeners();
  }

  void toggleZoomLock() {
    _zoomLocked = !_zoomLocked;
    notifyListeners();
  }
}
