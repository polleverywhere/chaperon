# Chaperon

## HTTP Service Performance Testing Tool

This is a tool for doing load and performance tests on HTTP based web services.
It tracks many kinds of metrics automatically and allows tracking custom ones that can be defined per environment.

An environment is a combination of target web services & scenarios to run against them, optional connection metadata (like headers for authentication) for each of the services, optional custom metrics and service interaction logic.

Chaperon supports running both HTTP & WebSocket actions against a web server.
Have a look at the `examples/firehose.ex` example file to see an example of both HTTP and WebSocket commands in action.

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
    >>> post_logout
  end

  def post_logout(session) do
    session
    |> foo_bar
    |> put("/baz", json: [data: "value"])
    |> with_result(fn session, %HTTPoison.Response{body: body} ->
      # do something with put request's response
      session
      |> assign(baz_body: body)
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
    # same as above but with helper macro:
    ~> logout
    # same but for foo_bar
    |> async(:foo_bar)
    # run custom logic & assign response to baz
    |> async(:baz, &put(&1, "/baz", json: [data: "value"]))
    # await first and last async, ignore second
    |> await([:logout, :baz])
    # wait for single task
    |> await(:foo_bar)
    # same as above but with helper macro:
    <~ foo_bar
  end
end

# our environment definition:
defmodule Environment.Production do
  use Chaperon.Environment

  scenarios do
    run BasicAccountLogin, %{
      some_config: some_val
    }
    run BasicAccountLogin, "custom_name", %{
      some_config: some_val
    }
  end
end
```

Here, the logout action adds metrics for the `GET /logout` (and all other web requests) automatically.
It also tracks timing and metrics for all async actions (using `~>`) and measured function calls (using `>>>`).
By default we label all metrics with the scenario name.

## Distributed Load-Testing (TODO - Still WIP)

Aside from running Chaperon scenarios from a single machine, you can also run them in a cluster.
Since Chaperon is written in Elixir, it makes use of its built-in distribution mechanics (provided by the Erlang VM and OTP) to achieve this.

To run a Chaperon scenario in distributed mode, you need to deploy your Chaperon scenario and environment code to all machines in the cluster, start them up and connect to the master node.

To start any node simply load up the code in an iex shell:

```
$ iex --cookie my-secret-cluster-cookie --name "chaperon@mynode.com" -S mix
```

For the master node, run this inside the iex shell:

```elixir
iex> Chaperon.Master.start
```

Then enter the following code into any worker's iex shell to connect it to the master node:

```elixir
iex> Chaperon.connect_to_master :"chaperon@node1.myhost.com"
```

Pick one of the nodes as your master node and connect to it from the worker nodes (see above).  
Before starting up the child nodes make sure you've given them the same VM cookie and config to point to the master node.  
The master node can be identical to the worker nodes, the only difference being that it kicks off the load test and distributes the workload across all worker nodes. When a worker node is done with running a scenario / session task, it sends the results back to the master, which then merges all results to give the final metrics for display / output.

## How to run this in production?

Don't yet. It's still WIP.
