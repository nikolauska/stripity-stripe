defmodule Stripe.APITest do
  use Stripe.StripeCase
  import Mox

  def telemetry_handler_fn(name, measurements, metadata, _config) do
    send(self(), {:telemetry_event, name, measurements, metadata})
  end

  defp restore_json_library({:ok, json_library}) do
    Application.put_env(:stripity_stripe, :json_library, json_library)
  end

  defp restore_json_library(:error) do
    Application.delete_env(:stripity_stripe, :json_library)
  end

  test "works with non existent responses without issue" do
    {:error, %Stripe.Error{extra: %{http_status: 404}}} =
      Stripe.API.request(%{}, :get, "/", %{}, [])
  end

  test "request_id is a string" do
    {:error, %Stripe.Error{request_id: "req_123"}} = Stripe.API.request(%{}, :get, "/", %{}, [])
  end

  test "oauth_request works" do
    verify_on_exit!()

    expect(Stripe.APIMock, :oauth_request, fn method, _endpoint, _body -> method end)

    assert Stripe.APIMock.oauth_request(:post, "www", %{body: "body"}) == :post
  end

  describe "json_library/0" do
    test "prefers Elixir's JSON module when it is available" do
      original_json_library = Application.fetch_env(:stripity_stripe, :json_library)
      on_exit(fn -> restore_json_library(original_json_library) end)

      Application.delete_env(:stripity_stripe, :json_library)

      expected_json_library = if Code.ensure_loaded?(JSON), do: JSON, else: Jason

      assert Stripe.API.json_library() == expected_json_library
    end

    test "can be configured" do
      original_json_library = Application.fetch_env(:stripity_stripe, :json_library)
      on_exit(fn -> restore_json_library(original_json_library) end)

      Application.put_env(:stripity_stripe, :json_library, CustomJSONLibrary)

      assert Stripe.API.json_library() == CustomJSONLibrary
    end
  end

  describe "generate_idempotency_key" do
    test "returns string value" do
      key = Stripe.API.generate_idempotency_key()

      assert key
      assert is_binary(key)
    end

    test "returns unique value" do
      key1 = Stripe.API.generate_idempotency_key()
      key2 = Stripe.API.generate_idempotency_key()

      assert key1 != key2
    end
  end

  describe "should_retry?" do
    test "given timeout error" do
      assert Stripe.API.should_retry?({:error, :timeout})
    end

    test "given connection timeout error" do
      assert Stripe.API.should_retry?({:error, :connect_timeout})
    end

    test "given connection refused error" do
      assert Stripe.API.should_retry?({:error, :econnrefused})
    end

    test "given other error" do
      refute Stripe.API.should_retry?({:error, :unknown})
    end

    test "given HTTP 200 response" do
      refute Stripe.API.should_retry?({:ok, 200, [], ""})
    end

    test "given attempts greater than max_attempts" do
      refute Stripe.API.should_retry?({:error, :timeout}, 2, max_attempts: 1)
    end

    test "given attempts less than max_attempts" do
      assert Stripe.API.should_retry?({:error, :timeout}, 0, max_attempts: 1)
    end

    test "given attempts equals to max_attempts" do
      refute Stripe.API.should_retry?({:error, :timeout}, 1, max_attempts: 1)
    end
  end

  describe "backoff" do
    test "given attempts = 0" do
      backoff = Stripe.API.backoff(0, base_backoff: 10, max_backoff: 100)
      assert backoff == 10
    end

    test "given attempts = 1" do
      backoff = Stripe.API.backoff(1, base_backoff: 10, max_backoff: 100)
      assert backoff in 10..20
    end

    test "given attempts = 2" do
      backoff = Stripe.API.backoff(2, base_backoff: 10, max_backoff: 100)
      assert backoff in 20..40
    end
  end

  describe "telemetry" do
    test "requests emit :start, :stop telemetry events", %{test: test} do
      handler_id = "#{test}"

      :telemetry.attach_many(
        handler_id,
        [[:stripe, :request, :start], [:stripe, :request, :stop]],
        &__MODULE__.telemetry_handler_fn/4,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      Stripe.API.request(%{query: ~s|email: "test@example.com"|}, :get, "/v1/customers/search", %{}, [])

      assert_received({
        :telemetry_event,
        [:stripe, :request, :start],
        %{monotonic_time: _},
        %{telemetry_span_context: _}
      })

      assert_received({
        :telemetry_event,
        [:stripe, :request, :stop],
        %{monotonic_time: _, duration: _},
        %{
          http_method: :get,
          http_retry_count: 0,
          http_status_code: 200,
          http_url: http_url,
          stripe_api_version: _,
          stripe_api_endpoint: "/v1/customers/search",
          telemetry_span_context: _
        }
      })

      assert String.ends_with?(http_url, "/v1/customers/search")
      assert not String.contains?(http_url, "test@example.com")
    end
  end

  test "gets default api version" do
    Stripe.API.request(%{}, :get, "/v1/products", %{}, [])
    assert_stripe_requested(:get, "/v1/products", headers: {"Stripe-Version", "2025-11-17.clover"})
  end

  test "can set custom api version" do
    Stripe.API.request(%{}, :get, "/v1/products", %{}, api_version: "2019-05-16; checkout_sessions_beta=v1")

    assert_stripe_requested(:get, "/v1/products", headers: {"Stripe-Version", "2019-05-16; checkout_sessions_beta=v1"})
  end

  test "oauth_request sets authorization header for deauthorize request" do
    defmodule ReqClientMock1 do
      def request(_, _, headers, _, _) do
        kv_headers = Enum.reduce(headers, %{}, fn {k, v}, acc -> Map.put(acc, k, v) end)

        {:ok, 200, headers, Stripe.API.json_library().encode!(kv_headers)}
      end
    end

    Application.put_env(:stripity_stripe, :http_module, ReqClientMock1)

    {:ok, body} = Stripe.API.oauth_request(:post, "deauthorize", %{})
    assert body["Authorization"] == "Bearer sk_test_123"

    {:ok, body} = Stripe.API.oauth_request(:post, "deauthorize", %{}, "1234")
    assert body["Authorization"] == "Bearer 1234"

    {:ok, body} = Stripe.API.oauth_request(:post, "token", %{})
    refute Map.has_key?(body, "Authorization")
  end

  test "reads req timeout opts from config" do
    # Return request opts as response body
    defmodule ReqClientMock2 do
      def request(_, _, headers, _, opts) do
        kv_opts =
          Enum.reduce(opts, %{}, fn opt, acc ->
            case opt do
              {k, v} ->
                Map.put(acc, k, normalize_option(v))

              _ ->
                Map.put(acc, opt, opt)
            end
          end)

        {:ok, 200, headers, Stripe.API.json_library().encode!(kv_opts)}
      end

      defp normalize_option(value) when is_list(value) do
        if Keyword.keyword?(value) do
          Map.new(value, fn {key, value} -> {key, normalize_option(value)} end)
        else
          Enum.map(value, &normalize_option/1)
        end
      end

      defp normalize_option(value), do: value
    end

    Application.put_env(:stripity_stripe, :http_module, ReqClientMock2)

    {:ok, request_opts} = Stripe.API.request(%{}, :get, "/", %{}, [])
    refute Map.has_key?(request_opts, "connect_options")
    refute Map.has_key?(request_opts, "receive_timeout")

    Application.put_env(:stripity_stripe, :req_opts, [
      {:connect_options, [timeout: 1000]},
      {:receive_timeout, 5000}
    ])

    {:ok, request_opts} = Stripe.API.oauth_request(:post, "token", %{})
    assert request_opts["connect_options"] == %{"timeout" => 1000}
    assert request_opts["receive_timeout"] == 5000

    {:ok, request_opts} = Stripe.API.request(%{}, :get, "/", %{}, [])
    assert request_opts["connect_options"] == %{"timeout" => 1000}
    assert request_opts["receive_timeout"] == 5000
  end
end
