defmodule Nested do
  @moduledoc """
  Nested provides utilities for accessing, extracting, and manipulating nested data structures
  in Elixir maps and lists with ease and safety.

  This module is particularly useful when working with:
  - JSON-like data structures
  - Configuration maps
  - API responses with nested data
  - Complex data transformations

  ## Key Features

  - **Safe navigation**: Gracefully handles missing paths without raising exceptions
  - **Flexible path syntax**: Supports integers, atoms, maps for filtering, and functions
  - **Map filtering**: Find list items by matching specific criteria
  - **Deep traversal**: Transform entire data structures with custom logic
  - **Struct handling**: Automatically converts structs while preserving special types

  ## Path Syntax

  Paths are lists that can contain:
  - `integer` - List index or map key
  - `atom` - Map key or keyword list key
  - `string` - Map string key
  - `map` - Filter criteria for finding items in lists
  - `function/1` - Custom predicate for finding items in lists
  - `"*"` - Wildcard to match all items (extract only)

  ## Examples

  Basic usage with nested maps and lists:

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

      # Map filtering - find user by criteria
      Nested.get(data, [:users, %{active: true}, :name])
      #=> "Alice"

      # Function filtering - find user with custom logic
      Nested.get(data, [:users, &(&1.age > 26), :name])
      #=> "Alice"

      # Extract all matching values
      Nested.extract(data, [:users, "*", :name])
      #=> ["Alice", "Bob"]

  ## Query String Syntax

  For convenience, you can also use query strings with `Nested.key/2`:

      # Basic dot notation
      Nested.get(data, Nested.key("users.0.name"))
      #=> "Alice"

      # Bracket filtering
      Nested.get(data, Nested.key("users[active=true].name"))
      #=> "Alice"

      # Extract with wildcards
      Nested.extract(data, Nested.key("users[*].name"))
      #=> ["Alice", "Bob"]

      # String keys for JSON data
      Nested.get(json_data, Nested.key("users.0.name", :string))

  """

  @doc """
  Parse a query string into a path list for use with other Nested functions.

  This function converts a human-readable query string into the path format
  used by `get/3`, `fetch/2`, `extract/2`, and other functions.

  ## Parameters

  - `query_string` - String representation of the path
  - `key_type` - Default type for dot notation keys (`:atom` or `:string`, defaults to `:atom`)

  ## Examples

      # Basic usage
      Nested.key("users.0.name")
      #=> [:users, 0, :name]

      # String keys mode
      Nested.key("config.database.host", :string)  
      #=> ["config", "database", "host"]

      # Use with other functions
      path = Nested.key("users[active=true].0.name")
      Nested.get(data, path)

  For full syntax documentation, see `Nested.QueryParser.parse/2`.
  """
  @spec key(String.t(), :atom | :string) :: list()
  def key(query_string, key_type \\ :atom) do
    Nested.QueryParser.parse(query_string, key_type)
  end

  @doc """
  Safely query data nested in maps and lists, returning a default value if the path doesn't exist.

  This is the safest way to access nested data as it never raises exceptions.

  ## Parameters

  - `object` - The data structure to query (map or list)
  - `paths` - List of keys/indices/filters defining the path to the desired value
  - `default` - Value to return if path doesn't exist (defaults to `nil`)

  ## Examples

      data = %{
        users: [
          %{name: "Alice", skills: ["elixir", "js"]},
          %{name: "Bob", skills: ["python"]}
        ]
      }

      # Basic access
      Nested.get(data, [:users, 0, :name])
      #=> "Alice"

      # With custom default
      Nested.get(data, [:users, 5, :name], "Unknown")
      #=> "Unknown"

      # Map filtering
      Nested.get(data, [:users, %{name: "Bob"}, :skills])
      #=> ["python"]

      # Function filtering
      has_elixir = fn user -> "elixir" in user.skills end
      Nested.get(data, [:users, has_elixir, :name])
      #=> "Alice"

      # Keyword lists
      config = [database: [host: "localhost", port: 5432]]
      Nested.get(config, [:database, :host])
      #=> "localhost"

  """
  def get(object, paths, default \\ nil) do
    case fetch(object, paths) do
      {:ok, data} -> data
      :error -> default
    end
  end

  @doc """
  Query data nested in maps and lists, returning `{:ok, value}` or `:error`.

  This function provides explicit error handling for cases where you need to distinguish
  between a successful lookup that returns `nil` and a failed lookup.

  ## Parameters

  - `object` - The data structure to query (map or list)
  - `paths` - List of keys/indices/filters defining the path to the desired value

  ## Returns

  - `{:ok, value}` - If the path exists and leads to a value
  - `:error` - If the path doesn't exist or any step fails

  ## Examples

      data = %{
        users: [
          %{name: "Alice", email: nil},
          %{name: "Bob", email: "bob@example.com"}
        ]
      }

      # Successful lookup
      Nested.fetch(data, [:users, 0, :name])
      #=> {:ok, "Alice"}

      # Successful lookup returning nil
      Nested.fetch(data, [:users, 0, :email])
      #=> {:ok, nil}

      # Failed lookup
      Nested.fetch(data, [:users, 5, :name])
      #=> :error

      # Map filtering
      Nested.fetch(data, [:users, %{email: "bob@example.com"}, :name])
      #=> {:ok, "Bob"}

      # No match found
      Nested.fetch(data, [:users, %{email: "nonexistent@example.com"}, :name])
      #=> :error

  ## Advanced Filtering

  ### Map Filtering
  Find items in lists by matching map criteria:

      users = [
        %{name: "Alice", role: "admin", active: true},
        %{name: "Bob", role: "user", active: false}
      ]

      # Find admin user
      Nested.fetch(%{users: users}, [:users, %{role: "admin"}, :name])
      #=> {:ok, "Alice"}

      # Find by multiple criteria
      Nested.fetch(%{users: users}, [:users, %{role: "admin", active: true}, :name])
      #=> {:ok, "Alice"}

  ### Function Filtering
  Use custom predicates for complex matching:

      # Find user with specific condition
      older_than_25 = fn user -> user.age > 25 end
      Nested.fetch(data, [:users, older_than_25, :name])

  """
  def fetch(nil, _) do
    :error
  end

  def fetch(value, []), do: {:ok, value}

  def fetch(object, [key | tail]) when is_map(object) do
    case Map.fetch(object, key) do
      {:ok, value} ->
        fetch(value, tail)

      error ->
        error
    end
  end

  def fetch(list, [key | tail]) when is_list(list) do
    cond do
      is_integer(key) ->
        case Enum.fetch(list, key) do
          {:ok, value} -> fetch(value, tail)
          error -> error
        end

      is_atom(key) ->
        case Keyword.fetch(list, key) do
          {:ok, value} -> fetch(value, tail)
          error -> error
        end

      is_map(key) ->
        case Enum.find(list, &item_matched?(&1, key)) do
          nil -> :error
          value -> fetch(value, tail)
        end

      is_function(key, 1) ->
        case Enum.find(list, key) do
          nil -> :error
          value -> fetch(value, tail)
        end

      true ->
        :error
    end
  end

  @doc """
  Extract multiple values from nested data structures using pattern matching and wildcards.

  > #### Deprecated {: .warning}
  >
  > For known/static data shapes, prefer plain `Enum` functions
  > (`Enum.map/2`, `Enum.flat_map/2`) directly — they're simpler and more
  > idiomatic. `extract/2` mainly earns its keep when the path itself is
  > dynamic (e.g. built at runtime via `key/2`) or the data may be missing
  > intermediate keys and you want `[]` instead of an exception.

  This function is powerful for collecting data from multiple locations in complex structures.
  Unlike `get/3` and `fetch/2` which return single values, `extract/2` always returns a list
  of all matching values.

  ## Parameters

  - `object` - The data structure to query (map or list)
  - `paths` - List of keys/indices/filters, may include wildcards (`"*"`)

  ## Returns

  Always returns a list, empty if no matches found.

  ## Wildcard Usage

  Use `"*"` to match all items in a list:

      data = %{
        teams: [
          %{name: "Backend", members: ["Alice", "Bob"]},
          %{name: "Frontend", members: ["Charlie", "Diana"]}
        ]
      }

      # Get all team names
      Nested.extract(data, [:teams, "*", :name])
      #=> ["Backend", "Frontend"]

      # Get all member lists
      Nested.extract(data, [:teams, "*", :members])
      #=> [["Alice", "Bob"], ["Charlie", "Diana"]]

  ## Filtering Examples

      users = [
        %{name: "Alice", department: "Engineering", active: true},
        %{name: "Bob", department: "Sales", active: false},
        %{name: "Charlie", department: "Engineering", active: true}
      ]

      data = %{users: users}

      # Extract all user names
      Nested.extract(data, [:users, "*", :name])
      #=> ["Alice", "Bob", "Charlie"]

      # Extract names of active users only
      Nested.extract(data, [:users, %{active: true}, :name])
      #=> ["Alice", "Charlie"]

      # Extract names of engineering department
      Nested.extract(data, [:users, %{department: "Engineering"}, :name])
      #=> ["Alice", "Charlie"]

      # Extract with function filtering
      senior_users = fn user -> user.experience_years > 5 end
      Nested.extract(data, [:users, senior_users, :name])

  ## Complex Nested Extraction

      company = %{
        departments: [
          %{
            name: "Engineering",
            teams: [
              %{name: "Backend", skills: ["elixir", "postgres"]},
              %{name: "Frontend", skills: ["react", "typescript"]}
            ]
          },
          %{
            name: "Design",
            teams: [
              %{name: "UX", skills: ["figma", "research"]},
              %{name: "Visual", skills: ["photoshop", "illustration"]}
            ]
          }
        ]
      }

      # Get all team names across all departments
      Nested.extract(company, [:departments, "*", :teams, "*", :name])
      #=> ["Backend", "Frontend", "UX", "Visual"]

      # Get all skills across all teams
      Nested.extract(company, [:departments, "*", :teams, "*", :skills])
      #=> [["elixir", "postgres"], ["react", "typescript"], ["figma", "research"], ["photoshop", "illustration"]]

  """
  @deprecated "Use Enum functions (e.g. Enum.map/2, Enum.flat_map/2) directly for known/static paths"
  @spec extract(map | list, list) :: list
  def extract(object, [key | tail]) when is_map(object) do
    case Map.fetch(object, key) do
      {:ok, value} ->
        extract(value, tail)

      _error ->
        []
    end
  end

  def extract(list, [key | tail]) when is_list(list) do
    cond do
      key == "*" ->
        # match all
        list
        |> Enum.map(&extract(&1, tail))
        |> Enum.concat()

      is_integer(key) ->
        case Enum.fetch(list, key) do
          {:ok, value} -> extract(value, tail)
          _error -> []
        end

      is_atom(key) ->
        case Keyword.fetch(list, key) do
          {:ok, value} -> extract(value, tail)
          _error -> []
        end

      is_map(key) ->
        list
        |> Enum.filter(&item_matched?(&1, key))
        |> Enum.map(&extract(&1, tail))
        |> Enum.concat()

      is_function(key, 1) ->
        list
        |> Enum.filter(key)
        |> Enum.map(&extract(&1, tail))
        |> Enum.concat()

      true ->
        []
    end
  end

  def extract(value, []), do: [value]
  def extract(_, _), do: []

  # check if map meets criterials
  defp item_matched?(item, criterials) when is_map(item) and is_map(criterials) do
    criterials == Map.take(item, Map.keys(criterials))
  end

  defp item_matched?(_, _), do: false

  @doc """
  Traverse nested data structures and apply transformations to each element.

  This is the most powerful function in the module, allowing you to walk through
  and transform entire data structures with fine-grained control over the process.

  ## Parameters

  - `object` - The data structure to traverse (map, list, or struct)
  - `fun` - Function that receives each item and returns a transformation directive

  ## Transformation Directives

  The transformation function can return:

  - `:discard` - Remove the item completely
  - `{:skip, item}` - Keep the item but don't traverse its children
  - `{:next, item}` - Transform the item and continue traversing its children
  - `item` - Equivalent to `{:next, item}`

  ## Examples

  ### Basic Transformation

      data = %{
        name: "Product",
        price: 100,
        tags: ["electronics", "gadget"]
      }

      # Double all numeric values
      Nested.traverse(data, fn
        {key, value} when is_number(value) -> {key, value * 2}
        item -> item
      end)
      #=> %{name: "Product", price: 200, tags: ["electronics", "gadget"]}

  ### Removing Data

      user_data = %{
        name: "Alice",
        email: "alice@example.com",
        password: "secret123",
        internal_id: "xyz789"
      }

      # Remove sensitive data
      Nested.traverse(user_data, fn
        {:password, _} -> :discard
        {:internal_id, _} -> :discard
        item -> item
      end)
      #=> %{name: "Alice", email: "alice@example.com"}

  ### Complex Data Cleaning

      api_response = %{
        users: [
          %{name: "Alice", temp_token: "abc", profile: %{age: 30, _debug: "info"}},
          %{name: "Bob", temp_token: "def", profile: %{age: 25, _debug: "info"}}
        ],
        _metadata: %{request_id: "123", debug: true}
      }

      # Remove temporary and debug data
      Nested.traverse(api_response, fn
        {:temp_token, _} -> :discard
        {key, _} when is_atom(key) and String.starts_with?(Atom.to_string(key), "_") -> :discard
        item -> item
      end)

  ### Conditional Processing

      # Skip processing certain branches
      Nested.traverse(data, fn
        {:sensitive_data, value} -> {:skip, {:sensitive_data, value}}  # Don't traverse children
        {:public_data, value} -> {:next, {:public_data, process(value)}}  # Transform and traverse
        item -> item
      end)

  ## Struct Handling

  The function automatically converts structs to maps (except for special types like DateTime):

      defmodule User do
        defstruct [:name, :email]
      end

      user = %User{name: "Alice", email: "alice@example.com"}

      Nested.traverse(%{user: user}, fn item -> item end)
      #=> %{user: %{name: "Alice", email: "alice@example.com"}}

  Special types that are preserved:
  - `DateTime`
  - `NaiveDateTime`
  - `Date`
  - `Time`

  ## Performance Notes

  - The function creates new data structures; it doesn't modify in place
  - For large datasets, consider processing in chunks or using streams
  - Struct conversion has minimal overhead but creates new maps

  """
  @ignore_types [DateTime, NaiveDateTime, Date, Time]
  def traverse(%type{} = object, _) when type in @ignore_types, do: object
  def traverse(object, fun) when is_struct(object), do: traverse(Map.from_struct(object), fun)

  def traverse(object, fun) when is_map(object) do
    Enum.reduce(object, %{}, fn {key, value}, acc ->
      case fun.({key, value}) do
        :discard -> acc
        {:skip, {key, value}} -> Map.put(acc, key, value)
        {:next, {key, value}} -> Map.put(acc, key, traverse(value, fun))
        {key, value} -> Map.put(acc, key, traverse(value, fun))
      end
    end)
  end

  def traverse(object, fun) when is_list(object) do
    object
    |> Enum.reduce([], fn item, acc ->
      case fun.(item) do
        :discard -> acc
        {:skip, item} -> [item | acc]
        {:next, item} -> [traverse(item, fun) | acc]
        item -> [traverse(item, fun) | acc]
      end
    end)
    |> Enum.reverse()
  end

  def traverse(object, _fun), do: object

  @doc """
  Remove all `nil` values from nested maps and lists.

  This function is useful for cleaning up data structures that may contain
  unwanted `nil` values, often resulting from API responses or incomplete data.

  ## Examples

      # Clean map with nil values
      data = %{
        name: "Alice",
        email: nil,
        profile: %{
          age: 30,
          bio: nil,
          settings: %{theme: "dark", notifications: nil}
        }
      }

      Nested.clean_nil(data)
      #=> %{
        name: "Alice",
        profile: %{
          age: 30,
          settings: %{theme: "dark"}
        }
      }

      # Clean list with nil values
      users = [
        %{name: "Alice", email: "alice@example.com"},
        nil,
        %{name: "Bob", email: nil}
      ]

      Nested.clean_nil(users)
      #=> [
        %{name: "Alice", email: "alice@example.com"},
        %{name: "Bob"}
      ]

  ## Use Cases

  - Cleaning API response data before storage
  - Preparing data for JSON serialization
  - Removing optional fields that weren't provided
  - Database record cleanup

  """
  def clean_nil(object) do
    traverse(object, fn
      nil -> :discard
      {_, nil} -> :discard
      value -> {:next, value}
    end)
  end

  @doc """
  Convert structs to maps by removing internal Elixir metadata.

  This function recursively converts all structs in a data structure to plain maps
  while preserving special types like DateTime. It's useful for serialization,
  logging, or when you need plain data structures.

  ## Parameters

  - `struct` - The data structure to convert (struct, map, or list)
  - `key_type` - How to normalize map keys (defaults to `:keep`):
    - `:keep` - leave keys as they are
    - `:atom` - convert all keys to atoms
    - `:string` - convert all keys to strings

  ## Examples

      defmodule User do
        defstruct [:name, :email, :created_at]
      end

      defmodule Company do
        defstruct [:name, :users]
      end

      user1 = %User{name: "Alice", email: "alice@example.com", created_at: ~U[2023-01-01 00:00:00Z]}
      user2 = %User{name: "Bob", email: "bob@example.com", created_at: ~U[2023-01-02 00:00:00Z]}

      company = %Company{
        name: "Tech Corp",
        users: [user1, user2]
      }

      Nested.to_map(company)
      #=> %{
        name: "Tech Corp",
        users: [
          %{name: "Alice", email: "alice@example.com", created_at: ~U[2023-01-01 00:00:00Z]},
          %{name: "Bob", email: "bob@example.com", created_at: ~U[2023-01-02 00:00:00Z]}
        ]
      }

  ## Normalizing Keys

      data = %{"name" => "Alice", "profile" => %{"age" => 30}}

      Nested.to_map(data, :atom)
      #=> %{name: "Alice", profile: %{age: 30}}

      data = %{name: "Alice", profile: %{age: 30}}

      Nested.to_map(data, :string)
      #=> %{"name" => "Alice", "profile" => %{"age" => 30}}

  ## Preserved Types

  These special types are NOT converted to maps:
  - `DateTime`
  - `NaiveDateTime`
  - `Date`
  - `Time`

  ## Use Cases

  - Preparing struct data for JSON serialization
  - Logging structured data without internal metadata
  - Converting Ecto schemas to plain maps
  - API response formatting
  - Normalizing keys of data decoded from JSON (string keys) to atoms, or vice versa

  """
  @spec to_map(any(), :keep | :atom | :string) :: any()
  def to_map(struct, key_type \\ :keep)

  def to_map(struct, key_type) when key_type in [:keep, :atom, :string] do
    traverse(struct, fn
      %type{} = value when type in @ignore_types -> {:skip, value}
      value when is_struct(value) -> {:next, Map.drop(value, [:__struct__, :__meta__])}
      {key, value} -> {:next, {convert_key(key, key_type), value}}
      value -> {:next, value}
    end)
  end

  def to_map(_struct, key_type) do
    raise ArgumentError, "key_type must be :keep, :atom, or :string, got: #{inspect(key_type)}"
  end

  defp convert_key(key, :keep), do: key
  defp convert_key(key, :atom) when is_atom(key), do: key
  defp convert_key(key, :atom), do: key |> to_string() |> String.to_atom()
  defp convert_key(key, :string) when is_binary(key), do: key
  defp convert_key(key, :string), do: to_string(key)

  @doc """
  Replace values with `"***"` for keys that contain any of the specified keywords.

  This function is useful for sanitizing sensitive data in logs, API responses,
  or when displaying data to users who shouldn't see certain fields.

  ## Parameters

  - `object` - The data structure to censor
  - `keywords` - List of strings to match against key names (case-sensitive, partial matching)

  ## Examples

      user_data = %{
        username: "alice",
        email: "alice@example.com",
        password: "secret123",
        api_token: "abc123xyz",
        user_preferences: %{theme: "dark"}
      }

      # Censor password-related fields
      Nested.censor(user_data, ["pass", "token", "secret"])
      #=> %{
        username: "alice",
        email: "alice@example.com",
        password: "***",
        api_token: "***",
        user_preferences: %{theme: "dark"}
      }

      # Censor nested sensitive data
      api_response = %{
        users: [
          %{name: "Alice", social_security: "123-45-6789", email: "alice@example.com"},
          %{name: "Bob", social_security: "987-65-4321", email: "bob@example.com"}
        ],
        admin_password: "supersecret"
      }

      Nested.censor(api_response, ["social", "password"])
      #=> %{
        users: [
          %{name: "Alice", social_security: "***", email: "alice@example.com"},
          %{name: "Bob", social_security: "***", email: "bob@example.com"}
        ],
        admin_password: "***"
      }

  ## Matching Behavior

  - Matching is **case-sensitive**
  - Uses **partial matching** (substring search)
  - Checks against the string representation of keys
  - Works with atom keys, string keys, and any key type that can be converted to string

  ## Use Cases

  - Sanitizing logs before writing to files
  - Preparing data for display in admin interfaces
  - Removing sensitive data from error reports
  - Creating safe data dumps for debugging

  """
  def censor(object, keywords) when is_list(keywords) do
    traverse(object, fn
      {key, value} ->
        should_censor? = Enum.any?(keywords, &String.contains?(to_string(key), &1))

        if should_censor? do
          {:skip, {key, "***"}}
        else
          {:next, {key, value}}
        end

      value ->
        {:next, value}
    end)
  end

  @doc """
  Recursively trim string values and convert blank strings to `nil`.

  This mirrors the "scrub" behavior common in web frameworks: whitespace-only
  or empty string values (typically submitted through forms or query params)
  are normalized to `nil` so presence validations behave consistently.
  Non-string values, and the shape of the data (keys, list length), are left
  untouched.

  ## Examples

      params = %{
        "name" => "  Alice  ",
        "nickname" => "   ",
        "email" => "",
        "tags" => ["ruby", "  ", ""],
        "age" => 30
      }

      Nested.scrub_params(params)
      #=> %{
        "name" => "Alice",
        "nickname" => nil,
        "email" => nil,
        "tags" => ["ruby", nil, nil],
        "age" => 30
      }

  Combine with `clean_nil/1` to drop the resulting blank entries entirely:

      params
      |> Nested.scrub_params()
      |> Nested.clean_nil()

  ## Use Cases

  - Normalizing form/query params before casting into a changeset
  - Making blank-string and missing-key inputs equivalent for validation
  - Cleaning up user-submitted text fields before further processing

  """
  @spec scrub_params(any()) :: any()
  def scrub_params(object) do
    traverse(object, fn
      {key, value} when is_binary(value) -> {:next, {key, scrub_value(value)}}
      value when is_binary(value) -> {:next, scrub_value(value)}
      item -> item
    end)
  end

  defp scrub_value(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  @doc """
  Deeply merge two maps, recursively combining nested maps.

  When the same key exists in both maps:
  - If both values are maps, they are merged recursively
  - Otherwise, the value from the right map takes precedence

  ## Parameters

  - `left` - The base map
  - `right` - The map to merge into the base map (takes precedence)

  ## Examples

      # Simple merge
      config_defaults = %{
        database: %{host: "localhost", port: 5432, pool_size: 10},
        cache: %{enabled: false, ttl: 3600}
      }

      user_config = %{
        database: %{host: "prod-db.example.com", pool_size: 20},
        cache: %{enabled: true},
        logging: %{level: :info}
      }

      Nested.merge(config_defaults, user_config)
      #=> %{
        database: %{host: "prod-db.example.com", port: 5432, pool_size: 20},
        cache: %{enabled: true, ttl: 3600},
        logging: %{level: :info}
      }

  ## Conflict Resolution

      base = %{
        settings: %{theme: "light", lang: "en"},
        data: [1, 2, 3]
      }

      override = %{
        settings: %{theme: "dark"},  # Map: merged recursively
        data: [4, 5, 6]              # Non-map: completely replaced
      }

      Nested.merge(base, override)
      #=> %{
        settings: %{theme: "dark", lang: "en"},  # Recursive merge preserves 'lang'
        data: [4, 5, 6]                          # Complete replacement
      }

  ## Use Cases

  - Configuration management with defaults and overrides
  - Combining user preferences with system defaults
  - Merging API response data
  - Building composite data structures from multiple sources

  ## Performance Notes

  - Creates new data structures; doesn't modify originals
  - Recursion depth matches the nesting depth of your data
  - Efficient for typical configuration and data merging scenarios

  """
  def merge(left, right) do
    Map.merge(left, right, &deep_resolve/3)
  end

  # Key exists in both maps, and both values are maps as well.
  # These can be merged recursively.
  defp deep_resolve(_key, left = %{}, right = %{}) do
    merge(left, right)
  end

  # Key exists in both maps, but at least one of the values is
  # NOT a map. We fall back to standard merge behavior, preferring
  # the value on the right.
  defp deep_resolve(_key, _left, right) do
    right
  end
end
