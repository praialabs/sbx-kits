---
name: elixir-lean-formalization
description: >-
  Formalize Elixir modules with the Lean 4 theorem prover to verify invariants,
  prove equivalence, identify optimization opportunities, and discover edge-case bugs and crash paths.
  Use when the user asks to formalize, verify, prove properties, or uncover bugs/optimizations in an Elixir module using Lean 4.
---

# Formalizing Elixir Modules with Lean 4

Formalizing Elixir code in Lean 4 forces an exhaustive, mathematically rigorous view of system behavior. Proof attempts frequently uncover subtle bugs, non-terminating loops, missing guard clauses, and unhandled pattern matches that unit tests, property-based tests, and naive LLM prompting miss.

---

## The 6-Phase Formalization Workflow

```
+-------------------------------------------------------------------------------+
|                        PHASE 1: SCOPE & BOUNDARY TRIAGE                       |
|   Separate pure domain logic / state transitions from BEAM I/O & scheduling   |
+---------------------------------------+---------------------------------------+
                                        |
                                        v
+-------------------------------------------------------------------------------+
|                       PHASE 2: LAKE PROJECT INITIALIZATION                    |
|   lake new formalization | lean-toolchain | Add Batteries if needed           |
+---------------------------------------+---------------------------------------+
                                        |
                                        v
+-------------------------------------------------------------------------------+
|                      PHASE 3: SEMANTIC MODELING IN LEAN 4                     |
|   Map Elixir types, structs, tuples, and reducer loops to Lean definitions   |
+---------------------------------------+---------------------------------------+
                                        |
                                        v
+-------------------------------------------------------------------------------+
|                     PHASE 4: TOTALITY & TERMINATION AUDIT                     |
|   Lean pattern exhaustiveness & termination_by expose missing branches/hangs |
+---------------------------------------+---------------------------------------+
                                        |
                                        v
+-------------------------------------------------------------------------------+
|                  PHASE 5: INVARIANT PROOFS & COUNTEREXAMPLES                  |
|   Prove preservation theorems; use #eval or slim_check on stuck proofs        |
+---------------------------------------+---------------------------------------+
                                        |
                                        v
+-------------------------------------------------------------------------------+
|                    PHASE 6: BACKPORTING & REPRODUCER TESTS                    |
|   Write ExUnit tests for found bugs; propose verified Pareto refactors        |
+-------------------------------------------------------------------------------+
```

---

### Phase 1: Scope & Boundary Triage

Do not attempt to formalize the entire BEAM actor scheduler, I/O sockets, or database drivers. Instead, separate:

1. **Pure Algorithmic Core:** Math, parsers, tokenizers, data structure transformations, validation pipelines. Formalize directly as pure Lean 4 functions.
2. **Stateful Processes (GenServers, Agents, FSMs):** Extract the state transition logic from `handle_call/3` and `handle_cast/2`. Formalize as a deterministic transition function:
   ```lean
   def step (s : State) (cmd : Command) : Except Error (State × List Action)
   ```
3. **Environment & Effects:** Model external queries as inputs to `step`, or parameterize with an abstract effect interface.

---

### Phase 2: Lake Project Initialization

From the repository root:

```bash
mkdir -p formalization
cd formalization
lake new formalization
```

