defmodule NestedTest do
  use ExUnit.Case
  doctest Nested

  # Test structs
  defmodule TestStruct do
    defstruct [:name, :value, :age]
  end

  defmodule Address do
    defstruct [:street, :city]
  end

  defmodule Person do
    defstruct [:name, :address]
  end

  # Test data
  @test_data %{
    users: [
      %{name: "user1", is_active: true, skills: ["js", "html"], age: 25},
      %{name: "user2", is_active: false, skills: ["elixir", "sql"], age: 30}
    ],
    config: %{
      database: %{host: "localhost", port: 5432},
      cache: %{enabled: true}
    },
    tags: ["important", "test"]
  }

  describe "get/3" do
    test "returns value for valid path" do
      assert Nested.get(@test_data, [:users, 0, :name]) == "user1"
      assert Nested.get(@test_data, [:config, :database, :host]) == "localhost"
      assert Nested.get(@test_data, [:tags, 1]) == "test"
    end

    test "returns default for invalid path" do
      assert Nested.get(@test_data, [:users, 5, :name]) == nil
      assert Nested.get(@test_data, [:invalid, :path], "default") == "default"
    end

    test "works with map filtering" do
      assert Nested.get(@test_data, [:users, %{is_active: true}, :name]) == "user1"
      assert Nested.get(@test_data, [:users, %{age: 30}, :skills]) == ["elixir", "sql"]
    end

    test "works with function filtering" do
      older_than_25 = fn user -> user.age > 25 end
      assert Nested.get(@test_data, [:users, older_than_25, :name]) == "user2"
    end

    test "handles keyword lists" do
      keyword_data = [users: [name: "test", active: true]]
      assert Nested.get(keyword_data, [:users, :name]) == "test"
    end
  end

  describe "fetch/2" do
    test "returns {:ok, value} for valid path" do
      assert Nested.fetch(@test_data, [:users, 0, :name]) == {:ok, "user1"}

      assert Nested.fetch(@test_data, [:config, :database]) ==
               {:ok, %{host: "localhost", port: 5432}}
    end

    test "returns :error for invalid path" do
      assert Nested.fetch(@test_data, [:users, 5, :name]) == :error
      assert Nested.fetch(@test_data, [:invalid]) == :error
    end

    test "returns :error for nil input" do
      assert Nested.fetch(nil, [:any, :path]) == :error
    end

    test "returns {:ok, value} for empty path" do
      assert Nested.fetch(@test_data, []) == {:ok, @test_data}
    end

    test "works with map filtering" do
      assert Nested.fetch(@test_data, [:users, %{is_active: false}, :skills]) ==
               {:ok, ["elixir", "sql"]}
    end

    test "returns :error when map filter doesn't match" do
      assert Nested.fetch(@test_data, [:users, %{age: 40}, :name]) == :error
    end
  end

  describe "extract/2" do
    test "extracts all items with wildcard" do
      result = Nested.extract(@test_data, [:users, "*", :name])
      assert result == ["user1", "user2"]
    end

    test "extracts multiple nested values" do
      result = Nested.extract(@test_data, [:users, "*", :skills])
      assert result == [["js", "html"], ["elixir", "sql"]]
    end

    test "extracts with map filtering" do
      result = Nested.extract(@test_data, [:users, %{is_active: true}, :skills])
      assert result == [["js", "html"]]
    end

    test "extracts with function filtering" do
      older_than_25 = fn user -> user.age > 25 end
      result = Nested.extract(@test_data, [:users, older_than_25, :name])
      assert result == ["user2"]
    end

    test "returns empty list for invalid path" do
      assert Nested.extract(@test_data, [:invalid, "*", :name]) == []
    end

    test "extracts single value" do
      result = Nested.extract(@test_data, [:config, :database, :host])
      assert result == ["localhost"]
    end

    test "handles integer index" do
      result = Nested.extract(@test_data, [:users, 1, :name])
      assert result == ["user2"]
    end
  end

  describe "traverse/2" do
    test "transforms all values" do
      result =
        Nested.traverse(%{a: 1, b: 2}, fn
          {key, value} -> {key, value * 2}
        end)

      assert result == %{a: 2, b: 4}
    end

    test "discards items" do
      result =
        Nested.traverse(@test_data, fn
          {:is_active, _} -> :discard
          item -> item
        end)

      user1 = result.users |> Enum.at(0)
      user2 = result.users |> Enum.at(1)

      refute Map.has_key?(user1, :is_active)
      refute Map.has_key?(user2, :is_active)
    end

    test "skips nested traversal" do
      result =
        Nested.traverse(@test_data, fn
          {:config, value} -> {:skip, {:config, value}}
          item -> item
        end)

      assert result.config == @test_data.config
    end

    test "uses :next for explicit traversal" do
      result =
        Nested.traverse(%{a: %{b: 1}}, fn
          {key, value} -> {:next, {key, value}}
        end)

      assert result == %{a: %{b: 1}}
    end

    test "handles lists" do
      result =
        Nested.traverse([1, 2, 3], fn
          2 -> :discard
          x -> x * 2
        end)

      assert result == [2, 6]
    end

    test "preserves DateTime types" do
      now = DateTime.utc_now()
      data = %{created_at: now}

      result = Nested.traverse(data, fn item -> item end)
      assert result.created_at == now
    end

    test "converts structs to maps" do
      struct_data = %{item: %NestedTest.TestStruct{name: "test", value: 42}}

      result = Nested.traverse(struct_data, fn item -> item end)
      assert result == %{item: %{name: "test", value: 42, age: nil}}
    end
  end

  describe "clean_nil/1" do
    test "removes nil values from map" do
      data = %{a: 1, b: nil, c: %{d: nil, e: 2}}
      result = Nested.clean_nil(data)
      assert result == %{a: 1, c: %{e: 2}}
    end

    test "removes nil values from list" do
      data = [1, nil, 2, %{a: nil, b: 3}]
      result = Nested.clean_nil(data)
      assert result == [1, 2, %{b: 3}]
    end

    test "handles nested structures" do
      data = %{
        users: [
          %{name: "user1", email: nil},
          nil,
          %{name: "user2", email: "user2@test.com"}
        ],
        config: nil
      }

      result = Nested.clean_nil(data)

      expected = %{
        users: [
          %{name: "user1"},
          %{name: "user2", email: "user2@test.com"}
        ]
      }

      assert result == expected
    end
  end

  describe "to_map/1" do
    test "converts struct to map" do
      struct_data = %NestedTest.TestStruct{name: "test", age: 25}
      result = Nested.to_map(struct_data)

      assert result == %{name: "test", age: 25, value: nil}
      refute Map.has_key?(result, :__struct__)
    end

    test "handles nested structs" do
      data = %NestedTest.Person{
        name: "John",
        address: %NestedTest.Address{street: "Main St", city: "NYC"}
      }

      result = Nested.to_map(data)

      expected = %{
        name: "John",
        address: %{street: "Main St", city: "NYC"}
      }

      assert result == expected
    end

    test "preserves DateTime structs" do
      now = DateTime.utc_now()
      data = %{created_at: now, updated_at: nil}

      result = Nested.to_map(data)
      assert result.created_at == now
    end
  end

  describe "censor/2" do
    test "censors matching keys" do
      data = %{
        username: "john",
        password: "secret123",
        email: "john@test.com"
      }

      result = Nested.censor(data, ["pass", "secret"])

      assert result == %{
               username: "john",
               password: "***",
               email: "john@test.com"
             }
    end

    test "censors nested values" do
      result = Nested.censor(@test_data, ["active", "skills"])

      user1 = result.users |> Enum.at(0)
      user2 = result.users |> Enum.at(1)

      assert user1.is_active == "***"
      assert user1.skills == "***"
      assert user2.is_active == "***"
      assert user2.skills == "***"

      # Non-matching keys should remain unchanged
      assert user1.name == "user1"
      assert user2.name == "user2"
    end

    test "handles partial key matches" do
      data = %{user_password: "secret", password_reset: "token"}
      result = Nested.censor(data, ["pass"])

      assert result == %{user_password: "***", password_reset: "***"}
    end
  end

  describe "merge/2" do
    test "merges simple maps" do
      left = %{a: 1, b: 2}
      right = %{b: 3, c: 4}

      result = Nested.merge(left, right)
      assert result == %{a: 1, b: 3, c: 4}
    end

    test "merges nested maps recursively" do
      left = %{
        user: %{name: "John", age: 25},
        config: %{theme: "dark"}
      }

      right = %{
        user: %{age: 26, email: "john@test.com"},
        config: %{lang: "en"}
      }

      result = Nested.merge(left, right)

      expected = %{
        user: %{name: "John", age: 26, email: "john@test.com"},
        config: %{theme: "dark", lang: "en"}
      }

      assert result == expected
    end

    test "prefers right values for non-map conflicts" do
      left = %{data: [1, 2, 3]}
      right = %{data: "string"}

      result = Nested.merge(left, right)
      assert result == %{data: "string"}
    end

    test "handles deeply nested structures" do
      left = %{
        level1: %{
          level2: %{
            level3: %{a: 1, b: 2}
          }
        }
      }

      right = %{
        level1: %{
          level2: %{
            level3: %{b: 3, c: 4}
          }
        }
      }

      result = Nested.merge(left, right)

      expected = %{
        level1: %{
          level2: %{
            level3: %{a: 1, b: 3, c: 4}
          }
        }
      }

      assert result == expected
    end
  end

  describe "key/2 query string parsing" do
    test "basic query string parsing" do
      assert Nested.key("users.0.name") == [:users, 0, :name]
      assert Nested.key("config.database.host", :string) == ["config", "database", "host"]
    end

    test "integration with get/3" do
      data = %{
        users: [
          %{name: "Alice", active: true},
          %{name: "Bob", active: false}
        ]
      }

      # Using query strings
      assert Nested.get(data, Nested.key("users.0.name")) == "Alice"
      assert Nested.get(data, Nested.key("users[active=true].name")) == "Alice"
      assert Nested.get(data, Nested.key("users[active=false].name")) == "Bob"
    end

    test "integration with fetch/2" do
      data = %{config: %{database: %{host: "localhost"}}}

      assert Nested.fetch(data, Nested.key("config.database.host")) == {:ok, "localhost"}
      assert Nested.fetch(data, Nested.key("config.missing.key")) == :error
    end

    test "integration with extract/2" do
      data = %{
        users: [
          %{name: "Alice", skills: ["elixir", "js"]},
          %{name: "Bob", skills: ["python", "go"]}
        ]
      }

      result = Nested.extract(data, Nested.key("users[*].name"))
      assert result == ["Alice", "Bob"]

      result2 = Nested.extract(data, Nested.key("users[*].skills"))
      assert result2 == [["elixir", "js"], ["python", "go"]]
    end

    test "works with string keys for JSON-like data" do
      json_data = %{
        "users" => [
          %{"name" => "Alice", "active" => true},
          %{"name" => "Bob", "active" => false}
        ]
      }

      path = Nested.key("users.0.name", :string)
      assert Nested.get(json_data, path) == "Alice"

      filter_path = Nested.key("users[active=true].name", :string)
      assert Nested.get(json_data, filter_path) == "Alice"
    end
  end

  # Edge cases and error handling
  describe "edge cases" do
    test "handles empty structures" do
      assert Nested.get(%{}, [:key]) == nil
      assert Nested.get([], [0]) == nil
      assert Nested.fetch(%{}, [:key]) == :error
      assert Nested.extract(%{}, [:key]) == []
    end

    test "handles non-map, non-list values" do
      # The fetch function will raise FunctionClauseError for non-map, non-list values
      # This is the expected behavior based on the current implementation
      assert_raise FunctionClauseError, fn ->
        Nested.fetch("string", [:key])
      end

      assert_raise FunctionClauseError, fn ->
        Nested.fetch(123, [0])
      end

      # get/3 also raises FunctionClauseError since it calls fetch/2 internally
      # and doesn't catch FunctionClauseError, only pattern matches on {:ok, data} | :error
      assert_raise FunctionClauseError, fn ->
        Nested.get("string", [:key])
      end

      assert_raise FunctionClauseError, fn ->
        Nested.get(123, [0], "default")
      end
    end

    test "traverse handles primitive values" do
      assert Nested.traverse("string", fn x -> x end) == "string"
      assert Nested.traverse(123, fn x -> x end) == 123
      assert Nested.traverse(true, fn x -> x end) == true
    end
  end
end
