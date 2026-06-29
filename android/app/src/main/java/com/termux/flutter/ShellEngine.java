package com.termux.flutter;

import android.content.Context;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

public final class ShellEngine {
    public interface OutputListener {
        void onOutput(byte[] output);
        void onClosed(int exitCode);
    }

    private final OutputListener listener;
    private final BootstrapInstaller bootstrapInstaller;
    private PtyProcess ptyProcess;

    public ShellEngine(Context context, OutputListener listener) {
        this.listener = listener;
        bootstrapInstaller = new BootstrapInstaller(context);
    }

    public synchronized void start() throws IOException {
        if (isRunning()) return;

        bootstrapInstaller.ensureInstalled(listener);

        ptyProcess = new PtyProcess(listener);
        try {
            ptyProcess.start(bootstrapInstaller.buildCommand(), bootstrapInstaller.buildEnvironment());
        } catch (IOException | RuntimeException ptyFailure) {
            ptyProcess = null;
            throw new IOException("PTY startup failed; interactive pipe fallback is disabled", ptyFailure);
        }
    }

    public synchronized void write(String input) throws IOException {
        if (ptyProcess != null) {
            ptyProcess.write(input);
        }
    }

    public synchronized void resize(int cols, int rows) {
        if (ptyProcess != null) ptyProcess.resize(cols, rows);
    }

    public synchronized void resize(int cols, int rows, int cellWidth, int cellHeight) {
        if (ptyProcess != null) ptyProcess.resize(cols, rows, cellWidth, cellHeight);
    }

    public synchronized void sendSignal(int signal) throws IOException {
        if (ptyProcess != null) ptyProcess.sendSignal(signal);
    }

    public synchronized void stop() {
        if (ptyProcess != null) {
            ptyProcess.close();
            ptyProcess = null;
        }
    }

    private boolean isRunning() {
        return ptyProcess != null;
    }

    static byte[] utf8(String text) {
        return text.getBytes(StandardCharsets.UTF_8);
    }
}
