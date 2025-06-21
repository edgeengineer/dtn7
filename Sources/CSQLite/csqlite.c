#include "include/csqlite.h"
#include <stdlib.h>
#include <string.h>

struct CSQLiteDB {
    sqlite3* db;
};

static const char* CREATE_TABLES_SQL = 
    "CREATE TABLE IF NOT EXISTS bundles ("
    "  id TEXT PRIMARY KEY,"
    "  data BLOB NOT NULL"
    ");"
    "CREATE TABLE IF NOT EXISTS bundle_metadata ("
    "  id TEXT PRIMARY KEY,"
    "  source TEXT NOT NULL,"
    "  destination TEXT NOT NULL,"
    "  creation_time INTEGER NOT NULL,"
    "  size INTEGER NOT NULL,"
    "  constraints INTEGER NOT NULL,"
    "  FOREIGN KEY(id) REFERENCES bundles(id) ON DELETE CASCADE"
    ");";

CSQLiteDB* csqlite_open(const char* path, CSQLiteResult* result) {
    CSQLiteDB* db = malloc(sizeof(CSQLiteDB));
    if (!db) {
        if (result) *result = CSQLITE_ERROR;
        return NULL;
    }
    
    int rc = sqlite3_open(path, &db->db);
    if (rc != SQLITE_OK) {
        free(db);
        if (result) *result = CSQLITE_ERROR;
        return NULL;
    }
    
    // Enable foreign keys
    sqlite3_exec(db->db, "PRAGMA foreign_keys = ON;", NULL, NULL, NULL);
    
    // Create tables
    char* err_msg = NULL;
    rc = sqlite3_exec(db->db, CREATE_TABLES_SQL, NULL, NULL, &err_msg);
    if (rc != SQLITE_OK) {
        sqlite3_free(err_msg);
        sqlite3_close(db->db);
        free(db);
        if (result) *result = CSQLITE_ERROR;
        return NULL;
    }
    
    if (result) *result = CSQLITE_OK;
    return db;
}

void csqlite_close(CSQLiteDB* db) {
    if (db) {
        sqlite3_close(db->db);
        free(db);
    }
}

CSQLiteResult csqlite_store_bundle(CSQLiteDB* db, const char* bundle_id, const uint8_t* bundle_data, size_t bundle_size, const CSQLiteBundleMetadata* metadata) {
    if (!db || !bundle_id || !bundle_data || !metadata) {
        return CSQLITE_ERROR;
    }
    
    sqlite3_stmt* stmt = NULL;
    int rc;
    
    // Begin transaction
    rc = sqlite3_exec(db->db, "BEGIN TRANSACTION;", NULL, NULL, NULL);
    if (rc != SQLITE_OK) {
        return CSQLITE_ERROR;
    }
    
    // Insert bundle data
    const char* insert_bundle_sql = "INSERT INTO bundles (id, data) VALUES (?, ?);";
    rc = sqlite3_prepare_v2(db->db, insert_bundle_sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        sqlite3_exec(db->db, "ROLLBACK;", NULL, NULL, NULL);
        return CSQLITE_ERROR;
    }
    
    sqlite3_bind_text(stmt, 1, bundle_id, -1, SQLITE_STATIC);
    sqlite3_bind_blob(stmt, 2, bundle_data, (int)bundle_size, SQLITE_STATIC);
    
    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    if (rc != SQLITE_DONE) {
        sqlite3_exec(db->db, "ROLLBACK;", NULL, NULL, NULL);
        return (rc == SQLITE_CONSTRAINT) ? CSQLITE_CONSTRAINT : CSQLITE_ERROR;
    }
    
    // Insert metadata
    const char* insert_metadata_sql = "INSERT INTO bundle_metadata (id, source, destination, creation_time, size, constraints) VALUES (?, ?, ?, ?, ?, ?);";
    rc = sqlite3_prepare_v2(db->db, insert_metadata_sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        sqlite3_exec(db->db, "ROLLBACK;", NULL, NULL, NULL);
        return CSQLITE_ERROR;
    }
    
    sqlite3_bind_text(stmt, 1, metadata->id, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 2, metadata->source, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 3, metadata->destination, -1, SQLITE_STATIC);
    sqlite3_bind_int64(stmt, 4, metadata->creation_time);
    sqlite3_bind_int64(stmt, 5, metadata->size);
    sqlite3_bind_int(stmt, 6, metadata->constraints);
    
    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    if (rc != SQLITE_DONE) {
        sqlite3_exec(db->db, "ROLLBACK;", NULL, NULL, NULL);
        return CSQLITE_ERROR;
    }
    
    // Commit transaction
    rc = sqlite3_exec(db->db, "COMMIT;", NULL, NULL, NULL);
    return (rc == SQLITE_OK) ? CSQLITE_OK : CSQLITE_ERROR;
}

