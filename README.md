## Installing

You can install `Memcache` by adding it as a dependecy to your
project's `mix.exs` file:

```elixir
defp deps do
  [
    {:memcache, "~> 0.1.2"}
  ]
end
```

## Examples

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

### Fetch

```elixir
value = Memcache.fetch!("hello", fn ->
  "world"
end)

# value == "world"

value = Memcache.fetch!("hello", fn ->
  "world2"
end)

# value == "world"
```

### Config like this

```elixir
config :memcache,
  host: "127.0.0.1",
  port: 11211,
  auth_method: :none,
  username: "",
  password: "",
  pool_size: 10,
  pool_max_overflow: 20,
  namespace: "default"
```
