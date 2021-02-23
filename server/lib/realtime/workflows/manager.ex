defmodule Realtime.Workflows.Manager do
  use GenServer
  require Logger

  alias Realtime.Adapters.Changes
  alias Realtime.TransactionFilter
  alias Realtime.Workflows

  @table_name :workflows_manager

  ## Manager API

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Send notification for txn to the workflow manager.
  """
  def notify(txn) do
    GenServer.call(__MODULE__, {:notify, txn})
  end

  @doc """
  Return a list of workflows that can be triggered by change.
  """
  def workflows_for_change(txn) do
    # No need to call GenServer, we can lookup the table directly
    :ets.foldl(
      fn ({_, workflow}, acc) ->
        event = %{event: "*", relation: workflow.trigger}
        if TransactionFilter.matches?(event, txn) do
          [workflow | acc]
        else
          acc
        end
      end,
      [],
      @table_name
    )
  end

  @doc """
  Return the workflow with the given id, or nil if not found.
  """
  def workflow_by_id(id) do
    case :ets.lookup(@table_name, id) do
      [{_, workflow}] -> workflow
      [] -> nil
    end
  end

  ## GenServer Callbacks

  @impl true
  def init(config) do
    workflows = :ets.new(@table_name, [:named_table, :protected])

    {:ok, nil, {:continue, :load_workflows}}
  end

  @impl true
  def handle_continue(:load_workflows, state) do
    Workflows.list_workflows()
    |> Enum.each(fn workflow_data ->
      with %{id: id, trigger: _, definition: _} = workflow <-
             Map.take(workflow_data, [:id, :trigger, :definition]) do
        :ets.insert(@table_name, {id, workflow})
      else
        _ -> nil
      end
    end)
    {:noreply, state}
  end

  def handle_call({:notify, txn}, _from, state) do
    do_handle_notification(@table_name, txn)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Private

  defp do_handle_notification(table, txn) do
    for change <- txn.changes do
      case change_type(change) do
        :insert -> insert_workflow(table, change)
        :update -> update_workflow(table, change)
        :delete -> delete_workflow(table, change)
        _ -> nil
      end
    end
  end

  defp insert_workflow(table, %Changes.NewRecord{record: record} = _change) do
    do_insert_workflow(table, record)
  end

  defp update_workflow(table, %Changes.UpdatedRecord{record: record} = _change) do
    do_insert_workflow(table, record)
  end

  defp delete_workflow(table, %Changes.DeletedRecord{old_record: record} = _change) do
    :ets.delete(table, record["id"])
  end

  defp do_insert_workflow(table, record) do
    workflow = %{
      id: record["id"],
      trigger: record["trigger"],
      definition: record["definition"]
    }
    :ets.insert(table, {workflow.id, workflow})
  end

  defp change_type(change) do
    if change.schema == "public" and change.table == "workflows" do
      case change.type do
        "INSERT" -> :insert
        "UPDATE" -> :update
        "DELETE" -> :delete
        _ -> :other
      end
    else
        :other
    end
  end
end