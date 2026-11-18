# Performance

Drafter decides whether to redraw by hashing state and comparing the hash with the last one. This guide covers what that costs, how to keep it small, and the two callbacks that let an app say what actually decides the output.

## What gets hashed

Two hashes are taken, and both read every byte of the term, binaries included:

- **The app state.** Before each render the app loop hashes the whole state returned by your callbacks. If the hash matches the previous render's and the layout is unchanged, the render is skipped.
- **A widget's state and rect.** Before a widget that draws an image (`image_raster/2` or `image/3`) generates one, its server hashes the widget state together with its rect. A picture is generated only when the hash differs from the last picture's.

The hash of a term costs time in proportion to its size. A state that holds a few kilobytes costs microseconds. A state that holds a 17 MB binary costs about 12 ms each time, several times a second, which is more than the frame budget.

## Keep large static data out of the state

Data that does not change while the app runs (decoded images, tile atlases, lookup tables, file contents) does not belong in a state that is hashed. Store it once and put a small handle in the state:

- an ETS table or `:persistent_term` entry, keyed by a reference or an atom, with the handle `%{key: key, size: size}` in the state;
- a process that owns the data and a pid in the state.

The code that needs the data fetches it by handle when it uses it. A handle hashes in nanoseconds however large the data is.

Closures count too: a function stored in a state or in widget props hashes together with every term it captured, so a closure that captures the large data carries it into every hash.

## Say what decides the output: `render_key/1` and `image_key/1`

When a state holds data that is expensive to hash and cannot be moved out, or holds fields that never affect the output, define one of the optional callbacks. Each returns a small value, and Drafter hashes that value in place of the state.

```elixir
defmodule MyApp do
  use Drafter.App

  def render_key(state), do: {state.screen, state.selected, state.query, state.rows_version}
end
```

For a widget that draws images:

```elixir
def image_key(state), do: {state.revision, state.zoom}
```

Rules for the returned value:

- It must change whenever the output changes. A key that stays the same while the output should change leaves the old output on screen.
- It must be cheap to build, since it is built on every frame.
- A version counter that the code bumps whenever it changes the underlying data is the usual choice.

## The slow-hash warning

When a hash of an app or widget state takes longer than 4 ms, Drafter logs a warning once for that module, with the size of the term it hashed. The warning means one of the two fixes above applies. It is logged once per module for the life of the VM.
