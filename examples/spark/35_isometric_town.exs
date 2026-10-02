Mix.install(
  [
    {:drafter, path: Path.join(__DIR__, "../..")},
    {:french_curve, path: Path.join(__DIR__, "../../../french_curve"), override: true},
    {:linocut, path: Path.join(__DIR__, "../../../cauldron/linocut")},
    {:gamepad, path: Path.join(__DIR__, "../../../gamepad")}
  ],
  consolidate_protocols: false
)

defmodule IsoTown.Pics do
  @textures %{
    grass: """
    G #4a8a3c
    g #437f37
    b #56984a
    d #3b7030

    GGGGGgGGGGbGGGGG
    GgGGGGGGGGGGGGgG
    GGGGGGGdGGGGGGGG
    GGGbGGGGGGGgGGGG
    GGGGGGGGGGGGGGGG
    GGGGGGgGGGdGGGGG
    GdGGGGGGGGGGGGbG
    GGGGGGGGGGGGGGGG
    GGGGbGGGGgGGGGGG
    GGGGGGGGGGGGGGGG
    GGgGGGGGGGGGGdGG
    GGGGGGGdGGbGGGGG
    GGGGGGGGGGGGGGGG
    GbGGGGGGGGGGgGGG
    GGGGGgGGGGGGGGGG
    GGGGGGGGGGdGGGGG
    """,
    road: """
    A #4a4a50
    a #45454b
    c #52525a

    AAAAaAAAAAAAcAAA
    AAaAAAAAAAAAAAAA
    AAAAAAAAcAAAAAAA
    AcAAAAAAAAAAaAAA
    AAAAAAAAAAAAAAAA
    AAAAAAaAAAAAAAcA
    AAAAAAAAAAAAAAAA
    AAAcAAAAAaAAAAAA
    AAAAAAAAAAAAAAAA
    AaAAAAAAAAAAcAAA
    AAAAAAAAAAAAAAAA
    AAAAAcAAAaAAAAAA
    AAAAAAAAAAAAAAAA
    AAAAAAAAAAAAAAaA
    AAcAAAAaAAAAAAAA
    AAAAAAAAAAAAAAAA
    """,
    cobble: """
    M #6d6a64
    S #8c887f
    s #7f7b73
    h #9a968c

    MMMMMMMMMMMMMMMM
    MSSSMSsSMSSSMShS
    MShSMSSSMSsSMSSS
    MSSSMSSSMSSSMSSS
    MMMMMMMMMMMMMMMM
    SSMSSSMSSSMSSSMS
    sSMShSMSSSMSsSMS
    SSMSSSMSSSMSSSMS
    MMMMMMMMMMMMMMMM
    MSSSMSSSMSsSMSSS
    MSsSMShSMSSSMShS
    MSSSMSSSMSSSMSSS
    MMMMMMMMMMMMMMMM
    SSMSSSMShSMSSSMS
    hSMSsSMSSSMSSSMS
    SSMSSSMSSSMSSSMS
    """,
    water: """
    W #2f6fb5
    w #2a64a6
    L #5c9ee0

    WWWWWWWWWWWWWWWW
    WWLLWWWWWWWLLWWW
    WWWWWWWWWWWWWWWW
    WWWWWWLLLWWWWWWW
    WwWWWWWWWWWWWwWW
    WWWWWWWWWWWWWWWW
    WWWLLWWWWWLLWWWW
    WWWWWWWWWWWWWWWW
    WWWWWWWwWWWWWWWW
    WLLWWWWWWWWWWLLW
    WWWWWWWWWWWWWWWW
    WWWWWWLLWWWWWWWW
    WWwWWWWWWWWwWWWW
    WWWWWWWWWWWWWWWW
    WWWWLLWWWWLLLWWW
    WWWWWWWWWWWWWWWW
    """,
    dirt: """
    D #8a6a44
    d #7d5f3c
    e #97764e

    DDDDdDDDDDDeDDDD
    DDDDDDDDDDDDDDDD
    DeDDDDDDdDDDDDDD
    DDDDDDDDDDDDDDeD
    DDDDDdDDDDDDDDDD
    DDDDDDDDDDDdDDDD
    DDeDDDDDDDDDDDDD
    DDDDDDDeDDDDDDDD
    DDDDDDDDDDDDDdDD
    DdDDDDDDDDeDDDDD
    DDDDDDDDDDDDDDDD
    DDDDDeDDDDDDDDDD
    DDDDDDDDDdDDDDDD
    DDDDDDDDDDDDDeDD
    DeDDDDDDDDDDDDDD
    DDDDDDDdDDDDDDDD
    """,
    plaster: """
    C #e8dcc0
    c #ddd0b2
    K #6b4a2e

    KKKKKKKKKKKKKKKK
    CCCCCCCCCCCCCCCC
    CCCCCCCcCCCCCCCC
    CCCCCCCCCCCCCCCC
    CCcCCCCCCCCCCcCC
    CCCCCCCCCCCCCCCC
    CCCCCCCCCCcCCCCC
    CCCCCCCCCCCCCCCC
    CCCCCcCCCCCCCCCC
    CCCCCCCCCCCCCCCC
    CCCCCCCCCCCCCcCC
    CCCcCCCCCCCCCCCC
    CCCCCCCCCCCCCCCC
    CCCCCCCCCcCCCCCC
    CCCCCCCCCCCCCCCC
    CCCCCCCCCCCCCCCC
    """,
    plaster_window: """
    C #e8dcc0
    K #6b4a2e
    B #6f9fd6
    b #8fb8e8

    KKKKKKKKKKKKKKKK
    CCCCCCCCCCCCCCCC
    CCCCCCCCCCCCCCCC
    CCCCCCCCCCCCCCCC
    CCCCKKKKKKKCCCCC
    CCCCKbBKbBKCCCCC
    CCCCKBBKBBKCCCCC
    CCCCKKKKKKKCCCCC
    CCCCKBBKBBKCCCCC
    CCCCKBBKBBKCCCCC
    CCCCKKKKKKKCCCCC
    CCCCCCCCCCCCCCCC
    CCCCCCCCCCCCCCCC
    CCCCCCCCCCCCCCCC
    CCCCCCCCCCCCCCCC
    CCCCCCCCCCCCCCCC
    """,
    plaster_door: """
    C #e8dcc0
    K #6b4a2e
    O #7a4a22
    o #8f5a2c
    Y #d9b34a

    KKKKKKKKKKKKKKKK
    CCCCCCCCCCCCCCCC
    CCCCCCCCCCCCCCCC
    CCCCCCCCCCCCCCCC
    CCCCCCCCCCCCCCCC
    CCCCCCOOOOCCCCCC
    CCCCCOOooOOCCCCC
    CCCCCOoOOoOCCCCC
    CCCCCOoOOoOCCCCC
    CCCCCOoOOoOCCCCC
    CCCCCOoOOoOCCCCC
    CCCCCOoOYoOCCCCC
    CCCCCOoOOoOCCCCC
    CCCCCOoOOoOCCCCC
    CCCCCOoOOoOCCCCC
    CCCCCOOOOOOCCCCC
    """,
    brick: """
    R #9a4a3a
    r #8e4234
    m #c9b8a0

    RRRRRRRmRRRRRRRR
    RRRrRRRmRRRRrRRR
    RRRRRRRmRRRRRRRR
    mmmmmmmmmmmmmmmm
    RRRmRRRRRRRmRRRR
    RRRmRRrRRRRmRRrR
    RRRmRRRRRRRmRRRR
    mmmmmmmmmmmmmmmm
    RRRRRRRmRRRRRRRR
    RrRRRRRmRRRrRRRR
    RRRRRRRmRRRRRRRR
    mmmmmmmmmmmmmmmm
    RRRmRRRRRRRmRRRR
    RRRmRRRRrRRmRRRR
    RRRmRRRRRRRmRRRR
    mmmmmmmmmmmmmmmm
    """,
    brick_window: """
    R #9a4a3a
    m #c9b8a0
    K #3a2a1e
    B #6f9fd6
    b #8fb8e8

    RRRRRRRmRRRRRRRR
    RRRRRRRmRRRRRRRR
    RRRRRRRmRRRRRRRR
    mmmmmmmmmmmmmmmm
    RRRmKKKKKKKmRRRR
    RRRmKbBKbBKmRRRR
    RRRmKBBKBBKmRRRR
    mmmmKKKKKKKmmmmm
    RRRRKBBKBBKRRRRR
    RRRRKBBKBBKRRRRR
    RRRRKKKKKKKRRRRR
    mmmmmmmmmmmmmmmm
    RRRmRRRRRRRmRRRR
    RRRmRRRRRRRmRRRR
    RRRmRRRRRRRmRRRR
    mmmmmmmmmmmmmmmm
    """,
    brick_door: """
    R #9a4a3a
    m #c9b8a0
    O #5a3a1a
    o #6e4622
    Y #d9b34a

    RRRRRRRmRRRRRRRR
    RRRRRRRmRRRRRRRR
    RRRRRRRmRRRRRRRR
    mmmmmmmmmmmmmmmm
    RRRmRRRRRRRmRRRR
    RRRmRROOOORRmRRR
    RRRmROOooOORmRRR
    mmmmmOoOOoOmmmmm
    RRRRROoOOoORRRRR
    RRRRROoOOoORRRRR
    RRRRROoOOoORRRRR
    mmmmmOoOYoOmmmmm
    RRRmROoOOoORmRRR
    RRRmROoOOoORmRRR
    RRRmROoOOoORmRRR
    mmmmmOOOOOOmmmmm
    """,
    shop_front: """
    E #d9483b
    W #f2ece0
    K #6b4a2e
    B #6f9fd6
    b #8fb8e8
    C #e8dcc0

    EEWWEEWWEEWWEEWW
    EEWWEEWWEEWWEEWW
    EEWWEEWWEEWWEEWW
    EEWWEEWWEEWWEEWW
    CCCCCCCCCCCCCCCC
    CKKKKKKKKKKKKKKC
    CKbBBBBKBBBBBbKC
    CKBBBBBKBBBBBBKC
    CKBBBBBKBBBBBBKC
    CKBBBBBKBBBBBBKC
    CKBBBBBKBBBBBBKC
    CKKKKKKKKKKKKKKC
    CCCCCCCCCCCCCCCC
    CCCCCCCCCCCCCCCC
    CCCCCCCCCCCCCCCC
    CCCCCCCCCCCCCCCC
    """,
    stone: """
    S #8a8f96
    s #7d8289
    t #9aa0a7
    n #5f646b

    SSSSSSSnSSSSSSSS
    SStSSSSnSSSsSSSS
    SSSSSSSnSSSSSSSS
    nnnnnnnnnnnnnnnn
    SSSnSSSSSSSnSSSS
    SsSnSSStSSSnSSSS
    SSSnSSSSSSSnSSSS
    nnnnnnnnnnnnnnnn
    SSSSSSSnSSSSSSSS
    SSSSStSnSSsSSSSS
    SSSSSSSnSSSSSSSS
    nnnnnnnnnnnnnnnn
    SSSnSSSSSSSnSSSS
    SSSnSsSSSSSnStSS
    SSSnSSSSSSSnSSSS
    nnnnnnnnnnnnnnnn
    """,
    stone_gate: """
    S #8a8f96
    n #5f646b
    N #2a2c30

    SSSSSSSnSSSSSSSS
    SSSSSSSnSSSSSSSS
    SSSSSSSnSSSSSSSS
    nnnnnnnnnnnnnnnn
    SSSnSSNNNNSnSSSS
    SSSnSNNNNNNnSSSS
    SSSnSNNNNNNnSSSS
    nnnnnNNNNNNnnnnn
    SSSSSNNNNNNSSSSS
    SSSSSNNNNNNSSSSS
    SSSSSNNNNNNSSSSS
    nnnnnNNNNNNnnnnn
    SSSnSNNNNNNnSSSS
    SSSnSNNNNNNnSSSS
    SSSnSNNNNNNnSSSS
    nnnnnNNNNNNnnnnn
    """,
    stone_top: """
    S #7a7f86
    t #8a9096

    SSSSSSSSSSSSSSSS
    SStSSSSSSSSStSSS
    SSSSSSSSSSSSSSSS
    SSSSSStSSSSSSSSS
    SSSSSSSSSSSSSSSS
    StSSSSSSSSSSSSSt
    SSSSSSSSSSStSSSS
    SSSSSSSSSSSSSSSS
    SSSStSSSSSSSSSSS
    SSSSSSSSStSSSSSS
    SSSSSSSSSSSSSSSS
    SSSSSSSSSSSSSStS
    SStSSSSSSSSSSSSS
    SSSSSSSStSSSSSSS
    SSSSSSSSSSSSSSSS
    SSSSStSSSSSSSSSS
    """,
    roof_tile: """
    T #b5533c
    t #9e4733
    u #c9654a

    TTTTTTTTTTTTTTTT
    tttttttttttttttt
    TTuTTTTuTTTTuTTT
    TTTTTTTTTTTTTTTT
    tttttttttttttttt
    TTTTuTTTTuTTTTuT
    TTTTTTTTTTTTTTTT
    tttttttttttttttt
    TTuTTTTuTTTTuTTT
    TTTTTTTTTTTTTTTT
    tttttttttttttttt
    TTTTuTTTTuTTTTuT
    TTTTTTTTTTTTTTTT
    tttttttttttttttt
    TTuTTTTuTTTTuTTT
    TTTTTTTTTTTTTTTT
    """,
    roof_slate: """
    T #5a6a80
    t #4e5c70
    u #6d7e96

    TTTTTTTTTTTTTTTT
    tttttttttttttttt
    TTuTTTTuTTTTuTTT
    TTTTTTTTTTTTTTTT
    tttttttttttttttt
    TTTTuTTTTuTTTTuT
    TTTTTTTTTTTTTTTT
    tttttttttttttttt
    TTuTTTTuTTTTuTTT
    TTTTTTTTTTTTTTTT
    tttttttttttttttt
    TTTTuTTTTuTTTTuT
    TTTTTTTTTTTTTTTT
    tttttttttttttttt
    TTuTTTTuTTTTuTTT
    TTTTTTTTTTTTTTTT
    """
  }

  @props %{
    tree: """
    L #3f8a3a
    l #357a30
    h #5aa64e
    K #6b4a2e
    k #5a3c22

    .....LLLLLL.....
    ...LLLhLLLLLL...
    ..LLhhLLLLLLLL..
    .LLhLLLLLLlLLLL.
    .LLLLLLLLLLLlLL.
    LLhLLLLLLLLLLLLL
    LLLLLLLLllLLLLlL
    LLLLLLLLLLLLLLLL
    .LLLlLLLLLLLLLL.
    .LLLLLLLlLLLLhL.
    ..LLLLLLLLLlLL..
    ...LLlLLLLLLL...
    .....LLLLLL.....
    .......KK.......
    .......Kk.......
    .......Kk.......
    .......Kk.......
    .......Kk.......
    .......Kk.......
    .......Kk.......
    .......Kk.......
    .......Kk.......
    ......KKkk......
    .....KKKkkk.....
    """,
    pine: """
    P #2f6e3a
    p #27602f
    q #3d8448
    K #5a3c22

    .......PP.......
    ......PPPP......
    .....PPqPPP.....
    ....PPPPPPPP....
    ......PPPP......
    .....PPPqPPP....
    ....PPPPPPPPP...
    ...PPqPPPPPPPP..
    ..PPPPPPPPpPPPP.
    .....PPPPPPP....
    ....PPPPqPPPP...
    ...PPPPPPPPPPP..
    ..PPqPPPPPPpPPP.
    .PPPPPPPPPPPPPPP
    ....PPPPPPPPP...
    ...PPPPqPPPPPP..
    ..PPPPPPPPPpPPP.
    .PPPPPPPPPPPPPPP
    PPPqPPPPPPPPPpPP
    .......KK.......
    .......KK.......
    .......KK.......
    .......KK.......
    ......KKKK......
    """,
    lamp: """
    I #3a3a40
    i #55555c
    Y #ffd76a
    y #ffb63a

    ......IIII......
    .....IyYYyI.....
    .....IYYYYI.....
    .....IyYYyI.....
    ......IIII......
    .......II.......
    .......II.......
    .......ii.......
    .......II.......
    .......II.......
    .......ii.......
    .......II.......
    .......II.......
    .......ii.......
    .......II.......
    .......II.......
    .......ii.......
    .......II.......
    .......II.......
    .......II.......
    .......II.......
    ......IIII......
    .....IIIIII.....
    ....IIIIIIII....
    """,
    barrel: """
    O #8a5a2e
    o #74491f
    S #55555c

    ................
    ................
    ....OOOOOOOO....
    ...OOSSSSSSOO...
    ...OOOOOOOOOO...
    ...OoOOOOOOoO...
    ...OoOOOOOOoO...
    ...OOSSSSSSOO...
    ...OoOOOOOOoO...
    ...OoOOOOOOoO...
    ...OoOOOOOOoO...
    ...OOSSSSSSOO...
    ...OOOOOOOOOO...
    ....OOOOOOOO....
    ................
    ................
    """
  }

  @character %{
    front: """
    H #3a2a1a
    F #f0c8a0
    T #3a6fd0
    t #2f5cb0
    L #4a3a2a
    B #2a2018
    E #202020

    ................
    .....HHHHHH.....
    ....HHHHHHHH....
    ....HFFFFFFH....
    ....FFEFFEFF....
    .....FFFFFF.....
    ......FFFF......
    ....TTTTTTTT....
    ...TTTTTTTTTT...
    ...FTTTTTTTTF...
    ...FTTTttTTTF...
    ....TTTTTTTT....
    .....LLLLLL.....
    .....LL..LL.....
    .....LL..LL.....
    ....BBB..BBB....
    """,
    back: """
    H #3a2a1a
    F #f0c8a0
    T #3a6fd0
    t #2f5cb0
    L #4a3a2a
    B #2a2018

    ................
    .....HHHHHH.....
    ....HHHHHHHH....
    ....HHHHHHHH....
    ....HHHHHHHH....
    .....HHHHHH.....
    ......FFFF......
    ....TTTTTTTT....
    ...TTTTTTTTTT...
    ...FTTTTTTTTF...
    ...FTTTTTTTTF...
    ....TTTTTTTT....
    .....LLLLLL.....
    .....LL..LL.....
    .....LL..LL.....
    ....BBB..BBB....
    """,
    side: """
    H #3a2a1a
    F #f0c8a0
    T #3a6fd0
    t #2f5cb0
    L #4a3a2a
    B #2a2018
    E #202020

    ................
    .....HHHHHH.....
    ....HHHHHHHH....
    ....HHHFFFFF....
    ....HHFFEFFF....
    .....HFFFFF.....
    ......FFFF......
    .....TTTTTT.....
    .....TTTTTTT....
    .....TTTTTTF....
    .....TTTtTT.....
    .....TTTTTT.....
    .....LLLLLL.....
    .....LLLLLL.....
    ......LLLL......
    .....BBBBBB.....
    """
  }

  @hero_palette """
  H #2b1a10
  h #4a2e1a
  i #6b4530
  F #f1c9a5
  f #d9a67f
  E #1e1e24
  m #c46a6a
  T #3a6fd0
  t #2f5cb0
  u #5c8ce0
  B #5a3a1e
  Y #d9b34a
  L #3b3a4a
  l #2a2936
  S #2a2018
  s #3d3024
  """

  @hero %{
    front: """
    ......HHHHHHHH......
    ....HHhhhhhhhhHH....
    ...HhhhiihhhhhhhhH..
    ...HhhiihhhhhhhhhH..
    ...HhhhhhhhhhhhhhH..
    ...HhFFFFFFFFFFFhH..
    ...HFFFFFFFFFFFFFH..
    ....FFEEFFFFFEEFF...
    ....FFEEFFFFFEEFF...
    ....FFFFFFFFFFFFF...
    ....fFFFFFmmFFFFf...
    .....fFFFFFFFFFf....
    ......ffFFFFFff.....
    .....TTTTFFFTTTT....
    ...TTTuTTTTTTTuTTT..
    ..TTTTuTTTTTTTuTTTT.
    ..TTTTTTTTTTTTTTTTT.
    ..tTTTTTTTTTTTTTTTt.
    ..tTTTTTTTTTTTTTTTt.
    ..FFtTTTTTTTTTTTtFF.
    ..FF.BBBBBBYYBBBB.FF
    ..ff.LLLLLLLLLLLL.ff
    .....LLLLLLLLLLLL...
    .....LLLLLl.lLLLLL..
    .....LLLLL...LLLLL..
    .....lLLLL...LLLLl..
    ....SSSSSS...SSSSSS.
    ....SsSSSS...SSSSsS.
    """,
    back: """
    ......HHHHHHHH......
    ....HHhhhhhhhhHH....
    ...HhhhiihhhhhhhhH..
    ...HhhhhhhhhhhhhhH..
    ...HhhhhhhhhhhhhhH..
    ...HhhhhhhhhhhhhhH..
    ...HhhhhhhhhhhhhhH..
    ....HhhhhhhhhhhhH...
    ....HhhhhhhhhhhhH...
    .....HhhhhhhhhhH....
    .....hhhhhhhhhhh....
    ......fFFFFFFFf.....
    ......ffFFFFFff.....
    .....TTTTtttTTTT....
    ...TTTTTTTtTTTTTTT..
    ..TTTTTTTTtTTTTTTTT.
    ..TTTTTTTTtTTTTTTTT.
    ..tTTTTTTTtTTTTTTTt.
    ..tTTTTTTTtTTTTTTTt.
    ..FFtTTTTTtTTTTTtFF.
    ..FF.BBBBBBBBBBBB.FF
    ..ff.LLLLLLLLLLLL.ff
    .....LLLLLLLLLLLL...
    .....LLLLLl.lLLLLL..
    .....LLLLL...LLLLL..
    .....lLLLL...LLLLl..
    ....SSSSSS...SSSSSS.
    ....SSSSSS...SSSSSS.
    """,
    side: """
    ......HHHHHHHH......
    ....HHhhhhhhhhHH....
    ...HhhhhiihhhhhhhH..
    ...HhhhhhhhhhhhhhH..
    ...HhhhhhhhhFFFFFH..
    ...HhhhhhhFFFFFFFF..
    ...HhhhhhFFFFEEFFF..
    ....HhhhhFFFFEEFFF..
    ....HhhhhFFFFFFFFf..
    .....hhhhFFFFFFmf...
    ......ffFFFFFFff....
    .......fFFFFFf......
    ........fFFf........
    ......TTTTFFTTT.....
    .....TTTTTTTTTTTu...
    .....TTTTTTTTTTTTu..
    .....tTTTTTTTTTTTT..
    .....tTTTTTTTTTTTT..
    .....tTTTTTTTTTTTT..
    .....tTTTTTTTTTTFF..
    .....BBBBBBBYBBBFF..
    .....LLLLLLLLLLL.ff.
    .....LLLLLLLLLLL....
    .....LLLLLLLLLLL....
    ......LLLLlLLLL.....
    ......LLLLlLLLL.....
    .....SSSSSSSSSSS....
    .....SsSSSSSSSSSS...
    """
  }

  def textures, do: @textures
  def props, do: @props
  def poses, do: Map.keys(@character)

  def character(pose, tunic, shade) do
    @character
    |> Map.fetch!(pose)
    |> String.replace("T #3a6fd0", "T #{tunic}")
    |> String.replace("t #2f5cb0", "t #{shade}")
  end

  def hero(pose, tunic, shade) do
    palette =
      @hero_palette
      |> String.replace("T #3a6fd0", "T #{tunic}")
      |> String.replace("t #2f5cb0", "t #{shade}")
      |> String.replace("u #5c8ce0", "u #{lighten(tunic)}")

    palette <> "\n" <> Map.fetch!(@hero, pose)
  end

  defp lighten("#" <> hex) do
    {value, ""} = Integer.parse(hex, 16)

    channels =
      for shift <- [16, 8, 0] do
        channel = Bitwise.band(Bitwise.bsr(value, shift), 255)
        min(255, channel + div(255 - channel, 3))
      end

    "#" <> Enum.map_join(channels, &String.pad_leading(Integer.to_string(&1, 16), 2, "0"))
  end
