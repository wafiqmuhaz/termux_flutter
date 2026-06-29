package com.termux.flutter;

import android.content.Context;
import android.content.res.AssetManager;
import android.os.Build;
import android.system.ErrnoException;
import android.system.Os;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.List;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

final class BootstrapInstaller {
    private static final String BOOTSTRAP_DIR = "bootstrap";

    private final Context context;
    private final File filesDir;
    private final File prefixDir;
    private final File stagingPrefixDir;
    private final File homeDir;
    private final File tmpDir;

    BootstrapInstaller(Context context) {
        this.context = context.getApplicationContext();
        filesDir = this.context.getFilesDir();
        prefixDir = new File(filesDir, "usr");
        stagingPrefixDir = new File(filesDir, "usr-staging");
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
            String[] candidates = new String[]{
                BOOTSTRAP_DIR + "/" + abi + ".zip",
                BOOTSTRAP_DIR + "/bootstrap-" + termuxArchForAbi(abi) + ".zip"
            };
            for (String assetName : candidates) {
                if (assetName.endsWith("null.zip")) continue;
                try {
                    InputStream ignored = assets.open(assetName);
                    ignored.close();
                    return assetName;
                } catch (IOException ignored) {
                    // Try the next supported ABI or upstream Termux arch alias.
                }
            }
        }
        return null;
    }

    private String termuxArchForAbi(String abi) {
        if ("arm64-v8a".equals(abi)) return "aarch64";
        if ("armeabi-v7a".equals(abi)) return "arm";
        if ("x86".equals(abi)) return "i686";
        if ("x86_64".equals(abi)) return "x86_64";
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
        deleteRecursively(stagingPrefixDir);
        deleteRecursively(prefixDir);
        if (!stagingPrefixDir.mkdirs() && !stagingPrefixDir.isDirectory()) {
            throw new IOException("failed to create staging prefix: " + stagingPrefixDir);
        }

        AssetManager assets = context.getAssets();
        ZipInputStream zip = new ZipInputStream(assets.open(assetName));
        List<Symlink> symlinks = new ArrayList<>();
        try {
            ZipEntry entry;
            while ((entry = zip.getNextEntry()) != null) {
                String entryName = entry.getName();
                if ("SYMLINKS.txt".equals(entryName)) {
                    readSymlinks(zip, symlinks);
                    zip.closeEntry();
                    continue;
                }

                File output = outputFileForEntry(entryName).getCanonicalFile();
                assertInside(output, filesDir);

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

        for (Symlink symlink : symlinks) {
            File link = new File(stagingPrefixDir, symlink.linkPath).getCanonicalFile();
            assertInside(link, stagingPrefixDir);
            File parent = link.getParentFile();
            if (parent != null) parent.mkdirs();
            try {
                Os.symlink(symlink.target, link.getAbsolutePath());
            } catch (ErrnoException e) {
                throw new IOException("failed to create bootstrap symlink " + link + " -> " + symlink.target, e);
            }
        }

        if (!stagingPrefixDir.renameTo(prefixDir)) {
            throw new IOException("failed to move staging prefix into place");
        }
    }

    private File outputFileForEntry(String entryName) {
        if (entryName.startsWith("usr/")) {
            return new File(filesDir, entryName);
        }
        return new File(stagingPrefixDir, entryName);
    }

    private void readSymlinks(InputStream input, List<Symlink> symlinks) throws IOException {
        BufferedReader reader = new BufferedReader(new InputStreamReader(input));
        String line;
        while ((line = reader.readLine()) != null) {
            String[] parts = line.split("←", 2);
            if (parts.length != 2) {
                throw new IOException("malformed bootstrap symlink line: " + line);
            }
            symlinks.add(new Symlink(parts[0], parts[1]));
        }
    }

    private void assertInside(File file, File directory) throws IOException {
        String dirPath = directory.getCanonicalPath();
        String filePath = file.getCanonicalPath();
        if (!filePath.equals(dirPath) && !filePath.startsWith(dirPath + File.separator)) {
            throw new IOException("invalid bootstrap entry path: " + filePath);
        }
    }

    private void deleteRecursively(File file) throws IOException {
        if (!file.exists()) return;
        if (file.isDirectory()) {
            File[] children = file.listFiles();
            if (children != null) {
                for (File child : children) {
                    deleteRecursively(child);
                }
            }
        }
        if (!file.delete()) {
            throw new IOException("failed to delete " + file);
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

    private static final class Symlink {
        final String target;
        final String linkPath;

        Symlink(String target, String linkPath) {
            this.target = target;
            this.linkPath = linkPath;
        }
    }
}
