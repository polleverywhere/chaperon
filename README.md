# Chaperon

## HTTP Service Performance Testing Tool

This is a tool for doing load and performance tests on HTTP based web services.
It tracks many kinds of metrics automatically and allows tracking custom ones that can be defined per environment.

An environment is a combination of target web services & scenarios to run against them, optional connection metadata (like headers for authentication) for each of the services, optional custom metrics and service interaction logic.


## Custom Scenario Sample

```elixir
defmodule BasicAccountLogin do
  use Chaperon.Scenario

  def init(session) do
    # you can annotate session with custom data if necessary
    session
    |> assign(my_config: "my_val")
    |> ok # returns {:ok, session}
  end

  def run(session) do
    session
    |> login
    |> get("/")
    |> logout
  end

  def cleanup(session) do
    session
    |> ok
  end

  def login(session) do
    session
    |> post("/login", form: [user: "admin", password: "password"]),
  end

  def logout(session) do
    session
    |> post("/logout")
  end

  def logout_with_stuff(session) do
    session
    |> logout
    |> meter(:post_logout, fn s ->
      s
      |> foo_bar
      |> put("/baz", json: [data: "value"])
    end)
  end

  def foo_bar(session) do
    session
    |> get("/foo")
    |> get("/bar")
  end

  def concurrent_logout_with_stuff(session) do
    session
    # calls logout/1, assigns response to :logout
    |> async(:logout)
    # same but for foo_bar
    |> async(:foo_bar)
    # run custom logic & assign response to baz
    |> async(:baz, &put(&1, "/baz", json: [data: "value"]))
    # await first and last async, ignore second
    |> await([:logout, :baz])
    # alternatively, wait on all async sessions:
    |> await(:all)

    # to get values out of async vals
    |> with_resp(:logout, fn (s, resp) ->
      # do something with logout response
    end)
  end
end

# our environment definition:
defmodule Environment.Production do
  use Chaperon.Environment

  scenarios do
    run BasicAccountLogin, %{
      some_config: some_val
    }
  end
end
```

Here, the logout action adds metrics for the `GET /logout` automatically.
It also tracks timing and metrics created inside the call to `meter` under `post_logout`.
By default we label metrics under the scenario name.

```elixir
%{
  BasicAccountLogin => %{
    http: %{
      put: %{
        "/logout": [
          duration: 200, # in μs
          # more metrics here
        ]
      }
    },
    post_logout: %{
      http: %{
        get: %{
          "/foo": [ duration: 150 ],
          "/bar": [ duration: 120 ]
        },
        put: %{
          "/baz": [ duration: 100 ]
        }
      }
    }
  }
}
```

## How does it work?

When you define a new Scenario (like the one above), you're building a nested datastructure - somewhat of an execution tree or similar to an AST in a language compiler - that then gets executed by Chaperon's scheduler (not yet implemented).
The idea is to build up the structure in your definition code and then interpret that data structure.
This allows easily inspecting the scenario (as it's just data). It's also easy to pass it around to other workers in a distributed context for easy concurrency and increasing load for a scenario by distributing the different sessions within it to multiple nodes.

## How to run this in production?

Don't yet. It's still WIP.
