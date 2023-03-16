defmodule Future do
  @moduledoc """
  type Future a
  force :: Future a -> (BoundedTime, a)
  """

  @doc """
  force : Future a -> (BoundedTime, a)
  """
  def force(f), do: f

  @doc """
  map : Future a -> (a -> b) -> Future b

  ## Examples
  iex> Future.pure(5) |> Future.map(fn x -> x + 1 end) |> Future.force()
  {:lower_bound, 6}
  """
  def map({t, a}, f), do: {t, f.(a)}

  @doc """
  pure : a -> Future a

  ## Examples
  iex> Future.pure(5) |> Future.force()
  {:lower_bound, 5}
  """
  def pure(a), do: {BoundedTime.empty(), a}

  @doc """
  ap : Future (a -> b) -> Future a -> Future b

  ## Examples
  iex> Future.pure(fn x -> fn y -> x + y end end) |> Future.ap(Future.pure(5)) |> Future.ap({1000, 2}) |> Future.force()
  {1000, 7}
  """
  def ap({t1, f}, {t2, a}) do
    {BoundedTime.max(t1, t2), f.(a)}
  end

  @doc """
  bind : Future a -> (a -> Future b) -> Future b

  ## Examples
  iex> Future.pure(5) |> Future.bind(fn x -> {1000, x + 2} end) |> Future.force()
  {1000, 7}
  """
  def bind({t1, a}, f) do
    {t2, b} = f.(a)
    {BoundedTime.max(t1, t2), b}
  end

  @doc """
  join : Future (Future a) -> Future a

  ## Examples
  iex> Future.pure(Future.pure(5)) |> Future.join() |> Future.force()
  {:lower_bound, 5}
  """
  def join({t1, {t2, a}}) do
    {BoundedTime.max(t1, t2), a}
  end

  @doc """
  append : Future a -> Future a -> Future a

  ## Examples
  iex> Future.pure(5) |> Future.append({1000, 3}) |> Future.force()
  {:lower_bound, 5}

  iex> Future.pure(5) |> Future.append(Future.empty()) |> Future.force()
  {:lower_bound, 5}

  iex> Future.empty() |> Future.append(Future.pure(5)) |> Future.force()
  {:lower_bound, 5}
  """
  def append({t1, a}, {t2, b}) do
    {BoundedTime.min(t1, t2), if(BoundedTime.compare(t1, t2) == :gt, do: b, else: a)}
  end

  @doc """
  empty : Future a

  ## Examples
  iex> Future.empty() |> Future.force()
  {:upper_bound, :bottom}
  """
  def empty(), do: {:upper_bound, :bottom}
end