1. **Toolchain:** Ensure `formalization/lean-toolchain` matches the environment (e.g. `leanprover/lean4:v4.34.0` or `leanprover/lean4:stable`).
2. **Dependencies:**
   - **Lean 4 Core + Batteries** (`leanprover-community/batteries`): Recommended default for general Elixir modules. Provides standard data structures and decision tactics (`omega`, `aesop`, `bv_decide`) with fast compile times:
     ```lean
     require batteries from git "https://github.com/leanprover-community/batteries" @ "main"
     ```
   - **CSLib** (`leanprover/cslib` - [cslib.io](https://www.cslib.io)): Dedicated computer science library (analogous to Mathlib for CS). Highly relevant when formalizing verified algorithms, data structures, execution semantics, or using the *Boole* framework for code reasoning:
     ```lean
     require cslib from git "https://github.com/leanprover/cslib" @ "main"
     ```
   - **Mathlib4** (`leanprover-community/mathlib4`): Only needed if the module involves advanced pure mathematics (topology, abstract algebra, real analysis). Avoid by default due to multi-gigabyte build size.
   - Run `lake update` and `lake build` to verify the setup.

---

### Phase 3: Semantic Modeling in Lean 4

Translate Elixir idioms into strict, statically typed Lean representations:

- **Atoms & Tagged Tuples:** Map to Lean `inductive` types.
- **Maps & Structs:** Map to Lean `structure`.
- **Dynamic Types & Nil:** Use `Option α` or `Except Error α`.
- **Numeric Guards (`when x > 0`):** Use dependent subtypes `{ x : Nat // x > 0 }` or `Nat` with precondition hypotheses.

See [references/translation_patterns.md](./references/translation_patterns.md) for detailed mapping patterns.

---

### Phase 4: Totality & Termination Audit

Lean 4 enforces totality and termination by default. This step surfaces immediate bugs:

1. **Non-Exhaustive Pattern Matching:**
   Elixir allows unhandled cases that crash at runtime with `CaseClauseError` or `FunctionClauseError`. When defining functions in Lean, missing branches trigger compiler errors:
   - Identify whether the unhandled case is an impossible state or a genuine missing edge-case in Elixir.
   - Record discovered edge cases in `formalization/FINDINGS.md`.
2. **Termination Proofs (`termination_by`):**
   Elixir recursive functions (`defp loop(state, acc)`) may diverge if an edge-case leads to cyclic transitions or non-decreasing loops.
   - Supply a decreasing measure in Lean (`termination_by size arg`).
   - If Lean cannot prove termination, trace the input that causes recursion without progress: this indicates an infinite loop vulnerability.

---

### Phase 5: Invariant Proofs & Counterexample Search

Formulate core system properties as Lean theorems:

```lean
-- State invariant preservation
theorem step_preserves_invariant (s : State) (cmd : Command) (h : Invariant s) :
  match step s cmd with
  | .ok (s', _) => Invariant s'
  | .error _    => True

-- Semantics-preserving refactor / Pareto equivalence
theorem refactor_is_equivalent (input : Input) :
  naive_implementation input = optimized_implementation input
```

#### Tactics & Proof Workflow
- Use automated decision procedures first: `simp`, `omega` (for integer/linear arithmetic), `aesop` (automated search), `bv_decide` (for bitwise operations).
- **When a proof gets stuck:** Do not waste cycles blindly trying tactics. A stuck proof often means the theorem is **false**!
  - Inspect the remaining proof goal.
  - Use `#eval` to test the property on concrete boundary values (e.g. empty lists, negative integers, 0, max integer).
  - Synthesize a counterexample.

---

### Phase 6: Backporting & Reporting

1. **Maintain Live Documentation (`formalization/FINDINGS.md`):**
   Keep this file updated throughout execution so progress is queryable via `/btw`:
   - 🐞 **Discovered Bugs & Unhandled Crashes**
   - ⚡ **Proven-Equivalent Optimizations**
   - 🛡 **Missing Guards or Spec Inaccuracies**
   - 📜 **Formalization Status** (verified theorems vs remaining `sorry` assumptions)
2. **Generate ExUnit Reproducers:**
   For every bug or invariant violation discovered in Lean, write an ExUnit test in `test/..._test.exs` proving the issue exists in the Elixir implementation.
3. **Propose Verified Fixes:**
   Update the Elixir code with necessary guard clauses, pattern handling, or verified performance optimizations.

---

## Detailed References & Examples

- [Translation Patterns Cheatsheet](./references/translation_patterns.md): Concrete Elixir to Lean 4 syntax mapping.
- [Walkthrough Example: Order FSM](./examples/order_fsm.md): End-to-end example of modeling a state machine, finding an invariant violation, and fixing the Elixir code.
