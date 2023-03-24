defmodule Signal.Future do
  @typep a :: term()
  @typep b :: term()

  @type time_value(a) :: {BoundedTime.t(), a}
  @opaque future(a) :: %__MODULE__{value: (() -> time_value(a))}

  defstruct [:value]

  @spec from_time_value_pair(time_value(a)) :: future(a)
  def from_time_value_pair(pair), do: %__MODULE__{value: fn -> pair end}

  @spec map(future(a), (a -> b)) :: future(b)
  def map(future, f),
    do: %__MODULE__{
      value: fn ->
        {t, a} = force(future)

        {t, f.(a)}
      end
    }

  @spec pure(a) :: future(a)
  def pure(value), do: %__MODULE__{value: fn -> {:lower_bound, value} end}

  @spec ap(future((a -> b)), future(a)) :: future(b)
  def ap(future_f, future_x),
    do: %__MODULE__{
      value: fn ->
        {t1, f} = force(future_f)
        {t2, x} = force(future_x)

        {BoundedTime.max(t1, t2), f.(x)}
      end
    }

  @spec bind(future(a), (a -> future(b))) :: future(b)
  def bind(future, f),
    do: %__MODULE__{
      value: fn ->
        {t1, a} = force(future)
        {t2, b} = force(f.(a))

        {BoundedTime.max(t1, t2), b}
      end
    }

  @spec join(future(future(a))) :: future(a)
  def join(future), do: bind(future, fn u -> u end)

  @spec empty() :: future(a)
  def empty(), do: %__MODULE__{value: fn -> {:upper_bound, :bottom} end}

  @spec append(future(a), future(a)) :: future(a)
  def append(future_a, future_b),
    do: %__MODULE__{
      value: fn ->
        {t1, a} = force(future_a)
        {t2, b} = force(future_b)

        {BoundedTime.min(t1, t2), if(BoundedTime.compare(t1, t2) == :gt, do: b, else: a)}
      end
    }

  @spec force(future(a)) :: time_value(a)
  def force(%__MODULE__{value: function}), do: function.()
end
