#include "postgres.h"
#include "fmgr.h"
#include "utils/builtins.h"
#include "libpq/pqformat.h"   /* send/recv */
#include "access/hash.h"      /* hash_uint32/64 helpers if available */

#ifdef PG_MODULE_MAGIC
PG_MODULE_MAGIC;
#endif

/* ------- Base58 alphabet (Bitcoin) ------- */
static const char *B58_ALPH = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
static int8_t B58_IDX[128]; /* map ASCII -> value, -1 = invalid */

static void
b58_init(void)
{
    static bool inited = false;
    if (inited) return;
    for (int i = 0; i < 128; i++) B58_IDX[i] = -1;
    for (int i = 0; B58_ALPH[i]; i++) B58_IDX[(unsigned char)B58_ALPH[i]] = i;
    inited = true;
}

/* Encode uint64 -> base58 into caller-supplied buffer (>= 24 bytes). Returns pointer to start. */
static char *
b58_encode_u64(uint64 val, char *buf, size_t buflen)
{
    /* Max digits base58 for 2^64-1 is 11. We pad all output to 11 chars. */
    #define B58_WIDTH 11
    char tmp[24];
    int  len = 0;

    if (buflen < sizeof(tmp))
        ereport(ERROR, (errmsg("internal buffer too small")));

    /* Convert value to base58 digits (least significant first) */
    if (val == 0) {
        len = 1;
        tmp[0] = '1';
    } else {
        while (val > 0) {
            uint64 q = val / 58;
            uint32 r = (uint32)(val - q*58);
            tmp[len++] = B58_ALPH[r];
            val = q;
        }
    }

    /* Pad with leading '1' (base58 zero) to B58_WIDTH, then reverse into buf */
    for (int i = 0; i < B58_WIDTH; i++) {
        if (i < len)
            buf[i] = tmp[len - 1 - i];
        else
            buf[i] = '1';  /* left-pad with '1' (represents 0) */
    }
    buf[B58_WIDTH] = '\0';
    return buf;
}

/* Decode base58 -> uint64. Returns true on success, false on invalid/overflow. */
static bool
b58_decode_u64(const char *str, uint64 *out)
{
    uint64 acc = 0;
    const unsigned char *p;

    b58_init();
    for (p = (const unsigned char*)str; *p; p++) {
        unsigned char c = *p;
        uint32 v;
        if (c >= 128 || B58_IDX[c] < 0) return false;
        v = (uint32)B58_IDX[c];
        /* acc = acc*58 + v   with overflow check */
        if (acc > (UINT64_MAX - v) / 58) return false;
        acc = acc * 58 + v;
    }
    *out = acc;
    return true;
}

/* Convenience macros: store/load bits via int64 Datum macros */
#define GET_BASE58ID(n)   ((uint64) PG_GETARG_INT64(n))
#define RET_BASE58ID(v)   PG_RETURN_INT64((int64) (v))

/* ---------- SQL-callable functions ---------- */
PG_FUNCTION_INFO_V1(base58id_in);
Datum base58id_in(PG_FUNCTION_ARGS)
{
    char   *str = PG_GETARG_CSTRING(0);
    uint64  v;
    if (*str == '\0' || !b58_decode_u64(str, &v))
        ereport(ERROR, (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
                        errmsg("invalid base58 value: \"%s\"", str)));
    RET_BASE58ID(v);
}

PG_FUNCTION_INFO_V1(base58id_out);
Datum base58id_out(PG_FUNCTION_ARGS)
{
    uint64 v = GET_BASE58ID(0);
    char buf[24];
    b58_encode_u64(v, buf, sizeof(buf));
    PG_RETURN_CSTRING(pstrdup(buf));
}

/* Binary I/O (network order) */
PG_FUNCTION_INFO_V1(base58id_recv);
Datum base58id_recv(PG_FUNCTION_ARGS)
{
    StringInfo  msg = (StringInfo) PG_GETARG_POINTER(0);
    uint64      v   = pq_getmsgint64(msg);
    RET_BASE58ID(v);
}

PG_FUNCTION_INFO_V1(base58id_send);
Datum base58id_send(PG_FUNCTION_ARGS)
{
    uint64     v = GET_BASE58ID(0);
    StringInfoData buf;
    pq_begintypsend(&buf);
    pq_sendint64(&buf, v);
    PG_RETURN_BYTEA_P(pq_endtypsend(&buf));
}