end

defmodule IsoTown.Blit do
  alias FrenchCurve.Raster

  def frame(width, height, {red, green, blue}) do
    row = :binary.copy(<<red, green, blue, 255>>, width)
    Map.new(0..(height - 1)//1, &{&1, row})
  end

  def to_raster(rows, width, height) do
    Raster.from_rgba(
      width,
      height,
      IO.iodata_to_binary(for y <- 0..(height - 1)//1, do: Map.fetch!(rows, y))
    )
  end

  def crop(rows, {x0, y0}, {width, height}) do
    Map.new(0..(height - 1)//1, fn y ->
      {y, binary_part(Map.fetch!(rows, y0 + y), x0 * 4, width * 4)}
    end)
  end

  def blit(rows, %{runs: runs}, {x0, y0}, width, height) do
    Enum.reduce(runs, rows, fn {run_y, run_x, run}, acc ->
      y = y0 + run_y

      if y < 0 or y >= height do
        acc
      else
        case clip(x0 + run_x, run, width) do
          nil -> acc
          {x, segment} -> Map.update!(acc, y, &splice(&1, x, segment, width))
        end
      end
    end)
  end

  defp clip(x, run, width) do
    length = div(byte_size(run), 4)
    from = max(0, -x)
    to = min(length, width - x)

    if to > from, do: {x + from, binary_part(run, from * 4, (to - from) * 4)}, else: nil
  end

  defp splice(row, x, segment, width) do
    length = div(byte_size(segment), 4)

    <<binary_part(row, 0, x * 4)::binary, segment::binary,
      binary_part(row, (x + length) * 4, (width - x - length) * 4)::binary>>
  end

  def runs(%{width: width, height: height, rgba: rgba}) do
    Enum.flat_map(0..(height - 1)//1, fn y ->
      row = binary_part(rgba, y * width * 4, width * 4)
      pixels = for <<pixel::binary-size(4) <- row>>, do: pixel

      pixels
      |> Enum.with_index()
      |> Enum.chunk_by(&opaque?/1)
      |> Enum.filter(&opaque?(hd(&1)))
      |> Enum.map(fn [{_pixel, x} | _] = chunk ->
        {y, x, IO.iodata_to_binary(Enum.map(chunk, &solid/1))}
      end)
    end)
  end

  defp opaque?({<<_, _, _, alpha>>, _x}), do: alpha >= 128

  defp solid({<<red, green, blue, _>>, _x}), do: <<red, green, blue, 255>>

  def shrink(image, 1), do: image

  def shrink(%{width: width, height: height, rgba: rgba}, factor) do
    new_width = div(width, factor)
    new_height = div(height, factor)

    shrunk =
      for y <- 0..(new_height - 1)//1, x <- 0..(new_width - 1)//1, into: <<>> do
        binary_part(rgba, (y * factor * width + x * factor) * 4, 4)
      end

    %{width: new_width, height: new_height, rgba: shrunk}
  end

  def flip(%{width: width, height: height, rgba: rgba}) do
    flipped =
      for y <- 0..(height - 1)//1, x <- (width - 1)..0//-1, into: <<>> do
        binary_part(rgba, (y * width + x) * 4, 4)
      end

    %{width: width, height: height, rgba: flipped}
  end

  def plot(rows, x, y, {red, green, blue}, width, height)
      when x >= 0 and y >= 0 and x < width and y < height do
    Map.update!(rows, y, &splice(&1, x, <<red, green, blue, 255>>, width))
  end

  def plot(rows, _x, _y, _colour, _width, _height), do: rows

  def line(rows, {x0, y0}, {x1, y1}, colour, width, height) do
    steps = max(abs(x1 - x0), abs(y1 - y0))

    Enum.reduce(0..steps//1, rows, fn step, acc ->
      fraction = if steps == 0, do: 0, else: step / steps

      plot(
        acc,
        round(x0 + (x1 - x0) * fraction),
        round(y0 + (y1 - y0) * fraction),
        colour,
        width,
        height
      )
    end)
  end

  def polyline(rows, points, colour, width, height) do
    points
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(rows, fn [from, to], acc -> line(acc, from, to, colour, width, height) end)
  end
end

defmodule IsoTown.Ruler do
  @rules [:euclid, :dnd, :pathfinder]

  def rules, do: @rules

  def next(rule),
    do: Enum.at(@rules, rem(Enum.find_index(@rules, &(&1 == rule)) + 1, length(@rules)))

  def distance(:euclid, {ax, ay}, {bx, by}),
    do: :math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay))

  def distance(:dnd, {ax, ay}, {bx, by}), do: max(abs(bx - ax), abs(by - ay))

  def distance(:pathfinder, {ax, ay}, {bx, by}) do
    long = max(abs(bx - ax), abs(by - ay))
    short = min(abs(bx - ax), abs(by - ay))
    long + div(short, 2)
  end

  def label(:euclid, distance), do: "#{Float.round(distance * 1.0, 1)}"
  def label(_rule, distance), do: "#{distance}"
