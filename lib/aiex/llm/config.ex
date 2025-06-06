defmodule Aiex.LLM.Config do
  @moduledoc """
  Configuration management for LLM adapters.

  Handles loading, validation, and encryption of API keys and other
  sensitive configuration data.
  """

  @type t :: %__MODULE__{
          provider: atom(),
          api_key: String.t() | nil,
          base_url: String.t() | nil,
          default_model: String.t(),
          max_tokens: pos_integer(),
          temperature: float(),
          timeout: pos_integer(),
          rate_limits: map(),
          encryption_key: binary() | nil
        }

  defstruct provider: :openai,
            api_key: nil,
            base_url: nil,
            default_model: "gpt-3.5-turbo",
            max_tokens: 4096,
            temperature: 0.7,
            timeout: 30_000,
            rate_limits: %{},
            encryption_key: nil

  @doc """
  Load configuration from various sources.
  """
  @spec load(keyword()) :: t()
  def load(opts \\ []) do
    %__MODULE__{}
    |> merge_env_config()
    |> merge_opts(opts)
    |> encrypt_sensitive_data()
  end

  @doc """
  Update existing configuration.
  """
  @spec update(t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def update(config, updates) do
    try do
      new_config =
        config
        |> merge_opts(updates)
        |> encrypt_sensitive_data()

      {:ok, new_config}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @doc """
  Get decrypted API key.
  """
  @spec get_api_key(t()) :: String.t() | nil
  def get_api_key(%__MODULE__{api_key: nil}), do: nil

  def get_api_key(%__MODULE__{api_key: encrypted_key, encryption_key: key}) when is_binary(key) do
    decrypt_data(encrypted_key, key)
  end

  def get_api_key(%__MODULE__{api_key: api_key}), do: api_key

  @doc """
  Validate configuration completeness.
  """
  @spec validate(t()) :: :ok | {:error, String.t()}
  def validate(config) do
    cond do
      is_nil(config.provider) ->
        {:error, "Provider must be specified"}

      is_nil(config.api_key) ->
        {:error, "API key must be specified"}

      config.max_tokens <= 0 ->
        {:error, "max_tokens must be positive"}

      config.temperature < 0 or config.temperature > 2 ->
        {:error, "temperature must be between 0 and 2"}

      config.timeout <= 0 ->
        {:error, "timeout must be positive"}

      true ->
        :ok
    end
  end

  @doc """
  Get provider-specific default configuration.
  """
  @spec provider_defaults(atom()) :: keyword()
  def provider_defaults(:openai) do
    [
      base_url: "https://api.openai.com/v1",
      default_model: "gpt-3.5-turbo",
      rate_limits: %{
        requests_per_minute: 60,
        tokens_per_minute: 90_000
      }
    ]
  end

  def provider_defaults(_), do: []

  # Private functions

  defp merge_env_config(config) do
    env_config =
      [
        provider: get_env_provider(),
        api_key: get_env_api_key(),
        base_url: System.get_env("AIEX_LLM_BASE_URL"),
        default_model: System.get_env("AIEX_LLM_DEFAULT_MODEL"),
        max_tokens: get_env_integer("AIEX_LLM_MAX_TOKENS"),
        temperature: get_env_float("AIEX_LLM_TEMPERATURE"),
        timeout: get_env_integer("AIEX_LLM_TIMEOUT")
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    merge_opts(config, env_config)
  end

  defp merge_opts(config, opts) do
    # First merge provider defaults
    provider = Keyword.get(opts, :provider, config.provider)
    defaults = provider_defaults(provider)

    # Then merge opts
    Enum.reduce(defaults ++ opts, config, fn {key, value}, acc ->
      if Map.has_key?(acc, key) do
        Map.put(acc, key, value)
      else
        acc
      end
    end)
  end

  defp encrypt_sensitive_data(config) do
    if config.api_key && !is_encrypted?(config.api_key) do
      key = get_or_generate_encryption_key()
      encrypted_key = encrypt_data(config.api_key, key)

      %{config | api_key: encrypted_key, encryption_key: key}
    else
      config
    end
  end

  defp get_env_provider do
    case System.get_env("AIEX_LLM_PROVIDER") do
      "openai" -> :openai
      "anthropic" -> :anthropic
      "google" -> :google
      nil -> nil
      other -> String.to_atom(other)
    end
  end

  defp get_env_api_key do
    System.get_env("OPENAI_API_KEY") ||
      System.get_env("ANTHROPIC_API_KEY") ||
      System.get_env("AIEX_LLM_API_KEY")
  end

  defp get_env_integer(key) do
    case System.get_env(key) do
      nil -> nil
      value -> String.to_integer(value)
    end
  rescue
    _ -> nil
  end

  defp get_env_float(key) do
    case System.get_env(key) do
      nil -> nil
      value -> String.to_float(value)
    end
  rescue
    _ -> nil
  end

  defp get_or_generate_encryption_key do
    # In production, this should come from a secure key management system
    # For now, we'll use a simple approach
    case System.get_env("AIEX_ENCRYPTION_KEY") do
      nil ->
        # Generate a random key (32 bytes for AES-256)
        :crypto.strong_rand_bytes(32)

      key_b64 ->
        Base.decode64!(key_b64)
    end
  end

  defp encrypt_data(data, key) do
    # 16 bytes for AES
    iv = :crypto.strong_rand_bytes(16)
    {_tag, ciphertext} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, data, "", true)

    # Prepend IV to ciphertext and encode
    (iv <> ciphertext) |> Base.encode64()
  end

  defp decrypt_data(encrypted_data, key) do
    encrypted_binary = Base.decode64!(encrypted_data)
    <<iv::binary-size(16), ciphertext::binary>> = encrypted_binary

    :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, "", false)
  end

  defp is_encrypted?(data) do
    # Simple heuristic: encrypted data will be base64 encoded
    # and longer than typical API keys
    case Base.decode64(data) do
      {:ok, _} when byte_size(data) > 100 -> true
      _ -> false
    end
  end
end
