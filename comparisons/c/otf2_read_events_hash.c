// Copyright Hewlett Packard Enterprise Development LP.

#include <otf2/otf2.h>
#include <stdlib.h>
#include <stdio.h>
#include <inttypes.h>
#include <string.h>
#include <time.h>
#include <stdbool.h>

// Compile with gcc -o otf2_read_events_hash otf2_read_events_hash.c -I/opt/otf2/include -L/opt/otf2/lib -lotf2 -fopenmp
// Or for mac use: clang -o otf2_read_events_hash otf2_read_events_hash.c -I/opt/otf2/include -L/opt/otf2/lib -lotf2 -Xpreprocessor -fopenmp -lomp -I/opt/homebrew/opt/libomp/include -L/opt/homebrew/opt/libomp/lib
// --- Hash table implementations for O(1) lookup ---

// Hash table node for chaining
typedef struct StringHashNode {
    OTF2_StringRef ref;
    char* name;
    struct StringHashNode* next;
} StringHashNode;

typedef struct {
    size_t capacity;
    size_t size;
    StringHashNode** buckets;
} StringTable;

typedef struct LocationHashNode {
    OTF2_LocationRef ref;
    char* name;
    struct LocationHashNode* next;
} LocationHashNode;

typedef struct {
    size_t capacity;
    size_t size;
    LocationHashNode** buckets;
} LocationNameTable;

typedef struct RegionHashNode {
    OTF2_RegionRef ref;
    char* name;
    struct RegionHashNode* next;
} RegionHashNode;

typedef struct {
    size_t capacity;
    size_t size;
    RegionHashNode** buckets;
} RegionNameTable;

// Simple hash function
static size_t hash_uint64(uint64_t key, size_t capacity) {
    // Simple multiplicative hash using a good constant
    return ((key * 2654435761UL) >> 16) % capacity;
}

static void StringTable_init(StringTable* t) {
    t->capacity = 1024;  // Larger initial capacity for better performance
    t->size = 0;
    t->buckets = calloc(t->capacity, sizeof(StringHashNode*));
    if (!t->buckets) {
        fprintf(stderr, "Failed to allocate memory for string table\n");
        exit(EXIT_FAILURE);
    }
}

static void StringTable_free(StringTable* t) {
    for (size_t i = 0; i < t->capacity; i++) {
        StringHashNode* node = t->buckets[i];
        while (node) {
            StringHashNode* temp = node;
            node = node->next;
            free(temp->name);
            free(temp);
        }
    }
    free(t->buckets);
}

static void StringTable_add(StringTable* t, OTF2_StringRef ref, const char* name) {
    size_t bucket = hash_uint64(ref, t->capacity);
    
    StringHashNode* new_node = malloc(sizeof(StringHashNode));
    if (!new_node) {
        fprintf(stderr, "Failed to allocate memory for string hash node\n");
        exit(EXIT_FAILURE);
    }
    
    new_node->ref = ref;
    new_node->name = strdup(name);
    new_node->next = t->buckets[bucket];
    t->buckets[bucket] = new_node;
    t->size++;
}

static const char* StringTable_lookup(StringTable* t, OTF2_StringRef ref) {
    size_t bucket = hash_uint64(ref, t->capacity);
    StringHashNode* node = t->buckets[bucket];
    
    while (node) {
        if (node->ref == ref) {
            return node->name;
        }
        node = node->next;
    }
    return NULL;
}

static void LocationNameTable_init(LocationNameTable* t, uint64_t number_of_locations) {
    // Use next power of 2 that's at least as large as number_of_locations, minimum 256
    t->capacity = 256;
    while (t->capacity < number_of_locations) {
        t->capacity *= 2;
    }
    t->size = 0;
    t->buckets = calloc(t->capacity, sizeof(LocationHashNode*));
    if (!t->buckets) {
        fprintf(stderr, "Failed to allocate memory for location name table\n");
        exit(EXIT_FAILURE);
    }
}

static void LocationNameTable_free(LocationNameTable* t) {
    for (size_t i = 0; i < t->capacity; i++) {
        LocationHashNode* node = t->buckets[i];
        while (node) {
            LocationHashNode* temp = node;
            node = node->next;
            free(temp->name);
            free(temp);
        }
    }
    free(t->buckets);
}

