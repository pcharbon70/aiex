defmodule Aiex.AI.Distributed.ResponseSelectionTest do
  use ExUnit.Case, async: false
  
  alias Aiex.AI.Distributed.{
    ResponseSelector,
    PreferenceLearner,
    PgConsensusCoordinator,
    OverrideManager,
    ConfidenceScorer
  }
  
  @moduletag :distributed_response_selection
  
  setup do
    # Ensure pg application is started
    Application.ensure_all_started(:pg)
    
    # Ensure mnesia is started for our tests
    Application.ensure_all_started(:mnesia)
    
    # Start the required processes for testing
    {:ok, _} = start_supervised(ResponseSelector)
    {:ok, _} = start_supervised(PreferenceLearner)
    {:ok, _} = start_supervised(PgConsensusCoordinator)
    {:ok, _} = start_supervised(OverrideManager)
    {:ok, _} = start_supervised(ConfidenceScorer)
    
    :ok
  end
  
  describe "ResponseSelector" do
    test "selects response using distributed ML ranking" do
      responses = [
        %{provider: :openai, content: "High quality response", quality_score: 0.9, duration_ms: 1500},
        %{provider: :anthropic, content: "Medium quality response", quality_score: 0.7, duration_ms: 2000},
        %{provider: :ollama, content: "Lower quality response", quality_score: 0.5, duration_ms: 3000}
      ]
      
      context = %{type: :code_explanation, domain: :elixir}
      
      assert {:ok, result} = ResponseSelector.select_response(responses, context)
      assert result.selected_response.provider in [:openai, :anthropic, :ollama]
      assert result.confidence > 0.0
      assert result.confidence <= 1.0
      assert is_binary(result.selection_id)
      assert Map.has_key?(result, :explanation)
      assert Map.has_key?(result, :metadata)
    end
    
    test "handles empty response list gracefully" do
      responses = []
      context = %{type: :general}
      
      assert {:error, :selection_failed} = ResponseSelector.select_response(responses, context)
    end
    
    test "records user preference for learning" do
      selection_id = "test_selection_123"
      chosen_response = %{provider: :openai, content: "Good response"}
      rejected_responses = [
        %{provider: :anthropic, content: "Not as good"},
        %{provider: :ollama, content: "Poor response"}
      ]
      feedback = %{rating: 5, comment: "Very helpful"}
      
      assert :ok = ResponseSelector.record_preference(selection_id, chosen_response, rejected_responses, feedback)
    end
    
    test "applies override rules correctly" do
      # Create an override rule favoring OpenAI
      user_id = "test_user"
      context_pattern = %{type: :code_generation}
      preference_rule = %{type: :provider, provider: :openai}
      
      assert {:ok, rule} = OverrideManager.create_override_rule(user_id, context_pattern, preference_rule)
      
      responses = [
        %{provider: :openai, content: "OpenAI response", quality_score: 0.7},
        %{provider: :anthropic, content: "Anthropic response", quality_score: 0.9}
      ]
      
      context = %{type: :code_generation, user_id: user_id}
      
      # Should select OpenAI despite lower quality due to override
      assert {:ok, result} = ResponseSelector.select_response(responses, context)
      assert result.selected_response.provider == :openai
    end
    
    test "provides detailed explanations for selection decisions" do
      selection_id = "test_selection_456"
      
      # First create a selection
      responses = [
        %{provider: :openai, content: "Response 1", quality_score: 0.8},
        %{provider: :anthropic, content: "Response 2", quality_score: 0.6}
      ]
      
      context = %{type: :explanation}
      assert {:ok, result} = ResponseSelector.select_response(responses, context)
      
      # Then request explanation
      assert {:ok, explanation} = ResponseSelector.explain_selection(result.selection_id)
      assert Map.has_key?(explanation, :basic_explanation)
      assert Map.has_key?(explanation, :detailed_analysis)
      assert Map.has_key?(explanation, :recommendations)
    end
    
    test "gets comprehensive selection statistics" do
      assert stats = ResponseSelector.get_selection_stats()
      assert Map.has_key?(stats, :node_id)
      assert Map.has_key?(stats, :total_selections)
      assert Map.has_key?(stats, :preference_data_points)
      assert Map.has_key?(stats, :avg_confidence)
      assert Map.has_key?(stats, :ml_model_performance)
      assert Map.has_key?(stats, :timestamp)
    end
  end
  
  describe "PreferenceLearner" do
    test "records and learns from user preferences" do
      user_id = "test_user_learning"
      context = %{type: :code_review, language: :elixir}
      chosen_response = %{provider: :anthropic, content: "Excellent review", quality_score: 0.9}
      alternatives = [
        %{provider: :openai, content: "Good review", quality_score: 0.7},
        %{provider: :ollama, content: "Basic review", quality_score: 0.5}
      ]
      feedback = %{helpful: true, accuracy: 5}
      
      assert :ok = PreferenceLearner.record_preference(user_id, context, chosen_response, alternatives, feedback)
    end
    
    test "predicts user preferences based on history" do
      user_id = "test_user_prediction"
      
      # Record some preferences first
      context = %{type: :documentation}
      chosen_response = %{provider: :anthropic, content: "Great docs"}
      alternatives = [%{provider: :openai, content: "Okay docs"}]
      
      :ok = PreferenceLearner.record_preference(user_id, context, chosen_response, alternatives)
      
      # Now predict preferences
      responses = [
        %{provider: :anthropic, content: "New response from Anthropic"},
        %{provider: :openai, content: "New response from OpenAI"}
      ]
      
      assert {:ok, predictions} = PreferenceLearner.predict_preference(user_id, context, responses)
      assert Map.has_key?(predictions, :predictions)
      assert Map.has_key?(predictions, :user_profile_strength)
      assert is_list(predictions.predictions)
    end
    
    test "builds comprehensive user profiles" do
      user_id = "test_user_profile"
      
      profile = PreferenceLearner.get_user_profile(user_id)
      assert Map.has_key?(profile, :user_id)
      assert Map.has_key?(profile, :total_preferences)
      assert Map.has_key?(profile, :preference_patterns)
      assert Map.has_key?(profile, :favorite_providers)
      assert Map.has_key?(profile, :confidence_level)
    end
    
    test "analyzes preference patterns automatically" do
      assert {:ok, patterns} = PreferenceLearner.analyze_patterns()
      assert is_list(patterns)
    end
    
    test "updates models based on preferences" do
      # With sufficient data, should be able to update models
      assert result = PreferenceLearner.update_models()
      assert result in [{:ok, :model_updated}, {:ok, :no_improvement}, {:error, :insufficient_data}]
    end
    
    test "provides global preference statistics" do
      assert stats = PreferenceLearner.get_preference_stats()
      assert Map.has_key?(stats, :node_stats)
      assert Map.has_key?(stats, :cluster_stats)
      assert Map.has_key?(stats, :model_performance)
      assert Map.has_key?(stats, :pattern_insights)
    end
  end
  
  describe "PgConsensusCoordinator" do
    test "coordinates consensus with single node" do
      consensus_request = %{
        ml_rankings: [
          %{response: %{provider: :openai, content: "Test"}, ml_score: 0.8},
          %{response: %{provider: :anthropic, content: "Test"}, ml_score: 0.6}
        ],
        strategy: :hybrid,
        timestamp: System.system_time(:millisecond)
      }
      
      assert {:ok, result} = PgConsensusCoordinator.coordinate_consensus(consensus_request)
      assert Map.has_key?(result, :selected_response)
      assert Map.has_key?(result, :confidence)
      assert Map.has_key?(result, :consensus_method)
    end
    
    test "handles consensus timeout gracefully" do
      consensus_request = %{
        ml_rankings: [],
        strategy: :majority,
        timestamp: System.system_time(:millisecond)
      }
      
      # Should handle empty rankings gracefully
      assert {:ok, result} = PgConsensusCoordinator.coordinate_consensus(consensus_request)
      assert result.consensus_method == :local_fallback
    end
    
    test "provides consensus statistics" do
      assert stats = PgConsensusCoordinator.get_consensus_stats()
      assert Map.has_key?(stats, :node_id)
      assert Map.has_key?(stats, :active_rounds)
      assert Map.has_key?(stats, :completed_rounds)
      assert Map.has_key?(stats, :peer_nodes_count)
      assert Map.has_key?(stats, :quorum_config)
    end
    
    test "assesses cluster health" do
      assert health = PgConsensusCoordinator.get_cluster_health()
      assert Map.has_key?(health, :cluster_size)
      assert Map.has_key?(health, :active_nodes)
      assert Map.has_key?(health, :consensus_readiness)
      assert Map.has_key?(health, :quorum_achievable)
    end
    
    test "updates voting weights" do
      weights = %{
        node1: 1.0,
        node2: 0.8,
        node3: 1.2
      }
      
      assert :ok = PgConsensusCoordinator.update_voting_weights(weights)
    end
  end
  
  describe "OverrideManager" do
    test "creates and applies user override rules" do
      user_id = "test_override_user"
      context_pattern = %{type: :testing}
      preference_rule = %{type: :provider, provider: :anthropic}
      
      # Create override rule
      assert {:ok, rule} = OverrideManager.create_override_rule(user_id, context_pattern, preference_rule)
      assert rule.user_id == user_id
      assert rule.active == true
      assert is_binary(rule.id)
      
      # Apply override rule
      responses = [
        %{provider: :openai, content: "OpenAI response"},
        %{provider: :anthropic, content: "Anthropic response"}
      ]
      context = %{type: :testing}
      
      assert override_result = OverrideManager.apply_overrides(user_id, context, responses)
      assert override_result.applied == true
      assert override_result.selected_response.provider == :anthropic
    end
    
    test "creates temporary override rules with expiration" do
      user_id = "test_temp_user"
      context_pattern = %{type: :temporary_test}
      preference_rule = %{type: :quality_threshold, minimum_quality: 0.8}
      duration_ms = 5000  # 5 seconds
      
      assert {:ok, rule} = OverrideManager.create_temporary_override(user_id, context_pattern, preference_rule, duration_ms)
      assert rule.scope == :temporary
      assert rule.expires_at > System.system_time(:millisecond)
    end
    
    test "creates administrative override rules" do
      admin_id = "admin_user"
      context_pattern = %{type: :admin_override}
      preference_rule = %{type: :exclude_providers, excluded_providers: [:ollama]}
      
      assert {:ok, rule} = OverrideManager.create_administrative_override(admin_id, context_pattern, preference_rule)
      assert rule.scope == :administrative
      assert rule.priority >= 1000  # High priority
      assert rule.user_id == :global
    end
    
    test "validates override rules before creation" do
      valid_context = %{type: :validation_test}
      valid_preference = %{type: :provider, provider: :openai}
      
      assert {:ok, :valid} = OverrideManager.validate_override_rule(valid_context, valid_preference)
      
      # Test invalid rule
      invalid_preference = %{invalid_field: true}
      assert {:error, _reason} = OverrideManager.validate_override_rule(valid_context, invalid_preference)
    end
    
    test "manages user override rules" do
      user_id = "test_rule_management"
      
      # Create multiple rules
      rule1_pattern = %{type: :rule1}
      rule1_preference = %{type: :provider, provider: :openai}
      assert {:ok, rule1} = OverrideManager.create_override_rule(user_id, rule1_pattern, rule1_preference)
      
      rule2_pattern = %{type: :rule2}
      rule2_preference = %{type: :provider, provider: :anthropic}
      assert {:ok, rule2} = OverrideManager.create_override_rule(user_id, rule2_pattern, rule2_preference)
      
      # Get user rules
      user_rules = OverrideManager.get_user_override_rules(user_id)
      assert length(user_rules) >= 2
      assert Enum.any?(user_rules, &(&1.id == rule1.id))
      assert Enum.any?(user_rules, &(&1.id == rule2.id))
      
      # Update a rule
      updates = %{priority: 800}
      assert {:ok, updated_rule} = OverrideManager.update_override_rule(rule1.id, updates)
      assert updated_rule.priority == 800
      
      # Delete a rule
      assert :ok = OverrideManager.delete_override_rule(rule2.id, user_id)
    end
    
    test "provides override statistics" do
      assert stats = OverrideManager.get_override_stats()
      assert Map.has_key?(stats, :node_id)
      assert Map.has_key?(stats, :total_rules)
      assert Map.has_key?(stats, :user_rules)
      assert Map.has_key?(stats, :administrative_rules)
      assert Map.has_key?(stats, :temporary_rules)
    end
  end
  
  describe "ConfidenceScorer" do
    test "calculates confidence scores for selections" do
      selection_data = %{
        ml_rankings: [
          %{response: %{provider: :openai}, ml_score: 0.8},
          %{response: %{provider: :anthropic}, ml_score: 0.6}
        ],
        consensus_result: %{
          selected_response: %{provider: :openai},
          confidence: 0.7
        },
        participating_nodes: 3
      }
      
      context = %{type: :confidence_test}
      
      assert {:ok, confidence_score} = ConfidenceScorer.calculate_confidence(selection_data, context)
      assert confidence_score.overall_confidence >= 0.0
      assert confidence_score.overall_confidence <= 1.0
      assert Map.has_key?(confidence_score, :factors)
      assert Map.has_key?(confidence_score, :calibrated_confidence)
      assert Map.has_key?(confidence_score, :confidence_interval)
      assert Map.has_key?(confidence_score, :reliability_score)
    end
    
    test "updates confidence models with feedback" do
      prediction = %{
        overall_confidence: 0.8,
        factors: %{ml_confidence: 0.9, consensus_confidence: 0.7}
      }
      actual_outcome = :correct
      metadata = %{test: true}
      
      assert :ok = ConfidenceScorer.update_confidence_model(prediction, actual_outcome, metadata)
    end
    
    test "calibrates models when sufficient data available" do
      # This might return error if insufficient data, which is expected
      result = ConfidenceScorer.calibrate_models()
      assert result in [{:ok, :calibrated}, {:error, :insufficient_data}]
    end
    
    test "provides confidence statistics" do
      assert stats = ConfidenceScorer.get_confidence_stats()
      assert Map.has_key?(stats, :node_id)
      assert Map.has_key?(stats, :confidence_models)
      assert Map.has_key?(stats, :calibration_data_points)
      assert Map.has_key?(stats, :validation_metrics)
      assert Map.has_key?(stats, :recent_confidence_distribution)
    end
    
    test "gets node-specific confidence metrics" do
      assert {:ok, metrics} = ConfidenceScorer.get_node_confidence_metrics()
      assert Map.has_key?(metrics, :node_id)
      assert Map.has_key?(metrics, :avg_confidence)
      assert Map.has_key?(metrics, :confidence_distribution)
      assert Map.has_key?(metrics, :calibration_status)
    end
    
    test "sets and validates confidence thresholds" do
      valid_thresholds = %{
        high_confidence: 0.9,
        medium_confidence: 0.7,
        low_confidence: 0.5,
        minimum_acceptable: 0.3
      }
      
      assert :ok = ConfidenceScorer.set_confidence_thresholds(valid_thresholds)
      
      # Test invalid thresholds
      invalid_thresholds = %{
        high_confidence: 1.5,  # > 1.0
        medium_confidence: 0.7
      }
      
      assert {:error, _reason} = ConfidenceScorer.set_confidence_thresholds(invalid_thresholds)
    end
    
    test "validates confidence accuracy over time" do
      time_window = 86_400_000  # 24 hours
      assert {:ok, validation_result} = ConfidenceScorer.validate_confidence_accuracy(time_window)
      assert Map.has_key?(validation_result, :accuracy)
      assert Map.has_key?(validation_result, :calibration_score)
      assert Map.has_key?(validation_result, :sample_size)
    end
  end
  
  describe "Integration Tests" do
    test "end-to-end response selection workflow" do
      # Setup: Create user preferences and override rules
      user_id = "integration_test_user"
      
      # Record some preferences
      context = %{type: :integration_test, domain: :elixir}
      chosen_response = %{provider: :anthropic, content: "Great response", quality_score: 0.9}
      alternatives = [%{provider: :openai, content: "Good response", quality_score: 0.7}]
      
      :ok = PreferenceLearner.record_preference(user_id, context, chosen_response, alternatives)
      
      # Create an override rule
      override_context = %{type: :integration_test}
      override_rule = %{type: :quality_threshold, minimum_quality: 0.6}
      {:ok, _rule} = OverrideManager.create_override_rule(user_id, override_context, override_rule)
      
      # Perform response selection
      responses = [
        %{provider: :openai, content: "Response 1", quality_score: 0.8, duration_ms: 1500},
        %{provider: :anthropic, content: "Response 2", quality_score: 0.9, duration_ms: 2000},
        %{provider: :ollama, content: "Response 3", quality_score: 0.4, duration_ms: 1000}  # Below threshold
      ]
      
      selection_context = %{type: :integration_test, user_id: user_id}
      
      assert {:ok, result} = ResponseSelector.select_response(responses, selection_context)
      
      # Verify selection results
      assert result.selected_response.provider in [:openai, :anthropic]  # Should exclude ollama due to quality threshold
      assert result.selected_response.quality_score >= 0.6  # Meets override threshold
      assert result.confidence > 0.0
      assert is_binary(result.selection_id)
      
      # Verify confidence scoring
      assert Map.has_key?(result.metadata, :peer_nodes_consulted)
      
      # Test explanation generation
      assert {:ok, explanation} = ResponseSelector.explain_selection(result.selection_id)
      assert Map.has_key?(explanation, :basic_explanation)
      
      # Record feedback for this selection
      feedback = %{rating: 4, helpful: true}
      assert :ok = ResponseSelector.record_preference(result.selection_id, result.selected_response, responses -- [result.selected_response], feedback)
    end
    
    test "consensus coordination with multiple selection strategies" do
      consensus_request = %{
        ml_rankings: [
          %{response: %{provider: :openai, content: "Test 1"}, ml_score: 0.8},
          %{response: %{provider: :anthropic, content: "Test 2"}, ml_score: 0.7},
          %{response: %{provider: :ollama, content: "Test 3"}, ml_score: 0.6}
        ],
        strategy: :hybrid,
        timestamp: System.system_time(:millisecond)
      }
      
      # Test different consensus strategies
      strategies = [:hybrid, :quality_weighted, :majority]
      
      for strategy <- strategies do
        request_with_strategy = %{consensus_request | strategy: strategy}
        assert {:ok, result} = PgConsensusCoordinator.coordinate_consensus(request_with_strategy)
        assert Map.has_key?(result, :selected_response)
        assert Map.has_key?(result, :confidence)
        assert Map.has_key?(result, :consensus_method)
      end
    end
    
    test "confidence scoring with calibration feedback loop" do
      # Generate multiple confidence scores
      selection_data_list = [
        %{
          ml_rankings: [%{response: %{provider: :openai}, ml_score: 0.9}],
          consensus_result: %{selected_response: %{provider: :openai}, confidence: 0.8}
        },
        %{
          ml_rankings: [%{response: %{provider: :anthropic}, ml_score: 0.7}],
          consensus_result: %{selected_response: %{provider: :anthropic}, confidence: 0.6}
        },
        %{
          ml_rankings: [%{response: %{provider: :ollama}, ml_score: 0.5}],
          consensus_result: %{selected_response: %{provider: :ollama}, confidence: 0.4}
        }
      ]
      
      context = %{type: :calibration_test}
      
      # Calculate confidence scores
      confidence_scores = Enum.map(selection_data_list, fn selection_data ->
        {:ok, score} = ConfidenceScorer.calculate_confidence(selection_data, context)
        score
      end)
      
      # Provide feedback on predictions
      outcomes = [:correct, :correct, :incorrect]
      
      Enum.zip(confidence_scores, outcomes)
      |> Enum.each(fn {prediction, outcome} ->
        :ok = ConfidenceScorer.update_confidence_model(prediction, outcome)
      end)
      
      # Verify feedback was recorded
      stats = ConfidenceScorer.get_confidence_stats()
      assert stats.calibration_data_points >= 3
    end
    
    test "override rule priority and conflict resolution" do
      user_id = "priority_test_user"
      
      # Create multiple override rules with different priorities
      high_priority_pattern = %{type: :priority_test, priority: :high}
      high_priority_rule = %{type: :provider, provider: :anthropic}
      {:ok, high_rule} = OverrideManager.create_override_rule(user_id, high_priority_pattern, high_priority_rule, priority: 800)
      
      low_priority_pattern = %{type: :priority_test}
      low_priority_rule = %{type: :provider, provider: :openai}
      {:ok, low_rule} = OverrideManager.create_override_rule(user_id, low_priority_pattern, low_priority_rule, priority: 400)
      
      # Test that higher priority rule takes precedence
      responses = [
        %{provider: :openai, content: "OpenAI response"},
        %{provider: :anthropic, content: "Anthropic response"}
      ]
      
      context = %{type: :priority_test, priority: :high}
      
      override_result = OverrideManager.apply_overrides(user_id, context, responses)
      assert override_result.applied == true
      assert override_result.selected_response.provider == :anthropic  # Higher priority rule
      assert override_result.rule_id == high_rule.id
    end
    
    test "distributed system performance under load" do
      # Simulate multiple concurrent requests
      num_requests = 10
      
      responses = [
        %{provider: :openai, content: "Response 1", quality_score: 0.8},
        %{provider: :anthropic, content: "Response 2", quality_score: 0.7}
      ]
      
      context = %{type: :load_test}
      
      # Run concurrent selections
      tasks = Enum.map(1..num_requests, fn i ->
        Task.async(fn ->
          ResponseSelector.select_response(responses, Map.put(context, :request_id, i))
        end)
      end)
      
      # Wait for all tasks to complete
      results = Task.await_many(tasks, 10_000)
      
      # Verify all requests completed successfully
      successful_results = Enum.filter(results, fn
        {:ok, _} -> true
        _ -> false
      end)
      
      assert length(successful_results) == num_requests
      
      # Verify system statistics reflect the load
      stats = ResponseSelector.get_selection_stats()
      assert stats.total_selections >= num_requests
    end
  end
  
  describe "Error Handling and Edge Cases" do
    test "handles malformed input gracefully" do
      # Test with malformed responses
      malformed_responses = [
        %{invalid: "structure"},
        nil,
        "not a map"
      ]
      
      context = %{type: :error_test}
      
      # Should handle gracefully without crashing
      result = ResponseSelector.select_response(malformed_responses, context)
      assert {:error, _reason} = result
    end
    
    test "handles network partition scenarios" do
      # Test cluster health during simulated partition
      health = PgConsensusCoordinator.get_cluster_health()
      assert Map.has_key?(health, :network_partition_detected)
      assert Map.has_key?(health, :consensus_readiness)
    end
    
    test "validates override rule limits" do
      user_id = "limit_test_user"
      
      # Create many override rules to test limits
      results = Enum.map(1..60, fn i ->
        pattern = %{type: :limit_test, index: i}
        rule = %{type: :provider, provider: :openai}
        OverrideManager.create_override_rule(user_id, pattern, rule)
      end)
      
      # Should eventually hit user limit
      error_results = Enum.filter(results, fn
        {:error, :user_rule_limit_exceeded} -> true
        _ -> false
      end)
      
      assert length(error_results) > 0
    end
    
    test "handles confidence calculation with missing data" do
      incomplete_selection_data = %{
        ml_rankings: [],  # No rankings
        consensus_result: %{}  # No consensus
      }
      
      context = %{type: :incomplete_test}
      
      # Should handle gracefully
      assert {:ok, confidence_score} = ConfidenceScorer.calculate_confidence(incomplete_selection_data, context)
      assert confidence_score.overall_confidence >= 0.0
      assert confidence_score.overall_confidence <= 1.0
    end
  end
end