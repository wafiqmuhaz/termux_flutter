package com.termux.flutter;

import java.io.IOException;
import java.util.Arrays;

public final class PtyProcess {
    public static final int SIGNAL_HUP = 1;
    public static final int SIGNAL_INT = 2;
    public static final int SIGNAL_TERM = 15;
    public static final int SIGNAL_KILL = 9;

    static {
        System.loadLibrary("termux_flutter_pty");
    }

    private final ShellEngine.OutputListener listener;
    private int masterFd = -1;
    private int childPid = -1;
    private volatile boolean closed;
    private int cols = 80;
    private int rows = 24;
    private int cellWidth = 8;
    private int cellHeight = 16;

    public PtyProcess(ShellEngine.OutputListener listener) {
        this.listener = listener;
    }

    public void start(String[] command, String[] environment) throws IOException {
        int[] result = nativeStart(command, environment, cols, rows, cellWidth, cellHeight);
        masterFd = result[0];
        childPid = result[1];
        startReader();
    }

    public void write(String input) throws IOException {
        if (closed || masterFd < 0) return;
        byte[] bytes = input.getBytes("UTF-8");
        int written = nativeWrite(masterFd, bytes, bytes.length);
        if (written < 0) throw new IOException("PTY write failed");
    }

    public void resize(int cols, int rows) {
        resize(cols, rows, cellWidth, cellHeight);
    }

    public void resize(int cols, int rows, int cellWidth, int cellHeight) {
        this.cols = cols;
        this.rows = rows;
        this.cellWidth = Math.max(1, cellWidth);
        this.cellHeight = Math.max(1, cellHeight);
        if (!closed && masterFd >= 0) {
            nativeResize(masterFd, cols, rows, this.cellWidth, this.cellHeight);
        }
    }

    public void sendSignal(int signal) throws IOException {
        if (closed || childPid <= 0) return;
        int result = nativeSendSignal(childPid, signal);
        if (result < 0) throw new IOException("PTY signal failed: " + signal);
    }

    public void close() {
        closed = true;
        if (childPid > 0) nativeSendSignal(childPid, SIGNAL_TERM);
        if (masterFd >= 0) nativeClose(masterFd);
        masterFd = -1;
        childPid = -1;
    }

    int[] getWindowSizeForTesting() {
        if (masterFd < 0) return null;
        return nativeGetWindowSize(masterFd);
    }

    String describeMasterFdForTesting() {
        if (masterFd < 0) return null;
        return nativeDebugDescribeFd(masterFd);
    }

    int getChildPidForTesting() {
        return childPid;
    }

    private void startReader() {
        Thread thread = new Thread(new Runnable() {
            @Override
            public void run() {
                byte[] buffer = new byte[4096];
                while (!closed && masterFd >= 0) {
                    int count = nativeRead(masterFd, buffer, buffer.length);
                    if (count <= 0) break;
                    try {
                        listener.onOutput(Arrays.copyOf(buffer, count));
                    } catch (Throwable ignored) {
                        break;
                    }
                }
                int status = childPid > 0 ? nativeWait(childPid) : -1;
                listener.onClosed(status);
            }
        }, "pty-shell-reader");
        thread.setDaemon(true);
        thread.start();
    }

    private static native int[] nativeStart(String[] command, String[] env, int cols, int rows, int cellWidth, int cellHeight) throws IOException;
    private static native int nativeRead(int fd, byte[] buffer, int length);
    private static native int nativeWrite(int fd, byte[] buffer, int length);
    private static native int nativeResize(int fd, int cols, int rows, int cellWidth, int cellHeight);
    private static native int[] nativeGetWindowSize(int fd);
    private static native String nativeDebugDescribeFd(int fd);
    private static native int nativeClose(int fd);
    private static native int nativeSendSignal(int pid, int signal);
    private static native int nativeWait(int pid);
}
