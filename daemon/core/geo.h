#ifndef LEGACYRAY_GEO_H
#define LEGACYRAY_GEO_H

/* geosite / geoip for routing rules, the way xray and happ spell them:
   "direct geosite category-ru", "direct geoip ru".

   the v2fly .dat files are protobuf lists of every category there is. an old
   phone has no business holding all of them in memory, so a download is
   read once and only the categories the rules name are written out as small
   text files next to it (site-<code>.txt, ip-<code>.txt). the daemon loads
   those into hash sets; a lookup costs one probe per label of the name.

   everything here is plain C over caller-provided paths, so the host tests
   drive it with fixtures and the daemon points it at its own directory */

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define GEO_CODE_MAX 64

/* where the daemon keeps downloads and extracts; readable by the app */
#include "../../common/senko_paths.h"
#define LR_GEO_DIR SENKO_GEO_DIR

/* <dir>/site-<code>.txt or ip-<code>.txt */
int geo_file_path(char *out, size_t cap, const char *dir, char kind, const char *code);

typedef enum {
    GEO_OK = 0,
    GEO_ERR_ARG = -1,
    GEO_ERR_IO = -2,
    GEO_ERR_FORMAT = -3,   /* not a geosite / geoip list */
    GEO_ERR_MEMORY = -4,
    GEO_ERR_MISSING = -5   /* the category is not in the file */
} geo_status_t;

/* "category-ru", "google@cn": lower case, [a-z0-9._-!] with one optional
   @attribute. returns 0 and writes the canonical form, -1 when invalid */
int geo_code_normalize(const char *text, size_t len, char *out, size_t cap);

/* pull the named categories out of a geosite.dat held in memory and write
   <dir>/site-<code>.txt for each one found. found[i] is set to the number of
   entries written for codes[i], or -1 when the file has no such category */
geo_status_t geo_extract_sites(const uint8_t *dat, size_t len,
                               const char *const *codes, size_t ncodes,
                               const char *dir, long *found);

/* the same for geoip.dat: <dir>/ip-<code>.txt, ipv4 cidrs only (the routing
   layers are ipv4) */
geo_status_t geo_extract_ips(const uint8_t *dat, size_t len,
                             const char *const *codes, size_t ncodes,
                             const char *dir, long *found);

/* a plain cidr list ("1.2.3.0/24" per line, # comments) saved as
   <dir>/ip-<code>.txt after checking every line. returns the count kept */
long geo_save_ip_list(const char *text, size_t len, const char *code, const char *dir);

/* the ranges "private" stands for, written out when a rule names them */
long geo_write_private(const char *dir);

/* ---- the loaded sets ------------------------------------------------- */

typedef struct geo_db geo_db_t;

geo_db_t *geo_db_new(void);
void geo_db_free(geo_db_t *db);

/* load <dir>/site-<code>.txt (kind 's') or ip-<code>.txt (kind 'i').
   returns the number of entries, or a negative geo_status_t */
long geo_db_load(geo_db_t *db, char kind, const char *code, const char *dir);

/* 1 when the name (already lower case, no trailing dot) is in the category */
int geo_db_site_match(const geo_db_t *db, const char *code, const char *name);
/* 1 when the ipv4 address (network order) is in the country */
int geo_db_ip_match(const geo_db_t *db, const char *code, const uint8_t addr[4]);
/* entries loaded for a code, -1 when it is not loaded */
long geo_db_count(const geo_db_t *db, char kind, const char *code);

/* ---- the process-wide database the rule matcher consults ------------- */

/* swap in a new database; the old one is freed once no lookup holds it */
void geo_publish(geo_db_t *db);
int geo_site_match(const char *code, const char *name);
int geo_ip_match(const char *code, const uint8_t addr[4]);
long geo_count(char kind, const char *code);

#ifdef __cplusplus
}
#endif

#endif
