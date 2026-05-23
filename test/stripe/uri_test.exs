defmodule Stripe.URITest do
  use ExUnit.Case, async: true

  describe "encode_query/1" do
    test "encodes nested maps" do
      assert Stripe.URI.encode_query(%{metadata: %{foo: "bar"}}) == "metadata%5Bfoo%5D=bar"
    end

    test "encodes lists with indexed keys" do
      params = %{cards: [%{number: 4242, exp_year: 2014}, %{number: 5555, exp_year: 2017}]}

      assert Stripe.URI.encode_query(params) ==
               "cards%5B0%5D%5Bnumber%5D=4242&cards%5B0%5D%5Bexp_year%5D=2014&cards%5B1%5D%5Bnumber%5D=5555&cards%5B1%5D%5Bexp_year%5D=2017"
    end

    test "encodes keyword lists as nested maps" do
      assert Stripe.URI.encode_query(%{promotion: [coupon: "25OFF", type: :coupon]}) ==
               "promotion%5Bcoupon%5D=25OFF&promotion%5Btype%5D=coupon"
    end

    test "encodes nil and boolean values" do
      assert Stripe.URI.encode_query(a: nil, b: true, c: false) == "a=&b=true&c=false"
    end

    test "encodes structs as scalar values" do
      assert Stripe.URI.encode_query(%{date: ~D[2026-05-23]}) == "date=2026-05-23"
    end

    test "omits empty maps and lists" do
      assert Stripe.URI.encode_query(%{empty: [], nested_empty: %{}}) == ""
    end
  end
end
