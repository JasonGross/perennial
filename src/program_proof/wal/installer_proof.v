From RecordUpdate Require Import RecordSet.
From iris.algebra Require Import gset dfrac.
From Perennial.base_logic.lib Require Import mono_nat.

From Perennial.Helpers Require Import ListSubset.
From Perennial.program_proof Require Import disk_lib.
From Perennial.program_proof Require Import wal.invariant.

Section goose_lang.
Context `{!heapG Σ}.
Context `{!walG Σ}.

Implicit Types (v:val) (z:Z).
Implicit Types (γ: wal_names).
Implicit Types (s: log_state.t) (memLog: list update.t) (txns: list (u64 * list update.t)).
Implicit Types (pos: u64) (txn_id: nat).

Context (P: log_state.t -> iProp Σ).
Let N := walN.
Let innerN := walN .@ "wal".
Let circN := walN .@ "circ".

Definition in_bounds γ (a: u64): iProp Σ :=
  ∃ d,
    "Hbounddisk" ∷ is_base_disk γ d ∗
    "%Hinbounds" ∷ ⌜is_Some (d !! int.Z a)⌝.

Global Instance in_bounds_persistent γ a : Persistent (in_bounds γ a) := _.

Theorem in_bounds_valid γ σ a :
  is_base_disk γ σ.(log_state.d) -∗
  in_bounds γ a -∗ ⌜is_Some (σ.(log_state.d) !! int.Z a)⌝.
Proof.
  iIntros "Hbase Hbound".
  iNamed "Hbound".
  iDestruct (is_base_disk_agree with "Hbase Hbounddisk") as %<-.
  eauto.
Qed.

