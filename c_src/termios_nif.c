#include <erl_nif.h>
#include <termios.h>
#include <unistd.h>
#include <string.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <errno.h>

#if defined(__APPLE__) || defined(__FreeBSD__) || defined(__NetBSD__) || defined(__OpenBSD__)
#include <util.h>
#else
#include <pty.h>
#endif
#include <stdlib.h>

static struct termios original_termios;
static int termios_saved = 0;
static volatile int tui_active = 0;

static ERL_NIF_TERM atom_ok;
static ERL_NIF_TERM atom_error;

static void restore_terminal(void) {
    if (!tui_active) return;
    tui_active = 0;

    if (termios_saved) {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &original_termios);
    }

    const char *sequences = "\e[?1006l\e[?1015l\e[?1002l\e[?1000l\e[?25h\e[?1049l";
    write(STDOUT_FILENO, sequences, strlen(sequences));
}

static void sigint_handler(int sig) {
    restore_terminal();
    signal(SIGINT, SIG_DFL);
    raise(SIGINT);
}

static int load(ErlNifEnv* env, void** priv_data, ERL_NIF_TERM load_info) {
    atom_ok = enif_make_atom(env, "ok");
    atom_error = enif_make_atom(env, "error");
    atexit(restore_terminal);
    return 0;
}

static ERL_NIF_TERM set_tui_active(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    tui_active = 1;
    signal(SIGINT, sigint_handler);
    return atom_ok;
}

static ERL_NIF_TERM set_tui_inactive(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    tui_active = 0;
    signal(SIGINT, SIG_DFL);
    return atom_ok;
}

static ERL_NIF_TERM disable_flow_control(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    struct termios raw;

    if (tcgetattr(STDIN_FILENO, &raw) == -1) {
        return atom_error;
    }

    if (!termios_saved) {
        memcpy(&original_termios, &raw, sizeof(struct termios));
        termios_saved = 1;
    }

    raw.c_iflag &= ~(IXON | IXOFF | IXANY);

    if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == -1) {
        return atom_error;
    }

    return atom_ok;
}

static ERL_NIF_TERM enable_flow_control(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    struct termios raw;

    if (tcgetattr(STDIN_FILENO, &raw) == -1) {
        return atom_error;
    }

    raw.c_iflag |= (IXON | IXOFF);

    if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == -1) {
        return atom_error;
    }

    return atom_ok;
}

static ERL_NIF_TERM enter_raw_mode(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    struct termios raw;

    if (tcgetattr(STDIN_FILENO, &raw) == -1) {
        return atom_error;
    }

    if (!termios_saved) {
        memcpy(&original_termios, &raw, sizeof(struct termios));
        termios_saved = 1;
    }

    raw.c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON | IXOFF | IXANY);
    raw.c_oflag &= ~(OPOST);
    raw.c_cflag |= (CS8);
    raw.c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);
    raw.c_cc[VMIN] = 1;
    raw.c_cc[VTIME] = 0;

    if (tcsetattr(STDIN_FILENO, TCSADRAIN, &raw) == -1) {
        return atom_error;
    }

    return atom_ok;
}

static ERL_NIF_TERM exit_raw_mode(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    if (termios_saved) {
        if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &original_termios) == -1) {
            return atom_error;
        }
    }
    return atom_ok;
}

static ERL_NIF_TERM flush_stdin(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    tcflush(STDIN_FILENO, TCIFLUSH);
    return atom_ok;
}

static ERL_NIF_TERM make_errno(ErlNifEnv* env) {
    const char* name = strerror(errno);
    ERL_NIF_TERM reason;
    size_t len = strlen(name);
    unsigned char* buf = enif_make_new_binary(env, len, &reason);
    memcpy(buf, name, len);
    return enif_make_tuple2(env, atom_error, reason);
}

static ERL_NIF_TERM winsize_term(ErlNifEnv* env, struct winsize* ws) {
    return enif_make_tuple2(env, atom_ok,
        enif_make_tuple4(env,
            enif_make_uint(env, ws->ws_col),
            enif_make_uint(env, ws->ws_row),
            enif_make_uint(env, ws->ws_xpixel),
            enif_make_uint(env, ws->ws_ypixel)));
}

