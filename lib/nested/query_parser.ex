defmodule Nested.QueryParser do
  @moduledoc """
  Simple parser for converting query strings into path lists.
  """

  @doc """
  Parse a query string into a path list.

  ## Examples

      parse("users.0.name")              #=> [:users, 0, :name]
      parse("users[name=Alice].age")     #=> [:users, %{name: "Alice"}, :age]
      parse("users[*].name")             #=> [:users, "*", :name]
  """
  @spec parse(String.t(), :atom | :string) :: list()
  def parse(query_string, key_type \\ :atom) do
    query_string
    |> String.trim()
    |> split_into_parts()
    |> Enum.flat_map(&parse_part(&1, key_type))
  end

  # Split on dots, but keep bracket expressions together
  defp split_into_parts(query_string) do
    # Simple regex to split on dots that aren't inside brackets
    String.split(query_string, ~r/\.(?![^\[]*\])/, trim: true)
  end

  # Parse each part (could be "users", "0", "users[0]", "users[name=Alice]")
  defp parse_part(part, key_type) do
    cond do
      # Has brackets: "users[0]" or "users[name=Alice]" or "users[*]"
      String.contains?(part, "[") ->
        parse_bracket_part(part, key_type)

      # Try integer first
      integer?(part) ->
        [String.to_integer(part)]

      # Otherwise use key_type
      true ->
        case key_type do
          :atom -> [String.to_atom(part)]
          :string -> [part]
          _ -> raise ArgumentError, "key_type must be :atom or :string, got: #{inspect(key_type)}"
        end
    end
  end

  # Parse "users[0]" or "users[name=Alice]" 
  defp parse_bracket_part(part, key_type) do
    case String.split(part, "[", parts: 2) do
      [base, bracket_content] ->
        content = String.trim_trailing(bracket_content, "]")
        
        base_parsed = case key_type do
          :atom -> String.to_atom(base)
          :string -> base
          _ -> raise ArgumentError, "key_type must be :atom or :string, got: #{inspect(key_type)}"
        end
        
        bracket_parsed = parse_bracket_content(content, key_type)
        [base_parsed, bracket_parsed]

      [single] ->
        parse_part(single, key_type)
    end
  end

  # Parse bracket content: "0", "'key'", "*", "name=Alice", "name=Alice,active=true"
  defp parse_bracket_content(content, key_type) do
    content = String.trim(content)

    cond do
      # Wildcard: "*"
      content == "*" ->
        "*"

      # Filter: "name=Alice" or "name=Alice,active=true"
      String.contains?(content, "=") ->
        parse_filter(content, key_type)

      # Quoted string: "'key'" or '"key"'
      quoted_string?(content) ->
        String.slice(content, 1..-2//1)

      # Atom: ":key"
      String.starts_with?(content, ":") ->
        String.slice(content, 1..-1//1) |> String.to_atom()

      # Integer
      integer?(content) ->
        String.to_integer(content)

      # String fallback
      true ->
        content
    end
  end

  # Parse "name=Alice,active=true" into %{name: "Alice", active: true}
  defp parse_filter(filter_string, key_type) do
    filter_string
    |> String.split(",", trim: true)
    |> Enum.map(&parse_filter_pair(&1, key_type))
    |> Map.new()
  end

  # Parse "name=Alice" into {:name, "Alice"}
  defp parse_filter_pair(pair, key_type) do
    case String.split(pair, "=", parts: 2) do
      [key, value] ->
        key = String.trim(key)
        value = String.trim(value)
        
        parsed_key = if String.starts_with?(key, ":") do
          String.slice(key, 1..-1//1) |> String.to_atom()
        else
          case key_type do
            :atom -> String.to_atom(key)
            :string -> key
            _ -> raise ArgumentError, "key_type must be :atom or :string, got: #{inspect(key_type)}"
          end
        end
        
        parsed_value = parse_value(value)
        {parsed_key, parsed_value}

      [key] ->
        parsed_key = case key_type do
          :atom -> String.to_atom(String.trim(key))
          :string -> String.trim(key)
          _ -> raise ArgumentError, "key_type must be :atom or :string, got: #{inspect(key_type)}"
        end
        {parsed_key, true}
    end
  end

  # Parse filter values with type inference
  defp parse_value(value) do
    cond do
      quoted_string?(value) -> String.slice(value, 1..-2//1)
      value == "true" -> true
      value == "false" -> false
      String.starts_with?(value, ":") -> String.slice(value, 1..-1//1) |> String.to_atom()
      integer?(value) -> String.to_integer(value)
      float?(value) -> String.to_float(value)
      true -> value
    end
  end

  # Helper functions
  defp integer?(string), do: Regex.match?(~r/^-?\d+$/, string)
  defp float?(string), do: Regex.match?(~r/^-?\d+\.\d+$/, string)
  defp quoted_string?(string) do
    (String.starts_with?(string, "'") and String.ends_with?(string, "'")) or
    (String.starts_with?(string, "\"") and String.ends_with?(string, "\""))
  end
end