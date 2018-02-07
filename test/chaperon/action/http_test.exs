defmodule Chaperon.Action.HTTP.Test do
  use ExUnit.Case
  doctest Chaperon.Action.HTTP
  alias Chaperon.Action.HTTP

  test "options/2 with no cookies or basic auth" do
    action = %HTTP{}
    session = %Chaperon.Session{}
    assert HTTP.options(action, session) == [
      params: %{},
      hackney: [
        pool: :chaperon
      ]
    ]
  end

  test "options/2 with cookies and no basic auth" do
    action = %HTTP{}
    session = %Chaperon.Session{
      cookies: ["cookie1", "cookie2"]
    }
    assert HTTP.options(action, session) == [
      params: %{},
      hackney: [
        cookie: ["cookie1", "cookie2"],
        pool: :chaperon
      ]
    ]
  end

  test "options/2 with no cookies and basic auth" do
    action = %HTTP{}
    session = %Chaperon.Session{
      config: %{basic_auth: {"user1", "password1"}}
    }
    assert HTTP.options(action, session) == [
      params: %{},
      hackney: [
        basic_auth: {"user1", "password1"},
        pool: :chaperon
      ]
    ]
  end

  test "options/2 with cookies and basic auth" do
    action = %HTTP{}
    session = %Chaperon.Session{
      cookies: ["cookie1", "cookie2"],
      config: %{basic_auth: {"user1", "password1"}}
    }
    assert HTTP.options(action, session) == [
      params: %{},
      hackney: [
        cookie: ["cookie1", "cookie2"],
        basic_auth: {"user1", "password1"},
        pool: :chaperon
      ]
    ]
  end

  test "metrics_url/2 with no custom metrics_url defined" do
    action = %HTTP{path: "/foo/bar/123.json"}

    session = %Chaperon.Session{
      config: %{base_url: "http://localhost:5000/api/v1"}
    }

    metrics_url = "http://localhost:5000/api/v1/foo/bar/123.json"
    assert HTTP.metrics_url(action, session) == metrics_url
  end

  test "metrics_url/2 with custom metrics_url defined" do
    action = %HTTP{path: "/foo/bar/123.json", metrics_url: "/foo/bar/ID.json"}

    session = %Chaperon.Session{
      config: %{base_url: "http://localhost:5000/api/v1"}
    }

    metrics_url = "http://localhost:5000/api/v1/foo/bar/ID.json"
    assert HTTP.metrics_url(action, session) == metrics_url
  end
end
