defmodule Aiex.AI.Distributed.QualityMetrics do
  @moduledoc """
  Automated response quality assessment for AI responses.
  
  Provides various metrics to evaluate response quality including:
  - Content quality analysis
  - Response completeness
  - Code syntax validation (for code responses)
  - Response coherence and relevance
  """
  
  require Logger
  
  @type response_data :: %{
    response: any(),
    duration_ms: integer(),
    success: boolean(),
    provider: atom(),
    timestamp: integer()
  }
  
  @type quality_score :: float()
  
  @doc """
  Assess overall quality of an AI response.
  
  Returns a score between 0.0 and 1.0, where 1.0 is the highest quality.
  """
  @spec assess_response_quality(response_data()) :: quality_score()
  def assess_response_quality(response_data) do
    if not response_data.success do
      0.0
    else
      response = response_data.response
      
      metrics = %{
        completeness: assess_completeness(response),
        relevance: assess_relevance(response),
        clarity: assess_clarity(response),
        accuracy: assess_accuracy(response),
        code_quality: assess_code_quality(response),
        response_time: assess_response_time(response_data.duration_ms),
        format_quality: assess_format_quality(response)
      }
      
      calculate_weighted_score(metrics)
    end
  end
  
  @doc """
  Assess completeness of response (does it fully address the request).
  """
  def assess_completeness(response) do
    content = extract_content(response)
    
    cond do
      String.length(content) < 10 -> 0.1  # Very short responses
      String.length(content) < 50 -> 0.4  # Short responses
      String.length(content) < 200 -> 0.7 # Medium responses
      true -> 0.9  # Comprehensive responses
    end
  end
  
  @doc """
  Assess relevance of response to the likely request.
  """
  def assess_relevance(response) do
    content = extract_content(response)
    
    # Basic heuristics for relevance
    relevance_indicators = [
      has_code_when_expected?(content),
      has_explanation_structure?(content),
      has_reasonable_length?(content),
      lacks_irrelevant_content?(content)
    ]
    
    positive_indicators = Enum.count(relevance_indicators, & &1)
    positive_indicators / length(relevance_indicators)
  end
  
  @doc """
  Assess clarity and readability of response.
  """
  def assess_clarity(response) do
    content = extract_content(response)
    
    clarity_factors = %{
      sentence_structure: assess_sentence_structure(content),
      paragraph_organization: assess_paragraph_organization(content),
      technical_clarity: assess_technical_clarity(content),
      formatting: assess_formatting_clarity(content)
    }
    
    # Weighted average of clarity factors
    clarity_factors.sentence_structure * 0.3 +
    clarity_factors.paragraph_organization * 0.2 +
    clarity_factors.technical_clarity * 0.3 +
    clarity_factors.formatting * 0.2
  end
  
  @doc """
  Assess likely accuracy of response (heuristic-based).
  """
  def assess_accuracy(response) do
    content = extract_content(response)
    
    # Heuristic accuracy assessment
    accuracy_signals = [
      has_specific_details?(content),
      lacks_contradictions?(content),
      has_proper_terminology?(content),
      has_reasonable_scope?(content)
    ]
    
    positive_signals = Enum.count(accuracy_signals, & &1)
    positive_signals / length(accuracy_signals)
  end
  
  @doc """
  Assess code quality if response contains code.
  """
  def assess_code_quality(response) do
    content = extract_content(response)
    
    if contains_code?(content) do
      code_blocks = extract_code_blocks(content)
      
      if Enum.empty?(code_blocks) do
        0.5  # Some code detected but not properly formatted
      else
        code_scores = Enum.map(code_blocks, &assess_single_code_block/1)
        Enum.sum(code_scores) / length(code_scores)
      end
    else
      1.0  # No code expected, so full marks
    end
  end
  
  @doc """
  Assess response time quality (faster is generally better).
  """
  def assess_response_time(duration_ms) do
    cond do
      duration_ms < 1000 -> 1.0      # Very fast
      duration_ms < 3000 -> 0.9      # Fast
      duration_ms < 8000 -> 0.7      # Moderate
      duration_ms < 15000 -> 0.5     # Slow
      duration_ms < 30000 -> 0.3     # Very slow
      true -> 0.1                    # Extremely slow
    end
  end
  
  @doc """
  Assess format quality (markdown, structure, etc.).
  """
  def assess_format_quality(response) do
    content = extract_content(response)
    
    format_factors = [
      has_proper_markdown?(content),
      has_good_structure?(content),
      has_appropriate_headings?(content),
      has_proper_code_formatting?(content)
    ]
    
    positive_factors = Enum.count(format_factors, & &1)
    positive_factors / length(format_factors)
  end
  
  @doc """
  Compare two responses and return quality difference.
  """
  def compare_responses(response1, response2) do
    quality1 = assess_response_quality(response1)
    quality2 = assess_response_quality(response2)
    
    %{
      quality1: quality1,
      quality2: quality2,
      difference: quality1 - quality2,
      better_response: if(quality1 > quality2, do: :response1, else: :response2)
    }
  end
  
  @doc """
  Batch assess multiple responses.
  """
  def assess_multiple_responses(responses) do
    Enum.map(responses, fn response ->
      quality = assess_response_quality(response)
      Map.put(response, :quality_score, quality)
    end)
    |> Enum.sort_by(& &1.quality_score, :desc)
  end
  
  # Private Helper Functions
  
  defp extract_content(response) do
    case response do
      %{content: content} when is_binary(content) -> content
      %{"content" => content} when is_binary(content) -> content
      binary when is_binary(binary) -> binary
      _ -> inspect(response)
    end
  end
  
  defp calculate_weighted_score(metrics) do
    # Weighted scoring based on importance
    weights = %{
      completeness: 0.25,
      relevance: 0.20,
      clarity: 0.15,
      accuracy: 0.20,
      code_quality: 0.10,
      response_time: 0.05,
      format_quality: 0.05
    }
    
    Enum.reduce(metrics, 0.0, fn {metric, score}, acc ->
      weight = Map.get(weights, metric, 0.0)
      acc + (score * weight)
    end)
  end
  
  # Content Analysis Helpers
  
  defp has_code_when_expected?(content) do
    # Simple heuristic: if content mentions programming concepts, expect code
    programming_keywords = ["function", "def ", "class ", "import", "return", "variable", "method"]
    
    has_keywords = Enum.any?(programming_keywords, fn keyword ->
      String.contains?(String.downcase(content), keyword)
    end)
    
    if has_keywords do
      contains_code?(content)
    else
      true  # No code expected
    end
  end
  
  defp has_explanation_structure?(content) do
    # Check for explanatory structure
    structure_indicators = [
      String.contains?(content, "because"),
      String.contains?(content, "this means"),
      String.contains?(content, "for example"),
      String.contains?(content, "however"),
      String.contains?(content, "therefore")
    ]
    
    Enum.count(structure_indicators, & &1) >= 1
  end
  
  defp has_reasonable_length?(content) do
    length = String.length(content)
    length >= 20 and length <= 5000  # Reasonable bounds
  end
  
  defp lacks_irrelevant_content?(content) do
    # Check for common irrelevant patterns
    irrelevant_patterns = [
      "I cannot",
      "I don't know",
      "I'm not sure",
      "As an AI"
    ]
    
    not Enum.any?(irrelevant_patterns, fn pattern ->
      String.contains?(content, pattern)
    end)
  end
  
  defp assess_sentence_structure(content) do
    sentences = String.split(content, ~r/[.!?]+/)
    
    if length(sentences) < 2 do
      0.5
    else
      avg_length = Enum.sum(Enum.map(sentences, &String.length/1)) / length(sentences)
      
      cond do
        avg_length < 10 -> 0.3   # Too short
        avg_length < 30 -> 0.6   # Short but okay
        avg_length < 100 -> 1.0  # Good length
        avg_length < 200 -> 0.8  # A bit long
        true -> 0.4              # Too long
      end
    end
  end
  
  defp assess_paragraph_organization(content) do
    paragraphs = String.split(content, ~r/\n\s*\n/)
    
    cond do
      length(paragraphs) == 1 -> 0.6  # Single paragraph
      length(paragraphs) <= 3 -> 0.8  # Good organization
      length(paragraphs) <= 6 -> 1.0  # Excellent organization
      true -> 0.7                     # Many paragraphs
    end
  end
  
  defp assess_technical_clarity(content) do
    # Check for technical clarity indicators
    clarity_indicators = [
      String.contains?(content, ":"),      # Explanations
      String.contains?(content, "->"),     # Arrows/relationships
      String.contains?(content, "```"),    # Code blocks
      String.contains?(content, "*"),      # Emphasis
      String.contains?(content, "-")       # Lists
    ]
    
    positive_count = Enum.count(clarity_indicators, & &1)
    min(positive_count / 3, 1.0)
  end
  
  defp assess_formatting_clarity(content) do
    if has_proper_markdown?(content) do
      0.9
    else
      0.6
    end
  end
  
  defp has_specific_details?(content) do
    # Look for specific technical details
    detail_indicators = [
      String.contains?(content, "function"),
      String.contains?(content, "method"),
      String.contains?(content, "parameter"),
      String.contains?(content, "return"),
      String.contains?(content, "variable")
    ]
    
    Enum.count(detail_indicators, & &1) >= 1
  end
  
  defp lacks_contradictions?(content) do
    # Simple contradiction detection
    contradiction_patterns = [
      {" not ", " is "},
      {" cannot ", " can "},
      {" never ", " always "}
    ]
    
    not Enum.any?(contradiction_patterns, fn {neg, pos} ->
      String.contains?(content, neg) and String.contains?(content, pos)
    end)
  end
  
  defp has_proper_terminology?(content) do
    # Check for appropriate technical terminology
    # For now, just ensure it's not too colloquial
    colloquial_terms = ["stuff", "things", "whatever", "kinda", "sorta"]
    
    not Enum.any?(colloquial_terms, fn term ->
      String.contains?(String.downcase(content), term)
    end)
  end
  
  defp has_reasonable_scope?(content) do
    # Ensure response doesn't claim to do impossible things
    overreaching_claims = [
      "will definitely",
      "always works",
      "never fails",
      "perfect solution"
    ]
    
    not Enum.any?(overreaching_claims, fn claim ->
      String.contains?(String.downcase(content), claim)
    end)
  end
  
  defp contains_code?(content) do
    String.contains?(content, "```") or
    String.contains?(content, "def ") or
    String.contains?(content, "function") or
    Regex.match?(~r/\b[a-zA-Z_][a-zA-Z0-9_]*\s*\(/, content)
  end
  
  defp extract_code_blocks(content) do
    # Extract markdown code blocks
    Regex.scan(~r/```[a-z]*\n(.*?)\n```/s, content, capture: :all_but_first)
    |> Enum.map(fn [code] -> String.trim(code) end)
    |> Enum.reject(&(String.length(&1) == 0))
  end
  
  defp assess_single_code_block(code) do
    quality_factors = [
      has_proper_indentation?(code),
      has_reasonable_variable_names?(code),
      has_proper_syntax_structure?(code),
      lacks_obvious_errors?(code)
    ]
    
    positive_factors = Enum.count(quality_factors, & &1)
    positive_factors / length(quality_factors)
  end
  
  defp has_proper_indentation?(code) do
    lines = String.split(code, "\n")
    
    # Check if indentation is consistent
    indented_lines = Enum.filter(lines, fn line ->
      String.starts_with?(line, "  ") or String.starts_with?(line, "\t")
    end)
    
    if Enum.empty?(indented_lines) do
      true  # No indentation needed
    else
      # Check for consistent indentation style
      spaces_used = Enum.any?(indented_lines, &String.starts_with?(&1, "  "))
      tabs_used = Enum.any?(indented_lines, &String.starts_with?(&1, "\t"))
      
      not (spaces_used and tabs_used)  # Consistent if not mixing
    end
  end
  
  defp has_reasonable_variable_names?(code) do
    # Extract potential variable names
    variable_matches = Regex.scan(~r/\b([a-z_][a-z0-9_]*)\s*[=:]/i, code, capture: :all_but_first)
    variable_names = Enum.map(variable_matches, fn [name] -> name end)
    
    if Enum.empty?(variable_names) do
      true  # No variables to judge
    else
      # Check if most variables have reasonable names
      reasonable_names = Enum.count(variable_names, fn name ->
        String.length(name) > 1 and not String.match?(name, ~r/^[a-z]$/)
      end)
      
      reasonable_names / length(variable_names) > 0.5
    end
  end
  
  defp has_proper_syntax_structure?(code) do
    # Basic syntax structure checks
    structure_indicators = [
      balanced_parentheses?(code),
      balanced_brackets?(code),
      balanced_braces?(code)
    ]
    
    Enum.all?(structure_indicators)
  end
  
  defp lacks_obvious_errors?(code) do
    # Check for common syntax errors
    error_patterns = [
      ~r/\(\s*\)/,          # Empty parentheses in wrong context
      ~r/def\s*\(/,         # Missing function name
      ~r/=\s*=\s*=/,        # Triple equals (common mistake)
      ~r/;;/                # Double semicolon
    ]
    
    not Enum.any?(error_patterns, fn pattern ->
      String.match?(code, pattern)
    end)
  end
  
  defp balanced_parentheses?(code) do
    count_chars(code, "(") == count_chars(code, ")")
  end
  
  defp balanced_brackets?(code) do
    count_chars(code, "[") == count_chars(code, "]")
  end
  
  defp balanced_braces?(code) do
    count_chars(code, "{") == count_chars(code, "}")
  end
  
  defp count_chars(string, char) do
    string
    |> String.graphemes()
    |> Enum.count(&(&1 == char))
  end
  
  defp has_proper_markdown?(content) do
    markdown_indicators = [
      String.contains?(content, "```"),    # Code blocks
      String.contains?(content, "**"),     # Bold
      String.contains?(content, "*"),      # Italic or lists
      String.contains?(content, "#"),      # Headers
      String.contains?(content, "-")       # Lists
    ]
    
    Enum.count(markdown_indicators, & &1) >= 2
  end
  
  defp has_good_structure?(content) do
    # Check for good overall structure
    has_introduction = String.length(content) > 100
    has_conclusion = String.ends_with?(String.trim(content), [".", "!", "```"])
    has_sections = String.contains?(content, "\n\n")
    
    [has_introduction, has_conclusion, has_sections]
    |> Enum.count(& &1) >= 2
  end
  
  defp has_appropriate_headings?(content) do
    heading_count = length(Regex.scan(~r/^#+\s/m, content))
    
    cond do
      String.length(content) < 200 -> heading_count == 0  # Short content doesn't need headings
      String.length(content) < 500 -> heading_count <= 2  # Medium content, few headings
      true -> heading_count >= 1 and heading_count <= 5   # Long content needs some structure
    end
  end
  
  defp has_proper_code_formatting?(content) do
    if contains_code?(content) do
      # If code is present, it should be in code blocks
      code_blocks = length(Regex.scan(~r/```/, content))
      inline_code = length(Regex.scan(~r/`[^`]+`/, content))
      
      code_blocks > 0 or inline_code > 0
    else
      true  # No code to format
    end
  end
end