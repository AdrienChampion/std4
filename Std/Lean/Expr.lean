/-
Copyright (c) 2022 Mario Carneiro. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Mario Carneiro
-/
import Lean.Elab.Term

/-!
# Additional operations on Expr and related types

This file defines basic operations on the types expr, name, declaration, level, environment.

This file is mostly for non-tactics.
-/

namespace Lean.Expr

open Lean.Elab.Term in
/-- Converts an `Expr` into a `Syntax`, by creating a fresh metavariable
assigned to the expr and  returning a named metavariable syntax `?a`. -/
def toSyntax (e : Expr) : TermElabM Syntax.Term := withFreshMacroScope do
  let stx ← `(?a)
  let mvar ← elabTermEnsuringType stx (← Meta.inferType e)
  mvar.mvarId!.assign e
  pure stx

/--
Returns the number of leading `∀` binders of an expression. Ignores metadata.
-/
def forallArity : Expr → Nat
  | mdata _ b => forallArity b
  | forallE _ _ body _ => 1 + forallArity body
  | _ => 0

/--
Returns the number of leading `λ` binders of an expression. Ignores metadata.
-/
def lambdaArity : Expr → Nat
  | mdata _ b => lambdaArity b
  | lam _ _ b _ => 1 + lambdaArity b
  | _ => 0

/-- Like `getAppFn` but ignores metadata. -/
def getAppFn' : Expr → Expr
  | mdata _ b => getAppFn' b
  | app f _ => getAppFn' f
  | e => e

/-- Like `getAppNumArgs` but ignores metadata. -/
def getAppNumArgs' (e : Expr) : Nat :=
  go e 0
where
  /-- Auxiliary definition for `getAppNumArgs'`. -/
  go : Expr → Nat → Nat
    | mdata _ b, n => go b n
    | app f _  , n => go f (n + 1)
    | _        , n => n

/-- Like `withApp` but ignores metadata. -/
@[inline]
def withApp' (e : Expr) (k : Expr → Array Expr → α) : α :=
  let dummy := mkSort levelZero
  let nargs := e.getAppNumArgs'
  go e (mkArray nargs dummy) (nargs - 1)
where
  /-- Auxiliary definition for `withApp'`. -/
  @[specialize]
  go : Expr → Array Expr → Nat → α
    | mdata _ b, as, i => go b as i
    | app f a  , as, i => go f (as.set! i a) (i-1)
    | f        , as, _ => k f as

/-- Like `getAppArgs` but ignores metadata. -/
@[inline]
def getAppArgs' (e : Expr) : Array Expr :=
  e.withApp' λ _ as => as

/-- Like `traverseApp` but ignores metadata. -/
def traverseApp' {m} [Monad m]
  (f : Expr → m Expr) (e : Expr) : m Expr :=
  e.withApp' λ fn args => return mkAppN (← f fn) (← args.mapM f)

/-- Like `withAppRev` but ignores metadata. -/
@[inline]
def withAppRev' (e : Expr) (k : Expr → Array Expr → α) : α :=
  go e (Array.mkEmpty e.getAppNumArgs')
where
  /-- Auxiliary definition for `withAppRev'`. -/
  @[specialize]
  go : Expr → Array Expr → α
    | mdata _ b, as => go b as
    | app f a  , as => go f (as.push a)
    | f        , as => k f as

/-- Like `getAppRevArgs` but ignores metadata. -/
@[inline]
def getAppRevArgs' (e : Expr) : Array Expr :=
  e.withAppRev' λ _ as => as

/-- Like `getRevArgD` but ignores metadata. -/
def getRevArgD' : Expr → Nat → Expr → Expr
  | mdata _ b, n  , v => getRevArgD' b n v
  | app _ a  , 0  , _ => a
  | app f _  , i+1, v => getRevArgD' f i v
  | _        , _  , v => v

/-- Like `getRevArg!` but ignores metadata. -/
@[inline]
def getRevArg!' : Expr → Nat → Expr
  | mdata _ b, n   => getRevArg!' b n
  | app _ a  , 0   => a
  | app f _  , i+1 => getRevArg!' f i
  | _        , _   => panic! "invalid index"

/-- Like `getArgD` but ignores metadata. -/
@[inline]
def getArgD' (e : Expr) (i : Nat) (v₀ : Expr) (n := e.getAppNumArgs') : Expr :=
  getRevArgD' e (n - i - 1) v₀

/-- Like `getArg!` but ignores metadata. -/
@[inline]
def getArg!' (e : Expr) (i : Nat) (n := e.getAppNumArgs') : Expr :=
  getRevArg!' e (n - i - 1)

/-- Like `isAppOf` but ignores metadata. -/
def isAppOf' (e : Expr) (n : Name) : Bool :=
  match e.getAppFn' with
  | const c .. => c == n
  | _ => false

/-- If the expression is a constant, return that name. Otherwise return `Name.anonymous`. -/
def constName (e : Expr) : Name :=
  e.constName?.getD Name.anonymous

/-- Return the function (name) and arguments of an application. -/
def getAppFnArgs (e : Expr) : Name × Array Expr :=
  withApp e λ e a => (e.constName, a)

/-- Turns an expression that is a natural number literal into a natural number. -/
def natLit! : Expr → Nat
  | lit (Literal.natVal v) => v
  | _                      => panic! "nat literal expected"

/-- Turns an expression that is a constructor of `Int` applied to a natural number literal
into an integer. -/
def intLit! (e : Expr) : Int :=
  if e.isAppOfArity ``Int.ofNat 1 then
    e.appArg!.natLit!
  else if e.isAppOfArity ``Int.negOfNat 1 then
    .negOfNat e.appArg!.natLit!
  else
    panic! "not a raw integer literal"

/--
Checks if an expression is a "natural number in normal form",
i.e. of the form `OfNat n`, where `n` matches `.lit (.natVal lit)` for some `lit`.
and if so returns `lit`.
-/
-- Note that an `Expr.lit (.natVal n)` is not considered in normal form!
def nat? (e : Expr) : Option Nat := do
  guard <| e.isAppOfArity ``OfNat.ofNat 3
  let lit (.natVal n) := e.appFn!.appArg! | none
  n

/--
Checks if an expression is an "integer in normal form",
i.e. either a natural number in normal form, or the negation of a positive natural number,
and if so returns the integer.
-/
def int? (e : Expr) : Option Int :=
  if e.isAppOfArity ``Neg.neg 3 then
    match e.appArg!.nat? with
    | none => none
    | some 0 => none
    | some n => some (-n)
  else
    e.nat?