static void LocationNameTable_add(LocationNameTable* t, OTF2_LocationRef ref, const char* name) {
    size_t bucket = hash_uint64(ref, t->capacity);
    
    LocationHashNode* new_node = malloc(sizeof(LocationHashNode));
    if (!new_node) {
        fprintf(stderr, "Failed to allocate memory for location hash node\n");
        exit(EXIT_FAILURE);
    }
    
    new_node->ref = ref;
    new_node->name = strdup(name);
    new_node->next = t->buckets[bucket];
    t->buckets[bucket] = new_node;
    t->size++;
}

static const char* LocationNameTable_lookup(LocationNameTable* t, OTF2_LocationRef ref) {
    size_t bucket = hash_uint64(ref, t->capacity);
    LocationHashNode* node = t->buckets[bucket];
    
    while (node) {
        if (node->ref == ref) {
            return node->name;
        }
        node = node->next;
    }
    return NULL;
}

static void RegionNameTable_init(RegionNameTable* t) {
    t->capacity = 512;  // Good initial size for regions
    t->size = 0;
    t->buckets = calloc(t->capacity, sizeof(RegionHashNode*));
    if (!t->buckets) {
        fprintf(stderr, "Failed to allocate memory for region name table\n");
        exit(EXIT_FAILURE);
    }
}

static void RegionNameTable_free(RegionNameTable* t) {
    for (size_t i = 0; i < t->capacity; i++) {
        RegionHashNode* node = t->buckets[i];
        while (node) {
            RegionHashNode* temp = node;
            node = node->next;
            free(temp->name);
            free(temp);
        }
    }
    free(t->buckets);
}

static void RegionNameTable_add(RegionNameTable* t, OTF2_RegionRef ref, const char* name) {
    size_t bucket = hash_uint64(ref, t->capacity);
    
    RegionHashNode* new_node = malloc(sizeof(RegionHashNode));
    if (!new_node) {
        fprintf(stderr, "Failed to allocate memory for region hash node\n");
        exit(EXIT_FAILURE);
    }
    
    new_node->ref = ref;
    new_node->name = strdup(name);
    new_node->next = t->buckets[bucket];
    t->buckets[bucket] = new_node;
    t->size++;
}

static const char* RegionNameTable_lookup(RegionNameTable* t, OTF2_RegionRef ref) {
    size_t bucket = hash_uint64(ref, t->capacity);
    RegionHashNode* node = t->buckets[bucket];
    
    while (node) {
        if (node->ref == ref) {
            return node->name;
        }
        node = node->next;
    }
    return NULL;
}

// Helper function to collect all location references for iteration
static void LocationNameTable_collect_refs(LocationNameTable* t, OTF2_LocationRef** refs, size_t* count) {
    *refs = malloc(t->size * sizeof(OTF2_LocationRef));
    if (!*refs) {
        fprintf(stderr, "Failed to allocate memory for location refs\n");
        exit(EXIT_FAILURE);
    }
    
    *count = 0;
    for (size_t i = 0; i < t->capacity; i++) {
        LocationHashNode* node = t->buckets[i];
        while (node) {
            (*refs)[(*count)++] = node->ref;
            node = node->next;
        }
    }
}

// --- Definition callbacks ---
// Combined context for all definition callbacks
typedef struct {
    StringTable* string_table;
    LocationNameTable* location_table;
    RegionNameTable* region_table;
} AllDefContext;


static void PrintUniqueLocationAndRegionStats(AllDefContext* all_def_ctx, bool verbose) {

    printf("Total unique locations: %zu\n", all_def_ctx->location_table->size);
    if (verbose) {
        printf("Unique locations:\n");
        for (size_t i = 0; i < all_def_ctx->location_table->capacity; i++) {
            LocationHashNode* node = all_def_ctx->location_table->buckets[i];
            while (node) {
                printf("  %s\n", node->name);
                node = node->next;
            }
        }
    }

    printf("Total unique regions: %zu\n", all_def_ctx->region_table->size);
    if (verbose) {
        printf("Unique regions:\n");
        for (size_t i = 0; i < all_def_ctx->region_table->capacity; i++) {
            RegionHashNode* node = all_def_ctx->region_table->buckets[i];
            while (node) {
                printf("  %s\n", node->name);
                node = node->next;
            }
        }
    }
}


