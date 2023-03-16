defmodule TimeFunction do
  @moduledoc """
  TimeFunction a = (T -> a)
  TimeFunction (TimeFunction a) = T1 -> T2 -> a
  """
  def force({:constant, a}), do: fn _ -> a end
  def force({:function, f}), do: fn t -> f.(t) end
  def map({:constant, a}, h), do: {:constant, h.(a)}
  def map({:function, f}, h), do: {:function, fn t -> h.(f.(t)) end}

  def pure(a), do: {:constant, a}
  def apply({:constant, f}, {:constant, a}), do: {:constant, f.(a)}
  def apply(cf, cx), do: {:function, fn t -> force(cf).(t).(force(cx).(t)) end}

  @doc """
  bind : TimeFunction a -> (a -> TimeFunction b) -> TimeFunction b
  """
  def bind({:constant, a}, h), do: h.(a)
  def bind({:function, f}, h), do: {:function, fn t -> h.(f.(t)).(t) end}

  def join({:constant, {:constant, a}}), do: {:constant, a}
  def join({:constant, {:function, f}}), do: {:function, f}

  def join({:function, f}),
    do:
      {:function,
       fn t ->
         case f.(t) do
           {:constant, a} -> a
           {:function, f2} -> f2.(t)
         end
       end}
end
