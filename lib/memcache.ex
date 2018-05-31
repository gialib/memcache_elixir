defmodule Memcache do
  @moduledoc """
  Binary protocol client for Memcached server.
  """

  use Application

  alias Memcache.Serialization.Opcode
  alias Memcache.Worker

  @default_pool_size 5
  @default_pool_max_overflow 20
  @default_host '127.0.0.1'
  @default_port 11211
  @default_auth_method :none
  @default_username ""
  @default_password ""
  @default_timeout 5000
  @default_socket_opts [:binary, {:nodelay, true}, {:active, false}, {:packet, :raw}]
  @default_type :json
  @default_namespace Application.get_env(:memcache, :namespace, "default")

  @type key :: binary
  @type value :: any
  @type opts :: Keyword.t()

  defmodule Response do
    defstruct key: "", value: "", extras: "", status: nil, cas: 0, data_type: nil

    @type t :: %Response{
            key: binary,
            value: any,
            extras: binary,
            status: atom,
            cas: non_neg_integer,
            data_type: non_neg_integer
          }
  end

  defmodule Request do
    defstruct opcode: nil, key: "", value: "", extras: "", cas: 0

    @type t :: %Request{
            opcode: atom,
            key: binary,
            value: any,
            extras: binary,
            cas: non_neg_integer
          }
  end

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    pool_args = [
      name: {:local, Memcache.Pool},
      worker_module: Memcache.Worker,
      size: Application.get_env(:memcache, :pool_size, @default_pool_size),
      max_overflow: Application.get_env(:memcache, :pool_max_overflow, @default_pool_max_overflow)
    ]

    worker_args = [
      host: Application.get_env(:memcache, :host, @default_host),
      port: Application.get_env(:memcache, :port, @default_port),
      auth_method: Application.get_env(:memcache, :auth_method, @default_auth_method),
      username: Application.get_env(:memcache, :username, @default_username),
      password: Application.get_env(:memcache, :password, @default_password),
      opts: Application.get_env(:memcache, :socket_opts, @default_socket_opts),
      timeout: Application.get_env(:memcache, :timeout, @default_timeout)
    ]

    poolboy_sup = :poolboy.child_spec(Memcache.Pool.Supervisor, pool_args, worker_args)

    children = [
      poolboy_sup
    ]

    opts = [strategy: :one_for_one, name: Memcache.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  Gets `value` for given `key`.
  """
  @spec get(key, opts) :: Response.t()
  def get(key, opts \\ []) do
    key = _encode_key(key)
    request = %Request{opcode: :get, key: key}
    [response] = multi_request([request], false, opts)

    response |> _decode_response(opts)
  end

  def get!(key, opts \\ []) do
    case get(key, opts) do
      %Memcache.Response{status: :ok, value: value} -> value
      _ -> nil
    end
  end

  defp _decode_response(%Memcache.Response{status: :ok} = response, opts) do
    transcoder = opts |> Keyword.get(:type, @default_type) |> _get_transcoder()
    value = if response.value, do: transcoder.decode_value(response.value)
    response |> Map.put(:value, value)
  end

  defp _decode_response(response, _opts), do: response

  @doc """
  Gets values for multiple `keys` with a single pipelined operation.
  """
  @spec mget(Enumerable.t(), opts) :: Stream.t()
  def mget(keys, opts \\ []) do
    keys
    |> Enum.map(fn key -> _encode_key(key) end)
    |> Enum.map(&%Request{opcode: :getk, key: &1})
    |> multi_request(true, opts)
    |> Enum.map(fn response ->
      _decode_response(response, opts)
    end)
  end

  @doc """
  Sets `value` for given `key`.
  """
  @spec set(key, value, opts) :: Response.t()
  def set(key, value, opts \\ []), do: _store(:set, key, value, opts)

  def fetch(key, missing_fn, opts \\ []) when is_binary(key) and is_function(missing_fn) do
    response = get(key, opts)

    case response.status do
      :key_not_found ->
        set(key, missing_fn.(), opts)

      _ ->
        response
    end
  end

  def fetch!(key, missing_fn, opts \\ []) do
    case fetch(key, missing_fn, opts) do
      %Memcache.Response{status: :ok, value: value} -> value
      _ -> nil
    end
  end

  @doc """
  Sets multiple `values` with a single pipelined operation. Value
  needs to be a tuple of `key` and `value`.
  """
  @spec mset(Enumerable.t(), opts) :: Stream.t()
  def mset(keyvalues, opts \\ []) do
    requests =
      keyvalues
      |> Enum.map(fn {key, value} ->
        _store_request(:set, key, value, [])
      end)

    multi_request(requests, true, opts)
  end

  @doc """
  Sets `value` for given `key` only if it does not already exist.
  """
  @spec add(key, value, opts) :: Response.t()
  def add(key, value, opts \\ []), do: _store(:add, key, value, opts)

  @doc """
  Sets `value`for given `key` only if it already exists.
  """
  @spec replace(key, value, opts) :: Response.t()
  def replace(key, value, opts \\ []), do: _store(:replace, key, value, opts)

  @doc """
  Deletes the `value` for the given `key`.
  """
  @spec delete(key) :: Response.t()
  def delete(key) do
    key = _encode_key(key)
    request = %Request{opcode: :delete, key: key}
    [response] = multi_request([request], false)

    response
  end

  @doc """
  Increments a counter on given `key`.
  """
  @spec increment(key, pos_integer, opts) :: Response.t()
  def increment(key, amount, opts \\ []), do: _incr_decr(:increment, key, amount, opts)

  @doc """
  Decrements a counter on given `key`.
  """
  @spec decrement(key, pos_integer, opts) :: Response.t()
  def decrement(key, amount, opts \\ []), do: _incr_decr(:decrement, key, amount, opts)

  @doc """
  Flushes the cache.
  """
  @spec flush(opts) :: Response.t()
  def flush(opts \\ []) do
    expires = Keyword.get(opts, :expires, 0)
    extras = <<expires::size(32)>>

    request = %Request{opcode: :flush, extras: extras}
    [response] = multi_request([request], false, opts)

    response
  end

  @doc """
  Returns the current memcached version.
  """
  @spec version() :: Response.t()
  def version() do
    request = %Request{opcode: :version}
    [response] = multi_request([request], false)
    response
  end

  ## private api

  defp multi_request(requests, return_stream, _opts \\ []) do
    stream =
      Stream.resource(
        fn ->
          worker = :poolboy.checkout(Memcache.Pool)
          :ok = _multi_request(requests, worker)
          {worker, :cont}
        end,
        fn
          {worker, :cont} = acc ->
            # stream responses
            receive do
              {:response, {:ok, header, key, value, extras}} ->
                if extras != "" and Opcode.get?(header.opcode) do
                  <<type_flag::size(32)>> = extras

                  case Memcache.Transcoder.decode_value(value, type_flag) do
                    {:error, _error} ->
                      %Response{
                        status: :transcode_error,
                        cas: header.cas,
                        key: key,
                        value: "Transcode error",
                        extras: extras
                      }

                    value ->
                      %Response{
                        status: header.status,
                        cas: header.cas,
                        key: key,
                        value: value,
                        extras: extras,
                        data_type: type_flag
                      }
                  end
                end

                if Opcode.quiet?(header.opcode) do
                  {[
                     %Response{
                       status: header.status,
                       cas: header.cas,
                       key: key,
                       value: value,
                       extras: extras
                     }
                   ], acc}
                else
                  {[
                     %Response{
                       status: header.status,
                       cas: header.cas,
                       key: key,
                       value: value,
                       extras: extras
                     }
                   ], {worker, :halt}}
                end

              {:response, {:error, reason}} ->
                if reason == :timeout do
                  :ok = Worker.close(worker)
                end

                {[%Response{status: reason, value: "#{reason}"}], {worker, :halt}}
            end

          {_worker, :halt} = acc ->
            {:halt, acc}
        end,
        fn {worker, _} ->
          :poolboy.checkin(Memcache.Pool, worker)
        end
      )

    if return_stream do
      stream
    else
      stream |> Enum.into([])
    end
  end

  defp _multi_request([request], worker) do
    Worker.cast(worker, self(), request, request.opcode)
  end

  defp _multi_request([request | requests], worker) do
    Worker.cast(worker, self(), request, Opcode.to_quiet(request.opcode))
    _multi_request(requests, worker)
  end

  defp _store(opcode, key, value, opts) do
    request = _store_request(opcode, key, value, opts)
    [response] = multi_request([request], false, opts)

    response |> Map.put(:value, value)
  end

  defp _store_request(opcode, key, value, opts) do
    key = _encode_key(key)
    expires = Keyword.get(opts, :expires, 0)
    cas = Keyword.get(opts, :cas, 0)
    transcoder = opts |> Keyword.get(:type, @default_type) |> _get_transcoder()

    {value, flags} = transcoder.encode_value(value)
    extras = <<flags::size(32), expires::size(32)>>

    %Request{opcode: opcode, key: key, value: value, extras: extras, cas: cas}
  end

  defp _get_transcoder(:json), do: Memcache.Transcoder.Json
  defp _get_transcoder(:raw), do: Memcache.Transcoder.Raw
  defp _get_transcoder(:erlang), do: Memcache.Transcoder.Erlang
  defp _get_transcoder(_), do: Memcache.Transcoder

  defp _incr_decr(opcode, key, amount, opts) do
    key = _encode_key(key)
    initial_value = Keyword.get(opts, :initial_value, 0)
    expires = Keyword.get(opts, :expires, 0)

    extras = <<amount::size(64), initial_value::size(64), expires::size(32)>>

    request = %Request{opcode: opcode, key: key, extras: extras}
    [response] = multi_request([request], false, opts)

    if response.status == :ok do
      <<value::unsigned-integer-size(64)>> = response.value
      %{response | value: value}
    else
      response
    end
  end

  defp _encode_key(key) do
    "#{@default_namespace}@#{key}"
  end
end
