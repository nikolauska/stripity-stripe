defmodule Stripe.URI do
  @moduledoc false

  defmacro __using__(_) do
    quote do
      defp build_url(ext \\ "") do
        if ext != "", do: ext = "/" <> ext

        @base <> ext
      end
    end
  end

  @doc """
  Takes a map and turns it into proper query values.

  ## Example
  card_data = %{
    cards: [
      %{
        number: 424242424242,
        exp_year: 2014
      },
      %{
        number: 424242424242,
        exp_year: 2017
      }
    ]
  }

  Stripe.URI.encode_query(card_data) # cards[0][number]=424242424242&cards[0][exp_year]=2014&cards[1][number]=424242424242&cards[1][exp_year]=2017
  """
  @spec encode_query(map | keyword) :: String.t()
  def encode_query(params) do
    params
    |> form_params()
    |> URI.encode_query()
  end

  @spec form_params(map | keyword) :: [{String.t(), String.t()}]
  def form_params(params) do
    Enum.flat_map(params, fn {key, value} ->
      query_params(to_string(key), value)
    end)
  end

  defp query_params(key, %{__struct__: _} = value), do: [{key, to_string(value)}]

  defp query_params(key, value) when is_map(value) do
    Enum.flat_map(value, fn {nested_key, nested_value} ->
      query_params("#{key}[#{nested_key}]", nested_value)
    end)
  end

  defp query_params(key, value) when is_list(value) do
    if Keyword.keyword?(value) do
      Enum.flat_map(value, fn {nested_key, nested_value} ->
        query_params("#{key}[#{nested_key}]", nested_value)
      end)
    else
      value
      |> Enum.with_index()
      |> Enum.flat_map(fn {nested_value, index} ->
        query_params("#{key}[#{index}]", nested_value)
      end)
    end
  end

  defp query_params(key, nil), do: [{key, ""}]

  defp query_params(key, value), do: [{key, to_string(value)}]
end
