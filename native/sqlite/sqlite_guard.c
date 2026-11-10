/*
 * Bottogram's trusted SQLite security bridge.
 *
 * SQLite's public extension ABI supplies the exact core's API table. This avoids
 * loading a second SQLite library or relying on package-private Dart bindings.
 * The bridge creates no SQL functions, virtual tables, or filesystem access.
 */
#include "sqlite3ext.h"
#include <stddef.h>

#if defined(_WIN32)
#include <windows.h>
#define BOTTOGRAM_EXPORT __declspec(dllexport)
static PVOID volatile bottogram_api_pointer = NULL;
static const sqlite3_api_routines *bottogram_api(void) {
  return (const sqlite3_api_routines *)InterlockedCompareExchangePointer(
      &bottogram_api_pointer, NULL, NULL);
}
static int bottogram_accept_api(const sqlite3_api_routines *api) {
  const sqlite3_api_routines *previous =
      (const sqlite3_api_routines *)InterlockedCompareExchangePointer(
          &bottogram_api_pointer, (PVOID)api, NULL);
  return previous == NULL || previous == api;
}
#else
#include <stdatomic.h>
#define BOTTOGRAM_EXPORT __attribute__((visibility("default")))
static _Atomic(const sqlite3_api_routines *) bottogram_api_pointer = NULL;
static const sqlite3_api_routines *bottogram_api(void) {
  return atomic_load_explicit(&bottogram_api_pointer, memory_order_acquire);
}
static int bottogram_accept_api(const sqlite3_api_routines *api) {
  const sqlite3_api_routines *expected = NULL;
  return atomic_compare_exchange_strong_explicit(
             &bottogram_api_pointer, &expected, api, memory_order_release,
             memory_order_acquire) ||
         expected == api;
}
#endif

/* This entry point is registered only by trusted application code through
 * sqlite3_auto_extension / Sqlite3.ensureExtensionLoaded. User SQL is never
 * allowed to load extensions. */
BOTTOGRAM_EXPORT int sqlite3_bottogramsecurity_init(
    sqlite3 *database, char **error, const sqlite3_api_routines *api) {
  (void)database;
  (void)error;
  if (api == NULL || !bottogram_accept_api(api)) {
    return SQLITE_MISUSE;
  }
  return SQLITE_OK;
}

BOTTOGRAM_EXPORT int bottogram_sqlite_set_authorizer(
    sqlite3 *database,
    int (*callback)(void *, int, const char *, const char *, const char *,
                    const char *),
    void *context) {
  const sqlite3_api_routines *api = bottogram_api();
  if (api == NULL || api->set_authorizer == NULL || database == NULL) {
    return SQLITE_MISUSE;
  }
  return api->set_authorizer(database, callback, context);
}

BOTTOGRAM_EXPORT int bottogram_sqlite_progress_handler(
    sqlite3 *database, int instructions, int (*callback)(void *), void *context) {
  const sqlite3_api_routines *api = bottogram_api();
  if (api == NULL || api->progress_handler == NULL || database == NULL) {
    return SQLITE_MISUSE;
  }
  api->progress_handler(database, instructions, callback, context);
  return SQLITE_OK;
}

BOTTOGRAM_EXPORT int bottogram_sqlite_limit(sqlite3 *database, int category,
                                          int value) {
  const sqlite3_api_routines *api = bottogram_api();
  if (api == NULL || api->limit == NULL || database == NULL) {
    return -1;
  }
  return api->limit(database, category, value);
}

struct bottogram_probe {
  int authorizer_calls;
  int progress_calls;
};

static int bottogram_probe_deny(void *context, int operation, const char *one,
                               const char *two, const char *database,
                               const char *source) {
  struct bottogram_probe *probe = (struct bottogram_probe *)context;
  (void)operation;
  (void)one;
  (void)two;
  (void)database;
  (void)source;
  probe->authorizer_calls++;
  return SQLITE_DENY;
}

static int bottogram_probe_interrupt(void *context) {
  struct bottogram_probe *probe = (struct bottogram_probe *)context;
  probe->progress_calls++;
  return 1;
}

/* Call only on a new, idle connection, before its real guard is installed.
 * Merely checking exported symbols is insufficient: compiled-out interfaces
 * can have NULL API-table entries or inert implementations. This probe proves
 * that authorization denies preparation and progress interrupts execution.
 * Returns bit 0 = authorizer, bit 1 = progress handler, bit 2 = runtime limits.
 */
BOTTOGRAM_EXPORT int bottogram_sqlite_security_probe(sqlite3 *database) {
  const sqlite3_api_routines *api = bottogram_api();
  sqlite3_stmt *statement = NULL;
  struct bottogram_probe probe = {0, 0};
  int capabilities = 0;
  int result;

  if (api == NULL || database == NULL || api->set_authorizer == NULL ||
      api->progress_handler == NULL || api->limit == NULL ||
      api->prepare_v2 == NULL || api->step == NULL || api->finalize == NULL) {
    return 0;
  }

  result = api->set_authorizer(database, bottogram_probe_deny, &probe);
  if (result != SQLITE_OK) {
    return 0;
  }
  result = api->prepare_v2(database, "SELECT 1", -1, &statement, NULL);
  if (statement != NULL) {
    api->finalize(statement);
    statement = NULL;
  }
  api->set_authorizer(database, NULL, NULL);
  if (result == SQLITE_AUTH && probe.authorizer_calls > 0) {
    capabilities |= 1;
  }

  api->progress_handler(database, 1, bottogram_probe_interrupt, &probe);
  result = api->prepare_v2(database, "SELECT 1", -1, &statement, NULL);
  if (result == SQLITE_OK) {
    result = api->step(statement);
  }
  if (statement != NULL) {
    api->finalize(statement);
  }
  api->progress_handler(database, 0, NULL, NULL);
  if (result == SQLITE_INTERRUPT && probe.progress_calls > 0) {
    capabilities |= 2;
  }

  /* A negative value reads the existing limit without changing it. */
  if (api->limit(database, SQLITE_LIMIT_ATTACHED, -1) >= 0) {
    capabilities |= 4;
  }
  return capabilities;
}

BOTTOGRAM_EXPORT int bottogram_sqlite_core_version(void) {
  const sqlite3_api_routines *api = bottogram_api();
  return api == NULL || api->libversion_number == NULL
             ? 0
             : api->libversion_number();
}
