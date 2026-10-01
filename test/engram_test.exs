defmodule Test.Rivet.EngramTest do
  use ExUnit.Case
  alias Rivet.Engram

  @engram_big """
  === rivet-engram-v1
  sections:
    red: yml
    blue: eex-yml
    green: eex-yml-docs
  === red
  hello: nurse
  === blue
  narf: <%= @sections.red.hello %>
  === green
  ---
  - narf
  ---
  dilbert: yes
  """
  @engram_big_name ".engram_big_test.yml"
  @engram_big_expect %{
    blue: %{narf: "nurse"},
    red: %{hello: "nurse"},
    green: [["narf"], %{dilbert: "yes"}]
  }

  # use rivet-template-v1 for backwards compatability
  @engram_simple """
  === rivet-template-v1
  sections:
     tardis: eex
  === tardis
  """

  @engram_assigns """
  === rivet-engram-v1
  sections:
    subject: eex
    body: eex
  static_assign: bloop
  === subject
  <%= @static_assign %> email
  === body
  <p>
  This is a message body for <%= @static_assign %>
  """

  test "Engram" do
    File.write(@engram_big_name, @engram_big)
    on_exit(fn -> File.rm(@engram_big_name) end)

    # coverage; call without opts
    # coverage; call without opts
    assert {:ok, %Engram{}} = Engram.parse_string(@engram_big)

    assert {:ok, %Engram{} = en} = Engram.process_file(@engram_big_name)
    assert @engram_big_expect == en.sections

    assert {:ok, %Engram{} = en} = Engram.process_string(@engram_big)
    assert @engram_big_expect == en.sections

    assert {:ok, %Engram{} = en} = Engram.process_string(@engram_big, sections: [:green])
    green = Map.drop(@engram_big_expect, [:blue, :red])
    assert ^green = en.sections

    assert {:error, "Not a Rivet Engram: " <> _} = Engram.process_file("mix.exs")

    assert {:error, "Invalid Engram: missing section index"} =
             Engram.process_string("=== rivet-engram-v1\n=== blue")

    assert {:error, nil, [%{display: "Line 4: undefined variable \"narf!\""}]} =
             Engram.process_string(@engram_simple <> "<% narf! %>")
  end

  ##############################################################################
  defp bad_eval(line, engram \\ @engram_assigns, opts \\ []) do
    assert {:error, nil, [%{display: display}]} = Engram.process_string(engram <> line, opts)
    display
  end

  test "handle bad" do
    # should be line 10
    assert bad_eval("<%= bad ") =~ ~r/^Line 10: expected closing '%>' for EEx expression/
    assert bad_eval("<%= ! %> ") =~ ~r/^Line 10: syntax error: expression is incomplete/
    assert bad_eval("<%= %{}.foo %>") =~ ~r/^Line 10: key :foo not found/
    assert bad_eval("<%= notafunc(1) %>") =~ ~r/^Line 10: undefined function notafunc/
    assert bad_eval("<%= throw({:boom, 123}) %>") =~ ~r/^Line 10: throw: {:boom, 123}/
    assert bad_eval("<%= exit(\"boom\") %>") =~ ~r/^Line 10: exit: boom/
    assert bad_eval("<%= exit({:boom}) %>") =~ ~r/^Line 10: exit: {:boom}/

    assert bad_eval("", @engram_simple, imports: ["DoesntExist"]) ==
             "Invalid import module name 'DoesntExist'"

    line = "<% IO.warn(\"engram warning\"); raise \"boom\" %>"
    assert {:error, nil, diags} = Engram.process_string(@engram_assigns <> line)
    assert Enum.any?(diags, &(&1.display == "engram warning"))
    assert Enum.any?(diags, &(&1.display == "Line 10: boom"))
  end

  ##############################################################################
  test "coverage" do
    assert {:ok, %Engram{}} = Engram.Evaluate.sections(%Engram{deferred: []})

    assert {:error, "File not found"} = Engram.parse_file("boop boop boop")

    assert {:error, "Invalid sections index" <> _} =
             Engram.parse_string(@engram_simple, sections: %{foo: 1})

    engram = """
    === rivet-engram-v1
    sections:
       bad: bad
    === bad
    """

    assert {:error, "Invalid section type \"bad\" for :bad"} = Engram.parse_string(engram)

    assert {:error, "Not a Rivet Engram: empty input"} = Engram.Read.from_string("")
  end
end
