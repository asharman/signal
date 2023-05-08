defmodule Signal.Reactive do
  alias Signal.BoundedTime

  @typep a :: term()
  @typep b :: term()

  @opaque occurance(a) :: {BoundedTime.t(), a}
  @opaque reactive(a) :: %__MODULE__{value: a, next_value: Enumerable.t()}

  defstruct [:value, :next_value]

  @spec initial_value(reactive(a)) :: a
  def initial_value(%__MODULE__{value: v}), do: v

  def at(%__MODULE__{value: a, next_value: v}),
    do: fn t ->
      Enum.reduce_while(v, a, fn {ts, value}, acc ->
        if BoundedTime.compare(t, ts) != :lt do
          {:cont, value}
        else
          {:halt, acc}
        end
      end)
    end

  @spec occurances(reactive(a)) :: Enumerable.t()
  def occurances(%__MODULE__{next_value: values}), do: values

  def within(%__MODULE__{value: v, next_value: futures}, time_start, time_end) do
    futures
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

  @spec of(a) :: reactive(a)
  def of(a), do: %__MODULE__{value: a, next_value: []}

  @spec stepper(a, [occurance(a)]) :: reactive(a)
  def stepper(initial_value, event), do: %__MODULE__{value: initial_value, next_value: event}

  @spec switcher(reactive(a), [occurance(reactive(a))]) :: reactive(a)
  def switcher(r, e), do: join(stepper(r, e))

  @spec map(reactive(a), (a -> b)) :: reactive(b)
  def map(%__MODULE__{value: a, next_value: e}, f),
    do: %__MODULE__{value: f.(a), next_value: Stream.map(e, fn {t, v} -> {t, f.(v)} end)}

  @spec ap(reactive((a -> b)), reactive(a)) :: reactive(b)
  def ap(%__MODULE__{} = reactive_f, %__MODULE__{} = reactive_a) do
    %__MODULE__{
      value: reactive_f.value.(reactive_a.value),
      next_value:
        Stream.unfold(
          %{
            functions: reactive_f.next_value,
            values: reactive_a.next_value,
            cached_function: reactive_f.value,
            cached_value: reactive_a.value
          },
          fn
            %{functions: fs, values: as, cached_function: f, cached_value: a} = acc ->
              next_f = Enum.at(fs, 0)
              next_a = Enum.at(as, 0)

              case {next_f, next_a} do
                {nil, nil} ->
                  nil

                {{t, next_f}, nil} ->
                  {{t, next_f.(a)}, %{acc | functions: Enum.drop(fs, 1), cached_function: next_f}}

                {nil, {t, next_a}} ->
                  {{t, f.(next_a)}, %{acc | values: Enum.drop(as, 1), cached_value: next_a}}

                {{t1, next_f}, {t2, next_a}} ->
                  if BoundedTime.compare(t1, t2) === :gt do
                    {{t2, f.(next_a)}, %{acc | values: Enum.drop(as, 1), cached_value: next_a}}
                  else
                    {{t1, next_f.(a)},
                     %{acc | functions: Enum.drop(fs, 1), cached_function: next_f}}
                  end
              end
          end
        )
    }
  end

  def combine(f, rs) when is_list(rs), do: Enum.reduce(rs, of(curry(f)), &ap(&2, &1))

  defp curry(fun) do
    {_, arity} = :erlang.fun_info(fun, :arity)
    curry(fun, arity, [])
  end

  defp curry(fun, 0, arguments), do: apply(fun, Enum.reverse(arguments))

  defp curry(fun, arity, arguments) do
    fn arg -> curry(fun, arity - 1, [arg | arguments]) end
  end

  def join(%__MODULE__{value: initial_reactive, next_value: next_reactives}) do
    %__MODULE__{
      value: initial_reactive.value,
      next_value:
        Stream.unfold(
          %{
            current_time: BoundedTime.empty(),
            current: initial_reactive.next_value,
            next_reactives: next_reactives
          },
          fn %{current_time: current_time, current: current, next_reactives: next} ->
            next_current = Enum.at(current, 0)
            next_reactive = Enum.at(next, 0)

            case {next_current, next_reactive} do
              {nil, nil} ->
                nil

              {{t, v}, nil} ->
                {{BoundedTime.max(t, current_time), v},
                 %{
                   current_time: BoundedTime.max(t, current_time),
                   current: Enum.drop(current, 1),
                   next_reactives: next
                 }}

              {nil, {t, next_reactive}} ->
                {{BoundedTime.max(t, current_time), next_reactive.value},
                 %{
                   current_time: BoundedTime.max(t, current_time),
                   current: next_reactive.next_value,
                   next_reactives: Enum.drop(next, 1)
                 }}

              {{t1, v}, {t2, next_reactive}} ->
                if BoundedTime.compare(t1, t2) === :gt do
                  {{BoundedTime.max(t2, current_time), next_reactive.value},
                   %{
                     current_time: BoundedTime.max(t2, current_time),
                     current: next_reactive.next_value,
                     next_reactives: Enum.drop(next, 1)
                   }}
                else
                  {{BoundedTime.max(t1, current_time), v},
                   %{
                     current_time: BoundedTime.max(t1, current_time),
                     current: Enum.drop(current, 1),
                     next_reactives: next
                   }}
                end
            end
          end
        )
    }
  end
end