end

defmodule IsoTown.Path do
  alias IsoTown.World

  @steps [{1, 0}, {-1, 0}, {0, 1}, {0, -1}]

  def find(world, from, to) do
    if World.walkable?(world, centre(to)),
      do: search(world, :queue.from_list([from]), %{from => nil}, to),
      else: nil
  end

  defp search(world, queue, came_from, goal) do
    case :queue.out(queue) do
      {:empty, _} ->
        nil

      {{:value, ^goal}, _} ->
        unwind(came_from, goal, [])

      {{:value, {x, y} = current}, rest} ->
        {queue, came_from} =
          Enum.reduce(@steps, {rest, came_from}, fn {dx, dy}, {queue_acc, seen} ->
            next = {x + dx, y + dy}

            if Map.has_key?(seen, next) or not open?(world, current, {dx, dy}),
              do: {queue_acc, seen},
              else: {:queue.in(next, queue_acc), Map.put(seen, next, current)}
          end)

        search(world, queue, came_from, goal)
    end
  end

  defp open?(world, {x, y}, {dx, dy}) do
    World.walkable?(world, centre({x + dx, y + dy})) and
      (dx == 0 or dy == 0 or
         (World.walkable?(world, centre({x + dx, y})) and
            World.walkable?(world, centre({x, y + dy}))))
  end

  defp unwind(_came_from, nil, path), do: path

  defp unwind(came_from, cell, path),
    do: unwind(came_from, Map.fetch!(came_from, cell), [cell | path])

  def centre({x, y}), do: {x + 0.5, y + 0.5}
end

defmodule IsoTown.Walk do
  @clear <<0, 0, 0, 0>>

  def frame(image, _legs, frame) when frame in [0, 2], do: image
  def frame(image, legs, 1), do: step(image, legs, :left)
  def frame(image, legs, 3), do: step(image, legs, :right)

  defp step(%{width: width, height: height, rgba: rgba}, {band, lift}, planted) do
    half = div(width, 2)

    lifted =
      for y <- 0..(height - 1)//1, x <- 0..(width - 1)//1, into: <<>> do
        if planted?(x, y, half, band, planted),
          do: pixel(rgba, width, height, x, y),
          else: pixel(rgba, width, height, x, y + lift)
      end

    %{width: width, height: height, rgba: lifted}
  end

  defp planted?(x, y, half, band, :left), do: y >= band and x < half
  defp planted?(x, y, half, band, :right), do: y >= band and x >= half

  defp pixel(_rgba, _width, height, _x, y) when y >= height, do: @clear
  defp pixel(rgba, width, _height, x, y), do: binary_part(rgba, (y * width + x) * 4, 4)
end

