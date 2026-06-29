package com.termux.flutter;

import android.content.Context;
import android.content.res.AssetManager;
import android.os.Build;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

final class BootstrapInstaller {
    private static final String BOOTSTRAP_DIR = "bootstrap";

    private final Context context;
    private final File filesDir;
    private final File prefixDir;
    private final File homeDir;
    private final File tmpDir;

    BootstrapInstaller(Context context) {
        this.context = context.getApplicationContext();
        filesDir = this.context.getFilesDir();
        prefixDir = new File(filesDir, "usr");
        homeDir = new File(filesDir, "home");
        tmpDir = new File(prefixDir, "tmp");
    }

    File getShell() {
        return new File(prefixDir, "bin/bash");
    }

    String[] buildCommand() {
        return new String[]{getShell().getAbsolutePath(), "--login"};
    }

    String[] buildEnvironment() {
        String prefix = prefixDir.getAbsolutePath();
        String home = homeDir.getAbsolutePath();
        return new String[]{
            "TERM=xterm-256color",
            "HOME=" + home,
            "PREFIX=" + prefix,
            "TMPDIR=" + tmpDir.getAbsolutePath(),
            "SHELL=" + getShell().getAbsolutePath(),
            "PATH=" + prefix + "/bin:" + prefix + "/bin/applets:/system/bin",
            "LD_LIBRARY_PATH=" + prefix + "/lib",
            "LANG=en_US.UTF-8",
            "ANDROID_ROOT=/system",
            "ANDROID_DATA=/data"
        };
    }

    void ensureInstalled(ShellEngine.OutputListener listener) throws IOException {
        homeDir.mkdirs();
        tmpDir.mkdirs();

        File shell = getShell();
        if (shell.isFile()) {
            shell.setExecutable(true, false);
            return;
        }

        String assetName = findBootstrapAsset();
        if (assetName == null) {
            listener.onOutput(ShellEngine.utf8(
                "\r\n[bootstrap missing]\r\n" +
                "This app no longer starts /system/bin/sh as a fake Termux shell.\r\n" +
                "Add a Termux-compatible bootstrap zip for this device ABI at:\r\n" +
                "  android/app/src/main/assets/bootstrap/<abi>.zip\r\n" +
                "For this device, expected one of: " + supportedAbiList() + "\r\n\r\n"
            ));
            throw new IOException("Termux bootstrap asset is missing");
        }

        listener.onOutput(ShellEngine.utf8("[installing bootstrap: " + assetName + "]\r\n"));
        extractBootstrap(assetName);
        chmodExecutables(new File(prefixDir, "bin"));
        chmodExecutables(new File(prefixDir, "libexec"));
        chmodExecutables(new File(prefixDir, "lib/apt/methods"));

        if (!shell.isFile()) {
            throw new IOException("bootstrap installed but usr/bin/bash was not found");
        }
        shell.setExecutable(true, false);
    }

    private String findBootstrapAsset() {
        AssetManager assets = context.getAssets();
        for (String abi : Build.SUPPORTED_ABIS) {
            String assetName = BOOTSTRAP_DIR + "/" + abi + ".zip";
            try {
                InputStream ignored = assets.open(assetName);
                ignored.close();
                return assetName;
            } catch (IOException ignored) {
                // Try the next supported ABI.
            }
        }
        return null;
    }

    private String supportedAbiList() {
        StringBuilder builder = new StringBuilder();
        for (int i = 0; i < Build.SUPPORTED_ABIS.length; i++) {
            if (i > 0) builder.append(", ");
            builder.append(Build.SUPPORTED_ABIS[i]);
        }
        return builder.toString();
    }

    private void extractBootstrap(String assetName) throws IOException {
        AssetManager assets = context.getAssets();
        ZipInputStream zip = new ZipInputStream(assets.open(assetName));
        try {
            ZipEntry entry;
            while ((entry = zip.getNextEntry()) != null) {
                File output = new File(filesDir, entry.getName()).getCanonicalFile();
                String filesPath = filesDir.getCanonicalPath();
                if (!output.getPath().startsWith(filesPath + File.separator)) {
                    throw new IOException("invalid bootstrap entry path: " + entry.getName());
                }

                if (entry.isDirectory()) {
                    output.mkdirs();
                } else {
                    File parent = output.getParentFile();
                    if (parent != null) parent.mkdirs();
                    FileOutputStream out = new FileOutputStream(output);
                    try {
                        byte[] buffer = new byte[8192];
                        int count;
                        while ((count = zip.read(buffer)) != -1) {
                            out.write(buffer, 0, count);
                        }
                    } finally {
                        out.close();
                    }
                }
                zip.closeEntry();
            }
        } finally {
            zip.close();
        }
    }

    private void chmodExecutables(File directory) {
        if (!directory.exists()) return;
        File[] children = directory.listFiles();
        if (children == null) return;
        for (File child : children) {
            if (child.isDirectory()) {
                chmodExecutables(child);
            } else {
                child.setExecutable(true, false);
            }
        }
    }
}
