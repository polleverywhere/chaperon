# Chaperon

## HTTP Service Performance Testing Framework

This is a framework / library & tool for doing load and performance tests on web services.
It tracks many kinds of metrics automatically and allows tracking custom ones, if needed.

A load test is a combination of target web services & scenarios to run against them.
It also defines session & HTTP / WebSocket connection settings (like authentication credentials, custom headers, etc.) for each of the services.

Chaperon natively supports running both HTTP & WebSocket actions against a web server.
It defines a `Chaperon.Actionable` protocol for which implementations for additional types of actions can be defined.
Have a look at the `examples/firehose.ex` example file to see an example of both HTTP and WebSocket commands in action.

For a more in-depth introduction check out the [basic starter tutorial here](docs/Tutorial.md).

## Documentation & Links

  - [API Documentation for latest release](https://hexdocs.pm/chaperon)
  - [Package on hex.pm](https://hex.pm/packages/chaperon)


## Distributed Load-Testing

Aside from running Chaperon scenarios from a single machine, you can also run them in a cluster.
Since Chaperon is written in Elixir, it makes use of its built-in distribution mechanics (provided by the Erlang VM and OTP) to achieve this.

To run a Chaperon scenario in distributed mode, you need to deploy your Chaperon scenario and load test code to all machines in the cluster, start them up and connect to the master node.

To start any node simply load up the code in an iex shell:

```
$ iex --cookie my-secret-cluster-cookie --name "chaperon@node1.myhost.com" -S mix
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
