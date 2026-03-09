// Copyright Hewlett Packard Enterprise Development LP.

module OTF2 {
  public use CTypes;
  public use MoreCTypes;
  public use OTF2_Archive;
  public use OTF2_AttributeList;
  public use OTF2_Callbacks;
  public use OTF2_Definitions;
  public use OTF2_ErrorCodes;
  public use OTF2_Events;
  public use OTF2_EvtReaderCallbacks_Mod;
  public use OTF2_GeneralDefinitions;
  public use OTF2_GlobalDefReaderCallbacks_Mod;
  public use OTF2_GlobalEvtReaderCallbacks_Mod;
  public use OTF2_Reader;
  // Custom Implemented OTF2 Locking Callbacks
  public use OTF2_ChplSync_Locks;
}