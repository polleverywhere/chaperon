# Chaperon Tutorial Part 2

## Rationale

When writing load tests, there's lots of potential code repetition that chaperon tries to eliminate by providing sane defaults for most common load test scenarios and providing a consistent API for writing them.

By default, measuring metrics, storing them and calculating statistically relevant histograms is done automatically by chaperon. All built-in supported actions are automatically traced (where it makes sense) and this lets us focus on the actual logic behind the load test instead of worrying about how we want to measure stuff and dealing with any incidental issues that aren't part of the core load testing logic.

Even though there are defaults and built-in assumptions on how load tests should be written, technically speaking there are no limits to the kind of code you could place inside a load test scenario. This is due to how the Erlang VM (which Elixir runs on) is designed and how it deals with concurrency and fault tolerance. So in cases where we need to write some unconventional code inside a load test scenario, we can easily do so without having to worry about breaking chaperon's processing guarantees. Session tasks in chaperon are isolated and run independently across the cluster, supervised by a [`Task.Supervisor`](https://hexdocs.pm/elixir/Task.Supervisor.html) (see: `Chaperon.Worker.Supervisor`).

## Session Tasks

Chaperon runs our load test scenarios inside sessions (see `Chaperon.Session`) that can be executed in parallel and can spawn new child session tasks, when asynchronous processing is required within a scenario. An example would be performing HTTP POST requests while asynchronously also awaiting messages on a WebSocket connection to a different server.

