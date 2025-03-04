/-
Copyright (c) 2023 by the authors listed in the file AUTHORS and their
institutional affiliations. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Joe Hendrix
-/

/-
This module defines properties of the bitwise operations on Natural numbers.

It is primarily intended to support the bitvector library.
-/
import Std.Data.Bool
import Std.Data.Nat.Lemmas
import Std.Tactic.RCases
import Std.Tactic.Simpa

namespace Nat

@[local simp]
private theorem one_div_two : 1/2 = 0 := by trivial

private theorem two_pow_succ_sub_one_div : (2 ^ (n+1) - 1) / 2 = 2^n - 1 := by
  apply fun x => (Nat.sub_eq_of_eq_add x).symm
  apply Eq.trans _
  apply Nat.add_mul_div_left _ _ Nat.zero_lt_two
  rw [Nat.mul_one, ←Nat.sub_add_comm (Nat.two_pow_pos _)]
  rw [ Nat.add_sub_assoc Nat.zero_lt_two ]
  simp [Nat.pow_succ, Nat.mul_comm _ 2, Nat.mul_add_div]

private theorem two_mul_sub_one {n : Nat} (n_pos : n > 0) : (2*n - 1) % 2 = 1 := by
  match n with
  | 0 => contradiction
  | n + 1 => simp [Nat.mul_succ, Nat.mul_add_mod, mod_eq_of_lt]

/-! ### Preliminaries -/

/--
An induction principal that works on divison by two.
-/
noncomputable def div2Induction {motive : Nat → Sort u}
    (n : Nat) (ind : ∀(n : Nat), (n > 0 → motive (n/2)) → motive n) : motive n := by
  induction n using Nat.strongInductionOn with
  | ind n hyp =>
    apply ind
    intro n_pos
    if n_eq : n = 0 then
      simp [n_eq] at n_pos
    else
      apply hyp
      exact Nat.div_lt_self n_pos (Nat.le_refl _)

@[simp] theorem zero_and (x : Nat) : 0 &&& x = 0 := by rfl

@[simp] theorem and_zero (x : Nat) : x &&& 0 = 0 := by
  simp only [HAnd.hAnd, AndOp.and, land]
  unfold bitwise
  simp

@[simp] theorem and_one_is_mod (x : Nat) : x &&& 1 = x % 2 := by
  if xz : x = 0 then
    simp [xz, zero_and]
  else
    have andz := and_zero (x/2)
    simp only [HAnd.hAnd, AndOp.and, land] at andz
    simp only [HAnd.hAnd, AndOp.and, land]
    unfold bitwise
    cases mod_two_eq_zero_or_one x with | _ p =>
      simp [xz, p, andz, one_div_two, mod_eq_of_lt]

/-! ### testBit -/

@[simp] theorem zero_testBit (i : Nat) : testBit 0 i = false := by
  simp only [testBit, zero_shiftRight, zero_and, bne_self_eq_false]

@[simp] theorem testBit_zero (x : Nat) : testBit x 0 = decide (x % 2 = 1) := by
  cases mod_two_eq_zero_or_one x with | _ p => simp [testBit, p]

@[simp] theorem testBit_succ (x i : Nat) : testBit x (succ i) = testBit (x/2) i := by
  unfold testBit
  simp [shiftRight_succ_inside]

