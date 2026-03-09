// Copyright Hewlett Packard Enterprise Development LP.

module OTF2_Callbacks {
  use CTypes;
  use OTF2_GeneralDefinitions;
  require "otf2/OTF2_Callbacks.h";

  // ---- Flush callbacks ----
  extern type OTF2_PreFlushCallback = c_fn_ptr;
  extern type OTF2_PostFlushCallback = c_fn_ptr;

  extern record OTF2_FlushCallbacks {
  var otf2_pre_flush: OTF2_PreFlushCallback;
  var otf2_post_flush: OTF2_PostFlushCallback;
  }

  // ---- Memory callbacks ----
  extern type OTF2_MemoryAllocate = c_fn_ptr;
  extern type OTF2_MemoryFreeAll = c_fn_ptr;

  extern record OTF2_MemoryCallbacks {
  var otf2_allocate: OTF2_MemoryAllocate;
  var otf2_free_all: OTF2_MemoryFreeAll;
  }

  // ---- Collective callbacks ----
  extern record OTF2_CollectiveContext { }

  // Macro constant; define locally to avoid extern of a macro
  param OTF2_COLLECTIVES_ROOT: c_int = 0:c_int;

  extern type OTF2_Collectives_GetSize = c_fn_ptr;
  extern type OTF2_Collectives_GetRank = c_fn_ptr;
  extern type OTF2_Collectives_CreateLocalComm = c_fn_ptr;
  extern type OTF2_Collectives_FreeLocalComm = c_fn_ptr;
  extern type OTF2_Collectives_Barrier = c_fn_ptr;
  extern type OTF2_Collectives_Bcast = c_fn_ptr;
  extern type OTF2_Collectives_Gather = c_fn_ptr;
  extern type OTF2_Collectives_Gatherv = c_fn_ptr;
  extern type OTF2_Collectives_Scatter = c_fn_ptr;
  extern type OTF2_Collectives_Scatterv = c_fn_ptr;
  extern type OTF2_Collectives_Release = c_fn_ptr;

  extern record OTF2_CollectiveCallbacks {
  var otf2_release: OTF2_Collectives_Release;
  var otf2_get_size: OTF2_Collectives_GetSize;
  var otf2_get_rank: OTF2_Collectives_GetRank;
  var otf2_create_local_comm: OTF2_Collectives_CreateLocalComm;
  var otf2_free_local_comm: OTF2_Collectives_FreeLocalComm;
  var otf2_barrier: OTF2_Collectives_Barrier;
  var otf2_bcast: OTF2_Collectives_Bcast;
  var otf2_gather: OTF2_Collectives_Gather;
  var otf2_gatherv: OTF2_Collectives_Gatherv;
  var otf2_scatter: OTF2_Collectives_Scatter;
  var otf2_scatterv: OTF2_Collectives_Scatterv;
  }

  // ---- Locking callbacks ----
  extern type OTF2_Lock = c_ptr(void);

  extern type OTF2_Locking_Create = c_fn_ptr;
  extern type OTF2_Locking_Destroy = c_fn_ptr;
  extern type OTF2_Locking_Lock = c_fn_ptr;
  extern type OTF2_Locking_Unlock = c_fn_ptr;
  extern type OTF2_Locking_Release = c_fn_ptr;

  extern record OTF2_LockingCallbacks {
  var otf2_release: OTF2_Locking_Release;
  var otf2_create: OTF2_Locking_Create;
  var otf2_destroy: OTF2_Locking_Destroy;
  var otf2_lock: OTF2_Locking_Lock;
  var otf2_unlock: OTF2_Locking_Unlock;
  }
}
