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
    redirect! conn, to: "/#{Enum.first(Minion.other)}"
  end

  get "/:node" do
    selected_node = conn.params[:node]

    conn = conn.assign(:nodes, Minion.other)
    conn = conn.assign(:selected_node, selected_node)

    remote_keys = [:current_station, :stations, :mpd_daemon_last_run, :volume]

    wait_for_values = ask_for_values(selected_node, remote_keys)

    await(conn, on_wake_up(&1, &2, wait_for_values, remote_keys))
  end

  def on_wake_up(message, conn, wait_for_values, remote_keys) do
    conn = wait_for_values.(message, conn)

    if Keyword.has_key?(conn.assigns, :current_station) and Keyword.has_key?(conn.assigns, :stations) and Keyword.has_key?(conn.assigns, :mpd_daemon_last_run) and Keyword.has_key?(conn.assigns, :volume) do
      render conn, "index.html"
    else 
      await(conn, on_wake_up(&1, &2, wait_for_values, remote_keys))
    end
  end

  def ask_for_values node, keys do
    pids = Enum.map(keys, fn(keyword) ->
      {Node.spawn_link(:"#{node}", Minion.State, :get, [self, "#{keyword}"]), keyword}
    end)

    process_message = fn(message, conn) ->
      {pid, value} = message

      key = ListDict.get(pids, pid)
      
      conn.assign(key, value)
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
        Gru.repeat(500, "mpc -f \"%file%\"", fn(node, result) ->
          current_station = Minion.State.get("current_station")

          Minion.State.set("mpd_daemon_last_run", :calendar.universal_time)

          [url, track_status, player_status] = String.split(String.strip(result), "\n")

          [play_status, track_no, played_time, progress] = String.split(String.strip(track_status))
          [volume, repeat, random, single, consume] = String.split(String.strip(player_status), "   ")

          [played_time, _] = String.split(String.strip(played_time), "/")

          case String.split(String.strip(played_time), ":") do
            ["600", _] ->
              System.cmd "mpc stop && mpc play"
            _  ->
              Minion.State.set("played_time", played_time)
          end

          [_, volume] = String.split(String.strip(volume))
          Minion.State.set("volume", volume)

          case String.strip(url) do
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

  get "/:node/set_station/:station" do
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

  post "/:node/add_station" do
    selected_node = conn.params[:node]
  end

  get "/:node/set_volume/:volume" do
    selected_node = conn.params[:node]
    volume = conn.params[:volume]

    Gru.only [:"#{selected_node}"], "mpc volume #{volume}"

    redirect! conn, to: "/#{selected_node}"
  end

  get "/:node/pause" do
    selected_node = conn.params[:node]

    Gru.only [:"#{selected_node}"], "mpc pause"

    redirect! conn, to: "/#{selected_node}"
  end

  get "/:node/play" do
    selected_node = conn.params[:node]

    Gru.only [:"#{selected_node}"], "mpc play"

    redirect! conn, to: "/#{selected_node}"
  end
end
