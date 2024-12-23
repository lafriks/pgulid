-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pgulid" to load this file.\quit

-- pgulid is based on OK Log's Go implementation of the ULID spec
--
-- https://github.com/oklog/ulid
-- https://github.com/ulid/spec
--
-- Copyright 2016 The Oklog Authors
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
-- http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

CREATE OR REPLACE FUNCTION generate_ulid()
RETURNS TEXT
AS $$
DECLARE
  -- Crockford's Base32
  encoding   BYTEA = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  timestamp  BYTEA = E'\\000\\000\\000\\000\\000\\000';

  unix_time  BIGINT;
  ulid       BYTEA;
BEGIN
  -- 6 timestamp bytes
  unix_time = (EXTRACT(EPOCH FROM CLOCK_TIMESTAMP()) * 1000)::BIGINT;
  timestamp = SET_BYTE(timestamp, 0, (unix_time >> 40)::BIT(8)::INTEGER);
  timestamp = SET_BYTE(timestamp, 1, (unix_time >> 32)::BIT(8)::INTEGER);
  timestamp = SET_BYTE(timestamp, 2, (unix_time >> 24)::BIT(8)::INTEGER);
  timestamp = SET_BYTE(timestamp, 3, (unix_time >> 16)::BIT(8)::INTEGER);
  timestamp = SET_BYTE(timestamp, 4, (unix_time >> 8)::BIT(8)::INTEGER);
  timestamp = SET_BYTE(timestamp, 5, unix_time::BIT(8)::INTEGER);

  -- 10 entropy bytes
  ulid = timestamp || gen_random_bytes(10);

  -- Encode the timestamp
  RETURN CHR(GET_BYTE(encoding, (GET_BYTE(ulid, 0) & 224) >> 5))
    || CHR(GET_BYTE(encoding, (GET_BYTE(ulid, 0) & 31)))
    || CHR(GET_BYTE(encoding, (GET_BYTE(ulid, 1) & 248) >> 3))
    || CHR(GET_BYTE(encoding, ((GET_BYTE(ulid, 1) & 7) << 2) | ((GET_BYTE(ulid, 2) & 192) >> 6)))
    || CHR(GET_BYTE(encoding, (GET_BYTE(ulid, 2) & 62) >> 1))
    || CHR(GET_BYTE(encoding, ((GET_BYTE(ulid, 2) & 1) << 4) | ((GET_BYTE(ulid, 3) & 240) >> 4)))
    || CHR(GET_BYTE(encoding, ((GET_BYTE(ulid, 3) & 15) << 1) | ((GET_BYTE(ulid, 4) & 128) >> 7)))
    || CHR(GET_BYTE(encoding, (GET_BYTE(ulid, 4) & 124) >> 2))
    || CHR(GET_BYTE(encoding, ((GET_BYTE(ulid, 4) & 3) << 3) | ((GET_BYTE(ulid, 5) & 224) >> 5)))
    || CHR(GET_BYTE(encoding, (GET_BYTE(ulid, 5) & 31)))
  -- Encode the entropy
    || CHR(GET_BYTE(encoding, (GET_BYTE(ulid, 6) & 248) >> 3))
    || CHR(GET_BYTE(encoding, ((GET_BYTE(ulid, 6) & 7) << 2) | ((GET_BYTE(ulid, 7) & 192) >> 6)))
    || CHR(GET_BYTE(encoding, (GET_BYTE(ulid, 7) & 62) >> 1))
    || CHR(GET_BYTE(encoding, ((GET_BYTE(ulid, 7) & 1) << 4) | ((GET_BYTE(ulid, 8) & 240) >> 4)))
    || CHR(GET_BYTE(encoding, ((GET_BYTE(ulid, 8) & 15) << 1) | ((GET_BYTE(ulid, 9) & 128) >> 7)))
    || CHR(GET_BYTE(encoding, (GET_BYTE(ulid, 9) & 124) >> 2))
    || CHR(GET_BYTE(encoding, ((GET_BYTE(ulid, 9) & 3) << 3) | ((GET_BYTE(ulid, 10) & 224) >> 5)))
    || CHR(GET_BYTE(encoding, (GET_BYTE(ulid, 10) & 31)))
    || CHR(GET_BYTE(encoding, (GET_BYTE(ulid, 11) & 248) >> 3))
    || CHR(GET_BYTE(encoding, ((GET_BYTE(ulid, 11) & 7) << 2) | ((GET_BYTE(ulid, 12) & 192) >> 6)))
    || CHR(GET_BYTE(encoding, (GET_BYTE(ulid, 12) & 62) >> 1))
    || CHR(GET_BYTE(encoding, ((GET_BYTE(ulid, 12) & 1) << 4) | ((GET_BYTE(ulid, 13) & 240) >> 4)))
    || CHR(GET_BYTE(encoding, ((GET_BYTE(ulid, 13) & 15) << 1) | ((GET_BYTE(ulid, 14) & 128) >> 7)))
    || CHR(GET_BYTE(encoding, (GET_BYTE(ulid, 14) & 124) >> 2))
    || CHR(GET_BYTE(encoding, ((GET_BYTE(ulid, 14) & 3) << 3) | ((GET_BYTE(ulid, 15) & 224) >> 5)))
    || CHR(GET_BYTE(encoding, (GET_BYTE(ulid, 15) & 31)));
END
$$
LANGUAGE plpgsql
VOLATILE;

CREATE OR REPLACE FUNCTION parse_ulid_timestamp(ulid TEXT) RETURNS TIMESTAMP
AS $$
DECLARE
  -- Crockford's Base32
  -- Drop the 0 because strpos() returns 0 for not-found
  -- We've pre-validated already, so this is safe
  encoding   TEXT = '123456789ABCDEFGHJKMNPQRSTVWXYZ';
  ts         BIGINT;
  v          CHAR[];
BEGIN
  IF ulid IS NULL THEN
    RETURN null;
  END IF;

  ulid = upper(ulid);

  IF NOT ulid ~ '^[0123456789ABCDEFGHJKMNPQRSTVWXYZ]{26}$' THEN
    RAISE EXCEPTION 'Invalid ULID: %', ulid;
  END IF;

  -- first 10 ULID characters are the timestamp
  v = regexp_split_to_array(substring(ulid for 10), '');

  -- base32 is 5 bits / character
  -- posix milliseconds (6 bytes)
  ts = (strpos(encoding, v[1])::bigint << 45)
    + (strpos(encoding, v[2])::bigint << 40)
    + (strpos(encoding, v[3])::bigint << 35)
    + (strpos(encoding, v[4])::bigint << 30)
    + (strpos(encoding, v[5]) << 25)
    + (strpos(encoding, v[6]) << 20)
    + (strpos(encoding, v[7]) << 15)
    + (strpos(encoding, v[8]) << 10)
    + (strpos(encoding, v[9]) << 5)
    + strpos(encoding, v[10]);

  RETURN to_timestamp(ts / 1000.0);
END
$$
LANGUAGE plpgsql
IMMUTABLE;
