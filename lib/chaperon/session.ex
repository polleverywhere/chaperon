defmodule Chaperon.Session do
  @moduledoc """
  Defines a Session struct and corresponding helper functions that are used
  within `Chaperon.Scenario` definitions.
  Most of Chaperon's logic is centered around these sessions.
  """

  defstruct [
    id: nil,
    name: nil,
    results: %{},
    errors: %{},
    async_tasks: %{},
    config: %{},
    assigned: %{},
    metrics: %{},
    scenario: nil,
    cookies: [],
    parent_pid: nil
  ]

  @type t :: %Chaperon.Session{
    id: String.t,
    name: String.t,
    results: map,
    errors: map,
    async_tasks: map,
    config: map,
    assigned: map,
    metrics: map,
    scenario: Chaperon.Scenario.t,
    cookies: [String.t],
    parent_pid: pid | nil
  }

  require Logger
  alias Chaperon.Session
  alias Chaperon.Session.Error
  alias Chaperon.Action
  alias Chaperon.Action.SpreadAsync
  alias Chaperon.Action.HTTP
  import Chaperon.Timing
  import Chaperon.Util
  use Chaperon.Session.Logging

  @default_timeout seconds(10)

  @type result_callback :: (Session.t, any -> Session.t)

  defmacro __using__(_opts) do
    quote do
      require Logger
      require Chaperon.Session
      import  Chaperon.Session
    end
  end

  @doc """
  Concurrently spreads a given action with a given rate over a given time
  interval within `session`.
  """
  @spec cc_spread(Session.t, atom, SpreadAsync.rate, SpreadAsync.time, atom | nil) :: Session.t
  def cc_spread(session, func_name, rate, interval, task_name \\ nil) do
    session
    |> run_action(%SpreadAsync{
      func: func_name,
      rate: rate,
      interval: interval,
      task_name: task_name || func_name
    })
  end

  @doc """
  Loops a given action for a given duration, returning the resulting session at
  the end.
  """
  @spec loop(Session.t, atom, Chaperon.Timing.duration) :: Session.t
  def loop(session, action_name, duration) do
    session
    |> run_action(%Action.Loop{
      action: %Action.CallFunction{func: action_name},
      duration: duration
    })
  end


  @doc """
  Repeats calling a given function with session a given amount of times,
  returning the resulting session at the end.

  ## Example

      session
      |> repeat(:foo, 2)

      # same as:
      session
      |> foo
      |> foo
  """
  @spec repeat(Session.t, atom, non_neg_integer) :: Session.t
  def repeat(session, _, 0), do: session
  def repeat(session, func, amount) when amount > 0 do
    session
    |> call(func)
    |> repeat(func, amount - 1)
  end

  @doc """
  Repeats calling a given function with session and additional args a given
  amount of times, returning the resulting session at the end.

  ## Example

      session
      |> repeat(:foo, ["bar", "baz"], 2)

      # same as:
      session
      |> foo("bar", "baz") |> foo("bar", "baz")
  """
  @spec repeat(Session.t, atom, [any], non_neg_integer) :: Session.t
  def repeat(session, _, _, 0), do: session
  def repeat(session, func, args, amount) when amount > 0 do
    session
    |> call(func, args)
    |> repeat(func, args, amount - 1)
  end

  @doc """
  Repeats calling a given function with session a given amount of times,
  returning the resulting session at the end. Also traces durations for all
  calls to the given function.

  ## Example

      session
      |> repeat_traced(:foo, 2)

      # same as:
      session
      |> call_traced(:foo)
      |> call_traced(:foo)
  """
  @spec repeat_traced(Session.t, atom, non_neg_integer) :: Session.t
  def repeat_traced(session, _, 0), do: session
  def repeat_traced(session, func, amount) when amount > 0 do
    session
    |> call_traced(func)
    |> repeat_traced(func, amount - 1)
  end

  @doc """
  Repeats calling a given function with session and additional args a given
  amount of times, returning the resulting session at the end.

  ## Example

      session
      |> repeat_traced(:foo, ["bar", "baz"], 2)

      # same as:
      session
      |> call_traced(:foo, ["bar", "baz"])
      |> call_traced(:foo, ["bar", "baz"])
  """
  @spec repeat_traced(Session.t, atom, [any], non_neg_integer) :: Session.t
  def repeat_traced(session, _, _, 0), do: session
  def repeat_traced(session, func, args, amount) when amount > 0 do
    session
    |> call_traced(func, args)
    |> repeat_traced(func, args, amount - 1)
  end

  @doc """
  Returns the session's configured timeout or the default timeout, if none
  specified.

  ## Example

      iex> session = %Chaperon.Session{config: %{timeout: 10}}
      iex> session |> Chaperon.Session.timeout
      10
  """
  @spec timeout(Session.t) :: non_neg_integer
  def timeout(session) do
    session.config[:timeout] || @default_timeout
  end

  @spec await(Session.t, atom, Task.t) :: Session.t
  def await(session, _task_name, nil), do: session

  def await(session, task_name, task = %Task{}) do
    task_session = task |> Task.await(session |> timeout)
    session
    |> remove_async_task(task_name, task)
    |> merge_async_task_result(task_session, task_name)
  end

  @spec await(Session.t, atom, [Task.t]) :: Session.t
  def await(session, task_name, tasks) when is_list(tasks) do
    tasks
    |> Enum.reduce(session, &await(&2, task_name, &1))
  end

  @doc """
  Await an async task with a given `task_name` in `session`.
  """
  @spec await(Session.t, atom) :: Session.t
  def await(session, task_name) when is_atom(task_name) do
    session
    |> await(task_name, session.async_tasks[task_name])
  end

  @doc """
  Await all async tasks for the given `task_names` in `session`.
  """
  @spec await(Session.t, [atom]) :: Session.t
  def await(session, task_names) when is_list(task_names) do
    task_names
    |> Enum.reduce(session, &await(&2, &1))
  end

  @doc """
  Await all async tasks with a given `task_name` in `session`.
  """
  @spec await_all(Session.t, atom) :: Session.t
  def await_all(session, task_name) do
    session
    |> await(task_name, session.async_tasks[task_name])
  end

  @doc """
  Returns a single task or a list of tasks associated with a given `task_name`
  in `session`.
  """
  @spec async_task(Session.t, atom) :: (Task.t | [Task.t])
  def async_task(session, task_name) do
    session.async_tasks[task_name]
  end

  @doc """
  Performs a HTTP GET request on `session`'s base_url and `path`.
  Takes an optional list of options to be passed to `HTTPotion`.
  """
  @spec get(Session.t, String.t, HTTP.options) :: Session.t
  def get(session, path, opts \\ []) do
    session
    |> run_action(Action.HTTP.get(path, opts))
  end

  @doc """
  Performs a HTTP POST request on `session`'s base_url and `path`.
  Takes an optional list of options to be passed to `HTTPotion`.
  """
  @spec post(Session.t, String.t, HTTP.options) :: Session.t
  def post(session, path, opts \\ []) do
    session
    |> run_action(Action.HTTP.post(path, opts))
  end

  @doc """
  Performs a HTTP PUT request on `session`'s base_url and `path`.
  Takes an optional list of options to be passed to `HTTPotion`.
  """
  @spec put(Session.t, String.t, HTTP.options) :: Session.t
  def put(session, path, opts \\ []) do
    session
    |> run_action(Action.HTTP.put(path, opts))
  end

  @doc """
  Performs a HTTP PATCH request on `session`'s base_url and `path`.
  Takes an optional list of options to be passed to `HTTPotion`.
  """
  @spec patch(Session.t, String.t, HTTP.options) :: Session.t
  def patch(session, path, opts) do
    session
    |> run_action(Action.HTTP.patch(path, opts))
  end

  @doc """
  Performs a HTTP DELETE request on `session`'s base_url and `path`.
  Takes an optional list of options to be passed to `HTTPotion`.
  """
  @spec delete(Session.t, String.t, HTTP.options) :: Session.t
  def delete(session, path, opts \\ []) do
    session
    |> run_action(Action.HTTP.delete(path, opts))
  end

  @doc """
  Performs a WebSocket connection attempt on `session`'s base_url and
  `path`.
  """
  @spec ws_connect(Session.t, String.t, Keyword.t) :: Session.t
  def ws_connect(session, path, options \\ []) do
    session
    |> run_action(Action.WebSocket.connect(path, options))
  end

  @doc """
  Performs a WebSocket message send on `session`s WebSocket connection.
  Takes an optional list of `options` to be passed along to `Socket.Web.send/3`.
  """
  @spec ws_send(Session.t, any, Keyword.t) :: Session.t
  def ws_send(session, msg, options \\ []) do
    session
    |> run_action(Action.WebSocket.send(msg, options))
  end

  @doc """
  Performs a WebSocket message receive on `session`s WebSocket connection.
  Takes an optional list of `options` to be passed along to `Socket.Web.recv/2`.
  """
  @spec ws_recv(Session.t, Keyword.t) :: Session.t
  def ws_recv(session, options \\ []) do
    session
    |> run_action(Action.WebSocket.recv(options))
  end

  @doc """
  Performs a WebSocket message receive on `session`s WebSocket connection.
  Takes an optional list of `options` to be passed along to `Socket.Web.recv/2`.
  """
  @spec ws_await_recv(Session.t, any, Keyword.t) :: Session.t
  def ws_await_recv(session, expected_message, options \\ []) do
    opts =
      options
      |> Keyword.merge([
        with_result: &ws_await_recv_loop(&1, expected_message, &2, options)
      ])

    session
    |> ws_recv(opts)
  end

  defp ws_await_recv_loop(session, expected_msg, msg, options) do
    if is_expected_message(msg, expected_msg) do
      session
      |> log_debug("Awaited expected WS message")

      callback = options[:with_result]
      if callback do
        callback.(session, msg)
      else
        session
      end
    else
      session
      |> log_debug("Ignoring unexpected WS message #{inspect msg}")

      session
      |> ws_await_recv(expected_msg, options)
    end
  end

  defp is_expected_message(msg, expected_msg) when is_function(expected_msg) do
    expected_msg.(msg)
  end

  defp is_expected_message(msg, expected_msg) do
    case msg do
      ^expected_msg -> true
      _             -> false
    end
  end

  @doc """
  Closes the session's websocket connection.
  Takes an optional list of `options` to be passed along to `Socket.Web.close/2`.
  """
  @spec ws_close(Session.t, Keyword.t) :: Session.t
  def ws_close(session, options \\ []) do
    session
    |> run_action(Action.WebSocket.close(options))
  end

  @doc """
  Calls a function inside the `session`'s scenario module with the given name
  and args, returning the resulting session.
  """
  @spec call(Session.t, atom, [any]) :: Session.t
  def call(session, func, args \\ [])
    when is_atom(func)
  do
    apply(session.scenario.module, func, [session | args])
  end

  @doc """
  Calls a given function or a function with the given name and args, then
  captures duration metrics in `session`.
  """
  @spec call_traced(Session.t, Action.CallFunction.callback, [any]) :: Session.t
  def call_traced(session, func, args \\ [])
    when is_atom(func) or is_function(func)
  do
    session
    |> run_action(%Action.CallFunction{func: func, args: args})
  end

  @doc """
  Runs & captures metrics of running another `Chaperon.Scenario` from `session`
  using `session`s config.
  """
  @spec run_scenario(Session.t, Action.RunScenario.scenario) :: Session.t
  def run_scenario(session, scenario) do
    session
    |> run_scenario(scenario, session.config)
  end

  @doc """
  Runs & captures metrics of running another `Chaperon.Scenario` from `session`
  with a given `config`.
  """
  @spec run_scenario(Session.t, Action.RunScenario.scenario, map, boolean) :: Session.t
  def run_scenario(session, scenario, config, merge_config \\ true) do
    scenario_config =
      if merge_config do
        Map.merge(session.config, config)
      else
        config
      end

    session
    |> run_action(Action.RunScenario.new(scenario, scenario_config))
  end

  @doc """
  Runs a given action within `session` and returns the resulting
  session.
  """
  @spec run_action(Session.t, Chaperon.Actionable.t) :: Session.t
  def run_action(session, action) do
    case Chaperon.Actionable.run(action, session) do
      {:error, %Chaperon.Session.Error{reason: reason}} ->
        session
        |> log_error("Session.run_action #{action} failed: #{inspect reason}")
        put_in session.errors[action], reason
      {:error, %Chaperon.Action.Error{reason: reason}} ->
        session
        |> log_error("Session.run_action #{action} failed: #{inspect reason}")
        put_in session.errors[action], reason
      {:error, reason} ->
        session
        |> log_debug("Session.run_action #{action} failed: #{inspect reason}")
        put_in session.errors[action], reason
      {:ok, new_session = %Chaperon.Session{}} ->
        session
        |> log_debug("SUCCESS #{action}")
        new_session
    end
  end

  @doc """
  Assigns a given list of key-value pairs (as a `Keyword` list) in `session`
  for further usage later.

  ## Example

      iex> alias Chaperon.Session; import Session
      iex> session = %Session{} |> assign(foo: 1, bar: "hello")
      iex> session.assigned.foo
      1
      iex> session.assigned.bar
      "hello"
      iex> session.assigned
      %{foo: 1, bar: "hello"}
  """
  @spec assign(Session.t, Keyword.t) :: Session.t
  def assign(session, assignments) do
    assignments
    |> Enum.reduce(session, fn {k, v}, session ->
      put_in session.assigned[k], v
    end)
  end

  @doc """
  Assigns a given list of key-value pairs (as a `Keyword` list) under a given
  namespace in `session` for further usage later.

  ## Example

      iex> alias Chaperon.Session; import Session
      iex> session = %Session{} |> assign(:api, auth_token: "auth123", login: "foo@bar.com")
      iex> session.assigned.api
      %{auth_token: "auth123", login: "foo@bar.com"}
      iex> session.assigned.api.auth_token
      "auth123"
      iex> session.assigned.api.login
      "foo@bar.com"
      iex> session.assigned
      %{api: %{auth_token: "auth123", login: "foo@bar.com"}}
  """
  @spec assign(Session.t, atom, Keyword.t) :: Session.t
  def assign(session, namespace, assignments) do
    assignments = assignments |> Enum.into(%{})

    session
    |> update_assign([{namespace, &Map.merge(&1 || %{}, assignments)}])
  end

  @doc """
  Updates assignments based on a given Keyword list of functions to be used for
  updating `assigned` in `session`.

  ## Example

      iex> alias Chaperon.Session; import Session
      iex> session = %Session{} |> assign(foo: 1, bar: "hello")
      iex> session.assigned
      %{foo: 1, bar: "hello"}
      iex> session = session |> update_assign(foo: &(&1 + 2))
      iex> session.assigned.foo
      3
      iex> session.assigned.bar
      "hello"
      iex> session.assigned
      %{foo: 3, bar: "hello"}
  """
  @spec update_assign(Session.t, Keyword.t((any -> any))) :: Session.t
  def update_assign(session, assignments) do
    assignments
    |> Enum.reduce(session, fn {k, func}, session ->
      update_in session.assigned[k], func
    end)
  end

  @doc """
  Updates assignments based on a given Keyword list of functions to be used for
  updating `assigned` within `namespace` in `session`.

  ## Example

      iex> alias Chaperon.Session; import Session
      iex> session = %Session{} |> assign(:api, auth_token: "auth123", login: "foo@bar.com")
      iex> session.assigned.api
      %{auth_token: "auth123", login: "foo@bar.com"}
      iex> session = session |> update_assign(:api, login: &("test" <> &1))
      iex> session.assigned.api.login
      "testfoo@bar.com"
      iex> session.assigned.api
      %{auth_token: "auth123", login: "testfoo@bar.com"}
  """
  @spec update_assign(Session.t, atom, Keyword.t((any -> any))) :: Session.t
  def update_assign(session, namespace, assignments) do
    assignments
    |> Enum.reduce(session, fn {k, func}, session ->
      update_in session.assigned[namespace][k], func
    end)
  end

  def delete_assign(session, key) do
    update_in session.assigned, &Map.delete(&1, key)
  end

  def delete_assign(session, namespace, key) do
    update_in session.assigned[namespace], &Map.delete(&1, key)
  end


  @doc """
  Updates a session's config based on a given Keyword list of functions to be
  used for updating `config` in `session`.

  ## Example

      iex> alias Chaperon.Session; import Session
      iex> session = %Session{config: %{foo: 1, bar: "hello"}}
      iex> session.config
      %{foo: 1, bar: "hello"}
      iex> session = session |> update_config(foo: &(&1 + 2))
      iex> session.config.foo
      3
      iex> session.config.bar
      "hello"
      iex> session.config
      %{foo: 3, bar: "hello"}
  """
  @spec update_config(Session.t, Keyword.t((any -> any))) :: Session.t
  def update_config(session, assignments) do
    assignments
    |> Enum.reduce(session, fn {k, func}, session ->
      update_in session.config[k], func
    end)
  end

  @doc """
  Updates a session's config based on a given Keyword list of new values to be
  used for `config` in `session`.

  ## Example

      iex> alias Chaperon.Session; import Session
      iex> session = %Session{config: %{foo: 1, bar: "hello"}}
      iex> session.config
      %{foo: 1, bar: "hello"}
      iex> session = session |> set_config(foo: 10, baz: "wat")
      iex> session.config.foo
      10
      iex> session.config.bar
      "hello"
      iex> session.config.baz
      "wat"
      iex> session.config
      %{foo: 10, bar: "hello", baz: "wat"}
  """
  @spec set_config(Session.t, Keyword.t(any)) :: Session.t
  def set_config(session, assignments) do
    assignments
    |> Enum.reduce(session, fn {k, val}, session ->
      put_in session.config[k], val
    end)
  end


  @doc """
  Get a (possibly nested) config value.

  ## Example

      iex> alias Chaperon.Session; import Session
      iex> session = %Session{config: %{foo: 1, bar: %{val1: "V1", val2: "V2"}}}
      iex> session.config
      %{foo: 1, bar: %{val1: "V1", val2: "V2"}}
      iex> session |> config(:foo)
      1
      iex> try do
      iex>   session |> config(:invalid) # no default value given
      iex> rescue
      iex>   _ in RuntimeError -> :failed
      iex> end
      :failed
      iex> session |> config(:invalid, "default")
      "default"
      iex> session |> config([:bar, :val1])
      "V1"
      iex> session |> config([:bar, :val2])
      "V2"
  """
  @spec config(Session.t, Keyword.t(any), any) :: Session.t
  def config(session, key, default_val \\ :no_default_given) do
    case key do
      keys when is_list(keys) ->
        session
        |> find_nested_config_val(keys, default_val)

      _ ->
        case default_val do
          :no_default_given ->
            session
            |> required_config(session.config, key)

          default ->
            Map.get session.config, key, default
        end
    end
  end

  defp find_nested_config_val(session, _keys = [key1 | rest], default_val) do
    rest
    |> Enum.reduce(session.config[key1], (fn
      key, acc when is_map(acc) ->
        case default_val do
          :no_default_given ->
            session
            |> required_config(acc, key)

          default ->
            Map.get(acc, key, default)
        end
      _key, acc ->
        acc
    end))
  end

  defp required_config(session, map, key) do
    case Map.fetch(map, key) do
      {:ok, val} ->
        val

      :error ->
        raise "Invalid config key #{inspect key} for session: #{session}"
    end
  end

  @spec skip_query_params_in_metrics(Session.t) :: Session.t
  def skip_query_params_in_metrics(session) do
    session
    |> set_config(skip_query_params_in_metrics: true)
  end

  @doc """
  Runs a given function with args asynchronously from `session`.
  """
  @spec async(Session.t, atom, [any], atom | nil) :: Session.t
  def async(session, func_name, args \\ [], task_name \\ nil) do
    session
    |> run_action(%Action.Async{
      module: session.scenario.module,
      function: func_name,
      args: args,
      task_name: task_name || func_name
    })
  end

  @doc """
  Delays further execution of `session` by a given `duration`.
  """
  @spec delay(Session.t, Chaperon.Timing.duration) :: Session.t
  def delay(session, duration) do
    :timer.sleep(duration)
    session
  end

  @doc """
  Adds a given `Task` to `session` under a given `name`.
  """
  @spec add_async_task(Session.t, atom, Task.t) :: Session.t
  def add_async_task(session, name, task) do
    update_in session.async_tasks[name], &[task | as_list(&1)]
  end

  @doc """
  Send a signal to the current session's async task with the given name.

  Example:

      # scenario run function
      def run(session) do
        session
        |> async(:search_entries, ["chaperon", "load testing"])
        |> async(:do_other_stuff)
        |> signal(:search_entries, :continue_search)
      end

      def search_entries(session, tag1, tag2) do
        session
        |> get("/search", json: [tag: tag1])
        |> await_signal(:continue_search)
        |> get("/search", json: [tag: tag2])
      end
  """
  @spec signal(Session.t, atom, any) :: Session.t
  def signal(session, name, signal) do
    send session.async_tasks[name].pid, {:chaperon_signal, signal}
    session
  end

  @doc """
  Sends a signal to the current session's parent session (that spawned it via
  a call to `Session.async`).

  Example:

      # scenario run function
      def run(session) do
        stream_path = "/secret/live/stream.json"
        session
        |> async(:connect_to_stream, [stream_path])
        |> await_signal({:connected_to_stream, stream_path})
        # ...
      end

      def connect_to_stream(session, stream_path) do
        session
        |> ws_connect(stream_path)
        |> signal_parent({:connected_to_stream, stream_path})
        |> stream_data
      end

      # ...
  """
  @spec signal_parent(Session.t, any) :: Session.t
  def signal_parent(session, signal) do
    send session.parent_pid, {:chaperon_signal, signal}
    session
  end


  @doc """
  Await any incoming signal for current session within given timeout.
  If callback is provided, it will be called with the session and the received
  signal value.

  Example:

      session
      |> await_signal_or_timeout(5 |> seconds, fn(session, signal) ->
        session
        |> log_info("Got signal")
        |> assign(signal: signal)
      end)
  """
  @spec await_signal_or_timeout(Session.t, non_neg_integer, nil | (Session.t, any -> Session.t)) :: Session.t
  def await_signal_or_timeout(session, timeout, callback \\ nil) do
    receive do
      {:chaperon_signal, signal} ->
        if callback do
          callback.(session, signal)
        else
          session
        end

      after timeout ->
        session
        |> error({:timeout, :await_signal, timeout})
    end
  end

  @doc """
  Await any signal and call a given callback with the session and the received
  signal.

  Example:

      session
      |> await_signal(fn(session, signal) ->
        session
        |> assign(signal: signal)
      end)
  """
  @spec await_signal(Session.t, any | (Session.t, any -> Session.t)) :: Session.t
  def await_signal(session, callback) when is_function(callback) do
    timeout = session |> timeout

    receive do
      {:chaperon_signal, signal} ->
        callback.(session, signal)

      after timeout ->
        session
        |> error({:timeout, :await_signal, timeout})
    end
  end

  @doc """
  Await a given signal in the current session and returns session afterwards.

  Example:

      session
      |> await_signal(:continue_search)
      |> get("/search", params: [query: "Got load test?"])
  """
  def await_signal(session, expected_signal) do
    timeout = session |> timeout

    receive do
      {:chaperon_signal, ^expected_signal} ->
        session

      after timeout ->
        session
        |> error({:timeout, :await_signal, timeout})
    end
  end

  @doc """
  Await an expected signal with a given timeout.

  Example:

      session
      |> await_signal(:continue_search, 5 |> seconds)
      |> get("/search", params: [query: "Got load test?"])
  """
  @spec await_signal(Session.t, any, non_neg_integer) :: Session.t
  def await_signal(session, expected_signal, timeout) do
    receive do
      {:chaperon_signal, ^expected_signal} ->
        session

      after timeout ->
        session
        |> error({:timeout, :await_signal, timeout})
    end
  end

  @doc """
  Removes a `Task` with a given `task_name` from `session`.
  """
  @spec remove_async_task(Session.t, atom, Task.t) :: Session.t
  def remove_async_task(session, task_name, task) do
    case session.async_tasks[task_name] do
      nil ->
        session
      [^task] ->
        update_in session.async_tasks, &Map.delete(&1, task_name)
      tasks when is_list(tasks) ->
        update_in session.async_tasks[task_name], &List.delete(&1, task)
    end
  end

  @doc """
  Adds a given HTTP request `result` to `session` for the given `action`.
  """
  @spec add_result(Session.t, Chaperon.Actionable.t, any) :: Session.t
  def add_result(session, action, result) do
    case session.config[:store_results] do
      true ->
        session
        |> log_debug("Add result #{action}")
        update_in session.results[action], &[result | as_list(&1)]

      _ ->
        session
    end
  end

  @doc """
  Adds a given WebSocket action `result` to `session` for a given `action`.
  """
  @spec add_ws_result(Session.t, Chaperon.Actionable.t, any) :: Session.t
  def add_ws_result(session, action, result) do
    case session.config[:store_results] do
      true ->
        session
        |> log_debug("Add WS result #{action} : #{inspect result}")
        update_in session.results[action], &[result | as_list(&1)]

      _ ->
        session
    end
  end

  @doc """
  Stores a given metric `val` under a given `name` in `session`.
  """
  @spec add_metric(Session.t, [any], any) :: Session.t
  def add_metric(session, name, val) do
    session
    |> log_debug("Add metric #{inspect name} : #{val}")
    update_in session.metrics[name], &[val | as_list(&1)]
  end

  @doc """
  Stores HTTP response cookies in `session` cookie store for further outgoing
  requests.
  """
  @spec store_cookies(Session.t, HTTPoison.Response.t) :: Session.t
  def store_cookies(session, response = %HTTPoison.Response{}) do
    put_in session.cookies, response_cookies(response)
  end

  defp response_cookies(response = %HTTPoison.Response{}) do
    response.headers
    |> Enum.map(fn
      {"Set-Cookie", cookie} ->
        cookie
      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Deletes all cookies from `session`'s cookie store.

      iex> session = %Chaperon.Session{cookies: ["cookie_val1", "cookie_val2"]}
      iex> session = session |> Chaperon.Session.delete_cookies
      iex> session.cookies
      []
  """
  @spec delete_cookies(Session.t) :: Session.t
  def delete_cookies(session) do
    put_in session.cookies, []
  end

  @spec async_results(Session.t, atom) :: map
  defp async_results(task_session, task_name) do
    for {k, v} <- task_session.results do
      {task_name, {:async, k, v}}
    end
    |> Enum.into(%{})
  end

  @spec async_metrics(Session.t, atom) :: map
  defp async_metrics(task_session, task_name) do
    for {k, v} <- task_session.metrics do
      {task_name, {:async, k, v}}
    end
    |> Enum.into(%{})
  end

  @spec merge_async_task_result(Session.t, Session.t, atom) :: Session.t
  defp merge_async_task_result(session, task_session, _task_name) do
    session
    |> merge_results(task_session.results)
    |> merge_metrics(task_session.metrics)
    |> merge_errors(task_session.errors)
  end

  @doc """
  Merges two session's results & metrics and returns the resulting session.
  """
  @spec merge(Session.t, Session.t) :: Session.t
  def merge(session, other_session) do
    session
    |> merge_results(other_session |> session_results)
    |> merge_metrics(other_session |> session_metrics)
    |> merge_errors(other_session |> session_errors)
  end

  @doc """
  Merges results of two sessions.
  """
  @spec merge_results(Session.t, map) :: Session.t
  def merge_results(session, results) do
    update_in session.results, &preserve_vals_merge(&1, results)
  end

  @doc """
  Merges metrics of two sessions.
  """
  @spec merge_metrics(Session.t, map) :: Session.t
  def merge_metrics(session, metrics) do
    update_in session.metrics, &preserve_vals_merge(&1, metrics)
  end


  @doc """
  Merges errors of two sessions.
  """
  def merge_errors(session, errors) do
    update_in session.errors, &preserve_vals_merge(&1, errors)
  end

  @doc """
  Returns `session`'s results wrapped with `session`'s name.
  """
  def session_results(session) do
    session.results
    |> map_nested_put(:session_name, session |> name)
  end

  @doc """
  Returns `session`'s metrics wrapped with `session`'s name.
  """
  def session_metrics(session) do
    session.metrics
    |> map_nested_put(:session_name, session |> name)
  end

  @doc """
  Returns `session`'s errors wrapped with `session`'s name.
  """
  def session_errors(session) do
    session.errors
    |> map_nested_put(:session_name, session |> name)
  end

  @doc """
  Returns the `session`s configured name or scenario's module name.
  """
  def name(session) do
    name = session.config[:session_name] || session.name
    "#{session.id} #{name}"
  end

  @doc """
  Returns `{:ok, reason}`.
  """
  @spec ok(Session.t) :: {:ok, Session.t}
  def ok(session), do: {:ok, session}

  @doc """
  Returns an `Chaperon.Session.Error` for the given `session` and with a given
  `reason`.
  """
  @spec error(Session.t, any) :: {:error, Error.t}
  def error(session, reason) do
    {:error, %Error{reason: reason, session: session}}
  end

  def run_callback(session, _, nil, _),
    do: session


  def run_callback(session, action = %{decode: _decode_options}, cb, response)
    when is_function(cb)
  do
    case decode_response(action, response) do
      {:ok, result} ->
        cb.(session, result)

      err ->
        error = session |> error("Response (#{inspect response}) decoding failed: #{inspect err}")
        put_in session.errors[action], error
    end
  end

  def run_callback(session, _action, cb, response) when is_function(cb),
    do: cb.(session, response)

  defp decode_response(action, response) do
    response_body =
      case response do
        %HTTPoison.Response{body: body} ->
          body
        s when is_binary(s) ->
          s
      end

    case action.decode do
      nil ->
        {:ok, response}

      :json ->
        Poison.decode(response_body, keys: :atoms)

      decode when is_function(decode) ->
        decode.(response_body)
    end
  end

  def reset_action_metadata(session) do
    %{session | metrics: %{}, results: %{}, errors: %{}, async_tasks: %{}}
  end


  @doc """
  Makes a given function call async for `session`.

  ## Example

      session
      ~> foo
      ~> bar(1,2,3)

  Is the same as:

      session
      |> async(:foo)
      |> async(:bar, [1,2,3])
  """
  defmacro session ~> {func, _, nil} do
    quote do
      unquote(session)
      |> Chaperon.Session.async(unquote(func))
    end
  end

  defmacro session ~> {task_name, _, args} do
    quote do
      unquote(session)
      |> Chaperon.Session.async(unquote(task_name), unquote(args))
    end
  end

  @doc """
  Awaits a given async task within `session`.

  ## Example

      session
      <~ foo
      <~ bar

  Is the same as:

      session
      |> await(:foo)
      |> await(:bar)
  """
  defmacro session <~ {task_name, _, _} do
    quote do
      unquote(session)
      |> Chaperon.Session.await(unquote(task_name))
    end
  end

  @doc """
  Wraps a function call with `session` as an arg in a call to
  `Chaperon.Session.call_traced` and captures function call duration metrics in
  `session`.

  ## Example

      session
      >>> foo
      >>> bar(1,2,3)

  Is the same as:

      session
      |> call_traced(:foo)
      |> call_traced(:bar, [1,2,3])
  """
  defmacro session >>> {func, _, nil} do
    quote do
      unquote(session)
      |> Chaperon.Session.call_traced(unquote(func))
    end
  end

  defmacro session >>> {func, _, args} do
    quote do
      unquote(session)
      |> Chaperon.Session.call_traced(unquote(func), unquote(args))
    end
  end
end

defimpl String.Chars, for: Chaperon.Session do
  def to_string(session) do
    case session.scenario do
      %Chaperon.Scenario{module: scenario_mod} ->
        "Session{id: #{inspect session.id}, scenario: #{inspect scenario_mod}}"
      nil ->
        "Session{id: #{inspect session.id}}"
    end
  end
end
