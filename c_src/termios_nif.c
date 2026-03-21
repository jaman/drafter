#include <erl_nif.h>
#include <termios.h>
#include <unistd.h>
#include <string.h>
#include <signal.h>
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

static ErlNifFunc nif_funcs[] = {
    {"disable_flow_control", 0, disable_flow_control},
    {"enable_flow_control", 0, enable_flow_control},
    {"enter_raw_mode", 0, enter_raw_mode},
    {"exit_raw_mode", 0, exit_raw_mode},
    {"set_tui_active", 0, set_tui_active},
    {"set_tui_inactive", 0, set_tui_inactive},
    {"flush_stdin", 0, flush_stdin}
};

ERL_NIF_INIT(Elixir.Drafter.Terminal.TermiosNif, nif_funcs, load, NULL, NULL, NULL)
