// Copyright Hewlett Packard Enterprise Development LP.

/*
 * Chapel Sync Variable-based Locking for OTF2
 * 
 * This module provides Chapel sync variable-based locking callbacks for OTF2
 * to enable safe parallel reading of OTF2 files in Chapel.
 * 
 * Usage example:
 *   var reader = OTF2_Reader_Open(...);
 *   otf2ChplSyncReaderSetLockingCallbacks(reader);
 *   // Now you can use the reader safely from multiple Chapel tasks
 */
module OTF2_ChplSync_Locks {
  use OTF2_Callbacks;
  use OTF2_Reader;
  use OTF2_Archive;
  use OTF2_GeneralDefinitions;
  use OTF2_ErrorCodes;
  use CTypes;
  use MoreCTypes;

  // Chapel sync variable-based lock object
  // Note: Using OTF2 naming convention to match C API expectations
  record OTF2_LockObject {
    var syncVar: sync bool;
    proc init (){}
  }

  // Create a new lock using Chapel sync variables
  // Note: userData parameter is required by C API but unused in this implementation
  export proc otf2ChplLockCreate(userData: c_ptr(void),
                          ref lock: OTF2_Lock): OTF2_CallbackCode {
    writeln("=========================");
    writeln("Created LOCK IN CHAPEL");

    // Create a new lock object - Chapel handles memory management
    ref lockObj = new OTF2_LockObject();

    // Initialize the sync variable as unlocked (full)
    lockObj.syncVar.writeEF(true);

    // Set the lock pointer to point to our lock object
    lock = c_ptrTo(lockObj): OTF2_Lock;

    writeln("=========================");
    return OTF2_CALLBACK_SUCCESS;
  }

  // Destroy a lock
  // Note: userData parameter is required by C API but unused in this implementation
  export proc otf2ChplLockDestroy(userData: c_ptr(void),
                           in lock: OTF2_Lock): OTF2_CallbackCode {
    writeln("=========================");
    writeln("Destroyed LOCK IN CHAPEL");

    if lock == nil {
      writeln("LOCK IS nil");
      return OTF2_CALLBACK_ERROR;
    }

    // Chapel will handle memory cleanup automatically
    // No explicit deallocation needed
    writeln("=========================");
    return OTF2_CALLBACK_SUCCESS;
  }

  // Acquire the lock (read from sync variable)
  // Note: userData parameter is required by C API but unused in this implementation
  export proc otf2ChplLockLock(userData: c_ptr(void),
                        in lock: OTF2_Lock): OTF2_CallbackCode {
    writeln("=========================");
    writeln("Acquiring LOCK IN CHAPEL");
    if lock == nil {
      writeln("LOCK IS nil");
      return OTF2_CALLBACK_ERROR;
    }

    // lock is already a pointer to OTF2_LockObject
    ref lockObj = (lock:c_ptr(OTF2_LockObject)).deref();
    ref lockSyncVar = lockObj.syncVar;


    writeln("About to call readFE() to acquire lock...");
    // Read from the sync variable to lock
    var val = lockSyncVar.readFE();
    writeln("Successfully acquired lock, read value: ", val);

    writeln("=========================");
    return OTF2_CALLBACK_SUCCESS;
  }

  // Release the lock (write to sync variable)
  // Note: userData parameter is required by C API but unused in this implementation
  export proc otf2ChplLockUnlock(userData: c_ptr(void),
                          in lock: OTF2_Lock): OTF2_CallbackCode {
    writeln("=========================");
    writeln("Releasing LOCK IN CHAPEL");
    if lock == nil {
      writeln("LOCK IS nil");
      return OTF2_CALLBACK_ERROR;
    }

    // lock is already a pointer to OTF2_LockObject
    ref lockObj = (lock:c_ptr(OTF2_LockObject)).deref();
    ref lockSyncVar = lockObj.syncVar;

    writeln("About to call writeEF(true) to release lock...");
    // write to sync var to unlock
    lockSyncVar.writeEF(true);
    writeln("Successfully released lock");

    writeln("=========================");
    return OTF2_CALLBACK_SUCCESS;
  }

  // Chapel locking callbacks structure
  ref otf2ChplLockingCallbacks = new OTF2_LockingCallbacks(
    otf2_release = nil,  // No release callback needed
    otf2_create = c_ptrTo(otf2ChplLockCreate):OTF2_Locking_Create,
    otf2_destroy = c_ptrTo(otf2ChplLockDestroy):OTF2_Locking_Destroy,
    otf2_lock = c_ptrTo(otf2ChplLockLock):OTF2_Locking_Lock,
    otf2_unlock = c_ptrTo(otf2ChplLockUnlock):OTF2_Locking_Unlock
  );

  // Set locking callbacks for an OTF2 archive
  proc otf2ChplSyncArchiveSetLockingCallbacks(archive: c_ptr(OTF2_Archive)): OTF2_ErrorCode {
    if archive == nil {
      return OTF2_ERROR_INVALID_ARGUMENT;
    }

    return OTF2_Archive_SetLockingCallbacks(archive,
                                           c_ptrTo(otf2ChplLockingCallbacks),
                                           nil);
  }

  // Set locking callbacks for an OTF2 reader
  proc otf2ChplSyncReaderSetLockingCallbacks(reader: c_ptr(OTF2_Reader)): OTF2_ErrorCode {
    if reader == nil {
      return OTF2_ERROR_INVALID_ARGUMENT;
    }

    return OTF2_Reader_SetLockingCallbacks(reader,
                                          c_ptrTo(otf2ChplLockingCallbacks),
                                          nil);
  }

}
