defmodule BoundedTime do
  @opaque t() :: :lower_bound | number() | :upper_bound
  defguard is_upper(value) when value === :upper_bound

  @spec empty() :: t()
  def empty(), do: :lower_bound

  def max(t1, t2), do: if(compare(t1, t2) == :lt, do: t2, else: t1)
  def min(t1, t2), do: if(compare(t1, t2) == :gt, do: t2, else: t1)

  # Time Is Bounded by +/- infinity
  def compare(:lower_bound, _), do: :lt
  def compare(_, :lower_bound), do: :gt
  def compare(:upper_bound, _), do: :gt
  def compare(_, :upper_bound), do: :lt

  def compare(t1, t2) do
    cond do
      t1 < t2 ->
        :lt

      t1 == t2 ->
        :eq

      t1 > t2 ->
        :gt
    end
  end
end
