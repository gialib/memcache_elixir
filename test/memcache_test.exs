defmodule MemcacheTest do
  use ExUnit.Case, async: false

  setup do
    flush_response = Memcache.flush()
    flush_response.status

    :ok
  end

  test "expires" do
    set_response = Memcache.set("hello", "world", expires: 3)

    assert set_response.status == :ok
    assert Memcache.get!("hello") == "world"

    Process.sleep(1000)
    assert Memcache.get!("hello") == "world"

    Process.sleep(1000)
    assert Memcache.get!("hello") == "world"

    Process.sleep(1000)
    assert Memcache.get!("hello") == nil
  end

  test "fetch!" do
    value = Memcache.fetch!("hello", fn ->
      "world"
    end)

    assert value == "world"

    value = Memcache.fetch!("hello", fn ->
      "world2"
    end)

    assert value == "world"
  end

  test "get key not found" do
    get_response = Memcache.get("key")
    assert get_response.status == :key_not_found
  end

  test "set key" do
    set_response = Memcache.set("key", "value")
    assert set_response.extras == ""
    assert set_response.status == :ok

    get_response = Memcache.get("key")
    assert get_response.cas == set_response.cas
    assert get_response.value == "value"
  end

  test "set key with cas" do
    set_response = Memcache.set("key", "value")
    cas = set_response.cas

    set_response = Memcache.set("key", "other value", cas: cas)
    assert set_response.status == :ok
    assert set_response.cas != cas

    set_response = Memcache.set("key", "yet another value", cas: 1_234_567)
    assert set_response.status == :key_exists
  end

  test "set key with expiry" do
    set_response = Memcache.set("key", "value", expires: 1000)
    assert set_response.status == :ok

    get_response = Memcache.get("key")
    assert get_response.status == :ok
    assert get_response.value == "value"
  end

  test "add key" do
    add_response = Memcache.add("key", "value")
    assert add_response.extras == ""
    assert add_response.status == :ok

    get_response = Memcache.get("key")
    assert get_response.cas == add_response.cas
    assert get_response.value == "value"

    # try add when already existing
    add_response = Memcache.add("key", "other value")
    assert add_response.status == :key_exists
  end

  test "replace key" do
    replace_response = Memcache.replace("key", "value")
    assert replace_response.status == :key_not_found

    set_response = Memcache.set("key", "value")
    assert set_response.status == :ok

    replace_response = Memcache.replace("key", "value")
    assert replace_response.status == :ok
    assert replace_response.cas != set_response.cas
  end

  test "increment key" do
    incr_response = Memcache.increment("key", 1)
    assert incr_response.status == :ok
    assert incr_response.value == 0

    incr_response = Memcache.increment("key", 1)
    assert incr_response.status == :ok
    assert incr_response.value == 1

    incr_response = Memcache.increment("key", 10)
    assert incr_response.status == :ok
    assert incr_response.value == 11
  end

  test "increment key with initial value" do
    incr_response = Memcache.increment("key", 10, initial_value: 100)
    assert incr_response.status == :ok
    assert incr_response.value == 100

    incr_response = Memcache.increment("key", 10)
    assert incr_response.status == :ok
    assert incr_response.value == 110
  end

  test "decrement key" do
    decr_response = Memcache.decrement("key", 10)
    assert decr_response.status == :ok
    assert decr_response.value == 0

    decr_response = Memcache.decrement("key", 10)
    assert decr_response.status == :ok
    assert decr_response.value == 0
  end

  test "decrement key with initial value" do
    decr_response = Memcache.decrement("key", 10, initial_value: 100)
    assert decr_response.status == :ok
    assert decr_response.value == 100

    decr_response = Memcache.decrement("key", 10)
    assert decr_response.status == :ok
    assert decr_response.value == 90
  end

  test "delete key" do
    delete_response = Memcache.delete("key")
    assert delete_response.status == :key_not_found

    set_response = Memcache.set("key", "value")
    assert set_response.status == :ok

    delete_response = Memcache.delete("key")
    assert delete_response.status == :ok

    get_response = Memcache.get("key")
    assert get_response.status == :key_not_found
  end

  test "multi get" do
    keys = ["test1", "test2", "test3"]
    [mget_response] = Memcache.mget(keys) |> Enum.into([])
    assert mget_response.status == :key_not_found

    set_response = Memcache.set("key1", "value1")
    assert set_response.status == :ok

    set_response = Memcache.set("key2", "value2")
    assert set_response.status == :ok

    keys = ["key1", "key2", "key3"]
    [response1, response2, response3] = Memcache.mget(keys) |> Enum.into([])
    assert response1.status == :ok
    assert response1.value == "value1"
    assert response2.status == :ok
    assert response2.value == "value2"
    assert response3.status == :key_not_found
  end

  test "multi set" do
    keyvals = [{"key1", "value1"}, {"key2", "value2"}]
    [mset_response] = Memcache.mset(keyvals) |> Enum.into([])
    assert mset_response.status == :ok

    get_response = Memcache.get("key1")
    assert get_response.status == :ok
    assert get_response.value == "value1"

    get_response = Memcache.get("key2")
    assert get_response.status == :ok
    assert get_response.value == "value2"
  end
end
