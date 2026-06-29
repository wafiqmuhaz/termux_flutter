#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <jni.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

#include <android/log.h>

#define LOG_TAG "PTY_BRIDGE"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

#ifndef IUTF8
#define IUTF8 0040000
#endif

extern char **environ;

static void throw_io(JNIEnv *env, const char *message) {
    jclass clazz = (*env)->FindClass(env, "java/io/IOException");
    if (clazz != NULL) {
        char buffer[256];
        snprintf(buffer, sizeof(buffer), "%s: %s", message, strerror(errno));
        (*env)->ThrowNew(env, clazz, buffer);
    }
}

static char **copy_string_array(JNIEnv *env, jobjectArray array) {
    if (array == NULL) return NULL;
    jsize count = (*env)->GetArrayLength(env, array);
    char **items = calloc((size_t) count + 1, sizeof(char *));
    if (items == NULL) return NULL;
    for (jsize i = 0; i < count; i++) {
        jstring value = (jstring) (*env)->GetObjectArrayElement(env, array, i);
        if (value == NULL) {
            items[i] = strdup("");
            continue;
        }
        const char *utf = (*env)->GetStringUTFChars(env, value, NULL);
        items[i] = strdup(utf == NULL ? "" : utf);
        if (utf != NULL) (*env)->ReleaseStringUTFChars(env, value, utf);
        (*env)->DeleteLocalRef(env, value);
    }
    return items;
}

static void free_string_array(char **items) {
    if (items == NULL) return;
    for (int i = 0; items[i] != NULL; i++) free(items[i]);
    free(items);
}

static int configure_termios(int fd) {
    struct termios t;
    if (tcgetattr(fd, &t) != 0) {
        LOGE("tcgetattr(fd=%d) failed errno=%d", fd, errno);
        return -1;
    }

    t.c_iflag &= ~(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL);
    t.c_oflag &= ~OPOST;
    t.c_lflag &= ~(ECHO | ECHONL | ICANON | ISIG | IEXTEN);
    t.c_cflag &= ~(CSIZE | PARENB);
    t.c_cflag |= CS8;
    t.c_cc[VMIN] = 1;
    t.c_cc[VTIME] = 0;
    t.c_iflag |= IUTF8;
    t.c_iflag &= ~(IXON | IXOFF | IXANY);

    int result = tcsetattr(fd, TCSANOW, &t);
    LOGD("tcsetattr(fd=%d raw IUTF8 no-flow) result=%d errno=%d", fd, result, result == 0 ? 0 : errno);
    return result;
}

static int set_window_size(int fd, int cols, int rows, int cell_width, int cell_height) {
    struct winsize ws;
    memset(&ws, 0, sizeof(ws));
    ws.ws_col = (unsigned short) cols;
    ws.ws_row = (unsigned short) rows;
    ws.ws_xpixel = (unsigned short) (cols * cell_width);
    ws.ws_ypixel = (unsigned short) (rows * cell_height);
    int result = ioctl(fd, TIOCSWINSZ, &ws);
    LOGD("ioctl(TIOCSWINSZ fd=%d rows=%d cols=%d xpixel=%d ypixel=%d) result=%d errno=%d",
         fd, rows, cols, ws.ws_xpixel, ws.ws_ypixel, result, result == 0 ? 0 : errno);
    return result;
}

static void close_inherited_fds(void) {
    DIR *self_dir = opendir("/proc/self/fd");
    if (self_dir == NULL) return;
    int self_dir_fd = dirfd(self_dir);
    struct dirent *entry;
    while ((entry = readdir(self_dir)) != NULL) {
        int fd = atoi(entry->d_name);
        if (fd > STDERR_FILENO && fd != self_dir_fd) close(fd);
    }
    closedir(self_dir);
}

