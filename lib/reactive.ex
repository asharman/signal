defmodule Reactive do
  @moduledoc """
  type Reactive a
    = Stepper a (Event a)
    | Apply (Reactive (a -> b)) (Reactive a)
    | Bind (Reactive a) (a -> Reactive b)

  # Observation
  at : Reactive a -> (BoundedTime -> a)
  """

  # type t(a) :: {:stepper, a, [Future.t(a)]}
  def at({:stepper, initial_value, event}),
    do: fn t -> List.last(Event.before(event, t), initial_value) end

  def at({:apply, f, a}), do: fn t -> at(f).(t).(at(a).(t)) end
  def at({:bind, a, f}), do: fn t -> at(f.(at(a).(t))).(t) end

  def occurances({:stepper, initial_value, events}),
    do: [{:lower_bound, initial_value} | Event.occurances(events)]

  @doc """
  stepper : a -> Event a -> Reactive a

  ## Examples
  iex> Reactive.stepper(5, Event.empty())
  ...> |> Reactive.at()
  ...> |> apply([15000000])
  5

  iex> Reactive.stepper(5, Event.from_list([{1000, 7}, {3000, 9}]))
  ...> |> Reactive.at()
  ...> |> apply([2000])
  7

  iex> Reactive.stepper(5, Event.from_list([{1000, 7}, {3000, 9}]))
  ...> |> Reactive.at()
  ...> |> apply([4000])
  9
  """
  def stepper(initial_value, events), do: {:stepper, initial_value, events}

  @doc """
  map : Reactive a -> (a -> b) -> Reactive b

  ## Examples
  iex> Reactive.stepper(5, Event.empty())
  ...> |> Reactive.map(fn x -> x + 1 end)
  ...> |> Reactive.at()
  ...> |> apply([15000000])
  6

  iex> Reactive.stepper(5, Event.from_list([{1000, 7}, {3000, 9}]))
  ...> |> Reactive.map(fn x -> x + 1 end)
  ...> |> Reactive.at()
  ...> |> apply([2000])
  8

  iex> Reactive.stepper(5, Event.from_list([{1000, 7}, {3000, 9}]))
  ...> |> Reactive.map(fn x -> x + 1 end)
  ...> |> Reactive.at()
  ...> |> apply([4000])
  10
  """
  def map(:bottom, _f), do: :bottom

  def map({:stepper, initial_value, events}, f),
    do: {:stepper, f.(initial_value), Event.map(events, f)}

  @doc """
  pure : a -> Reactive a

  apply : Reactive (a -> b) -> Reactive a -> Reactive b

  ## Examples
  iex> Reactive.pure(5) |> Reactive.at() |> apply([9000])
  5

  iex> Reactive.stepper(fn x -> x + 1 end, Event.empty())
  ...> |> Reactive.ap(Reactive.pure(5))
  ...> |> Reactive.at()
  ...> |> apply([4000])
  6

  iex> Reactive.pure(fn x -> fn y -> x + y end end)
  ...> |> Reactive.ap(Reactive.pure(5))
  ...> |> Reactive.ap(Reactive.pure(5))
  ...> |> Reactive.at()
  ...> |> apply([5000])
  10

  iex> Reactive.stepper(fn x -> x end, Event.from_list([{5000, fn x -> x + 1 end}]))
  ...> |> Reactive.ap(Reactive.pure(5))
  ...> |> Reactive.at()
  ...> |> apply([4000])
  5

  iex> Reactive.stepper(fn x -> x end, Event.from_list([{5000, fn x -> x + 1 end}]))
  ...> |> Reactive.ap(Reactive.pure(5))
  ...> |> Reactive.at()
  ...> |> apply([6000])
  6

  iex> Reactive.stepper(fn x -> x end, Event.from_list([{5000, fn x -> x + 1 end}]))
  ...> |> Reactive.ap(Reactive.stepper(5, Event.from_list([{5500, 6}])))
  ...> |> Reactive.at()
  ...> |> apply([6000])
  7

  iex> Reactive.stepper(fn x -> x end, Event.from_list([{5000, fn x -> x + 1 end}]))
  ...> |> Reactive.ap(Reactive.stepper(5, Event.from_list([{7000, 6}])))
  ...> |> Reactive.at()
  ...> |> apply([6000])
  6
  """
  def pure(a), do: {:stepper, a, Event.empty()}

  def ap({:stepper, function, {:upper_bound, _}}, a), do: map(a, function)
  def ap(function, {:stepper, a, {:upper_bound, _}}), do: map(function, fn f -> f.(a) end)

  def ap({:stepper, initial_f, event_f} = f, {:stepper, initial_a, event_a} = a) do
    {:stepper, initial_f.(initial_a),
     Future.append(
       Future.map(event_f, fn new_function -> ap(new_function, a) end),
       Future.map(event_a, fn new_value -> ap(f, new_value) end)
     )}
  end

  @doc """
  bind : Reactive a -> (a -> Reactive b) -> Reactive b

  ## Examples
  iex> Reactive.pure(5)
  ...> |> Reactive.bind(fn x -> Reactive.pure(x + 2) end)
  ...> |> Reactive.at()
  ...> |> apply([7000])
  7

  iex> Reactive.pure(Reactive.pure(5))
  ...> |> Reactive.join()
  ...> |> Reactive.at()
  ...> |> apply([7000])
  5
  """
  def bind(a, f), do: join(map(a, f))

  def join({:stepper, r, {:upper_bound, _}}), do: r

  def join({:stepper, {:stepper, a, inner_e}, outer_e}) do
    future =
      Future.append(
        Future.map(inner_e, fn new_value -> {:switcher, new_value, outer_e} end),
        Future.map(outer_e, &join/1)
      )

    {:stepper, a, future}
  end
end