CSQLiteResult csqlite_get_bundle(CSQLiteDB* db, const char* bundle_id, uint8_t** bundle_data, size_t* bundle_size) {
    if (!db || !bundle_id || !bundle_data || !bundle_size) {
        return CSQLITE_ERROR;
    }
    
    const char* query = "SELECT data FROM bundles WHERE id = ?;";
    sqlite3_stmt* stmt = NULL;
    
    int rc = sqlite3_prepare_v2(db->db, query, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        return CSQLITE_ERROR;
    }
    
    sqlite3_bind_text(stmt, 1, bundle_id, -1, SQLITE_STATIC);
    rc = sqlite3_step(stmt);
    
    if (rc == SQLITE_ROW) {
        const void* blob = sqlite3_column_blob(stmt, 0);
        int blob_size = sqlite3_column_bytes(stmt, 0);
        
        *bundle_data = malloc(blob_size);
        if (*bundle_data) {
            memcpy(*bundle_data, blob, blob_size);
            *bundle_size = blob_size;
            sqlite3_finalize(stmt);
            return CSQLITE_OK;
        }
    }
    
    sqlite3_finalize(stmt);
    return (rc == SQLITE_DONE) ? CSQLITE_NOT_FOUND : CSQLITE_ERROR;
}

CSQLiteResult csqlite_get_metadata(CSQLiteDB* db, const char* bundle_id, CSQLiteBundleMetadata* metadata) {
    if (!db || !bundle_id || !metadata) {
        return CSQLITE_ERROR;
    }
    
    const char* query = "SELECT id, source, destination, creation_time, size, constraints FROM bundle_metadata WHERE id = ?;";
    sqlite3_stmt* stmt = NULL;
    
    int rc = sqlite3_prepare_v2(db->db, query, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        return CSQLITE_ERROR;
    }
    
    sqlite3_bind_text(stmt, 1, bundle_id, -1, SQLITE_STATIC);
    rc = sqlite3_step(stmt);
    
    if (rc == SQLITE_ROW) {
        metadata->id = csqlite_strdup((const char*)sqlite3_column_text(stmt, 0));
        metadata->source = csqlite_strdup((const char*)sqlite3_column_text(stmt, 1));
        metadata->destination = csqlite_strdup((const char*)sqlite3_column_text(stmt, 2));
        metadata->creation_time = sqlite3_column_int64(stmt, 3);
        metadata->size = sqlite3_column_int64(stmt, 4);
        metadata->constraints = sqlite3_column_int(stmt, 5);
        
        sqlite3_finalize(stmt);
        return CSQLITE_OK;
    }
    
    sqlite3_finalize(stmt);
    return (rc == SQLITE_DONE) ? CSQLITE_NOT_FOUND : CSQLITE_ERROR;
}

CSQLiteResult csqlite_update_metadata(CSQLiteDB* db, const CSQLiteBundleMetadata* metadata) {
    if (!db || !metadata || !metadata->id) {
        return CSQLITE_ERROR;
    }
    
    const char* update_sql = "UPDATE bundle_metadata SET source = ?, destination = ?, creation_time = ?, size = ?, constraints = ? WHERE id = ?;";
    sqlite3_stmt* stmt = NULL;
    
    int rc = sqlite3_prepare_v2(db->db, update_sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        return CSQLITE_ERROR;
    }
    
    sqlite3_bind_text(stmt, 1, metadata->source, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 2, metadata->destination, -1, SQLITE_STATIC);
    sqlite3_bind_int64(stmt, 3, metadata->creation_time);
    sqlite3_bind_int64(stmt, 4, metadata->size);
    sqlite3_bind_int(stmt, 5, metadata->constraints);
    sqlite3_bind_text(stmt, 6, metadata->id, -1, SQLITE_STATIC);
    
    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    if (rc != SQLITE_DONE) {
        return CSQLITE_ERROR;
    }
    
    return (sqlite3_changes(db->db) > 0) ? CSQLITE_OK : CSQLITE_NOT_FOUND;
}

CSQLiteResult csqlite_remove_bundle(CSQLiteDB* db, const char* bundle_id) {
    if (!db || !bundle_id) {
        return CSQLITE_ERROR;
    }
    
    const char* delete_sql = "DELETE FROM bundles WHERE id = ?;";
    sqlite3_stmt* stmt = NULL;
    
    int rc = sqlite3_prepare_v2(db->db, delete_sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        return CSQLITE_ERROR;
    }
    
    sqlite3_bind_text(stmt, 1, bundle_id, -1, SQLITE_STATIC);
    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    if (rc != SQLITE_DONE) {
        return CSQLITE_ERROR;
    }
    
    return (sqlite3_changes(db->db) > 0) ? CSQLITE_OK : CSQLITE_NOT_FOUND;
}

