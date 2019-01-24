(* TODO: this is a bit of a hack, should be using a dedicated Options.v *)
Global Unset Auto Template Polymorphism.
Global Set Implicit Arguments.

From Coq Require Import Omega.
From Coq Require Import Arith.
From Classes Require Import EqualDec.
From stdpp Require Import decidable countable.

Instance eqdecision `{dec:EqualDec A} : EqDecision A := dec.

From Coq Require Import Extraction.

(** Machine unsigned integers *)

(* These will extract to Word64, with checked arithmetic to ensure the program
raises an exception (that is, crashes) if it overflows, leaving the model. We
can handle underflow by returning 0; we have to check anyway and the Coq model
saturates to 0 so we might as well match it (relying on this is a bad idea in
case we ever make this situation better). *)
Record uint64 : Type :=
  fromNum { toNum : nat }.

(* so convenient! wow! *)
Coercion fromNum : nat >-> uint64.

Lemma toNum_inj : forall x y, toNum x = toNum y -> x = y.
Proof.
  destruct x, y; simpl; auto.
Qed.

Lemma from_to_num_id : forall x, fromNum (toNum x) = x.
Proof.
  destruct x; simpl; auto.
Qed.

Lemma to_from_num_id : forall n, toNum (fromNum n) = n.
Proof.
  simpl; auto.
Qed.

Lemma u64_neq n m :
    fromNum n <> fromNum m ->
    n <> m.
Proof.
  intuition auto.
Qed.

Lemma fromNum_inj n m :
    fromNum n = fromNum m ->
    n = m.
Proof.
  inversion 1; auto.
Qed.

Ltac u64_cleanup :=
  repeat match goal with
         | [ H: fromNum ?n = fromNum ?m |- _ ] =>
           apply fromNum_inj in H
         | [ H: fromNum ?n <> fromNum ?m |- _ ] =>
           apply u64_neq in H
         end.

Section UInt64.
  Implicit Types (x y:uint64).
  Definition add x y : uint64 := fromNum (x.(toNum) + y.(toNum)).
  Definition sub x y : uint64 := fromNum (x.(toNum) - y.(toNum)).
  Definition compare x y : comparison := Nat.compare x.(toNum) y.(toNum).
End UInt64.

Instance uint64_eq_dec : EqualDec uint64.
Proof.
  hnf; intros.
  destruct_with_eqn (compare x y); unfold compare in *;
    [ left | right; intros <- .. ].
  - destruct x as [x], y as [y]; simpl in *.
    apply Nat.compare_eq_iff in Heqc; auto using toNum_inj.
  - destruct x as [x]; simpl in *.
    rewrite Nat.compare_refl in *; congruence.
  - destruct x as [x]; simpl in *.
    rewrite Nat.compare_refl in *; congruence.
Defined.

Module UIntNotations.
  Delimit Scope uint64_scope with u64.
  Infix "+" := add : uint64_scope.
  Infix "-" := sub : uint64_scope.
  Notation "0" := (fromNum 0) : uint64_scope.
  Notation "1" := (fromNum 1) : uint64_scope.
End UIntNotations.

(* bytes are completely opaque; there should be no need to worry about them *)
Axiom byte : Type.
Axiom byte_eqdec : EqualDec byte.
Existing Instance byte_eqdec.

Record ByteString :=
  fromByteList { getBytes: list byte }.

Instance ByteString_eq_dec : EqualDec ByteString.
Proof.
  hnf; decide equality.
  apply (equal getBytes0 getBytes1).
Defined.

Module BS.
  Implicit Types (bs:ByteString).
  Local Coercion getBytes : ByteString >-> list.
  Definition append bs1 bs2 := fromByteList (bs1 ++ bs2).
  Definition length bs : uint64 := fromNum (List.length bs).
  Definition take (n:uint64) bs :=
    fromByteList (List.firstn n.(toNum) bs).
  Definition drop (n:uint64) bs :=
    fromByteList (List.skipn n.(toNum) bs).
  Definition empty : ByteString := fromByteList [].
End BS.

Lemma skipn_nil A n : skipn n (@nil A) = nil.
  induction n; simpl; auto.
Qed.

Lemma skipn_length A n (l: list A) :
  List.length (List.skipn n l) = List.length l - n.
Proof.
  generalize dependent n.
  induction l; simpl; intros.
  rewrite skipn_nil; simpl.
  lia.
  destruct n; simpl; auto.
Qed.

Import UIntNotations.

Theorem drop_length : forall n bs, BS.length (BS.drop n bs) = (BS.length bs - n)%u64.
Proof.
  destruct bs as [bs].
  unfold BS.drop, BS.length; cbn [getBytes].
  rewrite skipn_length.
  reflexivity.
Qed.

Module BSNotations.
  Delimit Scope bs_scope with bs.
  Infix "++" := BS.append : bs_scope.
End BSNotations.

Class UIntEncoding bytes intTy :=
  { encodeLE : intTy -> ByteString;
    decodeLE : ByteString -> option intTy;
    encode_length_ok : forall x, toNum (BS.length (encodeLE x)) = bytes;
    encode_decode_LE_ok : forall x, decodeLE (encodeLE x) = Some x;
  }.

Axiom uint64_le_enc : UIntEncoding 8 uint64.
Existing Instances uint64_le_enc.

(** File descriptors *)

Axiom Fd:Type.
Axiom fd_eqdec : EqualDec Fd.
Existing Instance fd_eqdec.
Axiom fd_countable : Countable Fd.
Existing Instance fd_countable.