static int open_pty_master(char *slave_name, size_t slave_name_size) {
    int master = open("/dev/ptmx", O_RDWR | O_CLOEXEC);
    LOGD("open(/dev/ptmx) result=%d errno=%d", master, master >= 0 ? 0 : errno);
    if (master < 0) return -1;

    int grant_result = grantpt(master);
    LOGD("grantpt(%d) result=%d errno=%d", master, grant_result, grant_result == 0 ? 0 : errno);
    if (grant_result != 0) {
        close(master);
        return -1;
    }

    int unlock_result = unlockpt(master);
    LOGD("unlockpt(%d) result=%d errno=%d", master, unlock_result, unlock_result == 0 ? 0 : errno);
    if (unlock_result != 0) {
        close(master);
        return -1;
    }

    int pts_result = ptsname_r(master, slave_name, slave_name_size);
    LOGD("ptsname_r(%d) result=%d slave=%s errno=%d", master, pts_result,
         pts_result == 0 ? slave_name : "<none>", pts_result == 0 ? 0 : errno);
    if (pts_result != 0) {
        close(master);
        return -1;
    }

    if (configure_termios(master) != 0) {
        close(master);
        return -1;
    }

    return master;
}

JNIEXPORT jintArray JNICALL
Java_com_termux_flutter_PtyProcess_nativeStart(JNIEnv *env, jclass clazz, jobjectArray command,
                                               jobjectArray envp, jint cols, jint rows,
                                               jint cell_width, jint cell_height) {
    (void) clazz;

    char slave_name[128];
    int master = open_pty_master(slave_name, sizeof(slave_name));
    if (master < 0) {
        LOGE("FATAL: /dev/ptmx startup failed errno=%d", errno);
        throw_io(env, "open /dev/ptmx failed");
        return NULL;
    }

    if (set_window_size(master, cols, rows, cell_width, cell_height) != 0) {
        close(master);
        throw_io(env, "initial TIOCSWINSZ failed");
        return NULL;
    }

    char **argv = copy_string_array(env, command);
    char **environment = copy_string_array(env, envp);
    if (argv == NULL || argv[0] == NULL || argv[0][0] == '\0') {
        close(master);
        free_string_array(argv);
        free_string_array(environment);
        errno = EINVAL;
        throw_io(env, "invalid shell command");
        return NULL;
    }

    pid_t pid = fork();
    LOGD("fork() result=%d errno=%d", pid, pid >= 0 ? 0 : errno);
    if (pid < 0) {
        close(master);
        free_string_array(argv);
        free_string_array(environment);
        throw_io(env, "fork failed");
        return NULL;
    }

    if (pid == 0) {
        sigset_t signals_to_unblock;
        sigfillset(&signals_to_unblock);
        sigprocmask(SIG_UNBLOCK, &signals_to_unblock, NULL);

        close(master);

        pid_t session = setsid();
        LOGD("child setsid() result=%d errno=%d", session, session >= 0 ? 0 : errno);
        if (session < 0) _exit(127);

        int slave = open(slave_name, O_RDWR | O_CLOEXEC);
        LOGD("child open(slave=%s) result=%d errno=%d", slave_name, slave, slave >= 0 ? 0 : errno);
        if (slave < 0) _exit(127);

        int ctty_result = ioctl(slave, TIOCSCTTY, 0);
        LOGD("child ioctl(TIOCSCTTY slave=%d) result=%d errno=%d", slave, ctty_result, ctty_result == 0 ? 0 : errno);
        if (ctty_result != 0) _exit(127);
        set_window_size(slave, cols, rows, cell_width, cell_height);

        dup2(slave, STDIN_FILENO);
        dup2(slave, STDOUT_FILENO);
        dup2(slave, STDERR_FILENO);
        if (slave > STDERR_FILENO) close(slave);

        close_inherited_fds();

        clearenv();
        if (environment != NULL) {
            for (char **entry = environment; *entry != NULL; entry++) putenv(*entry);
        }

        execve(argv[0], argv, environ);
        perror("execve");
        _exit(127);
    }

    LOGD("parent closing slave=%s after child pid=%d", slave_name, pid);
    free_string_array(argv);
    free_string_array(environment);

    jint values[2];
    values[0] = master;
    values[1] = pid;
    jintArray result = (*env)->NewIntArray(env, 2);
    if (result == NULL) {
        close(master);
        return NULL;
    }
    (*env)->SetIntArrayRegion(env, result, 0, 2, values);
    return result;
}

