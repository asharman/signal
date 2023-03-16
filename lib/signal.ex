defmodule Signal do
  @moduledoc """
  Documentation for `Signal`.
  """

  def sample(signal, t), do: at(signal).(t)
  defp at(signal), do: fn t -> TimeFunction.force(Reactive.at(signal).(t)).(t) end

  def time(), do: Reactive.pure({:function, fn t -> t end})

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
  def pure(a), do: Reactive.pure(TimeFunction.pure(a))

  @doc """
  apply : Signal (a -> b) -> Signal a -> Signal b

  ## Examples
  iex> Signal.pure(fn x -> x + 1 end)
  ...> |> Signal.apply(Signal.pure(5))
  ...> |> Signal.sample(10000000)
  6

  iex> Signal.pure(fn x -> fn y -> x + y end end)
  ...> |> Signal.apply(Signal.pure(5))
  ...> |> Signal.apply(Signal.pure(5))
  ...> |> Signal.sample(10000000)
  10
  """
  def apply(f, a),
    do:
      Reactive.pure(fn function -> fn value -> TimeFunction.apply(function, value) end end)
      |> Reactive.ap(f)
      |> Reactive.ap(a)
end
