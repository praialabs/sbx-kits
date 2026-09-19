# Example Walkthrough: Order FSM Formalization

This example illustrates how formalizing an Elixir Finite State Machine (FSM) in Lean 4 exposes an invariant violation, generates a reproducer ExUnit test, and proves the subsequent fix.

---

## 1. Original Elixir Code (`lib/order_fsm.ex`)

```elixir
defmodule OrderFSM do
  @type state :: :created | :paid | :shipped | :cancelled

  defstruct [:id, :total_cents, :paid_cents, state: :created]

  def apply_payment(%OrderFSM{state: :created} = order, amount) when amount > 0 do
    new_paid = order.paid_cents + amount
    new_state = if new_paid >= order.total_cents, do: :paid, else: :created
    {:ok, %{order | paid_cents: new_paid, state: new_state}}
  end

  def cancel(%OrderFSM{state: state} = order) when state in [:created, :paid] do
    # Intended logic: Can cancel before shipment, refunds handled elsewhere
    {:ok, %{order | state: :cancelled}}
  end

  # BUG: Delivery can be triggered if state is :paid
  def ship(%OrderFSM{state: :paid} = order) do
    {:ok, %{order | state: :shipped}}
  end

  def ship(_order), do: {:error, :cannot_ship}
end
```

---

## 2. Lean 4 Formalization (`formalization/OrderFSM.lean`)

```lean
inductive OrderState where
  | created
  | paid
  | shipped
  | cancelled
  deriving Repr, DecidableEq

structure Order where
  id : Nat
  totalCents : Nat
  paidCents : Nat
  state : OrderState
  deriving Repr, DecidableEq

inductive Event where
  | pay (amount : Nat)
  | cancel
  | ship
  deriving Repr, DecidableEq

def step (o : Order) (ev : Event) : Except String Order :=
  match ev with
  | .pay amount =>
    if o.state == .created && amount > 0 then
      let newPaid := o.paidCents + amount
      let newState := if newPaid >= o.totalCents then OrderState.paid else OrderState.created
      .ok { o with paidCents := newPaid, state := newState }
    else
      .error "Cannot pay in current state"
  | .cancel =>
    if o.state == .created || o.state == .paid then
      .ok { o with state := .cancelled }
    else
      .error "Cannot cancel"
  | .ship =>
    if o.state == .paid then
      .ok { o with state := .shipped }
    else
      .error "Cannot ship"
```

---

## 3. Formulating Invariants and Finding the Bug

We formulate the core business safety invariant: **"An order can only be shipped if it has been fully paid (`paidCents >= totalCents`)."**

```lean
def ValidState (o : Order) : Prop :=
  o.state = .shipped → o.paidCents >= o.totalCents

-- Attempting to prove that any valid state remains valid after arbitrary events:
theorem step_maintains_validity (o : Order) (ev : Event) (h : ValidState o) :
  match step o ev with
  | .ok o'   => ValidState o'
  | .error _ => True := by
  cases ev <;> simp [step]
  case ship =>
    split
    · intro hState
      -- PROOF STUCK HERE!
      -- Hypothesis: o.state = .paid
      -- Goal: o.paidCents >= o.totalCents
      -- But does o.state = .paid guarantee o.paidCents >= o.totalCents?
      sorry
```

### Investigating Why the Proof Got Stuck
Lean cannot conclude `o.paidCents >= o.totalCents` purely from `o.state = .paid`.
When evaluating state transitions with `#eval`:
If an order is initialized as `%OrderFSM{state: :created, total_cents: 100, paid_cents: 0}`, what happens if an external update or partial state sets `total_cents` after initial payments, or if a refund reduces `paid_cents` without resetting state?
More critically: in the Elixir code, nothing prevented `ship/1` from executing if `state == :paid` even if `total_cents` was zero or unverified!

---

## 4. Generated ExUnit Reproducer Test (`test/order_fsm_test.exs`)

```elixir
defmodule OrderFSMTest do
  use ExUnit.Case

  test "reproducer from Lean formalization: state is :paid but paid_cents < total_cents" do
    # When total_cents is increased dynamically or created inconsistently
    order = %OrderFSM{id: 1, total_cents: 500, paid_cents: 100, state: :paid}

    # Elixir ships without asserting the invariant!
    assert {:ok, shipped} = OrderFSM.ship(order)
    assert shipped.state == :shipped
    # Invariant violated: shipped without full payment!
  end
end
```

---

## 5. Verified Elixir Fix

```elixir
def ship(%OrderFSM{state: :paid, total_cents: total, paid_cents: paid} = order)
    when paid >= total and total > 0 do
  {:ok, %{order | state: :shipped}}
end

def ship(_order), do: {:error, :cannot_ship}
```

Updating the Lean formalization with the guard:
```lean
  | .ship =>
    if o.state == .paid && o.paidCents >= o.totalCents && o.totalCents > 0 then
      .ok { o with state := .shipped }
    else
      .error "Cannot ship"
```
The Lean proof now resolves automatically with `omega` / `simp`!
