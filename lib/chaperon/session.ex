defmodule Chaperon.Session do
  @moduledoc """
  Defines a Session struct and corresponding helper functions that are used
  within `Chaperon.Scenario` definitions.
  Most of Chaperon's logic is centered around these sessions.
  """

  defstruct [
    id: nil,
    results: %{},
    errors: %{},
    async_tasks: %{},
    config: %{},
    assigns: %{},
    metrics: %{},
    scenario: nil,
    cookies: []
  ]

  @type t :: %Chaperon.Session{
    id: String.t,
    results: map,
    errors: map,
    async_tasks: map,
    config: map,
    assigns: map,
    metrics: map,
    scenario: Chaperon.Scenario.t,
    cookies: [String.t]
  }

  require Logger
  alias Chaperon.Session
  alias Chaperon.Session.Error
  alias Chaperon.Action
  alias Chaperon.Action.SpreadAsync
  import Chaperon.Timing
  import Chaperon.Util

  @default_timeout seconds(10)

  @type result_callback :: (Session.t, any -> Session.t)

  @doc """
  Concurrently spreads a given action with a given rate over a given time
  interval within `session`.
  """
  @spec cc_spread(Session.t, atom, SpreadAsync.rate, SpreadAsync.time) :: Session.t
  def cc_spread(session, func_name, rate, interval) do
    session
    |> run_action(%SpreadAsync{
      func: func_name,
      rate: rate,
      interval: interval
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
  Repeats a given action, returning the resulting session at the end.

  ## Example

      session |> repeat(:foo, 2)
      # same as:
      session |> foo |> foo
  """
  def repeat(session, _, 0), do: session
  def repeat(session, func, amount) when amount > 0 do
    session
    |> call(func)
    |> repeat(func, amount - 1)
  end

  @doc """
  Repeats a given action with args, returning the resulting session at the end.

  ## Example

      session |> repeat(:foo, ["bar", "baz"], 2)
      # same as:
      session |> foo("bar", "baz") |> foo("bar", "baz")
  """
  def repeat(session, _, _, 0), do: session
  def repeat(session, func, args, amount) when amount > 0 do
    session
    |> call(func, args)
    |> repeat(func, args, amount - 1)
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
  Returns a single task or a list of tasks associated with a given `action_name`
  in `session`.
  """
  @spec async_task(Session.t, atom) :: (Task.t | [Task.t])
  def async_task(session, action_name) do
    session.async_tasks[action_name]
  end

  @doc """
  Performs a HTTP GET request on `session`'s base_url and `path`.
  Takes an optional list of options to be passed to `HTTPotion`.
  """
  @spec get(Session.t, String.t, Keyword.t) :: Session.t
  def get(session, path, params \\ []) do
    session
    |> run_action(Action.HTTP.get(path, params))
  end

  @doc """
  Performs a HTTP POST request on `session`'s base_url and `path`.
  Takes an optional list of options to be passed to `HTTPotion`.
  """
  @spec post(Session.t, String.t, any) :: Session.t
  def post(session, path, opts \\ []) do
    session
    |> run_action(Action.HTTP.post(path, opts))
  end

  @doc """
  Performs a HTTP PUT request on `session`'s base_url and `path`.
  Takes an optional list of options to be passed to `HTTPotion`.
  """
  @spec put(Session.t, String.t, any) :: Session.t
  def put(session, path, opts) do
    session
    |> run_action(Action.HTTP.put(path, opts))
  end

  @doc """
  Performs a HTTP PATCH request on `session`'s base_url and `path`.
  Takes an optional list of options to be passed to `HTTPotion`.
  """
  @spec patch(Session.t, String.t, any) :: Session.t
  def patch(session, path, opts) do
    session
    |> run_action(Action.HTTP.patch(path, opts))
  end

  @doc """
  Performs a HTTP DELETE request on `session`'s base_url and `path`.
  Takes an optional list of options to be passed to `HTTPotion`.
  """
  @spec delete(Session.t, String.t, Keyword.t) :: Session.t
  def delete(session, path, opts) do
    session
    |> run_action(Action.HTTP.delete(path, opts))
  end

  @doc """
  Performs a WebSocket connection attempt on `session`'s base_url and
  `path`.
  """
  @spec ws_connect(Session.t, String.t) :: Session.t
  def ws_connect(session, path) do
    session
    |> run_action(Action.WebSocket.connect(path))
  end

  @doc """
  Performs a WebSocket message send on `session`s WebSocket connection.
  Takes an optional list of `options` to be passed along to `Socket.Web.send/3`.
  """
  @spec ws_send(Session.t, any) :: Session.t
  def ws_send(session, msg, options \\ []) do
    session
    |> run_action(Action.WebSocket.send(msg, options))
  end

  @doc """
  Performs a WebSocket message receive on `session`s WebSocket connection.
  Takes an optional list of `options` to be passed along to `Socket.Web.recv/2`.
  """
  @spec ws_recv(Session.t) :: Session.t
  def ws_recv(session, options \\ []) do
    session
    |> run_action(Action.WebSocket.recv(options))
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
  @spec run_scenario(Session.t, Action.RunScenario.scenario, map) :: Session.t
  def run_scenario(session, scenario, config) do
    session
    |> run_action(Action.RunScenario.new(scenario, config))
  end

  @doc """
  Runs a given action within `session` and returns the resulting
  session.
  """
  @spec run_action(Session.t, Chaperon.Actionable.t) :: Session.t
  def run_action(session, action) do
    case Chaperon.Actionable.run(action, session) do
      {:error, %Chaperon.Session.Error{reason: reason}} ->
        Logger.error "Session.run_action #{action} failed: #{inspect reason}"
        put_in session.errors[action], reason
      {:error, %Chaperon.Action.Error{reason: reason}} ->
        Logger.error "Session.run_action #{action} failed: #{inspect reason}"
        put_in session.errors[action], reason
      {:error, reason} ->
        Logger.error "Session.run_action #{action} failed: #{inspect reason}"
        put_in session.errors[action], reason
      {:ok, new_session} ->
        Logger.debug "SUCCESS #{action}"
        new_session
    end
  end

  @doc """
  Assigns a given list of key-value pairs (as a `Keyword` list) in `session`
  for further usage later.

  ## Example

      iex> alias Chaperon.Session; import Session
      iex> session = %Session{} |> assign(foo: 1, bar: "hello")
      iex> session.assigns.foo
      1
      iex> session.assigns.bar
      "hello"
      iex> session.assigns
      %{foo: 1, bar: "hello"}
  """
  @spec assign(Session.t, Keyword.t) :: Session.t
  def assign(session, assignments) do
    assignments
    |> Enum.reduce(session, fn {k, v}, session ->
      put_in session.assigns[k], v
    end)
  end

  @doc """
  Assigns a given list of key-value pairs (as a `Keyword` list) under a given
  namespace in `session` for further usage later.

  ## Example

      iex> alias Chaperon.Session; import Session
      iex> session = %Session{} |> assign(:api, auth_token: "auth123", login: "foo@bar.com")
      iex> session.assigns.api
      %{auth_token: "auth123", login: "foo@bar.com"}
      iex> session.assigns.api.auth_token
      "auth123"
      iex> session.assigns.api.login
      "foo@bar.com"
      iex> session.assigns
      %{api: %{auth_token: "auth123", login: "foo@bar.com"}}
  """
  @spec assign(Session.t, atom, Keyword.t) :: Session.t
  def assign(session, namespace, assignments) do
    assignments = assignments |> Enum.into(%{})

    session
    |> update_assign([{namespace, &Map.merge(&1 || %{}, assignments)}])
  end

  @doc """
  Updates assigns based on a given Keyword list of functions to be used for
  updating `assigns` in `session`.

  ## Example

      iex> alias Chaperon.Session; import Session
      iex> session = %Session{} |> assign(foo: 1, bar: "hello")
      iex> session.assigns
      %{foo: 1, bar: "hello"}
      iex> session = session |> update_assign(foo: &(&1 + 2))
      iex> session.assigns.foo
      3
      iex> session.assigns.bar
      "hello"
      iex> session.assigns
      %{foo: 3, bar: "hello"}
  """
  @spec update_assign(Session.t, Keyword.t((any -> any))) :: Session.t
  def update_assign(session, assignments) do
    assignments
    |> Enum.reduce(session, fn {k, func}, session ->
      update_in session.assigns[k], func
    end)
  end

  @doc """
  Updates assigns based on a given Keyword list of functions to be used for
  updating `assigns` within `namespace` in `session`.

  ## Example

      iex> alias Chaperon.Session; import Session
      iex> session = %Session{} |> assign(:api, auth_token: "auth123", login: "foo@bar.com")
      iex> session.assigns.api
      %{auth_token: "auth123", login: "foo@bar.com"}
      iex> session = session |> update_assign(:api, login: &("test" <> &1))
      iex> session.assigns.api.login
      "testfoo@bar.com"
      iex> session.assigns.api
      %{auth_token: "auth123", login: "testfoo@bar.com"}
  """
  @spec update_assign(Session.t, atom, Keyword.t((any -> any))) :: Session.t
  def update_assign(session, namespace, assignments) do
    assignments
    |> Enum.reduce(session, fn {k, func}, session ->
      update_in session.assigns[namespace][k], func
    end)
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
      iex> session |> config(:invalid)
      nil
      iex> session |> config(:invalid, "default")
      "default"
      iex> session |> config([:bar, :val1])
      "V1"
      iex> session |> config([:bar, :val2])
      "V2"
  """
  @spec config(Session.t, Keyword.t(any), any) :: Session.t
  def config(session, key, default_val \\ nil) do
    case key do
      [key1 | rest] ->
        rest
        |> Enum.reduce(session.config[key1], (fn key, acc ->
          case acc do
            map when is_map(map) -> Map.get(map, key, default_val)
            _ -> acc
          end
        end))
      _ ->
        Map.get session.config, key, default_val
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
  @spec async(Session.t, atom, [any]) :: Session.t
  def async(session, func_name, args \\ []) do
    session
    |> run_action(%Action.Async{
      module: session.scenario.module,
      function: func_name,
      args: args
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
        Logger.debug "Add result #{action}"
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
        Logger.debug "Add WS result #{action} : #{inspect result}"
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
    Logger.debug "Add metric #{inspect name} : #{val}"
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
    session.config[:session_name] || session.id
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


  def run_callback(session, action = %{decode: decode}, cb, response)
    when is_function(cb)
  do
    case decode_response(session, action, response) do
      {:ok, result} ->
        cb.(session, result)

      err ->
        error = session |> error("Response decoding failed: #{inspect response}")
        put_in session.errors[action], error
    end
  end

  def run_callback(session, action, cb, response) when is_function(cb),
    do: cb.(session, response)

  defp decode_response(session, action, response) do
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
