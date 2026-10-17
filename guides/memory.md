# Memory

A Drafter app is a handful of long-lived processes: the app loop, the compositor, one server per widget and the terminal driver. This guide covers what Drafter does to keep their heaps small, and the Erlang VM settings that decide how much of the machine's memory the whole program takes.

## Idle compaction

A process that builds a frame leaves the terms it built on its heap until the next garbage collection, and the heap stays as large as the biggest frame it has handled. The compositor, every widget server and the app loop therefore hibernate after 250 ms without a message. Hibernating collects the heap down to the terms still referenced. A process that receives a message more often than every 250 ms is never interrupted, so an animating app pays nothing.

The wait is set in the application configuration:

```elixir
config :drafter, idle_collect_ms: 250
```

`:infinity` turns the compaction off. In a release the same setting can be given on the command line, `-drafter idle_collect_ms infinity`, without rebuilding.

## Running from a release

`mix run` and `mix <task>` keep the Mix and Hex applications and the compiler loaded, and a run that has to compile first leaves the compiler's memory in the VM for the rest of the session. A release carries only the applications the program uses.

Measured on a minimal app of one label in a real terminal, default VM settings: 116 MB under `mix run` with nothing to compile, 104 MB as a release. A `mix run` that has to compile first holds 216 MB for the rest of the session.

## VM settings

Put these in the release's `rel/vm.args.eex`:

```
+P 32768
+Q 4096
+S 2:2
+SDcpu 2:2
+SDio 2
```

- `+P` and `+Q` set how many processes and ports can exist. The defaults are 1,048,576 each, and the VM sets the tables for them aside at start: about 24 MB for nothing. 32,768 processes covers an app serving a few hundred SSH sessions; raise it if sessions run into the thousands.
- `+S`, `+SDcpu` and `+SDio` set the number of normal, dirty CPU and dirty IO scheduler threads. The defaults follow the machine's core count (16, 16 and 10 on a 16-core machine), and each thread costs memory of its own: 30 MB between the defaults and `2:2:2` in the app measured below. A terminal app that renders a few frames a second uses well under one core. `+S 1:1 +SDcpu 1:1 +SDio 1` saves a few megabytes more but runs everything, including native calls, one at a time.

On macOS, set this in `rel/env.sh.eex`:

```sh
export MallocSpaceEfficient=1
```

Without it the C allocator holds about 20 MB of freed memory in the app measured below. It is read when the program starts, so it cannot be set from Elixir.

Allocator tuning (`+MBas`, `+MHas`, `+MHsbct`, `+MHmmbcs`, `+MHlmbcs` and the rest), `+hmqd off_heap` and scheduler busy-wait settings made no measurable difference.

## Measured

Footprint is what `footprint -p` reports on macOS (Activity Monitor's Memory column), for the terminal UI of a system monitor with four large widgets updating once a second, in a real terminal, after two minutes. OTP 29, Apple silicon.

| Setup | Footprint |
| --- | --- |
| `mix run`, default VM settings | 192 MB |
| release, default VM settings | 187 MB |
| release, `+P` and `+Q` | 155 MB |
| release, `+P`, `+Q`, `+S`, `+SDcpu`, `+SDio` | 123 MB |
| the same with `MallocSpaceEfficient=1` | 100 MB |

An empty VM with the same settings is 45 MB, and the minimal one-label app is 47 MB.