defmodule IsoTown.Art do
  alias FrenchCurve.Raster
  alias IsoTown.{Blit, Pics, Walk}

  @table :iso_town_memo
  @fog {40, 44, 60}
  @fog_levels 16
  @tunics %{
    player: {"#3a6fd0", "#2f5cb0"},
    green: {"#2e9e4a", "#237d3a"},
    red: {"#d0453a", "#a8352d"},
    purple: {"#8a4fd0", "#6f3cab"},
    gold: {"#d9a52a", "#b3871f"}
  }
  @materials %{
    plaster: %{ground: :plaster, upper: :plaster_window, door: :plaster_door, roof: :roof_tile},
    brick: %{ground: :brick, upper: :brick_window, door: :brick_door, roof: :roof_slate},
    shop: %{ground: :plaster, upper: :plaster_window, door: :shop_front, roof: :roof_slate},
    stone: %{ground: :stone, upper: :stone, door: :stone_gate, roof: :stone_top}
  }

  def table, do: @table
  def fog_levels, do: @fog_levels
  def material(name), do: Map.fetch!(@materials, name)
  def tunics, do: Map.keys(@tunics) -- [:player]

  def install do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    end

    textures = Map.new(Pics.textures(), fn {name, text} -> {name, parse(text).rgba} end)
    props = Map.new(Pics.props(), fn {name, text} -> {name, text |> parse() |> magnify(name)} end)

    characters =
      for {tunic, {main, shade}} <- @tunics, pose <- Pics.poses(), into: %{} do
        {{tunic, pose}, parse(Pics.character(pose, main, shade))}
      end

    heroes =
      for {tunic, {main, shade}} <- @tunics, pose <- Pics.poses(), into: %{} do
        {{{:hero, tunic}, pose}, parse(Pics.hero(pose, main, shade))}
      end

    :persistent_term.put({__MODULE__, :textures}, textures)
    :persistent_term.put({__MODULE__, :sprites}, Map.merge(props, Map.merge(characters, heroes)))
    :ok
  end

  defp parse(text) do
    {:ok, raster} = Linocut.Pic.parse(text)
    %{width: raster.width, height: raster.height, rgba: Raster.to_rgba_binary(raster)}
  end

  @magnified [:tree, :pine]

  defp magnify(image, name) when name in @magnified do
    doubled =
      for y <- 0..(image.height * 2 - 1)//1, x <- 0..(image.width * 2 - 1)//1, into: <<>> do
        binary_part(image.rgba, (div(y, 2) * image.width + div(x, 2)) * 4, 4)
      end

    %{width: image.width * 2, height: image.height * 2, rgba: doubled}
  end

  defp magnify(image, _name), do: image

  def texture(name), do: Map.fetch!(:persistent_term.get({__MODULE__, :textures}), name)
  def sprite(name), do: Map.fetch!(:persistent_term.get({__MODULE__, :sprites}), name)

  def memo(key, build) do
    case :ets.lookup(@table, key) do
      [{^key, value}] ->
        value

      [] ->
        value = build.()
        :ets.insert(@table, {key, value})
        value
    end
  end

  def frame_ms, do: memo(:frame_ms, fn -> 0 end)
  def record_frame_ms(ms), do: :ets.insert(@table, {:frame_ms, ms})

  def stamp(key, shrink) do
    memo({:stamp, key, shrink}, fn ->
      image = key |> build_image() |> Blit.shrink(shrink)
      %{width: image.width, height: image.height, runs: Blit.runs(image)}
    end)
  end

  defp build_image({:cube, top, left, right, tile_h}),
    do: cube(texture(top), texture(left), texture(right), tile_h)

  defp build_image({:diamond, floor, tile_h}), do: diamond(texture(floor), tile_h)
  defp build_image({:sprite, name, false}), do: sprite(name)
  defp build_image({:sprite, name, true}), do: Blit.flip(sprite(name))
  defp build_image({:sprite, name, flip, 0}), do: build_image({:sprite, name, flip})

  defp build_image({:sprite, name, flip, frame}),
    do: Walk.frame(build_image({:sprite, name, flip}), leg_band(name), frame)

  @walk_frames 4
  @stride_ms 120

  def walk_frames, do: @walk_frames

  def frame_at(false, _now), do: 0
  def frame_at(true, now), do: Integer.mod(div(now, @stride_ms), @walk_frames)

  defp leg_band({{:hero, _tunic}, _pose}), do: {21, 2}
  defp leg_band({_tunic, _pose}), do: {12, 1}

  def shaded_texture(name, level, side) do
    memo({:texture, name, level, side}, fn ->
      factor = if side == 0, do: 0.72, else: 1.0
      shade_all(texture(name), factor, level)
    end)
  end

  def shaded_sprite(key, level) do
    memo({:sprite_shaded, key, level}, fn ->
      image = build_image(key)
      %{image | rgba: shade_all(image.rgba, 1.0, level)}
    end)
  end

  defp shade_all(rgba, factor, level) do
    for <<pixel::binary-size(4) <- rgba>>, into: <<>>, do: shade(pixel, factor, level)
  end

  def shade(<<_, _, _, alpha>> = pixel, _factor, _level) when alpha < 128, do: pixel

  def shade(<<red, green, blue, _>>, factor, level) do
    {fog_red, fog_green, fog_blue} = @fog
    mix = level / @fog_levels

    <<channel(red * factor, fog_red, mix), channel(green * factor, fog_green, mix),
      channel(blue * factor, fog_blue, mix), 255>>
  end

  defp channel(value, fog, mix),
    do: value |> Kernel.+((fog - value) * mix) |> round() |> min(255) |> max(0)

  def fog_level(distance, max_distance) do
    min(@fog_levels, trunc(distance / max_distance * @fog_levels))
  end

  def texel(texture, u, v) do
    column = u |> Kernel.*(16) |> trunc() |> min(15) |> max(0)
    row = v |> Kernel.*(16) |> trunc() |> min(15) |> max(0)
    binary_part(texture, (row * 16 + column) * 4, 4)
  end

  @tile_w 32
  @block_h 16

  def tile_w, do: @tile_w
  def block_h, do: @block_h

  defp inside_diamond?(xc, yc, tile_h) do
    abs(xc - @tile_w / 2) / (@tile_w / 2) + abs(yc - tile_h / 2) / (tile_h / 2) <= 1 + 1 / @tile_w
  end

  defp last_top_row(x, tile_h) do
    Enum.max(for(y <- 0..(tile_h - 1)//1, inside_diamond?(x + 0.5, y + 0.5, tile_h), do: y), fn ->
      -1
    end)
  end

  defp diamond(top, tile_h) do
    rgba =
      for y <- 0..(tile_h - 1)//1, x <- 0..(@tile_w - 1)//1, into: <<>> do
        if inside_diamond?(x + 0.5, y + 0.5, tile_h),
          do: top_texel(top, x, y, tile_h),
          else: <<0, 0, 0, 0>>
      end

    %{width: @tile_w, height: tile_h, rgba: rgba}
  end

  defp top_texel(top, x, y, tile_h) do
    xc = x + 0.5
    yc = y + 0.5

    texel(
      top,
      (xc - @tile_w / 2) / @tile_w + yc / tile_h,
      yc / tile_h - (xc - @tile_w / 2) / @tile_w
    )
  end

  defp cube(top, left, right, tile_h) do
    rgba =
      for y <- 0..(tile_h + @block_h - 1)//1, x <- 0..(@tile_w - 1)//1, into: <<>> do
        cube_pixel(top, left, right, x, y, tile_h)
      end

    %{width: @tile_w, height: tile_h + @block_h, rgba: rgba}
  end

  defp cube_pixel(top, left, right, x, y, tile_h) do
    if y < tile_h and inside_diamond?(x + 0.5, y + 0.5, tile_h),
      do: top_texel(top, x, y, tile_h),
      else: face_pixel(left, right, x, y, last_top_row(x, tile_h))
  end

  defp face_pixel(left, right, x, y, last_top) when y > last_top and y <= last_top + @block_h do
    half = div(@tile_w, 2)
    v = (y - last_top - 1) / @block_h

    if x < half,
      do: shade(texel(left, x / half, v), 0.62, 0),
      else: shade(texel(right, (x - half) / half, v), 0.82, 0)
  end

  defp face_pixel(_left, _right, _x, _y, _last_top), do: <<0, 0, 0, 0>>
end

defmodule IsoTown.World do
  defstruct [:size, :cells]

  @legend """
  PPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP
  P..............................................P
  P.....T........wwwwwwwwwwwwwww.........T.......P
  P..............w.............w.................P
  P..T...........w..KKKKKKKKK..w......T..........P
  P..............w..KKKKKKKKK..w.................P
  P..............w..KKKKKKKKK..w...T.............P
  P.......T......w..KKKKKKKKK..w.................P
  P..............w....,,,,,....w.........T.......P
  P..............wwwwww,,,wwwwww.................P
  P...T.................=.............T..........P
  P.....................=........................P
  P.........HHHH........=........BBB.............P
  P.........HHHH........=........BBB....T........P
  P.........HHHH........=........BBB.............P
  P..T...........l......=..l.....................P
  P.....................=..............bb........P
  P.......hhh...........=..............bb........P
  P.......hhh...........=.........T....bb........P
  P.......hhh...........=........................P
  P.....................=.......l........ss......P
  P....T................=................ss......P
  P.....................=........................P
  P========================================......P
  P========================================......P
  P.....................=...........,,,,,,,......P
  P.........l...........=......l....,,,,,,,......P
  P......SSS............=...........,,o,,,,......P
  P......SSS............=...........,,,,,,,......P
  P......SSS............=...........,,,o,,,......P
  P.....................=...........,,,,,,,......P
  P...........T.........=.............l..........P
  P.....................=........................P
  P.....~~~~............=.....bbbb...............P
  P....~~~~~~...........=.....bbbb......T........P
  P....~~~~~~...........=.....bbbb...............P
  P.....~~~~............=........................P
  P.....................=..........T.............P
  P........T............=........................P
  P.....................=.....hh.................P
  P.......T.............=.....hh.......T.........P
  P.....................=........................P
  P..........::::::::::::::::::::................P
  P.......T.....................T................P
  P.....T........................................P
  P..............................................P
  P..............................................P
  PPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP
  """

  @floors %{"." => :grass, "=" => :road, "," => :cobble, "~" => :water, ":" => :dirt}
  @props %{
    "T" => {:grass, :tree},
    "P" => {:grass, :pine},
    "l" => {:cobble, :lamp},
    "o" => {:cobble, :barrel}
  }
  @blocks %{
    "h" => {:plaster, 1},
    "H" => {:plaster, 2},
    "b" => {:brick, 1},
    "B" => {:brick, 2},
    "s" => {:shop, 1},
    "S" => {:shop, 2},
    "w" => {:stone, 1},
    "K" => {:stone, 3}
  }
  @doorless ["w"]
  @walkable [:grass, :road, :cobble, :dirt]
  @roadish [:road, :cobble, :dirt]
  @sides %{n: {0, -1}, e: {1, 0}, s: {0, 1}, w: {-1, 0}}

  def sides, do: @sides

  def build do
    rows = @legend |> String.split("\n", trim: true) |> Enum.map(&String.graphemes/1)
    width = rows |> hd() |> length()
    height = length(rows)

    if Enum.any?(rows, &(length(&1) != width)),
      do: raise("every legend row must be #{width} wide")

    cells =
      for {row, y} <- Enum.with_index(rows), {char, x} <- Enum.with_index(row), into: %{} do
        {{x, y}, cell(char)}
      end

    %__MODULE__{size: {width, height}, cells: doors(cells, rows)}
  end

  defp cell(char) do
    cond do
      Map.has_key?(@floors, char) ->
        %{floor: Map.fetch!(@floors, char), block: nil, prop: nil}

      Map.has_key?(@props, char) ->
        {floor, prop} = Map.fetch!(@props, char)
        %{floor: floor, block: nil, prop: prop}

      Map.has_key?(@blocks, char) ->
        {material, storeys} = Map.fetch!(@blocks, char)
        %{floor: :cobble, block: %{material: material, storeys: storeys, door: nil}, prop: nil}

      true ->
        raise "unknown legend character #{inspect(char)}"
    end
  end

  defp doors(cells, rows) do
    chars =
      for {row, y} <- Enum.with_index(rows),
          {char, x} <- Enum.with_index(row),
          into: %{},
          do: {{x, y}, char}

    roadish =
      for {position, %{floor: floor, block: nil, prop: nil}} <- cells,
          floor in @roadish,
          do: position

    cells
    |> Map.keys()
    |> Enum.filter(&(cells[&1].block != nil and chars[&1] not in @doorless))
    |> buildings(chars)
    |> Enum.reduce(cells, fn building, acc ->
      case nearest_door(building, roadish) do
        nil -> acc
        {position, side} -> update_in(acc, [position, :block, :door], fn _ -> side end)
      end
    end)
  end

  defp buildings(positions, chars), do: buildings(MapSet.new(positions), chars, [])

  defp buildings(pending, chars, found) do
    case Enum.min(pending, fn -> nil end) do
      nil -> found
      seed -> flood(seed, pending, chars, found)
    end
  end

  defp flood(seed, pending, chars, found) do
    char = chars[seed]
    {building, rest} = grow([seed], MapSet.delete(pending, seed), MapSet.new([seed]), char, chars)
    buildings(rest, chars, [MapSet.to_list(building) | found])
  end

  defp grow([], pending, building, _char, _chars), do: {building, pending}

  defp grow([{x, y} | queue], pending, building, char, chars) do
    neighbours =
      for {dx, dy} <- Map.values(@sides),
          position = {x + dx, y + dy},
          MapSet.member?(pending, position),
          chars[position] == char,
          do: position

    grow(
      queue ++ neighbours,
      Enum.reduce(neighbours, pending, &MapSet.delete(&2, &1)),
      Enum.reduce(neighbours, building, &MapSet.put(&2, &1)),
      char,
      chars
    )
  end

  defp nearest_door(building, roadish) do
    for {bx, by} <- building, {rx, ry} <- roadish do
      {abs(rx - bx) + abs(ry - by), {bx, by}, {rx - bx, ry - by}}
    end
    |> Enum.min(fn -> nil end)
    |> case do
      nil -> nil
      {_distance, position, delta} -> {position, side_of(delta)}
    end
  end

  defp side_of({dx, dy}) when abs(dx) > abs(dy), do: if(dx > 0, do: :e, else: :w)
  defp side_of({_dx, dy}), do: if(dy >= 0, do: :s, else: :n)

  def cell(%__MODULE__{cells: cells}, {x, y}), do: Map.get(cells, {x, y})

  def walkable?(%__MODULE__{} = world, {x, y}) do
    case cell(world, {trunc(:math.floor(x)), trunc(:math.floor(y))}) do
      %{floor: floor, block: nil, prop: nil} -> floor in @walkable
      _blocked -> false
    end
  end

  def walkable_cells(%__MODULE__{cells: cells}) do
    for {position, %{floor: floor, block: nil, prop: nil}} <- cells,
        floor in @roadish,
        do: position
  end

  def props(%__MODULE__{cells: cells}) do
    for {{x, y}, %{prop: prop}} <- cells, prop != nil, do: {prop, {x + 0.5, y + 0.5}}
  end
end

defmodule IsoTown.Iso do
  alias FrenchCurve.Raster
  alias IsoTown.{Art, Blit, Path, Ruler, World}

  @void {18, 20, 28}

  def rotate_point({x, y}, 0, _size), do: {x, y}
  def rotate_point({x, y}, 1, {width, _height}), do: {y, width - x}
  def rotate_point({x, y}, 2, {width, height}), do: {width - x, height - y}
  def rotate_point({x, y}, 3, {_width, height}), do: {height - y, x}

  def rotate_cell({x, y}, 0, _size), do: {x, y}
  def rotate_cell({x, y}, 1, {width, _height}), do: {y, width - 1 - x}
  def rotate_cell({x, y}, 2, {width, height}), do: {width - 1 - x, height - 1 - y}
  def rotate_cell({x, y}, 3, {_width, height}), do: {height - 1 - y, x}

  def rotate_dir({dx, dy}, 0), do: {dx, dy}
  def rotate_dir({dx, dy}, 1), do: {dy, -dx}
  def rotate_dir({dx, dy}, 2), do: {-dx, -dy}
  def rotate_dir({dx, dy}, 3), do: {-dy, dx}

  def unrotate_dir(direction, facing), do: rotate_dir(direction, rem(4 - facing, 4))

  def visible_sides(0), do: %{right: :e, left: :s}
  def visible_sides(1), do: %{right: :s, left: :w}
  def visible_sides(2), do: %{right: :w, left: :n}
  def visible_sides(3), do: %{right: :n, left: :e}

  def geometry(shrink, tile_h) do
    %{
      shrink: shrink,
      tilt: tile_h,
      half_w: Art.tile_w() / 2 / shrink,
      half_h: tile_h / 2 / shrink,
      tile_w: Art.tile_w() / shrink,
      tile_h: tile_h / shrink,
      block_h: Art.block_h() / shrink
    }
  end

  def render(
        %World{} = world,
        %{facing: facing, player: player, npcs: npcs} = view,
        {width, height},
        shrink
      ) do
    geometry = geometry(shrink, view.tilt)
    origin = origin(world, view, {width, height}, geometry)
    {rpx, rpy} = rotate_point({player.x, player.y}, facing, world.size)
    rows = floor_rows(world, facing, {rpx, rpy}, {width, height}, geometry)
    rows = ground_overlay(rows, world, view, origin, geometry, {width, height})

    movers = [
      Map.put(player, :tunic, look(view, :player))
      | Enum.map(npcs, &%{&1 | tunic: look(view, &1.tunic)})
    ]

    items =
      standing_items(world, facing, origin, {width, height}, geometry) ++
        mover_items(movers, facing, world.size, origin, geometry)

    items
    |> Enum.sort_by(& &1.depth)
    |> Enum.reduce(rows, fn %{stamps: stamps}, acc ->
      Enum.reduce(stamps, acc, fn {stamp, x, y}, painted ->
        Blit.blit(painted, stamp, {x, y}, width, height)
      end)
    end)
    |> label_overlay(world, view, origin, geometry, {width, height})
    |> Blit.to_raster(width, height)
  end

  def look(%{look: :hero}, tunic), do: {:hero, tunic}
  def look(_view, tunic), do: tunic

  def tile_at(%World{} = world, %{facing: facing} = view, {width, height}, shrink, {px, py}) do
    geometry = geometry(shrink, view.tilt)
    {ox, oy} = origin(world, view, {width, height}, geometry)
    across = (px - ox) / geometry.half_w
    down = (py - oy) / geometry.half_h
    {wx, wy} = unrotate_point({(across + down) / 2, (down - across) / 2}, facing, world.size)
    {trunc(:math.floor(wx)), trunc(:math.floor(wy))}
  end

  def unrotate_point({x, y}, 0, _size), do: {x, y}
  def unrotate_point({rx, ry}, 1, {width, _height}), do: {width - ry, rx}
  def unrotate_point({rx, ry}, 2, {width, height}), do: {width - rx, height - ry}
  def unrotate_point({rx, ry}, 3, {_width, height}), do: {ry, height - rx}

  defp origin(world, %{facing: facing, player: player}, {width, height}, geometry) do
    {rpx, rpy} = rotate_point({player.x, player.y}, facing, world.size)
    {width / 2 - (rpx - rpy) * geometry.half_w, height / 2 - (rpx + rpy) * geometry.half_h}
  end

  defp project({rx, ry}, {ox, oy}, geometry),
    do: {round(ox + (rx - ry) * geometry.half_w), round(oy + (rx + ry) * geometry.half_h)}

  defp ground_overlay(rows, _world, %{aim: nil}, _origin, _geometry, _size), do: rows

  defp ground_overlay(
         rows,
         world,
         %{aim: {ax, ay}, facing: facing, player: player} = view,
         origin,
         geometry,
         {width, height}
       ) do
    colour = aim_colour(view)
    {rx, ry} = rotate_cell({ax, ay}, facing, world.size)

    corners =
      Enum.map(
        [{rx, ry}, {rx + 1, ry}, {rx + 1, ry + 1}, {rx, ry + 1}, {rx, ry}],
        &project(&1, origin, geometry)
      )

    foot = project(rotate_point({player.x, player.y}, facing, world.size), origin, geometry)
    centre = project(rotate_point({ax + 0.5, ay + 0.5}, facing, world.size), origin, geometry)

    path_points =
      for cell <- Map.get(view, :path, []) || [] do
        project(rotate_point(Path.centre(cell), facing, world.size), origin, geometry)
      end

    rows
    |> Blit.line(foot, centre, {200, 200, 210}, width, height)
    |> Blit.polyline(path_points, {255, 230, 120}, width, height)
    |> Blit.polyline(corners, colour, width, height)
  end

  defp label_overlay(rows, _world, %{aim: nil}, _origin, _geometry, _size), do: rows

  defp label_overlay(
         rows,
         world,
         %{aim: {ax, ay}, facing: facing, player: player} = view,
         origin,
         geometry,
         {width, height}
       ) do
    from = {trunc(:math.floor(player.x)), trunc(:math.floor(player.y))}
    text = Ruler.label(view.ruler, Ruler.distance(view.ruler, from, {ax, ay}))
    scale = max(1, div(2, geometry.shrink))
    label = Linocut.Font.render(text, aim_colour(view), scale: scale)

    stamp = %{
      width: label.width,
      height: label.height,
      runs:
        Blit.runs(%{width: label.width, height: label.height, rgba: Raster.to_rgba_binary(label)})
    }

    {cx, cy} = project(rotate_point({ax + 0.5, ay + 0.5}, facing, world.size), origin, geometry)

    Blit.blit(
      rows,
      stamp,
      {cx + round(geometry.half_w) + 2, cy - round(geometry.half_h) - label.height},
      width,
      height
    )
  end

  defp aim_colour(%{path: path, range: range, ruler: ruler, aim: aim, player: player}) do
    from = {trunc(:math.floor(player.x)), trunc(:math.floor(player.y))}
    in_range = range == nil or Ruler.distance(ruler, from, aim) <= range

    cond do
      path in [nil, []] -> {255, 110, 110}
      in_range -> {120, 255, 160}
      true -> {255, 190, 90}
    end
  end

  defp floor_rows(world, facing, {rpx, rpy}, {width, height}, geometry) do
    anchor = {trunc(:math.floor(rpx)), trunc(:math.floor(rpy))}
    {ax, ay} = anchor
    margin = {round(geometry.tile_w), round(geometry.tile_h)}
    {margin_x, margin_y} = margin
    key = {facing, anchor, width, height, geometry.shrink, geometry.tilt}

    layer =
      case :ets.lookup(Art.table(), :floor_layer) do
        [{:floor_layer, ^key, rows}] ->
          rows

        _other ->
          rows =
            floor_layer(
              world,
              facing,
              anchor,
              {width + 2 * margin_x, height + 2 * margin_y},
              margin,
              geometry
            )

          :ets.insert(Art.table(), {:floor_layer, key, rows})
          rows
      end

    x0 = round(margin_x + (rpx - rpy - (ax - ay)) * geometry.half_w)
    y0 = round(margin_y + (rpx + rpy - (ax + ay)) * geometry.half_h)
    Blit.crop(layer, {x0, y0}, {width, height})
  end

  defp floor_layer(world, facing, {ax, ay}, {layer_w, layer_h}, {margin_x, margin_y}, geometry) do
    ox = margin_x + (layer_w - 2 * margin_x) / 2 - (ax - ay) * geometry.half_w
    oy = margin_y + (layer_h - 2 * margin_y) / 2 - (ax + ay) * geometry.half_h

    Enum.reduce(world.cells, Blit.frame(layer_w, layer_h, @void), fn {position, cell}, rows ->
      {rx, ry} = rotate_cell(position, facing, world.size)
      sx = ox + (rx - ry) * geometry.half_w - geometry.half_w
      sy = oy + (rx + ry) * geometry.half_h

      if sx + geometry.tile_w > 0 and sx < layer_w and sy + geometry.tile_h > 0 and sy < layer_h do
        Blit.blit(
          rows,
          Art.stamp({:diamond, cell.floor, geometry.tilt}, geometry.shrink),
          {round(sx), round(sy)},
          layer_w,
          layer_h
        )
      else
        rows
      end
    end)
  end

  defp standing_items(world, facing, {ox, oy}, {width, height}, geometry) do
    sides = visible_sides(facing)

    for {position, %{block: block, prop: prop}} <- world.cells,
        block != nil or prop != nil,
        {rx, ry} = rotate_cell(position, facing, world.size),
        sx = ox + (rx - ry) * geometry.half_w - geometry.half_w,
        sy = oy + (rx + ry) * geometry.half_h,
        sx + geometry.tile_w > 0 and sx < width and sy + geometry.tile_h > 0 and
          sy - 3 * geometry.block_h - 2 * geometry.tile_h < height do
      stamps =
        case block do
          nil ->
            [
              standing(
                Art.stamp({:sprite, prop, false}, geometry.shrink),
                {sx + geometry.half_w, sy + geometry.half_h},
                geometry
              )
            ]

          block ->
            storeys(block, sides, {sx, sy}, geometry)
        end

      %{depth: rx + ry + 1, stamps: stamps}
    end
  end

  defp storeys(%{material: material, storeys: storeys, door: door}, sides, {sx, sy}, geometry) do
    faces = Art.material(material)

    for storey <- 0..(storeys - 1)//1 do
      left = face(faces, storey, sides.left == door)
      right = face(faces, storey, sides.right == door)
      stamp = Art.stamp({:cube, faces.roof, left, right, geometry.tilt}, geometry.shrink)
      {stamp, round(sx), round(sy - (storey + 1) * geometry.block_h)}
    end
  end

  defp face(faces, 0, true), do: faces.door
  defp face(faces, 0, false), do: faces.ground
  defp face(faces, _upper, _door), do: faces.upper

  defp standing(stamp, {foot_x, foot_y}, geometry) do
    {stamp, round(foot_x - stamp.width / 2), round(foot_y + geometry.half_h / 4 - stamp.height)}
  end

  defp mover_items(movers, facing, size, {ox, oy}, geometry) do
    now = System.monotonic_time(:millisecond)

    for mover <- movers do
      {rx, ry} = rotate_point({mover.x, mover.y}, facing, size)
      {hx, hy} = rotate_dir({:math.cos(mover.heading), :math.sin(mover.heading)}, facing)
      pose = if hx + hy >= 0, do: :front, else: :back
      flip = hx - hy < 0
      frame = Art.frame_at(Map.get(mover, :walking, false), now)
      stamp = Art.stamp({:sprite, {mover.tunic, pose}, flip, frame}, geometry.shrink)

      %{
        depth: rx + ry,
        stamps: [
          standing(
            stamp,
            {ox + (rx - ry) * geometry.half_w, oy + (rx + ry) * geometry.half_h},
            geometry
          )
        ]
      }
    end
  end
end

defmodule IsoTown.Raycast do
  alias FrenchCurve.Raster
  alias IsoTown.{Art, World}

  @eye 0.6
  @fov 70 * :math.pi() / 180
  @max_distance 24.0
  @max_steps 80
  @sky_top {24, 30, 58}
  @sky_bottom {96, 120, 170}
  @void {40, 44, 60}

  def eye, do: @eye

  def render(%World{} = world, camera, sprites, {width, height}, aspect \\ 1.0) do
    horizon = height / 2 + Map.get(camera, :pitch, 0.0) * height / 2
    tan_half = :math.tan(@fov / 2)
    projection = width / 2 / tan_half
    dir = {:math.cos(camera.heading), :math.sin(camera.heading)}
    perp = {-:math.sin(camera.heading), :math.cos(camera.heading)}

    context = %{
      cells: world.cells,
      horizon: horizon,
      projection: projection,
      vertical: projection / aspect,
      position: {camera.x, camera.y},
      sky: sky(height, horizon),
      floors: floor_textures(),
      void: Map.new(0..Art.fog_levels(), &{&1, Art.shade(void_pixel(), 1.0, &1)})
    }

    columns =
      Map.new(0..(width - 1)//1, fn x ->
        ray = ray(dir, perp, tan_half, 2 * (x + 0.5) / width - 1)
        {x, {cast(context, ray), ray}}
      end)

    columns =
      sprites
      |> Enum.reduce(columns, &billboard(&1, &2, context, dir, perp, tan_half, width))
      |> Enum.map(fn {x, {spans, {rx, ry}}} ->
        {x, {Enum.sort_by(spans, &elem(&1, 1)), rx, ry}}
      end)
      |> Enum.sort()
      |> Enum.map(&elem(&1, 1))
      |> List.to_tuple()

    rgba =
      for y <- 0..(height - 1)//1, x <- 0..(width - 1)//1, into: <<>> do
        pixel(elem(columns, x), y, context)
      end

    Raster.from_rgba(width, height, rgba)
  end

  defp void_pixel do
    {red, green, blue} = @void
    <<red, green, blue, 255>>
  end

  defp ray({dx, dy}, {px, py}, tan_half, camera_x),
    do: {dx + px * tan_half * camera_x, dy + py * tan_half * camera_x}

  defp sky(height, horizon) do
    {tr, tg, tb} = @sky_top
    {br, bg, bb} = @sky_bottom

    for y <- 0..(height - 1)//1 do
      mix = min(1.0, y / max(horizon, 1))

      <<round(tr + (br - tr) * mix), round(tg + (bg - tg) * mix), round(tb + (bb - tb) * mix),
        255>>
    end
    |> List.to_tuple()
  end

  defp floor_textures do
    for floor <- [:grass, :road, :cobble, :water, :dirt],
        level <- 0..Art.fog_levels(),
        into: %{} do
      {{floor, level}, Art.shaded_texture(floor, level, 1)}
    end
  end

  defp cast(context, {ray_x, ray_y}) do
    {px, py} = context.position
    map_x = trunc(:math.floor(px))
    map_y = trunc(:math.floor(py))
    delta_x = if ray_x == 0, do: 1.0e30, else: abs(1 / ray_x)
    delta_y = if ray_y == 0, do: 1.0e30, else: abs(1 / ray_y)

    {step_x, side_x} =
      if ray_x < 0, do: {-1, (px - map_x) * delta_x}, else: {1, (map_x + 1 - px) * delta_x}

    {step_y, side_y} =
      if ray_y < 0, do: {-1, (py - map_y) * delta_y}, else: {1, (map_y + 1 - py) * delta_y}

    walk(
      context,
      {ray_x, ray_y},
      %{x: map_x, y: map_y, side_x: side_x, side_y: side_y},
      {step_x, step_y, delta_x, delta_y},
      context.horizon + 1,
      0,
      []
    )
  end

  defp walk(_context, _ray, _at, _stepping, _top, @max_steps, spans), do: spans

  defp walk(context, ray, at, {step_x, step_y, delta_x, delta_y} = stepping, top, steps, spans) do
    {at, side, distance} =
      if at.side_x < at.side_y,
        do: {%{at | side_x: at.side_x + delta_x, x: at.x + step_x}, 0, at.side_x},
        else: {%{at | side_y: at.side_y + delta_y, y: at.y + step_y}, 1, at.side_y}

    cond do
      distance > @max_distance or top <= 0 ->
        spans

      true ->
        case Map.get(context.cells, {at.x, at.y}) do
          nil ->
            spans

          %{block: nil} ->
            walk(context, ray, at, stepping, top, steps + 1, spans)

          %{block: block} ->
            span = wall_span(context, ray, block, side, distance)
            {_, _, span_top, _, _, _, _, _} = span

            if span_top < top,
              do: walk(context, ray, at, stepping, span_top, steps + 1, [span | spans]),
              else: walk(context, ray, at, stepping, top, steps + 1, spans)
        end
    end
  end

  defp wall_span(context, {ray_x, ray_y}, block, side, distance) do
    {px, py} = context.position
    scale = context.vertical / max(distance, 1.0e-6)
    hit = if side == 0, do: py + distance * ray_y, else: px + distance * ray_x
    fraction = hit - :math.floor(hit)

    fraction =
      if (side == 0 and ray_x > 0) or (side == 1 and ray_y < 0), do: 1 - fraction, else: fraction

    face = face_hit(side, ray_x, ray_y)
    faces = Art.material(block.material)
    level = Art.fog_level(distance, @max_distance)
    ground = if block.door == face, do: faces.door, else: faces.ground

    {:wall, distance, context.horizon - (block.storeys - @eye) * scale,
     context.horizon + @eye * scale, Art.shaded_texture(ground, level, side),
     Art.shaded_texture(faces.upper, level, side), fraction |> Kernel.*(16) |> trunc() |> min(15),
     distance / context.vertical}
  end

  defp face_hit(0, ray_x, _ray_y), do: if(ray_x > 0, do: :w, else: :e)
  defp face_hit(1, _ray_x, ray_y), do: if(ray_y > 0, do: :n, else: :s)

  defp billboard(
         {key, {sx, sy}, world_w, world_h},
         columns,
         context,
         {dx, dy},
         {px, py},
         tan_half,
         width
       ) do
    {cx, cy} = context.position
    rel_x = sx - cx
    rel_y = sy - cy
    depth = rel_x * dx + rel_y * dy
    lateral = rel_x * px + rel_y * py

    if depth > 0.15 and abs(lateral) <= depth * tan_half + world_w do
      scale = context.projection / depth
      vertical = context.vertical / depth
      width_px = world_w * scale
      height_px = world_h * vertical
      left = width / 2 + lateral * scale - width_px / 2
      bottom = context.horizon + @eye * vertical
      top = bottom - height_px
      image = Art.shaded_sprite(key, Art.fog_level(depth, @max_distance))
      from = max(0, trunc(:math.floor(left)))
      to = min(width - 1, trunc(:math.ceil(left + width_px)) - 1)

      Enum.reduce(from..to//1, columns, fn x, acc ->
        u =
          ((x + 0.5 - left) / width_px * image.width) |> trunc() |> min(image.width - 1) |> max(0)

        span = {:sprite, depth, top, bottom, image.rgba, image.width, image.height, u, height_px}
        Map.update!(acc, x, fn {spans, ray} -> {[span | spans], ray} end)
      end)
    else
      columns
    end
  end

  defp pixel({spans, ray_x, ray_y}, y, context) do
    yc = y + 0.5

    case from_spans(spans, yc, context.horizon) do
      nil ->
        if yc <= context.horizon,
          do: elem(context.sky, y),
          else: floor_pixel(ray_x, ray_y, yc, context)

      found ->
        found
    end
  end

  defp from_spans([], _yc, _horizon), do: nil

  defp from_spans([span | rest], yc, horizon) do
    if yc >= elem(span, 2) and yc <= elem(span, 3) do
      case span_pixel(span, yc, horizon) do
        <<_, _, _, alpha>> = found when alpha >= 128 -> found
        _clear -> from_spans(rest, yc, horizon)
      end
    else
      from_spans(rest, yc, horizon)
    end
  end

  defp span_pixel({:wall, _distance, _top, _bottom, ground, upper, u, factor}, yc, horizon) do
    z = @eye + (horizon - yc) * factor
    storey = trunc(z)
    row = 15 - min(15, trunc((z - storey) * 16))
    texture = if storey == 0, do: ground, else: upper
    binary_part(texture, (row * 16 + u) * 4, 4)
  end

  defp span_pixel(
         {:sprite, _distance, top, _bottom, rgba, sprite_w, sprite_h, u, height_px},
         yc,
         _horizon
       ) do
    v = ((yc - top) / height_px * sprite_h) |> trunc() |> min(sprite_h - 1) |> max(0)
    binary_part(rgba, (v * sprite_w + u) * 4, 4)
  end

  defp floor_pixel(ray_x, ray_y, yc, context) do
    {px, py} = context.position
    distance = @eye * context.vertical / (yc - context.horizon)
    wx = px + ray_x * distance
    wy = py + ray_y * distance
    cx = :math.floor(wx)
    cy = :math.floor(wy)
    level = Art.fog_level(distance, @max_distance)

    case Map.get(context.cells, {trunc(cx), trunc(cy)}) do
      nil ->
        Map.fetch!(context.void, level)

      %{floor: floor} ->
        texture = Map.fetch!(context.floors, {floor, level})
        u = trunc((wx - cx) * 16)
        v = trunc((wy - cy) * 16)
        binary_part(texture, (v * 16 + u) * 4, 4)
    end
  end
end

defmodule IsoTown.Scene do
  alias IsoTown.{Iso, Raycast, World}

  @iso_pixel_tiles [4, 8, 16]
  @iso_cell_shrink [4, 2, 1]

  def zoom_levels, do: length(@iso_pixel_tiles)

  def render(%{view: :iso} = state, world, size, mode) do
    {raster, shrink, _cell} = iso_geometry(state, size, mode)
    Iso.render(world, state, raster, shrink)
  end

  def render(%{view: :fps} = state, world, {cols, rows}, :pixel) do
    scale = if cols > 160, do: 1, else: 2
    first_person(state, world, {cols * scale, rows * 2 * scale})
  end

  def render(%{view: :fps} = state, world, {cols, rows}, {:cells, {sx, sy}}) do
    first_person(state, world, {cols * sx, rows * sy}, 2 * sx / sy)
  end

  defp first_person(%{player: player, npcs: npcs} = state, world, size, aspect \\ 1.0) do
    Raycast.render(world, player, props(world) ++ villagers(state, npcs, player), size, aspect)
  end

  def tile_at(%{view: :iso} = state, world, size, mode, {col, row}) do
    {raster, shrink, {px, py}} = iso_geometry(state, size, mode)
    Iso.tile_at(world, state, raster, shrink, {(col + 0.5) * px, (row + 0.5) * py})
  end

  def tile_at(_state, _world, _size, _mode, _cell), do: nil

  defp iso_geometry(%{zoom: zoom}, {cols, rows}, :pixel) do
    scale = div(32, Enum.at(@iso_pixel_tiles, zoom))
    {{cols * scale, rows * 2 * scale}, 1, {scale, 2 * scale}}
  end

  defp iso_geometry(%{zoom: zoom}, {cols, rows}, {:cells, {sx, sy}}),
    do: {{cols * sx, rows * sy}, Enum.at(@iso_cell_shrink, zoom), {sx, sy}}

  @villager_size 0.75

  defp props(world) do
    for {prop, position} <- World.props(world) do
      sprite = IsoTown.Art.sprite(prop)
      {{:sprite, prop, false}, position, sprite.width / 16, sprite.height / 16}
    end
  end

  defp villagers(state, npcs, player) do
    perp = {-:math.sin(player.heading), :math.cos(player.heading)}
    now = System.monotonic_time(:millisecond)

    for npc <- npcs do
      {width, height} = villager_size(state)
      frame = IsoTown.Art.frame_at(Map.get(npc, :walking, false), now)

      {{:sprite, {Iso.look(state, npc.tunic), pose(npc, player)}, flip?(npc, perp), frame},
       {npc.x, npc.y}, width, height}
    end
  end

  defp villager_size(%{look: :hero}), do: {@villager_size * 20 / 28, @villager_size}
  defp villager_size(_state), do: {@villager_size, @villager_size}

  defp pose(npc, player) do
    {hx, hy} = {:math.cos(npc.heading), :math.sin(npc.heading)}
    {tx, ty} = {player.x - npc.x, player.y - npc.y}
    length = max(:math.sqrt(tx * tx + ty * ty), 1.0e-6)
    dot = (hx * tx + hy * ty) / length

    cond do
      dot > 0.5 -> :front
      dot < -0.5 -> :back
      true -> :side
    end
  end

  defp flip?(npc, {px, py}), do: :math.cos(npc.heading) * px + :math.sin(npc.heading) * py < 0
end

defmodule IsoTown.View do
  use Drafter.Widget, handles: []

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Session.Context
  alias Drafter.Widget.Chart.Pixel
  alias FrenchCurve.Backend.Cells
  alias IsoTown.{Art, Scene}

  defstruct view: :iso,
            facing: 0,
            zoom: 1,
            cells: nil,
            look: :plain,
            tilt: 16,
            aim: nil,
            path: [],
            range: nil,
            ruler: :euclid,
            player: nil,
            npcs: [],
            world: nil,
            widget_id: nil,
            rect: nil

  @keys [
    :view,
    :facing,
    :zoom,
    :cells,
    :look,
    :tilt,
    :aim,
    :path,
    :range,
    :ruler,
    :player,
    :npcs,
    :world
  ]

  def component_tag, do: :iso_view

  def from_component_opts(_args, opts) do
    opts |> Keyword.take(@keys) |> Map.new() |> Map.put(:id, Keyword.get(opts, :__widget_id__))
  end

  @impl true
  def mount(props) do
    props = Map.new(props)
    struct(%__MODULE__{widget_id: Map.get(props, :id)}, Map.take(props, @keys))
  end

  @impl true
  def update(props, state), do: struct(state, props |> Map.new() |> Map.take(@keys))

  def on_rect_change(rect, %__MODULE__{} = state) do
    if rect != state.rect and Drafter.AppRegistry.whereis() do
      Drafter.AppRegistry.send_to_loop(
        {:widget_action, state.widget_id, {:app_callback, :geometry, rect}}
      )
    end

    %{state | rect: rect}
  end

  @impl true
  def image_active?(state), do: picture?(state)

  def image(%__MODULE__{player: nil}, _rect, _id), do: nil

  def image(%__MODULE__{} = state, %{width: cols, height: rows}, id) when cols > 0 and rows > 0 do
    case picture?(state) and protocol() do
      false ->
        nil

      protocol ->
        raster = timed(fn -> Scene.render(state, world(state), {cols, rows}, :pixel) end)

        placements = FrenchCurve.Capability.placements?(Context.terminal_env())

        case FrenchCurve.frame(raster, id,
               fit: {cols, rows},
               protocol: protocol,
               placements: placements
             ) do
          nil ->
            nil

          {paint, clear, place} ->
            {paint, clear, %{dx: 0, dy: 0, cols: cols, rows: rows, place: place}}
        end
    end
  end

  def image(_state, _rect, _id), do: nil

  @impl true
  def render(_state, %{width: cols, height: rows}) when cols <= 0 or rows <= 0, do: []

  def render(%__MODULE__{player: nil}, rect), do: blank(rect)

  def render(%__MODULE__{} = state, %{width: cols, height: rows} = rect) do
    if picture?(state) do
      blank(rect)
    else
      set = glyph_set(state)

      fn -> Scene.render(state, world(state), {cols, rows}, {:cells, Cells.subpixels(set)}) end
      |> timed()
      |> FrenchCurve.render(:cells, set: set, background: {12, 12, 16})
      |> cell_strips(cols, rows)
    end
  end

  defp timed(fun) do
    {micros, result} = :timer.tc(fun)
    Art.record_frame_ms(div(micros, 1000))
    result
  end

  defp world(%__MODULE__{world: key}), do: :persistent_term.get({IsoTown.World, key})

  defp protocol, do: Pixel.protocol(:auto)

  defp picture?(%__MODULE__{cells: nil}), do: protocol() != nil
  defp picture?(%__MODULE__{}), do: false

  defp glyph_set(%__MODULE__{cells: nil}), do: Cells.default_set(Context.terminal_env())
  defp glyph_set(%__MODULE__{cells: set}), do: set

  defp cell_strips(rows, cols, count) do
    rows
    |> Enum.map(&(&1 |> Strip.from_cells() |> Strip.fit_to_width(cols)))
    |> Enum.take(count)
  end

  defp blank(%{width: cols, height: rows}) do
    List.duplicate(
      Strip.new([Segment.new(String.duplicate(" ", cols), %{bg: {12, 12, 16}})]),
      rows
    )
  end
end

defmodule IsoTown do
  use Drafter.App, frame_pacing: :always, mouse_hover: true, controller: true

  alias Drafter.Session.Context
  alias Drafter.Widget.Chart.Pixel
  alias FrenchCurve.Backend.Cells
  alias IsoTown.{Art, Iso, Path, Ruler, Scene, World}

  @tick_ms 50
  @stride 0.1
  @walk_hold_ms 250
  @reach 6
  @walk 0.25
  @turn :math.pi() / 18
  @tilt 0.08
  @tilt_limit 0.8
  @mouse_turn :math.pi() / 60
  @mouse_tilt 0.05

  @keymap [
    view: [:tab],
    cells: [:t],
    glyphs: [:b],
    look: [:h],
    ruler: [:r],
    range: [:l],
    zoom_in: [:+, :=],
    zoom_out: [:-, :_],
    turn_left: [:q],
    turn_right: [:e],
    forward: [:w, :up],
    back: [:s, :down],
    left: [:a, :left],
    right: [:d, :right],
    tilt_up: [:"\\", :z],
    tilt_down: [:/, :c],
    mouse_look: [:m]
  ]

  @optional [
    :view,
    :cells,
    :glyphs,
    :look,
    :tilt_up,
    :tilt_down,
    :mouse_look,
    :scroll_zoom,
    :controller
  ]
  @features [
    :view,
    :cells,
    :glyphs,
    :look,
    :tilt_up,
    :tilt_down,
    :mouse_look,
    :scroll_zoom,
    :controller
  ]
  @npc_speed 0.05
  @npc_count 7
  @radius 0.2
  @screen_up ~w(NW NE SE SW)
  @fps 20
  @full_image_fps 12
  @cells_fps 12

  def refresh_rate, do: "#{@fps}fps"

  def mount(_props) do
    world = :persistent_term.get({World, :town})

    %{
      view: :iso,
      facing: 0,
      zoom: 1,
      cells: nil,
      look: :plain,
      tilt: 16,
      selected: false,
      aim: nil,
      path: [],
      route: [],
      hovers: 0,
      rect: nil,
      range: nil,
      ruler: :euclid,
      player: %{x: 22.5, y: 21.5, heading: -:math.pi() / 2, pitch: 0.0, moved_at: nil},
      mouse_look: false,
      pointer: nil,
      pad: %{left: {0.0, 0.0}, right: {0.0, 0.0}, nudge: nil},
      npcs: spawn_npcs(world),
      frame_ms: 0,
      world: world
    }
  end

  def on_ready(state) do
    Drafter.set_interval(@tick_ms, :tick)
    pace(state)
  end

  defp pace(state) do
    Drafter.set_refresh_rate("#{frame_rate(state)}fps")
    state
  end

  defp frame_rate(state) do
    case {drawing_mode(state), Pixel.protocol(:auto)} do
      {{:cells, _subpixels}, _protocol} -> @cells_fps
      {:pixel, protocol} when protocol in [:iterm2, :sixel] -> @full_image_fps
      _placed -> @fps
    end
  end

  def on_timer(:tick, state) do
    state
    |> pad_tick()
    |> follow_path()
    |> Map.put(:npcs, Enum.map(state.npcs, &step_npc(&1, state.world)))
    |> Map.put(:frame_ms, Art.frame_ms())
  end

  defp follow_path(%{route: []} = state), do: state

  defp follow_path(%{route: [next | rest], player: player} = state) do
    {tx, ty} = Path.centre(next)
    dx = tx - player.x
    dy = ty - player.y
    distance = :math.sqrt(dx * dx + dy * dy)

    if distance <= @stride do
      arrived = %{state | player: %{player | x: tx, y: ty}, route: rest}
      if rest == [], do: %{arrived | aim: nil, path: []}, else: arrived
    else
      heading = :math.atan2(dy, dx)

      moved = %{
        player
        | x: player.x + dx / distance * @stride,
          y: player.y + dy / distance * @stride,
          heading: heading
      }

      %{state | player: moved}
    end
  end

  keybinding {:q, [:ctrl]}, "quit" do
    {:stop, :normal}
  end

  def handle_event({:key, :escape, _modifiers}, state), do: escape(state)
  def handle_event({:key, :escape}, state), do: escape(state)
  def handle_event({:key, key, _modifiers}, state), do: {:ok, key(key, state)}
  def handle_event({:key, key}, state), do: {:ok, key(key, state)}

  def handle_event({:mouse, %{type: :move, x: x, y: y}}, %{view: :iso} = state) do
    case tile_under(state, x, y) do
      nil -> {:noreply, state}
      tile -> handle_event(:aim, tile, state)
    end
  end

  def handle_event(
        {:mouse, %{type: :mouse_down, button: :left, x: x, y: y}},
        %{view: :iso} = state
      ) do
    case tile_under(state, x, y) do
      nil -> {:noreply, state}
      tile -> handle_event(:go, tile, state)
    end
  end

  def handle_event({:mouse, %{type: :scroll, direction: direction}}, %{view: :iso} = state)
      when direction in [:up, :down] do
    if :scroll_zoom in @features,
      do: {:ok, zoom(state, if(direction == :up, do: 1, else: -1))},
      else: {:noreply, state}
  end

  def handle_event({:controller, event}, state) do
    if :controller in @features, do: {:ok, pad(event, state)}, else: {:noreply, state}
  end

  def handle_event({:mouse, %{type: :move, x: x, y: y}}, %{view: :fps, mouse_look: true} = state) do
    case state.pointer do
      nil ->
        {:ok, %{state | pointer: {x, y}}}

      {px, py} ->
        looked = tilt(turn((x - px) * @mouse_turn, state), (py - y) * @mouse_tilt)
        {:ok, %{looked | pointer: {x, y}}}
    end
  end

  def handle_event(_event, state), do: {:noreply, state}

  def handle_event(:geometry, rect, state), do: {:ok, %{state | rect: rect}}

  def handle_event(:aim, tile, %{view: :iso, selected: true, aim: tile} = state),
    do: {:noreply, state}

  def handle_event(:aim, tile, %{view: :iso, selected: true} = state) do
    state = %{state | hovers: state.hovers + 1}

    {:ok,
     if(tile == cell_of(state.player), do: %{state | aim: nil, path: []}, else: aim(state, tile))}
  end

  def handle_event(:aim, _tile, %{view: :iso} = state),
    do: {:ok, %{state | hovers: state.hovers + 1}}

  def handle_event(:go, tile, %{view: :iso} = state) do
    cond do
      tile == cell_of(state.player) and state.selected -> {:ok, cancel(state)}
      tile == cell_of(state.player) -> {:ok, %{cancel(state) | selected: true}}
      state.selected -> {:ok, commit(aim(state, tile))}
      true -> {:noreply, state}
    end
  end

  def handle_event(_event, _data, state), do: {:noreply, state}

  defp tile_under(%{rect: nil}, _x, _y), do: nil

  defp tile_under(%{rect: rect} = state, x, y) do
    col = x - rect.x
    row = y - rect.y

    if col >= 0 and row >= 0 and col < rect.width and row < rect.height do
      Scene.tile_at(
        state,
        state.world,
        {rect.width, rect.height},
        drawing_mode(state),
        {col, row}
      )
    else
      nil
    end
  end

  defp drawing_mode(%{cells: nil}) do
    if Pixel.protocol(:auto), do: :pixel, else: {:cells, Cells.subpixels(default_cells())}
  end

  defp drawing_mode(%{cells: set}), do: {:cells, Cells.subpixels(set)}

  defp cancel(state), do: %{state | selected: false, aim: nil, path: [], route: []}

  defp commit(state) do
    if reachable?(state), do: %{state | selected: false, route: state.path}, else: state
  end

  defp escape(%{selected: true} = state), do: {:ok, cancel(state)}
  defp escape(%{route: [_ | _]} = state), do: {:ok, cancel(state)}
  defp escape(_state), do: {:stop, :normal}

  defp cell_of(%{x: x, y: y}), do: {trunc(:math.floor(x)), trunc(:math.floor(y))}

  defp aim(state, tile) do
    from = cell_of(state.player)
    %{state | aim: tile, path: Path.find(state.world, from, tile) || []}
  end

  defp reachable?(%{path: []}), do: false
  defp reachable?(%{range: nil}), do: true

  defp reachable?(%{range: range, ruler: ruler, aim: aim, player: player}) do
    from = {trunc(:math.floor(player.x)), trunc(:math.floor(player.y))}
    Ruler.distance(ruler, from, aim) <= range
  end

  defp key(key, state) do
    case Enum.find(@keymap, fn {_action, keys} -> key in keys end) do
      {action, _keys} -> act(action, state)
      nil -> state
    end
  end

  defp act(action, state) do
    if action in @features or action not in @optional, do: perform(action, state), else: state
  end

  defp perform(:view, state), do: %{state | view: if(state.view == :iso, do: :fps, else: :iso)}
  defp perform(:cells, %{cells: nil} = state), do: pace(%{state | cells: default_cells()})
  defp perform(:cells, state), do: pace(%{state | cells: nil})
  defp perform(:glyphs, %{cells: nil} = state), do: pace(%{state | cells: default_cells()})
  defp perform(:glyphs, state), do: %{state | cells: next_set(state.cells)}

  defp perform(:look, state),
    do: %{state | look: if(state.look == :plain, do: :hero, else: :plain)}

  defp perform(:ruler, state), do: %{state | ruler: Ruler.next(state.ruler)}
  defp perform(:range, state), do: %{state | range: if(state.range == nil, do: @reach, else: nil)}
  defp perform(:zoom_in, state), do: zoom(state, 1)
  defp perform(:zoom_out, state), do: zoom(state, -1)
  defp perform(:mouse_look, state), do: %{state | mouse_look: not state.mouse_look}
  defp perform(:turn_left, %{view: :iso} = state), do: %{state | facing: rem(state.facing + 3, 4)}

  defp perform(:turn_right, %{view: :iso} = state),
    do: %{state | facing: rem(state.facing + 1, 4)}

  defp perform(:forward, %{view: :iso} = state), do: iso_walk({0, -1}, state)
  defp perform(:back, %{view: :iso} = state), do: iso_walk({0, 1}, state)
  defp perform(:left, %{view: :iso} = state), do: iso_walk({-1, 0}, state)
  defp perform(:right, %{view: :iso} = state), do: iso_walk({1, 0}, state)
  defp perform(:turn_left, state), do: turn(-@turn, state)
  defp perform(:turn_right, state), do: turn(@turn, state)
  defp perform(:forward, state), do: fps_walk(1.0, 0.0, state)
  defp perform(:back, state), do: fps_walk(-1.0, 0.0, state)
  defp perform(:left, state), do: fps_walk(0.0, -1.0, state)
  defp perform(:right, state), do: fps_walk(0.0, 1.0, state)
  defp perform(:tilt_up, %{view: :iso} = state), do: %{state | tilt: min(state.tilt + 2, 24)}
  defp perform(:tilt_down, %{view: :iso} = state), do: %{state | tilt: max(state.tilt - 2, 8)}
  defp perform(:tilt_up, state), do: tilt(state, @tilt)
  defp perform(:tilt_down, state), do: tilt(state, -@tilt)
  defp perform(_action, state), do: state

  @deadzone 0.3
  @pad_buttons [
    start: :view,
    x: :cells,
    y: :look,
    left_bumper: :zoom_out,
    right_bumper: :zoom_in,
    dpad_up: :forward,
    dpad_down: :back,
    dpad_left: :left,
    dpad_right: :right
  ]

  defp pad(%{type: :axis, axis: axis, value: value}, %{pad: pad} = state) do
    pad =
      case axis do
        :left_x -> %{pad | left: {value, elem(pad.left, 1)}}
        :left_y -> %{pad | left: {elem(pad.left, 0), value}}
        :right_x -> %{pad | right: {value, elem(pad.right, 1)}}
        :right_y -> %{pad | right: {elem(pad.right, 0), value}}
        _trigger -> pad
      end

    nudge_aim(%{state | pad: pad})
  end

  defp pad(%{type: :button, pressed: true, button: :a}, %{view: :iso} = state) do
    cond do
      state.selected and state.aim != nil -> commit(state)
      state.selected -> cancel(state)
      true -> %{cancel(state) | selected: true, aim: cell_of(state.player)}
    end
  end

  defp pad(%{type: :button, pressed: true, button: :b}, state), do: cancel(state)

  defp pad(%{type: :button, pressed: true, button: button}, state) do
    case Keyword.get(@pad_buttons, button) do
      nil -> state
      action -> act(action, state)
    end
  end

  defp pad(_event, state), do: state

  defp pad_tick(%{pad: %{left: {lx, ly}, right: {rx, ry}}} = state) do
    state
    |> pad_walk(lx, ly)
    |> pad_look(rx, ry)
  end

  defp pad_walk(state, x, y) when abs(x) < @deadzone and abs(y) < @deadzone, do: state

  defp pad_walk(%{view: :iso} = state, x, y) do
    axis =
      cond do
        abs(x) >= abs(y) and x > 0 -> {1, 0}
        abs(x) >= abs(y) -> {-1, 0}
        y > 0 -> {0, 1}
        true -> {0, -1}
      end

    {dx, dy} = Iso.unrotate_dir(axis, state.facing)
    stride = @stride * min(1.0, :math.sqrt(x * x + y * y))
    player = %{state.player | heading: :math.atan2(dy, dx)}
    %{state | player: move(player, {dx * stride, dy * stride}, state.world)}
  end

  defp pad_walk(%{player: player} = state, x, y) do
    {fx, fy} = {:math.cos(player.heading), :math.sin(player.heading)}
    {sx, sy} = {-fy, fx}
    forward = -y * @stride
    strafe = x * @stride
    step = {fx * forward + sx * strafe, fy * forward + sy * strafe}
    %{state | player: move(player, step, state.world)}
  end

  defp pad_look(%{view: :fps} = state, x, y) when abs(x) >= @deadzone or abs(y) >= @deadzone do
    turned = if abs(x) >= @deadzone, do: turn(x * @turn / 2, state), else: state
    if abs(y) >= @deadzone, do: tilt(turned, -y * @tilt / 2), else: turned
  end

  defp pad_look(state, _x, _y), do: state

  defp nudge_aim(%{view: :iso, selected: true, pad: %{right: {x, y}} = pad} = state) do
    direction =
      cond do
        abs(x) < 0.5 and abs(y) < 0.5 -> nil
        abs(x) >= abs(y) and x > 0 -> {1, 0}
        abs(x) >= abs(y) -> {-1, 0}
        y > 0 -> {0, 1}
        true -> {0, -1}
      end

    cond do
      direction == nil -> %{state | pad: %{pad | nudge: nil}}
      direction == pad.nudge -> state
      true -> nudge(%{state | pad: %{pad | nudge: direction}}, direction)
    end
  end

  defp nudge_aim(state), do: state

  defp nudge(state, screen_axis) do
    {dx, dy} = Iso.unrotate_dir(screen_axis, state.facing)
    {ax, ay} = state.aim || cell_of(state.player)
    aim(state, {ax + dx, ay + dy})
  end

  defp zoom(state, delta),
    do: %{state | zoom: state.zoom |> Kernel.+(delta) |> max(0) |> min(Scene.zoom_levels() - 1)}

  defp iso_walk(screen_axis, state) do
    {dx, dy} = Iso.unrotate_dir(screen_axis, state.facing)
    player = %{state.player | heading: :math.atan2(dy, dx)}
    %{state | player: move(player, {dx * @walk, dy * @walk}, state.world)}
  end

  defp tilt(%{view: :fps, player: player} = state, delta),
    do: %{
      state
      | player: %{
          player
          | pitch: player.pitch |> Kernel.+(delta) |> max(-@tilt_limit) |> min(@tilt_limit)
        }
    }

  defp tilt(state, _delta), do: state

  defp turn(delta, state),
    do: %{state | player: %{state.player | heading: state.player.heading + delta}}

  defp fps_walk(forward, strafe, %{player: player} = state) do
    {fx, fy} = {:math.cos(player.heading), :math.sin(player.heading)}
    {sx, sy} = {-fy, fx}
    step = {(fx * forward + sx * strafe) * @walk, (fy * forward + sy * strafe) * @walk}
    %{state | player: move(player, step, state.world)}
  end

  defp move(mover, {dx, dy}, world) do
    x =
      if World.walkable?(world, {mover.x + dx + sign(dx) * @radius, mover.y}),
        do: mover.x + dx,
        else: mover.x

    y =
      if World.walkable?(world, {x, mover.y + dy + sign(dy) * @radius}),
        do: mover.y + dy,
        else: mover.y

    if {x, y} == {mover.x, mover.y},
      do: mover,
      else: %{mover | x: x, y: y, moved_at: System.monotonic_time(:millisecond)}
  end

  defp sign(value) when value < 0, do: -1
  defp sign(value) when value > 0, do: 1
  defp sign(_zero), do: 0

  defp spawn_npcs(world) do
    cells = World.walkable_cells(world)

    for tunic <- Stream.cycle(Art.tunics()) |> Enum.take(@npc_count) do
      {cx, cy} = Enum.random(cells)

      %{
        x: cx + 0.5,
        y: cy + 0.5,
        heading: Enum.random([0, 1, 2, 3]) * :math.pi() / 2,
        tunic: tunic,
        target: nil,
        wait: 0
      }
    end
  end

  defp step_npc(%{target: nil, wait: wait} = npc, _world) when wait > 0,
    do: %{npc | wait: wait - 1}

  defp step_npc(%{target: nil} = npc, world) do
    cx = trunc(:math.floor(npc.x))
    cy = trunc(:math.floor(npc.y))

    choices =
      for {dx, dy} <- Map.values(World.sides()),
          World.walkable?(world, {cx + dx + 0.5, cy + dy + 0.5}),
          do: {dx, dy}

    case choices do
      [] ->
        %{npc | wait: 20}

      _ ->
        {dx, dy} = Enum.random(choices)
        %{npc | target: {cx + dx + 0.5, cy + dy + 0.5}, heading: :math.atan2(dy, dx)}
    end
  end

  defp step_npc(%{target: {tx, ty}} = npc, _world) do
    dx = tx - npc.x
    dy = ty - npc.y
    distance = :math.sqrt(dx * dx + dy * dy)

    if distance <= @npc_speed do
      %{npc | x: tx, y: ty, target: nil, wait: Enum.random(0..30)}
    else
      %{npc | x: npc.x + dx / distance * @npc_speed, y: npc.y + dy / distance * @npc_speed}
    end
  end

  def render(state) do
    vertical([
      label(hud(state), style: %{fg: {230, 230, 235}, bg: {20, 22, 30}, bold: true}),
      {:iso_view,
       [
         id: :scene,
         view: state.view,
         facing: state.facing,
         zoom: state.zoom,
         cells: state.cells,
         look: state.look,
         tilt: state.tilt,
         aim: state.aim,
         path: state.path,
         range: state.range,
         ruler: state.ruler,
         player: Map.put(state.player, :walking, walking?(state)),
         npcs: Enum.map(state.npcs, &Map.put(&1, :walking, &1.target != nil)),
         world: :town,
         flex: 1,
         image_throttle: {1, :tick},
         image_priority: :normal
       ]},
      label(keys(state), style: %{fg: {150, 150, 165}, bg: {20, 22, 30}})
    ])
  end

  defp hud(%{view: :iso} = state) do
    angle = round(:math.atan(state.tilt / Art.tile_w()) * 180 / :math.pi())

    " ISOMETRIC   #{Enum.at(@screen_up, state.facing)} is up   angle #{angle}°   " <>
      "player #{position(state.player)}   zoom #{state.zoom + 1}/#{Scene.zoom_levels()}   " <>
      "#{drawing(state)}   #{targeting(state)}   frame #{state.frame_ms} ms"
  end

  defp hud(%{view: :fps} = state) do
    degrees = Integer.mod(round(state.player.heading * 180 / :math.pi()), 360)

    look = if state.mouse_look, do: "   mouse look", else: ""

    " FIRST PERSON   heading #{degrees}°   tilt #{Float.round(state.player.pitch, 2)}#{look}   " <>
      "player #{position(state.player)}   #{drawing(state)}   frame #{state.frame_ms} ms"
  end

  defp targeting(%{aim: nil, selected: false} = state),
    do: "click your character to move   ruler #{state.ruler}#{reach(state)}"

  defp targeting(%{aim: nil} = state),
    do: "point at a tile   ruler #{state.ruler}#{reach(state)}   hovers #{state.hovers}"

  defp targeting(%{aim: {ax, ay} = aim, player: player} = state) do
    from = {trunc(:math.floor(player.x)), trunc(:math.floor(player.y))}
    distance = Ruler.label(state.ruler, Ruler.distance(state.ruler, from, aim))
    steps = if state.path == [], do: "no path", else: "#{length(state.path) - 1} steps"
    walking = if state.route == [], do: "", else: ", walking"
    "aim (#{ax},#{ay}) #{distance} tiles by #{state.ruler}#{reach(state)}, #{steps}#{walking}"
  end

  defp reach(%{range: nil}), do: ""
  defp reach(%{range: range}), do: " within #{range}"

  defp drawing(%{cells: nil}) do
    case Pixel.protocol(:auto) do
      nil -> "#{default_cells()} cells (terminal default)"
      protocol -> "picture (#{protocol})"
    end
  end

  defp drawing(%{cells: set}) do
    {sx, sy} = Cells.subpixels(set)
    "#{set} cells (#{sx}×#{sy})"
  end

  defp default_cells, do: Cells.default_set(Context.terminal_env())

  defp next_set(set) do
    sets = Cells.sets()
    Enum.at(sets, rem(Enum.find_index(sets, &(&1 == set)) + 1, length(sets)))
  end

  defp position(%{x: x, y: y}), do: "(#{Float.round(x, 1)}, #{Float.round(y, 1)})"

  defp walking?(%{route: [_ | _]}), do: true
  defp walking?(%{player: %{moved_at: nil}}), do: false

  defp walking?(%{player: player}),
    do: System.monotonic_time(:millisecond) - player.moved_at < @walk_hold_ms

  defp keys(%{view: :iso}),
    do:
      " WASD walk   click character, aim, click to go, Esc cancels   R ruler   L range   H look   Q/E turn   +/- zoom   T/B cells   Tab   ^Q quit"

  defp keys(%{view: :fps}),
    do:
      " W/S walk   A/D strafe   Q/E ←/→ turn   \\ / or Z/C tilt   M mouse look   T/B cells   Tab isometric   Esc/^Q quit"
end

IsoTown.Art.install()
:persistent_term.put({IsoTown.World, :town}, IsoTown.World.build())
Drafter.Widget.Registry.register(IsoTown.View)
Drafter.run(IsoTown)
