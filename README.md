## Installing

You can install `Memcache` by adding it as a dependecy to your
project's `mix.exs` file:

```elixir
defp deps do
  [
    {:memcache, "~> 0.1.0"}
  ]
end
```

Examples
--------

### Get value for a key:

```elixir
response = Memcache.get("key")
case response.status do
  :ok ->
    {:ok, response.value}
  status ->
    {:error, status}
end
```
