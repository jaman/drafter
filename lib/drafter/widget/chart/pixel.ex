defmodule Drafter.Widget.Chart.Pixel do
  @moduledoc """
  Renders chart data as terminal graphics via the frozen `french_curve` library.

  Three outputs from a single rasterisation path: a true-image escape sequence for
  terminals that support a pixel protocol (kitty / iTerm2 / sixel), anti-aliased
  braille `Strip`s for any other truecolor terminal, or block-character `Strip`s in
  one of `FrenchCurve.Backend.Cells`' glyph sets (`:half`, `:quad`, `:sextant`,
  `:octant`), two colours per cell. Callers pick the mode with `mode/2` ("best
  available" for `:pixel`) and pass a chart `spec` to `picture/3` (a raster for
  `Drafter.Render.Picture` to encode), `braille_strips/2` or `cells_strips/3`.

  A `spec` is `%{type, values, color: {r,g,b,a}, smooth, fill_opacity, min, max}`.
  Add a `raster/3` clause to support a new chart type; `supported/0` gates which
  types use this path at all.
  """

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Session.Context
  alias Drafter.Visualization.Reduce
  alias FrenchCurve.Backend.Cells
  alias FrenchCurve.{Capability, Chart, Draw, Raster}

  @pixel_protocols [:iterm2, :kitty, :sixel]
  @cell_sets [:half, :quad, :sextant, :octant]
  @modes [:auto, :pixel, :kitty, :iterm2, :sixel, :braille, :text | @cell_sets]
  @supported [
    :line,
    :step,
    :area,
    :braille_area,
    :stacked_area,
    :bar,
    :clustered_bar,
    :stacked_bar,
    :range_bar,
    :histogram,
    :scatter,
    :bubble,
    :candlestick,
    :heatmap,
    :pie,
    :gauge
  ]
  @up_color {90, 200, 130, 255}
  @down_color {220, 90, 90, 255}
  @palette [
    {120, 200, 255, 255},
    {255, 150, 80, 255},
    {120, 230, 150, 255},
    {220, 130, 230, 255},
    {255, 215, 90, 255},
    {130, 220, 220, 255}
  ]

  @spec supported() :: [atom()]
  def supported, do: @supported

  @doc """
  The list of mode atoms accepted by `:renderer`, `DRAFTER_MODE`, and the `mode:`
  run option: `#{inspect(@modes)}`.
  """
  @spec modes() :: [atom()]
  def modes, do: @modes

  @typedoc "How a chart or slider draws: an image, braille, block characters of a glyph set, or text."
  @type drawing :: :pixel | :braille | {:cells, FrenchCurve.Backend.Cells.set()} | :text

  @doc "The glyph sets accepted as modes, each drawing through `cells_strips/3`."
  @spec cell_sets() :: [atom()]
  def cell_sets, do: @cell_sets

  @spec mode(atom() | nil, atom()) :: drawing()
  def mode(renderer, type), do: to_mode(resolve(renderer), type)

  defp to_mode(_effective, type) when type not in @supported, do: :text
  defp to_mode(:text, _type), do: :text
  defp to_mode(:braille, _type), do: :braille
  defp to_mode(set, _type) when set in @cell_sets, do: {:cells, set}

  defp to_mode(effective, _type) when effective in [:auto, :pixel] do
    if detect(), do: :pixel, else: :braille
  end

  defp to_mode(proto, _type) when proto in @pixel_protocols, do: :pixel

  @doc """
  The graphics protocol to draw with, or `nil` when the terminal has none.

  A `renderer` naming a protocol (`:kitty`, `:iterm2`, `:sixel`) is used as given;
  any mode that is not `:auto` or `:pixel` has no protocol and returns `nil`.

  `:auto` and `:pixel` take what the terminal answered when it was probed at
  startup — see `Drafter.Terminal.Probe`. A terminal that was never probed, or
  that answered the probe without naming a protocol, is guessed at from its
  environment instead, through `FrenchCurve.Capability.detect/1`.

  Either way the terminal in question is the one this session is attached to, which
  for a session served over ssh or telnet is the connecting client's rather than
  the host's.
  """
  @spec protocol(atom() | nil) :: atom() | nil
  def protocol(renderer), do: protocol_for(resolve(renderer))

  defp protocol_for(effective) when effective in [:auto, :pixel], do: detect()
  defp protocol_for(proto) when proto in @pixel_protocols, do: proto
  defp protocol_for(_effective), do: nil

  @doc """
  Resolve an effective mode from precedence: the `DRAFTER_MODE` env var forces and
  wins over everything; otherwise an explicit per-widget `renderer` (any mode atom),
  then the runtime `:drafter` `:render_mode` application env, then `:text`.
  """
  @spec resolve(atom() | nil) :: atom()
  def resolve(renderer), do: env_mode() || widget_mode(renderer) || runtime_mode() || :text

  defp widget_mode(renderer) when renderer in @modes, do: renderer
  defp widget_mode(_renderer), do: nil

  defp env_mode do
    case System.get_env("DRAFTER_MODE") do
      blank when blank in [nil, ""] -> legacy_mode()
      value -> parse_mode(value)
    end
  end

  defp legacy_mode do
    if System.get_env("DRAFTER_NO_PIXEL") not in [nil, ""], do: :text
  end

  defp runtime_mode do
    case Application.get_env(:drafter, :render_mode) do
      mode when mode in @modes -> mode
      _ -> nil
    end
  end

  @mode_names Map.new(@modes, &{Atom.to_string(&1), &1})

  defp parse_mode(value), do: Map.get(@mode_names, value |> String.trim() |> String.downcase())

  @doc """
  The graphics protocol of this session's terminal, whatever mode is in force.

  What the terminal answered when it was probed at startup, or, when it was never
  probed or named no protocol, what its environment suggests through
  `FrenchCurve.Capability.detect/1`. `nil` when neither names one. An iTerm2 session is
  always judged by its environment, whatever it answered: `:iterm2`, or `:kitty` when
  `FRENCH_CURVE_ITERM2=kitty` is set (see `FrenchCurve.Capability`).
  """
  @spec terminal() :: atom() | nil
  def terminal, do: detect()

  defp detect do
    case Context.terminal_protocol() do
      {:ok, probed} when not is_nil(probed) -> unless_iterm2(probed)
      _unprobed_or_unnamed -> detect_from_env()
    end
  end

  defp unless_iterm2(probed) do
    if Capability.iterm2?(Context.terminal_env()), do: detect_from_env(), else: probed
  end

  defp detect_from_env do
    case Capability.detect(Context.terminal_env()) do
      :braille -> nil
      protocol -> protocol
    end
  end

  @default_image_scale 4
  @max_image_width 512
  @max_image_height 288

  @doc """
  Draws `spec` as a `Drafter.Render.Picture` filling a `cols` by `rows` cell box at the
  widget's top left, to be drawn with `protocol`.

  The raster is a whole number of pixels per cell: `:scale` (default `4`) across and
  twice that down, reduced where needed to keep it within 512 by 288 pixels. Returns
  `nil` when `protocol` is `nil` or the chart cannot be drawn.
  """
  @spec picture(map(), atom() | nil, {pos_integer(), pos_integer()}) ::
          Drafter.Render.Picture.t() | nil
  def picture(_spec, nil, _cells), do: nil

  def picture(spec, protocol, {cols, rows}) do
    scale = Map.get(spec, :scale, @default_image_scale)
    across = max(1, min(scale, div(@max_image_width, cols)))
    down = max(1, min(scale * 2, div(@max_image_height, rows)))

    case raster(spec, cols * across, rows * down) do
      nil ->
        nil

      raster ->
        %{
          raster: Raster.finalize(raster),
          protocol: protocol,
          dx: 0,
          dy: 0,
          cols: cols,
          rows: rows
        }
    end
  rescue
    _ -> nil
  end

  @spec braille_strips(map(), {pos_integer(), pos_integer()}) :: [Strip.t()] | nil
  def braille_strips(spec, {cols, rows}) do
    case raster(spec, cols * 2, rows * 4) do
      nil -> nil
      r -> r |> FrenchCurve.render(:braille, []) |> rows_to_strips() |> fit_rows(rows, cols)
    end
  rescue
    _ -> nil
  end

  @doc """
  Renders `spec` as `rows` strips of `cols` cells in the glyph set `set`, or `nil` when
  it cannot be drawn.
  """
  @spec cells_strips(map(), {pos_integer(), pos_integer()}, FrenchCurve.Backend.Cells.set()) ::
          [Strip.t()] | nil
  def cells_strips(spec, {cols, rows}, set) do
    {sx, sy} = Cells.subpixels(set)

    case raster(spec, cols * sx, rows * sy) do
      nil -> nil
      r -> r |> FrenchCurve.render(:cells, set: set) |> cells_to_strips() |> fit_rows(rows, cols)
    end
  rescue
    _ -> nil
  end

  @line_types [:line, :step]
  @area_types [:area, :braille_area, :stacked_area]

  defp raster(spec, w, h), do: spec |> fit_to_width(w) |> draw_raster(w, h)

  defp fit_to_width(%{type: type, data: data} = spec, w) when type in @line_types do
    %{spec | data: fit_series(data, &Reduce.min_max(&1, w, fn item -> to_value(item) end))}
  end

  defp fit_to_width(%{type: type, data: [first | _] = data} = spec, w)
       when type in @area_types and is_list(first) do
    lists = Enum.filter(data, &value_list?/1)
    %{spec | data: Reduce.aligned_peaks(lists, w, &to_value/1)}
  end

  defp fit_to_width(%{type: type, data: data} = spec, w) when type in @area_types do
    %{spec | data: fit_series(data, &Reduce.peaks(&1, w, fn item -> to_value(item) end))}
  end

  defp fit_to_width(spec, _w), do: spec

  defp fit_series([first | _] = data, reducer) when is_list(first), do: Enum.map(data, reducer)
  defp fit_series([_ | _] = data, reducer), do: reducer.(data)
  defp fit_series(data, _reducer), do: data

  defp draw_raster(%{type: type} = spec, w, h) when type in [:area, :braille_area] do
    case classify(spec.data) do
      {:single, values} -> Chart.area(values, fc_opts(spec, w, h))
      {:multi, series} -> build_multi_area(series, spec, w, h)
      :empty -> nil
    end
  end

  defp draw_raster(%{type: :line} = spec, w, h) do
    case classify(spec.data) do
      {:single, values} -> Chart.line(values, fc_opts(spec, w, h))
      {:multi, series} -> build_multi_line(series, spec, w, h)
      :empty -> nil
    end
  end

  defp draw_raster(%{type: :step} = spec, w, h) do
    with_numbers(spec.data, &build_step(&1, spec, w, h))
  end

  defp draw_raster(%{type: :stacked_area} = spec, w, h) do
    case classify(spec.data) do
      {:multi, series} -> build_stacked_area(series, spec, w, h)
      {:single, values} -> Chart.area(values, fc_opts(spec, w, h))
      :empty -> nil
    end
  end

  defp draw_raster(%{type: :bar} = spec, w, h) do
    with_numbers(spec.data, &build_bar(&1, spec, w, h))
  end

  defp draw_raster(%{type: :histogram} = spec, w, h) do
    with_numbers(spec.data, &build_histogram(&1, spec, w, h))
  end

  defp draw_raster(%{type: :clustered_bar} = spec, w, h) do
    case classify(spec.data) do
      {:multi, series} -> build_grouped_bar(series, spec, w, h, :clustered)
      {:single, values} -> build_bar(values, spec, w, h)
      :empty -> nil
    end
  end

  defp draw_raster(%{type: :stacked_bar} = spec, w, h) do
    case classify(spec.data) do
      {:multi, series} -> build_grouped_bar(series, spec, w, h, :stacked)
      {:single, values} -> build_bar(values, spec, w, h)
      :empty -> nil
    end
  end

  defp draw_raster(%{type: :range_bar} = spec, w, h) do
    case ranges(spec.data) do
      [] -> nil
      pairs -> build_range_bar(pairs, spec, w, h)
    end
  end

  defp draw_raster(%{type: :scatter} = spec, w, h) do
    case scatter_series(spec.data) do
      {:single, points} -> build_scatter(points, spec, w, h)
      {:multi, series} -> build_multi_scatter(series, spec, w, h)
      :empty -> nil
    end
  end

  defp draw_raster(%{type: :bubble} = spec, w, h) do
    case scatter_points(spec.data) do
      [] -> nil
      points -> build_bubble(points, spec, w, h)
    end
  end

  defp draw_raster(%{type: :candlestick} = spec, w, h) do
    case candles(spec.data) do
      [] -> nil
      candles -> build_candlestick(candles, w, h)
    end
  end

  defp draw_raster(%{type: :heatmap} = spec, w, h) do
    case grid(spec.data) do
      [] -> nil
      rows -> build_heatmap(rows, w, h)
    end
  end

  defp draw_raster(%{type: :pie, slices: slices}, w, h) when slices != [] do
    build_pie(slices, w, h)
  end

  defp draw_raster(%{type: :gauge, value: value, fill: fill, track: track}, w, h) do
    build_gauge(value, fill, track, w, h)
  end

  defp draw_raster(_spec, _w, _h), do: nil

  defp with_numbers(data, fun) do
    case numbers(data) do
      [] -> nil
      values -> fun.(values)
    end
  end

  defp fc_opts(spec, w, h) do
    [width: w, height: h, color: spec.color, smooth: spec.smooth, fill_opacity: spec.fill_opacity]
    |> maybe_put(:min, Map.get(spec, :min))
    |> maybe_put(:max, Map.get(spec, :max))
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp build_bar(all_values, spec, w, h) do
    values = visible_tail(all_values, w, 1)
    {lo, hi} = range(values, spec)
    band = max(1, div(w, length(values)))
    base_y = round(y_px(clamp(0.0, lo, hi), lo, hi, h))

    values
    |> Enum.with_index()
    |> Enum.reduce(Raster.new(w, h), fn {value, index}, raster ->
      x0 = index * band
      x1 = min(w - 1, x0 + max(1, band - 1) - 1)
      vy = round(y_px(value, lo, hi, h))
      {top, bottom} = if vy <= base_y, do: {vy, base_y}, else: {base_y, vy}
      Draw.fill_rect(raster, {x0, top}, {x1, bottom}, spec.color)
    end)
  end

  defp build_scatter(points, spec, w, h) do
    {xlo, xhi} = bounds(Enum.map(points, &point_x/1))
    {ylo, yhi} = bounds(Enum.map(points, &point_y/1))

    Enum.reduce(points, Raster.new(w, h), fn point, raster ->
      px = round(lin(point_x(point), xlo, xhi, w))
      py = round(y_px(point_y(point), ylo, yhi, h))
      Draw.fill_rect(raster, {px - 1, py - 1}, {px + 1, py + 1}, spec.color)
    end)
  end

  @min_candle_band 3

  defp visible_tail(items, w, min_band) do
    capacity = max(1, div(w, min_band))

    if length(items) <= capacity, do: items, else: Enum.take(items, -capacity)
  end

  defp visible_candles(candles, w), do: visible_tail(candles, w, @min_candle_band)

  defp build_candlestick(all_candles, w, h) do
    candles = visible_candles(all_candles, w)
    highs = Enum.map(candles, fn {_o, high, _l, _c} -> high end)
    lows = Enum.map(candles, fn {_o, _h, low, _c} -> low end)
    {lo, hi} = bounds(highs ++ lows)
    band = max(@min_candle_band, div(w, length(candles)))

    candles
    |> Enum.with_index()
    |> Enum.reduce(Raster.new(w, h), fn {{open, high, low, close}, index}, raster ->
      cx = index * band + div(band, 2)
      color = if close >= open, do: @up_color, else: @down_color
      body_a = round(y_px(open, lo, hi, h))
      body_b = round(y_px(close, lo, hi, h))
      {bt, bb} = {min(body_a, body_b), max(body_a, body_b)}
      half = max(1, div(band, 3))

      raster
      |> Draw.line({cx, round(y_px(high, lo, hi, h))}, {cx, round(y_px(low, lo, hi, h))}, color)
      |> Draw.fill_rect({max(0, cx - half), bt}, {min(w - 1, cx + half), max(bb, bt + 1)}, color)
    end)
  end

  defp build_pie(slices, w, h) do
    total = slices |> Enum.map(&elem(&1, 0)) |> Enum.sum() |> max(1) |> Kernel.*(1.0)
    ranges = pie_ranges(slices, total)
    cx = w / 2
    cy = h / 2
    radius = min(w, h) / 2 - 1

    reach = radius * radius
    left = max(0, ceil(cx - radius))
    right = min(w - 1, floor(cx + radius))
    top = max(0, ceil(cy - radius))
    bottom = min(h - 1, floor(cy + radius))

    for y <- top..bottom//1, x <- left..right//1, reduce: Raster.new(w, h) do
      raster ->
        dx = x - cx
        dy = y - cy

        if dx * dx + dy * dy <= reach do
          Raster.put_pixel(raster, x, y, slice_color_at(ranges, pixel_angle(dx, dy)))
        else
          raster
        end
    end
  end

  defp pie_ranges(slices, total) do
    {ranges, _} =
      Enum.reduce(slices, {[], 0.0}, fn {value, color}, {acc, start} ->
        sweep = value / total * 2 * :math.pi()
        {[{start, start + sweep, color} | acc], start + sweep}
      end)

    Enum.reverse(ranges)
  end

  defp pixel_angle(dx, dy) do
    angle = :math.atan2(dy, dx)
    if angle < 0, do: angle + 2 * :math.pi(), else: angle
  end

  defp slice_color_at(ranges, angle) do
    Enum.find_value(ranges, fn {start, stop, color} ->
      if angle >= start and angle < stop, do: color
    end) || elem(List.last(ranges), 2)
  end

  defp build_gauge(value, fill, track, w, h) do
    cx = w / 2
    cy = h - 1
    outer = min(w / 2, h) - 1
    inner = outer * 0.74
    threshold = :math.pi() * (1 - clamp(value * 1.0, 0.0, 1.0))

    for y <- 0..(h - 1)//1, x <- 0..(w - 1)//1, reduce: Raster.new(w, h) do
      raster ->
        paint_gauge_pixel(raster, {x, y}, {cx, cy}, {inner, outer}, threshold, fill, track)
    end
  end

  defp paint_gauge_pixel(raster, {x, y}, {cx, cy}, {inner, outer}, threshold, fill, track) do
    dx = x - cx
    dy = cy - y
    dist2 = dx * dx + dy * dy

    if dy >= 0 and dist2 >= inner * inner and dist2 <= outer * outer do
      color = if :math.atan2(dy, dx) >= threshold, do: fill, else: track
      Raster.put_pixel(raster, x, y, color)
    else
      raster
    end
  end

  defp build_multi_line(series, spec, w, h) do
    {lo, hi} = range(List.flatten(series), spec)
    colors = palette_colors(spec)

    series
    |> Enum.with_index()
    |> Enum.reduce(Raster.new(w, h), fn {values, si}, raster ->
      points =
        values |> float_points(w, h, lo, hi) |> Enum.map(fn {x, y} -> {round(x), round(y)} end)

      Draw.polyline(raster, points, color_at(colors, si))
    end)
  end

  defp build_multi_area(series, spec, w, h) do
    {lo, hi} = range(List.flatten(series), spec)
    colors = palette_colors(spec)
    baseline = h - 1

    series
    |> Enum.with_index()
    |> Enum.reduce(Raster.new(w, h), fn {values, si}, raster ->
      color = color_at(colors, si)
      points = float_points(values, w, h, lo, hi)

      raster
      |> fill_under(points, baseline, fade(color, spec.fill_opacity || 0.4))
      |> Draw.polyline(Enum.map(points, fn {x, y} -> {round(x), round(y)} end), color)
    end)
  end

  defp build_stacked_area(series, spec, w, h) do
    colors = palette_colors(spec)
    groups = series |> Enum.map(&length/1) |> Enum.max()
    padded = Enum.map(series, &(&1 ++ List.duplicate(0, groups - length(&1))))
    totals = Enum.zip_with(padded, &Enum.sum/1)
    lo = Map.get(spec, :min) || 0
    hi = Map.get(spec, :max) || Enum.max([1 | totals])
    scale = {groups, w, h, lo, hi}

    {raster, _cum} =
      padded
      |> Enum.with_index()
      |> Enum.reduce({Raster.new(w, h), List.duplicate(0.0, groups)}, fn {values, si},
                                                                         {acc, cum} ->
        new_cum = Enum.zip_with(cum, values, &(&1 + &2))
        top = stack_points(new_cum, scale)
        bottom = stack_points(cum, scale)
        {fill_band(acc, top, bottom, color_at(colors, si)), new_cum}
      end)

    raster
  end

  defp stack_points(values, {groups, w, h, lo, hi}) do
    values
    |> Enum.with_index()
    |> Enum.map(fn {value, g} -> {x_index(g, groups, w), y_px(value, lo, hi, h)} end)
  end

  defp fill_band(raster, top, bottom, color) do
    columns =
      Enum.zip(top, bottom)
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.flat_map(fn [{{tx1, ty1}, {_b1x, by1}}, {{tx2, ty2}, {_b2x, by2}}] ->
        band_columns({round(tx1), ty1, by1}, {round(tx2), ty2, by2})
      end)

    Draw.fill_columns(raster, columns, color)
  end

  defp band_columns({xa, ta, ba}, {xb, tb, bb}) do
    for col <- xa..xb do
      {col, round(interp_y(xa, ta, xb, tb, col)), round(interp_y(xa, ba, xb, bb, col))}
    end
  end

  defp interp_y(xa, ya, xb, _yb, _col) when xb == xa, do: ya
  defp interp_y(xa, ya, xb, yb, col), do: ya + (yb - ya) * (col - xa) / (xb - xa)

  defp build_step(values, spec, w, h) do
    {lo, hi} = range(values, spec)

    points =
      values |> float_points(w, h, lo, hi) |> Enum.map(fn {x, y} -> {round(x), round(y)} end)

    Draw.polyline(Raster.new(w, h), step_points(points), spec.color)
  end

  defp build_grouped_bar(series, spec, w, h, :clustered) do
    colors = palette_colors(spec)
    nseries = length(series)
    groups = series |> Enum.map(&length/1) |> Enum.max()
    {lo, hi} = bar_range(List.flatten(series))
    base_y = round(y_px(clamp(0.0, lo, hi), lo, hi, h))
    group_w = max(nseries, div(w, max(1, groups)))
    bar_w = max(1, div(group_w, nseries))

    for group <- 0..(groups - 1)//1,
        {values, si} <- Enum.with_index(series),
        reduce: Raster.new(w, h) do
      raster ->
        case Enum.at(values, group) do
          nil ->
            raster

          value ->
            x0 = group * group_w + si * bar_w
            x1 = min(w - 1, x0 + max(1, bar_w - 1) - 1)
            {top, bottom} = minmax2(round(y_px(value, lo, hi, h)), base_y)
            Draw.fill_rect(raster, {x0, top}, {x1, bottom}, color_at(colors, si))
        end
    end
  end

  defp build_grouped_bar(series, spec, w, h, :stacked) do
    colors = palette_colors(spec)
    groups = series |> Enum.map(&length/1) |> Enum.max()

    totals =
      for g <- 0..(groups - 1)//1, do: Enum.reduce(series, 0, &(&2 + (Enum.at(&1, g) || 0)))

    hi = Enum.max([1 | totals])
    band = max(1, div(w, max(1, groups)))

    Enum.reduce(0..(groups - 1)//1, Raster.new(w, h), fn group, base_raster ->
      x0 = group * band
      x1 = min(w - 1, x0 + max(1, band - 1) - 1)

      {raster, _acc} =
        series
        |> Enum.with_index()
        |> Enum.reduce({base_raster, 0.0}, fn {values, si}, {raster, acc} ->
          value = Enum.at(values, group) || 0
          y_top = round(y_px(acc + value, 0, hi, h))
          y_bot = round(y_px(acc, 0, hi, h))
          {Draw.fill_rect(raster, {x0, y_top}, {x1, y_bot}, color_at(colors, si)), acc + value}
        end)

      raster
    end)
  end

  defp build_range_bar(all_pairs, spec, w, h) do
    pairs = visible_tail(all_pairs, w, 1)
    {lo, hi} = bounds(Enum.flat_map(pairs, fn {l, r} -> [l, r] end))
    band = max(1, div(w, length(pairs)))

    pairs
    |> Enum.with_index()
    |> Enum.reduce(Raster.new(w, h), fn {{low, high}, index}, raster ->
      x0 = index * band
      x1 = min(w - 1, x0 + max(1, band - 1) - 1)

      Draw.fill_rect(
        raster,
        {x0, round(y_px(high, lo, hi, h))},
        {x1, round(y_px(low, lo, hi, h))},
        spec.color
      )
    end)
  end

  defp build_multi_scatter(series, spec, w, h) do
    colors = palette_colors(spec)
    points = Enum.concat(series)
    {xlo, xhi} = bounds(Enum.map(points, &point_x/1))
    {ylo, yhi} = bounds(Enum.map(points, &point_y/1))

    series
    |> Enum.with_index()
    |> Enum.reduce(Raster.new(w, h), fn {pts, si}, base_raster ->
      color = color_at(colors, si)

      Enum.reduce(pts, base_raster, fn point, raster ->
        px = round(lin(point_x(point), xlo, xhi, w))
        py = round(y_px(point_y(point), ylo, yhi, h))
        Draw.fill_rect(raster, {px - 1, py - 1}, {px + 1, py + 1}, color)
      end)
    end)
  end

  defp build_bubble(points, spec, w, h) do
    {xlo, xhi} = bounds(Enum.map(points, &point_x/1))
    {ylo, yhi} = bounds(Enum.map(points, &point_y/1))
    {_, wmax} = bounds(Enum.map(points, &point_weight/1))

    Enum.reduce(points, Raster.new(w, h), fn point, raster ->
      px = round(lin(point_x(point), xlo, xhi, w))
      py = round(y_px(point_y(point), ylo, yhi, h))
      radius = max(1, round(point_weight(point) / max(1, wmax) * 6))
      fill_disc(raster, {px, py}, radius, spec.color)
    end)
  end

  defp build_histogram(values, spec, w, h) do
    bins = values |> length() |> min(40) |> max(5)
    {lo, hi} = bounds(values)
    counts = histogram_counts(values, lo, hi, bins)
    cmax = Enum.max([1 | counts])
    band = max(1, div(w, bins))
    base_y = h - 1

    counts
    |> Enum.with_index()
    |> Enum.reduce(Raster.new(w, h), fn {count, index}, raster ->
      x0 = index * band
      x1 = min(w - 1, x0 + max(1, band - 1) - 1)
      top = round((1 - count / cmax) * (h - 1))
      Draw.fill_rect(raster, {x0, top}, {x1, base_y}, spec.color)
    end)
  end

  defp build_heatmap(rows, w, h) do
    nrows = length(rows)
    ncols = rows |> Enum.map(&length/1) |> Enum.max()
    {lo, hi} = bounds(List.flatten(rows))
    cell_w = max(1, div(w, ncols))
    cell_h = max(1, div(h, nrows))

    rows
    |> Enum.with_index()
    |> Enum.reduce(Raster.new(w, h), fn {row, ry}, base_raster ->
      row
      |> Enum.with_index()
      |> Enum.reduce(base_raster, fn {value, cx}, raster ->
        x0 = cx * cell_w
        y0 = ry * cell_h

        Draw.fill_rect(
          raster,
          {x0, y0},
          {min(w - 1, x0 + cell_w - 1), min(h - 1, y0 + cell_h - 1)},
          heat_color(value, lo, hi)
        )
      end)
    end)
  end

  defp classify(data) do
    cond do
      not is_list(data) or data == [] ->
        :empty

      value?(hd(data)) ->
        {:single, Enum.map(data, &to_value/1)}

      value_list?(hd(data)) ->
        {:multi, data |> Enum.filter(&value_list?/1) |> Enum.map(&to_values/1)}

      true ->
        :empty
    end
  end

  defp value?(n) when is_number(n), do: true
  defp value?({v, _weight}) when is_number(v), do: true
  defp value?(_other), do: false

  defp to_value(n) when is_number(n), do: n
  defp to_value({v, _weight}) when is_number(v), do: v
  defp to_value(_other), do: 0

  defp value_list?([head | _]), do: value?(head)
  defp value_list?(_other), do: false

  defp to_values(list), do: Enum.map(list, &to_value/1)

  defp number_list?([n | _]) when is_number(n), do: true
  defp number_list?(_other), do: false

  defp scatter_series(data) when not is_list(data), do: :empty
  defp scatter_series([]), do: :empty

  defp scatter_series([first | _] = data) do
    cond do
      point?(first) -> {:single, scatter_points(data)}
      is_number(first) -> {:single, indexed_points(data)}
      is_list(first) -> nested_series(first, data)
      true -> :empty
    end
  end

  defp nested_series(first, data) do
    cond do
      Enum.any?(first, &point?/1) -> {:multi, Enum.map(data, &scatter_points/1)}
      Enum.all?(first, &is_number/1) -> {:multi, Enum.map(data, &indexed_points/1)}
      true -> :empty
    end
  end

  defp indexed_points(values) do
    values
    |> Enum.filter(&is_number/1)
    |> Enum.with_index()
    |> Enum.map(fn {value, index} -> {index, value} end)
  end

  defp ranges(data) when is_list(data),
    do: data |> Enum.map(&range_pair/1) |> Enum.reject(&is_nil/1)

  defp ranges(_data), do: []

  defp range_pair([lo, hi]) when is_number(lo) and is_number(hi), do: {lo, hi}
  defp range_pair({lo, hi}) when is_number(lo) and is_number(hi), do: {lo, hi}
  defp range_pair(_other), do: nil

  defp grid(data) when is_list(data), do: Enum.filter(data, &number_list?/1)
  defp grid(_data), do: []

  defp palette_colors(spec) do
    case Map.get(spec, :colors) do
      list when is_list(list) and list != [] -> Enum.map(list, &rgba/1)
      _ -> @palette
    end
  end

  defp rgba({r, g, b}), do: {r, g, b, 255}
  defp rgba({r, g, b, a}), do: {r, g, b, a}
  defp rgba(_other), do: {180, 180, 180, 255}

  defp color_at(colors, index), do: Enum.at(colors, rem(index, length(colors)))

  defp float_points(values, w, h, lo, hi) do
    count = length(values)

    values
    |> Enum.with_index()
    |> Enum.map(fn {value, index} -> {x_index(index, count, w), y_px(value, lo, hi, h)} end)
  end

  defp x_index(_index, 1, _w), do: 0.0
  defp x_index(index, count, w), do: index * (w - 1) / (count - 1)

  defp step_points([]), do: []

  defp step_points([first | rest]) do
    {points, _} =
      Enum.reduce(rest, {[first], first}, fn {x, y}, {acc, {_px, py}} ->
        {[{x, y}, {x, py} | acc], {x, y}}
      end)

    Enum.reverse(points)
  end

  defp fill_under(raster, points, baseline, color) do
    columns =
      points
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.flat_map(fn [a, b] -> segment_columns(a, b, baseline) end)

    Draw.fill_columns(raster, columns, color)
  end

  defp segment_columns({x1, y1}, {x2, y2}, baseline) do
    xa = round(x1)
    xb = round(x2)

    for col <- xa..xb do
      t = if xb == xa, do: y1, else: y1 + (y2 - y1) * (col - xa) / (xb - xa)
      {col, round(t), baseline}
    end
  end

  defp fill_disc(raster, {cx, cy}, radius, color) do
    spans =
      for dy <- -radius..radius do
        span = round(:math.sqrt(max(0, radius * radius - dy * dy)))
        {cy + dy, cx - span, cx + span}
      end

    Raster.fill_spans(raster, spans, color)
  end

  defp fade({r, g, b, a}, opacity),
    do: {round(r * opacity), round(g * opacity), round(b * opacity), a}

  defp minmax2(a, b), do: {min(a, b), max(a, b)}

  defp bar_range([]), do: {0.0, 1.0}

  defp bar_range(values) do
    lo = min(0.0, Enum.min(values))
    hi = Enum.max(values)
    if hi == lo, do: {lo, lo + 1}, else: {lo, hi}
  end

  defp histogram_counts(values, lo, hi, bins) do
    width = (hi - lo) / bins

    Enum.reduce(values, List.duplicate(0, bins), fn value, acc ->
      index = if width == 0, do: 0, else: min(bins - 1, trunc((value - lo) / width))
      List.update_at(acc, index, &(&1 + 1))
    end)
  end

  defp heat_color(value, lo, hi) do
    t = if hi == lo, do: 0.0, else: (value - lo) / (hi - lo)
    {round(40 + t * 200), round(70 + t * 60 - t * t * 50), round(150 - t * 110), 255}
  end

  defp point_weight(%{weight: weight}), do: weight
  defp point_weight([_x, _y, weight | _]), do: weight
  defp point_weight({_x, _y, weight}), do: weight
  defp point_weight(_other), do: 1

  defp range(values, spec) do
    lo = Map.get(spec, :min) || Enum.min(values)
    hi = Map.get(spec, :max) || Enum.max(values)
    if hi == lo, do: {lo, lo + 1}, else: {lo, hi}
  end

  defp bounds([]), do: {0.0, 1.0}

  defp bounds(list) do
    lo = Enum.min(list)
    hi = Enum.max(list)
    if hi == lo, do: {lo, lo + 1}, else: {lo, hi}
  end

  defp y_px(value, lo, hi, h), do: (hi - value) / (hi - lo) * (h - 1)
  defp lin(value, lo, hi, span), do: (value - lo) / (hi - lo) * (span - 1)
  defp clamp(value, lo, hi), do: value |> max(lo) |> min(hi)

  defp numbers([first | _] = data) when is_number(first), do: data
  defp numbers(_data), do: []

  defp scatter_points(data) when is_list(data), do: Enum.filter(data, &point?/1)
  defp scatter_points(_data), do: []

  defp point?([x, y | _]) when is_number(x) and is_number(y), do: true
  defp point?(%{x: x, y: y}) when is_number(x) and is_number(y), do: true
  defp point?({x, y}) when is_number(x) and is_number(y), do: true
  defp point?({x, y, _w}) when is_number(x) and is_number(y), do: true
  defp point?(_other), do: false

  defp point_x(%{x: x}), do: x
  defp point_x([x, _y | _]), do: x
  defp point_x({x, _y}), do: x
  defp point_x({x, _y, _w}), do: x
  defp point_y(%{y: y}), do: y
  defp point_y([_x, y | _]), do: y
  defp point_y({_x, y}), do: y
  defp point_y({_x, y, _w}), do: y

  defp candles(data) when is_list(data), do: data |> Enum.map(&candle/1) |> Enum.reject(&is_nil/1)
  defp candles(_data), do: []

  defp candle([o, h, l, c]) when is_number(o), do: {o, h, l, c}
  defp candle(%{open: o, high: h, low: l, close: c}), do: {o, h, l, c}
  defp candle(_other), do: nil

  defp rows_to_strips(rows) do
    Enum.map(rows, fn row ->
      Strip.new(
        Enum.map(row, fn
          {glyph, nil} -> Segment.new(glyph)
          {glyph, {r, g, b}} -> Segment.new(glyph, %{fg: {r, g, b}})
        end)
      )
    end)
  end

  defp cells_to_strips(rows), do: Enum.map(rows, &Strip.from_cells/1)

  defp fit_rows(strips, rows, cols) do
    sized = Enum.map(strips, &Strip.fit_to_width(&1, cols))
    blank = Strip.new([Segment.new(String.duplicate(" ", cols))])

    if length(sized) >= rows do
      Enum.take(sized, rows)
    else
      sized ++ List.duplicate(blank, rows - length(sized))
    end
  end
end
