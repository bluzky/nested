# Nested

Utilities for safely accessing, extracting, and manipulating nested data structures in Elixir maps and lists.

`Nested` is particularly useful when working with:
- JSON-like data structures
- Configuration maps
- API responses with nested data
- Complex data transformations

## Features

- **Safe navigation** — gracefully handles missing paths without raising exceptions
- **Flexible path syntax** — supports integers, atoms, strings, maps for filtering, and functions
- **Map filtering** — find list items by matching specific criteria
- **Query strings** — parse human-readable dot/bracket paths (e.g. `"users[active=true].name"`) into path lists
- **Deep traversal** — transform entire data structures with custom logic
- **Struct handling** — automatically converts structs while preserving special types (`DateTime`, `Date`, `Time`, `NaiveDateTime`)

## Installation

The package can be installed by adding `nestex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:nestex, "~> 0.2.0"}
  ]
end
```

Documentation can be found at <https://hexdocs.pm/nested>.

## Path Syntax

Paths are lists that can contain:
- `integer` - list index or map key
- `atom` - map key or keyword list key
- `string` - map string key
- `map` - filter criteria for finding items in lists
- `function/1` - custom predicate for finding items in lists
- `"*"` - wildcard to match all items (`extract/2` only)

## Usage

### Safe navigation with `get/3` and `fetch/2`

```elixir
data = %{
  users: [
    %{name: "Alice", age: 30, active: true},
    %{name: "Bob", age: 25, active: false}
  ],
  config: %{database: %{host: "localhost", port: 5432}}
}

# Simple path navigation
Nested.get(data, [:users, 0, :name])
#=> "Alice"

# Missing path returns nil, or a custom default
Nested.get(data, [:users, 5, :name], "Unknown")
#=> "Unknown"

# Map filtering - find item by criteria
Nested.get(data, [:users, %{active: true}, :name])
#=> "Alice"

# Function filtering - custom predicate
Nested.get(data, [:users, &(&1.age > 26), :name])
#=> "Alice"

# fetch/2 distinguishes "found nil" from "not found"
Nested.fetch(data, [:config, :database, :host])
#=> {:ok, "localhost"}

Nested.fetch(data, [:users, 5, :name])
#=> :error
```

### Extracting multiple values with `extract/2` (deprecated)

> `extract/2` is deprecated. For known/static data shapes, prefer plain `Enum`
> functions (`Enum.map/2`, `Enum.flat_map/2`) — they're simpler and more
> idiomatic. It mainly earns its keep when the path is built dynamically at
> runtime (e.g. via `key/2`) or intermediate keys may be missing and you want
> `[]` instead of an exception.

`extract/2` always returns a list and supports the `"*"` wildcard:

```elixir
data = %{
  teams: [
    %{name: "Backend", members: ["Alice", "Bob"]},
    %{name: "Frontend", members: ["Charlie", "Diana"]}
  ]
}

Nested.extract(data, [:teams, "*", :name])
#=> ["Backend", "Frontend"]

# Wildcards can be nested
company = %{
  departments: [
    %{teams: [%{name: "Backend"}, %{name: "Frontend"}]},
    %{teams: [%{name: "UX"}, %{name: "Visual"}]}
  ]
}

Nested.extract(company, [:departments, "*", :teams, "*", :name])
#=> ["Backend", "Frontend", "UX", "Visual"]
```

### Query strings with `key/2`

For convenience, paths can be written as strings and parsed with `Nested.key/2`:

```elixir
Nested.get(data, Nested.key("users.0.name"))
#=> "Alice"

Nested.get(data, Nested.key("users[active=true].name"))
#=> "Alice"

Nested.extract(data, Nested.key("users[*].name"))
#=> ["Alice", "Bob"]

# Use :string mode for JSON-like data with string keys
Nested.get(json_data, Nested.key("users.0.name", :string))
```

### Transforming data with `traverse/2`

The transformation function can return `:discard`, `{:skip, item}`, `{:next, item}`, or a bare item (equivalent to `{:next, item}`):

```elixir
user_data = %{
  name: "Alice",
  email: "alice@example.com",
  password: "secret123"
}

Nested.traverse(user_data, fn
  {:password, _} -> :discard
  item -> item
end)
#=> %{name: "Alice", email: "alice@example.com"}
```

### Utility functions

```elixir
# Remove all nil values, recursively
Nested.clean_nil(%{name: "Alice", email: nil, profile: %{bio: nil}})
#=> %{name: "Alice", profile: %{}}

# Convert structs to plain maps (preserving DateTime/Date/Time/NaiveDateTime)
Nested.to_map(%User{name: "Alice", created_at: ~U[2023-01-01 00:00:00Z]})
#=> %{name: "Alice", created_at: ~U[2023-01-01 00:00:00Z]}

# Optionally normalize keys at the same time (:keep default, :atom, or :string)
Nested.to_map(%{"name" => "Alice", "profile" => %{"age" => 30}}, :atom)
#=> %{name: "Alice", profile: %{age: 30}}

# Censor sensitive fields by keyword match
Nested.censor(%{username: "alice", password: "secret"}, ["pass"])
#=> %{username: "alice", password: "***"}

# Trim strings and turn blank strings into nil (e.g. for form/query params)
Nested.scrub_params(%{"name" => "  Alice  ", "nickname" => "   "})
#=> %{"name" => "Alice", "nickname" => nil}

# Deep merge maps, recursing into nested maps
Nested.merge(
  %{database: %{host: "localhost", port: 5432}},
  %{database: %{host: "prod-db"}}
)
#=> %{database: %{host: "prod-db", port: 5432}}
```

## Testing

```
mix test
```
