# Elixir to Lean 4 Translation Patterns

This reference provides idiomatic mappings between dynamic Elixir constructs and strict, dependently typed Lean 4 definitions.

---

## 1. Atoms, Enums & Tagged Tuples

### Elixir
```elixir
# Status atoms
:pending | :approved | :rejected

# Tagged result tuples
{:ok, value} | {:error, :not_found} | {:error, {:invalid_state, current}}
```

### Lean 4
```lean
inductive Status where
  | pending
  | approved
  | rejected
  deriving Repr, DecidableEq

inductive AppError where
  | notFound
  | invalidState (current : Status)
  deriving Repr, DecidableEq

-- Standard result type
abbrev Result (α : Type) := Except AppError α
```

---

## 2. Structs & Records

### Elixir
```elixir
defmodule Order do
  defstruct [:id, :amount, :status, items: []]
end
```

### Lean 4
```lean
structure Order where
  id : String
  amount : Nat
  status : Status
  items : List String := []
  deriving Repr, DecidableEq
```

---

## 3. Guard Clauses & Invariant Constraints

In Elixir, guards like `when amount > 0` are dynamically checked at runtime. In Lean 4, preconditions can either be modeled via dependent subtypes (`Subtype` / `{ x // P x }`) or as explicit hypothesis arguments.

### Elixir
```elixir
def withdraw(%Account{balance: bal} = acc, amount) when amount > 0 and bal >= amount do
  {:ok, %{acc | balance: bal - amount}}
end

def withdraw(_acc, _amount), do: {:error, :insufficient_funds_or_invalid_amount}
```

### Lean 4
```lean
structure Account where
  balance : Nat
  deriving Repr, DecidableEq

-- Option A: Explicit result with validation
def withdraw (acc : Account) (amount : Nat) : Except String Account :=
  if amount == 0 then
    .error "Amount must be positive"
  else if acc.balance >= amount then
    .ok { acc with balance := acc.balance - amount }
  else
    .error "Insufficient funds"

-- Option B: Proof-carrying precondition
def withdrawVerified (acc : Account) (amount : Nat) (hPos : amount > 0) (hBal : acc.balance >= amount) : Account :=
  { acc with balance := acc.balance - amount }
```

---

## 4. Recursive Functions & Termination Measures

Elixir relies on tail recursion. Lean 4 requires proof that every recursive function terminates, typically by showing that an argument shrinks on every recursive step.

### Elixir
```elixir
def countdown(0), do: :ok
def countdown(n) when n > 0 do
  countdown(n - 1)
end
```

### Lean 4
```lean
def countdown : Nat → Unit
  | 0 => ()
  | n + 1 => countdown n
-- Lean automatically proves termination by structural recursion on Nat.

-- For complex recursion with explicit measure:
def customLoop (acc : List Nat) (remaining : Nat) : List Nat :=
  if h : remaining = 0 then
    acc
  else
    have : remaining - 1 < remaining := Nat.sub_lt (Nat.pos_of_ne_zero h) (by decide)
    customLoop (remaining :: acc) (remaining - 1)
termination_by remaining
```

---

## 5. GenServer / Process State Modeling

Do not model process mailboxes, PIDs, or message passing. Instead, model the state machine defined by `handle_call/3` and `handle_cast/2`.

### Elixir
```elixir
defmodule CounterServer do
  use GenServer

  def handle_call(:get, _from, count), do: {:reply, count, count}
  def handle_call({:add, n}, _from, count) when n > 0, do: {:reply, :ok, count + n}
  def handle_call({:reset, max}, _from, _count) when max > 0, do: {:reply, :ok, 0}
end
```

### Lean 4
```lean
inductive CounterCmd where
  | get
  | add (n : Nat)
  | reset (max : Nat)

structure CounterState where
  count : Nat
  deriving Repr, DecidableEq

inductive CounterReply where
  | countVal (n : Nat)
  | ok
  | error (msg : String)
  deriving Repr, DecidableEq

def handleCall (cmd : CounterCmd) (s : CounterState) : CounterReply × CounterState :=
  match cmd with
  | .get => (.countVal s.count, s)
  | .add n =>
    if n > 0 then
      (.ok, { count := s.count + n })
    else
      (.error "add value must be > 0", s)
  | .reset max =>
    if max > 0 then
      (.ok, { count := 0 })
    else
      (.error "max must be > 0", s)
```

---

## 6. Proving Invariant Preservation

Once modeled as a transition system, state invariants are stated as inductive properties:

```lean
-- Invariant: Count is never negative (natural numbers) and satisfies upper bound if configured
def Invariant (s : CounterState) : Prop :=
  s.count >= 0

theorem handleCall_preserves_invariant (cmd : CounterCmd) (s : CounterState) (h : Invariant s) :
  Invariant (handleCall cmd s).2 := by
  cases cmd <;> simp [handleCall]
  · exact h
  · split <;> simp [Invariant]
  · split <;> simp [Invariant]
```