/* Casts */
PG_FUNCTION_INFO_V1(base58id_to_bigint);
Datum base58id_to_bigint(PG_FUNCTION_ARGS)
{
    uint64 v = GET_BASE58ID(0);
    /* If > INT64_MAX, bigint (signed) would overflow; throw to be safe. */
    if (v > INT64_MAX)
        ereport(ERROR, (errcode(ERRCODE_NUMERIC_VALUE_OUT_OF_RANGE),
                        errmsg("value out of range for bigint")));
    PG_RETURN_INT64((int64) v);
}

PG_FUNCTION_INFO_V1(bigint_to_base58id);
Datum bigint_to_base58id(PG_FUNCTION_ARGS)
{
    int64 s = PG_GETARG_INT64(0);
    if (s < 0)
        ereport(ERROR, (errcode(ERRCODE_NUMERIC_VALUE_OUT_OF_RANGE),
                        errmsg("negative bigint cannot be cast to base58id")));
    RET_BASE58ID((uint64) s);
}

PG_FUNCTION_INFO_V1(text_to_base58id);
Datum text_to_base58id(PG_FUNCTION_ARGS)
{
    text  *t   = PG_GETARG_TEXT_PP(0);
    char  *str = text_to_cstring(t);
    uint64 v;
    if (*str == '\0' || !b58_decode_u64(str, &v))
        ereport(ERROR, (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
                        errmsg("invalid base58 value: \"%s\"", str)));
    pfree(str);
    RET_BASE58ID(v);
}

PG_FUNCTION_INFO_V1(base58id_to_text);
Datum base58id_to_text(PG_FUNCTION_ARGS)
{
    uint64 v = GET_BASE58ID(0);
    char buf[24];
    b58_encode_u64(v, buf, sizeof(buf));
    PG_RETURN_TEXT_P(cstring_to_text(buf));
}

/* Comparisons */
PG_FUNCTION_INFO_V1(base58id_cmp);
Datum base58id_cmp(PG_FUNCTION_ARGS)
{
    uint64 a = GET_BASE58ID(0);
    uint64 b = GET_BASE58ID(1);
    if (a < b) PG_RETURN_INT32(-1);
    if (a > b) PG_RETURN_INT32(1);
    PG_RETURN_INT32(0);
}

PG_FUNCTION_INFO_V1(base58id_eq);
Datum base58id_eq(PG_FUNCTION_ARGS)
{
    PG_RETURN_BOOL(GET_BASE58ID(0) == GET_BASE58ID(1));
}
PG_FUNCTION_INFO_V1(base58id_ne);
Datum base58id_ne(PG_FUNCTION_ARGS)
{
    PG_RETURN_BOOL(GET_BASE58ID(0) != GET_BASE58ID(1));
}
PG_FUNCTION_INFO_V1(base58id_lt);
Datum base58id_lt(PG_FUNCTION_ARGS)
{
    PG_RETURN_BOOL(GET_BASE58ID(0) < GET_BASE58ID(1));
}
PG_FUNCTION_INFO_V1(base58id_le);
Datum base58id_le(PG_FUNCTION_ARGS)
{
    PG_RETURN_BOOL(GET_BASE58ID(0) <= GET_BASE58ID(1));
}
PG_FUNCTION_INFO_V1(base58id_gt);
Datum base58id_gt(PG_FUNCTION_ARGS)
{
    PG_RETURN_BOOL(GET_BASE58ID(0) > GET_BASE58ID(1));
}
PG_FUNCTION_INFO_V1(base58id_ge);
Datum base58id_ge(PG_FUNCTION_ARGS)
{
    PG_RETURN_BOOL(GET_BASE58ID(0) >= GET_BASE58ID(1));
}

/* Hash (32-bit) – use PostgreSQL's hash_any for good distribution */
PG_FUNCTION_INFO_V1(base58id_hash);
Datum base58id_hash(PG_FUNCTION_ARGS)
{
    uint64 v = GET_BASE58ID(0);
    return hash_any((unsigned char *) &v, sizeof(uint64));
}
