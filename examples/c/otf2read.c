// Copyright Hewlett Packard Enterprise Development LP.

#include <otf2/otf2.h>
#include <stdlib.h>
#include <stdio.h>
#include <inttypes.h>
static OTF2_CallbackCode
Enter_print( OTF2_LocationRef    location,
             OTF2_TimeStamp      time,
             void*               userData,
             OTF2_AttributeList* attributes,
             OTF2_RegionRef      region )
{
    printf( "Entering region %u at location %" PRIu64 " at time %" PRIu64 ".\n",
            region, location, time );
    return OTF2_CALLBACK_SUCCESS;
}
static OTF2_CallbackCode
Leave_print( OTF2_LocationRef    location,
             OTF2_TimeStamp      time,
             void*               userData,
             OTF2_AttributeList* attributes,
             OTF2_RegionRef      region )
{
    printf( "Leaving region %u at location %" PRIu64 " at time %" PRIu64 ".\n",
            region, location, time );
    return OTF2_CALLBACK_SUCCESS;
}
struct vector
{
    size_t   capacity;
    size_t   size;
    OTF2_LocationRef members[];
};
static OTF2_CallbackCode
GlobDefLocation_Register( void*                 userData,
                          OTF2_LocationRef      location,
                          OTF2_StringRef        name,
                          OTF2_LocationType     locationType,
                          uint64_t              numberOfEvents,
                          OTF2_LocationGroupRef locationGroup )
{
    printf("Inside GlobDefLocation_Register Callback\n");
    struct vector* locations = userData;
    if ( locations->size == locations->capacity )
    {
        return OTF2_CALLBACK_INTERRUPT;
    }
    locations->members[ locations->size++ ] = location;
    printf("Registered location %" PRIu64 " with name %u and type %u.\n",
            location, name, locationType);
    return OTF2_CALLBACK_SUCCESS;
}
int
main( int    argc,
      char** argv )
{
    // OTF2_Reader* reader = OTF2_Reader_Open("/workspace/scorep-traces/frontier-hpl-run-using-2-ranks-with-craypm/traces.otf2" );
    OTF2_Reader* reader = OTF2_Reader_Open("/workspace/scorep-traces/simple-mi300-example-run/traces.otf2" );
    OTF2_Reader_SetSerialCollectiveCallbacks( reader );
    uint64_t number_of_locations;
    OTF2_Reader_GetNumberOfLocations( reader,
                                      &number_of_locations );
    printf( "Number of locations: %" PRIu64 "\n", number_of_locations );
    struct vector* locations = malloc( sizeof( *locations )
                                       + number_of_locations
                                       * sizeof( *locations->members ) );
    locations->capacity = number_of_locations;
    locations->size     = 0;
    OTF2_GlobalDefReader* global_def_reader = OTF2_Reader_GetGlobalDefReader( reader );
    OTF2_GlobalDefReaderCallbacks* global_def_callbacks = OTF2_GlobalDefReaderCallbacks_New();
    OTF2_GlobalDefReaderCallbacks_SetLocationCallback( global_def_callbacks,
                                                       &GlobDefLocation_Register );
    OTF2_Reader_RegisterGlobalDefCallbacks( reader,
                                            global_def_reader,
                                            global_def_callbacks,
                                            locations );
    OTF2_GlobalDefReaderCallbacks_Delete( global_def_callbacks );
    printf("About to read definitions and register locations\n");
    uint64_t definitions_read = 0;
    OTF2_Reader_ReadAllGlobalDefinitions( reader,
                                          global_def_reader,
                                          &definitions_read );
    printf( "Number of definitions read: %" PRIu64 "\n", definitions_read );

    for ( size_t i = 0; i < locations->size; i++ )
    {
        printf( "Selecting location %" PRIu64 "\n", locations->members[ i ] );
        OTF2_Reader_SelectLocation( reader, locations->members[ i ] );
    }
    bool successful_open_def_files =
        OTF2_Reader_OpenDefFiles( reader ) == OTF2_SUCCESS;
    OTF2_Reader_OpenEvtFiles( reader );
    for ( size_t i = 0; i < locations->size; i++ )
    {
        if ( successful_open_def_files )
        {
            OTF2_DefReader* def_reader =
                OTF2_Reader_GetDefReader( reader, locations->members[ i ] );
            if ( def_reader )
            {
                uint64_t def_reads = 0;
                OTF2_Reader_ReadAllLocalDefinitions( reader,
                                                     def_reader,
                                                     &def_reads );
                OTF2_Reader_CloseDefReader( reader, def_reader );
            }
        }
        OTF2_EvtReader* evt_reader =
            OTF2_Reader_GetEvtReader( reader, locations->members[ i ] );
    }
    if ( successful_open_def_files )
    {
        OTF2_Reader_CloseDefFiles( reader );
    }
    OTF2_GlobalEvtReader* global_evt_reader = OTF2_Reader_GetGlobalEvtReader( reader );
    OTF2_GlobalEvtReaderCallbacks* event_callbacks = OTF2_GlobalEvtReaderCallbacks_New();
    OTF2_GlobalEvtReaderCallbacks_SetEnterCallback( event_callbacks,
                                                    &Enter_print );
    OTF2_GlobalEvtReaderCallbacks_SetLeaveCallback( event_callbacks,
                                                    &Leave_print );
    OTF2_Reader_RegisterGlobalEvtCallbacks( reader,
                                            global_evt_reader,
                                            event_callbacks,
                                            NULL );
    OTF2_GlobalEvtReaderCallbacks_Delete( event_callbacks );
    uint64_t events_read = 0;
    OTF2_Reader_ReadAllGlobalEvents( reader,
                                     global_evt_reader,
                                     &events_read );
    OTF2_Reader_CloseGlobalEvtReader( reader, global_evt_reader );
    OTF2_Reader_CloseEvtFiles( reader );
    OTF2_Reader_Close( reader );
    free( locations );
    return EXIT_SUCCESS;
}