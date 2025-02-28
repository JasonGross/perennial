From RecordUpdate Require Import RecordSet.

From Perennial.Helpers Require Import ModArith.
From Perennial.program_logic Require Import atomic.
From Perennial.program_logic Require Import recovery_adequacy dist_adequacy.
From Perennial.goose_lang Require Import crash_modality wpr_lifting dist_lifting.
From Perennial.goose_lang Require Import adequacy recovery_adequacy dist_adequacy.

From Goose.github_com.mit_pdos.perennial_examples Require Import replicated_block.
From Perennial.algebra Require Import own_discrete.
From Perennial.goose_lang.lib Require Import lock.crash_lock.
From Perennial.program_proof Require Import disk_lib.
From Perennial.program_proof Require Import disk_prelude.


(** * Replicated block example

    Replicates single-block writes across two underlying disk blocks, and
    supports read from either the "primary" or "backup" block.

    On crash the blocks may disagree. In that case the recovery procedure copies
    from the primary to restore synchronization.
 *)

(* the abstract state of the replicated block is  *)
Module rblock.
  Definition t := Block.
End rblock.

Section goose.
  Context `{!heapG Σ}.
  Context `{!stagedG Σ}.

  Implicit Types (l:loc) (addr: u64) (σ: rblock.t) (γ: gname).

  (* the replicated block has a stronger lock invariant [rblock_linv] that holds
  when the lock is free as well as a weaker crash invariant [rblock_cinv] that
  holds at all intermediate points *)
  Definition rblock_linv addr σ : iProp Σ :=
    ("Hprimary" ∷ int.Z addr d↦ σ ∗
     "Hbackup" ∷ int.Z (word.add addr 1) d↦ σ)%I.

  Definition rblock_cinv addr σ :=
    ("Hprimary" ∷ int.Z addr d↦ σ ∗
     "Hbackup" ∷ ∃ b0, int.Z (word.add addr 1) d↦ b0)%I.
  (* Let eauto unfold this *)
  Local Hint Extern 1 (environments.envs_entails _ (rblock_cinv _ _)) => unfold rblock_cinv : core.

  Instance rblock_linv_discretizable addr σ:
    Discretizable (rblock_linv addr σ).
  Proof. apply _. Qed.

  Instance rblock_cinv_discretizable addr σ:
    Discretizable (rblock_cinv addr σ).
  Proof. apply _. Qed.

  Theorem rblock_linv_to_cinv addr σ :
    rblock_linv addr σ -∗ rblock_cinv addr σ.
  Proof.
    iNamed 1.
    iFrame "Hprimary".
    iExists _; iFrame.
  Qed.

  (** the abstraction relation for the replicated block is written in HOCAP
  style, by quantifying over an arbitrary caller-specified predicate [P] of the
  block's state. *)
  Let N := nroot.@"replicated_block".
  Context (P: rblock.t → iProp Σ).

  (* low-level rblock state *)
  Definition rblock_state l d m_ref addr : iProp Σ :=
      (* reflect coq values in program data structure *)
      "#d" ∷ readonly (l ↦[RepBlock :: "d"] (disk_val d)) ∗
      "#addr" ∷ readonly (l ↦[RepBlock :: "addr"] #addr) ∗
      "#m" ∷ readonly (l ↦[RepBlock :: "m"] #m_ref).

  Definition is_pre_rblock (l: loc) addr σ : iProp Σ :=
    "*" ∷ (∃ d (m_ref : loc),
      "Hro_state" ∷ rblock_state l d m_ref addr ∗
      "Hfree_lock" ∷ is_free_lock m_ref) ∗
    "Hlinv" ∷ rblock_linv addr σ.

  Definition is_rblock (k': nat) (l: loc) addr : iProp Σ :=
    ∃ d (m_ref : loc),
      "Hro_state" ∷ rblock_state l d m_ref addr ∗
      (* lock protocol *)
      "#Hlock" ∷ is_crash_lock N k' #m_ref
        (∃ σ, "Hlkinv" ∷ rblock_linv addr σ ∗ "HP" ∷ P σ)
        (∃ σ, "Hclkinv" ∷ rblock_cinv addr σ ∗ "HP" ∷ P σ)
  .

  Global Instance is_rblock_Persistent k' l addr :
    Persistent (is_rblock k' l addr).
  Proof. apply _. Qed.

  Theorem init_zero_cinv addr :
    int.Z addr d↦ block0 ∗ int.Z (word.add addr 1) d↦ block0 -∗
    rblock_cinv addr block0.
  Proof.
    iIntros "(Hp&Hb)".
    iSplitL "Hp".
    - iExact "Hp".
    - iExists block0; iExact "Hb".
  Qed.

  Theorem replicated_block_cfupd {l} k' addr σ0 :
    is_pre_rblock l addr σ0 -∗
    ▷ P σ0 ={⊤}=∗
      is_rblock (S k') l addr ∗
      <disc> |C={⊤}_(S k')=> ▷ (∃ σ, rblock_cinv addr σ ∗ P σ).
  Proof.
    iIntros "Hpre HP"; iNamed "Hpre".

    (* actually initialize the lock *)
    iMod (alloc_crash_lock_cfupd N k'
                             (∃ σ, "Hlkinv" ∷ rblock_linv addr σ ∗ "HP" ∷ P σ)%I
                             (∃ σ, "Hclkinv" ∷ rblock_cinv addr σ ∗ "HP" ∷ P σ)%I
            with "Hfree_lock [] [Hlinv HP]") as "(Hlk&$)".
    { iIntros "!> H !> !>". iNamed "H".
      iExists _; iFrame.
      iApply rblock_linv_to_cinv; iFrame. }
    { eauto with iFrame. }

    iModIntro.
    iExists _, _; iFrame.
  Qed.

  (* Open is the replicated block's recovery procedure, which constructs the
  in-memory state as well as recovering the synchronization between primary and
  backup, going from the crash invariant to the lock invariant. *)
  Theorem wpc_Open {k} d addr σ :
    {{{ rblock_cinv addr σ }}}
      Open (disk_val d) #addr @ (S k); ⊤
    {{{ (l:loc), RET #l; is_pre_rblock l addr σ }}}
    {{{ rblock_cinv addr σ }}}.
  Proof.
    iIntros (Φ Φc) "Hpre HΦ"; iNamed "Hpre".
    iDeexHyp "Hbackup".
    wpc_call.
    { eauto 10 with iFrame. }
    { eauto 10 with iFrame. }
    iCache with "Hprimary Hbackup HΦ".
    { crash_case. eauto 10 with iFrame. }
    (* read block content, write it to backup block *)
    wpc_pures.
    wpc_apply (wpc_Read with "Hprimary").
    iSplit; [ | iNext ].
    { iLeft in "HΦ". iModIntro. iIntros "Hprimary".
      (* Cached the wrong thing :( *)
      iApply "HΦ". eauto with iFrame. }
    iIntros (s) "(Hprimary&Hb)".
    iDestruct (is_slice_to_small with "Hb") as "Hb".
    wpc_pures.
    wpc_apply (wpc_Write' with "[$Hbackup $Hb]").
    iSplit; [ | iNext ].
    { iLeft in "HΦ". iModIntro. iIntros "[Hbackup|Hbackup]"; iApply "HΦ"; eauto with iFrame. }
    iIntros "(Hbackup&_)".
    iCache with "HΦ Hprimary Hbackup".
    { iLeft in "HΦ". iModIntro. iApply "HΦ"; eauto with iFrame. }

    (* allocate lock *)
    wpc_pures.
    wpc_bind (lock.new _).
    wpc_frame.
    wp_apply wp_new_free_lock.
    iIntros (m_ref) "Hfree_lock".
    iNamed 1.

    (* allocate struct *)
    rewrite -wpc_fupd.
    wpc_frame.
    wp_apply wp_allocStruct; auto.
    iIntros (l) "Hrb".
    iNamed 1.

    (* ghost allocation *)
    iDestruct (struct_fields_split with "Hrb") as "(d&addr&m&_)".
    iMod (readonly_alloc_1 with "d") as "d".
    iMod (readonly_alloc_1 with "addr") as "addr".
    iMod (readonly_alloc_1 with "m") as "m".
    iModIntro.
    iApply "HΦ".
    rewrite /is_pre_rblock; eauto with iFrame.
  Qed.

  (* this is an example of a small helper function which needs only a WP spec
  since the spec does not talk about durable state. *)
  Theorem wp_RepBlock__readAddr addr l (primary: bool) :
    {{{ readonly (l ↦[RepBlock :: "addr"] #addr) }}}
      RepBlock__readAddr #l #primary
    {{{ (a: u64), RET #a; ⌜a = addr ∨ a = word.add addr 1⌝ }}}.
  Proof.
    iIntros (Φ) "#addr HΦ".
    wp_call.
    wp_if_destruct.
    - wp_loadField.
      iApply "HΦ"; auto.
    - wp_loadField.
      wp_pures.
      iApply "HΦ"; auto.
  Qed.

  Lemma wpc_RepBlock__Read {k} {k' l} addr (primary: bool) :
    (S k ≤ k')%nat →
    ⊢ {{{ "Hrb" ∷ is_rblock (S k') l addr }}}
      <<{ ∀∀ σ, ▷ P σ }>>
        RepBlock__Read #l #primary @ (S k); ⊤
      <<{ ▷ P σ }>>
      {{{ s, RET (slice_val s); is_block s 1 σ }}}
      {{{ True }}}.
  Proof.
    iIntros (? Φ Φc HL) "!# Hpre Hfupd"; iNamed "Hpre".
    iNamed "Hrb".
    iNamed "Hro_state".
    wpc_call; [done..|].
    iEval (rewrite ->(left_id True bi_wand)%I) in "Hfupd".
    iCache with "Hfupd"; first by crash_case. (* after we stripped the later, cache proof *)
    wpc_pures.
    wpc_frame_seq.
    wp_loadField.
    wp_apply (crash_lock.acquire_spec with "Hlock"); first by auto.
    iIntros "His_locked"; iNamed 1.
    wpc_pures.
    wpc_bind (RepBlock__readAddr _ _); wpc_frame.
    wp_apply (wp_RepBlock__readAddr with "addr").
    iIntros (addr' Haddr'_eq).
    iNamed 1.

    wpc_bind_seq.
    crash_lock_open "His_locked".
    iDestruct 1 as (σ) "(>Hlkinv&HP)".
    iMod (fupd_later_to_disc with "HP") as "HP".
    iNamed "Hlkinv".
    iApply ncfupd_wpc.
    iSplit.
    { iLeft in "Hfupd". do 2 iModIntro. iFrame. iExists _; iFrame.
      iApply rblock_linv_to_cinv; iFrame. }
    iAssert (int.Z addr' d↦ σ ∗
                   <bdisc> (int.Z addr' d↦ σ -∗ rblock_linv addr σ))%I
      with "[Hlkinv]" as "(Haddr'&Hlkinv)".
    { iNamed "Hlkinv".
      destruct Haddr'_eq; subst; iFrame; iModIntro; iFrame; auto. }
    iMod (own_disc_fupd_elim with "HP") as "HP".
    iRight in "Hfupd".
    iMod ("Hfupd" with "HP") as "[HP HQ]".
    iEval (rewrite ->(left_id True bi_wand)%I) in "HQ".
    iMod (fupd_later_to_disc with "HP") as "HP".
    iApply wpc_ncfupd. iModIntro.
    wpc_apply (wpc_Read with "Haddr'").
    iSplit; [ | iNext ].
    { iLeft in "HQ". iModIntro.
      iFrame. iIntros.
      iExists _; iFrame.
      iApply rblock_linv_to_cinv; iFrame. iApply "Hlkinv". eauto. }
    iIntros (s) "(Haddr'&Hb)".
    iDestruct (own_discrete_elim with "Hlkinv") as "Hlkinv".
    iDestruct (is_slice_to_small with "Hb") as "Hb".
    iMod (own_disc_fupd_elim with "HP") as "HP".
    iSpecialize ("Hlkinv" with "Haddr'"). iModIntro.
    iSplitR "HP Hlkinv"; last by eauto with iFrame.
    (* TODO: why is this the second goal?
       RALF: because use_crash_locked puts [R] to the right. *)
    iIntros "His_locked".
    iCache (<disc> Φc)%I with "HQ".
    { by iLeft in "HQ". }
    iSplit; first by iFromCache.
    wpc_pures.
    wpc_frame.

    wp_loadField.
    wp_apply (crash_lock.release_spec with "[$His_locked]"); auto.
    wp_pures.
    iModIntro. iNamed 1.
    iRight in "HQ".
    iApply "HQ"; iFrame.
  Qed.

  Theorem wpc_RepBlock__Read_triple (Q: Block → iProp Σ) (Qc: iProp Σ) `{Timeless _ Qc} {k} {k' l} addr (primary: bool) :
    (S k ≤ k')%nat →
    {{{ "Hrb" ∷ is_rblock (S k') l addr ∗ (* replicated block protocol *)
        "HQc" ∷ (∀ σ, Q σ -∗ <disc> Qc) ∗ (* crash condition after "linearization point" *)
        "Hfupd" ∷ (<disc> Qc (* crash condition before "linearization point" *) ∧
                   (∀ σ, ▷ P σ ={⊤}=∗ ▷ P σ ∗ Q σ)) }}}
      RepBlock__Read #l #primary @ (S k); ⊤
    {{{ s b, RET (slice_val s); is_block s 1 b ∗ Q b }}}
    {{{ Qc }}}.
  Proof.
    iIntros (? Φ Φc) "Hpre HΦ"; iNamed "Hpre".
    iApply (wpc_step_strong_mono _ _ _ _ _ _ _
           (λ v, ∃ s b, ⌜ v = slice_val s ⌝ ∗ is_block s 1 b ∗ Q b)%I _ _ with "[-HΦ] [HΦ]"); auto.
    2: { iSplit.
         * iNext. iIntros (?) "H". iDestruct "H" as (??) "(%&?)". subst.
           iModIntro. iRight in "HΦ". by iApply "HΦ".
         * iLeft in "HΦ".  iModIntro. iIntros. iModIntro. by iApply "HΦ". }
    iApply (wpc_RepBlock__Read with "[] [$Hrb]"); first done.
    { iPureIntro; apply _. }
    iSplit.
    { iLeft in "Hfupd". iIntros "!> _". eauto. }
    iNext. iIntros (σ) "HP". iRight in "Hfupd". iMod ("Hfupd" with "HP") as "[HP HQ]".
    iModIntro. iFrame "HP". iSplit.
    { iSpecialize ("HQc" with "[$]"). iIntros "!> _"; by iApply "HQc". }
    iIntros (s) "Hblock". iExists _, _; iSplit; first eauto; by iFrame.
  Qed.

  Lemma wpc_RepBlock__Write {k} l k' addr (s: Slice.t) q (b: Block) :
    (S k ≤ k')%nat →
    ⊢ {{{ "Hrb" ∷ is_rblock (S k') l addr ∗
          "Hb" ∷ is_block s q b }}}
      <<{ ∀∀ σ, ▷ P σ }>>
        RepBlock__Write #l (slice_val s) @ (S k); ⊤
      <<{ ▷ P b }>>
      {{{ RET #(); is_block s q b }}}
      {{{ True }}}.
  Proof.
    iIntros (? Φ Φc HL) "!# Hpre Hfupd"; iNamed "Hpre".
    iNamed "Hrb".
    iNamed "Hro_state".
    wpc_call; [done..|].
    iEval (rewrite ->(left_id True bi_wand)%I) in "Hfupd".
    iCache with "Hfupd"; first by crash_case.
    wpc_pures.
    wpc_frame_seq.
    wp_loadField.
    wp_apply (crash_lock.acquire_spec with "Hlock"); first by auto.
    iIntros "His_locked".
    iNamed 1.

    wpc_pures.
    wpc_bind_seq.
    crash_lock_open "His_locked".
    iDestruct 1 as (σ) "(>Hlkinv&HP)".
    iNamed "Hlkinv".
    iNamed "Hlkinv".
    iMod (fupd_later_to_disc with "HP") as "HP".
    iCache with "HP Hprimary Hbackup Hfupd".
    { iLeft in "Hfupd". eauto 10 with iFrame. }

    (* call to (lower-case) write, doing the actual writes *)
    wpc_call.
    wpc_loadField.
    (* first write *)
    (* This is an interesting example illustrating crash safety - notice that we
    produce [Q] atomically during this Write. This is the only valid simulation
    point in this example, because if we crash the operation has logically
    occurred due to recovery.

    Also note that this is quite different from the Perennial example which
    requires helping due to the possibility of losing the first disk block
    between crash and recovery - the commit cannot happen until recovery
    succesfully synchronizes the disks. *)
    wpc_apply (wpc_Write_ncfupd ⊤ with "Hb").
    iModIntro. iExists _; iFrame. iIntros "!> Hprimary".
    (* linearization/simulation point: run Hfupd. *)
    iRight in "Hfupd".
    iMod (own_disc_fupd_elim with "HP") as "HP".
    iMod ("Hfupd" with "HP") as "[HP HΦ]".
    iEval (rewrite ->(left_id True bi_wand)%I) in "HΦ".
    iMod (fupd_later_to_disc with "HP") as "HP".
    iModIntro. iSplit.
    { iLeft in "HΦ". eauto 10 with iFrame. }
    iIntros "Hb".
    iCache (<disc> Φc)%I with "HΦ".
    { by iLeft in "HΦ". }

    wpc_pures.
    { iLeft in "HΦ". eauto 10 with iFrame. }
    iCache with "HΦ Hprimary Hbackup HP".
    { iLeft in "HΦ". eauto 10 with iFrame. }
    wpc_loadField.
    wpc_pures.
    iApply wpc_fupd.
    (* second write *)
    wpc_apply (wpc_Write' with "[$Hb Hbackup]").
    { iFrame. }
    iSplit; [ | iNext ].
    { iLeft in "HΦ". iModIntro.
      iIntros "[Hbackup|Hbackup]"; eauto 10 with iFrame.
    }
    iIntros "(Hbackup&Hb)".
    iSplitR "Hprimary Hbackup HP"; last first.
    { iMod (own_disc_fupd_elim with "HP"). eauto with iFrame. }
    iIntros "!> His_locked".
    iSplit; first iFromCache.
    wpc_pures.
    wpc_frame.
    wp_loadField.
    wp_apply (crash_lock.release_spec with "[$His_locked]"); auto.
    iNamed 1.
    iApply "HΦ"; iFrame.
  Qed.

  Theorem wpc_RepBlock__Write_triple (Q: iProp Σ) (Qc: iProp Σ) `{Timeless _ Qc} {k} l k' addr (s: Slice.t) q (b: Block) :
    (S k ≤ k')%nat →
    {{{ "Hrb" ∷ is_rblock (S k') l addr ∗
        "Hb" ∷ is_block s q b ∗
        "HQc" ∷ (Q -∗ <disc> Qc) ∗
        "Hfupd" ∷ (<disc> Qc ∧ (∀ σ, ▷ P σ ={⊤}=∗ ▷ P b ∗ Q)) }}}
      RepBlock__Write #l (slice_val s) @ (S k); ⊤
    {{{ RET #(); Q ∗ is_block s q b }}}
    {{{ Qc }}}.
  Proof.
    iIntros (? Φ Φc) "Hpre HΦ"; iNamed "Hpre".
    iApply (wpc_step_strong_mono _ _ _ _ _ _ _
           (λ v, ⌜ v = #()⌝ ∗ Q ∗ is_block s q b)%I _ _ with "[-HΦ] [HΦ]"); auto.
    2: { iSplit.
         * iNext. iIntros (?) "H". iDestruct "H" as "(%&?)". subst.
           iModIntro. iRight in "HΦ". by iApply "HΦ".
         * iLeft in "HΦ".  iModIntro. iIntros. iModIntro. by iApply "HΦ". }
    iApply (wpc_RepBlock__Write with "[] [$Hrb $Hb //]"); first done.
    { iPureIntro; apply _. }
    iFrame. iSplit.
    { iLeft in "Hfupd". by iIntros "!> _". }
    iNext. iIntros (σ) "HP". iRight in "Hfupd". iMod ("Hfupd" with "HP") as "[HP HQ]".
    iModIntro. iFrame "HP". iSplit.
    { iSpecialize ("HQc" with "[$]"). by iIntros "!> _". }
    iIntros "Hblock". iSplit; first eauto. iFrame.
  Qed.

  (* Silly example client *)
  Definition OpenRead d (addr: u64) : expr :=
    (let: "l" := Open (disk_val d) #addr in
     RepBlock__Read "l" #true).

  Theorem wpc_OpenRead d addr σ:
    {{{ rblock_cinv addr σ ∗ P σ }}}
      OpenRead d addr @ 2; ⊤
    {{{ (x: val), RET x; True }}}
    {{{ ∃ σ, rblock_cinv addr σ ∗ ▷ P σ }}}.
  Proof using stagedG0.
    rewrite /OpenRead.
    iIntros (??) "(H&HP) HΦ".
    wpc_bind (Open _ _).
    iAssert (▷ P σ)%I with "[HP]" as "HP"; first by eauto.
    iMod (fupd_later_to_disc with "HP") as "HP".
    wpc_apply (wpc_Open with "H").
    iSplit.
    { iLeft in "HΦ". iModIntro. iIntros "H". iApply "HΦ". eauto with iFrame. }
    iNext. iIntros (?) "Hpre".
    iMod (own_disc_fupd_elim with "HP") as "HP".
    iMod (replicated_block_cfupd 1 with "Hpre HP") as "(#Hrblock&Hcfupd)".
    (* Here is the use of the cfupd to cancel out the rblock_cinv from crash condition,
       which is important because RepBlock__Read doesn't guarantee rblock_cinv! *)
    iApply wpc_cfupd.
    iMod "Hcfupd" as "_".
    iCache with "HΦ".
    { iLeft in "HΦ". iModIntro. iDestruct 1 as (?) "(>?&?)". iIntros. iApply "HΦ".
      iExists _. by iFrame. }
    wpc_pures.
    (* Weaken the levels. *)
    iApply (wpc_idx_mono 1); first lia.
    iApply (wpc_step_strong_mono _ _ _ _ _ _ _
           (λ v, True)%I _ True
              with "[-HΦ] [HΦ]"); auto.
    2: { iSplit.
         * iNext. iIntros (?) "H". iModIntro. iRight in "HΦ". by iApply "HΦ".
         * iLeft in "HΦ".  iModIntro. 
           iIntros. iModIntro.  
           iDestruct 1 as (?) "(>?&?)". iIntros. iApply "HΦ".
           iExists _. by iFrame. }
    wpc_apply (wpc_RepBlock__Read with "[] Hrblock").
    { lia. }
    { iPureIntro; apply _. }
    iSplit.
    { iIntros "!> _". done. }
    iIntros "!> * ?". iModIntro. iFrame "# ∗".
    rewrite left_id.
    iSplit; eauto.
  Qed.

End goose.

Typeclasses Opaque rblock_cinv.

(* rblock_cinv is durable *)
Instance rblock_crash `{!heapG Σ} addr σ :
  IntoCrash (rblock_cinv addr σ) (λ _, rblock_cinv addr σ).
Proof.
  rewrite /IntoCrash /rblock_cinv. iIntros "?".
  iCrash. iFrame.
Qed.

Section recov.
  Context `{!heapG Σ}.
  Context `{!stagedG Σ}.

  (* This has to be in a separate section from the wpc lemmas because we will
     use different heapG instances after crash *)

  (* Just a simple example of using idempotence *)
  Theorem wpr_Open d addr σ:
    rblock_cinv addr σ -∗
    wpr NotStuck 2 ⊤
        (Open (disk_val d) #addr)
        (Open (disk_val d) #addr)
        (λ _, True%I)
        (λ _, True%I)
        (λ _ _, True%I).
  Proof.
    iIntros "Hstart".
    iApply (idempotence_wpr _ (S (S O)) ⊤ _ _ _ _ _ (λ _, ∃ σ, rblock_cinv addr σ)%I with "[Hstart]").
    { wpc_apply (wpc_Open with "Hstart"). eauto 10. }
    iModIntro. iIntros (?????) "H".
    iDestruct "H" as (σ'') "Hstart".
    iNext. iCrash.
    iIntros.
    iSplit; first done.
    wpc_apply (wpc_Open with "Hstart").
    eauto 10.
  Qed.

  Theorem wpr_OpenRead d addr σ:
    rblock_cinv addr σ -∗
    wpr NotStuck 2 ⊤
        (OpenRead d addr)
        (OpenRead d addr)
        (λ _, True%I)
        (λ _, True%I)
        (λ _ _, True%I).
  Proof using stagedG0.
    iIntros "Hstart".
    iApply (idempotence_wpr _ 2 ⊤ _ _ _ _ _ (λ _, ∃ σ, rblock_cinv addr σ ∗ True)%I with "[Hstart]").
    { wpc_apply (wpc_OpenRead (λ _, True)%I with "[$Hstart]").
      iSplit; eauto. iModIntro. iDestruct 1 as (?) "(H&_)". iExists _. iFrame. }
    iModIntro. iIntros (?????) "H".
    iDestruct "H" as (σ'') "(Hstart&_)".
    iNext. iCrash.
    iIntros (?).
    iSplit; first done.
    wpc_apply (wpc_OpenRead (λ _, True)%I with "[$Hstart] []").
    { iSplit; eauto. iModIntro. iDestruct 1 as (?) "(H&_)". iExists _. iFrame. }
  Qed.
End recov.

Existing Instances subG_stagedG.

Definition repΣ := #[stagedΣ; heapΣ; crashΣ].

Lemma ffi_start_OpenRead σ addr g (d : ()) {hG: heapG repΣ} :
  int.Z addr ∈ dom (gset Z) (σ.(world) : (@ffi_state disk_model)) →
  int.Z (word.add addr 1) ∈ dom (gset Z) (σ.(world) : (@ffi_state disk_model)) →
  ffi_local_start heapG_ffiG σ.(world) g
  -∗ wpr NotStuck 2 ⊤ (OpenRead d addr) (OpenRead d addr) (λ _ : goose_lang.val, True)
       (λ _, True) (λ _ _, True).
Proof.
  rewrite ?elem_of_dom.
  intros (d1&Hin1) (d2&Hin2).
  iIntros "Hstart".
  iApply wpr_OpenRead.
  rewrite /ffi_local_start//=.
  rewrite /rblock_cinv.
  iDestruct (big_sepM_delete _ _ (int.Z addr) with "Hstart") as "(Hd1&Hmap)"; first eapply Hin1.
  iDestruct (big_sepM_delete _ _ (int.Z (word.add addr 1)) with "Hmap") as "(Hd2&Hmap)".
  { rewrite lookup_delete_ne //=.
    apply word_add1_neq. }
  iFrame. iExists _. iFrame.
Qed.

Theorem OpenRead_adequate σ g addr :
  (* We assume the addresses we replicate are in the disk domain *)
  int.Z addr ∈ dom (gset Z) (σ.(world) : (@ffi_state disk_model)) →
  int.Z (word.add addr 1) ∈ dom (gset Z) (σ.(world) : (@ffi_state disk_model)) →
  recv_adequate (CS := goose_crash_lang) NotStuck (OpenRead () addr) (OpenRead () addr)
                σ g (λ v _ _, True) (λ v _ _, True) (λ _ _, True).
Proof.
  intros.
  apply (heap_recv_adequacy (repΣ) _ 2 _ _ _ _ _ _ _ (λ _, True)%I).
  { simpl. auto. }
  { simpl. auto. }
  iIntros (?) "Hstart _ _".
  iModIntro.
  iSplitL "".
  { iModIntro; iIntros. iMod (fupd_mask_subseteq ∅); eauto. }
  iSplitL "".
  { iModIntro; iIntros. iModIntro. iMod (fupd_mask_subseteq ∅); eauto. }
  iApply (ffi_start_OpenRead); eauto.
Qed.

(* Trivial example showing we can run OpenRead on two nodes safely.
   (Unsurprisingly, since there's no interaction... *)


Definition OpenRead_init_cfg dref addr σ :=
  {| init_thread := OpenRead dref addr;
     init_restart := OpenRead dref addr;
     init_local_state := σ |}.

Theorem OpenRead_dist_adequate σ g addr :
  (* We assume the addresses we replicate are in the disk domain *)
  int.Z addr ∈ dom (gset Z) (σ.(world) : (@ffi_state disk_model)) →
  int.Z (word.add addr 1) ∈ dom (gset Z) (σ.(world) : (@ffi_state disk_model)) →
  dist_adequate (CS := goose_crash_lang)
                [OpenRead_init_cfg () addr σ;
                 OpenRead_init_cfg () addr σ]
                g (λ _, True).
Proof.
  intros.
  apply (heap_dist_adequacy_alt (repΣ) 2 _ _ _).
  { simpl. auto. }
  { simpl. auto. }
  iIntros (?) "_". iModIntro.
  iSplitL ""; last first.
  { iMod (fupd_mask_subseteq ∅); eauto. }
  rewrite ?big_sepL_cons big_sepL_nil.
  iSplitL "".
  { iIntros (? Heq ?) "(H&_&_)". iModIntro. iExists _, _, _.
    iApply (ffi_start_OpenRead with "[-]"); eauto. }
  iSplitL ""; last done.
  { iIntros (? Heq ?) "(H&_&_)". iModIntro. iExists _, _, _.
    iApply (ffi_start_OpenRead with "[-]"); eauto. }
Qed.
