# Rivet Engram

Rivet Engram provides multi-section templates with EEx and YAML-based section types for the Rivet framework.

It is a standalone implementation from the original Rivet.Template format.

An Engram is a pattern or template that is realized through processing. Each document contains metadata followed by one or more named sections, which may contain YAML, EEx, or EEx-generated YAML.

Engrams are currently used by Dragon (an EEx CMS) and Rivet.Mailer (templated batching/sending of emails).

## Warning

***Engrams are not safe for untrusted or end-user input.***

They generate atoms and may execute arbitrary Elixir code. Only process Engrams from sources you trust.

## Engram Structure:

An Engram is divided into sections using:

```text
=== section-name
```

The general rules are:

* `^=== (.*)$` is the section delimiter, where the captured value is the section label.
* The first line must be `=== rivet-engram-v1` (or the legacy header `=== rivet-template-v1`)
* The content immediately following the version header is YAML metadata.
* The metadata must contain a `sections:` map describing the named sections and their types.
* Any metadata fields other than `sections:` are added to the Engram assigns and are available to EEx sections.
* `===` is used instead of YAML's `---` delimiter so that sections may themselves contain multiple YAML documents.
* Section order matters (the sections themselves, not the section index). As each section is processed, its result is added to the assigns for future sections EEx evaluation, under `@sections`.

For example:

```yaml
sections:
  constants: yml
  inputs: eex-yml
  rack: eex-yml
```

This describes three named sections in addition to the initial metadata section.

Supported section types are:

* `yml` — parsed directly as YAML.
* `eex-yml` — evaluated as EEx, then parsed as a single YAML document.
* `eex-yml-docs` — evaluated as EEx, then parsed as multiple YAML documents.
* `eex` — evaluated as EEx without YAML parsing.

## Example

```
=== rivet-engram-v1
sections:
  red: yml
  blue: eex-yml
  green: eex-yml-docs
embed_assign: bork bork
=== red
hello: nurse
=== blue
narf: <%= @sections.red.hello %>
=== green
---
- narf
---
dilbert: <%= @embed_assign %>
```

A few things are happening here:

* `embed_assign` becomes part of the assigns available to EEx sections.
* the green section demonstrates multi-doc YAML inside an Engram section.
* cross-section assigns: The `blue` section references the previously processed `red` section.

## Usage

`Rivet.Engram` provides the public entry points.

The simplest usage is:

```elixir
{:ok, %Rivet.Engram{} = engram} = Rivet.Engram.process_string("...")
```

The resulting struct contains:

* `sections` — the processed result of each requested section.
* `diags` — diagnostic information collected while evaluating sections.

Most use cases can simply use:

```elixir
Rivet.Engram.process_file/2
Rivet.Engram.process_string/2
```

The lower-level parsing functions perform the initial parse without evaluating deferred EEx sections:

```elixir
Rivet.Engram.parse_file/2
Rivet.Engram.parse_string/2
```

## Nuanced behavior

Section structure is not currently enforced beyond the basic metadata requirements, so malformed or inconsistent Engrams may produce unexpected results. Notably:

* Undeclared sections are silently skipped.
* Declared-but-missing sections are not detected.
* Duplicate sections are not explicitly rejected.
* The version header currently accepts trailing text.
* Requesting only selected sections with the `:sections` option may fail logically if those sections depend on sections that were not selected and therefore were not evaluated.

## Todo

* Add stricter structural validation.
* Document processing options.
* Improve format-invariant tests, including malformed metadata, duplicate or missing sections, unknown sections, ordering and dependency behavior, unusual labels, and selective section processing.
