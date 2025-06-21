#ifndef CSQLITE_H
#define CSQLITE_H

#include <sqlite3.h>
#include <stdint.h>
#include <stdbool.h>

// Error codes
typedef enum {
    CSQLITE_OK = 0,
    CSQLITE_ERROR = 1,
    CSQLITE_NOT_FOUND = 2,
    CSQLITE_CONSTRAINT = 3,
} CSQLiteResult;

// Bundle metadata structure
typedef struct {
    const char* id;
    const char* source;
    const char* destination;
    uint64_t creation_time;
    uint64_t size;
    int constraints;
} CSQLiteBundleMetadata;

// Database handle
typedef struct CSQLiteDB CSQLiteDB;

// Database operations
CSQLiteDB* csqlite_open(const char* path, CSQLiteResult* result);
void csqlite_close(CSQLiteDB* db);

// Bundle operations
CSQLiteResult csqlite_store_bundle(CSQLiteDB* db, const char* bundle_id, const uint8_t* bundle_data, size_t bundle_size, const CSQLiteBundleMetadata* metadata);
CSQLiteResult csqlite_get_bundle(CSQLiteDB* db, const char* bundle_id, uint8_t** bundle_data, size_t* bundle_size);
CSQLiteResult csqlite_get_metadata(CSQLiteDB* db, const char* bundle_id, CSQLiteBundleMetadata* metadata);
CSQLiteResult csqlite_update_metadata(CSQLiteDB* db, const CSQLiteBundleMetadata* metadata);
CSQLiteResult csqlite_remove_bundle(CSQLiteDB* db, const char* bundle_id);
CSQLiteResult csqlite_has_bundle(CSQLiteDB* db, const char* bundle_id, bool* exists);

// Query operations
uint64_t csqlite_count_bundles(CSQLiteDB* db);
CSQLiteResult csqlite_get_all_ids(CSQLiteDB* db, char*** ids, size_t* count);
CSQLiteResult csqlite_get_all_metadata(CSQLiteDB* db, CSQLiteBundleMetadata** metadata, size_t* count);

// Memory management helpers
void csqlite_free_data(void* data);
void csqlite_free_ids(char** ids, size_t count);
void csqlite_free_metadata_array(CSQLiteBundleMetadata* metadata, size_t count);
char* csqlite_strdup(const char* str);

#endif // CSQLITE_H