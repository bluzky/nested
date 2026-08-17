# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an Elixir library (Hex package `nestex`, module name `Nested`) that provides utilities for safely accessing, extracting, and manipulating nested data structures in maps and lists. The library focuses on safe navigation without exceptions and a flexible path syntax for complex data operations.

## Common Commands

### Testing
- `mix test` - Run all tests
- `mix test test/nested_test.exs` - Run the core module's tests
- `mix test test/nested/query_parser_test.exs` - Run query-string parser tests
- `mix test path/to/file.exs:LINE` - Run a single test by line number
- `mix test --verbose` - Run tests with detailed output

### Development
- `mix compile` - Compile the project
- `mix deps.get` - Install dependencies
- `mix docs` - Generate documentation (uses `ex_doc`, see `doc/`)
- `mix format` - Format code according to `.formatter.exs`

## Architecture

The library has two modules:

- **`lib/nested.ex`** (`Nested`) - the public API and all core traversal/access logic.
- **`lib/nested/query_parser.ex`** (`Nested.QueryParser`) - converts human-readable query strings (e.g. `"users[active=true].name"`) into the path lists that the core API consumes. Invoked via `Nested.key/2`. Implemented as a recursive-descent scanner over the input binary (function-head pattern matching, e.g. `<<".", rest::binary>>`) rather than regexes — this is what correctly handles dots inside `[...]` without a lookahead regex.

### Core Functions (`Nested`)
- **Safe Navigation**: `get/3` and `fetch/2` for safe data access
- **Data Extraction**: `extract/2` for collecting multiple values using wildcards and filters — **deprecated**, prefer `Enum` for known/static paths; still useful for dynamic paths (e.g. built via `key/2`) or nil-tolerant traversal
- **Data Transformation**: `traverse/2` for walking and transforming entire data structures
- **Utility Functions**: `clean_nil/1`, `to_map/2`, `censor/2`, `scrub_params/1`, and `merge/2` for common data manipulation tasks
- **Query Strings**: `key/2` parses a dot/bracket query string (via `Nested.QueryParser.parse/2`) into a path list for use with the functions above

### Path Syntax
Paths passed to `get/3`, `fetch/2`, and `extract/2` are lists that can contain:
- Integers for list indices or map keys
- Atoms for map/keyword list keys
- Strings for map string keys
- Maps for filtering list items by criteria (e.g. `%{active: true}`, matched via `Map.take/2` equality)
- Functions/1 for custom predicate filtering
- `"*"` wildcard for matching all items (extract only)

### Query String Syntax (`Nested.key/2` / `Nested.QueryParser`)
- Dot notation for path segments: `"users.0.name"`
- Bracket indexing/filtering: `"users[0]"`, `"users[name=Alice]"`, `"users[name=Alice,active=true]"`
- Wildcard: `"users[*].name"`
- Quoted (`'key'`/`"key"`) and atom (`:key`) bracket keys
- A `key_type` argument (`:atom` default, or `:string`) controls whether bare dot-notation segments and filter keys become atoms or strings
- Filter values are type-inferred: `true`/`false`, `:atom`, integers, floats, quoted strings, else raw string

### Error Handling
- Functions use safe navigation patterns returning `nil` or `:error` rather than raising exceptions
- `get/3` returns a default value (`nil` unless specified) for missing paths
- `fetch/2` returns `{:ok, value}` or `:error` tuples
- `Nested.QueryParser.parse/2` raises `ArgumentError` only for an invalid `key_type`

### Data Structure Support
- Maps and nested maps
- Lists and nested lists
- Keyword lists (looked up via atom keys in `fetch/2`/`extract/2`)
- Structs (automatically converted to maps by `traverse/2`-based functions, except `DateTime`/`Date`/`Time`/`NaiveDateTime`, which are preserved as-is)

## Development Guidelines

### Code Patterns
- All functions follow the convention of accepting the data structure as the first parameter
- Path specifications passed to `get/3`, `fetch/2`, `extract/2` are always lists of keys/indices/filters
- `traverse/2`'s callback returns one of `:discard`, `{:skip, item}`, `{:next, item}`, or a bare item (treated as `{:next, item}`); `clean_nil/1`, `to_map/2`, `censor/2`, and `scrub_params/1` are all implemented on top of `traverse/2`
- `to_map/2` takes an optional `key_type` (`:keep` default, `:atom`, or `:string`) to normalize map keys while converting structs; invalid values raise `ArgumentError`
- `scrub_params/1` trims string values and turns blank/whitespace-only strings into `nil`, recursively, without dropping keys or changing list length; pair with `clean_nil/1` to also drop the resulting blanks
- Struct handling preserves special Elixir date/time types; all other structs are converted to plain maps

### Testing
- Test suite in `test/nested_test.exs` (core API) and `test/nested/query_parser_test.exs` (query string parsing), using ExUnit
- Tests cover all main functions with various data types and edge cases
- Doctests are included in the main module (`@moduledoc`/`@doc` examples) for documentation
