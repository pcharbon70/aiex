defmodule Aiex.AI.Distributed.QualityMetricsTest do
  use ExUnit.Case
  
  alias Aiex.AI.Distributed.QualityMetrics
  
  describe "response quality assessment" do
    test "assesses successful text response quality" do
      response_data = %{
        response: %{content: "This is a well-structured response with proper explanation and examples."},
        duration_ms: 1500,
        success: true,
        provider: :openai,
        timestamp: System.system_time(:millisecond)
      }
      
      quality_score = QualityMetrics.assess_response_quality(response_data)
      
      assert is_float(quality_score)
      assert quality_score >= 0.0
      assert quality_score <= 1.0
      assert quality_score > 0.5  # Should be reasonable quality
    end
    
    test "returns zero quality for failed responses" do
      response_data = %{
        response: nil,
        duration_ms: 5000,
        success: false,
        provider: :openai,
        timestamp: System.system_time(:millisecond)
      }
      
      quality_score = QualityMetrics.assess_response_quality(response_data)
      
      assert quality_score == 0.0
    end
    
    test "handles different response formats" do
      response_formats = [
        %{content: "String content response"},
        "Direct string response",
        %{"content" => "Map with string key"},
        %{other_field: "Non-standard format"}
      ]
      
      Enum.each(response_formats, fn response ->
        response_data = %{
          response: response,
          duration_ms: 1000,
          success: true,
          provider: :test,
          timestamp: System.system_time(:millisecond)
        }
        
        quality_score = QualityMetrics.assess_response_quality(response_data)
        
        assert is_float(quality_score)
        assert quality_score >= 0.0
        assert quality_score <= 1.0
      end)
    end
  end
  
  describe "completeness assessment" do
    test "rates short responses as low completeness" do
      short_response = "Yes."
      completeness = QualityMetrics.assess_completeness(short_response)
      
      assert completeness <= 0.4
    end
    
    test "rates comprehensive responses as high completeness" do
      comprehensive_response = """
      This is a comprehensive response that explains the concept in detail,
      provides examples, discusses potential edge cases, and offers practical
      implementation guidance. It covers multiple aspects of the topic and
      provides sufficient depth for the user to understand the subject matter.
      """
      
      completeness = QualityMetrics.assess_completeness(comprehensive_response)
      
      assert completeness >= 0.7
    end
    
    test "handles empty responses" do
      completeness = QualityMetrics.assess_completeness("")
      
      assert completeness >= 0.0
      assert completeness <= 1.0
    end
  end
  
  describe "relevance assessment" do
    test "assesses relevance of code responses" do
      code_response = """
      Here's a function that adds two numbers:
      
      ```elixir
      def add(a, b) do
        a + b
      end
      ```
      
      This function takes two parameters and returns their sum.
      """
      
      relevance = QualityMetrics.assess_relevance(code_response)
      
      assert is_float(relevance)
      assert relevance > 0.5  # Should be relevant
    end
    
    test "detects irrelevant content patterns" do
      irrelevant_response = "I cannot help with that request."
      
      relevance = QualityMetrics.assess_relevance(irrelevant_response)
      
      assert is_float(relevance)
      # May still have some relevance score but should be lower
      assert relevance >= 0.0
      assert relevance <= 1.0
    end
  end
  
  describe "clarity assessment" do
    test "assesses well-structured content as clear" do
      clear_content = """
      ## Overview
      
      This section explains the concept clearly.
      
      ### Implementation
      
      Here's how to implement it:
      
      1. First step
      2. Second step
      3. Final step
      
      The implementation follows these principles for clarity.
      """
      
      clarity = QualityMetrics.assess_clarity(clear_content)
      
      assert is_float(clarity)
      assert clarity > 0.6  # Should be fairly clear
    end
    
    test "handles content without structure" do
      unstructured_content = "this is all one long sentence without any structure or formatting which makes it harder to read and understand the content being presented"
      
      clarity = QualityMetrics.assess_clarity(unstructured_content)
      
      assert is_float(clarity)
      assert clarity >= 0.0
      assert clarity <= 1.0
    end
  end
  
  describe "code quality assessment" do
    test "assesses code blocks in responses" do
      response_with_code = """
      Here's a function:
      
      ```elixir
      def calculate_total(items) do
        Enum.reduce(items, 0, fn item, acc ->
          acc + item.price
        end)
      end
      ```
      
      This function properly calculates the total.
      """
      
      code_quality = QualityMetrics.assess_code_quality(response_with_code)
      
      assert is_float(code_quality)
      assert code_quality > 0.5  # Should be reasonable quality
    end
    
    test "handles responses without code" do
      text_response = "This is a text-only response without any code."
      
      code_quality = QualityMetrics.assess_code_quality(text_response)
      
      assert code_quality == 1.0  # Full marks when no code expected
    end
    
    test "detects poor code formatting" do
      poorly_formatted_code = """
      Here's some code: def bad_function(x,y):return x+y
      """
      
      code_quality = QualityMetrics.assess_code_quality(poorly_formatted_code)
      
      assert is_float(code_quality)
      # Should detect poor formatting
      assert code_quality < 0.9
    end
  end
  
  describe "response time assessment" do
    test "rates fast responses highly" do
      fast_time_score = QualityMetrics.assess_response_time(800)  # 0.8 seconds
      
      assert fast_time_score >= 0.9
    end
    
    test "rates slow responses poorly" do
      slow_time_score = QualityMetrics.assess_response_time(25_000)  # 25 seconds
      
      assert slow_time_score <= 0.3
    end
    
    test "handles extreme response times" do
      very_fast = QualityMetrics.assess_response_time(100)  # 0.1 seconds
      very_slow = QualityMetrics.assess_response_time(60_000)  # 1 minute
      
      assert very_fast == 1.0
      assert very_slow <= 0.1
    end
  end
  
  describe "format quality assessment" do
    test "rates well-formatted markdown highly" do
      markdown_content = """
      # Main Title
      
      This content has **bold text** and *italic text*.
      
      ## Subsection
      
      - List item 1
      - List item 2
      
      ```elixir
      # Code block
      def example, do: :ok
      ```
      """
      
      format_quality = QualityMetrics.assess_format_quality(markdown_content)
      
      assert is_float(format_quality)
      assert format_quality >= 0.7
    end
    
    test "handles plain text appropriately" do
      plain_text = "This is just plain text without any formatting."
      
      format_quality = QualityMetrics.assess_format_quality(plain_text)
      
      assert is_float(format_quality)
      assert format_quality >= 0.0
      assert format_quality <= 1.0
    end
  end
  
  describe "response comparison" do
    test "compares two responses and identifies better one" do
      response1 = %{
        response: %{content: "Short answer."},
        duration_ms: 1000,
        success: true,
        provider: :provider1,
        timestamp: System.system_time(:millisecond)
      }
      
      response2 = %{
        response: %{content: "This is a much more comprehensive and detailed answer that provides better value to the user with explanations and examples."},
        duration_ms: 1500,
        success: true,
        provider: :provider2,
        timestamp: System.system_time(:millisecond)
      }
      
      comparison = QualityMetrics.compare_responses(response1, response2)
      
      assert is_map(comparison)
      assert Map.has_key?(comparison, :quality1)
      assert Map.has_key?(comparison, :quality2)
      assert Map.has_key?(comparison, :difference)
      assert Map.has_key?(comparison, :better_response)
      
      assert is_float(comparison.quality1)
      assert is_float(comparison.quality2)
      assert comparison.better_response in [:response1, :response2]
    end
    
    test "handles identical responses" do
      response1 = %{
        response: %{content: "Same content"},
        duration_ms: 1000,
        success: true,
        provider: :provider1,
        timestamp: System.system_time(:millisecond)
      }
      
      response2 = %{
        response: %{content: "Same content"},
        duration_ms: 1000,
        success: true,
        provider: :provider2,
        timestamp: System.system_time(:millisecond)
      }
      
      comparison = QualityMetrics.compare_responses(response1, response2)
      
      assert abs(comparison.difference) < 0.1  # Should be very similar
    end
  end
  
  describe "batch assessment" do
    test "assesses multiple responses and sorts by quality" do
      responses = [
        %{
          response: %{content: "Short."},
          duration_ms: 1000,
          success: true,
          provider: :provider1,
          timestamp: System.system_time(:millisecond)
        },
        %{
          response: %{content: "This is a comprehensive response with detailed explanations and examples."},
          duration_ms: 1500,
          success: true,
          provider: :provider2,
          timestamp: System.system_time(:millisecond)
        },
        %{
          response: %{content: "Medium length response with some detail."},
          duration_ms: 1200,
          success: true,
          provider: :provider3,
          timestamp: System.system_time(:millisecond)
        }
      ]
      
      assessed_responses = QualityMetrics.assess_multiple_responses(responses)
      
      assert length(assessed_responses) == 3
      
      # Should be sorted by quality (highest first)
      qualities = Enum.map(assessed_responses, & &1.quality_score)
      assert qualities == Enum.sort(qualities, :desc)
      
      # All should have quality scores
      Enum.each(assessed_responses, fn response ->
        assert Map.has_key?(response, :quality_score)
        assert is_float(response.quality_score)
        assert response.quality_score >= 0.0
        assert response.quality_score <= 1.0
      end)
    end
    
    test "handles empty response list" do
      assessed_responses = QualityMetrics.assess_multiple_responses([])
      
      assert assessed_responses == []
    end
  end
  
  describe "edge cases and error handling" do
    test "handles nil response content" do
      response_data = %{
        response: nil,
        duration_ms: 1000,
        success: true,
        provider: :test,
        timestamp: System.system_time(:millisecond)
      }
      
      quality_score = QualityMetrics.assess_response_quality(response_data)
      
      assert is_float(quality_score)
      assert quality_score >= 0.0
      assert quality_score <= 1.0
    end
    
    test "handles very long responses" do
      very_long_content = String.duplicate("This is a very long response. ", 1000)
      
      response_data = %{
        response: %{content: very_long_content},
        duration_ms: 1000,
        success: true,
        provider: :test,
        timestamp: System.system_time(:millisecond)
      }
      
      quality_score = QualityMetrics.assess_response_quality(response_data)
      
      assert is_float(quality_score)
      assert quality_score >= 0.0
      assert quality_score <= 1.0
    end
    
    test "handles malformed response structures" do
      malformed_responses = [
        %{not_a_response: "invalid"},
        %{response: %{not_content: "also invalid"}},
        %{response: 123},  # Non-string/map response
        %{}  # Empty map
      ]
      
      Enum.each(malformed_responses, fn response ->
        response_data = %{
          response: response,
          duration_ms: 1000,
          success: true,
          provider: :test,
          timestamp: System.system_time(:millisecond)
        }
        
        # Should not crash
        quality_score = QualityMetrics.assess_response_quality(response_data)
        
        assert is_float(quality_score)
        assert quality_score >= 0.0
        assert quality_score <= 1.0
      end)
    end
  end
  
  describe "specific quality metrics" do
    test "code syntax validation" do
      good_code = """
      ```elixir
      def valid_function(param) do
        case param do
          {:ok, value} -> value
          {:error, _} -> nil
        end
      end
      ```
      """
      
      bad_code = """
      ```elixir
      def invalid_function(( do
        case param do
          {:ok, value -> value
          {:error, _ -> nil
      end
      ```
      """
      
      good_quality = QualityMetrics.assess_code_quality(good_code)
      bad_quality = QualityMetrics.assess_code_quality(bad_code)
      
      # Good code should score higher than bad code
      assert good_quality >= bad_quality
    end
    
    test "technical terminology detection" do
      technical_content = "This function implements a recursive algorithm using tail call optimization."
      casual_content = "This thing does stuff with some kinda algorithm or whatever."
      
      technical_quality = QualityMetrics.assess_response_quality(%{
        response: %{content: technical_content},
        duration_ms: 1000,
        success: true,
        provider: :test,
        timestamp: System.system_time(:millisecond)
      })
      
      casual_quality = QualityMetrics.assess_response_quality(%{
        response: %{content: casual_content},
        duration_ms: 1000,
        success: true,
        provider: :test,
        timestamp: System.system_time(:millisecond)
      })
      
      # Technical content should generally score higher
      assert technical_quality >= casual_quality
    end
  end
end