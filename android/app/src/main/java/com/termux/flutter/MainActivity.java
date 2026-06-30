package com.termux.flutter;

import android.os.Handler;
import android.os.Looper;
import android.os.Build;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private static final String METHOD_CHANNEL = "com.termux.flutter/shell";
    private static final String EVENT_CHANNEL = "com.termux.flutter/output";

    private ShellEngine shellEngine;
    private EventChannel.EventSink eventSink;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            disableMouseCursorChannel(flutterEngine);
        }

        shellEngine = new ShellEngine(this, new ShellEngine.OutputListener() {
            @Override
            public void onOutput(final byte[] output) {
                mainHandler.post(new Runnable() {
                    @Override
                    public void run() {
                        if (eventSink != null) eventSink.success(output);
                    }
                });
            }

            @Override
            public void onClosed(final int exitCode) {
                mainHandler.post(new Runnable() {
                    @Override
                    public void run() {
                        if (eventSink != null) eventSink.success(ShellEngine.utf8("\r\n[process exited " + exitCode + "]\r\n"));
                    }
                });
            }
        });

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), METHOD_CHANNEL)
            .setMethodCallHandler(new MethodChannel.MethodCallHandler() {
                @Override
                public void onMethodCall(MethodCall call, MethodChannel.Result result) {
                    try {
                        if ("startShell".equals(call.method)) {
                            shellEngine.start();
                            result.success(null);
                        } else if ("writeInput".equals(call.method)) {
                            String input = call.argument("input");
                            shellEngine.write(input == null ? "" : input);
                            result.success(null);
                        } else if ("resizePty".equals(call.method)) {
                            Integer cols = call.argument("cols");
                            Integer rows = call.argument("rows");
                            Integer cellWidth = call.argument("cellWidth");
                            Integer cellHeight = call.argument("cellHeight");
                            shellEngine.resize(
                                cols == null ? 80 : cols,
                                rows == null ? 24 : rows,
                                cellWidth == null ? 8 : cellWidth,
                                cellHeight == null ? 16 : cellHeight
                            );
                            result.success(null);
                        } else if ("sendSignal".equals(call.method)) {
                            Integer signal = call.argument("signal");
                            shellEngine.sendSignal(signal == null ? PtyProcess.SIGNAL_INT : signal);
                            result.success(null);
                        } else if ("stopShell".equals(call.method)) {
                            shellEngine.stop();
                            result.success(null);
                        } else {
                            result.notImplemented();
                        }
                    } catch (Throwable t) {
                        if (eventSink != null) {
                            eventSink.success(ShellEngine.utf8(
                                "\r\n[shell error] " + t.getMessage() + "\r\n"
                            ));
                        }
                        result.error("shell_error", t.getMessage(), null);
                    }
                }
            });

        new EventChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), EVENT_CHANNEL)
            .setStreamHandler(new EventChannel.StreamHandler() {
                @Override
                public void onListen(Object arguments, EventChannel.EventSink events) {
                    eventSink = events;
                }

                @Override
                public void onCancel(Object arguments) {
                    eventSink = null;
                }
            });
    }

    private void disableMouseCursorChannel(FlutterEngine flutterEngine) {
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), "flutter/mousecursor")
            .setMethodCallHandler(new MethodChannel.MethodCallHandler() {
                @Override
                public void onMethodCall(MethodCall call, MethodChannel.Result result) {
                    if ("activateSystemCursor".equals(call.method)) {
                        result.success(null);
                    } else {
                        result.notImplemented();
                    }
                }
            });
    }

    @Override
    protected void onDestroy() {
        if (shellEngine != null) shellEngine.stop();
        super.onDestroy();
    }
}
