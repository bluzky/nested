defmodule Nested.QueryParser do
  @moduledoc """
  Parser for converting query strings into path lists.

  Implemented as a small recursive-descent scanner over the input binary
  (walking it via function-head pattern matching) rather than regular
  expressions — this avoids fragile lookaheads for things like "split on
  dots, but not the ones inside brackets".
  """

  @doc """
  Parse a query string into a path list.

  ## Examples

      parse("users.0.name")              #=> [:users, 0, :name]
      parse("users[name=Alice].age")     #=> [:users, %{name: "Alice"}, :age]
      parse("users[*].name")             #=> [:users, "*", :name]
  """
  @spec parse(String.t(), :atom | :string) :: list()
  def parse(query_string, key_type \\ :atom)

  def parse(query_string, key_type)
      when is_binary(query_string) and key_type in [:atom, :string] do
    query_string
    |> String.trim()
    |> scan([], key_type)
  end

  def parse(query_string, key_type) when is_binary(query_string) do
    raise ArgumentError, "key_type must be :atom or :string, got: #{inspect(key_type)}"
  end

  # Walks the (already-trimmed) query string one path segment at a time:
  # a bare key ("name"), a key followed by a bracket ("users[0]"), or just
  # a bracket. Each segment is separated from the next by a top-level "."
  # — dots inside "[...]" don't count, since we only look for "." once
  # we're back outside a bracket.
  defp scan("", acc, _key_type), do: Enum.reverse(acc)

  defp scan(query, acc, key_type) do
    {base, rest} = take_base(query, <<>>)

    case rest do
      "[" <> after_bracket ->
        {content, after_close} = take_bracket_content(after_bracket, <<>>)

        new_acc =
          acc
          |> push_key(base, key_type)
          |> push(resolve_bracket_value(String.trim(content), key_type))

        continue(after_close, new_acc, key_type)

      "." <> after_dot ->
        scan(after_dot, push_key(acc, base, key_type), key_type)

      "" ->
        acc
        |> push_key(base, key_type)
        |> Enum.reverse()
    end
  end

  defp continue("", acc, _key_type), do: Enum.reverse(acc)
  defp continue("." <> rest, acc, key_type), do: scan(rest, acc, key_type)
  defp continue(rest, acc, key_type), do: scan(rest, acc, key_type)

  defp push(acc, value), do: [value | acc]
  defp push_key(acc, "", _key_type), do: acc
  defp push_key(acc, base, key_type), do: push(acc, resolve_plain_key(base, key_type))

  # Consume characters up to (not including) the next "." or "[", or the
  # end of the string.
  defp take_base(<<>>, acc), do: {acc, <<>>}
  defp take_base(<<".", _::binary>> = rest, acc), do: {acc, rest}
  defp take_base(<<"[", _::binary>> = rest, acc), do: {acc, rest}
  defp take_base(<<c::utf8, rest::binary>>, acc), do: take_base(rest, <<acc::binary, c::utf8>>)

  # Consume characters up to (not including) the closing "]".
  defp take_bracket_content(<<"]", rest::binary>>, acc), do: {acc, rest}
  defp take_bracket_content(<<>>, acc), do: {acc, <<>>}

  defp take_bracket_content(<<c::utf8, rest::binary>>, acc),
    do: take_bracket_content(rest, <<acc::binary, c::utf8>>)

  # A bare segment: try integer first ("0", "-1"), otherwise a plain key.
  defp resolve_plain_key(base, key_type) do
    case parse_number(base) do
      {:integer, n} -> n
      _not_an_integer -> convert_key(base, key_type)
    end
  end

  # Bracket content: "0", "'key'", ":key", "*", "name=Alice", "name=Alice,active=true"
  defp resolve_bracket_value("*", _key_type), do: "*"

  defp resolve_bracket_value(content, key_type) do
    cond do
      String.contains?(content, "=") -> parse_filter(content, key_type)
      quoted_string?(content) -> unquote_string(content)
      String.starts_with?(content, ":") -> content |> String.slice(1..-1//1) |> String.to_atom()
      true -> resolve_bracket_number_or_string(content)
    end
  end

  # Bare bracket content only recognizes integers, not floats or booleans —
  # e.g. "items[1.5]" stays the raw string "1.5", matching filter values'
  # richer type inference (see resolve_filter_value/1) only inside "k=v" pairs.
  defp resolve_bracket_number_or_string(content) do
    case parse_number(content) do
      {:integer, n} -> n
      _not_an_integer -> content
    end
  end

  # "name=Alice,active=true" -> %{name: "Alice", active: true}
  defp parse_filter(filter_string, key_type) do
    filter_string
    |> String.split(",", trim: true)
    |> Map.new(&parse_filter_pair(&1, key_type))
  end

  # "name=Alice" -> {:name, "Alice"} ; "flag" -> {:flag, true}
  defp parse_filter_pair(pair, key_type) do
    case String.split(pair, "=", parts: 2) do
      [key, value] ->
        {parse_filter_key(String.trim(key), key_type), resolve_filter_value(String.trim(value))}

      [key] ->
        {parse_filter_key(String.trim(key), key_type), true}
    end
  end

  defp parse_filter_key(":" <> key, _key_type), do: String.to_atom(key)
  defp parse_filter_key(key, key_type), do: convert_key(key, key_type)

  # Filter values get full type inference: quoted strings, booleans, atoms,
  # integers/floats, else a raw string.
  defp resolve_filter_value(value) do
    cond do
      quoted_string?(value) -> unquote_string(value)
      value == "true" -> true
      value == "false" -> false
      String.starts_with?(value, ":") -> value |> String.slice(1..-1//1) |> String.to_atom()
      true -> resolve_number_or_string(value)
    end
  end

  defp resolve_number_or_string(value) do
    case parse_number(value) do
      {:integer, n} -> n
      {:float, f} -> f
      :error -> value
    end
  end

  defp convert_key(key, :atom), do: String.to_atom(key)
  defp convert_key(key, :string), do: key

  defp quoted_string?(<<c, _::binary>> = str) when c in [?', ?"],
    do: String.ends_with?(str, <<c>>)

  defp quoted_string?(_str), do: false

  defp unquote_string(str), do: String.slice(str, 1..-2//1)

  # Recognizes an optionally-signed run of digits, with an optional
  # "." + digits fractional part, consuming the whole string.
  defp parse_number(<<"-", rest::binary>>), do: parse_number(rest, "-")
  defp parse_number(str), do: parse_number(str, "")

  defp parse_number(rest, sign) do
    case take_digits(rest, <<>>) do
      {digits, ""} when digits != "" ->
        {:integer, String.to_integer(sign <> digits)}

      {digits, "." <> after_dot} when digits != "" ->
        case take_digits(after_dot, <<>>) do
          {fraction, ""} when fraction != "" ->
            {:float, String.to_float(sign <> digits <> "." <> fraction)}

          _no_valid_fraction ->
            :error
        end

      _no_leading_digits ->
        :error
    end
  end

  defp take_digits(<<c, rest::binary>>, acc) when c in ?0..?9,
    do: take_digits(rest, <<acc::binary, c>>)

  defp take_digits(rest, acc), do: {acc, rest}
end