// String definition callback
static OTF2_CallbackCode
GlobDefString_Register(void* userData,
                       OTF2_StringRef self,
                       const char* string)
{
    AllDefContext* all_ctx = (AllDefContext*)userData;
    StringTable_add(all_ctx->string_table, self, string ? string : "UnknownString");
    return OTF2_CALLBACK_SUCCESS;
}

static OTF2_CallbackCode
GlobDefLocation_Register(void* userData,
                         OTF2_LocationRef location,
                         OTF2_StringRef name,
                         OTF2_LocationType locationType,
                         uint64_t numberOfEvents,
                         OTF2_LocationGroupRef locationGroup)
{
    AllDefContext* all_ctx = (AllDefContext*)userData;
    // Lookup name in string table
    const char* locname = StringTable_lookup(all_ctx->string_table, name);
    if (!locname) locname = "UnknownLocation";
    LocationNameTable_add(all_ctx->location_table, location, locname);
    return OTF2_CALLBACK_SUCCESS;
}

static OTF2_CallbackCode
GlobDefRegion_Register(void* userData,
                       OTF2_RegionRef region,
                       OTF2_StringRef name,
                       OTF2_StringRef canonicalName,
                       OTF2_StringRef description,
                       OTF2_RegionRole regionRole,
                       OTF2_Paradigm paradigm,
                       OTF2_RegionFlag regionFlags,
                       OTF2_StringRef sourceFile,
                       uint32_t beginLineNumber,
                       uint32_t endLineNumber)
{
    AllDefContext* all_ctx = (AllDefContext*)userData;
    const char* regionname = StringTable_lookup(all_ctx->string_table, name);
    if (!regionname) regionname = "UnknownRegion";
    RegionNameTable_add(all_ctx->region_table, region, regionname);
    return OTF2_CALLBACK_SUCCESS;
}

typedef struct {
    char* location_name;
    char* event_name;
    char* region_name;
} EventInfo;

typedef struct {
    size_t   capacity;
    size_t   size;
    uint64_t enter_count;
    uint64_t leave_count;
    EventInfo* events;
} AllEventsData;

// Helper: add event to events array
static void add_event(AllEventsData* data, const char* location, const char* event, const char* region) {
    if (data->size == data->capacity) {
        size_t new_cap = data->capacity * 2 + 1;
        EventInfo* new_events = realloc(data->events, new_cap * sizeof(EventInfo));
        if (!new_events) {
            fprintf(stderr, "Failed to allocate memory for events\n");
            exit(EXIT_FAILURE);
        }
        data->events = new_events;
        data->capacity = new_cap;
    }
    data->events[data->size].location_name = strdup(location);
    data->events[data->size].event_name = strdup(event);
    data->events[data->size].region_name = region ? strdup(region) : strdup("");
    data->size++;
}

// Helper: free allocated memory in AllEventsData
static void free_events_data(AllEventsData* data) {
    for (size_t i = 0; i < data->size; i++) {
        free(data->events[i].location_name);
        free(data->events[i].event_name);
        free(data->events[i].region_name);
    }
    free(data->events);
}


// --- Event callback context ---
typedef struct {
    AllEventsData* event_data;
    LocationNameTable* location_table;
    RegionNameTable* region_table;
} EventCallbackContext;

static OTF2_CallbackCode
Enter_store_and_count(OTF2_LocationRef location,
                      OTF2_TimeStamp time,
                      void* userData,
                      OTF2_AttributeList* attributes,
                      OTF2_RegionRef region)
{
    // Get pointers to the context and event data
    EventCallbackContext* ctx = (EventCallbackContext*)userData;
    AllEventsData* all_event_data = ctx->event_data;
    // Increment enter count
    all_event_data->enter_count++;
    // Get location and region names
    const char* locname = LocationNameTable_lookup(ctx->location_table, location);
    if (!locname) locname = "UnknownLocation";
    const char* regionname = RegionNameTable_lookup(ctx->region_table, region);
    if (!regionname) regionname = "UnknownRegion";
    // Add event to all_event_data
    add_event(all_event_data, locname, "Enter", regionname);
    return OTF2_CALLBACK_SUCCESS;
}

