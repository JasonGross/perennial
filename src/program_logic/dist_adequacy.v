From iris.proofmode Require Import tactics.
From iris.algebra Require Import gmap auth agree gset coPset.
From Perennial.base_logic.lib Require Import wsat.
From Perennial.program_logic Require Export weakestpre.
From Perennial.program_logic Require Export crash_lang recovery_weakestpre dist_weakestpre.
From Perennial.program_logic Require Import crash_adequacy.
Import uPred.

Set Default Proof Using "Type".

Section distributed_adequacy.
Context `{!perennialG Λ CS T Σ}.
Context `{!groveG Λ CS Σ}.

Context (mj: nat).
(* The IH of the theorems here requires working with some fixed choice of mj in the wpc0 form,
   instead of wpc. So, we introduce here a notation to insert the mj explicitly to porting these proofs easier *)
Local Notation "'WPC' e @ k ; E1 {{ Φ } } {{ Φc } }" := (wpc0 NotStuck k%nat mj E1 e%E Φ Φc)
  (at level 20, e, Φ, Φc at level 200, only parsing) : bi_scope.
Local Notation "'WPC' e @ s ; k ; E1 {{ Φ } } {{ Φc } }" := (wpc0 s k%nat mj E1 e%E Φ Φc)
  (at level 20, e, Φ, Φc at level 200, only parsing) : bi_scope.
Local Notation "'WPC' e @ s ; k ; E1 {{ Φ } } {{ Φc } }" := (wpc0 s k%nat mj E1 e%E Φ Φc)
  (at level 20, e, Φ, Φc at level 200, only parsing) : stdpp_scope.

Implicit Types s : stuckness.
Implicit Types k : nat.
Implicit Types P : iProp Σ.
Implicit Types Φ : val Λ → iProp Σ.
Implicit Types Φinv : crashG Σ → pbundleG T Σ → iProp Σ.
Implicit Types Φc : crashG Σ → pbundleG T Σ → val Λ → iProp Σ.
Implicit Types v : val Λ.
Implicit Types e : expr Λ.

Definition wptp (ct : crashG Σ * pbundleG T Σ) s k tpool :=
  let Hc := fst ct in
  let t := snd ct in
  ([∗ list] ef ∈ tpool, WPC ef @ s; k; ⊤ {{ fork_post }} {{ True }})%I.

Definition wpnode (ct : crashG Σ * pbundleG T Σ) k (dn: dist_node) :=
  (□ equal_global_inG ct ∗
  match tpool dn with
  | [] => False%I
  | e :: tp =>
    ∃ Φ Φinv Φr,
    wpr0 NotStuck k mj (fst ct) (snd ct) ⊤ e (boot dn) Φ Φinv Φr ∗
    wptp ct NotStuck k tp
  end)%I.

Definition stwpnode (ct : crashG Σ * pbundleG T Σ) k (dn: dist_node) : iProp Σ :=
  (let Hc := fst ct in
   let t := snd ct in
   state_interp (local_state dn) (pred (length (tpool dn))) ∗
   NC 1) ∗
  wpnode ct k dn.

Definition stwpnodes k (dns: list dist_node) : iProp Σ :=
  [∗ list] dn ∈ dns, ∃ ct, stwpnode ct k dn.

Existing Instance grove_invG | 0.

Lemma stwpnode_step ct k eb t1 σ1 g1 t2 σ2 g2 κ κs ns:
  step (t1, (σ1,g1)) κ (t2, (σ2,g2)) →
  grove_global_state_interp g1 ns (κ ++ κs) -∗
  stwpnode ct k {| boot := eb; tpool := t1; local_state := σ1 |} -∗
  |={⊤,∅}=> |={∅}▷=>^(S $ grove_num_laters_per_step ns) |={∅, ⊤}=>
  grove_global_state_interp g2 (S ns) κs ∗
  stwpnode ct k {| boot := eb; tpool := t2; local_state := σ2 |}.
