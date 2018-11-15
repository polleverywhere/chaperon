defmodule Chaperon.Session do
  @moduledoc """
  Defines a Session struct and corresponding helper functions that are used
  within `Chaperon.Scenario` definitions.
  Most of Chaperon's logic is centered around these sessions.
  """

  defstruct id: nil,
            name: nil,
            results: %{},
            errors: %{},
            async_tasks: %{},
            config: %{},
            assigned: %{},
            metrics: %{},
            scenario: nil,
            cookies: [],
            parent_pid: nil,
            cancellation: nil

  @type t :: %Chaperon.Session{
          id: String.t(),
          name: String.t(),
          results: map,
          errors: map,
          async_tasks: map,
          config: map,
          assigned: map,
          metrics: map,
          scenario: Chaperon.Scenario.t(),
          cookies: [String.t()],
          parent_pid: pid | nil,
          cancellation: String.t() | nil
        }

  @type metric :: {atom, any} | any

  @type config_key :: [atom] | atom | String.t()

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

  @type result_callback :: atom | (Session.t(), any -> Session.t())

  defmacro __using__(_opts) do
    quote do
      require Logger
      require Chaperon.Session
      import Chaperon.Session
    end
  end

  @doc """
  Concurrently spreads a given action with a given rate over a given time
  interval within `session`.
  """
  @spec cc_spread(
          Session.t(),
          atom,
          SpreadAsync.rate(),
          SpreadAsync.time(),
          atom | nil
        ) :: Session.t()
  def cc_spread(session, func_name, rate, interval, task_name \\ nil) do
    session
    |> run_action(%SpreadAsync{
      func: func_name,
      rate: rate,
      interval: interval,
      task_name: task_name || func_name
    })
  end

  @type cc_spread_options ::
          [
            rate: SpreadAsync.rate(),
            interval: SpreadAsync.time(),
            name: atom | nil
          ]
          | %{
              rate: SpreadAsync.rate(),
              interval: SpreadAsync.time(),
              name: atom | nil
            }

  @doc """
  Concurrently spreads a given action with a given rate over a given time
  interval within `session`.
  """
  @spec cc_spread(Session.t(), atom, cc_spread_options) :: Session.t()
  def cc_spread(session, func_name, opts \\ []) do
    session
    |> run_action(%SpreadAsync{
      func: func_name,
      rate: opts[:rate],
      interval: opts[:interval],
      task_name: opts[:name] || func_name
    })
  end

  @doc """
  Loops a given action for a given duration, returning the resulting session at
  the end.
  """
  @spec loop(Session.t(), atom, Chaperon.Timing.duration()) :: Session.t()
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
  @spec repeat(Session.t(), atom, non_neg_integer) :: Session.t()
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
  @spec repeat(Session.t(), atom, [any], non_neg_integer) :: Session.t()
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
  @spec repeat_traced(Session.t(), atom, non_neg_integer) :: Session.t()
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
  @spec repeat_traced(Session.t(), atom, [any], non_neg_integer) :: Session.t()
  def repeat_traced(session, _, _, 0), do: session

  def repeat_traced(session, func, args, amount) when amount > 0 do
    session
    |> call_traced(func, args)
    |> repeat_traced(func, args, amount - 1)
  end

  @type retry_options :: [
          retries: non_neg_integer,
          delay: non_neg_integer,
          random_delay: non_neg_integer
        ]

  @default_retry_opts [retries: 1, random_delay: 1_000]

  @doc """
  Call a given function (with arguments). If any exception is raised,
  retry the call a given amount of times (defaults to 1 retry).
  The retry can be delayed by a fixed or random duration (defaults to 1s).

  Example:
      session
      |> retry_on_error(:publish, ["post title"], retries: 10, delay: 0.5 |> seconds)
      # call function without args
      |> retry_on_error(:cleanup, [], retries: 10, delay: 0.5 |> seconds)

      # retry once by default
      session
      |> retry_on_error(:publish, ["post title"], random_delay: 5 |> seconds)

      # retry once with default delay of 1s
      session
      |> retry_on_error(:publish, ["post title"])

      # retry function without args and default options
      session
      |> retry_on_error(:publish_default)
  """
  @spec retry_on_error(Session.t(), atom, [any], retry_options) :: Session.t()
  def retry_on_error(session, func, args \\ [], opts \\ @default_retry_opts) do
    retries = opts[:retries] || 1

    try do
      session
      |> call(func, args)
    rescue
      err ->
        session
        |> log_error(inspect(err))

        retries =
          case retries do
            :infinity -> :infinity
            r -> r - 1
          end

        if retries > 0 do
          opts = Keyword.merge(opts, retries: retries)

          session
          |> log_error("Retrying #{func} another #{retries} times")
          |> retry_delay(opts)
          |> retry_on_error(func, args, opts)
        else
          stacktrace = System.stacktrace()
          reraise err, stacktrace
        end
    end
  end

  defp retry_delay(session, opts) do
    case {opts[:random_delay], opts[:delay]} do
      {nil, nil} ->
        session

      {nil, delay} ->
        session
        |> delay(delay)

      {r_delay, nil} ->
        session
        |> delay(:rand.uniform(r_delay))

      {r_delay, _} ->
        session
        |> delay(:rand.uniform(r_delay))
    end
  end

  @doc """
  Returns the session's configured timeout or the default timeout, if none
  specified.

  ## Example

      iex> session = %Chaperon.Session{config: %{timeout: 10}}
      iex> session |> Chaperon.Session.timeout
      10
  """
  @spec timeout(Session.t()) :: non_neg_integer
  def timeout(session) do
    session.config[:timeout] || @default_timeout
  end

  @spec await(Session.t(), atom, Task.t()) :: Session.t()
  def await(session, _task_name, nil), do: session

  def await(session, task_name, task = %Task{}) do
    task_session = task |> Task.await(session |> timeout)

    session
    |> remove_async_task(task_name, task)
    |> merge_async_task_result(task_session, task_name)
  end

  @spec await(Session.t(), atom, [Task.t()]) :: Session.t()
  def await(session, task_name, tasks) when is_list(tasks) do
    tasks
    |> Enum.reduce(session, &await(&2, task_name, &1))
  end

  @doc """
  Await an async task with a given `task_name` in `session`.
  """
  @spec await(Session.t(), atom) :: Session.t()
  def await(session, task_name) when is_atom(task_name) do
    session
    |> await(task_name, session.async_tasks[task_name])
  end

  @doc """
  Await all async tasks for the given `task_names` in `session`.
  """
  @spec await(Session.t(), [atom]) :: Session.t()
  def await(session, task_names) when is_list(task_names) do
    task_names
    |> Enum.reduce(session, &await(&2, &1))
  end

  @doc """
  Await all async tasks with a given `task_name` in `session`.
  """
  @spec await_all(Session.t(), atom) :: Session.t()
  def await_all(session, task_name) do
    session
    |> await(task_name, session.async_tasks[task_name])
  end

  @doc """
  Returns a single task or a list of tasks associated with a given `task_name`
  in `session`.
  """
  @spec async_task(Session.t(), atom) :: Task.t() | [Task.t()]
  def async_task(session, task_name) do
    session.async_tasks[task_name]
  end

  @doc """
  Performs a HTTP GET request on `session`'s base_url and `path`.
  Takes an optional list of options to be passed to `HTTPotion`.
  """
  @spec get(Session.t(), String.t(), HTTP.options()) :: Session.t()
  def get(session, path, opts \\ []) do
    session
    |> run_action(Action.HTTP.get(path, opts))
  end

  @doc """
  Performs a HTTP POST request on `session`'s base_url and `path`.
  Takes an optional list of options to be passed to `HTTPotion`.
  """
  @spec post(Session.t(), String.t(), HTTP.options()) :: Session.t()
  def post(session, path, opts \\ []) do
    session
    |> run_action(Action.HTTP.post(path, opts))
  end

  @doc """
  Performs a HTTP PUT request on `session`'s base_url and `path`.
  Takes an optional list of options to be passed to `HTTPotion`.
  """
  @spec put(Session.t(), String.t(), HTTP.options()) :: Session.t()
  def put(session, path, opts \\ []) do
    session
    |> run_action(Action.HTTP.put(path, opts))
  end

  @doc """
  Performs a HTTP PATCH request on `session`'s base_url and `path`.
  Takes an optional list of options to be passed to `HTTPotion`.
  """
  @spec patch(Session.t(), String.t(), HTTP.options()) :: Session.t()
  def patch(session, path, opts) do
    session
    |> run_action(Action.HTTP.patch(path, opts))
  end

  @doc """
  Performs a HTTP DELETE request on `session`'s base_url and `path`.
  Takes an optional list of options to be passed to `HTTPotion`.
  """
  @spec delete(Session.t(), String.t(), HTTP.options()) :: Session.t()
  def delete(session, path, opts \\ []) do
    session
    |> run_action(Action.HTTP.delete(path, opts))
  end

  @doc """
  Performs a WebSocket connection attempt on `session`'s base_url and
  `path`.
  """
  @spec ws_connect(Session.t(), String.t(), Keyword.t()) :: Session.t()
  def ws_connect(session, path, options \\ []) do
    session
    |> run_action(Action.WebSocket.connect(path, options))
  end

  @doc """
  Performs a WebSocket message send on `session`s WebSocket connection.
  Takes an optional list of `options` to be passed along to `Socket.Web.send/3`.
  """
  @spec ws_send(Session.t(), any, Keyword.t()) :: Session.t()
  def ws_send(session, msg, options \\ []) do
    session
    |> run_action(Action.WebSocket.send(msg, options))
  end

  @doc """
  Performs a WebSocket message receive on `session`s WebSocket connection.
  Takes an optional list of `options` to be passed along to `Socket.Web.recv/2`.
  """
  @spec ws_recv(Session.t(), Keyword.t()) :: Session.t()
  def ws_recv(session, options \\ []) do
    session
    |> run_action(Action.WebSocket.recv(options))
  end

  @doc """
  Performs a WebSocket message receive on `session`s WebSocket connection.
  Takes an optional list of `options` to be passed along to `Socket.Web.recv/2`.
  """
  @spec ws_await_recv(Session.t(), any, Keyword.t()) :: Session.t()
  def ws_await_recv(session, expected_message, options \\ []) do
    opts =
      options
      |> Keyword.merge(with_result: &ws_await_recv_loop(&1, expected_message, &2, options))

    session
    |> ws_recv(opts)
  end

  defp ws_await_recv_loop(session, expected_msg, msg, options) do
    if is_expected_message(msg, expected_msg) do
      session
      |> log_debug("Awaited expected WS message")
      |> call_callback(options[:with_result], msg)
    else
      session
      |> log_debug("Ignoring unexpected WS message #{inspect(msg)}")
      |> ws_await_recv(expected_msg, options)
    end
  end

  defp is_expected_message(msg, expected_msg) when is_function(expected_msg) do
    expected_msg.(msg)
  end

  defp is_expected_message(msg, expected_msg) do
    case msg do
      ^expected_msg -> true
      _ -> false
    end
  end

  @doc """
  Closes the session's websocket connection.
  Takes an optional list of `options` to be passed along to `Socket.Web.close/2`.
  """
  @spec ws_close(Session.t(), Keyword.t()) :: Session.t()
  def ws_close(session, options \\ []) do
    session
    |> run_action(Action.WebSocket.close(options))
  end

  @doc """
  Calls a function inside the `session`'s scenario module with the given name
  and args, returning the resulting session.
  """
  @spec call(Session.t(), atom, [any]) :: Session.t()
  def call(session, func, args \\ [])
      when is_atom(func) do
    apply(session.scenario.module, func, [session | args])
  end

  @doc """
  Calls a given function or a function with the given name and args, then
  captures duration metrics in `session`.
  """
  @spec call_traced(Session.t(), Action.CallFunction.callback(), [any]) :: Session.t()
  def call_traced(session, func, args \\ [])
      when is_atom(func) or is_function(func) do
    session
    |> run_action(%Action.CallFunction{func: func, args: args})
  end

  @doc """
  Runs & captures metrics of running another `Chaperon.Scenario` from `session`
  using `session`s config.
  """
  @spec run_scenario(Session.t(), Action.RunScenario.scenario()) :: Session.t()
  def run_scenario(session, scenario) do
    session
    |> run_action(Action.RunScenario.new(scenario, session.config, :local))
  end

  @doc """
  Runs & captures metrics of running another `Chaperon.Scenario` from `session`
  with a given `config`.
  """
  @spec run_scenario(
          Session.t(),
          Action.RunScenario.scenario(),
          map,
          boolean
        ) :: Session.t()
  def run_scenario(session, scenario, config, merge_config \\ true) do
    session
    |> run_scenario_with_config(scenario, config, merge_config, :local)
  end

  @doc """
  Runs & captures metrics of running another `Chaperon.Scenario` from `session`
  with a given `config` on a random node in the Chaperon cluster.
  """
  def schedule_scenario(session, scenario) do
    session
    |> run_action(Action.RunScenario.new(scenario, session.config, :cluster))
  end

  @doc """
  Runs & captures metrics of running another `Chaperon.Scenario` from `session`
  with a given `config`.
  """
  @spec schedule_scenario(
          Session.t(),
          Action.RunScenario.scenario(),
          map,
          boolean
        ) :: Session.t()
  def schedule_scenario(session, scenario, config, merge_config \\ true) do
    session
    |> run_scenario_with_config(scenario, config, merge_config, :cluster)
  end

  @spec run_scenario_with_config(
          Session.t(),
          Action.RunScenario.scenario(),
          map,
          boolean,
          Action.RunScenario.scheduler()
        ) :: Session.t()
  defp run_scenario_with_config(session, scenario, config, merge_config, scheduler) do
    scenario_config =
      if merge_config do
        DeepMerge.deep_merge(session.config, config)
      else
        config
      end

    session
    |> run_action(Action.RunScenario.new(scenario, scenario_config, scheduler))
  end

  @doc """
  Runs a given action within `session` and returns the resulting
  session.
  """
  @spec run_action(Session.t(), Chaperon.Actionable.t()) :: Session.t()
  def run_action(session = %{cancellation: reason}, _) when is_binary(reason) do
    session
  end

  def run_action(session, action) do
    case Chaperon.Actionable.run(action, session) do
      {:error, %Chaperon.Session.Error{reason: reason}} ->
        session
        |> log_error("Session.run_action #{action} failed: #{inspect(reason)}")

        put_in(session.errors[action], reason)

      {:error, %Chaperon.Action.Error{reason: reason}} ->
        session
        |> log_error("Session.run_action #{action} failed: #{inspect(reason)}")

        put_in(session.errors[action], reason)

      {:error, reason} ->
        session
        |> log_debug("Session.run_action #{action} failed: #{inspect(reason)}")

        put_in(session.errors[action], reason)

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
  @spec assign(Session.t(), Keyword.t()) :: Session.t()
  def assign(session, assignments) do
    assignments
    |> Enum.reduce(session, fn {k, v}, session ->
      put_in(session.assigned[k], v)
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
  @spec assign(Session.t(), atom, Keyword.t()) :: Session.t()
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
  @spec update_assign(Session.t(), Keyword.t((any -> any))) :: Session.t()
  def update_assign(session, assignments) do
    assignments
    |> Enum.reduce(session, fn {k, func}, session ->
      update_in(session.assigned[k], func)
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
  @spec update_assign(Session.t(), atom, Keyword.t((any -> any))) :: Session.t()
  def update_assign(session, namespace, assignments) do
    assignments
    |> Enum.reduce(session, fn {k, func}, session ->
      update_in(session.assigned[namespace][k], func)
    end)
  end

  def delete_assign(session, key) do
    update_in(session.assigned, &Map.delete(&1, key))
  end

  def delete_assign(session, namespace, key) do
    update_in(session.assigned[namespace], &Map.delete(&1, key))
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
  @spec update_config(Session.t(), Keyword.t((any -> any))) :: Session.t()
  def update_config(session, assignments) do
    assignments
    |> Enum.reduce(session, fn {k, func}, session ->
      update_in(session.config[k], func)
    end)
  end

  @doc """
  Updates a session's config based on a given Keyword list of functions to be
  used for updating `config` in `session` under a given namespace.

  ## Example

      iex> alias Chaperon.Session; import Session
      iex> session = %Session{config: %{foo: 1, bar: %{baz: "hello", quux: 0}}}
      iex> session.config
      %{foo: 1, bar: %{baz: "hello", quux: 0}}
      iex> session = session |> update_config(:bar, quux: &(&1 + 2))
      iex> session.config
      %{foo: 1, bar: %{baz: "hello", quux: 2}}
  """
  @spec update_config(Session.t(), atom, Keyword.t((any -> any))) :: Session.t()
  def update_config(session, namespace, assignments) do
    assignments
    |> Enum.reduce(session, fn {k, func}, session ->
      update_in(session.config[namespace][k], func)
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
  @spec set_config(Session.t(), Keyword.t(any)) :: Session.t()
  def set_config(session, assignments) do
    assignments
    |> Enum.reduce(session, fn {k, val}, session ->
      put_in(session.config[k], val)
    end)
  end

  @doc """
  Updates a session's config based on a given Keyword list of new values inside
  a given namespace to be used for `config` in `session`.

  ## Example

      iex> alias Chaperon.Session; import Session
      iex> session = %Session{config: %{foo: 1, bar: %{baz: "hello",  quux: 0}}}
      iex> session.config
      %{foo: 1, bar: %{baz: "hello", quux: 0}}
      iex> session = session |> set_config(:bar, quux: 10)
      iex> session.config.bar.quux
      10
      iex> session.config.bar
      %{baz: "hello", quux: 10}
      iex> session.config
      %{foo: 1, bar: %{baz: "hello", quux: 10}}
  """
  @spec set_config(Session.t(), atom, Keyword.t(any)) :: Session.t()
  def set_config(session, namespace, assignments) do
    assignments
    |> Enum.reduce(session, fn {k, val}, session ->
      put_in(session.config[namespace][k], val)
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
      iex>   _ in Chaperon.Session.RequiredConfigMissing -> :failed
      iex> end
      :failed
      iex> session |> config(:invalid, "default")
      "default"
      iex> session |> config([:bar, :val1])
      "V1"
      iex> session |> config([:bar, :val2])
      "V2"
      iex> session |> config("bar.val1")
      "V1"
      iex> session |> config("bar.val2")
      "V2"
  """
  @spec config(Session.t(), config_key, any) :: Session.t()
  def config(session, key, default_val \\ :no_default_given) do
    case key do
      keys when is_list(keys) ->
        session
        |> find_nested_config_val(keys, default_val)

      path when is_binary(path) ->
        keys =
          path
          |> String.split(".")
          |> Enum.map(&String.to_atom/1)

        session
        |> config(keys, default_val)

      _ ->
        case default_val do
          :no_default_given ->
            session
            |> required_config(session.config, key)

          default ->
            Map.get(session.config, key, default)
        end
    end
  end

  defp find_nested_config_val(session, keys = [key1 | rest], default_val) do
    if Map.has_key?(session.config, key1) do
      rest
      |> Enum.reduce(session.config[key1], fn
        key, acc when is_map(acc) ->
          case default_val do
            :no_default_given ->
              session
              |> required_config(acc, key)

            default ->
              acc
              |> Map.get(key, default)
          end

        _key, acc ->
          acc
      end)
    else
      case default_val do
        :no_default_given ->
          session
          |> required_config(keys)

        default ->
          default
      end
    end
  end

  defmodule RequiredConfigMissing do
    defexception config_key: nil, session: nil

    @type t :: %__MODULE__{
            config_key: Chaperon.Session.config_key(),
            session: Chaperon.Session.t()
          }

    @spec new(Chaperon.Session.config_key(), Chaperon.Session.t()) :: t()
    def new(key, session) do
      %__MODULE__{config_key: key, session: session}
    end

    @spec message(t()) :: String.t()
    def message(%__MODULE__{config_key: key, session: session}) do
      "[Chaperon.Session.RequiredConfigMissing #{session.id} #{session.name}] | #{inspect(key)} "
    end
  end

  defp required_config(session, key) do
    session
    |> required_config(session.config, key)
  end

  defp required_config(session, map, key) do
    case Map.fetch(map, key) do
      {:ok, val} ->
        val

      :error ->
        session
        |> log_error("Config key #{inspect(key)} not found")

        raise RequiredConfigMissing.new(key, session)
    end
  end

  @spec skip_query_params_in_metrics(Session.t()) :: Session.t()
  def skip_query_params_in_metrics(session) do
    session
    |> set_config(skip_query_params_in_metrics: true)
  end

  @doc """
  Runs a given function with args asynchronously from `session`.
  """
  @spec async(Session.t(), atom | {atom, atom}, [any], atom | nil) :: Session.t()
  def async(session, target, args \\ [], task_name \\ nil) do
    {mod, func} =
      case target do
        {module, f} ->
          {module, f}

        f when is_atom(f) ->
          {session.scenario.module, f}
      end

    session
    |> run_action(%Action.Async{
      module: mod,
      function: func,
      args: args,
      task_name: task_name || func
    })
  end

  @doc """
  Delays further execution of `session` by a given `duration`.
  `duration` can also be `{:random, integer_val}` in which case `random_delay`
  is called with `integer_val`.

  Example:
      session
      |> delay(3 |> seconds)
      |> get("/")

      # or with random delay up to 3 seconds:
      session
      |> delay({:random, 3 |> seconds})
      |> get("/")
  """
  @spec delay(Session.t(), Chaperon.Timing.duration()) :: Session.t()
  def delay(session, {:random, max_duration}) do
    session
    |> random_delay(max_duration)
  end

  def delay(session, duration) do
    :timer.sleep(duration)
    session
  end

  @doc """
  Delays further execution of `session` by a random value up to the given
  `duration`.
  """
  @spec random_delay(Session.t(), Chaperon.Timing.duration()) :: Session.t()
  def random_delay(session, max_duration) do
    session
    |> delay(:rand.uniform(max_duration))
  end

  @doc """
  Adds a given `Task` to `session` under a given `name`.
  """
  @spec add_async_task(Session.t(), atom, Task.t()) :: Session.t()
  def add_async_task(session, name, task) do
    update_in(session.async_tasks[name], &[task | List.wrap(&1)])
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
  @spec signal(Session.t(), atom, any) :: Session.t()
  def signal(session, name, signal) do
    send(session.async_tasks[name].pid, {:chaperon_signal, signal})
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
  @spec signal_parent(Session.t(), any) :: Session.t()
  def signal_parent(session, signal) do
    send(session.parent_pid, {:chaperon_signal, signal})
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

      # or using an atom as the callback:

      def run(session) do
        session
        |> await_signal_or_timeout(5 |> seconds, :got_signal)
      end

      def got_signal(session, signal) do
        session
        |> log_info("Got signal")
        |> assign(signal: signal)
      end
  """
  @spec await_signal_or_timeout(
          Session.t(),
          non_neg_integer,
          nil | (Session.t(), any -> Session.t())
        ) :: Session.t()
  def await_signal_or_timeout(session, timeout, callback \\ nil) do
    receive do
      {:chaperon_signal, signal} ->
        session
        |> call_callback(callback, signal)
    after
      timeout ->
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
  @spec await_signal(
          Session.t(),
          any | (Session.t(), any -> Session.t())
        ) :: Session.t()
  def await_signal(session, callback) when is_function(callback) do
    timeout = session |> timeout

    receive do
      {:chaperon_signal, signal} ->
        callback.(session, signal)
    after
      timeout ->
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
    after
      timeout ->
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
  @spec await_signal(Session.t(), any, non_neg_integer) :: Session.t()
  def await_signal(session, expected_signal, timeout) do
    receive do
      {:chaperon_signal, ^expected_signal} ->
        session
    after
      timeout ->
        session
        |> error({:timeout, :await_signal, timeout})
    end
  end

  @doc """
  Removes a `Task` with a given `task_name` from `session`.
  """
  @spec remove_async_task(Session.t(), atom, Task.t()) :: Session.t()
  def remove_async_task(session, task_name, task) do
    case session.async_tasks[task_name] do
      nil ->
        session

      [^task] ->
        update_in(session.async_tasks, &Map.delete(&1, task_name))

      tasks when is_list(tasks) ->
        update_in(session.async_tasks[task_name], &List.delete(&1, task))
    end
  end

  @doc """
  Adds a given HTTP request `result` to `session` for the given `action`.
  """
  @spec add_result(Session.t(), Chaperon.Actionable.t(), any) :: Session.t()
  def add_result(session, action, result) do
    case session.config[:store_results] do
      true ->
        session
        |> log_debug("Add result #{action}")

        update_in(session.results[action], &[result | List.wrap(&1)])

      _ ->
        session
    end
  end

  @doc """
  Adds a given WebSocket action `result` to `session` for a given `action`.
  """
  @spec add_ws_result(Session.t(), Chaperon.Actionable.t(), any) :: Session.t()
  def add_ws_result(session, action, result) do
    case session.config[:store_results] do
      true ->
        session
        |> log_debug("Add WS result #{action} : #{inspect(result)}")

        update_in(session.results[action], &[result | List.wrap(&1)])

      _ ->
        session
    end
  end

  @doc """
  Stores a given metric `val` under a given `name` in `session`.
  """
  @spec add_metric(Session.t(), metric, any) :: Session.t()
  def add_metric(session, metric, val) do
    if session |> add_metric?(metric) do
      session
      |> log_debug("Add metric #{inspect(metric)} : #{val}")

      update_in(session.metrics[metric], &[val | List.wrap(&1)])
    else
      session
    end
  end

  defp add_metric?(session, metric) do
    case session.config[:metrics] do
      nil ->
        true

      f when is_function(f) ->
        f.(metric)

      types ->
        case metric do
          {metric_type, _} ->
            MapSet.member?(types, metric_type)

          metric_type ->
            MapSet.member?(types, metric_type)
        end
    end
  end

  @doc """
  Stores a `Chaperon.Session.Error` in `session` for a given `action` for later
  inspection.
  """
  @spec add_error(
          Session.t(),
          Chaperon.Actionable.t(),
          {:error, Error.t()}
        ) :: Session.t()
  def add_error(session, action, error) do
    put_in(session.errors[action], error)
  end

  @doc """
  Stores HTTP response cookies in `session` cookie store for further outgoing
  requests.
  """
  @spec store_response_cookies(Session.t(), HTTPoison.Response.t()) :: Session.t()
  def store_response_cookies(session, response = %HTTPoison.Response{}) do
    response
    |> response_cookies()
    |> strip_cookie_attributes()
    |> store_cookies(session)
  end

  def response_cookies(response = %HTTPoison.Response{}) do
    response.headers
    |> Enum.filter(fn {key, _} -> String.match?(key, ~r/\Aset-cookie\z/i) end)
    |> Enum.map(fn {_, value} -> value end)
  end

  # Strips attributes like Expires and HttpOnly from cookies. Only the name and
  # value are allowed when sending cookies in requests.
  defp strip_cookie_attributes(cookies) do
    cookies
    |> Enum.map(fn value ->
      String.replace(value, ~r/;.*$/, "", global: false)
    end)
  end

  defp store_cookies([], session) do
    # do nothing
    session
  end

  defp store_cookies(cookies, session) when is_list(cookies) do
    put_in(session.cookies, [cookies |> Enum.join("; ")])
  end

  @doc """
  Deletes all cookies from `session`'s cookie store.

      iex> session = %Chaperon.Session{cookies: ["cookie_val1", "cookie_val2"]}
      iex> session = session |> Chaperon.Session.delete_cookies
      iex> session.cookies
      []
  """
  @spec delete_cookies(Session.t()) :: Session.t()
  def delete_cookies(session) do
    put_in(session.cookies, [])
  end

  @spec async_results(Session.t(), atom) :: map
  defp async_results(task_session, task_name) do
    for {k, v} <- task_session.results do
      {task_name, {:async, k, v}}
    end
    |> Enum.into(%{})
  end

  @spec async_metrics(Session.t(), atom) :: map
  defp async_metrics(task_session, task_name) do
    for {k, v} <- task_session.metrics do
      {task_name, {:async, k, v}}
    end
    |> Enum.into(%{})
  end

  @spec merge_async_task_result(Session.t(), Session.t(), atom) :: Session.t()
  defp merge_async_task_result(session, task_session, _task_name) do
    session
    |> merge_results(task_session.results)
    |> merge_metrics(task_session.metrics)
    |> merge_errors(task_session.errors)
  end

  @doc """
  Merges two session's results & metrics and returns the resulting session.
  """
  @spec merge(Session.t(), Session.t()) :: Session.t()
  def merge(session, other_session) do
    session
    |> merge_results(other_session |> session_results)
    |> merge_metrics(other_session |> session_metrics)
    |> merge_errors(other_session |> session_errors)
  end

  @doc """
  Merges results of two sessions.
  """
  @spec merge_results(Session.t(), map) :: Session.t()
  def merge_results(session, results) do
    update_in(session.results, &preserve_vals_merge(&1, results))
  end

  @doc """
  Merges metrics of two sessions.
  """
  @spec merge_metrics(Session.t(), map) :: Session.t()
  def merge_metrics(session, metrics) do
    update_in(session.metrics, &preserve_vals_merge(&1, metrics))
  end

  @doc """
  Merges errors of two sessions.
  """
  def merge_errors(session, errors) do
    update_in(session.errors, &preserve_vals_merge(&1, errors))
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
  @spec ok(Session.t()) :: {:ok, Session.t()}
  def ok(session), do: {:ok, session}

  @doc """
  Returns a `Chaperon.Session.Error` for the given `session` and with a given
  `reason`.
  """
  @spec error(Session.t(), any) :: {:error, Error.t()}
  def error(session, reason) do
    {:error, %Error{reason: reason, session: session}}
  end

  @doc """
  Runs a potentially configured callback for a given action in case of success.
  In case of failure, runs the configured error callback with an
  `{:error, reason}` tuple.

  For more info have a look at `Chaperon.Action.callback/1` and
  `Chaperon.Action.error_callback/1`.
  """
  def run_callback(session, %{callback: nil}, _), do: session

  def run_callback(session, action = %{decode: _decode_options}, response) do
    cb = Chaperon.Action.callback(action)
    error_cb = Chaperon.Action.error_callback(action)

    case decode_response(action, response) do
      {:ok, result} ->
        session
        |> call_callback(cb, result)

      err ->
        error =
          session
          |> error("Response (#{inspect(response)}) decoding failed: #{inspect(err)}")

        session
        |> add_error(action, error)
        |> call_callback(error_cb, err)
    end
  end

  def run_callback(session, action, response) do
    session
    |> call_callback(Chaperon.Action.callback(action), response)
  end

  @doc """
  Calls a `callback` with `session` and an additional argument.

  If the given callback is nil, simply returns `session`.
  If the callback is a function, call it with `session` and the extra argument.
  If it's an atom, call the function with that name in `session`'s currently
  running scenario module.
  """
  @spec call_callback(Session.t(), result_callback, any) :: Session.t()
  def call_callback(session, nil, _), do: session

  def call_callback(session, func_name, arg) when is_atom(func_name),
    do: apply(session.scenario.module, func_name, [session, arg])

  def call_callback(session, cb, arg) when is_function(cb), do: cb.(session, arg)

  def run_error_callback(session, action, response) do
    session
    |> call_callback(Chaperon.Action.error_callback(action), response)
  end

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
  Records a custom metric for the duration of calling a given function with the
  current `Chaperon.Session`.

  Example:

      # records a metric named :my_metric with the duration of calling
      # the given function in the module with the given args.
      session
      |> time(:my_action, MyModule, :my_func, [arg1, arg2])

      # this would record the duration of calling:
      # MyModule.my_func(session, arg1, arg2)
  """
  @spec time(Session.t(), metric, atom, atom, [any]) :: Session.t()
  def time(session, metric, module, func, args \\ []) do
    start = timestamp()
    session = apply(module, func, [session | args])

    session
    |> add_metric(metric, timestamp() - start)
  end

  @doc """
  Records a custom metric for the duration of calling a given function with the
  current `Chaperon.Session`.

  Example:

      # records a metric named :my_metric with the duration of calling
      # the given function
      session
      |> time(:my_action, fn session ->
        # do stuff with session
        # and at the end return session from inside this function
      end)
  """
  @spec time(Session.t(), metric, (Session.t() -> Session.t())) :: Session.t()
  def time(session, metric, func) do
    start = timestamp()

    session =
      case func do
        f when is_atom(f) ->
          apply(session.scenario.module, f, [session])

        f when is_function(f) ->
          f.(session)
      end

    session
    |> add_metric(metric, timestamp() - start)
  end

  @spec abort(Session.t(), String.t()) :: Session.t()
  def abort(session, reason) when is_binary(reason) do
    %{session | cancellation: reason}
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
        "Session{id: #{inspect(session.id)}, scenario: #{inspect(scenario_mod)}}"

      nil ->
        "Session{id: #{inspect(session.id)}}"
    end
  end
end
