From Perennial.program_proof Require Import dist_prelude.
From Goose.github_com.mit_pdos.gokv Require Import memkv.
From Perennial.program_proof.lockservice Require Import rpc.
From Perennial.program_proof.memkv Require Import common_proof memkv_shard_clerk_proof memkv_shard_definitions memkv_coord_definitions memkv_marshal_get_proof.

Section memkv_coord_clerk_proof.

Context `{!heapG Σ, rpcG Σ ShardReplyC, rpcregG Σ, kvMapG Σ}.

Definition own_MemKVCoordClerk ck γkv : iProp Σ :=
  ∃ γh host (cl : loc),
    "%Heq_kv_gn" ∷ ⌜ γh.(coord_kv_gn) = γkv ⌝ ∗
    "Hcl" ∷ ck ↦[MemKVCoordClerk :: "cl"] #cl ∗
    "#His_coord" ∷ is_coord_server host γh ∗
    "Hcl_own" ∷ RPCClient_own cl host.

Lemma wp_decodeShardMap data_sl data (shardMapping : list u64) :
  {{{
       "%Henc" ∷ ⌜ has_encoding_shardMapping data shardMapping ⌝ ∗
      "Hsl" ∷ typed_slice.is_slice (V:=u8) data_sl byteT 1 data
  }}}
    decodeShardMap (slice_val data_sl)
  {{{  rep_sl , RET (slice_val rep_sl);
       ⌜ length shardMapping = int.nat 65536 ⌝ ∗
       typed_slice.is_slice rep_sl uint64T 1 shardMapping }}}.
Proof.
  wp_pures. iIntros (Φ) "H HΦ".
  iNamed "H".
  wp_lam.

  iDestruct (typed_slice.is_slice_small_acc with "Hsl") as "[Hsl _]".
  destruct Henc as [Henc Hlen].
  wp_apply (wp_new_dec with "[$Hsl]").
  { done. }
  iIntros (?) "Hdec".
  wp_pures.
  wp_apply (wp_Dec__GetInts _ _ _ _ [] with "[Hdec]").
  { exact Hlen. }
  { rewrite app_nil_r. iFrame. }
  iIntros (?) "(?&H)". iApply "HΦ". iSplit; eauto.
Qed.

Lemma wp_MemKVCoordClerk__GetShardMap (ck:loc) γkv :
  {{{
       own_MemKVCoordClerk ck γkv
  }}}
    MemKVCoordClerk__GetShardMap #ck
  {{{
       shardMap_sl (shardMapping:list u64), RET (slice_val shardMap_sl);
       own_MemKVCoordClerk ck γkv ∗
       typed_slice.is_slice shardMap_sl uint64T 1%Qp shardMapping ∗
       ⌜Z.of_nat (length shardMapping) = uNSHARD⌝ ∗
       all_are_shard_servers shardMapping γkv
  }}}
.
Proof.
  iIntros (Φ) "Hclerk HΦ".
  wp_lam.
  wp_apply (wp_ref_of_zero).
  { naive_solver. }
  iIntros (rawRep) "HrawRep".
  wp_pures.
  iAssert (∃ sl, rawRep ↦[slice.T byteT] (slice_val sl))%I with "[HrawRep]" as "HrawRep".
  {
    rewrite zero_slice_val.
    iExists _; iFrame.
  }

  wp_forBreak_cond.
  wp_pures.
  iNamed "Hclerk".
  iNamed "His_coord".
  iNamed "HrawRep".
  wp_apply (typed_slice.wp_NewSlice (V:=u8)).
  iIntros (s) "H".
  wp_loadField.
  wp_apply (wp_RPCClient__Call () with "[Hcl_own H $HrawRep]").
  { iFrame "H". iFrame "Hcl_own".
    rewrite /has_handler. iFrame "HgetSpec". done. }
  iIntros (?) "(Hcl_own & Hreq_sl & Hpost)".
  iDestruct "Hpost" as "[(-> & HrawRep) | (% & % & -> & HrawRep & Hrep_sl & Hpost)]"; wp_pures.
  { (* continue *)
    wp_pures. iLeft.
    iModIntro. iSplit; first done.
    iFrame "HΦ".
    iSplitR "HrawRep"; last first.
    { eauto. }
    iExists _, _, _. iFrame "Hcl". iFrame "Hcl_own".
    iSplitL ""; last first.
    { rewrite /is_coord_server.
      iSplit.
      { iExact "HaddSpec". }
      { iExact "HgetSpec". }
    }
    eauto.
  }
  (* got reply *)
  iRight.
  iModIntro. iSplitL ""; first done.
  wp_pures.
  wp_load.
  iDestruct "Hpost" as (??) "Hcid".
  wp_apply (wp_decodeShardMap with "[$Hrep_sl]").
  { done. }
  iIntros (shardMap_sl) "(%Hlen&HshardMap_sl)".
  iApply "HΦ".
  iFrame "HshardMap_sl". 
  iSplitR "Hcid".
  { iExists _, _, _. iFrame "Hcl". iFrame "Hcl_own".
    iSplitL ""; last first.
    { rewrite /is_coord_server.
      iSplit.
      { iExact "HaddSpec". }
      { iExact "HgetSpec". }
    }
    eauto.
  }
  rewrite Heq_kv_gn. iFrame "Hcid".
  rewrite /uNSHARD.
  iPureIntro. word.
Qed.

Lemma wp_ShardClerkSet__GetClerk (γ:memkv_shard_names) (γkv:gname) (s:loc) (host:u64) :
  {{{
       own_ShardClerkSet s γkv ∗
       is_shard_server host γ ∗
       ⌜γ.(kv_gn) = γkv⌝
  }}}
    ShardClerkSet__GetClerk #s #host
  {{{
       (ck_ptr:loc), RET #ck_ptr; own_MemKVShardClerk ck_ptr γkv ∗
                                    (own_MemKVShardClerk ck_ptr γkv -∗ own_ShardClerkSet s γkv)
  }}}.
Proof.
  iIntros (Φ) "Hpre HΦ".
  wp_lam.
  wp_pures.
  iDestruct "Hpre" as "(Hown & #His_shard & %Hγeq)".
  iNamed "Hown".

  wp_loadField.
  wp_apply (wp_MapGet with "HclsMap").
  iIntros (cl_ptr ok) "[%Hlookup HclsMap]".
  wp_pures.
  wp_if_destruct.
  { (* Make fresh clerk*)
    wp_apply (wp_MakeFreshKVClerk with "His_shard").
    iIntros (ck) "HownCk".
    wp_pures.
    wp_loadField.
    wp_apply (wp_MapInsert with "HclsMap").
    { done. }
    iIntros "HclsMap".
    wp_pures.
    iApply "HΦ".
    iModIntro.
    iFrame "HownCk".
    iIntros "Hown".
    iExists _, _; iFrame "Hcls HclsMap".
    rewrite /typed_map.map_insert.
    apply map_get_false in Hlookup.
    iApply (big_sepM_insert with "[Hown $HclsOwn]").
    { naive_solver. }
    iFrame.
  }
  {
    apply map_get_true in Hlookup.
    iDestruct (big_sepM_lookup_acc with "HclsOwn") as "[Hcl HclsOwn]".
    { done. }
    iApply "HΦ".
    iModIntro.
    iFrame.
    iIntros "Hown".
    iSpecialize ("HclsOwn" with "Hown").
    iExists _, _; iFrame.
  }
Qed.

End memkv_coord_clerk_proof.
