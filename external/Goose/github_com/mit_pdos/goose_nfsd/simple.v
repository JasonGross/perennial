(* autogenerated from github.com/mit-pdos/goose-nfsd/simple *)
From Perennial.goose_lang Require Import prelude.
From Perennial.goose_lang Require Import ffi.disk_prelude.

From Goose Require github_com.mit_pdos.goose_nfsd.addr.
From Goose Require github_com.mit_pdos.goose_nfsd.buf.
From Goose Require github_com.mit_pdos.goose_nfsd.buftxn.
From Goose Require github_com.mit_pdos.goose_nfsd.common.
From Goose Require github_com.mit_pdos.goose_nfsd.fh.
From Goose Require github_com.mit_pdos.goose_nfsd.lockmap.
From Goose Require github_com.mit_pdos.goose_nfsd.nfstypes.
From Goose Require github_com.mit_pdos.goose_nfsd.txn.
From Goose Require github_com.mit_pdos.goose_nfsd.util.
From Goose Require github_com.tchajed.marshal.

(* 0super.go *)

Definition block2addr: val :=
  rec: "block2addr" "blkno" :=
    addr.MkAddr "blkno" #0.

Definition nInode: val :=
  rec: "nInode" <> :=
    common.INODEBLK.

Definition inum2Addr: val :=
  rec: "inum2Addr" "inum" :=
    addr.MkAddr common.LOGSIZE ("inum" * common.INODESZ * #8).

(* inode.go *)

Module Inode.
  Definition S := struct.decl [
    "Inum" :: uint64T;
    "Size" :: uint64T;
    "Data" :: uint64T
  ].
End Inode.

Definition Inode__Encode: val :=
  rec: "Inode__Encode" "ip" :=
    let: "enc" := marshal.NewEnc common.INODESZ in
    marshal.Enc__PutInt "enc" (struct.loadF Inode.S "Size" "ip");;
    marshal.Enc__PutInt "enc" (struct.loadF Inode.S "Data" "ip");;
    marshal.Enc__Finish "enc".

Definition Decode: val :=
  rec: "Decode" "buf" "inum" :=
    let: "ip" := struct.alloc Inode.S (zero_val (struct.t Inode.S)) in
    let: "dec" := marshal.NewDec (struct.loadF buf.Buf.S "Data" "buf") in
    struct.storeF Inode.S "Inum" "ip" "inum";;
    struct.storeF Inode.S "Size" "ip" (marshal.Dec__GetInt "dec");;
    struct.storeF Inode.S "Data" "ip" (marshal.Dec__GetInt "dec");;
    "ip".

(* Returns number of bytes read and eof *)
Definition Inode__Read: val :=
  rec: "Inode__Read" "ip" "btxn" "offset" "bytesToRead" :=
    (if: "offset" ≥ struct.loadF Inode.S "Size" "ip"
    then (slice.nil, #true)
    else
      let: "count" := ref_to uint64T "bytesToRead" in
      (if: ![uint64T] "count" ≥ "offset" + struct.loadF Inode.S "Size" "ip"
      then
        "count" <-[uint64T] struct.loadF Inode.S "Size" "ip" - "offset";;
        #()
      else #());;
      util.DPrintf #5 (#(str"Read: off %d cnt %d
      ")) #();;
      let: "data" := ref_to (slice.T byteT) (NewSlice byteT #0) in
      let: "buf" := buftxn.BufTxn__ReadBuf "btxn" (block2addr (struct.loadF Inode.S "Data" "ip")) common.NBITBLOCK in
      let: "b" := ref_to uint64T #0 in
      (for: (λ: <>, ![uint64T] "b" < ![uint64T] "count"); (λ: <>, "b" <-[uint64T] ![uint64T] "b" + #1) := λ: <>,
        "data" <-[slice.T byteT] SliceAppend byteT (![slice.T byteT] "data") (SliceGet byteT (struct.loadF buf.Buf.S "Data" "buf") ("offset" + ![uint64T] "b"));;
        Continue);;
      util.DPrintf #10 (#(str"Read: off %d cnt %d -> %v
      ")) #();;
      (![slice.T byteT] "data", #false)).

Definition Inode__WriteInode: val :=
  rec: "Inode__WriteInode" "ip" "btxn" :=
    let: "d" := Inode__Encode "ip" in
    buftxn.BufTxn__OverWrite "btxn" (inum2Addr (struct.loadF Inode.S "Inum" "ip")) (common.INODESZ * #8) "d";;
    util.DPrintf #1 (#(str"WriteInode %v
    ")) #().

(* Returns number of bytes written and error *)
Definition Inode__Write: val :=
  rec: "Inode__Write" "ip" "btxn" "offset" "count" "dataBuf" :=
    util.DPrintf #5 (#(str"Write: off %d cnt %d
    ")) #();;
    (if: "count" ≠ slice.len "dataBuf"
    then (#0, #false)
    else
      (if: "offset" + "count" > disk.BlockSize
      then (#0, #false)
      else
        let: "buffer" := buftxn.BufTxn__ReadBuf "btxn" (block2addr (struct.loadF Inode.S "Data" "ip")) common.NBITBLOCK in
        let: "b" := ref_to uint64T #0 in
        (for: (λ: <>, ![uint64T] "b" < "count"); (λ: <>, "b" <-[uint64T] ![uint64T] "b" + #1) := λ: <>,
          SliceSet byteT (struct.loadF buf.Buf.S "Data" "buffer") ("offset" + ![uint64T] "b") (SliceGet byteT "dataBuf" (![uint64T] "b"));;
          Continue);;
        buf.Buf__SetDirty "buffer";;
        util.DPrintf #1 (#(str"Write: off %d cnt %d size %d
        ")) #();;
        (if: "offset" + "count" > struct.loadF Inode.S "Size" "ip"
        then
          struct.storeF Inode.S "Size" "ip" ("offset" + "count");;
          Inode__WriteInode "ip" "btxn";;
          #()
        else #());;
        ("count", #true))).

Definition ReadInode: val :=
  rec: "ReadInode" "btxn" "inum" :=
    let: "buffer" := buftxn.BufTxn__ReadBuf "btxn" (inum2Addr "inum") (common.INODESZ * #8) in
    let: "ip" := Decode "buffer" "inum" in
    "ip".

Definition Inode__MkFattr: val :=
  rec: "Inode__MkFattr" "ip" :=
    struct.mk nfstypes.Fattr3.S [
      "Ftype" ::= nfstypes.NF3REG;
      "Mode" ::= #(U32 511);
      "Nlink" ::= #(U32 1);
      "Uid" ::= #(U32 0);
      "Gid" ::= #(U32 0);
      "Size" ::= struct.loadF Inode.S "Size" "ip";
      "Used" ::= struct.loadF Inode.S "Size" "ip";
      "Rdev" ::= struct.mk nfstypes.Specdata3.S [
        "Specdata1" ::= #(U32 0);
        "Specdata2" ::= #(U32 0)
      ];
      "Fsid" ::= #0;
      "Fileid" ::= struct.loadF Inode.S "Inum" "ip";
      "Atime" ::= struct.mk nfstypes.Nfstime3.S [
        "Seconds" ::= #(U32 0);
        "Nseconds" ::= #(U32 0)
      ];
      "Mtime" ::= struct.mk nfstypes.Nfstime3.S [
        "Seconds" ::= #(U32 0);
        "Nseconds" ::= #(U32 0)
      ];
      "Ctime" ::= struct.mk nfstypes.Nfstime3.S [
        "Seconds" ::= #(U32 0);
        "Nseconds" ::= #(U32 0)
      ]
    ].

Definition inodeInit: val :=
  rec: "inodeInit" "btxn" :=
    let: "i" := ref_to uint64T #0 in
    (for: (λ: <>, ![uint64T] "i" < nInode #()); (λ: <>, "i" <-[uint64T] ![uint64T] "i" + #1) := λ: <>,
      let: "ip" := ReadInode "btxn" (![uint64T] "i") in
      struct.storeF Inode.S "Data" "ip" (common.LOGSIZE + #1 + ![uint64T] "i");;
      Inode__WriteInode "ip" "btxn";;
      Continue).

(* mount.go *)

Definition Nfs__MOUNTPROC3_NULL: val :=
  rec: "Nfs__MOUNTPROC3_NULL" "nfs" :=
    #().

Definition Nfs__MOUNTPROC3_MNT: val :=
  rec: "Nfs__MOUNTPROC3_MNT" "nfs" "args" :=
    let: "reply" := struct.alloc nfstypes.Mountres3.S (zero_val (struct.t nfstypes.Mountres3.S)) in
    (* log.Printf("Mount %v\n", args) *)
    struct.storeF nfstypes.Mountres3.S "Fhs_status" "reply" nfstypes.MNT3_OK;;
    struct.storeF nfstypes.Mountres3_ok.S "Fhandle" (struct.fieldRef nfstypes.Mountres3.S "Mountinfo" "reply") (struct.get nfstypes.Nfs_fh3.S "Data" (fh.MkRootFh3 #()));;
    struct.load nfstypes.Mountres3.S "reply".

Definition Nfs__MOUNTPROC3_UMNT: val :=
  rec: "Nfs__MOUNTPROC3_UMNT" "nfs" "args" :=
    (* log.Printf("Unmount %v\n", args) *)
    #().

Definition Nfs__MOUNTPROC3_UMNTALL: val :=
  rec: "Nfs__MOUNTPROC3_UMNTALL" "nfs" :=
    (* log.Printf("Unmountall\n") *)
    #().

Definition Nfs__MOUNTPROC3_DUMP: val :=
  rec: "Nfs__MOUNTPROC3_DUMP" "nfs" :=
    (* log.Printf("Dump\n") *)
    struct.mk nfstypes.Mountopt3.S [
      "P" ::= slice.nil
    ].

Definition Nfs__MOUNTPROC3_EXPORT: val :=
  rec: "Nfs__MOUNTPROC3_EXPORT" "nfs" :=
    let: "res" := struct.mk nfstypes.Exports3.S [
      "Ex_dir" ::= #(str"");
      "Ex_groups" ::= slice.nil;
      "Ex_next" ::= slice.nil
    ] in
    struct.storeF nfstypes.Exports3.S "Ex_dir" "res" #(str"/");;
    struct.mk nfstypes.Exportsopt3.S [
      "P" ::= "res"
    ].

(* ops.go *)

Module Nfs.
  Definition S := struct.decl [
    "t" :: struct.ptrT txn.Txn.S;
    "l" :: struct.ptrT lockmap.LockMap.S
  ].
End Nfs.

Definition fh2ino: val :=
  rec: "fh2ino" "fh3" :=
    let: "fh" := fh.MakeFh "fh3" in
    struct.get fh.Fh.S "Ino" "fh".

Definition rootFattr: val :=
  rec: "rootFattr" <> :=
    struct.mk nfstypes.Fattr3.S [
      "Ftype" ::= nfstypes.NF3DIR;
      "Mode" ::= #(U32 511);
      "Nlink" ::= #(U32 1);
      "Uid" ::= #(U32 0);
      "Gid" ::= #(U32 0);
      "Size" ::= #0;
      "Used" ::= #0;
      "Rdev" ::= struct.mk nfstypes.Specdata3.S [
        "Specdata1" ::= #(U32 0);
        "Specdata2" ::= #(U32 0)
      ];
      "Fsid" ::= #0;
      "Fileid" ::= common.ROOTINUM;
      "Atime" ::= struct.mk nfstypes.Nfstime3.S [
        "Seconds" ::= #(U32 0);
        "Nseconds" ::= #(U32 0)
      ];
      "Mtime" ::= struct.mk nfstypes.Nfstime3.S [
        "Seconds" ::= #(U32 0);
        "Nseconds" ::= #(U32 0)
      ];
      "Ctime" ::= struct.mk nfstypes.Nfstime3.S [
        "Seconds" ::= #(U32 0);
        "Nseconds" ::= #(U32 0)
      ]
    ].

Definition Nfs__NFSPROC3_NULL: val :=
  rec: "Nfs__NFSPROC3_NULL" "nfs" :=
    util.DPrintf #0 (#(str"NFS Null
    ")) #().

Definition Nfs__NFSPROC3_GETATTR: val :=
  rec: "Nfs__NFSPROC3_GETATTR" "nfs" "args" :=
    let: "reply" := ref (zero_val (struct.t nfstypes.GETATTR3res.S)) in
    util.DPrintf #1 (#(str"NFS GetAttr %v
    ")) #();;
    let: "txn" := buftxn.Begin (struct.loadF Nfs.S "t" "nfs") in
    let: "inum" := fh2ino (struct.get nfstypes.GETATTR3args.S "Object" "args") in
    (if: ("inum" = common.ROOTINUM)
    then
      struct.storeF nfstypes.GETATTR3res.S "Status" "reply" nfstypes.NFS3_OK;;
      struct.storeF nfstypes.GETATTR3resok.S "Obj_attributes" (struct.fieldRef nfstypes.GETATTR3res.S "Resok" "reply") (rootFattr #());;
      ![struct.t nfstypes.GETATTR3res.S] "reply"
    else
      (if: "inum" ≥ nInode #()
      then
        struct.storeF nfstypes.GETATTR3res.S "Status" "reply" nfstypes.NFS3ERR_INVAL;;
        ![struct.t nfstypes.GETATTR3res.S] "reply"
      else
        lockmap.LockMap__Acquire (struct.loadF Nfs.S "l" "nfs") "inum";;
        let: "ip" := ReadInode "txn" "inum" in
        struct.storeF nfstypes.GETATTR3resok.S "Obj_attributes" (struct.fieldRef nfstypes.GETATTR3res.S "Resok" "reply") (Inode__MkFattr "ip");;
        let: "ok" := buftxn.BufTxn__CommitWait "txn" #true in
        (if: "ok"
        then struct.storeF nfstypes.GETATTR3res.S "Status" "reply" nfstypes.NFS3_OK
        else struct.storeF nfstypes.GETATTR3res.S "Status" "reply" nfstypes.NFS3ERR_SERVERFAULT);;
        lockmap.LockMap__Release (struct.loadF Nfs.S "l" "nfs") "inum";;
        ![struct.t nfstypes.GETATTR3res.S] "reply")).

Definition Nfs__NFSPROC3_SETATTR: val :=
  rec: "Nfs__NFSPROC3_SETATTR" "nfs" "args" :=
    let: "reply" := ref (zero_val (struct.t nfstypes.SETATTR3res.S)) in
    util.DPrintf #1 (#(str"NFS SetAttr %v
    ")) #();;
    let: "txn" := buftxn.Begin (struct.loadF Nfs.S "t" "nfs") in
    let: "inum" := fh2ino (struct.get nfstypes.SETATTR3args.S "Object" "args") in
    util.DPrintf #1 (#(str"inum %d %d
    ")) #();;
    (if: ("inum" = common.ROOTINUM) || ("inum" ≥ nInode #())
    then
      struct.storeF nfstypes.SETATTR3res.S "Status" "reply" nfstypes.NFS3ERR_INVAL;;
      ![struct.t nfstypes.SETATTR3res.S] "reply"
    else
      lockmap.LockMap__Acquire (struct.loadF Nfs.S "l" "nfs") "inum";;
      let: "ip" := ReadInode "txn" "inum" in
      (if: struct.get nfstypes.Set_size3.S "Set_it" (struct.get nfstypes.Sattr3.S "Size" (struct.get nfstypes.SETATTR3args.S "New_attributes" "args"))
      then
        let: "newsize" := struct.get nfstypes.Set_size3.S "Size" (struct.get nfstypes.Sattr3.S "Size" (struct.get nfstypes.SETATTR3args.S "New_attributes" "args")) in
        (if: struct.loadF Inode.S "Size" "ip" < "newsize"
        then
          let: "data" := NewSlice byteT ("newsize" - struct.loadF Inode.S "Size" "ip") in
          let: ("count", "writeok") := Inode__Write "ip" "txn" (struct.loadF Inode.S "Size" "ip") ("newsize" - struct.loadF Inode.S "Size" "ip") "data" in
          (if: (~ "writeok") || ("count" ≠ "newsize" - struct.loadF Inode.S "Size" "ip")
          then
            struct.storeF nfstypes.SETATTR3res.S "Status" "reply" nfstypes.NFS3ERR_NOSPC;;
            lockmap.LockMap__Release (struct.loadF Nfs.S "l" "nfs") "inum";;
            ![struct.t nfstypes.SETATTR3res.S] "reply"
          else #())
        else
          struct.storeF Inode.S "Size" "ip" "newsize";;
          Inode__WriteInode "ip" "txn");;
        #()
      else #());;
      let: "ok" := buftxn.BufTxn__CommitWait "txn" #true in
      (if: "ok"
      then struct.storeF nfstypes.SETATTR3res.S "Status" "reply" nfstypes.NFS3_OK
      else struct.storeF nfstypes.SETATTR3res.S "Status" "reply" nfstypes.NFS3ERR_SERVERFAULT);;
      lockmap.LockMap__Release (struct.loadF Nfs.S "l" "nfs") "inum";;
      ![struct.t nfstypes.SETATTR3res.S] "reply").

(* Lookup must lock child inode to find gen number *)
Definition Nfs__NFSPROC3_LOOKUP: val :=
  rec: "Nfs__NFSPROC3_LOOKUP" "nfs" "args" :=
    util.DPrintf #1 (#(str"NFS Lookup %v
    ")) #();;
    let: "reply" := ref (zero_val (struct.t nfstypes.LOOKUP3res.S)) in
    let: "fn" := struct.get nfstypes.Diropargs3.S "Name" (struct.get nfstypes.LOOKUP3args.S "What" "args") in
    let: "inum" := ref (zero_val uint64T) in
    (if: ("fn" = #(str"a"))
    then
      "inum" <-[uint64T] #2;;
      #()
    else #());;
    (if: ("fn" = #(str"b"))
    then
      "inum" <-[uint64T] #3;;
      #()
    else #());;
    (if: (![uint64T] "inum" = #0) || (![uint64T] "inum" = common.ROOTINUM) || (![uint64T] "inum" ≥ nInode #())
    then
      struct.storeF nfstypes.LOOKUP3res.S "Status" "reply" nfstypes.NFS3ERR_NOENT;;
      ![struct.t nfstypes.LOOKUP3res.S] "reply"
    else
      let: "fh" := struct.mk fh.Fh.S [
        "Ino" ::= ![uint64T] "inum";
        "Gen" ::= #0
      ] in
      struct.storeF nfstypes.LOOKUP3resok.S "Object" (struct.fieldRef nfstypes.LOOKUP3res.S "Resok" "reply") (fh.Fh__MakeFh3 "fh");;
      struct.storeF nfstypes.LOOKUP3res.S "Status" "reply" nfstypes.NFS3_OK;;
      ![struct.t nfstypes.LOOKUP3res.S] "reply").

Definition Nfs__NFSPROC3_ACCESS: val :=
  rec: "Nfs__NFSPROC3_ACCESS" "nfs" "args" :=
    util.DPrintf #1 (#(str"NFS Access %v
    ")) #();;
    let: "reply" := ref (zero_val (struct.t nfstypes.ACCESS3res.S)) in
    struct.storeF nfstypes.ACCESS3res.S "Status" "reply" nfstypes.NFS3_OK;;
    struct.storeF nfstypes.ACCESS3resok.S "Access" (struct.fieldRef nfstypes.ACCESS3res.S "Resok" "reply") (nfstypes.ACCESS3_READ `or` nfstypes.ACCESS3_LOOKUP `or` nfstypes.ACCESS3_MODIFY `or` nfstypes.ACCESS3_EXTEND `or` nfstypes.ACCESS3_DELETE `or` nfstypes.ACCESS3_EXECUTE);;
    ![struct.t nfstypes.ACCESS3res.S] "reply".

Definition Nfs__NFSPROC3_READ: val :=
  rec: "Nfs__NFSPROC3_READ" "nfs" "args" :=
    let: "reply" := ref (zero_val (struct.t nfstypes.READ3res.S)) in
    util.DPrintf #1 (#(str"NFS Read %v %d %d
    ")) #();;
    let: "txn" := buftxn.Begin (struct.loadF Nfs.S "t" "nfs") in
    let: "inum" := fh2ino (struct.get nfstypes.READ3args.S "File" "args") in
    (if: ("inum" = common.ROOTINUM) || ("inum" ≥ nInode #())
    then
      struct.storeF nfstypes.READ3res.S "Status" "reply" nfstypes.NFS3ERR_INVAL;;
      ![struct.t nfstypes.READ3res.S] "reply"
    else
      lockmap.LockMap__Acquire (struct.loadF Nfs.S "l" "nfs") "inum";;
      let: "ip" := ReadInode "txn" "inum" in
      let: ("data", "eof") := Inode__Read "ip" "txn" (struct.get nfstypes.READ3args.S "Offset" "args") (to_u64 (struct.get nfstypes.READ3args.S "Count" "args")) in
      let: "ok" := buftxn.BufTxn__CommitWait "txn" #true in
      (if: "ok"
      then
        struct.storeF nfstypes.READ3res.S "Status" "reply" nfstypes.NFS3_OK;;
        struct.storeF nfstypes.READ3resok.S "Count" (struct.fieldRef nfstypes.READ3res.S "Resok" "reply") (slice.len "data");;
        struct.storeF nfstypes.READ3resok.S "Data" (struct.fieldRef nfstypes.READ3res.S "Resok" "reply") "data";;
        struct.storeF nfstypes.READ3resok.S "Eof" (struct.fieldRef nfstypes.READ3res.S "Resok" "reply") "eof"
      else struct.storeF nfstypes.READ3res.S "Status" "reply" nfstypes.NFS3ERR_SERVERFAULT);;
      lockmap.LockMap__Release (struct.loadF Nfs.S "l" "nfs") "inum";;
      ![struct.t nfstypes.READ3res.S] "reply").

Definition Nfs__NFSPROC3_WRITE: val :=
  rec: "Nfs__NFSPROC3_WRITE" "nfs" "args" :=
    let: "reply" := ref (zero_val (struct.t nfstypes.WRITE3res.S)) in
    util.DPrintf #1 (#(str"NFS Write %v off %d cnt %d how %d
    ")) #();;
    let: "txn" := buftxn.Begin (struct.loadF Nfs.S "t" "nfs") in
    let: "inum" := fh2ino (struct.get nfstypes.WRITE3args.S "File" "args") in
    util.DPrintf #1 (#(str"inum %d %d
    ")) #();;
    (if: ("inum" = common.ROOTINUM) || ("inum" ≥ nInode #())
    then
      struct.storeF nfstypes.WRITE3res.S "Status" "reply" nfstypes.NFS3ERR_INVAL;;
      ![struct.t nfstypes.WRITE3res.S] "reply"
    else
      lockmap.LockMap__Acquire (struct.loadF Nfs.S "l" "nfs") "inum";;
      let: "ip" := ReadInode "txn" "inum" in
      let: ("count", "writeok") := Inode__Write "ip" "txn" (struct.get nfstypes.WRITE3args.S "Offset" "args") (to_u64 (struct.get nfstypes.WRITE3args.S "Count" "args")) (struct.get nfstypes.WRITE3args.S "Data" "args") in
      (if: ~ "writeok"
      then
        lockmap.LockMap__Release (struct.loadF Nfs.S "l" "nfs") "inum";;
        struct.storeF nfstypes.WRITE3res.S "Status" "reply" nfstypes.NFS3ERR_SERVERFAULT;;
        ![struct.t nfstypes.WRITE3res.S] "reply"
      else
        let: "ok" := ref (zero_val boolT) in
        (if: (struct.get nfstypes.WRITE3args.S "Stable" "args" = nfstypes.FILE_SYNC)
        then "ok" <-[boolT] buftxn.BufTxn__CommitWait "txn" #true
        else
          (if: (struct.get nfstypes.WRITE3args.S "Stable" "args" = nfstypes.DATA_SYNC)
          then "ok" <-[boolT] buftxn.BufTxn__CommitWait "txn" #true
          else "ok" <-[boolT] buftxn.BufTxn__CommitWait "txn" #false));;
        (if: ![boolT] "ok"
        then
          struct.storeF nfstypes.WRITE3res.S "Status" "reply" nfstypes.NFS3_OK;;
          struct.storeF nfstypes.WRITE3resok.S "Count" (struct.fieldRef nfstypes.WRITE3res.S "Resok" "reply") "count";;
          struct.storeF nfstypes.WRITE3resok.S "Committed" (struct.fieldRef nfstypes.WRITE3res.S "Resok" "reply") (struct.get nfstypes.WRITE3args.S "Stable" "args")
        else struct.storeF nfstypes.WRITE3res.S "Status" "reply" nfstypes.NFS3ERR_SERVERFAULT);;
        lockmap.LockMap__Release (struct.loadF Nfs.S "l" "nfs") "inum";;
        ![struct.t nfstypes.WRITE3res.S] "reply")).

Definition Nfs__NFSPROC3_CREATE: val :=
  rec: "Nfs__NFSPROC3_CREATE" "nfs" "args" :=
    util.DPrintf #1 (#(str"NFS Create %v
    ")) #();;
    let: "reply" := ref (zero_val (struct.t nfstypes.CREATE3res.S)) in
    struct.storeF nfstypes.CREATE3res.S "Status" "reply" nfstypes.NFS3ERR_NOTSUPP;;
    ![struct.t nfstypes.CREATE3res.S] "reply".

Definition Nfs__NFSPROC3_MKDIR: val :=
  rec: "Nfs__NFSPROC3_MKDIR" "nfs" "args" :=
    util.DPrintf #1 (#(str"NFS Mkdir %v
    ")) #();;
    let: "reply" := ref (zero_val (struct.t nfstypes.MKDIR3res.S)) in
    struct.storeF nfstypes.MKDIR3res.S "Status" "reply" nfstypes.NFS3ERR_NOTSUPP;;
    ![struct.t nfstypes.MKDIR3res.S] "reply".

Definition Nfs__NFSPROC3_SYMLINK: val :=
  rec: "Nfs__NFSPROC3_SYMLINK" "nfs" "args" :=
    util.DPrintf #1 (#(str"NFS Symlink %v
    ")) #();;
    let: "reply" := ref (zero_val (struct.t nfstypes.SYMLINK3res.S)) in
    struct.storeF nfstypes.SYMLINK3res.S "Status" "reply" nfstypes.NFS3ERR_NOTSUPP;;
    ![struct.t nfstypes.SYMLINK3res.S] "reply".

Definition Nfs__NFSPROC3_READLINK: val :=
  rec: "Nfs__NFSPROC3_READLINK" "nfs" "args" :=
    util.DPrintf #1 (#(str"NFS Readlink %v
    ")) #();;
    let: "reply" := ref (zero_val (struct.t nfstypes.READLINK3res.S)) in
    struct.storeF nfstypes.READLINK3res.S "Status" "reply" nfstypes.NFS3ERR_NOTSUPP;;
    ![struct.t nfstypes.READLINK3res.S] "reply".

Definition Nfs__NFSPROC3_MKNOD: val :=
  rec: "Nfs__NFSPROC3_MKNOD" "nfs" "args" :=
    util.DPrintf #1 (#(str"NFS Mknod %v
    ")) #();;
    let: "reply" := ref (zero_val (struct.t nfstypes.MKNOD3res.S)) in
    struct.storeF nfstypes.MKNOD3res.S "Status" "reply" nfstypes.NFS3ERR_NOTSUPP;;
    ![struct.t nfstypes.MKNOD3res.S] "reply".

Definition Nfs__NFSPROC3_REMOVE: val :=
  rec: "Nfs__NFSPROC3_REMOVE" "nfs" "args" :=
    util.DPrintf #1 (#(str"NFS Remove %v
    ")) #();;
    let: "reply" := ref (zero_val (struct.t nfstypes.REMOVE3res.S)) in
    struct.storeF nfstypes.REMOVE3res.S "Status" "reply" nfstypes.NFS3ERR_NOTSUPP;;
    ![struct.t nfstypes.REMOVE3res.S] "reply".

Definition Nfs__NFSPROC3_RMDIR: val :=
  rec: "Nfs__NFSPROC3_RMDIR" "nfs" "args" :=
    util.DPrintf #1 (#(str"NFS Rmdir %v
    ")) #();;
    let: "reply" := ref (zero_val (struct.t nfstypes.RMDIR3res.S)) in
    struct.storeF nfstypes.RMDIR3res.S "Status" "reply" nfstypes.NFS3ERR_NOTSUPP;;
    ![struct.t nfstypes.RMDIR3res.S] "reply".

Definition Nfs__NFSPROC3_RENAME: val :=
  rec: "Nfs__NFSPROC3_RENAME" "nfs" "args" :=
    util.DPrintf #1 (#(str"NFS Rename %v
    ")) #();;
    let: "reply" := ref (zero_val (struct.t nfstypes.RENAME3res.S)) in
    struct.storeF nfstypes.RENAME3res.S "Status" "reply" nfstypes.NFS3ERR_NOTSUPP;;
    ![struct.t nfstypes.RENAME3res.S] "reply".

Definition Nfs__NFSPROC3_LINK: val :=
  rec: "Nfs__NFSPROC3_LINK" "nfs" "args" :=
    util.DPrintf #1 (#(str"NFS Link %v
    ")) #();;
    let: "reply" := ref (zero_val (struct.t nfstypes.LINK3res.S)) in
    struct.storeF nfstypes.LINK3res.S "Status" "reply" nfstypes.NFS3ERR_NOTSUPP;;
    ![struct.t nfstypes.LINK3res.S] "reply".

Definition Nfs__NFSPROC3_READDIR: val :=
  rec: "Nfs__NFSPROC3_READDIR" "nfs" "args" :=
    util.DPrintf #1 (#(str"NFS Readdir %v
    ")) #();;
    let: "reply" := ref (zero_val (struct.t nfstypes.READDIR3res.S)) in
    let: "e2" := struct.new nfstypes.Entry3.S [
      "Fileid" ::= #3;
      "Name" ::= #(str"b");
      "Cookie" ::= #1;
      "Nextentry" ::= slice.nil
    ] in
    let: "e1" := struct.new nfstypes.Entry3.S [
      "Fileid" ::= #2;
      "Name" ::= #(str"a");
      "Cookie" ::= #0;
      "Nextentry" ::= "e2"
    ] in
    struct.storeF nfstypes.READDIR3res.S "Status" "reply" nfstypes.NFS3_OK;;
    struct.storeF nfstypes.READDIR3resok.S "Reply" (struct.fieldRef nfstypes.READDIR3res.S "Resok" "reply") (struct.mk nfstypes.Dirlist3.S [
      "Entries" ::= "e1";
      "Eof" ::= #true
    ]);;
    ![struct.t nfstypes.READDIR3res.S] "reply".

Definition Nfs__NFSPROC3_READDIRPLUS: val :=
  rec: "Nfs__NFSPROC3_READDIRPLUS" "nfs" "args" :=
    util.DPrintf #1 (#(str"NFS Readdirplus %v
    ")) #();;
    let: "reply" := ref (zero_val (struct.t nfstypes.READDIRPLUS3res.S)) in
    struct.storeF nfstypes.READDIRPLUS3res.S "Status" "reply" nfstypes.NFS3ERR_NOTSUPP;;
    ![struct.t nfstypes.READDIRPLUS3res.S] "reply".

Definition Nfs__NFSPROC3_FSSTAT: val :=
  rec: "Nfs__NFSPROC3_FSSTAT" "nfs" "args" :=
    util.DPrintf #1 (#(str"NFS Fsstat %v
    ")) #();;
    let: "reply" := ref (zero_val (struct.t nfstypes.FSSTAT3res.S)) in
    struct.storeF nfstypes.FSSTAT3res.S "Status" "reply" nfstypes.NFS3ERR_NOTSUPP;;
    ![struct.t nfstypes.FSSTAT3res.S] "reply".

Definition Nfs__NFSPROC3_FSINFO: val :=
  rec: "Nfs__NFSPROC3_FSINFO" "nfs" "args" :=
    util.DPrintf #1 (#(str"NFS Fsinfo %v
    ")) #();;
    let: "reply" := ref (zero_val (struct.t nfstypes.FSINFO3res.S)) in
    struct.storeF nfstypes.FSINFO3res.S "Status" "reply" nfstypes.NFS3_OK;;
    struct.storeF nfstypes.FSINFO3resok.S "Wtmax" (struct.fieldRef nfstypes.FSINFO3res.S "Resok" "reply") (#(U32 4096));;
    struct.storeF nfstypes.FSINFO3resok.S "Maxfilesize" (struct.fieldRef nfstypes.FSINFO3res.S "Resok" "reply") #4096;;
    ![struct.t nfstypes.FSINFO3res.S] "reply".

Definition Nfs__NFSPROC3_PATHCONF: val :=
  rec: "Nfs__NFSPROC3_PATHCONF" "nfs" "args" :=
    util.DPrintf #1 (#(str"NFS Pathconf %v
    ")) #();;
    let: "reply" := ref (zero_val (struct.t nfstypes.PATHCONF3res.S)) in
    struct.storeF nfstypes.PATHCONF3res.S "Status" "reply" nfstypes.NFS3ERR_NOTSUPP;;
    ![struct.t nfstypes.PATHCONF3res.S] "reply".

Definition Nfs__NFSPROC3_COMMIT: val :=
  rec: "Nfs__NFSPROC3_COMMIT" "nfs" "args" :=
    util.DPrintf #1 (#(str"NFS Commit %v
    ")) #();;
    let: "reply" := ref (zero_val (struct.t nfstypes.COMMIT3res.S)) in
    let: "txn" := buftxn.Begin (struct.loadF Nfs.S "t" "nfs") in
    let: "ok" := buftxn.BufTxn__CommitWait "txn" #true in
    (if: "ok"
    then struct.storeF nfstypes.COMMIT3res.S "Status" "reply" nfstypes.NFS3_OK
    else struct.storeF nfstypes.COMMIT3res.S "Status" "reply" nfstypes.NFS3ERR_IO);;
    ![struct.t nfstypes.COMMIT3res.S] "reply".

(* start.go *)

Definition MakeNfs: val :=
  rec: "MakeNfs" "d" :=
    let: "txn" := txn.MkTxn "d" in
    let: "btxn" := buftxn.Begin "txn" in
    inodeInit "btxn";;
    let: "ok" := buftxn.BufTxn__CommitWait "btxn" #true in
    (if: ~ "ok"
    then slice.nil
    else
      let: "lockmap" := lockmap.MkLockMap #() in
      let: "nfs" := struct.new Nfs.S [
        "t" ::= "txn";
        "l" ::= "lockmap"
      ] in
      "nfs").
