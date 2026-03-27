defmodule Canopy.Ontology.ServiceTest do
  use ExUnit.Case

  alias Canopy.Ontology.Service

  setup do
    # Clear cache before each test
    Service.clear_all_cache()
    :ok
  end

  describe "list_ontologies/1" do
    test "lists ontologies with pagination" do
      {:ok, ontologies, total, metadata} = Service.list_ontologies(limit: 50, offset: 0)

      assert is_list(ontologies)
      assert is_integer(total)
      assert metadata.cache_hit == false
      assert is_struct(metadata.retrieved_at, DateTime)
    end

    test "respects limit and offset parameters" do
      {:ok, _, _, metadata1} = Service.list_ontologies(limit: 10, offset: 0)
      {:ok, _, _, metadata2} = Service.list_ontologies(limit: 20, offset: 5)

      refute metadata1.cache_hit
      refute metadata2.cache_hit
    end

    test "caches results and returns cache_hit on second call" do
      {:ok, ontologies1, total1, metadata1} = Service.list_ontologies(limit: 50, offset: 0)
      refute metadata1.cache_hit

      {:ok, ontologies2, total2, metadata2} = Service.list_ontologies(limit: 50, offset: 0)
      assert metadata2.cache_hit

      assert ontologies1 == ontologies2
      assert total1 == total2
    end

    test "respects cache: false option" do
      {:ok, _, _, metadata1} = Service.list_ontologies(limit: 50, offset: 0, cache: true)
      refute metadata1.cache_hit

      {:ok, _, _, metadata2} = Service.list_ontologies(limit: 50, offset: 0, cache: false)
      refute metadata2.cache_hit
    end

    test "different pagination params don't share cache" do
      {:ok, _, _, m1} = Service.list_ontologies(limit: 10, offset: 0)
      {:ok, _, _, m2} = Service.list_ontologies(limit: 20, offset: 0)

      refute m1.cache_hit
      refute m2.cache_hit
    end
  end

  describe "get_ontology/2" do
    test "retrieves ontology details by id" do
      {:ok, ontology, metadata} = Service.get_ontology("fibo-core")

      assert is_map(ontology)
      assert metadata.cache_hit == false
      assert metadata.ontology_id == "fibo-core"
    end

    test "caches ontology and returns cache_hit on second call" do
      {:ok, ont1, m1} = Service.get_ontology("fibo-core")
      refute m1.cache_hit

      {:ok, ont2, m2} = Service.get_ontology("fibo-core")
      assert m2.cache_hit

      assert ont1 == ont2
    end

    test "respects cache: false option" do
      {:ok, _, m1} = Service.get_ontology("fibo-core", cache: true)
      refute m1.cache_hit

      {:ok, _, m2} = Service.get_ontology("fibo-core", cache: false)
      refute m2.cache_hit
    end

    test "returns error for unknown ontology" do
      {:error, _reason} = Service.get_ontology("unknown-ontology")
    end
  end

  describe "search/3" do
    test "searches for classes and properties" do
      {:ok, results, metadata} = Service.search("fibo-core", "agent")

      assert is_list(results)
      assert metadata.cache_hit == false
      assert metadata.query == "agent"
      assert metadata.ontology_id == "fibo-core"
    end

    test "caches search results" do
      {:ok, results1, m1} =
        Service.search("fibo-core", "agent", type: "class", limit: 20, offset: 0)

      refute m1.cache_hit

      {:ok, results2, m2} =
        Service.search("fibo-core", "agent", type: "class", limit: 20, offset: 0)

      assert m2.cache_hit
      assert results1 == results2
    end

    test "different searches don't share cache" do
      {:ok, _, m1} = Service.search("fibo-core", "agent")
      {:ok, _, m2} = Service.search("fibo-core", "entity")

      refute m1.cache_hit
      refute m2.cache_hit
    end

    test "respects search_type parameter" do
      {:ok, _, metadata} = Service.search("fibo-core", "agent", type: "class")

      assert is_map(metadata)
    end

    test "respects limit and offset in cache key" do
      {:ok, _, m1} = Service.search("fibo-core", "agent", limit: 10, offset: 0)
      {:ok, _, m2} = Service.search("fibo-core", "agent", limit: 20, offset: 0)

      refute m1.cache_hit
      refute m2.cache_hit
    end
  end

  describe "get_class/3" do
    test "retrieves class details by id" do
      {:ok, class_info, metadata} = Service.get_class("fibo-core", "Agent")

      assert is_map(class_info)
      assert metadata.cache_hit == false
      assert metadata.class_id == "Agent"
      assert metadata.ontology_id == "fibo-core"
    end

    test "caches class information" do
      {:ok, class1, m1} = Service.get_class("fibo-core", "Agent")
      refute m1.cache_hit

      {:ok, class2, m2} = Service.get_class("fibo-core", "Agent")
      assert m2.cache_hit

      assert class1 == class2
    end

    test "different classes don't share cache" do
      {:ok, _, m1} = Service.get_class("fibo-core", "Agent")
      {:ok, _, m2} = Service.get_class("fibo-core", "Entity")

      refute m1.cache_hit
      refute m2.cache_hit
    end
  end

  describe "get_statistics/1" do
    test "retrieves global statistics" do
      {:ok, stats, metadata} = Service.get_statistics()

      assert is_map(stats)
      assert metadata.cache_hit == false
    end

    test "caches statistics" do
      {:ok, stats1, m1} = Service.get_statistics()
      refute m1.cache_hit

      {:ok, stats2, m2} = Service.get_statistics()
      assert m2.cache_hit

      assert stats1 == stats2
    end

    test "respects cache: false option" do
      {:ok, _, m1} = Service.get_statistics(cache: true)
      refute m1.cache_hit

      {:ok, _, m2} = Service.get_statistics(cache: false)
      refute m2.cache_hit
    end
  end

  describe "reload_ontologies/0" do
    test "reloads ontologies and clears cache" do
      # Prime the cache
      {:ok, _, _, m1} = Service.list_ontologies()
      assert m1.cache_hit == false

      # Next call should hit cache
      {:ok, _, _, m2} = Service.list_ontologies()
      assert m2.cache_hit == true

      # Reload and clear cache
      :ok = Service.reload_ontologies()

      # Next call should miss cache
      {:ok, _, _, m3} = Service.list_ontologies()
      refute m3.cache_hit
    end
  end

  describe "cache_stats/0" do
    test "returns cache statistics" do
      stats = Service.cache_stats()

      assert is_integer(stats.hits)
      assert is_integer(stats.misses)
      assert is_integer(stats.total)
      assert is_float(stats.hit_rate)
    end

    test "tracks cache hits and misses" do
      initial_stats = Service.cache_stats()

      # Generate a cache miss
      Service.list_ontologies()
      stats_after_miss = Service.cache_stats()
      assert stats_after_miss.misses > initial_stats.misses

      # Generate a cache hit
      Service.list_ontologies()
      stats_after_hit = Service.cache_stats()
      assert stats_after_hit.hits > stats_after_miss.hits
    end

    test "calculates hit rate correctly" do
      Service.clear_all_cache()

      # 2 hits, 2 misses = 50% hit rate
      # miss
      Service.list_ontologies()
      # hit
      Service.list_ontologies()
      # miss
      Service.get_ontology("fibo-core")
      # hit
      Service.get_ontology("fibo-core")

      stats = Service.cache_stats()
      assert stats.total == 4
      assert stats.hits == 2
      assert stats.misses == 2
      assert stats.hit_rate == 0.5
    end
  end

  describe "clear_all_cache/0" do
    test "clears all cache entries" do
      # Prime cache with multiple entries
      Service.list_ontologies()
      Service.get_ontology("fibo-core")
      Service.search("fibo-core", "agent")

      # Verify cache is populated
      stats_before = Service.cache_stats()
      assert stats_before.misses == 3

      # Clear cache
      :ok = Service.clear_all_cache()

      # Reset stats and verify cache is cleared
      stats_after = Service.cache_stats()
      assert stats_after.hits == 0
      assert stats_after.misses == 0

      # Next calls should all miss
      Service.list_ontologies()
      Service.get_ontology("fibo-core")
      Service.search("fibo-core", "agent")

      final_stats = Service.cache_stats()
      assert final_stats.misses == 3
      assert final_stats.hits == 0
    end
  end

  describe "clear_ontology_cache/1" do
    test "clears cache for specific ontology" do
      # Prime cache
      Service.list_ontologies()
      Service.get_ontology("fibo-core")
      Service.get_ontology("prov-o")

      stats_before = Service.cache_stats()
      assert stats_before.hits == 0
      assert stats_before.misses == 3

      # Clear ontology cache
      :ok = Service.clear_ontology_cache("fibo-core")

      # Verify cache is cleared
      stats_after = Service.cache_stats()
      assert stats_after.hits == 0
      assert stats_after.misses == 0
    end
  end

  describe "concurrency and GenServer behavior" do
    test "concurrent calls are handled safely" do
      # Spawn 5 concurrent requests
      pids =
        Enum.map(1..5, fn _i ->
          spawn_link(fn ->
            Service.list_ontologies()
          end)
        end)

      # Wait for all to complete
      Enum.each(pids, &Process.monitor/1)

      # Verify stats are consistent
      stats = Service.cache_stats()
      assert stats.total >= 1
    end

    test "cache stats increments are atomic" do
      initial = Service.cache_stats()

      Enum.each(1..10, fn _i ->
        Service.list_ontologies()
      end)

      final = Service.cache_stats()
      assert final.total == initial.total + 10
    end
  end

  describe "metadata consistency" do
    test "metadata contains required fields for all operations" do
      {:ok, _, _, m1} = Service.list_ontologies()
      assert Map.has_key?(m1, :cache_hit)
      assert Map.has_key?(m1, :retrieved_at)
      assert Map.has_key?(m1, :count)
      assert Map.has_key?(m1, :total)

      {:ok, _, m2} = Service.get_ontology("fibo-core")
      assert Map.has_key?(m2, :cache_hit)
      assert Map.has_key?(m2, :retrieved_at)

      {:ok, _, m3} = Service.search("fibo-core", "agent")
      assert Map.has_key?(m3, :cache_hit)
      assert Map.has_key?(m3, :retrieved_at)
      assert Map.has_key?(m3, :query)

      {:ok, _, m4} = Service.get_class("fibo-core", "Agent")
      assert Map.has_key?(m4, :cache_hit)
      assert Map.has_key?(m4, :retrieved_at)

      {:ok, _, m5} = Service.get_statistics()
      assert Map.has_key?(m5, :cache_hit)
      assert Map.has_key?(m5, :retrieved_at)
    end

    test "retrieved_at is a valid DateTime" do
      {:ok, _, _, metadata} = Service.list_ontologies()

      assert is_struct(metadata.retrieved_at, DateTime)
      # Verify it's recent (within last 5 seconds)
      now = DateTime.utc_now()
      diff = DateTime.diff(now, metadata.retrieved_at, :second)
      assert diff >= 0 and diff <= 5
    end
  end
end