(* this is more or less big_sepM_lookup_acc, but with is_installed unfolded *)
Theorem is_installed_read_lookup {γ d txns installed_lb durable_txn_id} {a} :
  is_Some (d !! a) ->
  is_installed γ d txns installed_lb durable_txn_id -∗
  ∃ b txn_id',
    ⌜installed_lb ≤ txn_id' ≤ durable_txn_id ∧
      apply_upds (txn_upds (take (S txn_id') txns)) d !! a = Some b⌝ ∗
     a d↦ b ∗ ⌜2 + LogSz ≤ a⌝ ∗
     (a d↦ b -∗ is_installed γ d txns installed_lb durable_txn_id).
Proof.
  iIntros (Hlookup) "Hbs".
  destruct Hlookup as [b0 Hlookup].
  iNamedRestorable "Hbs".
  iDestruct (big_sepM_lookup_acc _ _ _ _ Hlookup with "Hdata") as "[Hb Hdata]".
  iApply restore_intro in "Hb".
  (* FIXME: Due to missing [IntoAnd] instances for [Restore], we cannot out [Ha_bound] into the Coq context immediately. *)
  iDestruct "Hb" as (b txn_id') "((%Hin_bounds&%Halready_installed&%Happly_upds) &Hb & Ha_bound & Hb')".
  iDestruct "Ha_bound" as "%Ha_bound".
  iDestruct (restore_elim with "Hb'") as "#Hb_restore"; iClear "Hb'".
  iExists _, txn_id'.
  iFrame "Hb".
  iSplitR.
  1: iPureIntro; eauto with lia.
  iSplitR.
  1: iPureIntro; eauto with lia.
  iIntros "Hb".
  iApply "Hbs"; iFrame.
  iApply "Hdata".
  iApply "Hb_restore".
  iFrame.
Qed.

Ltac wp_start :=
  iIntros (Φ) "Hpre HΦ";
  lazymatch goal with
  | |- context[Esnoc _ (INamed "HΦ") (▷ ?Q)%I] =>
    set (post:=Q)
  end;
  lazymatch iTypeOf "Hpre" with
  | Some (_, named _ _ ∗ _)%I => iNamed "Hpre"
  | Some (_, named _ _)%I => iNamed "Hpre"
  | _ => idtac
  end.

Lemma sliding_set_mutable_start f (σ: slidingM.t) :
  slidingM.start (set slidingM.mutable f σ) = slidingM.start σ.
Proof. by destruct σ. Qed.

Lemma is_durable_txn_bound γ cs txns diskEnd_txn_id durable_lb :
  is_durable_txn (Σ:=Σ) γ cs txns diskEnd_txn_id durable_lb -∗
  ⌜(diskEnd_txn_id < length txns)%nat⌝.
Proof.
  iNamed 1.
  iPureIntro.
  apply is_txn_bound in Hend_txn; lia.
Qed.

Theorem wp_Walog__ReadInstalled (Q: Block -> iProp Σ) l γ dinit a :
  {{{ is_wal P l γ dinit ∗
      in_bounds γ a ∗
       (∀ σ σ' b,
         ⌜wal_wf σ⌝ -∗
         ⌜relation.denote (log_read_installed a) σ σ' b⌝ -∗
         (P σ -∗ |NC={⊤ ∖↑ N}=> P σ' ∗ Q b))
   }}}
    Walog__ReadInstalled #l #a
  {{{ bl, RET slice_val bl; ∃ b, is_block bl 1 b ∗ Q b}}}.
Proof.
  iIntros (Φ) "(#Hwal & #Ha_valid & Hfupd) HΦ".
  wp_call.
  wp_apply wp_Read_atomic.
  iDestruct "Hwal" as "[Hwal Hcirc]".
  iInv "Hwal" as (σ) "[Hinner HP]" "Hclose".
  iDestruct "Hinner" as "(>? & ? & ? & >? & >Hdisk)"; iNamed.
  iNamed "Hdisk".
  iNamed "Hdisk".
  iNamed "Hdisk".

  iDestruct (in_bounds_valid _ σ with "Hbasedisk Ha_valid") as %Hlookup.
  iDestruct (is_installed_read_lookup Hlookup with "Hinstalled") as
      (b txn_id) "(%Htxn_id&Hb&%Hbound&Hinstalled)".
  iApply ncfupd_mask_intro; first set_solver+. iIntros "HcloseE".
  iExists _; iFrame "Hb".
  iNext.
  iIntros "Hb".
  iMod "HcloseE" as "_".
  iSpecialize ("Hinstalled" with "Hb").
  iNamed "circ.start".
  fold innerN.
  iMod (fupd_mask_subseteq (⊤∖↑N)) as "HinnerN".
  { solve_ndisj. }
  iDestruct (is_durable_txn_bound with "circ.end") as %Hdurable_bound.

  iMod ("Hfupd" $! σ σ b with "[//] [] HP") as "[HP HQ]".
  { iPureIntro.
    repeat (simpl; monad_simpl).
    exists σ txn_id.
    { econstructor; eauto; lia. }
    repeat (simpl; monad_simpl).
    destruct Htxn_id as (_&Htxn_id).
    rewrite Htxn_id.
    simpl. monad_simpl.
  }
  iMod "HinnerN" as "_".
  iFrame.
  iMod ("Hclose" with "[-HQ HΦ]") as "_".
  {
    iModIntro.
    iExists _; iFrame "HP".
    iFrame.
    iSplit; auto.
    iExists _.
    iFrame "Howncs".
    iExists _, _.
    iFrame "# ∗".
    auto.
  }
  iIntros "!>" (s) "Hs".
  iApply "HΦ".
  iExists _; iFrame.
  iDestruct (is_slice_to_small with "Hs") as "$".
Qed.

Lemma txn_upds_subseteq txns1 txns2 :
  txns1 ⊆ txns2 →
  txn_upds txns1 ⊆ txn_upds txns2.
Proof.
  rewrite /txn_upds => ?.
  apply concat_respects_subseteq, list_fmap_mono; auto.
Qed.

Lemma subslice_subslice_subseteq {A} (l: list A) (s1 e1 s2 e2: nat):
  s2 ≤ s1 →
  e1 ≤ e2 →
  subslice s1 e1 l ⊆ subslice s2 e2 l.
Proof.
  intros Hs_le He_le.
  apply (iffRL (elem_of_subseteq _ _)).
  intros x Hin.
  apply elem_of_list_lookup in Hin.
  destruct Hin as (i&Hin).
  apply (elem_of_list_lookup_2 _ (s1 + i - s2)).
  pose proof (subslice_lookup_bound' _ _ _ _ _ _ Hin) as Hlookup_bound.
  rewrite subslice_lookup.
  2: lia.
  replace (s2 + (s1 + i - s2))%nat with (s1 + i)%nat by lia.
  apply subslice_lookup_some in Hin.
  assumption.
Qed.

Lemma subslice_subseteq {A} (l: list A) (s1 e1: nat):
  subslice s1 e1 l ⊆ l.
Proof.
  destruct (decide (e1 ≤ length l)).
  - rewrite {2}(subslice_complete l).
    apply subslice_subslice_subseteq; auto.
    lia.
  - rewrite subslice_take_drop.
    rewrite -> take_ge by lia.
    apply drop_subseteq.
Qed.

Lemma txns_are_in_bounds E γ start txns l dinit :
  ↑walN.@"wal" ⊆ E →
  txns_are γ start txns -∗
  is_wal P l γ dinit -∗
  |NC={E}=> ⌜Forall (λ (u: update.t), ∃ b, dinit !! int.Z u.(update.addr) = Some b) (txn_upds txns)⌝.
Proof.
  iIntros (Hmask) "#Htxns_are [Hinv _]".
  iApply (ncinv_open_persistent with "Hinv"); auto.
  iIntros "Hinner".
  iDestruct "Hinner" as (σ) "[Hinner _]".
  iDestruct "Hinner" as "(>? &_ & >? &_&_& >?)"; iNamed.
  iNamed "Hdisk".
  iNamed "Hdisk".
  iModIntro.
  iDestruct (txns_are_sound with "Htxns_ctx Htxns_are") as %Hsub.
  destruct Hwf as (Haddrs_wf&_).
  rewrite /log_state.updates in Haddrs_wf.
  iPureIntro.
  apply (Forall_subset _ _ (concat σ.(log_state.txns).*2)).
  - apply concat_respects_subseteq.
    etrans; [ | eapply subslice_subseteq ].
    apply (f_equal (λ x, x.*2)) in Hsub.
    rewrite -Hsub.
    rewrite fmap_subslice //.
  - fold (txn_upds σ.(log_state.txns)).
    rewrite /addrs_wf in Haddrs_wf.
    eapply Forall_impl; eauto.
    simpl; intros.
    destruct H as [_ [b ?]].
    apply Hdaddrs_init; eauto.
Qed.

Theorem wp_installBlocks γ l dinit (d: val) q bufs_s (bufs: list update.t)
        (being_installed_start_txn_id: nat) subtxns :
  {{{ "Hbufs_s" ∷ updates_slice_frag bufs_s q bufs ∗
      "#Hwal" ∷ is_wal P l γ dinit ∗
      "%Hbufs" ∷ ⌜has_updates bufs subtxns⌝ ∗
      "Halready_installed_installer" ∷ ghost_var γ.(already_installed_name) (1/2) (∅: gset Z) ∗
      "HownBeingInstalledStartTxn_installer" ∷ mono_nat_auth_own γ.(being_installed_start_txn_name) (1/2) being_installed_start_txn_id ∗
      "HownBeingInstalledEndTxn_installer" ∷ ghost_var γ.(being_installed_end_txn_name) (1/2) (being_installed_start_txn_id + length subtxns)%nat ∗
      "#Hsubtxns" ∷ txns_are γ (S being_installed_start_txn_id) subtxns
  }}}
    installBlocks d (slice_val bufs_s)
  {{{ RET #();
      "#Hwal" ∷ is_wal P l γ dinit ∗
      "Halready_installed_installer" ∷ ghost_var γ.(already_installed_name) (1/2) (list_to_set (C:=gset Z) ((λ u, int.Z (update.addr u)) <$> bufs)) ∗
      "HownBeingInstalledStartTxn_installer" ∷ mono_nat_auth_own γ.(being_installed_start_txn_name) (1/2) being_installed_start_txn_id ∗
      "HownBeingInstalledEndTxn_installer" ∷ ghost_var γ.(being_installed_end_txn_name) (1/2) (being_installed_start_txn_id + length subtxns)%nat
  }}}.
Proof.
  wp_start.
  wp_call.

  iMod (txns_are_in_bounds with "Hsubtxns [$]") as %Htxns_addrs; first auto.
  assert (Forall (λ u : update.t, ∃ (b: Block), dinit !! int.Z u.(update.addr) = Some b) bufs) as Hbufs_addrs.
  { eapply has_updates_addrs in Hbufs.
    move: Htxns_addrs.
    change (λ u, ∃ b, dinit !! int.Z u.(update.addr) = Some b) with
      ((λ a, ∃ b, dinit !! a = Some b) ∘ (λ u, int.Z u.(update.addr))).
    intros.
    rewrite -Forall_fmap.
    apply Forall_fmap in Htxns_addrs.
    eapply Forall_subset; eauto. }

  wp_apply (wp_absorbBufs with "Hbufs_s").
  iIntros (bks_s upds) "Hpost".
  iNamed "Hpost".
  apply (apply_upds_equiv_implies_has_updates_equiv _ _ _ Hsame_upds) in Hbufs.
  pose proof (equiv_upds_addrs_subseteq _ _ (Hsame_upds ∅)) as Hupds_subseteq.

  wp_pures.
  iDestruct "Habsorbed" as (bks) "(Hbks_s&Hupds)".
  iDestruct (is_slice_to_small with "Hbks_s") as "Hbks_s".
  iDestruct (slice.is_slice_small_sz with "Hbks_s") as %Hslen.
  rewrite fmap_length in Hslen.
  iDestruct (big_sepL2_length with "Hupds") as %Hslen2.

  wp_apply (slice.wp_forSlice (fun i =>
    ("Hupds" ∷ [∗ list] uv;upd ∈ bks;upds, is_update uv q upd) ∗
      "Halready_installed_installer" ∷ ghost_var γ.(already_installed_name) (1/2) (list_to_set (C:=gset Z) (take (int.nat i) ((λ u, int.Z (update.addr u)) <$> upds))) ∗
      "HownBeingInstalledStartTxn_installer" ∷ mono_nat_auth_own γ.(being_installed_start_txn_name) (1/2) being_installed_start_txn_id ∗
      "HownBeingInstalledEndTxn_installer" ∷ ghost_var γ.(being_installed_end_txn_name) (1/2) (being_installed_start_txn_id + length subtxns)%nat
    )%I with "[] [$Hbks_s Hupds $Halready_installed_installer $HownBeingInstalledStartTxn_installer $HownBeingInstalledEndTxn_installer]").
  {
    iIntros (i buf Φₗ) "!> [HI [% %]] HΦ".
    iNamed "HI".

    rewrite list_lookup_fmap in H0.
    apply fmap_Some in H0.
    destruct H0 as [ [addr bk_s] [Hbkseq ->] ].
    list_elem upds i as u.
    iDestruct (big_sepL2_lookup_acc with "Hupds") as "[Hi Hupds]"; eauto.
    destruct u as [addr_i b_i]; simpl.
    iDestruct "Hi" as "[%Heq Hi]".
    simpl in Heq; subst.

    wp_pures.
    wp_apply util_proof.wp_DPrintf.
    wp_pures.
    wp_apply (wp_Write_atomic with "Hi").

    assert (((λ u : update.t, int.Z u.(update.addr)) <$> upds) !! int.nat i = Some (int.Z addr_i)) as Hu_lookup_map.
    1: rewrite list_lookup_fmap Hu_lookup //.
    apply elem_of_list_lookup_2 in Hu_lookup_map.
    apply ((iffLR (elem_of_subseteq _ _)) Hupds_subseteq) in Hu_lookup_map.
    apply elem_of_list_fmap in Hu_lookup_map.
    destruct Hu_lookup_map as (upd&(Hupd&Hupd_in)).
    apply ((iffLR (Forall_forall _ _)) Hbufs_addrs _) in Hupd_in.
    destruct Hupd_in as (binit&Hbinit).

    iDestruct "Hwal" as "[Hwal Hcircular]".
    iInv "Hwal" as (σs) "[Hinner HP]" "Hclose".
    iDestruct "Hinner" as "(>%Hwf&Hmem&>?&>?&>?&>?)"; iNamed.
    iNamed "Hdisk".
    iNamed "Hdisk".
    iNamed "Hinstalled".
    iNamed "Howninstalled".

    iDestruct (ghost_var_agree with "Halready_installed_installer Halready_installed") as %<-.
    iDestruct (mono_nat_auth_own_agree with "HownBeingInstalledStartTxn_installer HownBeingInstalledStartTxn_walinv") as %[_ <-].
    iDestruct (ghost_var_agree with "HownBeingInstalledEndTxn_installer HownBeingInstalledEndTxn_walinv") as %<-.
    iMod (ghost_var_update_halves (list_to_set (C:=gset Z) (take (S (int.nat i)) ((λ u, int.Z (update.addr u)) <$> upds)))
      with "Halready_installed_installer Halready_installed") as
          "[Halready_installed_installer Halready_installed]".

    apply mk_is_Some in Hbinit.
    apply Hdaddrs_init in Hbinit.
    destruct Hbinit as (b&Hbsome).

    (* we can't use is_installed_read_lookup since we need to change the already_installed set in the big_sepM *)
    iDestruct (big_sepM_lookup_acc_impl _ _ Hbsome with "Hdata") as "[Hdata Hdataclose]".
    iDestruct ("Hdataclose" $! (λ a _,
        is_dblock_with_txns σs.(log_state.d) σs.(log_state.txns)
        being_installed_start_txn_id (being_installed_start_txn_id + length subtxns)
        (list_to_set (take
            (S (int.nat i)) (* the only change here is incrementing this *)
            ((λ u : update.t,
            int.Z u.(update.addr)) <$>
            upds))) a)%I with "[]") as "Hdataclose".
    {
      (* show that new big_sepM condition holds for addresses not touched by the update *)
      iModIntro.
      iIntros (addr' b' Hb' Hneq) "Hdata".
      rewrite -Hupd in Hneq.
      iDestruct "Hdata" as (b_old txn_id') "((%Htxn_id'_bound&%Htxn_id'&%Happly_upds)&Hmapsto&%Haddr_bound)".
      rewrite /=.
      iExists _, txn_id'.
      iFrame (Haddr_bound) "∗".
      iPureIntro.
      split; first by lia.
      split. 2: apply Happly_upds.
      destruct (decide (addr' ∈ take (S (int.nat i)) ((λ u : update.t, int.Z u.(update.addr)) <$> upds))).
      - rewrite (take_S_r _ _ (int.Z addr_i)) in e.
        2: rewrite list_lookup_fmap Hu_lookup //=.
        apply elem_of_app in e.
        destruct e as [He | He].
        2: apply elem_of_list_singleton in He; contradiction.
        intuition.
        apply Htxn_id'.
        apply elem_of_list_to_set.
        apply He.
      - intro Haddr'_in.
        apply elem_of_list_to_set in Haddr'_in.
        contradiction.
    }

    iDestruct "Hdata" as (b_disk txn_id') "(%Hb_disk&Haddr_i_mapsto&%Haddr_LogSz_bound)".
    iExists _.
    rewrite -Hupd.
    iFrame "Haddr_i_mapsto".
    iApply ncfupd_mask_intro; first set_solver+.
    iIntros "HcloseE !> /= Haddr_i_mapsto".
    iMod "HcloseE" as "_".
    iDestruct (txns_are_sound with "Htxns_ctx Hsubtxns") as %Hsubtxns.

    iMod ("Hclose" with "[
      Hmem Htxns_ctx γtxns HnextDiskEnd_inv Howncs Hdurable
      HownBeingInstalledStartTxn_walinv HownBeingInstalledEndTxn_walinv
      Halready_installed
      HP Hdataclose Haddr_i_mapsto]") as "_".
    {
      iIntros "!>".
      iExists _.
      iFrame (Hwf) "Hmem Htxns_ctx γtxns HnextDiskEnd_inv HP".
      iExists _.
      iFrame "Howncs".
      iExists _, _.
      iFrameNamed.
      iExists _, _.
      iFrame (Hinstalled_bounds) "∗ Hbeing_installed_txns".
      iSpecialize ("Hdataclose" with "[Haddr_i_mapsto]").
      {
        (* show that the new big_sepM condition holds for address touched by the update *)
        iExists _, (being_installed_start_txn_id + length subtxns)%nat.
        rewrite -Hupd in Haddr_LogSz_bound.
        iFrame (Haddr_LogSz_bound) "∗".
        iPureIntro.
        split; first by lia.
        intuition.
        rewrite -subslice_from_start
          -(subslice_app_contig _ (S being_installed_start_txn_id)).
        2: lia.
        rewrite Hsubtxns txn_upds_app apply_upds_app -Hbufs.
        apply (apply_upds_NoDup_lookup _ _ (int.nat i)); intuition.
      }
      rewrite Hsubtxns.
      iFrame.
    }
    iIntros "!> Hb_i".
    iApply "HΦ".
    iFrame.
    replace (int.nat (word.add i 1)) with (S (int.nat i)).
    2: {
      assert (int.Z bks_s.(Slice.sz) ≤ 2^64 - 1) by word.
      word.
    }
    iFrame.
    iApply "Hupds".
    rewrite /is_update /=.
    eauto.
  }
  { rewrite /is_update.
    iApply (big_sepL2_mono with "Hupds").
    iIntros (?????) "Hb".
    destruct y2; simpl.
    iDestruct "Hb" as "[$ $]". }
  iIntros "[(?&?&?&?) Hbks_s]".
  iNamed.
  iApply "HΦ".
  rewrite take_ge.
  2: rewrite fmap_length; lia.
  rewrite (equiv_upds_addrs_eq bufs upds Hsame_upds).
  by iFrame "∗ #".
Qed.

(* TODO: why do we need this here again? *)
Opaque is_sliding.

Lemma readonly_struct_field_mapsto_agree E l d f v1 v2 :
  readonly (l ↦[d :: f] v1) -∗
  readonly (l ↦[d :: f] v2) -∗
  |={E}=> ⌜v1 = v2⌝.
Proof.
  iIntros "#H1 #H2".
  iMod (readonly_load with "H1") as (q1) "Hv1".
  iMod (readonly_load with "H2") as (q2) "Hv2".
  iDestruct (struct_field_mapsto_agree with "Hv1 Hv2") as "%Hv".
  done.
Qed.

Lemma snapshot_memLog_txns_are γ l dinit log diskEnd_pos (diskEnd_txn_id: nat) :
  "#Hwal" ∷ is_wal P l γ dinit -∗
  "Hlinv" ∷ memLog_linv γ log diskEnd_pos diskEnd_txn_id -∗
  "HownInstallerPos_installer" ∷ (∃ (installer_pos : nat), ghost_var γ.(installer_pos_name) (1/2) installer_pos) -∗
  "HownInstallerTxn_installer" ∷ (∃ (installer_txn_id : nat), ghost_var γ.(installer_txn_id_name) (1/2) installer_txn_id) -∗
  "HownInstallerPosMem_installer" ∷ (∃ (installer_pos_mem : u64), ghost_var γ.(installer_pos_mem_name) (1/2) installer_pos_mem) -∗
  "HownInstallerTxnMem_installer" ∷ (∃ (installer_txn_id_mem : nat), ghost_var γ.(installer_txn_id_mem_name) (1/2) installer_txn_id_mem) -∗
  |NC={⊤}=> ∃ installed_txn_id_mem nextDiskEnd_txn_id txns logger_pos logger_txn_id,
    "%Hsnapshot" ∷ ⌜has_updates
      (take (slidingM.logIndex log diskEnd_pos) log.(slidingM.log))
      (subslice (S installed_txn_id_mem) (S diskEnd_txn_id) txns)⌝ ∗
    "#Hsnapshot_txns" ∷ txns_are γ (S installed_txn_id_mem) (subslice (S installed_txn_id_mem) (S diskEnd_txn_id) txns) ∗
    "Hlinv" ∷ memLog_linv_core γ log diskEnd_pos diskEnd_txn_id
                                installed_txn_id_mem nextDiskEnd_txn_id txns
                                logger_pos logger_txn_id
                                diskEnd_pos diskEnd_txn_id ∗
    "HownInstallerPos_installer" ∷ ghost_var γ.(installer_pos_name) (1/2) (int.nat diskEnd_pos) ∗
    "HownInstallerTxn_installer" ∷ ghost_var γ.(installer_txn_id_name) (1/2) diskEnd_txn_id ∗
    "HownInstallerPosMem_installer" ∷ ghost_var γ.(installer_pos_mem_name) (1/2) diskEnd_pos ∗
    "HownInstallerTxnMem_installer" ∷ ghost_var γ.(installer_txn_id_mem_name) (1/2) diskEnd_txn_id.
Proof.
  iIntros.
  iNamed.
  iNamed "Hlinv".
  iNamed "Hlinv_pers".
  iNamed "Htxns".
  iNamed "HownInstallerPos_installer".
  iNamed "HownInstallerTxn_installer".
  iNamed "HownInstallerPosMem_installer".
  iNamed "HownInstallerTxnMem_installer".

  pose proof (is_txn_bound _ _ _ HdiskEnd_txn) as HdiskEnd_bound.
  iMod (get_txns_are _ _ _ _ _ (S installed_txn_id_mem) (S diskEnd_txn_id)
    (subslice (S installed_txn_id_mem) (S diskEnd_txn_id) txns)
    with "Howntxns Hwal") as "(#Htxns_subslice&Howntxns)"; eauto.
  { lia. }

  iDestruct "Hwal" as "[Hwal Hcircular]".
  iInv "Hwal" as (σs) "[Hinner HP]" "Hclose".
  iDestruct "Hinner" as "(>%Hwf&#Hmem&>Htxns_ctx&>γtxns&>HnextDiskEnd_inv&>Hdisk)".
  iDestruct "Hdisk" as (cs) "(Howncs&Hdisk)".
  iDestruct "Hdisk" as (??) "Hdisk".
  iNamed "Hdisk".
  iNamed "Hdurable".

  iDestruct (mono_nat_auth_own_agree with "HownDiskEndMem_linv HownDiskEndMem_walinv") as %[_ <-].
  iDestruct (mono_nat_auth_own_agree with "HownDiskEndMemTxn_linv HownDiskEndMemTxn_walinv") as %[_ <-].
  iMod (ghost_var_update_halves (int.nat diskEnd_pos) with
    "HownInstallerPos_installer HownInstallerPos_walinv"
  ) as "[HownInstallerPos_installer HownInstallerPos_walinv]".
  iMod (ghost_var_update_halves diskEnd_txn_id with
    "HownInstallerTxn_installer HownInstallerTxn_walinv"
  ) as "[HownInstallerTxn_installer HownInstallerTxn_walinv]".
  iMod (ghost_var_update_halves diskEnd_pos with
    "HownInstallerPosMem_installer HownInstallerPosMem_linv"
  ) as "[HownInstallerPosMem_installer HownInstallerPosMem_linv]".
  iMod (ghost_var_update_halves diskEnd_txn_id with
    "HownInstallerTxnMem_installer HownInstallerTxnMem_linv"
  ) as "[HownInstallerTxnMem_installer HownInstallerTxnMem_linv]".

  iMod ("Hclose" with "[Htxns_ctx γtxns HnextDiskEnd_inv Howncs
    HownInstallerPos_walinv HownInstallerTxn_walinv HownDiskEndMem_walinv HownDiskEndMemTxn_walinv
    Hinstalled HP]") as "_".
  {
    iNext.
    iExists _.
    iFrame "Hmem Htxns_ctx γtxns HnextDiskEnd_inv HP".
    iSplit; first by eauto.
    iExists _.
    iFrame "Howncs".
    iExists _, _.
    iFrame "Hinstalled circ.start circ.end Hbasedisk".
    iSplit; [ | by eauto ].
    iExists _, _, _, _.
    iFrame "HownInstallerPos_walinv HownInstallerTxn_walinv HownDiskEndMem_walinv HownDiskEndMemTxn_walinv".
    iPureIntro.
    rewrite /circ_matches_txns.
    destruct Hcirc_matches as
      (Hmatches_installer_pos&
        Hmatches_diskEnd_pos&
        Hmatches_logger&
        Hlog_index_ordering_walinv&
        Htxn_id_ordering_walinv).
    split.
    {
      pose proof (has_updates_app _ _ _ _ Hmatches_installer_pos Hmatches_diskEnd_pos) as Hmatches.
      rewrite -> subslice_app_contig in Hmatches by lia.
      rewrite <- subslice_from_start, subslice_app_contig in Hmatches by lia.
      rewrite subslice_from_start in Hmatches.
      assumption.
    }
    split_and!; try lia; eauto.
    rewrite !subslice_zero_length //.
  }

  iExists _, _, _, _, _.
  iFrame "HownInstallerPos_installer HownInstallerTxn_installer
    HownInstallerPosMem_installer HownInstallerTxnMem_installer
    Htxns_subslice".

  pose proof (has_updates_app _ _ _ _ His_installerEnd His_diskEnd) as Hmatches.
  rewrite -> subslice_app_contig in Hmatches by lia.
  rewrite -subslice_from_start subslice_app_contig in Hmatches; last first.
  { rewrite /slidingM.logIndex; lia. }
  rewrite subslice_from_start in Hmatches.

  iSplitR; first by eauto.
  iFrame.
  iFrame (HdiskEnd_txn Htxnpos_bound) "#".
  iPureIntro.
  split_and!; auto with lia.
  rewrite subslice_zero_length subslice_zero_length //.
Qed.

Lemma unify_memLog_installed_pos_mem γ log diskEnd_pos diskEnd_txn_id installed_txn_id_mem nextDiskEnd_txn_id txns logger_pos logger_txn_id installer_pos_mem installer_txn_id_mem installed_pos_mem_ext installed_txn_id_mem_ext :
  "Hlinv" ∷ memLog_linv_core γ log diskEnd_pos diskEnd_txn_id
                                installed_txn_id_mem nextDiskEnd_txn_id txns
                                logger_pos logger_txn_id
                                installer_pos_mem installer_txn_id_mem -∗
  "HownInstalledPosMem_installer" ∷ ghost_var γ.(installed_pos_mem_name) (1/2) installed_pos_mem_ext -∗
  "HownInstalledTxnMem_installer" ∷ ghost_var γ.(installed_txn_id_mem_name) (1/2) installed_txn_id_mem_ext -∗
    "Hlinv" ∷ memLog_linv_core γ log diskEnd_pos diskEnd_txn_id
                                installed_txn_id_mem nextDiskEnd_txn_id txns
                                logger_pos logger_txn_id
                                installer_pos_mem installer_txn_id_mem ∗
    "HownInstalledPosMem_installer" ∷ ghost_var γ.(installed_pos_mem_name) (1/2) log.(slidingM.start) ∗
    "HownInstalledTxnMem_installer" ∷ ghost_var γ.(installed_txn_id_mem_name) (1/2) installed_txn_id_mem ∗
    "%Hinstalled_pos_mem_eq" ∷ ⌜log.(slidingM.start) = installed_pos_mem_ext⌝ ∗
    "%Hinstalled_txn_id_mem_eq" ∷ ⌜installed_txn_id_mem = installed_txn_id_mem_ext⌝.
Proof.
  iIntros.
  iNamed.
  iNamed "Hlinv".
  iDestruct (ghost_var_agree with
    "HownInstalledPosMem_installer HownInstalledPosMem_linv"
  ) as %->.
  iDestruct (ghost_var_agree with
    "HownInstalledTxnMem_installer HownInstalledTxnMem_linv"
  ) as %->.
  iFrame "∗ # %".
  eauto.
Qed.

Lemma unify_memLog_installer_pos_mem γ log diskEnd_pos diskEnd_txn_id installed_txn_id_mem nextDiskEnd_txn_id txns logger_pos logger_txn_id installer_pos_mem installer_txn_id_mem installer_pos_mem_ext installer_txn_id_mem_ext :
  "Hlinv" ∷ memLog_linv_core γ log diskEnd_pos diskEnd_txn_id
                                installed_txn_id_mem nextDiskEnd_txn_id txns
                                logger_pos logger_txn_id
                                installer_pos_mem installer_txn_id_mem -∗
  "HownInstallerPosMem_installer" ∷ ghost_var γ.(installer_pos_mem_name) (1/2) installer_pos_mem_ext -∗
  "HownInstallerTxnMem_installer" ∷ ghost_var γ.(installer_txn_id_mem_name) (1/2) installer_txn_id_mem_ext -∗
    "Hlinv" ∷ memLog_linv_core γ log diskEnd_pos diskEnd_txn_id
                                installed_txn_id_mem nextDiskEnd_txn_id txns
                                logger_pos logger_txn_id
                                installer_pos_mem installer_txn_id_mem ∗
    "HownInstallerPosMem_installer" ∷ ghost_var γ.(installer_pos_mem_name) (1/2) installer_pos_mem ∗
    "HownInstallerTxnMem_installer" ∷ ghost_var γ.(installer_txn_id_mem_name) (1/2) installer_txn_id_mem ∗
    "%Hinstaller_pos_mem_eq" ∷ ⌜installer_pos_mem = installer_pos_mem_ext⌝ ∗
    "%Hinstaller_txn_id_mem_eq" ∷ ⌜installer_txn_id_mem = installer_txn_id_mem_ext⌝.
Proof.
  iIntros.
  iNamed.
  iNamed "Hlinv".
  iDestruct (ghost_var_agree with
    "HownInstallerPosMem_installer HownInstallerPosMem_linv"
  ) as %->.
  iDestruct (ghost_var_agree with
    "HownInstallerTxnMem_installer HownInstallerTxnMem_linv"
  ) as %->.
  iFrame "∗ # %".
  eauto.
Qed.

Lemma unify_memLog_txns γ log diskEnd_pos diskEnd_txn_id installed_txn_id_mem nextDiskEnd_txn_id txns logger_pos logger_txn_id installer_pos_mem installer_txn_id_mem txns_ext :
  "Hlinv" ∷ memLog_linv_core γ log diskEnd_pos diskEnd_txn_id
                                installed_txn_id_mem nextDiskEnd_txn_id txns
                                logger_pos logger_txn_id
                                installer_pos_mem installer_txn_id_mem -∗
  "γtxns"  ∷ ghost_var γ.(txns_name) (1/2) txns_ext -∗
    "Hlinv" ∷ memLog_linv_core γ log diskEnd_pos diskEnd_txn_id
                                installed_txn_id_mem nextDiskEnd_txn_id txns_ext
                                logger_pos logger_txn_id
                                installer_pos_mem installer_txn_id_mem ∗
    "γtxns"  ∷ ghost_var γ.(txns_name) (1/2) txns_ext ∗
    "%Htxns_eq" ∷ ⌜txns = txns_ext⌝.
Proof.
  iIntros.
  iNamed.
  iNamed "Hlinv".
  iDestruct (ghost_var_agree with
    "Howntxns γtxns"
  ) as %<-.
  iFrame "∗ # %".
  eauto.
Qed.

Lemma unify_memLog_diskEnd_mem γ log diskEnd_pos diskEnd_txn_id installed_txn_id_mem nextDiskEnd_txn_id txns logger_pos logger_txn_id installer_pos_mem installer_txn_id_mem (diskEnd_pos_ext diskEnd_txn_id_ext: nat) :
  "Hlinv" ∷ memLog_linv_core γ log diskEnd_pos diskEnd_txn_id
                                installed_txn_id_mem nextDiskEnd_txn_id txns
                                logger_pos logger_txn_id
                                installer_pos_mem installer_txn_id_mem -∗
  "HownDiskEndMem" ∷ mono_nat_auth_own γ.(diskEnd_mem_name) (1/2) diskEnd_pos_ext -∗
  "HownDiskEndMemTxn" ∷ mono_nat_auth_own γ.(diskEnd_mem_txn_id_name) (1/2) diskEnd_txn_id_ext -∗
    "Hlinv" ∷ memLog_linv_core γ log diskEnd_pos diskEnd_txn_id
                                installed_txn_id_mem nextDiskEnd_txn_id txns
                                logger_pos logger_txn_id
                                installer_pos_mem installer_txn_id_mem ∗
    "HownDiskEndMem" ∷ mono_nat_auth_own γ.(diskEnd_mem_name) (1/2) (int.nat diskEnd_pos) ∗
    "HownDiskEndMemTxn" ∷ mono_nat_auth_own γ.(diskEnd_mem_txn_id_name) (1/2) diskEnd_txn_id ∗
    "%HdiskEnd_pos_eq" ∷ ⌜int.nat diskEnd_pos = diskEnd_pos_ext⌝ ∗
    "%HdiskEnd_txn_id_eq" ∷ ⌜diskEnd_txn_id = diskEnd_txn_id_ext⌝.
Proof.
  iIntros.
  iNamed.
  iNamed "Hlinv".
  iDestruct (mono_nat_auth_own_agree with "HownDiskEndMem_linv HownDiskEndMem" ) as %[_ HdiskEnd_pos_eq].
  iDestruct (mono_nat_auth_own_agree with "HownDiskEndMemTxn_linv HownDiskEndMemTxn" ) as %[_ HdiskEnd_txn_id_eq].
  rewrite -HdiskEnd_pos_eq -HdiskEnd_txn_id_eq.
  iFrame "∗ # %".
  eauto.
Qed.

Lemma linv_get_pers_core γ σ diskEnd_pos diskEnd_txn_id installed_txn_id_mem nextDiskEnd_txn_id txns logger_pos logger_txn_id installer_pos_mem installer_txn_id_mem :
  "Hlinv" ∷ memLog_linv_core γ σ diskEnd_pos diskEnd_txn_id
                                installed_txn_id_mem nextDiskEnd_txn_id txns
                                logger_pos logger_txn_id
                                installer_pos_mem installer_txn_id_mem -∗
  "#Hlinv_pers" ∷ memLog_linv_pers_core γ σ diskEnd_pos diskEnd_txn_id installed_txn_id_mem nextDiskEnd_txn_id txns logger_pos logger_txn_id installer_pos_mem installer_txn_id_mem.
Proof.
  iIntros "Hlinv".
  iDestruct "Hlinv" as "(#Hlinv_pers&Hlinv)".
  iFrame "Hlinv_pers".
Qed.

Reserved Notation "x ≤ y ≤ z ≤ v ≤ w"
  (at level 70, y at next level, z at next level, v at next level).
Notation "x ≤ y ≤ z ≤ v ≤ w" := (x ≤ y ∧ y ≤ z ∧ z ≤ v ∧ v ≤ w)%nat : nat_scope.

Lemma is_durable_txn_get_is_txn γ cs txns diskEnd_txn_id durable_lb :
  "#circ.end" ∷ is_durable_txn γ cs txns diskEnd_txn_id durable_lb -∗
    ∃ (diskEnd: u64), (
      "#HdiskEnd_txn" ∷ ⌜is_txn txns diskEnd_txn_id diskEnd⌝ ∗
      "%HdiskEnd_val" ∷ ⌜int.Z diskEnd = circΣ.diskEnd cs⌝
    ).
Proof.
  iIntros.
  iNamed.
  iNamed "circ.end".
  iExists _.
  eauto.
Qed.

Theorem wp_Walog__logInstall γ l dinit (diskEnd_txn_id_bound: nat) σₛ :
  {{{ "#st" ∷ readonly (l ↦[Walog :: "st"] #σₛ.(wal_st)) ∗
      "#d" ∷ readonly (l ↦[Walog :: "d"] σₛ.(wal_d)) ∗
      "#memLock" ∷ readonly (l ↦[Walog :: "memLock"] #σₛ.(memLock)) ∗
      "#condInstall" ∷ readonly (l ↦[Walog :: "condInstall"] #σₛ.(condInstall)) ∗
      "#Hwal" ∷ is_wal P l γ dinit ∗
      "Hlkinv" ∷ wal_linv σₛ.(wal_st) γ ∗
      "His_locked" ∷ locked #σₛ.(memLock) ∗
      "#lk" ∷ is_lock N #σₛ.(memLock) (wal_linv σₛ.(wal_st) γ) ∗
      "#cond_install" ∷ is_cond σₛ.(condInstall) #σₛ.(memLock) ∗
      "Hinstaller" ∷ installer_inv γ
  }}}
    Walog__logInstall #l
  {{{ (blkCount installEnd:u64), RET (#blkCount, #installEnd);
      "Hlkinv" ∷ wal_linv σₛ.(wal_st) γ ∗
      "His_locked" ∷ locked #σₛ.(memLock) ∗
      "Hinstaller" ∷ installer_inv γ
  }}}.
Proof.
  wp_start.
  iNamedRestorable "Hlkinv".
  iNamedRestorable "Hfields".
  iNamed "Hfield_ptsto".

  iNamed "HdiskEnd_circ".
  iNamed "Hstart_circ".

  iMod (is_wal_read_mem with "Hwal") as "#Hmem".
  wp_call.
  iNamed "Hmem".
  iClear "Hmem".
  iDestruct "Hstfields" as "(memLock'&d'&circ'&st'&Hstfields)".
  iMod (readonly_struct_field_mapsto_agree with "st st'") as "<-".
  iMod (readonly_struct_field_mapsto_agree with "memLock memLock'") as "<-".
  iMod (readonly_struct_field_mapsto_agree with "d d'") as "<-".

  wp_loadField.
  wp_loadField.
  wp_loadField.
  wp_loadField.

  wp_apply (wp_sliding__takeTill with "His_memLog"); first by word.
  iIntros (q s) "(His_memLog&Htxn_slice)".
  wp_pures.
  wp_apply wp_slice_len; wp_pures.
  wp_if_destruct; wp_pures.
  {
    iApply "HΦ".
    iFrame "His_locked Hinstaller".
    iExists _.
    iFrame "∗ #".
    iExists _.
    by iFrame (Hlocked_wf) "∗".
  }

  iDestruct (updates_slice_frag_len with "Htxn_slice") as %Hs_len.
  rewrite take_length_le in Hs_len.
  2: {
    rewrite /locked_wf /slidingM.wf in Hlocked_wf.
    rewrite /slidingM.logIndex.
    lia.
  }
  assert (int.Z s.(Slice.sz) ≠ int.Z 0) as HdiskEnd_neq.
  {
    intros Hcontradiction.
    apply (inj int.Z) in Hcontradiction.
    assert (#s.(Slice.sz) = #0) as Hcontradiction'
      by (f_equal; f_equal; apply Hcontradiction).
    contradiction.
  }
  rewrite Hs_len in HdiskEnd_neq.
  replace (int.Z 0) with 0 in HdiskEnd_neq by word.

  iNamed "Hinstaller".
  iMod (snapshot_memLog_txns_are with "Hwal HmemLog_linv
    HownInstallerPos_installer HownInstallerTxn_installer
    HownInstallerPosMem_installer HownInstallerTxnMem_installer"
  ) as (installed_txn_id_mem_linv nextDiskEnd_txn_id txns logger_pos logger_txn_id) "Hsnapshot".
  iNamed "Hsnapshot".
  iNamed "HownInstalledPosMem_installer".
  iDestruct (unify_memLog_installed_pos_mem with
    "Hlinv HownInstalledPosMem_installer HownInstalledTxnMem_installer")
    as "(Hlinv&HownInstalledPosMem_installer&HownInstalledTxnMem_installer&<-&->)".
  iMod (thread_own_get with "Hstart_exactly HnotInstalling") as "(Hstart_exactly&Hstart_is&Hinstalling)".

  (* vvv TODO: factor this out into a lemma vvv *)

  iDestruct "Hwal" as "[Hwal Hcircular]".
  rewrite -ncfupd_wp.
  iInv "Hwal" as (σs) "[Hinner HP]" "Hclose".
  iDestruct "Hinner" as "(>%Hwf&#Hmem&>Htxns_ctx&>γtxns&>HnextDiskEnd_inv&>Hdisk)".
  iDestruct "Hdisk" as (cs) "(Howncs&Hdisk)".
  iDestruct "Hdisk" as (??) "Hdisk".
  iNamed "Hdisk".
  iNamed "Hinstalled".

  iDestruct (unify_memLog_txns with "Hlinv γtxns") as "(Hlinv&γtxns&->)".
  iDestruct (linv_get_pers_core with "Hlinv") as "#Hlinv_pers".
  iDestruct "Hlinv_pers" as "(?&?&?&?&?&?&?&?&?)".
  iNamed.
  iNamed "Howninstalled".
  iDestruct (ghost_var_agree with "Halready_installed_installer Halready_installed") as %<-.
  iDestruct (mono_nat_auth_own_agree with "HownBeingInstalledStartTxn_installer HownBeingInstalledStartTxn_walinv") as %[_ <-].
  iDestruct (ghost_var_agree with "HownBeingInstalledEndTxn_installer HownBeingInstalledEndTxn_walinv") as %->.
  iMod (ghost_var_update_halves σ.(locked_diskEnd_txn_id) with
    "HownBeingInstalledEndTxn_installer HownBeingInstalledEndTxn_walinv"
  ) as "[HownBeingInstalledEndTxn_installer HownBeingInstalledEndTxn_walinv]".
  iNamed "Hdurable".
  iDestruct (unify_memLog_diskEnd_mem with "Hlinv HownDiskEndMem_walinv HownDiskEndMemTxn_walinv")
    as "(Hlinv&HownDiskEndMem_walinv&HownDiskEndMemTxn_walinv&%HdiskEnd_pos_eq&%HdiskEnd_txn_id_eq)".
  subst diskEnd_mem diskEnd_mem_txn_id.
  iDestruct (mono_nat_lb_own_get with "HownDiskEndMem_walinv") as "#HownDiskEndMem_lb".
  iDestruct (mono_nat_lb_own_valid with "HownDiskEndMemTxn_walinv HdiskEndMem_lb_installer") as %[_ HdiskEndMemTxn_lb].
  iDestruct (mono_nat_lb_own_get with "HownDiskEndMemTxn_walinv") as "#HdiskEndMem_lb".

  pose proof (is_txn_bound _ _ _ HdiskEnd_txn) as HdiskEnd_mem_bound.
  rewrite /is_txn in HdiskEnd_txn.
  destruct (σs.(log_state.txns) !! σ.(locked_diskEnd_txn_id)) as [diskEnd_txn|] eqn:HdiskEnd_txn_eq.
  2: simpl in HdiskEnd_txn; inversion HdiskEnd_txn.
  destruct diskEnd_txn as (upd_pos&upds).
  simpl in HdiskEnd_txn.
  inversion HdiskEnd_txn as (HdiskEnd_txn_inv).
  rewrite HdiskEnd_txn_inv in HdiskEnd_txn_eq.
  iDestruct (txns_ctx_complete _ _ _ _ HdiskEnd_txn_eq with "Htxns_ctx") as "#HdiskEnd_txn_val".

  iMod ("Hclose" with "[Htxns_ctx γtxns HnextDiskEnd_inv Howncs
    HownInstallerPos_walinv HownInstallerTxn_walinv
    HownDiskEndMem_walinv HownDiskEndMemTxn_walinv
    HownBeingInstalledStartTxn_walinv HownBeingInstalledEndTxn_walinv
    Halready_installed Hdata HP]") as "_".
  {
    iExists _.
    iFrame "Hmem Htxns_ctx γtxns HnextDiskEnd_inv HP".
    iSplit; first by intuition.
    iExists _.
    iFrame "Howncs".
    iExists _, _.
    iFrameNamed.
    iSplitR "HownInstallerPos_walinv HownInstallerTxn_walinv
      HownDiskEndMem_walinv HownDiskEndMemTxn_walinv".
    2: {
      iExists _, _, _, _.
      iFrame.
      iPureIntro.
      eauto.
    }
    iExists _, _.
    iFrame "Halready_installed HownBeingInstalledStartTxn_walinv HownBeingInstalledEndTxn_walinv".
    iFrame "Hsnapshot_txns".

    iSplit.
    { iPureIntro. rewrite /circ_matches_txns in Hcirc_matches. lia. }
    iApply (big_sepM_mono with "Hdata").
    iIntros (addr blk Haddr_bound) "Hdata".
    destruct (decide (addr ∈ (∅ : gset _))).
    1: set_solver.
    iDestruct "Hdata" as (b txn_id') "(%Hb&Haddr_d&%Haddr_bound')".
    iExists b, txn_id'.
    iFrame "∗ %". iPureIntro. intuition eauto.
    lia.
  }

  (* ^^^ TODO: factor this out into a lemma ^^^ *)

  (* these names would be free if the above was a lemma *)
  remember σs.(log_state.txns) as txns.
  iClear "circ.start circ.end Hbasedisk Hbeing_installed_txns Hmem HinstalledTxn_lb".
  clear Heqtxns Hwf Hdaddrs_init σs Hinstalled_bounds Hcirc_matches diskEnd_txn_id installer_pos installer_txn_id cs.

  iModIntro.
  wp_loadField.
  wp_apply (release_spec with "[$lk $His_locked Hlinv
    HdiskEnd_exactly Hstart_exactly
    His_memLog HmemLog HdiskEnd Hshutdown Hnthread]").
  {
    iNext.
    iApply "Hlkinv"; iFrameNamed.
    iSplitL "Hlinv".
    {
      iExists _, _, _, _, _, _, _.
      iFrame "Hlinv".
    }
    iSplitL "Hstart_exactly"; first by iFrame.
    iSplitL "HdiskEnd_exactly"; first by iFrame.
    iApply "Hfields"; iFrameNamed.
  }
  iClear (Hlocked_wf) "Hlkinv Hfields Hstart_at_least".
  wp_pures.
  wp_apply util_proof.wp_DPrintf.
  wp_pures.
  wp_loadField.

  wp_apply (wp_installBlocks with "[
    $Halready_installed_installer $HownBeingInstalledStartTxn_installer
    $Htxn_slice
    $Hwal $Hcircular
    HownBeingInstalledEndTxn_installer
  ]").
  {
    iFrame (Hsnapshot) "Hsnapshot_txns".
    rewrite -> subslice_length by lia.
    iExactEq "HownBeingInstalledEndTxn_installer".
    rewrite /named.
    auto with f_equal lia.
  }

  iIntros "(_&Halready_installed_installer&HownBeingInstalledStartTxn_installer&HownBeingInstalledEndTxn_installer)".
  rewrite -> subslice_length by lia.
  replace (installed_txn_id_mem + (S σ.(locked_diskEnd_txn_id) - (S installed_txn_id_mem)))%nat
    with σ.(locked_diskEnd_txn_id) by lia.

  wp_apply wp_Barrier.
  wp_loadField.

  wp_apply (wp_circular__Advance _ _ (
      "HownInstallerPos_installer" ∷
        ghost_var γ.(installer_pos_name) (1/2)
          (int.nat σ.(diskEnd)) ∗
      "HownInstallerTxn_installer" ∷
        ghost_var γ.(installer_txn_id_name) (1/2)
          σ.(locked_diskEnd_txn_id) ∗
      "HownBeingInstalledStartTxn_installer" ∷
        mono_nat_auth_own γ.(being_installed_start_txn_name) (1/2)
          σ.(locked_diskEnd_txn_id) ∗
      "HownBeingInstalledEndTxn_installer" ∷
        ghost_var γ.(being_installed_end_txn_name) (1/2)
          σ.(locked_diskEnd_txn_id) ∗
      "Halready_installed_installer" ∷
        ghost_var γ.(already_installed_name) (1/2) (∅: gset Z)
    ) with "[$Hcircular $Hstart_is $HdiskEnd_at_least
      HownInstallerPos_installer HownInstallerTxn_installer
      HownBeingInstalledStartTxn_installer HownBeingInstalledEndTxn_installer
      Halready_installed_installer]").
  {
    iSplit.
    1: iPureIntro; lia.
    iIntros (σc) "(%Hcirc_wf&Hcirc_ctx&%Hstart)".
    iIntros (σc' b) "(%Hrelation&%Hcirc_wf')".
    simpl in Hrelation; monad_inv.

    iInv "Hwal" as (σs) "[Hinner HP]".
    iDestruct "Hinner" as "(>%Hwf&Hmem&>Htxns_ctx&>γtxns&>HnextDiskEnd_inv&>Hdisk)"; iNamed.
    iNamed "Hdisk".
    iNamed "Hdisk".
    rewrite /circular_pred.
    iDestruct (ghost_var_agree with "Hcirc_ctx Howncs") as %<-.
    iDestruct (txns_are_sound with "Htxns_ctx Hsnapshot_txns") as %Hsnapshot_txns_are.
    rewrite subslice_length in Hsnapshot_txns_are.
    2: lia.
    replace (installed_txn_id_mem + (S σ.(locked_diskEnd_txn_id) - installed_txn_id_mem))%nat
      with (S σ.(locked_diskEnd_txn_id)) in Hsnapshot_txns_are by lia.
    iMod (ghost_var_update_halves with "Hcirc_ctx Howncs") as "[$ Howncs]".
    iDestruct (txn_val_valid_general with "Htxns_ctx HdiskEnd_txn_val") as %HdiskEnd_txn_lookup.
    iNamed "Hdisk".
    iNamed "Hinstalled".
    iNamed "Howninstalled".
    iNamed "Hdurable".
    iDestruct (ghost_var_agree with "HownInstallerPos_installer HownInstallerPos_walinv") as %<-.
    iDestruct (ghost_var_agree with "HownInstallerTxn_installer HownInstallerTxn_walinv") as %<-.
    iDestruct (mono_nat_auth_own_agree with "HownBeingInstalledStartTxn_installer HownBeingInstalledStartTxn_walinv") as %[_ <-].
    iDestruct (ghost_var_agree with "HownBeingInstalledEndTxn_installer HownBeingInstalledEndTxn_walinv") as %<-.
    iDestruct (ghost_var_agree with "Halready_installed_installer Halready_installed") as %<-.
    iMod (mono_nat_own_update_halves σ.(locked_diskEnd_txn_id)
      with "HownBeingInstalledStartTxn_installer HownBeingInstalledStartTxn_walinv") as
          "(HownBeingInstalledStartTxn_installer&HownBeingInstalledStartTxn_walinv&HinstalledTxn_lb')".
    1: lia.
    iMod (ghost_var_update_halves (∅: gset Z)
      with "Halready_installed_installer Halready_installed") as
          "[Halready_installed_installer Halready_installed]".
    iDestruct (txns_are_sound with "Htxns_ctx Hsnapshot_txns") as %Hsnapshot_txns.
    rewrite -> subslice_length in Hsnapshot_txns by lia.
    replace
      (S installed_txn_id_mem + (S σ.(locked_diskEnd_txn_id) - S installed_txn_id_mem))%nat
      with (S σ.(locked_diskEnd_txn_id))
      in Hsnapshot_txns by lia.
    iSplitR "HownInstallerPos_installer HownInstallerTxn_installer
      HownBeingInstalledStartTxn_installer HownBeingInstalledEndTxn_installer
      Halready_installed_installer".
    2: iFrame; eauto.
    iExists _.
    iFrame (Hwf) "HP Hmem Htxns_ctx γtxns HnextDiskEnd_inv".
    iExists _; iFrame.
    iExists σ.(locked_diskEnd_txn_id), diskEnd_txn_id.
    iFrame (Hdaddrs_init) "Hbasedisk".
    iSplitL "HownBeingInstalledStartTxn_walinv HownBeingInstalledEndTxn_walinv Halready_installed Hdata".
    {
      iExists _, _.
      iFrame "HownBeingInstalledStartTxn_walinv HownBeingInstalledEndTxn_walinv Halready_installed".

      iSplitR; first by (iPureIntro; lia).
      iSplitR.
      { rewrite subslice_zero_length. iApply txns_are_nil. }
      iApply (big_sepM_impl with "Hdata").
      iIntros "!> !> !>".
      iIntros (addr x Hx) "Hdata".
      iDestruct "Hdata" as (b txn_id') "(%Htxn_id'&Hb&%Haddr_bound)".
      iExists _, σ.(locked_diskEnd_txn_id).
      iFrame (Haddr_bound) "Hb".
      iPureIntro.
      split; first by lia.
      split; first by eauto.
      destruct Htxn_id' as (Htxn_id'&Haddr&Hb).
      destruct (decide (
        addr ∈ (
          (λ u, int.Z u.(update.addr)) <$>
            take (slidingM.logIndex σ.(memLog) σ.(diskEnd))
              σ.(memLog).(slidingM.log)
        )
      )).
      {
        assert (txn_id' = σ.(locked_diskEnd_txn_id)).
        {
          apply Haddr.
          apply elem_of_list_to_set.
          apply e.
        }
        subst txn_id'.
        apply Hb.
      }
      replace (take (S σ.(locked_diskEnd_txn_id)) σs.(log_state.txns))
        with (take (S txn_id') σs.(log_state.txns) ++
          subslice (S txn_id') (S σ.(locked_diskEnd_txn_id)) σs.(log_state.txns)).
      2: {
        rewrite -subslice_from_start subslice_app_contig.
        2: lia.
        rewrite subslice_from_start //.
      }
      rewrite txn_upds_app apply_upds_app apply_upds_notin'.
      1: apply Hb.
      rewrite -Hsnapshot_txns in Hsnapshot.
      intros Haddr_in.
      assert (
        (txn_upds
          (subslice
            (S txn_id')
            (S (σ.(locked_diskEnd_txn_id)))
        σs.(log_state.txns)))
        ⊆
        (txn_upds
          (subslice
            (S installed_txn_id_mem)
            (S σ.(locked_diskEnd_txn_id))
        σs.(log_state.txns)))) as Hsubseteq.
      {
        apply txn_upds_subseteq.
        apply subslice_subslice_subseteq.
        all: lia.
      }
      eapply list_fmap_mono in Hsubseteq.
      apply ((iffLR (elem_of_subseteq _ _)) Hsubseteq addr) in Haddr_in.
      apply equiv_upds_addrs_subseteq in Hsnapshot.
      apply ((iffLR (elem_of_subseteq _ _)) Hsnapshot) in Haddr_in.
      contradiction.
    }

    destruct Hcirc_matches as (Hmatches_locked_diskEnd&Hmatches_diskEnd_mem&Hmatches_diskEnd&Hcirc_log_index_ordering&Hcirc_txn_id_ordering).
    rewrite /circΣ.diskEnd /= in Hcirc_log_index_ordering.
    replace (Z.to_nat (int.Z (start σc) + length (circΣ.upds σc)))
      with (int.nat (start σc) + length (circΣ.upds σc))%nat
      in Hcirc_log_index_ordering by word.

    iSplitL.
    {
      iExists _, _, _, _.
      iFrame.
      iPureIntro.
      rewrite /circ_matches_txns /=.
      rewrite Nat.sub_diag take_0 subslice_zero_length.
      split; first by eauto.
      rewrite subslice_from_start.
      replace (Z.to_nat (int.Z σ.(diskEnd) - int.Z (start σc))) with (int.nat σ.(diskEnd) - int.nat (start σc))%nat by word.
      split.
      {
        replace (diskEnd_mem - int.nat σ.(diskEnd))%nat
          with ((diskEnd_mem - int.nat (start σc)) - (int.nat σ.(diskEnd) - int.nat (start σc)))%nat by lia.
        rewrite -subslice_drop_take.
        2: lia.
        intuition.
      }
      rewrite drop_drop.
      replace (int.nat σ.(diskEnd) - int.nat (start σc) + (diskEnd_mem - int.nat σ.(diskEnd)))%nat
        with (diskEnd_mem - int.nat (start σc))%nat by lia.
      split; first by intuition.
      rewrite /circΣ.diskEnd /= drop_length.
      replace (Z.to_nat (int.Z σ.(diskEnd) + (length (circΣ.upds σc) - (int.nat σ.(diskEnd) - int.nat (start σc)))%nat))
        with (int.nat σ.(diskEnd) + (length (circΣ.upds σc) - (int.nat σ.(diskEnd) - int.nat (start σc))))%nat by word.
      lia.
    }
    iSplitL.
    2: {
      iDestruct "circ.end" as (diskEnd_disk) "(?&?&?&?)".
      iExists diskEnd_disk.
      iNamed.
      iFrame (Hdurable_lb) "Hend_txn_stable".
      iSplitL.
      2: eauto.
      iPureIntro.
      rewrite /circΣ.diskEnd /= drop_length.
      replace (Z.to_nat (int.Z σ.(diskEnd) - int.Z (start σc)))
        with (int.nat σ.(diskEnd) - int.nat (start σc))%nat by word.
      rewrite /circΣ.diskEnd /= in HdiskEnd_val.
      word.
    }
    iNamed "circ.start".
    rewrite /is_installed_txn /=.
    iFrame "HdiskEnd_stable".
    iSplitR.
    1: iPureIntro; lia.
    iPureIntro.
    replace (S installed_txn_id_mem + (S σ.(locked_diskEnd_txn_id) - S installed_txn_id_mem))%nat
      with (S σ.(locked_diskEnd_txn_id)) in Hsnapshot_txns_are by lia.
    rewrite /is_txn HdiskEnd_txn_lookup //.
  }
  iIntros "(Hpost&Hstart_is)".
  iNamed "Hpost".

  wp_loadField.
  wp_apply (acquire_spec with "lk").
  iIntros "(His_locked&Hlkinv)".

  iDestruct "Hlkinv" as (σ') "Hlkinv".
  iNamedRestorable "Hlkinv".
  iNamed "Hfields".
  iNamed "Hfield_ptsto".

  wp_loadField.
  wp_call.
  wp_loadField.

  iDestruct "HmemLog_linv" as (installed_txn_id_mem' nextDiskEnd_txn_id' txns' logger_pos' logger_txn_id' installer_pos_mem' installer_txn_id_mem') "Hlinv".
  iDestruct (unify_memLog_installed_pos_mem with
    "Hlinv HownInstalledPosMem_installer HownInstalledTxnMem_installer")
    as "(Hlinv&HownInstalledPosMem_installer&HownInstalledTxnMem_installer&%Hinstalled_pos_mem_eq&->)".
  iDestruct (unify_memLog_installer_pos_mem with
    "Hlinv HownInstallerPosMem_installer HownInstallerTxnMem_installer")
    as "(Hlinv&HownInstallerPosMem_installer&HownInstallerTxnMem_installer&->&->)".
  iDestruct "Hlinv" as "(#Hlinv_pers&Howntxns&HnextDiskEnd&Hγ)".
  iNamed "Hγ".
  iDestruct "Hlinv_pers" as "(%Hlog_index_ordering'&%Htxn_id_ordering'&#HmemStart_txn'&%HdiskEnd_txn'&#HdiskEnd_stable'&#HmemEnd_txn'&#HinstalledTxn_lb'&#Htxns'&%Htxnpos_bound')".
  iMod (ghost_var_update_halves σ.(diskEnd)
    with "HownInstalledPosMem_installer HownInstalledPosMem_linv") as
        "[HownInstalledPosMem_installer HownInstalledPosMem_linv]".
  iMod (ghost_var_update_halves σ.(locked_diskEnd_txn_id)
    with "HownInstalledTxnMem_installer HownInstalledTxnMem_linv") as
        "[HownInstalledTxnMem_installer HownInstalledTxnMem_linv]".
  iNamed "Hstart_circ".
  iDestruct (start_is_to_at_least with "Hstart_is") as "#Hstart_at_least'".
  iMod (thread_own_put with "Hstart_exactly Hinstalling Hstart_is")
    as "[Hstart_exactly HnotInstalling]".
  iDestruct (mono_nat_lb_own_valid with "HownDiskEndMem_linv HownDiskEndMem_lb") as %HdiskEnd_lb.
  iDestruct (mono_nat_lb_own_get with "HownBeingInstalledStartTxn_installer") as "#HinstalledTxn_lb".

  wp_apply (wp_sliding__deleteFrom with "His_memLog").
  1: lia.
  iIntros "His_memLog".
  wp_loadField.
  wp_apply (wp_condBroadcast with "cond_install").
  wp_pures.

  iApply "HΦ".
  iFrame "His_locked".
  iSplitR "HownBeingInstalledStartTxn_installer HownBeingInstalledEndTxn_installer
    Halready_installed_installer
    HdiskEndMem_lb_installer
    HownInstalledPosMem_installer HownInstalledTxnMem_installer
    HownInstallerPosMem_installer HownInstallerTxnMem_installer
    HownInstallerPos_installer HownInstallerTxn_installer
    HnotInstalling".
  2: {
    iExists _, _. iModIntro.
    iFrame "HdiskEndMem_lb ∗".
    iSplitL "HownInstallerPos_installer".
    1: iExists _; by iFrame.
    iSplitL "HownInstallerTxn_installer".
    1: iExists _; by iFrame.
    iSplitL "HownInstallerPosMem_installer".
    1: iExists _; by iFrame.
    iSplitL "HownInstallerTxnMem_installer".
    1: iExists _; by iFrame.
    1: iExists _; by iFrame.
  }
  iExists {|
    diskEnd := σ'.(diskEnd);
    locked_diskEnd_txn_id := σ'.(locked_diskEnd_txn_id);
    memLog := (set slidingM.start (λ _ : u64, σ.(diskEnd))
      (set slidingM.log
        (drop (slidingM.logIndex σ'.(memLog) σ.(diskEnd)))
          σ'.(memLog)))
  |}.
  simpl.
  iSplitL "His_memLog HmemLog HdiskEnd Hshutdown Hnthread".
  {
    iExists _.
    simpl.
    iFrame.
    iPureIntro.
    rewrite /locked_wf /=.
    split; first by lia.
    rewrite /slidingM.wf /= drop_length.
    destruct Hlocked_wf as (Hlocked_wf_bound&Hsliding_wf).
    rewrite /slidingM.wf in Hsliding_wf.
    rewrite /slidingM.logIndex.
    word.
  }
  iFrame "HdiskEnd_circ Hstart_exactly Hstart_at_least'".
  iExists _, _, _, _, _, _, _.
  iFrame. iModIntro.
  iSplit.
  {
    iPureIntro.
    destruct σ'.
    simpl.
    simpl in Hlog_index_ordering'.
    lia.
  }
  iSplit.
  1: iPureIntro; lia.
  simpl.
  iDestruct (txn_val_to_pos with "HdiskEnd_txn_val") as "HdiskEnd_txn_pos".
  iFrame (HdiskEnd_txn') "HdiskEnd_stable' HdiskEnd_txn_pos HinstalledTxn_lb".

  destruct σ'.
  rewrite /memLog_linv_txns /= /slidingM.logIndex.
  destruct memLog.
  rewrite /slidingM.endPos /slidingM.memEnd /=.
  simpl in *.
  rewrite /locked_wf /slidingM.wf /= in Hlocked_wf.

  iSplit.
  {
    rewrite drop_length.
    replace (word.add σ.(invariant.diskEnd)
      (length log - (int.nat σ.(invariant.diskEnd) - int.nat start))%nat)
      with (word.add start (length log)).
    2: apply (inj int.Z); word.
    iFrame "HmemEnd_txn'".
  }

  iDestruct "Htxns'" as
    "(%His_installerEnd'&%His_diskEnd'&%His_loggerEnd'&%His_nextDiskEnd'&%His_nextTxn')".
  iSplit.
  2: {
    iPureIntro.
    rewrite drop_length.
    replace (int.Z σ.(invariant.diskEnd) +
        (length log - (int.nat σ.(invariant.diskEnd) - int.nat start))%nat)
      with (int.Z start + length log) by word.
    apply Htxnpos_bound'.
  }

  iPureIntro.
  split; first by rewrite Nat.sub_diag take_0 subslice_zero_length //.
  split.
  {
    rewrite Nat.sub_diag.
    rewrite subslice_drop_take.
    2: lia.
    rewrite drop_drop Nat.add_0_r Nat.sub_0_r.
    rewrite subslice_drop_take in His_diskEnd'.
    2: lia.
    replace (int.nat diskEnd - int.nat start -
      (int.nat σ.(invariant.diskEnd) - int.nat start))%nat
      with (int.nat diskEnd - int.nat σ.(invariant.diskEnd))%nat
      in His_diskEnd' by lia.
    apply His_diskEnd'.
  }
  split.
  {
    rewrite subslice_drop_take.
    2: lia.
    rewrite drop_drop.
    rewrite subslice_drop_take in His_loggerEnd'.
    2: lia.
    replace (int.nat logger_pos' - int.nat start -
      (int.nat diskEnd - int.nat start))%nat
      with (int.nat logger_pos' - int.nat diskEnd)%nat
      in His_loggerEnd' by lia.
    replace (int.nat logger_pos' - int.nat σ.(invariant.diskEnd) -
      (int.nat diskEnd - int.nat σ.(invariant.diskEnd)))%nat
      with (int.nat logger_pos' - int.nat diskEnd)%nat by lia.
    replace (int.nat σ.(invariant.diskEnd) - int.nat start +
      (int.nat diskEnd - int.nat σ.(invariant.diskEnd)))%nat
      with (int.nat diskEnd - int.nat start)%nat by lia.
    apply His_loggerEnd'.
  }
  split.
  {
    rewrite subslice_drop_take.
    2: lia.
    rewrite drop_drop.
    rewrite subslice_drop_take in His_nextDiskEnd'.
    2: lia.
    replace (int.nat mutable - int.nat start -
      (int.nat logger_pos' - int.nat start))%nat
      with (int.nat mutable - int.nat logger_pos')%nat
      in His_nextDiskEnd' by lia.
    replace (int.nat mutable - int.nat σ.(invariant.diskEnd) -
      (int.nat logger_pos' - int.nat σ.(invariant.diskEnd)))%nat
      with (int.nat mutable - int.nat logger_pos')%nat by lia.
    replace (int.nat σ.(invariant.diskEnd) - int.nat start +
      (int.nat logger_pos' - int.nat σ.(invariant.diskEnd)))%nat
      with (int.nat logger_pos' - int.nat start)%nat by lia.
    apply His_nextDiskEnd'.
  }
  rewrite drop_drop.
  replace (int.nat σ.(invariant.diskEnd) - int.nat start +
    (int.nat mutable - int.nat σ.(invariant.diskEnd)))%nat
    with (int.nat mutable - int.nat start)%nat by lia.
  by apply His_nextTxn'.
Qed.

Theorem wp_Walog__installer γ l dinit :
  {{{ "#Hwal" ∷ is_wal P l γ dinit ∗
      "Hinstaller" ∷ installer_inv γ }}}
    Walog__installer #l
  {{{ RET #(); True }}}.
Proof.
  wp_start.
  iMod (is_wal_read_mem with "Hwal") as "#Hmem".
  wp_call.
  iNamed "Hmem".
  iNamed "Hstfields".
  wp_loadField.
  wp_apply (acquire_spec with "lk").
  iIntros "[Hlocked Hlockinv]".
  wp_apply (wp_inc_nthread with "[$Hlockinv $st]"); iIntros "Hlockinv".
  wp_pures.
  wp_bind (For _ _ _).
  wp_apply (wp_forBreak_cond (fun _ =>
    "Hlockinv" ∷ wal_linv σₛ.(wal_st) γ ∗
    "Hlocked" ∷ locked #σₛ.(memLock) ∗
    "Hinstaller" ∷ installer_inv γ
  )%I with "[] [$Hlocked $Hlockinv $Hinstaller]").
  { clear post Φ.
    iIntros "!>" (Φ) "I HΦ"; iNamed "I".
    wp_apply (wp_load_shutdown with "[$st $Hlockinv]"); iIntros (shutdown) "Hlockinv".
    wp_pures.
    wp_if_destruct.
    - wp_pures.
      wp_apply (wp_Walog__logInstall with "[$Hwal $st $d $lk $memlock $condInstall $cond_install $Hlocked $Hlockinv $Hinstaller]").
      1: apply 0%nat.
      iIntros (blkCount installEnd) "post"; iNamed "post".
      wp_pures.
      wp_bind (If _ _ _).
      wp_if_destruct.
      { wp_apply util_proof.wp_DPrintf; wp_pures.
        iApply ("HΦ" with "[$]"). }
      wp_loadField.
      wp_apply (wp_condWait with "[$cond_install $lk $His_locked $Hlkinv]").
      iIntros "[His_locked Hlkinv]".
      wp_pures.
      iApply ("HΦ" with "[$]").
    - iApply ("HΦ" with "[$]"). }
  iIntros "I"; iNamed "I".
  wp_apply util_proof.wp_DPrintf.
  wp_apply (wp_dec_nthread with "[$Hlockinv $st]"); iIntros "Hlockinv".
  wp_loadField.
  wp_apply (wp_condSignal with "[$cond_shut]").
  wp_loadField.
  wp_apply (release_spec with "[$lk $Hlocked $Hlockinv]").
  by iApply ("HΦ" with "[$]").
Qed.

End goose_lang.
