defmodule Signal do
  @moduledoc """
  Documentation for `Signal`.
  """

  alias Signal.Reactive

  def sample(signal, t), do: at(signal).(t)

  def sample_within(signal, start_time, end_time, sample_rate) do
    Reactive.within(signal, start_time, end_time)
    |> Enum.reverse()
    |> Enum.reduce([{sample(signal, end_time), end_time}], fn
      {{:constant, a}, s, e}, acc ->
        case rem(e, sample_rate) do
          0 ->
            [{a, s}, {a, e - sample_rate} | acc]

          r ->
            [{a, s}, {a, e - r} | acc]
        end

      {{:function, f}, s, e}, acc ->
        recursive_sample(f, sample_rate, s, e - rem(e, sample_rate), acc)
    end)
  end

  defp recursive_sample(f, rate, s, sample_time, acc) do
    if sample_time <= s do
      [{f.(s), s} | acc]
    else
      recursive_sample(f, rate, s, sample_time - rate, [{f.(sample_time), sample_time} | acc])
    end
  end

  defp at(signal), do: fn t -> TimeFunction.force(Reactive.at(signal).(t)).(t) end

  def switcher(s, e), do: Reactive.switcher(s, e)

  def time(), do: Reactive.of({:function, fn t -> t end})

  @doc """
  map : Signal a -> (a -> b) -> Signal b

  ## Examples
  iex> Signal.pure(5)
  ...> |> Signal.map(fn x -> x + 1 end)
  ...> |> Signal.sample(1000)
  6
  """
  def map(signal, f), do: Reactive.map(signal, &TimeFunction.map(&1, f))

  @doc """
  pure : a -> Signal a

  ## Examples
  iex> Signal.pure(5) |> Signal.sample(5000)
  5
  """
  def of(a), do: Reactive.of(TimeFunction.pure(a))

  @doc """
  apply : Signal (a -> b) -> Signal a -> Signal b

  ## Examples
  iex> Signal.pure(fn x -> x + 1 end)
  ...> |> Signal.ap(Signal.pure(5))
  ...> |> Signal.sample(10000000)
  6

  iex> Signal.pure(fn x -> fn y -> x + y end end)
  ...> |> Signal.ap(Signal.pure(5))
  ...> |> Signal.ap(Signal.pure(5))
  ...> |> Signal.sample(10000000)
  10
  """
  def ap(f, a),
    do:
      Reactive.of(fn function -> fn value -> TimeFunction.apply(function, value) end end)
      |> Reactive.ap(f)
      |> Reactive.ap(a)

  def combine(f, signals) when is_list(signals),
    do: Enum.reduce(signals, of(curry(f)), &ap(&2, &1))

  defp curry(fun) do
    {_, arity} = :erlang.fun_info(fun, :arity)
    curry(fun, arity, [])
  end

  defp curry(fun, 0, arguments), do: apply(fun, Enum.reverse(arguments))

  defp curry(fun, arity, arguments) do
    fn arg -> curry(fun, arity - 1, [arg | arguments]) end
  end
end