CSQLiteResult csqlite_has_bundle(CSQLiteDB* db, const char* bundle_id, bool* exists) {
    if (!db || !bundle_id || !exists) {
        return CSQLITE_ERROR;
    }
    
    const char* query = "SELECT 1 FROM bundles WHERE id = ? LIMIT 1;";
    sqlite3_stmt* stmt = NULL;
    
    int rc = sqlite3_prepare_v2(db->db, query, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        return CSQLITE_ERROR;
    }
    
    sqlite3_bind_text(stmt, 1, bundle_id, -1, SQLITE_STATIC);
    rc = sqlite3_step(stmt);
    
    *exists = (rc == SQLITE_ROW);
    sqlite3_finalize(stmt);
    
    return CSQLITE_OK;
}

uint64_t csqlite_count_bundles(CSQLiteDB* db) {
    if (!db) {
        return 0;
    }
    
    const char* query = "SELECT COUNT(*) FROM bundles;";
    sqlite3_stmt* stmt = NULL;
    
    int rc = sqlite3_prepare_v2(db->db, query, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        return 0;
    }
    
    rc = sqlite3_step(stmt);
    uint64_t count = 0;
    
    if (rc == SQLITE_ROW) {
        count = sqlite3_column_int64(stmt, 0);
    }
    
    sqlite3_finalize(stmt);
    return count;
}

CSQLiteResult csqlite_get_all_ids(CSQLiteDB* db, char*** ids, size_t* count) {
    if (!db || !ids || !count) {
        return CSQLITE_ERROR;
    }
    
    const char* query = "SELECT id FROM bundles;";
    sqlite3_stmt* stmt = NULL;
    
    int rc = sqlite3_prepare_v2(db->db, query, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        return CSQLITE_ERROR;
    }
    
    // Count results first
    size_t n = 0;
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        n++;
    }
    
    if (n == 0) {
        *ids = NULL;
        *count = 0;
        sqlite3_finalize(stmt);
        return CSQLITE_OK;
    }
    
    // Allocate array
    *ids = malloc(n * sizeof(char*));
    if (!*ids) {
        sqlite3_finalize(stmt);
        return CSQLITE_ERROR;
    }
    
    // Reset and fetch
    sqlite3_reset(stmt);
    size_t i = 0;
    while (sqlite3_step(stmt) == SQLITE_ROW && i < n) {
        const char* id = (const char*)sqlite3_column_text(stmt, 0);
        (*ids)[i] = csqlite_strdup(id);
        i++;
    }
    
    *count = i;
    sqlite3_finalize(stmt);
    return CSQLITE_OK;
}

CSQLiteResult csqlite_get_all_metadata(CSQLiteDB* db, CSQLiteBundleMetadata** metadata, size_t* count) {
    if (!db || !metadata || !count) {
        return CSQLITE_ERROR;
    }
    
    const char* query = "SELECT id, source, destination, creation_time, size, constraints FROM bundle_metadata;";
    sqlite3_stmt* stmt = NULL;
    
    int rc = sqlite3_prepare_v2(db->db, query, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        return CSQLITE_ERROR;
    }
    
    // Count results first
    size_t n = 0;
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        n++;
    }
    
    if (n == 0) {
        *metadata = NULL;
        *count = 0;
        sqlite3_finalize(stmt);
        return CSQLITE_OK;
    }
    
    // Allocate array
    *metadata = malloc(n * sizeof(CSQLiteBundleMetadata));
    if (!*metadata) {
        sqlite3_finalize(stmt);
        return CSQLITE_ERROR;
    }
    
    // Reset and fetch
    sqlite3_reset(stmt);
    size_t i = 0;
    while (sqlite3_step(stmt) == SQLITE_ROW && i < n) {
        (*metadata)[i].id = csqlite_strdup((const char*)sqlite3_column_text(stmt, 0));
        (*metadata)[i].source = csqlite_strdup((const char*)sqlite3_column_text(stmt, 1));
        (*metadata)[i].destination = csqlite_strdup((const char*)sqlite3_column_text(stmt, 2));
        (*metadata)[i].creation_time = sqlite3_column_int64(stmt, 3);
        (*metadata)[i].size = sqlite3_column_int64(stmt, 4);
        (*metadata)[i].constraints = sqlite3_column_int(stmt, 5);
        i++;
    }
    
    *count = i;
    sqlite3_finalize(stmt);
    return CSQLITE_OK;
}

void csqlite_free_data(void* data) {
    free(data);
}

void csqlite_free_ids(char** ids, size_t count) {
    if (ids) {
        for (size_t i = 0; i < count; i++) {
            free(ids[i]);
        }
        free(ids);
    }
}

void csqlite_free_metadata_array(CSQLiteBundleMetadata* metadata, size_t count) {
    if (metadata) {
        for (size_t i = 0; i < count; i++) {
            free((void*)metadata[i].id);
            free((void*)metadata[i].source);
            free((void*)metadata[i].destination);
        }
        free(metadata);
    }
}

char* csqlite_strdup(const char* str) {
    if (!str) return NULL;
    size_t len = strlen(str) + 1;
    char* copy = malloc(len);
    if (copy) {
        memcpy(copy, str, len);
    }
    return copy;
}