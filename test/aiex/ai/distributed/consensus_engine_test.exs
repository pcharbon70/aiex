defmodule Aiex.AI.Distributed.ConsensusEngineTest do
  use ExUnit.Case, async: false
  
  alias Aiex.AI.Distributed.ConsensusEngine
  
  setup do
    # Start ConsensusEngine for testing
    {:ok, pid} = ConsensusEngine.start_link([])
    on_exit(fn -> 
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)
    %{consensus_pid: pid}
  end
  
  describe "consensus reaching" do
    test "reaches consensus with sufficient responses" do
      responses = [
        %{
          provider: :openai,
          content: "This is a comprehensive response with good detail.",
          quality_score: 0.8,
          timestamp: System.system_time(:millisecond),
          success: true
        },
        %{
          provider: :anthropic,
          content: "Another good response.",
          quality_score: 0.7,
          timestamp: System.system_time(:millisecond),
          success: true
        }
      ]
      
      result = ConsensusEngine.reach_consensus(responses)
      
      assert {:ok, consensus_result} = result
      assert is_map(consensus_result)
      assert Map.has_key?(consensus_result, :selected_response)
      assert Map.has_key?(consensus_result, :confidence)
      assert Map.has_key?(consensus_result, :voting_breakdown)
      assert Map.has_key?(consensus_result, :consensus_method)
      assert Map.has_key?(consensus_result, :metadata)
      
      assert is_map(consensus_result.selected_response)
      assert is_float(consensus_result.confidence)
      assert consensus_result.confidence >= 0.0
      assert consensus_result.confidence <= 1.0
      assert is_atom(consensus_result.consensus_method)
    end
    
    test "rejects consensus with insufficient responses" do
      responses = [
        %{
          provider: :openai,
          content: "Single response",
          quality_score: 0.8,
          timestamp: System.system_time(:millisecond),
          success: true
        }
      ]
      
      result = ConsensusEngine.reach_consensus(responses)
      
      assert {:error, :insufficient_responses} = result
    end
    
    test "handles empty response list" do
      result = ConsensusEngine.reach_consensus([])
      
      assert {:error, :insufficient_responses} = result
    end
  end
  
  describe "voting strategies" do
    test "can set different voting strategies" do
      strategies = [:majority, :quality_weighted, :ranked_choice, :hybrid]
      
      Enum.each(strategies, fn strategy ->
        result = ConsensusEngine.set_voting_strategy(strategy)
        assert :ok = result
      end)
    end
    
    test "rejects invalid voting strategies" do
      result = ConsensusEngine.set_voting_strategy(:invalid_strategy)
      assert {:error, :invalid_strategy} = result
    end
    
    test "different strategies produce valid results" do
      responses = [
        %{
          provider: :openai,
          content: "Response 1",
          quality_score: 0.9,
          duration_ms: 1000,
          timestamp: System.system_time(:millisecond),
          success: true
        },
        %{
          provider: :anthropic,
          content: "Response 2",
          quality_score: 0.7,
          duration_ms: 1500,
          timestamp: System.system_time(:millisecond),
          success: true
        },
        %{
          provider: :ollama,
          content: "Response 3",
          quality_score: 0.6,
          duration_ms: 2000,
          timestamp: System.system_time(:millisecond),
          success: true
        }
      ]
      
      strategies = [:majority, :quality_weighted, :ranked_choice, :hybrid]
      
      Enum.each(strategies, fn strategy ->
        ConsensusEngine.set_voting_strategy(strategy)
        
        result = ConsensusEngine.reach_consensus(responses)
        
        assert {:ok, consensus_result} = result
        assert consensus_result.consensus_method == strategy
        assert is_map(consensus_result.selected_response)
        assert consensus_result.selected_response.provider in [:openai, :anthropic, :ollama]
      end)
    end
  end
  
  describe "consensus statistics" do
    test "returns comprehensive consensus statistics" do
      stats = ConsensusEngine.get_consensus_stats()
      
      assert is_map(stats)
      assert Map.has_key?(stats, :voting_strategy)
      assert Map.has_key?(stats, :minimum_responses)
      assert Map.has_key?(stats, :confidence_threshold)
      assert Map.has_key?(stats, :total_consensus_decisions)
      assert Map.has_key?(stats, :avg_confidence)
      assert Map.has_key?(stats, :provider_selection_frequency)
      assert Map.has_key?(stats, :method_usage)
      assert Map.has_key?(stats, :recent_performance)
      assert Map.has_key?(stats, :timestamp)
      
      assert is_atom(stats.voting_strategy)
      assert is_integer(stats.minimum_responses)
      assert is_float(stats.confidence_threshold)
      assert is_integer(stats.total_consensus_decisions)
      assert is_float(stats.avg_confidence)
      assert is_map(stats.provider_selection_frequency)
      assert is_map(stats.method_usage)
      assert is_map(stats.recent_performance)
      assert is_integer(stats.timestamp)
    end
    
    test "statistics start with reasonable defaults" do
      stats = ConsensusEngine.get_consensus_stats()
      
      # Should start with no consensus decisions
      assert stats.total_consensus_decisions == 0
      assert stats.avg_confidence == 0.0
      assert map_size(stats.provider_selection_frequency) == 0
      assert map_size(stats.method_usage) == 0
    end
    
    test "statistics are updated after consensus decisions" do
      initial_stats = ConsensusEngine.get_consensus_stats()
      
      responses = [
        %{
          provider: :openai,
          content: "Test response 1",
          quality_score: 0.8,
          timestamp: System.system_time(:millisecond),
          success: true
        },
        %{
          provider: :anthropic,
          content: "Test response 2",
          quality_score: 0.7,
          timestamp: System.system_time(:millisecond),
          success: true
        }
      ]
      
      {:ok, _result} = ConsensusEngine.reach_consensus(responses)
      
      updated_stats = ConsensusEngine.get_consensus_stats()
      
      # Should have updated statistics
      assert updated_stats.total_consensus_decisions > initial_stats.total_consensus_decisions
      assert updated_stats.timestamp >= initial_stats.timestamp
    end
  end
  
  describe "performance weights" do
    test "can update performance weights" do
      weights = %{
        openai: 1.2,
        anthropic: 1.0,
        ollama: 0.8
      }
      
      result = ConsensusEngine.update_performance_weights(weights)
      assert :ok = result
    end
    
    test "performance weights affect consensus decisions" do
      # Set weights favoring one provider
      weights = %{
        openai: 1.5,
        anthropic: 0.5
      }
      
      ConsensusEngine.update_performance_weights(weights)
      ConsensusEngine.set_voting_strategy(:quality_weighted)
      
      responses = [
        %{
          provider: :openai,
          content: "OpenAI response",
          quality_score: 0.7,
          timestamp: System.system_time(:millisecond),
          success: true
        },
        %{
          provider: :anthropic,
          content: "Anthropic response",
          quality_score: 0.8,  # Higher base quality
          timestamp: System.system_time(:millisecond),
          success: true
        }
      ]
      
      {:ok, result} = ConsensusEngine.reach_consensus(responses)
      
      # With weights, OpenAI might be selected despite lower quality
      assert result.selected_response.provider in [:openai, :anthropic]
      assert Map.has_key?(result.voting_breakdown, :weights)
    end
  end
  
  describe "consensus methods" do
    test "majority consensus works correctly" do
      ConsensusEngine.set_voting_strategy(:majority)
      
      responses = [
        %{
          provider: :openai,
          content: "High quality response",
          quality_score: 0.9,
          timestamp: System.system_time(:millisecond),
          success: true
        },
        %{
          provider: :anthropic,
          content: "Lower quality response",
          quality_score: 0.6,
          timestamp: System.system_time(:millisecond),
          success: true
        }
      ]
      
      {:ok, result} = ConsensusEngine.reach_consensus(responses)
      
      assert result.consensus_method == :majority
      assert result.selected_response.provider == :openai  # Higher quality should win
    end
    
    test "quality weighted consensus considers weights" do
      ConsensusEngine.set_voting_strategy(:quality_weighted)
      
      responses = [
        %{
          provider: :openai,
          content: "Response 1",
          quality_score: 0.8,
          timestamp: System.system_time(:millisecond),
          success: true
        },
        %{
          provider: :anthropic,
          content: "Response 2",
          quality_score: 0.7,
          timestamp: System.system_time(:millisecond),
          success: true
        }
      ]
      
      {:ok, result} = ConsensusEngine.reach_consensus(responses)
      
      assert result.consensus_method == :quality_weighted
      assert Map.has_key?(result.voting_breakdown, :weights)
      assert Map.has_key?(result.voting_breakdown, :total_weight)
    end
    
    test "ranked choice consensus uses multiple criteria" do
      ConsensusEngine.set_voting_strategy(:ranked_choice)
      
      responses = [
        %{
          provider: :openai,
          content: "Response 1",
          quality_score: 0.8,
          duration_ms: 1000,
          timestamp: System.system_time(:millisecond),
          success: true
        },
        %{
          provider: :anthropic,
          content: "Response 2",
          quality_score: 0.7,
          duration_ms: 500,  # Faster response
          timestamp: System.system_time(:millisecond),
          success: true
        }
      ]
      
      {:ok, result} = ConsensusEngine.reach_consensus(responses)
      
      assert result.consensus_method == :ranked_choice
      assert Map.has_key?(result.voting_breakdown, :borda_scores)
      assert Map.has_key?(result.voting_breakdown, :rankings)
    end
    
    test "hybrid consensus combines multiple methods" do
      ConsensusEngine.set_voting_strategy(:hybrid)
      
      responses = [
        %{
          provider: :openai,
          content: "Response 1",
          quality_score: 0.8,
          duration_ms: 1000,
          timestamp: System.system_time(:millisecond),
          success: true
        },
        %{
          provider: :anthropic,
          content: "Response 2",
          quality_score: 0.7,
          duration_ms: 1500,
          timestamp: System.system_time(:millisecond),
          success: true
        }
      ]
      
      {:ok, result} = ConsensusEngine.reach_consensus(responses)
      
      assert result.consensus_method == :hybrid
      assert Map.has_key?(result.voting_breakdown, :composite_scores)
      assert Map.has_key?(result.voting_breakdown, :method_results)
      assert Map.has_key?(result.voting_breakdown, :method_confidences)
    end
  end
  
  describe "confidence calculation" do
    test "confidence reflects consensus strength" do
      # Test with very different quality scores
      high_confidence_responses = [
        %{
          provider: :openai,
          content: "Excellent response",
          quality_score: 0.95,
          timestamp: System.system_time(:millisecond),
          success: true
        },
        %{
          provider: :anthropic,
          content: "Poor response",
          quality_score: 0.3,
          timestamp: System.system_time(:millisecond),
          success: true
        }
      ]
      
      # Test with similar quality scores
      low_confidence_responses = [
        %{
          provider: :openai,
          content: "Response 1",
          quality_score: 0.75,
          timestamp: System.system_time(:millisecond),
          success: true
        },
        %{
          provider: :anthropic,
          content: "Response 2",
          quality_score: 0.73,
          timestamp: System.system_time(:millisecond),
          success: true
        }
      ]
      
      {:ok, high_confidence_result} = ConsensusEngine.reach_consensus(high_confidence_responses)
      {:ok, low_confidence_result} = ConsensusEngine.reach_consensus(low_confidence_responses)
      
      # High difference should lead to higher confidence
      assert high_confidence_result.confidence >= low_confidence_result.confidence
    end
    
    test "confidence is within valid range" do
      responses = [
        %{
          provider: :openai,
          content: "Response 1",
          quality_score: 0.8,
          timestamp: System.system_time(:millisecond),
          success: true
        },
        %{
          provider: :anthropic,
          content: "Response 2",
          quality_score: 0.6,
          timestamp: System.system_time(:millisecond),
          success: true
        }
      ]
      
      {:ok, result} = ConsensusEngine.reach_consensus(responses)
      
      assert result.confidence >= 0.0
      assert result.confidence <= 1.0
    end
  end
  
  describe "concurrent consensus operations" do
    test "handles multiple concurrent consensus requests" do
      responses_sets = Enum.map(1..3, fn i ->
        [
          %{
            provider: :openai,
            content: "Response #{i}-1",
            quality_score: 0.8,
            timestamp: System.system_time(:millisecond),
            success: true
          },
          %{
            provider: :anthropic,
            content: "Response #{i}-2",
            quality_score: 0.7,
            timestamp: System.system_time(:millisecond),
            success: true
          }
        ]
      end)
      
      # Submit consensus requests concurrently
      tasks = Enum.map(responses_sets, fn responses ->
        Task.async(fn ->
          ConsensusEngine.reach_consensus(responses)
        end)
      end)
      
      # Wait for all to complete
      results = Task.await_many(tasks, 10_000)
      
      # All should complete successfully
      assert length(results) == 3
      Enum.each(results, fn result ->
        assert {:ok, consensus_result} = result
        assert is_map(consensus_result)
      end)
    end
    
    test "maintains statistics consistency under concurrent load" do
      initial_stats = ConsensusEngine.get_consensus_stats()
      
      # Submit multiple consensus requests
      tasks = Enum.map(1..5, fn i ->
        Task.async(fn ->
          responses = [
            %{
              provider: :openai,
              content: "Load test #{i}-1",
              quality_score: 0.8,
              timestamp: System.system_time(:millisecond),
              success: true
            },
            %{
              provider: :anthropic,
              content: "Load test #{i}-2",
              quality_score: 0.7,
              timestamp: System.system_time(:millisecond),
              success: true
            }
          ]
          
          ConsensusEngine.reach_consensus(responses)
        end)
      end)
      
      # Wait for completion
      Task.await_many(tasks, 15_000)
      
      # Statistics should be updated consistently
      updated_stats = ConsensusEngine.get_consensus_stats()
      
      assert updated_stats.total_consensus_decisions >= initial_stats.total_consensus_decisions + 5
      assert updated_stats.timestamp >= initial_stats.timestamp
    end
  end
  
  describe "error handling and robustness" do
    test "handles responses without quality scores" do
      responses = [
        %{
          provider: :openai,
          content: "Response without quality score",
          timestamp: System.system_time(:millisecond),
          success: true
        },
        %{
          provider: :anthropic,
          content: "Another response without quality score",
          timestamp: System.system_time(:millisecond),
          success: true
        }
      ]
      
      # Should not crash and should calculate quality scores internally
      result = ConsensusEngine.reach_consensus(responses)
      
      assert {:ok, consensus_result} = result
      assert is_map(consensus_result.selected_response)
    end
    
    test "handles malformed responses gracefully" do
      malformed_responses = [
        %{
          provider: :openai,
          # Missing content
          quality_score: 0.8,
          timestamp: System.system_time(:millisecond),
          success: true
        },
        %{
          # Missing provider
          content: "Response without provider",
          quality_score: 0.7,
          timestamp: System.system_time(:millisecond),
          success: true
        }
      ]
      
      # Should handle gracefully, not crash
      result = ConsensusEngine.reach_consensus(malformed_responses)
      
      assert is_tuple(result)
    end
    
    test "remains responsive after error conditions" do
      # Try various operations that might cause errors
      ConsensusEngine.reach_consensus([%{}])
      ConsensusEngine.set_voting_strategy(:invalid)
      ConsensusEngine.update_performance_weights(%{invalid: "data"})
      
      # ConsensusEngine should still be responsive
      stats = ConsensusEngine.get_consensus_stats()
      assert is_map(stats)
      
      # Valid operation should still work
      valid_responses = [
        %{
          provider: :openai,
          content: "Valid response 1",
          quality_score: 0.8,
          timestamp: System.system_time(:millisecond),
          success: true
        },
        %{
          provider: :anthropic,
          content: "Valid response 2",
          quality_score: 0.7,
          timestamp: System.system_time(:millisecond),
          success: true
        }
      ]
      
      result = ConsensusEngine.reach_consensus(valid_responses)
      assert {:ok, _consensus_result} = result
    end
  end
end