# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an Elixir library called "Nested" that provides utilities for safely accessing, extracting, and manipulating nested data structures in maps and lists. The library focuses on safe navigation without exceptions and flexible path syntax for complex data operations.

## Common Commands

### Testing
- `mix test` - Run all tests
- `mix test test/nested_test.exs` - Run specific test file
- `mix test --verbose` - Run tests with detailed output

### Development
- `mix compile` - Compile the project
- `mix deps.get` - Install dependencies
- `mix docs` - Generate documentation (requires ex_doc dependency)

### Code Quality
- `mix format` - Format code according to Elixir standards
- `mix credo` - Static code analysis (if credo is added to deps)

## Architecture

The codebase is structured as a single-module library with the main functionality in `lib/nested.ex`. The core architecture consists of:

### Core Functions
- **Safe Navigation**: `get/3` and `fetch/2` for safe data access
- **Data Extraction**: `extract/2` for collecting multiple values using wildcards and filters
- **Data Transformation**: `traverse/2` for walking and transforming entire data structures
- **Utility Functions**: `clean_nil/1`, `to_map/1`, `censor/2`, and `merge/2` for common data manipulation tasks

### Path Syntax
The library uses a flexible path syntax supporting:
- Integers for list indices or map keys
- Atoms for map/keyword list keys  
- Strings for map string keys
- Maps for filtering list items by criteria
- Functions for custom predicate filtering
- "*" wildcard for matching all items (extract only)

### Error Handling
- Functions use safe navigation patterns returning `nil` or `:error` rather than raising exceptions
- `get/3` returns default values for missing paths
- `fetch/2` returns `{:ok, value}` or `:error` tuples

### Data Structure Support
- Maps and nested maps
- Lists and nested lists
- Keyword lists
- Structs (automatically converted to maps, except DateTime/Date/Time types)

## Development Guidelines

### Code Patterns
- All functions follow the convention of accepting the data structure as the first parameter
- Path specifications are always lists of keys/indices/filters
- Default values and error cases are handled gracefully
- Struct handling preserves special Elixir types (DateTime, Date, Time, NaiveDateTime)

### Testing
- Comprehensive test suite in `test/nested_test.exs` using ExUnit
- Tests cover all main functions with various data types and edge cases
- Doctests are included in the main module for documentation examples