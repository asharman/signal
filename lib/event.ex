defmodule Event do
  @moduledoc """
  type Event a
    = Ev (Future (Reactive a))
  """

  alias Signal.Reactive

  def occurances({:upper_bound, _}), do: []
  def occurances({t, {:stepper, a, es}}), do: [{t, a} | occurances(es)]
  def from_list([]), do: empty()
  def from_list([{t, a} | e]), do: {t, {:stepper, a, from_list(e)}}

  @doc """
  instance Monoid (Event a) where
  empty : Event a
  append : Event a -> Event a -> Event a

  ## Examples
  iex> Event.append(Event.empty, Event.from_list([{1000, :value}]))
  ...> |> Event.occurances()
  [{1000, :value}]

  iex> Event.append(Event.from_list([{1000, :value}]), Event.empty)
  ...> |> Event.occurances()
  [{1000, :value}]

  iex> Event.from_list([{1000, :value_a}, {2750, :c}, {5000, :value_e}])
  iex> |> Event.append(Event.from_list([{3000, :value_d}]))
  iex> |> Event.append(Event.from_list([{2500, :value_b}]))
  ...> |> Event.occurances()
  [{1000, :value_a}, {2500, :value_b}, {2750, :c}, {3000, :value_d}, {5000, :value_e}]

  iex> Event.append(Event.from_list([{3000, :value_b}]), Event.from_list([{1000, :value_a}, {5000, :value_c}]))
  ...> |> Event.occurances()
  [{1000, :value_a}, {3000, :value_b}, {5000, :value_c}]
  """
  def empty(), do: Future.empty()
  def append(event_a, event_b), do: merge(event_a, event_b)

  def merge(a, b) do
    Future.append(
      Future.map(a, fn reactive_a ->
        in_future(fn e -> merge(e, b) end, reactive_a)
      end),
      Future.map(b, fn reactive_b ->
        in_future(fn e -> merge(a, e) end, reactive_b)
      end)
    )
  end

  defp in_future(f, {:stepper, r, u}), do: {:stepper, r, f.(u)}
  defp in_future(_f, :bottom), do: :bottom

  @doc """
  instance Functor (Event a) where
  map : Event a -> (a -> b) -> Event b

  ## Examples
  iex> Event.map(Event.from_list([{5000, 1}, {6000, 2}, {7000, 3}]), fn x -> x + 1 end)
  ...> |> Event.occurances()
  [{5000, 2}, {6000, 3}, {7000, 4}]
  """
  def map(event, f), do: Future.map(event, &Reactive.map(&1, f))

  def pure(value), do: Future.pure(Reactive.pure(value))

  @doc """
  instance Monad (Event a) where
  bind : Event a -> (a -> Event b) -> Event b
  join : Event (Event a) -> Event a

  ## Examples
  # iex> Event.from_list([ {1000, :value_a} ])
  # ...> |> Event.bind(fn _ -> Event.from_list([{500, :value_b}, {750, :value_d}, {1500, :value_c}]) end)
  # ...> |> Event.occurances()
  # [{1000, :value_b}, {1000, :value_d}, {1500, :value_c}]

  iex> Event.from_list([
  ...>  {1000, Event.from_list([{500, :value_a}, {1500, :value_b}, {2000, :value_c}])},
  ...>  {1500, Event.from_list([{500, :value_d}, {1000, :value_e}, {1500, :value_f}, {3000, :value_g}])},
  ...>  {2000, Event.from_list([{500, :value_h}])}
  ...> ])
  ...> |> Event.join()
  ...> |> Event.occurances()
  [{1000, :value_a}, {1500, :value_b}, {1500, :value_d}, {1500, :value_e}, {1500, :value_f}, {2000, :value_c}, {2000, :value_h}, {3000, :value_g}]
  """
  def bind(event, f), do: join(map(event, f))
  def join({:upper_bound, _}), do: Event.empty()

  def join(event) do
    IO.inspect(event, label: "EVENT")

    Future.bind(event, fn {:stepper, e, es} ->
      IO.inspect(e, label: "E")
      IO.inspect(es, label: "ES")
      append(e, join(es))
    end)
  end

  def before(event, t),
    do:
      event
      |> occurances()
      |> Enum.filter(fn {time, _} -> BoundedTime.compare(time, t) != :gt end)
      |> Enum.map(fn {_, a} -> a end)

  @doc """
  ## Examples
  iex> Event.from_list([{1000, :value_a}])
  ...> |> Event.foldl([], fn u, acc -> [u | acc] end)
  [{1000, :value_a}]

  iex> Event.from_list([{1000, :value_a}, {2000, :value_b}])
  ...> |> Event.foldl(
  ...>      {Event.from_list([{1500, :value_c}]), nil},
  ...>        fn binder ->
  ...>          u, acc -> {binder, Future.bind(binder, fn _ -> u end)}
  ...>          u, acc -> {binder, {t, {:stepper, a, Future.bind(binder, fn _ -> u end)}}}
  ...>        end)
  [{1000, :value_a}]
  """
  def foldl({:upper_bound, _}, acc, _), do: acc

  def foldl({t, {:stepper, a, e}}, acc, f) do
    foldl(e, f.({t, a}, acc), f)
  end
end