Proof.
  iIntros (Hstep) "Hg Hnode".
  destruct ct as (Hc&t).
  iDestruct "Hnode" as "((Hσ&HNC)&(#Hequal&Hwptp))".
  iDestruct "Hequal" as ((Hnum&Hinv)) "Hglobal".
  destruct t1; first done. simpl.
  rewrite -Hnum -Hinv.
  iDestruct "Hwptp" as (Φ Φinv Φr) "(Hwpr&Hwptp)".
  iPoseProof (crash_adequacy.wptp_step with "[$Hσ] [Hg] [Hwpr] [Hwptp] [HNC]") as "H"; eauto.
  { iApply "Hglobal". eauto. }
  { rewrite wpr0_unfold/wpr0_pre. eauto. }
  { rewrite perennial_crashG. iFrame. }
  iMod "H" as (e2 t2' ->) "H".
  iMod "H". iModIntro. simpl. iMod "H". iModIntro. iNext.
  iApply (step_fupdN_wand with "H"). iIntros "H".
  iMod "H" as "(Hσ&Hg&Hwpr&Hwptp&HNC)".
  iFrame. iModIntro.
  iSplitL "Hg".
  { iApply "Hglobal". eauto. }
  iSplitL "HNC".
  { rewrite perennial_crashG. iFrame. }
  iSplit.
  { iModIntro. iSplit; first done. eauto. }
  simpl. iExists Φ, Φinv, Φr.
  rewrite wpr0_unfold/wpr0_pre. eauto.
Qed.

Lemma stwpnode_crash ct k eb t1 σ1 g σ2 κs ns:
  crash_prim_step CS σ1 σ2 →
  grove_global_state_interp g ns κs -∗
  stwpnode ct k {| boot := eb; tpool := t1; local_state := σ1 |} -∗
  |={⊤}=> ▷ |={⊤}=> ∃ ct',
  grove_global_state_interp g (S ns) κs ∗
  stwpnode ct' k {| boot := eb; tpool := [eb]; local_state := σ2 |}.
Proof.
  iIntros (Hstep) "Hg Hnode".
  destruct ct as (Hc&t).
  iDestruct "Hnode" as "((Hσ&HNC)&(#Hequal&Hwptp))".
  iDestruct "Hequal" as ((Hnum&Hinv)) "Hglobal".
  destruct t1; first done. simpl.
  rewrite -Hinv.
  iDestruct "Hwptp" as (Φ Φinv Φr) "(Hwpr&Hwptp)".
  iMod (NC_upd_C with "HNC") as "#HC".
  rewrite wpr0_unfold/wpr0_pre.
  iMod (wpc0_crash with "Hwpr") as "H".
  iMod (own_disc_fupd_elim with "H") as "H".
  iSpecialize ("H" with "[HC]").
  { rewrite perennial_crashG. iFrame "#". }
  iMod (fupd_split_level_fupd with "H") as "H".
  iMod ("H" with "[//] [$] [Hg]") as "H".
  { iApply "Hglobal". eauto. }
  iModIntro. iNext. iClear "HC".
  unshelve (iMod NC_alloc as (Hc') "HNC").
  { destruct Hc. constructor. apply _. }
  iSpecialize ("H" with "HNC").
  rewrite (perennial_inv_crashG Hc' Hc) Hinv.
  iMod "H".
  iDestruct "H" as (t' Heq1) "(#Heq&Hσ&Hg&(_&Hwpr)&HNC)".
  rewrite -Heq1.
  iModIntro.
  iFrame.
  iExists (Hc', t'). iFrame.
  iSplitL "Hg".
  { iApply "Hglobal". iApply "Heq". eauto. }
  rewrite /wpnode/=.
  iSplit.
  { iModIntro. iSplit.
    { iPureIntro. split_and!; eauto.
     rewrite -Hnum ?perennial_num_laters_per_step_spec //. }
    { iIntros. iSplit.
      - iIntros. iApply "Hglobal". iApply "Heq". eauto.
      - iIntros. iApply "Heq". iApply "Hglobal". eauto.
    }
  }
  iExists _, _, _. iFrame. rewrite /wptp. rewrite big_sepL_nil. eauto.
Qed.

Lemma stwpnodes_step k dns1 g1 ns dns2 g2 κ κs :
  dist_step (CS := CS) (dns1, g1) κ (dns2, g2) →
  grove_global_state_interp g1 ns (κ ++ κs) -∗
  stwpnodes k dns1 -∗
  |={⊤,∅}=> |={∅}▷=>^(S $ grove_num_laters_per_step ns) |={∅, ⊤}=>
  grove_global_state_interp g2 (S ns) κs ∗
  stwpnodes k dns2.
Proof.
  iIntros (Hstep) "Hg Hnodes".
  inversion Hstep as [ρ1 κs' ρ2 m eb t1 σ1 t2 σ2 Hlookup1 Hlookup2 Hprim |
                      ρ1 ρ2 m eb σ1 σ2 tp Hlookup1 Heq1 Heq2 Hcrash].
  - subst. rewrite /stwpnodes.
    iDestruct (big_sepL_insert_acc with "Hnodes") as "(Hdn&Hnodes)"; first eassumption.
    iDestruct "Hdn" as (ct) "Hdn".
    iDestruct (stwpnode_step with "[$] [$]") as "H"; first eassumption.
    iApply (step_fupdN_inner_wand with "H"); auto.
    iIntros "($&Hnode)".
    simpl in Hlookup2. rewrite Hlookup2.
    iApply "Hnodes". iExists _. eauto.
  - subst. rewrite /stwpnodes.
    iDestruct (big_sepL_insert_acc with "Hnodes") as "(Hdn&Hnodes)"; first eassumption.
    iDestruct "Hdn" as (ct) "Hdn".
    iDestruct (stwpnode_crash with "[$] [$]") as "H"; first eassumption.
    iMod "H".
    iApply step_fupdN_inner_later'. iNext. iNext.
    iMod "H" as (ct') "(Hg&Hnode)". rewrite app_nil_l.
    simpl in Heq2. rewrite Heq2. iFrame.
    iModIntro.
    simpl in Heq1. rewrite Heq1.
    iApply "Hnodes". iExists _. eauto.
Qed.

Local Fixpoint steps_sum (num_laters_per_step : nat → nat) (start ns : nat) : nat :=
  match ns with
  | O => 0
  | S ns =>
    S $ num_laters_per_step start + steps_sum num_laters_per_step (S start) ns
  end.

Lemma stwpnodes_steps n k dns1 g1 ns dns2 g2 κs κs' :
  dist_nsteps (CS := CS) n (dns1, g1) κs (dns2, g2) →
  grove_global_state_interp g1 ns (κs ++ κs') -∗
  stwpnodes k dns1 -∗
  |={⊤,∅}=> |={∅}▷=>^(steps_sum grove_num_laters_per_step ns n) |={∅, ⊤}=>
  grove_global_state_interp g2 (n + ns) κs' ∗
  stwpnodes k dns2.
Proof.
  revert dns1 dns2 κs κs' g1 ns g2.
  induction n as [|n IH]=> dns1 dns2 κs κs' g1 ns g2 /=.
  { inversion_clear 1; iIntros "? ?" => /=.
    iFrame. by iApply fupd_mask_subseteq. }
  iIntros (Hsteps) "Hσ He". inversion_clear Hsteps as [|?? [t1' σ1']].
  rewrite -(assoc_L (++)) Nat_iter_add plus_n_Sm.
  iDestruct (stwpnodes_step with "Hσ He") as ">H"; first eauto; simplify_eq.
  iModIntro. iApply step_fupdN_S_fupd. iApply (step_fupdN_wand with "H").
  iIntros ">(Hσ & He)". iMod (IH with "Hσ He") as "IH"; first done. iModIntro.
  iApply (step_fupdN_wand with "IH"). iIntros ">IH".
  iDestruct "IH" as "[??]".
  by eauto with iFrame.
Qed.

Lemma stwpnodes_strong_adequacy n k dns1 g1 ns dns2 g2 κs κs' :
  dist_nsteps (CS := CS) n (dns1, g1) κs (dns2, g2) →
  grove_global_state_interp g1 ns (κs ++ κs') -∗
  stwpnodes k dns1 -∗
  |={⊤,∅}=> |={∅}▷=>^(steps_sum grove_num_laters_per_step ns n) |={∅, ⊤}=>
  (▷^(S (S (grove_num_laters_per_step (n + ns))))
      (⌜ ∀ dn e, dn ∈ dns2 → e ∈ tpool dn → not_stuck e (local_state dn) g2 ⌝)) ∗
  grove_global_state_interp g2 (n + ns) κs' ∗
  stwpnodes k dns2.
Proof.
  iIntros (Hstep) "Hg Ht".
  iMod (stwpnodes_steps with "Hg Ht") as "Hgt"; first done.
  iModIntro. iApply (step_fupdN_wand with "Hgt").
  iMod 1 as "(Hg & Ht)".
  iMod (fupd_plain_keep_l ⊤
    (▷^(S (S (grove_num_laters_per_step (n + ns))))
      (⌜ ∀ dn e, dn ∈ dns2 → e ∈ tpool dn → not_stuck e (local_state dn) g2 ⌝))%I
    (grove_global_state_interp g2 (n + ns) κs' ∗
    stwpnodes k dns2)%I
    with "[$Hg $Ht]") as "(Hsafe&Hg&Ht)".
  { iIntros "(Hg & Ht)" (dn e' Hin1 Hin2).
    rewrite /stwpnodes.
    eapply elem_of_list_lookup_1 in Hin1 as (i&Hlookup1).
    iDestruct (big_sepL_lookup with "Ht") as "Hdn"; first eassumption.
    iDestruct "Hdn" as (ct) "Hnode".
    rewrite /stwpnode.
    iDestruct "Hnode" as "((Hσ&HNC)&(#Heq&Hwptp))".
    rewrite /wpnode. destruct (tpool dn) as [| hd tp]; first done.
    iDestruct "Hwptp" as (???) "(Hwpr&Ht)".
    apply elem_of_cons in Hin2 as [<-|(t1''&t2''&->)%elem_of_list_split].
    - rewrite wpr0_unfold/wpr0_pre.
      iDestruct "Heq" as ((Hnum&Hinv)) "Hglobal".
      rewrite -Hnum -Hinv.
      iPoseProof (wpc_safe with "Hσ [Hg] Hwpr") as "H".
      { iApply "Hglobal". eauto. }
      rewrite ncfupd_eq.
      iMod ("H" with "[HNC]") as "($&_)"; last done.
      { rewrite perennial_crashG. iFrame. }
    - iDestruct "Ht" as "(_ & He' & _)".
      iDestruct "Heq" as ((Hnum&Hinv)) "Hglobal".
      rewrite -Hnum -Hinv.
      iPoseProof (wpc_safe with "Hσ [Hg] He'") as "H".
      { iApply "Hglobal". eauto. }
      rewrite ncfupd_eq.
      iMod ("H" with "[HNC]") as "($&_)"; last done.
      { rewrite perennial_crashG. iFrame. }
  }
  iModIntro. iFrame.
Qed.

End distributed_adequacy.

Theorem wpd_strong_adequacy Σ Λ CS T `{HIPRE: !invPreG Σ} `{HCPRE: !crashPreG Σ} k ebσs g1 n κs dns2 g2 φ f :
  (∀ `{Hinv : !invG Σ} (Heq_pre: inv_inG = HIPRE),
     ⊢ |={⊤}=> ∃ (cts: list (crashG Σ * pbundleG T Σ))
         (Heq_cpre: ∀ k ct, cts !! k = Some ct → @crash_inG _ (fst ct) = @crash_inPreG _ HCPRE)
         (stateI : pbundleG T Σ → state Λ → nat → iProp Σ)
         (global_stateI : global_state Λ → nat → list (observation Λ) → iProp Σ)
         (fork_post : pbundleG T Σ → val Λ → iProp Σ) Hpf1 Hpf1' Hpf2 Hpf3,
        let _ : groveG Λ CS Σ :=
            GroveG _ _ Σ global_stateI f Hinv in
        let _ : perennialG Λ CS _ Σ :=
            PerennialG _ _ T Σ
              (λ Hc t,
               IrisG Λ Σ Hinv Hc (stateI t) (global_stateI) (fork_post t) f (Hpf1 Hc t)) Hpf1' Hpf2 f Hpf3
               in
       global_stateI g1 0 κs ∗
       ([∗ list] i ↦ ct; σ ∈ cts; init_local_state <$> ebσs,
                                  let _ := fst ct in NC 1 ∗ stateI (snd ct) σ 0) ∗
       wpd k ⊤ cts ((λ x, (init_thread x, init_restart x)) <$> ebσs) ∗
       (⌜ ∀ dn, dn ∈ dns2 → not_stuck_node dn g2 ⌝ -∗
         global_stateI g2 n [] -∗
         (* Under these assumptions, and while opening all invariants, we
         can conclude [φ] in the logic. After opening all required invariants,
         one can use [fupd_mask_subseteq] to introduce the fancy update. *)
         |={⊤,∅}=> ⌜ φ ⌝)) →
  dist_nsteps (CS := CS) n (starting_dist_cfg ebσs g1) κs (dns2, g2) →
  (* Then we can conclude [φ] at the meta-level. *)
  φ.
Proof.
  intros Hwp ?.
  apply (step_fupdN_soundness_strong _ (steps_sum f 0 n + S (S (f n)))) => Hinv HEQ.
  rewrite Nat_iter_add.
  iMod Hwp as (cts Heq_cpre stateI global_stateI fork_post) "Hwp"; first done.
  iDestruct "Hwp" as (Hpf1 Hpf1' Hpf2 Hpf3) "(Hg & Hσs & Hwp & Hφ)".
  iPoseProof (@stwpnodes_strong_adequacy _ _ _ _
               (PerennialG _ _ T Σ
                 (λ Hc t,
                  IrisG Λ Σ Hinv Hc (stateI t) (global_stateI) (fork_post t) f (Hpf1 Hc t)) Hpf1' Hpf2 f Hpf3)
               (GroveG _ _ Σ global_stateI f Hinv)
               0 n k _ _ _ _ _ _ []
    with "[Hg] [Hσs Hwp]") as "H"; first done.
  { rewrite app_nil_r /=. iExact "Hg". }
  { rewrite /stwpnodes/wpd.
    iDestruct "Hwp" as "(Heq_global&Hwp)".
    iCombine "Hσs Hwp" as "H".
    rewrite ?big_sepL2_fmap_r.
    iDestruct (big_sepL2_sep with "H") as "H".
    iApply big_sepL_fmap.
    iDestruct (big_sepL.big_sepL2_to_sepL_2 with "H") as "H".
    iApply (big_sepL.big_sepL_mono_with_pers with "Heq_global H").
    iIntros (i ρ Hlookup) "#Heq_global H".
    iDestruct "H" as (ct Hlookup') "((HNC&Hσ)&Hwp)". iExists ct.
    simpl. rewrite /stwpnode.
    rewrite /=. iFrame "HNC Hσ".
    rewrite /wpnode/=. iSplit.
    { iModIntro. iApply "Heq_global". iPureIntro. eapply elem_of_list_lookup_2; eauto. }
    iDestruct "Hwp" as (Φ Φrx Φinv) "H".
    iExists Φ, Φinv, Φrx.
    rewrite /wptp big_sepL_nil right_id.
    by iApply wpr0_wpr.
  }
  iMod "H". iModIntro.
  rewrite /grove_num_laters_per_step.
  iApply (step_fupdN_wand with "H").
  iIntros "H".
  iApply step_fupdN_S_fupd. simpl. iMod "H".
  iApply (fupd_mask_intro); first by set_solver.
  iIntros "Hclo". iNext. iModIntro.
  iApply (step_fupdN_later); first auto.
  iModIntro. iNext. iModIntro.
  rewrite Nat.add_0_r.
  iNext. iMod "Hclo".
  iDestruct "H" as "(%Hnotstuck&Hg&_)".
  iApply ("Hφ" with "[] [$]").
  { iPureIntro. intros dn Hin e Hin'. eapply Hnotstuck; eauto. }
Qed.

Record dist_adequate {Λ CS} (ρs: list (@node_init_cfg Λ)) (g : global_state Λ)
    (φinv: global_state Λ → Prop)  := {
  dist_adequate_not_stuck dns' g' dn :
   rtc (erased_dist_step (CS := CS)) (starting_dist_cfg ρs g) (dns', g') →
   dn ∈ dns' → not_stuck_node dn g';
  dist_adequate_inv dns' g' :
   rtc (erased_dist_step (CS := CS)) (starting_dist_cfg ρs g) (dns', g') →
   φinv g'
}.

Lemma dist_adequate_alt {Λ CS} ebσ g1 φinv :
  dist_adequate (Λ := Λ) (CS := CS) ebσ g1 φinv ↔ ∀ dns2 g2,
    rtc (erased_dist_step (CS := CS)) (starting_dist_cfg ebσ g1) (dns2, g2) →
      (∀ dn, dn ∈ dns2 → not_stuck_node dn g2) ∧
      (φinv g2).
Proof.
  split.
  - intros [] ???; naive_solver.
  - constructor; naive_solver.
Qed.

Corollary wpd_dist_adequacy_inv Σ Λ CS (T: ofe) `{HIPRE: !invPreG Σ} `{HCPRE: !crashPreG Σ} (k : nat)
          ebσs g φinv f:
  (∀ `{Hinv : !invG Σ} (Heq_pre: inv_inG = HIPRE) κs,
     ⊢ |={⊤}=> ∃ (cts: list (crashG Σ * pbundleG T Σ))
         (Heq_cts: ∀ k ct, cts !! k = Some ct → @crash_inG _ (fst ct) = @crash_inPreG _ HCPRE)
         (stateI : pbundleG T Σ → state Λ → nat → iProp Σ)
         (global_stateI : global_state Λ → nat → list (observation Λ) → iProp Σ)
         (fork_post : pbundleG T Σ → val Λ → iProp Σ) Hpf1 Hpf1' Hpf2 Hpf3,
        let _ : groveG Λ CS Σ :=
            GroveG _ _ Σ global_stateI f Hinv in
        let _ : perennialG Λ CS _ Σ :=
            PerennialG _ _ T Σ
              (λ Hc t,
               IrisG Λ Σ Hinv Hc (stateI t) (global_stateI) (fork_post t) f (Hpf1 Hc t)) Hpf1' Hpf2 f Hpf3
               in
       (∀ g κs ns, global_stateI g κs ns -∗ |={⊤, ∅}=> ⌜ φinv g ⌝) ∗
       ([∗ list] i ↦ ct; σ ∈ cts; init_local_state <$> ebσs, let _ := fst ct in NC 1 ∗ stateI (snd ct) σ 0) ∗
       global_stateI g 0 κs ∗
       wpd k ⊤ cts ((λ x, (init_thread x, init_restart x)) <$> ebσs)) →
  dist_adequate (CS := CS) ebσs g (λ g, φinv g).
Proof.
  intros Hwp.
  apply dist_adequate_alt.
  intros dns2 g2 Hsteps.
  apply erased_dist_steps_nsteps in Hsteps as [n [κs Hsteps]].
  eapply (wpd_strong_adequacy Σ _); [| eauto ] => ??.
  iMod Hwp as (cts Heq_cts stateI global_stateI fork_post) "Hwp"; first done.
  iDestruct "Hwp" as (Hpf1 Hpf1' Hpf2 Hpf3) "(Hφ&Hσ&Hg&Hwp)".
  iModIntro. iExists cts, Heq_cts, stateI, global_stateI, fork_post.
  iExists Hpf1, Hpf1', Hpf2, Hpf3.
  iFrame. iIntros "%Hns Hg". iMod ("Hφ" with "[$]") as %Hφ. iPureIntro; eauto.
Qed.
