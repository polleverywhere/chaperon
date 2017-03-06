defmodule Chaperon.Action.HTTP.Test do
  use ExUnit.Case
  doctest Chaperon.Action.HTTP
  alias Chaperon.Action.HTTP

  test "options/2 with no cookies or basic auth" do
    action = %HTTP{}
    session = %Chaperon.Session{}
    assert HTTP.options(action, session) == [
      params: %{}
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
        cookie: ["cookie1", "cookie2"]
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
        basic_auth: {"user1", "password1"}
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
        basic_auth: {"user1", "password1"}
      ]
    ]
  end
end