theorem testBit_to_div_mod {x : Nat} : testBit x i = decide (x / 2^i % 2 = 1) := by
  induction i generalizing x with
  | zero =>
    unfold testBit
    cases mod_two_eq_zero_or_one x with | _ xz => simp [xz]
  | succ i hyp =>
    simp [hyp, Nat.div_div_eq_div_mul, Nat.pow_succ']

theorem ne_zero_implies_bit_true {x : Nat} (xnz : x ≠ 0) : ∃ i, testBit x i := by
  induction x using div2Induction with
  | ind x hyp =>
    have x_pos : x > 0 := Nat.pos_of_ne_zero xnz
    match mod_two_eq_zero_or_one x with
    | Or.inl mod2_eq =>
      rw [←div_add_mod x 2] at xnz
      simp only [mod2_eq, ne_eq, Nat.mul_eq_zero, Nat.add_zero, false_or] at xnz
      have ⟨d, dif⟩   := hyp x_pos xnz
      apply Exists.intro (d+1)
      simp_all
    | Or.inr mod2_eq =>
      apply Exists.intro 0
      simp_all

theorem ne_implies_bit_diff {x y : Nat} (p : x ≠ y) : ∃ i, testBit x i ≠ testBit y i := by
  induction y using Nat.div2Induction generalizing x with
  | ind y hyp =>
    cases Nat.eq_zero_or_pos y with
    | inl yz =>
      simp only [yz, Nat.zero_testBit, Bool.eq_false_iff]
      simp only [yz] at p
      have ⟨i,ip⟩  := ne_zero_implies_bit_true p
      apply Exists.intro i
      simp [ip]
    | inr ypos =>
      if lsb_diff : x % 2 = y % 2 then
        rw [←Nat.div_add_mod x 2, ←Nat.div_add_mod y 2] at p
        simp only [ne_eq, lsb_diff, Nat.add_right_cancel_iff,
          Nat.zero_lt_succ, Nat.mul_left_cancel_iff] at p
        have ⟨i, ieq⟩  := hyp ypos p
        apply Exists.intro (i+1)
        simpa
      else
        apply Exists.intro 0
        simp only [testBit_zero]
        revert lsb_diff
        cases mod_two_eq_zero_or_one x with | _ p =>
          cases mod_two_eq_zero_or_one y with | _ q =>
            simp [p,q]

/--
`eq_of_testBit_eq` allows proving two natural numbers are equal
if their bits are all equal.
-/
theorem eq_of_testBit_eq {x y : Nat} (pred : ∀i, testBit x i = testBit y i) : x = y := by
  if h : x = y then
    exact h
  else
    let ⟨i,eq⟩ := ne_implies_bit_diff h
    have p := pred i
    contradiction

theorem ge_two_pow_implies_high_bit_true {x : Nat} (p : x ≥ 2^n) : ∃ i, i ≥ n ∧ testBit x i := by
  induction x using div2Induction generalizing n with
  | ind x hyp =>
    have x_pos : x > 0 := Nat.lt_of_lt_of_le (Nat.two_pow_pos n) p
    have x_ne_zero : x ≠ 0 := Nat.ne_of_gt x_pos
    match n with
    | zero =>
      let ⟨j, jp⟩ := ne_zero_implies_bit_true x_ne_zero
      exact Exists.intro j (And.intro (Nat.zero_le _) jp)
    | succ n =>
      have x_ge_n : x / 2 ≥ 2 ^ n := by
          simpa [le_div_iff_mul_le, ← Nat.pow_succ'] using p
      have ⟨j, jp⟩ := @hyp x_pos n x_ge_n
      apply Exists.intro (j+1)
      apply And.intro
      case left =>
        exact (Nat.succ_le_succ jp.left)
      case right =>
        simpa using jp.right

theorem testBit_implies_ge {x : Nat} (p : testBit x i = true) : x ≥ 2^i := by
  simp only [testBit_to_div_mod] at p
  by_contra not_ge
  have x_lt : x < 2^i := Nat.lt_of_not_le not_ge
  simp [div_eq_of_lt x_lt] at p

theorem testBit_lt_two {x i : Nat} (lt : x < 2^i) : x.testBit i = false := by
  match p : x.testBit i with
  | false => trivial
  | true =>
    exfalso
    exact Nat.not_le_of_gt lt (testBit_implies_ge p)

theorem lt_pow_two_of_testBit (x : Nat) (p : ∀i, i ≥ n → testBit x i = false) : x < 2^n := by
  by_contra not_lt
  have x_ge_n := Nat.ge_of_not_lt not_lt
  have ⟨i, ⟨i_ge_n, test_true⟩⟩ := ge_two_pow_implies_high_bit_true x_ge_n
  have test_false := p _ i_ge_n
  simp only [test_true] at test_false

/-! ### testBit -/

private theorem succ_mod_two : succ x % 2 = 1 - x % 2 := by
  induction x with
  | zero =>
    trivial
  | succ x hyp =>
    have p : 2 ≤ x + 2 := Nat.le_add_left _ _
    simp [Nat.mod_eq (x+2) 2, p, hyp]
    cases Nat.mod_two_eq_zero_or_one x with | _ p => simp [p]

private theorem testBit_succ_zero : testBit (x + 1) 0 = not (testBit x 0) := by
  simp [testBit_to_div_mod, succ_mod_two]
  cases Nat.mod_two_eq_zero_or_one x with | _ p =>
    simp [p]

theorem testBit_two_pow_add_eq (x i : Nat) : testBit (2^i + x) i = not (testBit x i) := by
  simp [testBit_to_div_mod, add_div_left, Nat.two_pow_pos, succ_mod_two]
  cases mod_two_eq_zero_or_one (x / 2 ^ i) with
  | _ p => simp [p]

theorem testBit_mul_two_pow_add_eq (a b i : Nat) :
    testBit (2^i*a + b) i = Bool.xor (a%2 = 1) (testBit b i) := by
  match a with
  | 0 => simp
  | a+1 =>
    simp [Nat.mul_succ, Nat.add_assoc,
          testBit_mul_two_pow_add_eq a,
          testBit_two_pow_add_eq,
          Nat.succ_mod_two]
    cases mod_two_eq_zero_or_one a with
    | _ p => simp [p]

theorem testBit_two_pow_add_gt {i j : Nat} (j_lt_i : j < i) (x : Nat) :
    testBit (2^i + x) j = testBit x j := by
  have i_def : i = j + (i-j) := (Nat.add_sub_cancel' (Nat.le_of_lt j_lt_i)).symm
  rw [i_def]
  simp only [testBit_to_div_mod, Nat.pow_add,
        Nat.add_comm x, Nat.mul_add_div (Nat.two_pow_pos _)]
  match i_sub_j_eq : i - j with
  | 0 =>
    exfalso
    rw [Nat.sub_eq_zero_iff_le] at i_sub_j_eq
    exact Nat.not_le_of_gt j_lt_i i_sub_j_eq
  | d+1 =>
    simp [pow_succ, Nat.mul_comm _ 2,  Nat.mul_add_mod]

@[simp] theorem testBit_mod_two_pow (x j i : Nat) :
    testBit (x % 2^j) i = (decide (i < j) && testBit x i) := by
  induction x using Nat.strongInductionOn generalizing j i with
  | ind x hyp =>
    rw [mod_eq]
    rcases Nat.lt_or_ge x (2^j) with x_lt_j | x_ge_j
    · have not_j_le_x := Nat.not_le_of_gt x_lt_j
      simp [not_j_le_x]
      rcases Nat.lt_or_ge i j with i_lt_j | i_ge_j
      · simp [i_lt_j]
      · have x_lt : x < 2^i :=
            calc x < 2^j := x_lt_j
                _ ≤ 2^i := Nat.pow_le_pow_of_le_right Nat.zero_lt_two i_ge_j
        simp [Nat.testBit_lt_two x_lt]
    · generalize y_eq : x - 2^j = y
      have x_eq : x = y + 2^j := Nat.eq_add_of_sub_eq x_ge_j y_eq
      simp only [Nat.two_pow_pos, x_eq, Nat.le_add_left, true_and, ite_true]
      have y_lt_x : y < x := by
            simp [x_eq]
            exact Nat.lt_add_of_pos_right (Nat.two_pow_pos j)
      simp only [hyp y y_lt_x]
      if i_lt_j : i < j then
        rw [ Nat.add_comm _ (2^_), testBit_two_pow_add_gt i_lt_j]
      else
        simp [i_lt_j]

private theorem testBit_one_zero : testBit 1 0 = true := by trivial

@[simp] theorem testBit_two_pow_sub_one (n i : Nat) : testBit (2^n-1) i = decide (i < n) := by
  induction i generalizing n with
  | zero =>
    simp only [testBit_zero]
    match n with
    | 0 =>
      simp
    | n+1 =>
      simp [Nat.pow_succ, Nat.mul_comm _ 2, two_mul_sub_one, Nat.two_pow_pos]
  | succ i hyp =>
    simp only [testBit_succ]
    match n with
    | 0 =>
      simp [pow_zero]
    | n+1 =>
      simp [two_pow_succ_sub_one_div, hyp, Nat.succ_lt_succ_iff]

theorem testBit_bool_to_nat (b : Bool) (i : Nat) :
    testBit (Bool.toNat b) i = (decide (i = 0) && b) := by
  cases b <;> cases i <;>
  simp [testBit_to_div_mod, Nat.pow_succ, Nat.mul_comm _ 2,
        ←Nat.div_div_eq_div_mul _ 2, one_div_two,
        Nat.mod_eq_of_lt]

/-! ### bitwise -/

theorem testBit_bitwise
  (false_false_axiom : f false false = false) (x y i : Nat)
: (bitwise f x y).testBit i = f (x.testBit i) (y.testBit i) := by
  induction i using Nat.strongInductionOn generalizing x y with
  | ind i hyp =>
    unfold bitwise
    if x_zero : x = 0 then
      cases p : f false true <;>
        cases yi : testBit y i <;>
          simp [x_zero, p, yi, false_false_axiom]
    else if y_zero : y = 0 then
      simp [x_zero, y_zero]
      cases p : f true false <;>
        cases xi : testBit x i <;>
          simp [p, xi, false_false_axiom]
    else
      simp only [x_zero, y_zero, ←Nat.two_mul]
      cases i with
      | zero =>
        cases p : f (decide (x % 2 = 1)) (decide (y % 2 = 1)) <;>
          simp [p, Nat.mul_add_mod, mod_eq_of_lt]
      | succ i =>
        have hyp_i := hyp i (Nat.le_refl (i+1))
        cases p : f (decide (x % 2 = 1)) (decide (y % 2 = 1)) <;>
          simp [p, one_div_two, hyp_i, Nat.mul_add_div]

/-! ### bitwise -/

@[local simp]
private theorem eq_0_of_lt_one (x : Nat) : x < 1 ↔ x = 0 :=
  Iff.intro
    (fun p =>
      match x with
      | 0 => Eq.refl 0
      | _+1 => False.elim (not_lt_zero _ (Nat.lt_of_succ_lt_succ p)))
    (fun p => by simp [p, Nat.zero_lt_succ])

private theorem eq_0_of_lt (x : Nat) : x < 2^ 0 ↔ x = 0 := eq_0_of_lt_one x

@[local simp]
private theorem zero_lt_pow (n : Nat) : 0 < 2^n := by
  induction n
  case zero => simp [eq_0_of_lt]
  case succ n hyp =>
    simp [pow_succ]
    exact (Nat.mul_lt_mul_of_pos_right hyp Nat.zero_lt_two : 0 < 2 ^ n * 2)

private theorem div_two_le_of_lt_two {m n : Nat} (p : m < 2 ^ succ n) : m / 2 < 2^n := by
  simp [div_lt_iff_lt_mul Nat.zero_lt_two]
  exact p

/-- This provides a bound on bitwise operations. -/
theorem bitwise_lt_two_pow (left : x < 2^n) (right : y < 2^n) : (Nat.bitwise f x y) < 2^n := by
  induction n generalizing x y with
  | zero =>
    simp only [eq_0_of_lt] at left right
    unfold bitwise
    simp [left, right]
  | succ n hyp =>
    unfold bitwise
    if x_zero : x = 0 then
      simp only [x_zero, if_true]
      by_cases p : f false true = true <;> simp [p, right]
    else if y_zero : y = 0 then
      simp only [x_zero, y_zero, if_false, if_true]
      by_cases p : f true false = true <;> simp [p, left]
    else
      simp only [x_zero, y_zero, if_false]
      have hyp1 := hyp (div_two_le_of_lt_two left) (div_two_le_of_lt_two right)
      by_cases p : f (decide (x % 2 = 1)) (decide (y % 2 = 1)) = true <;>
        simp [p, pow_succ, mul_succ, Nat.add_assoc]
      case pos =>
        apply lt_of_succ_le
        simp only [← Nat.succ_add]
        apply Nat.add_le_add <;> exact hyp1
      case neg =>
        apply Nat.add_lt_add <;> exact hyp1

/-! ### and -/

@[simp] theorem testBit_and (x y i : Nat) : (x &&& y).testBit i = (x.testBit i && y.testBit i) := by
  simp [HAnd.hAnd, AndOp.and, land, testBit_bitwise ]

theorem and_lt_two_pow (x : Nat) {y n : Nat} (right : y < 2^n) : (x &&& y) < 2^n := by
  apply lt_pow_two_of_testBit
  intro i i_ge_n
  have yf : testBit y i = false := by
          apply Nat.testBit_lt_two
          apply Nat.lt_of_lt_of_le right
          exact pow_le_pow_of_le_right Nat.zero_lt_two i_ge_n
  simp [testBit_and, yf]

@[simp] theorem and_pow_two_is_mod (x n : Nat) : x &&& (2^n-1) = x % 2^n := by
  apply eq_of_testBit_eq
  intro i
  simp only [testBit_and, testBit_mod_two_pow]
  cases testBit x i <;> simp

theorem and_pow_two_identity {x : Nat} (lt : x < 2^n) : x &&& 2^n-1 = x := by
  rw [and_pow_two_is_mod]
  apply Nat.mod_eq_of_lt lt

/-! ### lor -/

@[simp] theorem or_zero (x : Nat) : 0 ||| x = x := by
  simp only [HOr.hOr, OrOp.or, lor]
  unfold bitwise
  simp [@eq_comm _ 0]

@[simp] theorem zero_or (x : Nat) : x ||| 0 = x := by
  simp only [HOr.hOr, OrOp.or, lor]
  unfold bitwise
  simp [@eq_comm _ 0]

@[simp] theorem testBit_or (x y i : Nat) : (x ||| y).testBit i = (x.testBit i || y.testBit i) := by
  simp [HOr.hOr, OrOp.or, lor, testBit_bitwise ]

theorem or_lt_two_pow {x y n : Nat} (left : x < 2^n) (right : y < 2^n) : x ||| y < 2^n :=
  bitwise_lt_two_pow left right

/-! ### xor -/

@[simp] theorem testBit_xor (x y i : Nat) :
    (x ^^^ y).testBit i = Bool.xor (x.testBit i) (y.testBit i) := by
  simp [HXor.hXor, Xor.xor, xor, testBit_bitwise ]

theorem xor_lt_two_pow {x y n : Nat} (left : x < 2^n) (right : y < 2^n) : x ^^^ y < 2^n :=
  bitwise_lt_two_pow left right

/-! ### Arithmetic -/

theorem testBit_mul_pow_two_add (a : Nat) {b i : Nat} (b_lt : b < 2^i) (j : Nat) :
    testBit (2 ^ i * a + b) j =
      if j < i then
        testBit b j
      else
        testBit a (j - i) := by
  cases Nat.lt_or_ge j i with
  | inl j_lt =>
    simp only [j_lt]
    have i_ge := Nat.le_of_lt j_lt
    have i_sub_j_nez : i-j ≠ 0 := Nat.sub_ne_zero_of_lt j_lt
    have i_def : i = j + succ (pred (i-j)) :=
          calc i = j + (i-j) := (Nat.add_sub_cancel' i_ge).symm
               _ = j + succ (pred (i-j)) := by
                 rw [← congrArg (j+·) (Nat.succ_pred i_sub_j_nez)]
    rw [i_def]
    simp only [testBit_to_div_mod, Nat.pow_add, Nat.mul_assoc]
    simp only [Nat.mul_add_div (Nat.two_pow_pos _), Nat.mul_add_mod]
    simp [Nat.pow_succ, Nat.mul_comm _ 2, Nat.mul_assoc, Nat.mul_add_mod]
  | inr j_ge =>
    have j_def : j = i + (j-i) := (Nat.add_sub_cancel' j_ge).symm
    simp only [
        testBit_to_div_mod,
        Nat.not_lt_of_le,
        j_ge,
        ite_false]
    simp [congrArg (2^·) j_def, Nat.pow_add,
          ←Nat.div_div_eq_div_mul,
          Nat.mul_add_div,
          Nat.div_eq_of_lt b_lt,
          Nat.two_pow_pos i]

theorem testBit_mul_pow_two :
    testBit (2 ^ i * a) j = (decide (j ≥ i) && testBit a (j-i)) := by
  have gen := testBit_mul_pow_two_add a (Nat.two_pow_pos i) j
  simp at gen
  rw [gen]
  cases Nat.lt_or_ge j i with
  | _ p => simp [p, Nat.not_le_of_lt, Nat.not_lt_of_le]

theorem mul_add_lt_is_or {b : Nat} (b_lt : b < 2^i) (a : Nat) : 2^i * a + b = 2^i * a ||| b := by
  apply eq_of_testBit_eq
  intro j
  simp only [testBit_mul_pow_two_add _ b_lt,
        testBit_or, testBit_mul_pow_two]
  if j_lt : j < i then
    simp [Nat.not_le_of_lt, j_lt]
  else
    have i_le : i ≤ j := Nat.le_of_not_lt j_lt
    have b_lt_j :=
            calc b < 2 ^ i := b_lt
                 _ ≤ 2 ^ j := Nat.pow_le_pow_of_le_right Nat.zero_lt_two i_le
    simp [i_le, j_lt, testBit_lt_two, b_lt_j]

/-! ### shiftLeft and shiftRight -/

@[simp] theorem testBit_shiftLeft (x : Nat) : testBit (x <<< i) j =
    (decide (j ≥ i) && testBit x (j-i)) := by
  simp [shiftLeft_eq, Nat.mul_comm _ (2^_), testBit_mul_pow_two]

@[simp] theorem testBit_shiftRight (x : Nat) : testBit (x >>> i) j = testBit x (i+j) := by
  simp [testBit, ←shiftRight_add]
