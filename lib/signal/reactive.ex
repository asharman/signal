defmodule Signal.Reactive do
  @moduledoc """
  type Reactive a
    = Stepper a (Event a)

  # Observation
  at : Reactive a -> (Time -> a)
  within : Reactive a -> [{a, Time, Time}]
  """

  # type t(a) :: {:stepper, a, [Future.t(a)]}
  def at({:stepper, initial_value, event}),
    do: fn t -> List.last(Event.before(event, t), initial_value) end

  def at({:switcher, r, e}),
    do: fn t -> Event.before(e, t) |> List.last(r) |> at() |> apply([t]) end

  def occurances({:stepper, initial_value, events}),
    do: [{:initial, initial_value} | Event.occurances(events)]

  def within({:stepper, v, e}, time_start, time_end) do
    Event.occurances(e)
    |> Enum.filter(fn {t, _} -> BoundedTime.compare(time_end, t) == :gt end)
    |> Enum.reduce([{v, time_start, time_end}], fn {t, a}, [{prev_a, prev_t_start, _} | rest] ->
      cond do
        BoundedTime.compare(t, time_start) != :gt ->
          [{a, time_start, time_end}]

        BoundedTime.compare(t, prev_t_start) == :eq ->
          [{a, t, time_end} | rest]

        true ->
          [{a, t, time_end} | [{prev_a, prev_t_start, t} | rest]]
      end
    end)
    |> Enum.reverse()
  end

  def initial_value({:stepper, value, _}), do: value
  def event({:stepper, _, event}), do: event
  def event({:switcher, _, event}), do: Future.map(event, &join/1)

  @doc """
  stepper : a -> Event a -> Reactive a

  ## Examples
  iex> Signal.Reactive.pure(5)
  ...> |> Signal.Reactive.at()
  ...> |> then(fn f -> f.(15000000) end)
  5

  iex> Signal.Reactive.stepper(5, Event.from_list([{1000, 7}, {3000, 9}]))
  ...> |> Signal.Reactive.at()
  ...> |> then(fn f -> f.(2000) end)
  7

  iex> Signal.Reactive.stepper(5, Event.from_list([{1000, 7}, {3000, 9}]))
  ...> |> Signal.Reactive.at()
  ...> |> then(fn f -> f.(4000) end)
  9
  """
  def stepper(initial_value, events), do: {:stepper, initial_value, events}
  # def switcher(r, e), do: join(stepper(r, e)) |> IO.inspect(label: "POST JOIN")
  def switcher(r, e), do: join(stepper(r, e))

  @doc """
  map : Reactive a -> (a -> b) -> Reactive b

  ## Examples
  iex> Signal.Reactive.pure(5)
  ...> |> Signal.Reactive.map(fn x -> x + 1 end)
  ...> |> Signal.Reactive.at()
  ...> |> then(fn f -> f.(15000000) end)
  6

  iex> Signal.Reactive.stepper(5, Event.from_list([{1000, 7}, {3000, 9}]))
  ...> |> Signal.Reactive.map(fn x -> x + 1 end)
  ...> |> Signal.Reactive.at()
  ...> |> then(fn f -> f.(2000) end)
  8

  iex> Signal.Reactive.stepper(5, Event.from_list([{1000, 7}, {3000, 9}]))
  ...> |> Signal.Reactive.map(fn x -> x + 1 end)
  ...> |> Signal.Reactive.at()
  ...> |> then(fn f -> f.(4000) end)
  10
  """
  def map(:bottom, _f), do: :bottom

  def map({:stepper, initial_value, events}, f),
    do: {:stepper, f.(initial_value), Event.map(events, f)}

  @doc """
  pure : a -> Reactive a

  apply : Reactive (a -> b) -> Reactive a -> Reactive b

  ## Examples
  iex> Signal.Reactive.pure(5) |> Signal.Reactive.at() |> then(fn f -> f.(5000) end)
  5

  iex> Signal.Reactive.pure(fn x -> x + 1 end)
  ...> |> Signal.Reactive.ap(Signal.Reactive.pure(5))
  ...> |> Signal.Reactive.at()
  ...> |> then(fn f -> f.(4000) end)
  6

  iex> Signal.Reactive.pure(fn x -> fn y -> x + y end end)
  ...> |> Signal.Reactive.ap(Signal.Reactive.pure(5))
  ...> |> Signal.Reactive.ap(Signal.Reactive.pure(5))
  ...> |> Signal.Reactive.at()
  ...> |> then(fn f -> f.(5000) end)
  10

  iex> Signal.Reactive.stepper(fn x -> x end, Event.from_list([{5000, fn x -> x + 1 end}]))
  ...> |> Signal.Reactive.ap(Signal.Reactive.pure(5))
  ...> |> Signal.Reactive.at()
  ...> |> then(fn f -> f.(4000) end)
  5

  iex> Signal.Reactive.stepper(fn x -> x end, Event.from_list([{5000, fn x -> x + 1 end}]))
  ...> |> Signal.Reactive.ap(Signal.Reactive.pure(5))
  ...> |> Signal.Reactive.at()
  ...> |> then(fn f -> f.(6000) end)
  6

  iex> Signal.Reactive.stepper(fn x -> x end, Event.from_list([{5000, fn x -> x + 1 end}]))
  ...> |> Signal.Reactive.ap(Signal.Reactive.stepper(5, Event.from_list([{5500, 6}])))
  ...> |> Signal.Reactive.at()
  ...> |> then(fn f -> f.(6000) end)
  7

  iex> Signal.Reactive.stepper(fn x -> x end, Event.from_list([{5000, fn x -> x + 1 end}]))
  ...> |> Signal.Reactive.ap(Signal.Reactive.stepper(5, Event.from_list([{7000, 6}])))
  ...> |> Signal.Reactive.at()
  ...> |> then(fn f -> f.(6000) end)
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

  def combine(f, rs) when is_list(rs), do: Enum.reduce(rs, pure(curry(f)), &ap(&2, &1))

  defp curry(fun) do
    {_, arity} = :erlang.fun_info(fun, :arity)
    curry(fun, arity, [])
  end

  defp curry(fun, 0, arguments), do: apply(fun, Enum.reverse(arguments))

  defp curry(fun, arity, arguments) do
    fn arg -> curry(fun, arity - 1, [arg | arguments]) end
  end

  @doc """
  bind : Reactive a -> (a -> Reactive b) -> Reactive b

  ## Examples
  iex> Signal.Reactive.pure(5)
  ...> |> Signal.Reactive.bind(fn x -> Signal.Reactive.pure(x + 2) end)
  ...> |> Signal.Reactive.at()
  ...> |> then(fn f -> f.(7000) end)
  7

  iex> Signal.Reactive.pure(Signal.Reactive.pure(5))
  ...> |> Signal.Reactive.join()
  ...> |> Signal.Reactive.at()
  ...> |> then(fn f -> f.(7000) end)
  5
  """
  def bind(a, f) do
    # IO.inspect(a, label: "BIND")
    joinR(map(a, f))
  end

  def join(rr), do: bind(rr, fn x -> x end)

  defp joinR({:stepper, r, {:upper_bound, _}}), do: r
  # def join({:stepper, {:stepper, a, {:upper_bound, _}}, e}), do: {:stepper, a, Future.join(e)}

  defp joinR({:stepper, {:stepper, a, inner_e}, outer_e} = rr) do
    # IO.inspect(rr, label: "NESTED REACTIVE")

    future =
      Future.append(
        Future.map(inner_e, fn new_value ->
          if new_value == :bottom do
            new_value
          else
            # IO.inspect(inner_e, label: "INNER EVENT")
            # IO.inspect(new_value, label: "NEW INNER VALUE")
            switcher(new_value, outer_e)
          end
        end),
        Future.map(outer_e, fn next_reactive ->
          # IO.inspect(next_reactive, label: "NEXT REACTIVE VALUE SECOND BRANCH")
          join(next_reactive)
          # |> IO.inspect(label: "AFTER INNER JOIN IN SECOND BRANCH")
        end)
      )

    # |> IO.inspect(label: "FUTURE APPEND")

    {:stepper, a, future}
  end
end
