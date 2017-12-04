defmodule Avatar.Supervisor do
  use Supervisor
  @name Avatars

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [], name: @name)
  end

  def start_child(args, opts \\ []) do
    Supervisor.start_child(@name, [args, opts])
  end

  def init(_) do
    Supervisor.init([Avatar], strategy: :simple_one_for_one)
  end
end

defmodule Avatar do
  use GenServer, restart: :temporary
  @vsn 1

  require Logger

  def start_link(_, args, opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  # session may be an AI controller, or a client connection
  # TODO: design another mechanism to support restart notification to session/ai/observer
  def init({id, session}) do
    GenServer.cast(session, {:ack, self()})

    data = Character.load(id, @vsn)
    {:ok, {id, session, data}}
  end

  def handle_cast({:login, _}, {id, session, %{pos: pos} = data}) do
    # send login response, with map info (id, x, y) for client to preload
    GenServer.cast(session, {:reply, {:login, [id, pos.map, pos.x, pos.y]}})

    # send avatar properties
    GenServer.cast(session, {:reply, {:info, client_info({id, data})}})

    # update data
    data = process_login({id, data})
    {:noreply, {id, session, data}}
  end

  def handle_cast({:logout, _}, {id, _session, data} = state) do
    Character.save(id, data)

    {:stop, :normal, state}
  end

  def handle_cast({{module, action}, args}, {id, _, data} = state) do
    # TODO: pass module sub state when dispatching action
    dispatch(module, action, List.wrap(args) ++ [{id, data}])
    |> handle_result(state)
  end

  def handle_cast({skill, args}, state) do
    handle_cast({{:skill, skill}, args}, state)
  end

  defp dispatch(module, action, args) do
    require Utils

    mod = "Elixir." <> (module |> Atom.to_string |> Macro.camelize) |> Utils.to_atom
    func = action |> Atom.to_string |> Macro.underscore |> Utils.to_atom

    Utils.ensure_module(mod)

    if function_exported?(mod, func, length(args)) do
      try do
        apply(mod, func, args)
      rescue
        err -> IO.puts "#{module}:#{action} error: #{inspect err}"
      end
    else
      {:reply, {{module, action}, "action received"}}
    end
  end

  defp handle_result({:reply, response}, {_, session, _} = state) do
    GenServer.cast(session, {:reply, response})
    {:noreply, state}
  end

  defp handle_result({:notify, events, changed}, {id, session, data}) do
    # {events, changed} = apply_rules({events, changed}, {id, data})
    GenServer.cast(session, {:notify, events})
    {:noreply, {id, session, data |> merge(changed)}}
  end

  defp handle_result(:ok, state) do
    {:noreply, state}
  end

  defp merge(data, nil) do
    data
  end

  defp merge(data, changed) when is_map(changed) do
    data |> Map.merge(changed)
  end

  defp merge(data, changed) when is_list(changed) do
    changed |> Enum.reduce(data, fn
      {path, value}, data -> data |> put_in(path, value)
    end)
  end

  defp client_info({id, data}) do
    [["", id, data]]
  end

  defp process_login({_id, data}) do
    data
  end
end