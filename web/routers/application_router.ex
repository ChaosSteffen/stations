defmodule ApplicationRouter do
  use Dynamo.Router

  prepare do
    # Pick which parts of the request you want to fetch
    # You can comment the line below if you don't need
    # any of them or move them to a forwarded router
    conn.fetch([:cookies, :params])
  end

  # It is common to break your Dynamo into many
  # routers, forwarding the requests between them:
  # forward "/posts", to: PostsRouter

  get "/" do
    conn = conn.assign(:nodes, Minion.other)
    render conn, "index.html"
  end

  get "/:node" do
    selected_node = conn.params[:node]

    conn = conn.assign(:nodes, Minion.other)
    conn = conn.assign(:selected_node, selected_node)

    pids = Enum.map([:current_station, :stations, :mpd_daemon_last_run], fn(keyword) ->
      {Node.spawn_link(:"#{selected_node}", Minion.State, :get, [self, "#{keyword}"]), keyword}
    end)

    assign_values = fn(message, conn) ->
      {pid, value} = message

      key = ListDict.get(pids, pid)
      
      conn.assign(key, value)
    end

    await(conn, on_wake_up(&1, &2, assign_values))
  end

  def on_wake_up(message, conn, assign_values) do
    conn = assign_values.(message, conn)

    if Keyword.has_key?(conn.assigns, :current_station) and Keyword.has_key?(conn.assigns, :stations) and Keyword.has_key?(conn.assigns, :mpd_daemon_last_run) do
      render conn, "index.html"
    else 
      await(conn, on_wake_up(&1, &2, assign_values))
    end
  end

  get "/:node/start_daemon" do
    selected_node = conn.params[:node]

    execute_on_remote = quote do
      daemon_pid = Process.whereis(:mpd_daemon)
      if is_pid(daemon_pid) and Process.alive?(daemon_pid) do
        Process.unregister(:mpd_daemon)
        Process.exit(daemon_pid, :normal)
      end

      pid = Process.spawn(fn()->
        Gru.repeat(1000, "mpc current -f \"%file%\"", fn(node, result) ->
          current_station = Minion.State.get("current_station")

          Minion.State.set("mpd_daemon_last_run", :calendar.universal_time)

          case String.strip(result) do
            ^current_station ->
              Minion.me
            _ ->
              System.cmd "mpc clear && mpc add #{current_station} && mpc play"
          end
        end)
      end)

      Process.register(pid, :mpd_daemon)
    end

    Minion.execute([:"#{selected_node}"], Code, :eval_quoted, [execute_on_remote])

    redirect! conn, to: "/#{selected_node}"
  end

  get "/:node/:station" do
    selected_node = conn.params[:node]
    selected_station = conn.params[:station]

    stations_pid = Node.spawn_link(:"#{selected_node}", Minion.State, :get, [self, "stations"])
    await(conn, fn(message, conn) ->
      {^stations_pid, stations} = message

      url = HashDict.get(stations, selected_station)

      Node.spawn_link(:"#{selected_node}", Minion.State, :set, ["current_station", url])

      redirect! conn, to: "/#{selected_node}"
    end)
  end

end
