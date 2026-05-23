defmodule Stripe.ReqClient do
  @moduledoc false

  @spec request(Stripe.API.method(), String.t(), [{String.t(), String.t()}], Stripe.API.body(), Keyword.t()) ::
          {:ok, integer, [{String.t(), String.t()}], binary} | {:error, term}
  def request(method, url, headers, body, opts) do
    opts = Keyword.delete(opts, :telemetry_metadata)

    opts
    |> Keyword.merge(
      method: method,
      url: url,
      headers: headers,
      raw: true,
      retry: false,
      redirect: false
    )
    |> put_body(body)
    |> Req.request()
    |> normalize_response()
  end

  defp put_body(opts, {:multipart, parts}) do
    opts
    |> Keyword.put(:headers, drop_content_type(opts[:headers]))
    |> Keyword.put(:form_multipart, Enum.map(parts, &normalize_multipart_part/1))
  end

  defp put_body(opts, body), do: Keyword.put(opts, :body, body)

  defp drop_content_type(headers) do
    Enum.reject(headers, fn {key, _value} -> String.downcase(key) == "content-type" end)
  end

  defp normalize_multipart_part({:file, path}) when is_binary(path) do
    {:file, File.stream!(path)}
  end

  defp normalize_multipart_part(part), do: part

  defp normalize_response({:ok, %Req.Response{status: status, headers: headers, body: body}}) do
    {:ok, status, normalize_headers(headers), IO.iodata_to_binary(body)}
  end

  defp normalize_response({:error, %Req.TransportError{reason: reason}}), do: {:error, reason}
  defp normalize_response({:error, exception}), do: {:error, exception}

  defp normalize_headers(headers) do
    Enum.flat_map(headers, fn
      {key, values} when is_list(values) -> Enum.map(values, &{key, &1})
      header -> [header]
    end)
  end
end
