import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

class ShellBridge {
  static const MethodChannel _methods = MethodChannel('com.termux.flutter/shell');
  static const EventChannel _events = EventChannel('com.termux.flutter/output');

  Stream<String>? _output;

  Stream<String> get output {
    _output ??= _events
        .receiveBroadcastStream()
        .map(_eventToBytes)
        .transform(utf8.decoder);
    return _output!;
  }

  Future<void> startShell() => _methods.invokeMethod<void>('startShell');

  Future<void> stopShell() => _methods.invokeMethod<void>('stopShell');

  Future<void> writeInput(String input) =>
      _methods.invokeMethod<void>('writeInput', <String, String>{'input': input});

  Future<void> resizePty(
    int cols,
    int rows, {
    int cellWidth = 8,
    int cellHeight = 16,
  }) =>
      _methods.invokeMethod<void>(
        'resizePty',
        <String, int>{
          'cols': cols,
          'rows': rows,
          'cellWidth': cellWidth,
          'cellHeight': cellHeight,
        },
      );

  Future<void> sendSignal(int signal) =>
      _methods.invokeMethod<void>('sendSignal', <String, int>{'signal': signal});

  List<int> _eventToBytes(Object? event) {
    if (event is Uint8List) return event;
    if (event is ByteData) return event.buffer.asUint8List(event.offsetInBytes, event.lengthInBytes);
    if (event is List<int>) return Uint8List.fromList(event);
    return utf8.encode(event?.toString() ?? '');
  }
}
