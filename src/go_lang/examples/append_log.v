(* autogenerated from append_log *)
From Perennial.go_lang Require Import prelude.

(* disk FFI *)
From Perennial.go_lang Require Import ffi.disk.
Existing Instances disk_op disk_model disk_ty.
Local Coercion Var' (s: string) := Var s.

Module Log.
  Definition S := struct.new [
    "sz"; "diskSz"
  ].
  Definition T: ty := intT * intT.
  Section fields.
    Context `{ext_ty: ext_types}.
    Definition get := struct.get S.
  End fields.
End Log.

Definition writeHdr: val :=
  λ: "log",
    let: "hdr" := NewSlice byteT #4096 in
    UInt64Put "hdr" (Log.get "sz" "log");;
    UInt64Put (SliceSkip "hdr" #8) (Log.get "sz" "log");;
    disk.Write #0 "hdr".

Definition Init: val :=
  λ: "diskSz",
    if: "diskSz" < #1
    then
      (struct.mk Log.S [
         "sz" ::= #0;
         "diskSz" ::= #0
       ], #false)
    else
      let: "log" := struct.mk Log.S [
        "sz" ::= #0;
        "diskSz" ::= "diskSz"
      ] in
      writeHdr "log";;
      ("log", #true).

Definition Get: val :=
  λ: "log" "i",
    let: "sz" := Log.get "sz" "log" in
    if: "i" < "sz"
    then (disk.Read (#1 + "i"), #true)
    else (slice.nil, #false).

Definition writeAll: val :=
  λ: "bks" "off",
    let: "numBks" := slice.len "bks" in
    let: "i" := ref #0 in
    for: (!"i" < "numBks"); ("i" <- !"i" + #1) :=
      let: "bk" := SliceGet "bks" !"i" in
      disk.Write ("off" + !"i") "bk";;
      Continue.

Definition Append: val :=
  λ: "log" "bks",
    let: "sz" := Log.get "sz" !"log" in
    if: #1 + "sz" + slice.len "bks" ≥ Log.get "diskSz" !"log"
    then #false
    else
      writeAll "bks" (#1 + "sz");;
      let: "newLog" := struct.mk Log.S [
        "sz" ::= "sz" + slice.len "bks";
        "diskSz" ::= Log.get "diskSz" !"log"
      ] in
      writeHdr "newLog";;
      "log" <- "newLog";;
      #true.

Definition Reset: val :=
  λ: "log",
    let: "newLog" := struct.mk Log.S [
      "sz" ::= #0;
      "diskSz" ::= Log.get "diskSz" !"log"
    ] in
    writeHdr "newLog";;
    "log" <- "newLog".
