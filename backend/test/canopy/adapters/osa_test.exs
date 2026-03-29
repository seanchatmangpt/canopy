defmodule Canopy.Adapters.OSATest do
  use ExUnit.Case, async: true
  alias Canopy.Adapters.OSA

  describe "adapter metadata" do
    test "type is osa" do
      assert OSA.type() == "osa"
    end

    test "default model is openai/gpt-oss-20b" do
      assert OSA.default_model() == "openai/gpt-oss-20b"
    end

    test "default provider is groq" do
      assert OSA.default_provider() == "groq"
    end
  end
end
