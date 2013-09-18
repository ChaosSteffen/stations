Dynamo.under_test(Stations.Dynamo)
Dynamo.Loader.enable
ExUnit.start

defmodule Stations.TestCase do
  use ExUnit.CaseTemplate

  # Enable code reloading on test cases
  setup do
    Dynamo.Loader.enable
    :ok
  end
end
