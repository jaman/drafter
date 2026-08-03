#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

#define EXIT_USAGE 64
#define EXIT_SETUP 71
#define EXIT_NOEXEC 127

static void close_inherited_descriptors(void) {
    long limit = sysconf(_SC_OPEN_MAX);

    if (limit < 0 || limit > 65536) {
        limit = 4096;
    }

    for (int fd = STDERR_FILENO + 1; fd < (int) limit; fd++) {
        close(fd);
    }
}

int main(int argc, char *argv[]) {
    if (argc < 3) {
        return EXIT_USAGE;
    }

    const char *slave_path = argv[1];

    setsid();

    int slave = open(slave_path, O_RDWR);

    if (slave == -1) {
        return EXIT_SETUP;
    }

#ifdef TIOCSCTTY
    ioctl(slave, TIOCSCTTY, 0);
#endif

    if (dup2(slave, STDIN_FILENO) == -1 || dup2(slave, STDOUT_FILENO) == -1 ||
        dup2(slave, STDERR_FILENO) == -1) {
        return EXIT_SETUP;
    }

    if (slave > STDERR_FILENO) {
        close(slave);
    }

    close_inherited_descriptors();

    tcsetpgrp(STDIN_FILENO, getpgrp());

    execvp(argv[2], &argv[2]);

    fprintf(stderr, "pty_spawn: %s: %s\r\n", argv[2], strerror(errno));
    _exit(EXIT_NOEXEC);
}