JNIEXPORT jint JNICALL
Java_com_termux_flutter_PtyProcess_nativeRead(JNIEnv *env, jclass clazz, jint fd, jbyteArray buffer, jint length) {
    (void) clazz;
    jbyte *bytes = (*env)->GetByteArrayElements(env, buffer, NULL);
    if (bytes == NULL) return -1;
    int count = (int) read(fd, bytes, (size_t) length);
    (*env)->ReleaseByteArrayElements(env, buffer, bytes, count >= 0 ? 0 : JNI_ABORT);
    return count;
}

JNIEXPORT jint JNICALL
Java_com_termux_flutter_PtyProcess_nativeWrite(JNIEnv *env, jclass clazz, jint fd, jbyteArray buffer, jint length) {
    (void) clazz;
    jbyte *bytes = (*env)->GetByteArrayElements(env, buffer, NULL);
    if (bytes == NULL) return -1;
    int count = (int) write(fd, bytes, (size_t) length);
    (*env)->ReleaseByteArrayElements(env, buffer, bytes, JNI_ABORT);
    LOGD("write(fd=%d length=%d) result=%d errno=%d", fd, length, count, count >= 0 ? 0 : errno);
    return count;
}

JNIEXPORT jint JNICALL
Java_com_termux_flutter_PtyProcess_nativeResize(JNIEnv *env, jclass clazz, jint fd, jint cols, jint rows,
                                                jint cell_width, jint cell_height) {
    (void) env;
    (void) clazz;
    return set_window_size(fd, cols, rows, cell_width, cell_height);
}

JNIEXPORT jintArray JNICALL
Java_com_termux_flutter_PtyProcess_nativeGetWindowSize(JNIEnv *env, jclass clazz, jint fd) {
    (void) clazz;
    struct winsize ws;
    memset(&ws, 0, sizeof(ws));
    if (ioctl(fd, TIOCGWINSZ, &ws) != 0) return NULL;
    jint values[4];
    values[0] = ws.ws_col;
    values[1] = ws.ws_row;
    values[2] = ws.ws_xpixel;
    values[3] = ws.ws_ypixel;
    jintArray result = (*env)->NewIntArray(env, 4);
    if (result != NULL) (*env)->SetIntArrayRegion(env, result, 0, 4, values);
    return result;
}

JNIEXPORT jstring JNICALL
Java_com_termux_flutter_PtyProcess_nativeDebugDescribeFd(JNIEnv *env, jclass clazz, jint fd) {
    (void) clazz;
    char proc_path[64];
    char target[256];
    snprintf(proc_path, sizeof(proc_path), "/proc/self/fd/%d", fd);
    ssize_t count = readlink(proc_path, target, sizeof(target) - 1);
    if (count < 0) return NULL;
    target[count] = '\0';
    return (*env)->NewStringUTF(env, target);
}

JNIEXPORT jint JNICALL
Java_com_termux_flutter_PtyProcess_nativeClose(JNIEnv *env, jclass clazz, jint fd) {
    (void) env;
    (void) clazz;
    int result = close(fd);
    LOGD("close(fd=%d) result=%d errno=%d", fd, result, result == 0 ? 0 : errno);
    return result;
}

JNIEXPORT jint JNICALL
Java_com_termux_flutter_PtyProcess_nativeSendSignal(JNIEnv *env, jclass clazz, jint pid, jint signal) {
    (void) env;
    (void) clazz;
    int result = kill(-(pid_t) pid, signal);
    if (result != 0 && errno == ESRCH) result = kill((pid_t) pid, signal);
    LOGD("signal(pid=%d pgid=%d sig=%d) result=%d errno=%d", pid, -pid, signal, result, result == 0 ? 0 : errno);
    return result;
}

JNIEXPORT jint JNICALL
Java_com_termux_flutter_PtyProcess_nativeWait(JNIEnv *env, jclass clazz, jint pid) {
    (void) env;
    (void) clazz;
    int status = 0;
    if (waitpid((pid_t) pid, &status, 0) < 0) return -1;
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
    return status;
}
