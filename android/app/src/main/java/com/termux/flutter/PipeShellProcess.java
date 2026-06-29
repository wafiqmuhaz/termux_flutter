package com.termux.flutter;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

final class PipeShellProcess {
    private final ShellEngine.OutputListener listener;
    private Process process;
    private OutputStream stdin;

    PipeShellProcess(ShellEngine.OutputListener listener) {
        this.listener = listener;
    }

    void start(String[] command, String[] environment) throws IOException {
        ProcessBuilder builder = new ProcessBuilder(command);
        builder.environment().clear();
        for (String entry : environment) {
            int separator = entry.indexOf('=');
            if (separator > 0) {
                builder.environment().put(entry.substring(0, separator), entry.substring(separator + 1));
            }
        }
        builder.redirectErrorStream(true);
        process = builder.start();
        stdin = process.getOutputStream();
        startReader(process.getInputStream());
    }

    void write(String input) throws IOException {
        if (stdin == null) return;
        stdin.write(input.getBytes("UTF-8"));
        stdin.flush();
    }

    void close() {
        if (process != null) process.destroy();
    }

    private void startReader(final InputStream stream) {
        Thread thread = new Thread(new Runnable() {
            @Override
            public void run() {
                byte[] buffer = new byte[4096];
                int exitCode = -1;
                try {
                    int count;
                    while ((count = stream.read(buffer)) >= 0) {
                        if (count > 0) listener.onOutput(java.util.Arrays.copyOf(buffer, count));
                    }
                    exitCode = process.waitFor();
                } catch (Throwable ignored) {
                    exitCode = -1;
                }
                listener.onClosed(exitCode);
            }
        }, "pipe-shell-reader");
        thread.setDaemon(true);
        thread.start();
    }
}
