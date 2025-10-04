-- base58id--1.0.sql

-- Create shell type first
CREATE TYPE base58id;

-- Text/Binary I/O functions (must be defined before the full type definition)
CREATE FUNCTION base58id_in(cstring)  RETURNS base58id IMMUTABLE STRICT LANGUAGE C AS 'MODULE_PATHNAME';
CREATE FUNCTION base58id_out(base58id) RETURNS cstring  IMMUTABLE STRICT LANGUAGE C AS 'MODULE_PATHNAME';
CREATE FUNCTION base58id_recv(internal) RETURNS base58id IMMUTABLE STRICT LANGUAGE C AS 'MODULE_PATHNAME';
CREATE FUNCTION base58id_send(base58id) RETURNS bytea    IMMUTABLE STRICT LANGUAGE C AS 'MODULE_PATHNAME';

-- Now create the full type definition. 8 bytes, by-value, double alignment.
CREATE TYPE base58id (
  INPUT          = base58id_in,
  OUTPUT         = base58id_out,
  RECEIVE        = base58id_recv,
  SEND           = base58id_send,
  INTERNALLENGTH = 8,
  PASSEDBYVALUE,
  ALIGNMENT      = double,
  STORAGE        = plain,
  CATEGORY       = 'U'
);

-- Operators
CREATE FUNCTION base58id_cmp(base58id, base58id) RETURNS int4 IMMUTABLE STRICT PARALLEL SAFE LANGUAGE C AS 'MODULE_PATHNAME';
CREATE FUNCTION base58id_eq (base58id, base58id) RETURNS bool IMMUTABLE STRICT PARALLEL SAFE LANGUAGE C AS 'MODULE_PATHNAME';
CREATE FUNCTION base58id_ne (base58id, base58id) RETURNS bool IMMUTABLE STRICT PARALLEL SAFE LANGUAGE C AS 'MODULE_PATHNAME';
CREATE FUNCTION base58id_lt (base58id, base58id) RETURNS bool IMMUTABLE STRICT PARALLEL SAFE LANGUAGE C AS 'MODULE_PATHNAME';
CREATE FUNCTION base58id_le (base58id, base58id) RETURNS bool IMMUTABLE STRICT PARALLEL SAFE LANGUAGE C AS 'MODULE_PATHNAME';
CREATE FUNCTION base58id_gt (base58id, base58id) RETURNS bool IMMUTABLE STRICT PARALLEL SAFE LANGUAGE C AS 'MODULE_PATHNAME';
CREATE FUNCTION base58id_ge (base58id, base58id) RETURNS bool IMMUTABLE STRICT PARALLEL SAFE LANGUAGE C AS 'MODULE_PATHNAME';

CREATE OPERATOR = (LEFTARG = base58id, RIGHTARG = base58id, PROCEDURE = base58id_eq, COMMUTATOR = '=', NEGATOR = '<>', RESTRICT = eqsel, JOIN = eqjoinsel);
CREATE OPERATOR <> (LEFTARG = base58id, RIGHTARG = base58id, PROCEDURE = base58id_ne, COMMUTATOR = '<>', NEGATOR = '=', RESTRICT = neqsel, JOIN = neqjoinsel);
CREATE OPERATOR < (LEFTARG = base58id, RIGHTARG = base58id, PROCEDURE = base58id_lt, RESTRICT = scalarltsel, JOIN = scalarltjoinsel);
CREATE OPERATOR <=(LEFTARG = base58id, RIGHTARG = base58id, PROCEDURE = base58id_le, RESTRICT = scalarltsel, JOIN = scalarltjoinsel);
CREATE OPERATOR > (LEFTARG = base58id, RIGHTARG = base58id, PROCEDURE = base58id_gt, RESTRICT = scalargtsel, JOIN = scalargtjoinsel);
CREATE OPERATOR >=(LEFTARG = base58id, RIGHTARG = base58id, PROCEDURE = base58id_ge, RESTRICT = scalargtsel, JOIN = scalargtjoinsel);

-- btree opclass
CREATE OPERATOR CLASS base58id_btree_ops
DEFAULT FOR TYPE base58id USING btree AS
  OPERATOR 1 < ,
  OPERATOR 2 <=,
  OPERATOR 3 = ,
  OPERATOR 4 >=,
  OPERATOR 5 > ,
  FUNCTION 1 base58id_cmp(base58id, base58id);

-- hash opclass
CREATE FUNCTION base58id_hash(base58id) RETURNS int4 IMMUTABLE STRICT PARALLEL SAFE LANGUAGE C AS 'MODULE_PATHNAME';

CREATE OPERATOR CLASS base58id_hash_ops
DEFAULT FOR TYPE base58id USING hash AS
  OPERATOR 1 = ,
  FUNCTION 1 base58id_hash(base58id);

-- Casts
CREATE FUNCTION base58id_to_bigint(base58id) RETURNS bigint IMMUTABLE STRICT LANGUAGE C AS 'MODULE_PATHNAME';
CREATE FUNCTION bigint_to_base58id(bigint)   RETURNS base58id IMMUTABLE STRICT LANGUAGE C AS 'MODULE_PATHNAME';
CREATE FUNCTION base58id_to_text(base58id)   RETURNS text   IMMUTABLE STRICT LANGUAGE C AS 'MODULE_PATHNAME';
CREATE FUNCTION text_to_base58id(text)       RETURNS base58id IMMUTABLE STRICT LANGUAGE C AS 'MODULE_PATHNAME';

CREATE CAST (base58id AS bigint)  WITH FUNCTION base58id_to_bigint(base58id) AS ASSIGNMENT;
CREATE CAST (bigint   AS base58id) WITH FUNCTION bigint_to_base58id(bigint)   AS ASSIGNMENT;
CREATE CAST (base58id AS text)    WITH FUNCTION base58id_to_text(base58id)   AS IMPLICIT;
CREATE CAST (text     AS base58id) WITH FUNCTION text_to_base58id(text)       AS IMPLICIT;
