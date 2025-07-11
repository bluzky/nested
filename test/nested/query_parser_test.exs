defmodule Nested.QueryParserTest do
  use ExUnit.Case
  alias Nested.QueryParser

  describe "parse/2 with basic dot notation" do
    test "parses simple path with atoms (default)" do
      assert QueryParser.parse("users.name") == [:users, :name]
      assert QueryParser.parse("config.database.host") == [:config, :database, :host]
    end

    test "parses simple path with strings" do
      assert QueryParser.parse("users.name", :string) == ["users", "name"]
      assert QueryParser.parse("config.database.host", :string) == ["config", "database", "host"]
    end

    test "handles empty string" do
      assert QueryParser.parse("") == []
      assert QueryParser.parse("", :string) == []
    end

    test "handles single segment" do
      assert QueryParser.parse("users") == [:users]
      assert QueryParser.parse("users", :string) == ["users"]
    end
  end

  describe "parse/2 with numeric indices" do
    test "parses integer indices in dot notation" do
      assert QueryParser.parse("users.0.name") == [:users, 0, :name]
      assert QueryParser.parse("data.1.2.value") == [:data, 1, 2, :value]
    end

    test "handles negative indices" do
      assert QueryParser.parse("items.-1.id") == [:items, -1, :id]
    end
  end

  describe "parse/2 with bracket notation" do
    test "parses integer indices in brackets" do
      assert QueryParser.parse("users[0]") == [:users, 0]
      assert QueryParser.parse("users[0].name") == [:users, 0, :name]
    end

    test "parses quoted string keys" do
      assert QueryParser.parse("data['key']") == [:data, "key"]
      assert QueryParser.parse("data[\"key\"]") == [:data, "key"]
      assert QueryParser.parse("config['api-key'].token") == [:config, "api-key", :token]
    end

    test "parses atom keys with colon prefix" do
      assert QueryParser.parse("data[:key]") == [:data, :key]
      assert QueryParser.parse("config[:database].host") == [:config, :database, :host]
    end

    test "handles mixed bracket and dot notation" do
      assert QueryParser.parse("users[0].profile['full-name']") == [
               :users,
               0,
               :profile,
               "full-name"
             ]

      assert QueryParser.parse("config[:env].database.host") == [:config, :env, :database, :host]
    end
  end

  describe "parse/2 with filtering" do
    test "parses simple filter criteria" do
      result = QueryParser.parse("users[name=Alice]")
      assert result == [:users, %{name: "Alice"}]
    end

    test "parses multiple filter criteria" do
      result = QueryParser.parse("users[name=Alice,active=true]")
      assert result == [:users, %{name: "Alice", active: true}]
    end

    test "parses filter with path continuation" do
      result = QueryParser.parse("users[active=true].name")
      assert result == [:users, %{active: true}, :name]
    end

    test "handles different value types in filters" do
      # Integer
      result1 = QueryParser.parse("users[age=30]")
      assert result1 == [:users, %{age: 30}]

      # Float
      result2 = QueryParser.parse("products[price=19.99]")
      assert result2 == [:products, %{price: 19.99}]

      # Boolean
      result3 = QueryParser.parse("users[active=true,verified=false]")
      assert result3 == [:users, %{active: true, verified: false}]

      # String (unquoted)
      result4 = QueryParser.parse("users[role=admin]")
      assert result4 == [:users, %{role: "admin"}]

      # Quoted string
      result5 = QueryParser.parse("users[name='John Doe']")
      assert result5 == [:users, %{name: "John Doe"}]

      # Atom
      result6 = QueryParser.parse("config[env=:production]")
      assert result6 == [:config, %{env: :production}]
    end

    test "handles atom keys in filters" do
      result = QueryParser.parse("users[:role=admin]")
      assert result == [:users, %{role: "admin"}]
    end
  end

  describe "parse/2 with wildcards" do
    test "parses wildcard in bracket notation" do
      assert QueryParser.parse("users[*].name") == [:users, "*", :name]

      assert QueryParser.parse("departments[*].teams[*].name") == [
               :departments,
               "*",
               :teams,
               "*",
               :name
             ]
    end

    test "handles wildcard with string key_type" do
      result = QueryParser.parse("users[*].name", :string)
      assert result == ["users", "*", "name"]
    end
  end

  describe "parse/2 edge cases" do
    test "handles whitespace" do
      assert QueryParser.parse("  users.name  ") == [:users, :name]
      assert QueryParser.parse("users[ name = Alice ]") == [:users, %{name: "Alice"}]
    end

    test "handles complex nested paths" do
      query = "company.departments[name=Engineering].teams[active=true].members[*].profile.name"
      result = QueryParser.parse(query)

      expected = [
        :company,
        :departments,
        %{name: "Engineering"},
        :teams,
        %{active: true},
        :members,
        "*",
        :profile,
        :name
      ]

      assert result == expected
    end

    test "handles special characters in quoted strings" do
      assert QueryParser.parse("data['key-with-dashes']") == [:data, "key-with-dashes"]
      assert QueryParser.parse("data['key with spaces']") == [:data, "key with spaces"]
      assert QueryParser.parse("data['key.with.dots']") == [:data, "key.with.dots"]
    end
  end

  describe "error handling" do
    test "handles invalid key_type" do
      assert_raise ArgumentError, fn ->
        QueryParser.parse("users.name", :invalid)
      end
    end

    test "handles non-string input" do
      assert_raise FunctionClauseError, fn ->
        QueryParser.parse(123)
      end
    end
  end
end