static ERL_NIF_TERM get_winsize_fd(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    int fd;
    struct winsize ws;

    if (!enif_get_int(env, argv[0], &fd)) {
        return enif_make_badarg(env);
    }

    if (ioctl(fd, TIOCGWINSZ, &ws) == -1) {
        return make_errno(env);
    }

    return winsize_term(env, &ws);
}

static ERL_NIF_TERM get_winsize(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    struct winsize ws;

    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == -1) {
        if (ioctl(STDIN_FILENO, TIOCGWINSZ, &ws) == -1) {
            return enif_make_tuple2(env, atom_error, enif_make_atom(env, "not_a_tty"));
        }
    }

    return winsize_term(env, &ws);
}

static ERL_NIF_TERM set_winsize(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    int fd;
    unsigned int cols, rows, xpixel, ypixel;

    if (!enif_get_int(env, argv[0], &fd) ||
        !enif_get_uint(env, argv[1], &cols) ||
        !enif_get_uint(env, argv[2], &rows) ||
        !enif_get_uint(env, argv[3], &xpixel) ||
        !enif_get_uint(env, argv[4], &ypixel)) {
        return enif_make_badarg(env);
    }

    struct winsize ws;
    memset(&ws, 0, sizeof(ws));
    ws.ws_col = (unsigned short) cols;
    ws.ws_row = (unsigned short) rows;
    ws.ws_xpixel = (unsigned short) xpixel;
    ws.ws_ypixel = (unsigned short) ypixel;

    if (ioctl(fd, TIOCSWINSZ, &ws) == -1) {
        return enif_make_tuple2(env, atom_error, enif_make_atom(env, "ioctl_failed"));
    }

    return atom_ok;
}

static ERL_NIF_TERM open_pty(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    unsigned int cols, rows;

    if (!enif_get_uint(env, argv[0], &cols) || !enif_get_uint(env, argv[1], &rows)) {
        return enif_make_badarg(env);
    }

    struct winsize ws;
    memset(&ws, 0, sizeof(ws));
    ws.ws_col = (unsigned short) cols;
    ws.ws_row = (unsigned short) rows;

    int master = -1, slave = -1;
    char name[1024];

    if (openpty(&master, &slave, name, NULL, &ws) == -1) {
        return make_errno(env);
    }

    ERL_NIF_TERM path;
    size_t len = strlen(name);
    unsigned char* buf = enif_make_new_binary(env, len, &path);
    memcpy(buf, name, len);

    return enif_make_tuple2(env, atom_ok,
        enif_make_tuple3(env,
            enif_make_int(env, master),
            enif_make_int(env, slave),
            path));
}

static ERL_NIF_TERM close_fd(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    int fd;

    if (!enif_get_int(env, argv[0], &fd)) {
        return enif_make_badarg(env);
    }

    if (close(fd) == -1) {
        return make_errno(env);
    }

    return atom_ok;
}

/* Signals the process group led by pid. Signal 0 delivers nothing and reports
   only whether the group is still there. */
static ERL_NIF_TERM killpg_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    int pid;
    int sig;

    if (!enif_get_int(env, argv[0], &pid) || !enif_get_int(env, argv[1], &sig)) {
        return enif_make_badarg(env);
    }

    if (pid <= 0) {
        return enif_make_badarg(env);
    }

    if (killpg(pid, sig) == -1) {
        return make_errno(env);
    }

    return atom_ok;
}

static ErlNifFunc nif_funcs[] = {
    {"disable_flow_control", 0, disable_flow_control},
    {"enable_flow_control", 0, enable_flow_control},
    {"enter_raw_mode", 0, enter_raw_mode},
    {"exit_raw_mode", 0, exit_raw_mode},
    {"set_tui_active", 0, set_tui_active},
    {"set_tui_inactive", 0, set_tui_inactive},
    {"flush_stdin", 0, flush_stdin},
    {"get_winsize", 0, get_winsize},
    {"get_winsize", 1, get_winsize_fd},
    {"set_winsize", 5, set_winsize},
    {"open_pty", 2, open_pty},
    {"close_fd", 1, close_fd},
    {"killpg", 2, killpg_nif}
};

ERL_NIF_INIT(Elixir.Drafter.Terminal.TermiosNif, nif_funcs, load, NULL, NULL, NULL)