Each chaperon session is run inside a `Task` (comes with Elixir's standard library) that is supervised by the `Chaperon.Worker.Supervisor` task supervisor. These session tasks run independently but are automatically `linked` (see Elixir documentation [here](https://elixir-lang.org/getting-started/processes.html#links) & [here](https://elixir-lang.org/getting-started/mix-otp/task-and-gen-tcp.html)) to the session that spawned them in case of child sessions.

Since chaperon takes care of spawning, monitoring & tracing sessions where needed, we generally don't have to worry about this directly. It is recommended to use the `Chaperon.Session` API in most cases.

### Async child tasks

Here's an example of how to spawn a child session from a running one:

```elixir
defmodule MyScenario do
  use Chaperon.Scenario

  def run(session) do
    session
    |> async(:publish, ["My data to be published"]) # run publish in async child task
    |> post("/foo", json: [key: "value"]) # post {"key": "value"} JSON
    |> await(:publish) # await async publish task
  end

  def publish(session, message) do
    session
    |> post("/my/status", json: [status: message])
  end
end
```

When running `MyScenario`, we spawn a new child session that executes the code in `publish/2` and chaperon will automatically record the durations of both running the whole `publish/2` function as well as any actions performed inside it (in this case the HTTP POST request).
After starting the async `publish` session, the parent session performs a HTTP POST and finally `await`s the `publish` task, causing the parent session to halt execution until the child task has finished.

#### Task signals

Sometimes just spawning and awaiting child tasks is sufficient for coordinating tasks. In other cases, we might need more fine-grained control over how async tasks coordinate their processing logic.

An example would be where we'd want to subscribe to some WebSocket server for messages and also perform some publishing tasks but make sure we only start publishing once we've fully subscribed and connected the WebSocket session to the server. In that case we'd want to use a task signal to coordinate work between two asynchronously running sessions.

Here's an example that also shows session state modifications by using `Session.assign` to assign values to the current session's state:

```elixir
defmodule PublishAndAwait do
  use Chaperon.Scenario

  def run(session) do
    message_count = session |> config(:message_count)

    session
    |> async(:subscribe, ["/foo", message_count])
    |> await_signal({:subscribed, "/foo"})
    |> repeat(:publish, message_count)
    |> await(:subscribe)
  end

  def publish(session) do
    session
    |> post("/publications", json: [data: "some random data here"])
  end

  def subscribe(session, endpoint, message_count) do
    session
    |> ws_connect(endpoint)
    |> signal_parent({:subscribed, endpoint}) # send signal to parent session for coordination
    |> assign(subscription_messages: [])      # we'll store received WS messages in this list
    |> repeat(:subscribe_recv_message, message_count)
    |> ws_close
    |> subscribe_finished
  end

  def subscribe_recv_message(session) do
    session
    |> ws_recv(with_result: fn(session, msg) ->
      # store msg in session assignments once received via WebSocket
      session
      |> assign(subscription_messages: &[msg | &1])
    end)
  end

  def subscribe_finished(session) do
    session
    |> log_info("Finished subscribing - Received messages: #{inspect session.assigned.subscription_messages}")
  end
end
```

## Session logging

The `Chaperon.Session` API provides helper macros for logging messages inside a running session which will automatically prefix the logged message with the currently running session's meta information (like its UUID and currently executed scenario name).

Example usage:

```elixir
session
|> log_info("Info level logging message")
|> log_error("Error message inside session")
|> log_debug("This can be used for verbose debug log output")
|> log_warn("And warnings can be logged like this")
```

It is recommended to use these macros whenever performing logging inside a session scenario for more consistent log messages and easier debugging.


## Built-in session actions

To get an overview of all supported built-in actions, have a look at the API documentation for the `Chaperon.Session` module.
To generate the API documentation (it might be hosted somewhere in the future - but for now we need to generate it ourselves):

```
$ mix docs
$ open doc/index.html
```

Here's a short list of commonly used helper functions for performing the built-in actions:

- HTTP actions (all work with the session config's `base_url` value as the root URL to perform against)
  - `post/3`
    - Perform HTTP POST request
  - `put/3`
    - Perform HTTP PUT request
  - `patch/3`
    - Perform HTTP PATCH request
  - `get/3`
    - Perform HTTP GET request
  - `delete/3`
    - Perform HTTP DELETE request


- WebSocket actions (they all default to using a single WS connection but each of them take a `name` option to distinguish between multiple WS connections, if needed)
  - `ws_connect/3`
    - Connect to a given endpoint via WS
  - `ws_close/2`
    - Close WS previously established connection
  - `ws_send/3`
    - Send a message over a WS connection
  - `ws_recv/2`
    - Receive a message over a WS connection and possibly do something with it upon receiving
  - `ws_await_recv/3`
    - Await receiving a message via WS connection that matches a given expected message (or callback that checks if it matches)


- Session task handling
  - `async/3`
    - Call a given function with session in a new async child session task
  - `await/2`
    - Await one or more previously spawned async child session task
  - `await_all/2`
    - Await all async child session tasks with the given name
  - `delay/2`
    - Delay the current session by the given duration (in ms)
  - `repeat/3` / `repeat/4`
    - Repeat calling a given function repeatedly for a given amount of times
  - `repeat_traced/3` / `repeat_traced/4`
    - Same as above but trace all call durations
  - `loop/3`
    - Call a given function with the current session for a given duration (e.g. call `publish` for 1 minute repeatedly)
  - `call/2` / `call/3`
    - Call a given function (with session and optional args)
  - `call_traced/2` / `call_traced/3`
    - Same as above but additionally traces call durations
  - `run_scenario/2`
     - Run a given scenario inside the current session
  - `run_scenario/3` / `run_scenario/4`
    - Same as above but additionally allows passing & merging in custom configuration values to be used by the scenario during execution
  - `signal/3`
    - Send a signal value to an async child session task
  - `signal_parent/2`
    - Send a signal value to the session's parent session task
  - `await_signal_or_timeout/2` / `await_signal_or_timeout/3`
    - Wait for a signal for the current session task
  - `await_signal/2`
    - Await a specific signal or call a function with the session and the signal, once received
  - `await_signal/3`
    - Await an expected signal or timeout after a given value (in ms)


- Session state handling
  - `assign/2` / `assign/3`
    - Assign values to the session's assigned state
  - `update_assign`
    - Update assignments within session
  - `delete_assign`
    - Delete assigned values from session state
  - `config/2`
    - Retrieve config value based on key or list of keys (for nested config values)
  - `update_config/2`
    - Update config value within session config
  - `set_config/2`
    - Set config values within session config
  - `add_metric/3`
    - Record metric value in session state. Is called internally for recording metrics during a session's lifetime but can also be used to track custom metrics, if needed

## Running load tests

A nice command-line interface for running load tests is planned but for now we can run them from within an `iex` shell (iex is Elixir's REPL):

```elixir
iex> Chaperon.run_load_test MyLoadTestModule; nil  # return nil so we don't inspect the returned `Chaperon.Session` value
```

By default `Chaperon.run_load_test` returns the merged `Chaperon.Session` value. Usually we could ignore this fact but the REPL automatically inspects the return values of any expression typed into it (similar to Ruby), so we'll just return `nil` here to prevent it printing all of that info (unless we want to look at it, then you can just skip returning `nil` here).

If we want to export the recorded metrics into a file instead of printing them directly in the REPL at the end, we can specify this like so:

```elixir
iex> Chaperon.run_load_test MyLoadTestModule, output: "metrics.csv"
```

Chaperon currently supports CSV and JSON as metric export formats.
By default, CSV will be used as the metrics export format.
We can force a specific format like so:

```elixir
iex> Chaperon.run_load_test MyLoadTestModule, output: "metrics.csv", format: :csv
iex> Chaperon.run_load_test MyLoadTestModule, output: "metrics.json", format: :json
```

These commands will run the load test on our current machine. If we want to run our load test in a Chaperon cluster, e.g. to be able to generate more load, we need to start the master process first.
This assumes we're running the `iex` shell on a node that is connected to the other nodes in the cluster (see `README.md` for how this can be done):

On master node (any node we want to use to initiate the load test from and where we'll collect all metrics at the end):

```elixir
iex> Chaperon.Master.start
iex> Chaperon.Master.run_load_test MyLoadTestModule, output: "cluster-metrics.csv"
```

## Reusing and nesting scenarios

Chaperon allows reusing existing scenarios in new ones. This is important to allow fast iteration and development of new interesting scenarios based on existing ones. The existing scenarios should not need to be changed in order to work in new ones.
Below is an example of how we can run another scenario from within a scenario:

```elixir
defmodule ScenarioA do
  use Chaperon.Scenario

  def run(session) do
    session
    |> post("/a", json: [name: "A"])
    |> post("/a/config", json: [config: session |> config(:config_value)])
  end
end

defmodule ScenarioB do
  use Chaperon.Scenario

  def run(session) do
    session
    |> post("/b", json: [name: "B"])
    |> run_scenario(ScenarioA, %{
      config_value: "This is used by ScenarioA"
    })
  end
end

defmodule ScenarioC do
  use Chaperon.Scenario

  def run(session) do
    session
    |> post("/c", json: [name: "C"])
    |> assign(config_value: "This can be used by anyone interested in this value")
  end
end

defmodule LoadTest do
  use Chaperon.LoadTest

  def default_config, do: %{
    base_url: "http://localhost:5000/"
  }

  def scenarios, do: [
    # run ScenarioA with given config value explicitly
    {ScenarioA, %{
      config_value: "Some value to be used by ScenarioA"
    }},

    # run ScenarioB explicitly, which internally runs ScenarioA and provides it
    # the required config_value
    {ScenarioB, %{}},

    # run ScenarioC followed by ScenarioA in a `Chaperon.Scenario.Sequence`
    # which automatically converts assignments from a preceding scenario
    # to config values for the following scenario. This allows easily combining
    # existing scenarios in pipelines without having to define a new scenario
    # just for creating these pipelines.
    {[ScenarioC, ScenarioA], %{}},

    # if we want to run multiple concurrent instances of the same scenario
    # we just wrap the scenario with the number in a tuple like so:
    {{100, ScenarioA}, %{
      config_value: "This scenario is now run 100 times!"
    }},

    # the same works for pipelined scenarios:
    {{100, [ScenarioC, ScenarioA]}, %{}}
  ]
end

```
