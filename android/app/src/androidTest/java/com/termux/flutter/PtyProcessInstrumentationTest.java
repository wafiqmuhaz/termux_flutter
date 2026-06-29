package com.termux.flutter;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import android.content.Context;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

@RunWith(AndroidJUnit4.class)
public final class PtyProcessInstrumentationTest {
    private static final String[] ENV = new String[]{
        "TERM=xterm-256color",
        "PATH=/system/bin",
        "HOME=/data/local/tmp",
        "ANDROID_ROOT=/system",
        "ANDROID_DATA=/data"
    };

    @Test
    public void shellStartupUsesPty() throws Exception {
        TestListener listener = new TestListener();
        PtyProcess process = startScript(listener, "echo READY\nread line\nexit 0\n");
        try {
            assertTrue(listener.awaitText("READY", 3000));
            assertTrue(process.getChildPidForTesting() > 0);
            String fd = process.describeMasterFdForTesting();
            assertNotNull(fd);
            assertTrue("master fd should point at /dev/ptmx or /dev/pts", fd.contains("/dev/"));
            assertFalse("interactive startup must not use a pipe fd", fd.contains("pipe:"));
        } finally {
            process.close();
        }
    }

    @Test
    public void resizePropagatesRowsColumnsAndPixels() throws Exception {
        TestListener listener = new TestListener();
        PtyProcess process = startScript(listener, "read line\n");
        try {
            process.resize(80, 24, 9, 18);
            int[] size = process.getWindowSizeForTesting();
            assertArrayEquals(new int[]{80, 24, 720, 432}, size);
        } finally {
            process.close();
        }
    }

    @Test
    public void ctrlCSignalReachesProcessGroup() throws Exception {
        TestListener listener = new TestListener();
        PtyProcess process = startScript(listener, "trap 'echo INT; exit 130' INT\necho READY\nwhile :; do :; done\n");
        assertTrue(listener.awaitText("READY", 3000));
        process.sendSignal(PtyProcess.SIGNAL_INT);
        assertTrue(listener.awaitText("INT", 3000));
        assertEquals(130, listener.awaitExit(3000));
    }

    @Test
    public void eofClosesShellCleanly() throws Exception {
        TestListener listener = new TestListener();
        PtyProcess process = startCommand(listener, new String[]{"/system/bin/sh"});
        process.write("exit 0\n");
        assertEquals(0, listener.awaitExit(3000));
    }

    @Test
    public void processExitStatusIsReported() throws Exception {
        TestListener listener = new TestListener();
        startScript(listener, "exit 42\n");
        assertEquals(42, listener.awaitExit(3000));
    }

    @Test
    public void sigtermTerminatesProcess() throws Exception {
        TestListener listener = new TestListener();
        PtyProcess process = startScript(listener, "trap 'exit 143' TERM\necho READY\nwhile :; do :; done\n");
        assertTrue(listener.awaitText("READY", 3000));
        process.sendSignal(PtyProcess.SIGNAL_TERM);
        assertEquals(143, listener.awaitExit(3000));
    }

    @Test
    public void binaryOutputIsPreserved() throws Exception {
        TestListener listener = new TestListener();
        startScript(listener, "printf '\\000\\001\\377'\n");
        assertTrue(listener.awaitBytes(new byte[]{0, 1, (byte) 0xff}, 3000));
    }

    @Test
    public void noPipeFallbackFdIsUsed() throws Exception {
        TestListener listener = new TestListener();
        PtyProcess process = startScript(listener, "read line\n");
        try {
            String fd = process.describeMasterFdForTesting();
            assertNotNull(fd);
            assertFalse(fd.contains("pipe:"));
        } finally {
            process.close();
        }
    }

    private PtyProcess startScript(TestListener listener, String body) throws Exception {
        File script = File.createTempFile("pty-test", ".sh", appContext().getCacheDir());
        try (FileOutputStream out = new FileOutputStream(script)) {
            out.write(body.getBytes(StandardCharsets.UTF_8));
        }
        script.setExecutable(true, false);
        return startCommand(listener, new String[]{"/system/bin/sh", script.getAbsolutePath()});
    }

    private PtyProcess startCommand(TestListener listener, String[] command) throws Exception {
        PtyProcess process = new PtyProcess(listener);
        process.start(command, ENV);
        return process;
    }

    private Context appContext() {
        return InstrumentationRegistry.getInstrumentation().getTargetContext();
    }

    private static final class TestListener implements ShellEngine.OutputListener {
        private final ByteArrayOutputStream output = new ByteArrayOutputStream();
        private final CountDownLatch closed = new CountDownLatch(1);
        private volatile int exitCode = Integer.MIN_VALUE;

        @Override
        public synchronized void onOutput(byte[] chunk) {
            output.write(chunk, 0, chunk.length);
            notifyAll();
        }

        @Override
        public void onClosed(int exitCode) {
            this.exitCode = exitCode;
            closed.countDown();
            synchronized (this) {
                notifyAll();
            }
        }

        synchronized boolean awaitText(String text, long timeoutMs) throws Exception {
            byte[] needle = text.getBytes(StandardCharsets.UTF_8);
            long deadline = System.currentTimeMillis() + timeoutMs;
            while (System.currentTimeMillis() < deadline) {
                if (contains(output.toByteArray(), needle)) return true;
                wait(50);
            }
            return false;
        }

        synchronized boolean awaitBytes(byte[] needle, long timeoutMs) throws Exception {
            long deadline = System.currentTimeMillis() + timeoutMs;
            while (System.currentTimeMillis() < deadline) {
                if (contains(output.toByteArray(), needle)) return true;
                wait(50);
            }
            return false;
        }

        int awaitExit(long timeoutMs) throws Exception {
            assertTrue("process did not exit", closed.await(timeoutMs, TimeUnit.MILLISECONDS));
            return exitCode;
        }

        private static boolean contains(byte[] haystack, byte[] needle) {
            if (needle.length == 0) return true;
            for (int i = 0; i <= haystack.length - needle.length; i++) {
                if (Arrays.equals(Arrays.copyOfRange(haystack, i, i + needle.length), needle)) {
                    return true;
                }
            }
            return false;
        }
    }
}
