# Chaperon tutorial Part 1 (basic overview)

## How chaperon works

Basically, all load test scenarios in Chaperon operate on `Chaperon.Session` structs.
Built-in actions, such as for making HTTP and WebSocket requests can be found in the `Chaperon.Action.` module namespace but are accessible via helper functions in the `Chaperon.Session` module.

## API Documentation
To view chaperon's API documentation, run `mix docs` and then open `doc/index.html`.


## How to write load test scenarios

Let's say we want to write a WebSocket load test that connects to a server and sends a message, then awaits a response and we track the duration of all of those ping/pong iterations. We'll write the ping pong logic inside a module that implements the `Chaperon.Scenario` behavior by exposing a `run/1` function. The `init/1` function is optional and can be defined to perform some initial setup logic before running the scenario.

### The WebSocket PingPong Scenario

```elixir
defmodule Scenario.WS.PingPong do
  use Chaperon.Scenario

  def init(session) do
    # you can add custom session setup logic in an `init/1` function, if you need to.
    # return {:ok, session} or {:error, reason} (see `Chaperon.Session` module)
    {:ok, session}
  end

  def run(session) do
    # accessing config values using the `Session.config/2` helper function.
    # alternatively we could have just accessed `session.config.ping_pong.iterations`
    # but using the helper function as we do here gives us better error messages
    # in case we didn't define the config value for this session.
    iterations = session |> config([:ping_pong, :iterations])

    # this will call `ping_pong/1` repeatedly for `iterations` amount of times
    # and record the duration of calling it in a histogram

    session
    |> ws_connect("/ping/pong")
    |> repeat_traced(:ping_pong, iterations)
    |> log_info("PingPong finished after #{iterations} iterations")
    |> ws_close
  end

  def ping_pong(session) do
    session
    |> ws_send("ping")
    |> ws_await_recv("pong") # await until "pong" message is received via WS
  end
end
```


### Configuration

Once we've defined the Scenario logic above, we define the load test configuration in another module that uses the `Chaperon.Loadtest` module to define everything we need to run the load test.

We provide a default config that is used by all load test scenarios we want to run as part of the load test, which in this case is just the `PingPong` scenario we wrote.

```elixir
defmodule LoadTest.PingPong do
  use Chaperon.LoadTest

  scenarios do
    default_config %{
      base_url: "http://localhost:5000"
    }

    # run 100 PingPong sessions with 10 iterations each
    # accross the cluster
    run {100, Scenario.WS.PingPong}, %{
      ping_pong: %{
        iterations: 10
      }
    }
  end
end
```

### Next Steps

Check out the more [in-depth tutorial using more advanced features](Tutorial2.md).

You can also take a look at the `examples/` directory for more example load tests.
