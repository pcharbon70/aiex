ExUnit.start()

# Start Phoenix endpoint for LiveView tests
{:ok, _} = Application.ensure_all_started(:aiex)

# Load test helpers
Code.require_file("support/test_engine.ex", __DIR__)
Code.require_file("support/test_projections.ex", __DIR__)
Code.require_file("support/conn_case.ex", __DIR__)
Code.require_file("support/web_case.ex", __DIR__)
Code.require_file("support/web_test_helpers.ex", __DIR__)