static OTF2_CallbackCode
Leave_store_and_count(OTF2_LocationRef location,
                      OTF2_TimeStamp time,
                      void* userData,
                      OTF2_AttributeList* attributes,
                      OTF2_RegionRef region)
{
    // Get pointers to the context and event data
    EventCallbackContext* ctx = (EventCallbackContext*)userData;
    AllEventsData* all_event_data = ctx->event_data;
    // Increment leave count
    all_event_data->leave_count++;
    // Get location and region names
    const char* locname = LocationNameTable_lookup(ctx->location_table, location);
    if (!locname) locname = "UnknownLocation";
    const char* regionname = RegionNameTable_lookup(ctx->region_table, region);
    if (!regionname) regionname = "UnknownRegion";
    // Add event to all_event_data
    add_event(all_event_data, locname, "Leave", regionname);
    return OTF2_CALLBACK_SUCCESS;
}


int main(int argc, char** argv) {
    clock_t start_time = clock();

    // OTF2_Reader* reader = OTF2_Reader_Open("/workspace/scorep-traces/frontier-hpl-run-using-2-ranks-with-craypm/traces.otf2" );
    OTF2_Reader* reader = OTF2_Reader_Open("/workspace/scorep-traces/simple-mi300-example-run/traces.otf2" );
    if (!reader) {
        fprintf(stderr, "Failed to open OTF2 archive\n");
        return EXIT_FAILURE;
    }

    printf("Time taken to open OTF2 archive: %.2f seconds\n",
           (double)(clock() - start_time) / CLOCKS_PER_SEC);
    clock_t def_read_start_time = clock();

    OTF2_Reader_SetSerialCollectiveCallbacks(reader);
    uint64_t number_of_locations;
    OTF2_Reader_GetNumberOfLocations(reader, &number_of_locations);
    printf("Number of locations: %" PRIu64 "\n", number_of_locations);

    // --- Lookup tables ---
    StringTable string_table; StringTable_init(&string_table);
    LocationNameTable location_table; LocationNameTable_init(&location_table, number_of_locations);
    RegionNameTable region_table; RegionNameTable_init(&region_table);

    // --- Definition callbacks ---
    OTF2_GlobalDefReader* global_def_reader = OTF2_Reader_GetGlobalDefReader(reader);
    OTF2_GlobalDefReaderCallbacks* global_def_callbacks = OTF2_GlobalDefReaderCallbacks_New();

    // String callback - register first since locations and regions depend on strings
    OTF2_GlobalDefReaderCallbacks_SetStringCallback(global_def_callbacks,
                                                    &GlobDefString_Register);

    // Location callback
    OTF2_GlobalDefReaderCallbacks_SetLocationCallback(global_def_callbacks,
                                                      &GlobDefLocation_Register);

    // Region callback
    OTF2_GlobalDefReaderCallbacks_SetRegionCallback(global_def_callbacks,
                                                    &GlobDefRegion_Register);

    // Register callbacks with a single context structure containing all needed data
    AllDefContext all_ctx = {
        &string_table,
        &location_table,
        &region_table
    };

    OTF2_Reader_RegisterGlobalDefCallbacks(reader,
                                           global_def_reader,
                                           global_def_callbacks,
                                           &all_ctx);

    OTF2_GlobalDefReaderCallbacks_Delete(global_def_callbacks);

    uint64_t definitions_read = 0;
    OTF2_Reader_ReadAllGlobalDefinitions(reader,
                                         global_def_reader,
                                         &definitions_read);
    printf("Read %" PRIu64 " global definitions\n", definitions_read);
    printf("Time taken to read global definitions: %.2f seconds\n",
           (double)(clock() - def_read_start_time) / CLOCKS_PER_SEC);

    clock_t local_def_start_time = clock();

    // Collect all location references for iteration
    OTF2_LocationRef* location_refs;
    size_t location_count;
    LocationNameTable_collect_refs(&location_table, &location_refs, &location_count);

    for (size_t i = 0; i < location_count; i++) {
        OTF2_Reader_SelectLocation(reader, location_refs[i]);
    }

    bool successful_open_def_files =
        OTF2_Reader_OpenDefFiles(reader) == OTF2_SUCCESS;


    OTF2_Reader_OpenEvtFiles(reader);
    for (size_t i = 0; i < location_count; i++) {
        if (successful_open_def_files) {
            OTF2_DefReader* def_reader = OTF2_Reader_GetDefReader(reader,
                                                                  location_refs[i]);
            if (def_reader) {
                uint64_t def_reads = 0;
                OTF2_Reader_ReadAllLocalDefinitions(reader,
                                                    def_reader,
                                                    &def_reads);

                OTF2_Reader_CloseDefReader(reader,
                                           def_reader);
            }
        }
        // Mark file to be read by Global Reader later
        OTF2_EvtReader* evt_reader =
                OTF2_Reader_GetEvtReader(reader, location_refs[i]);
    }
    if (successful_open_def_files) {
        OTF2_Reader_CloseDefFiles(reader);
    }

    printf("Time taken to read local definition files and mark all local event files for reading: %.2f seconds\n",
           (double)(clock() - local_def_start_time) / CLOCKS_PER_SEC);

    clock_t event_read_start_time = clock();

    OTF2_GlobalEvtReader* global_evt_reader = OTF2_Reader_GetGlobalEvtReader(reader);

    // Initialize event_data
    AllEventsData event_data = {0};
    event_data.capacity = 1024;
    event_data.size = 0;
    event_data.enter_count = 0;
    event_data.leave_count = 0;
    event_data.events = calloc(event_data.capacity, sizeof(EventInfo));
    if (!event_data.events) {
        fprintf(stderr, "Failed to allocate memory for event data\n");
        return EXIT_FAILURE;
    }

    // Event callback context
    EventCallbackContext evt_ctx = {&event_data, &location_table, &region_table};

    OTF2_GlobalEvtReaderCallbacks* event_callbacks = OTF2_GlobalEvtReaderCallbacks_New();

    OTF2_GlobalEvtReaderCallbacks_SetEnterCallback(event_callbacks, &Enter_store_and_count);
    OTF2_GlobalEvtReaderCallbacks_SetLeaveCallback(event_callbacks, &Leave_store_and_count);

    OTF2_Reader_RegisterGlobalEvtCallbacks(reader,
                                           global_evt_reader,
                                           event_callbacks,
                                           &evt_ctx);

    OTF2_GlobalEvtReaderCallbacks_Delete(event_callbacks);

    uint64_t total_events_read = 0;
    OTF2_Reader_ReadAllGlobalEvents(reader,
                                    global_evt_reader,
                                    &total_events_read);

    OTF2_Reader_CloseGlobalEvtReader(reader,
                                     global_evt_reader);

    OTF2_Reader_CloseEvtFiles(reader);
    OTF2_Reader_Close(reader);

    printf("Time taken to read events: %.2f seconds\n",
           (double)(clock() - event_read_start_time) / CLOCKS_PER_SEC);

    printf("Total time: %.2f seconds\n", (double)(clock() - start_time) / CLOCKS_PER_SEC);

    // Print event summary (matching Python output)
    printf("\nEvent Summary:\n");
    printf("Total number of events: %" PRIu64 "\n", total_events_read);
    printf("Event types and their counts:\n");
    printf("  Enter: %" PRIu64 " events\n", event_data.enter_count);
    printf("  Leave: %" PRIu64 " events\n", event_data.leave_count);
    PrintUniqueLocationAndRegionStats(&all_ctx, false);

    // Free event_data
    free_events_data(&event_data);

    // Free lookup tables
    StringTable_free(&string_table);
    LocationNameTable_free(&location_table);
    RegionNameTable_free(&region_table);

    return EXIT_SUCCESS;
}