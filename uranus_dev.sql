--
-- PostgreSQL database dump
--

-- Dumped from database version 16.2 (Postgres.app)
-- Dumped by pg_dump version 16.2 (Postgres.app)

-- Started on 2026-04-05 19:24:42 CEST

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 18 (class 2615 OID 2265937)
-- Name: uranus; Type: SCHEMA; Schema: -; Owner: oklab
--

CREATE SCHEMA uranus;


ALTER SCHEMA uranus OWNER TO oklab;

--
-- TOC entry 2501 (class 1247 OID 2307894)
-- Name: event_release_status; Type: TYPE; Schema: uranus; Owner: oklab
--

CREATE TYPE uranus.event_release_status AS ENUM (
    'inherited',
    'draft',
    'review',
    'released',
    'cancelled',
    'deferred',
    'rescheduled'
);


ALTER TYPE uranus.event_release_status OWNER TO oklab;

--
-- TOC entry 2498 (class 1247 OID 2307874)
-- Name: uranus_price_type; Type: TYPE; Schema: uranus; Owner: oklab
--

CREATE TYPE uranus.uranus_price_type AS ENUM (
    'not_specified',
    'regular_price',
    'free',
    'donation',
    'tiered_prices'
);


ALTER TYPE uranus.uranus_price_type OWNER TO oklab;

--
-- TOC entry 2495 (class 1247 OID 2307862)
-- Name: uranus_ticket_flag; Type: TYPE; Schema: uranus; Owner: oklab
--

CREATE TYPE uranus.uranus_ticket_flag AS ENUM (
    'advance_ticket',
    'ticket_required',
    'on_site_ticket_sales',
    'registration_required'
);


ALTER TYPE uranus.uranus_ticket_flag OWNER TO oklab;

--
-- TOC entry 1340 (class 1255 OID 2265938)
-- Name: check_event_date_space_venue(); Type: FUNCTION; Schema: uranus; Owner: oklab
--

CREATE FUNCTION uranus.check_event_date_space_venue() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    space_venue_id integer;
BEGIN
    -- Skip check if space_id is NULL
    IF NEW.space_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Get venue of referenced space
    SELECT venue_id INTO space_venue_id
    FROM uranus.space
    WHERE id = NEW.space_id;

    -- Enforce match between space.venue_id and event_date.venue_id
    IF NEW.venue_id IS NOT NULL AND NEW.venue_id <> space_venue_id THEN
        RAISE EXCEPTION
            'space_id % belongs to venue %, but event_date.venue_id is %',
            NEW.space_id, space_venue_id, NEW.venue_id
            USING ERRCODE = 'foreign_key_violation';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION uranus.check_event_date_space_venue() OWNER TO oklab;

--
-- TOC entry 1456 (class 1255 OID 2265939)
-- Name: event_search_text_trigger(); Type: FUNCTION; Schema: uranus; Owner: oklab
--

CREATE FUNCTION uranus.event_search_text_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE NOTICE 'Trigger fired for event id=%', NEW.id;

    NEW.search_text := unaccent_immutable(normalize_german(
                        NEW.title || ' ' || NEW.subtitle || ' ' ||
                        COALESCE(NEW.description, '') || ' ' ||
                        COALESCE(NEW.teaser_text, '')
                     ));
    RETURN NEW;
END;
$$;


ALTER FUNCTION uranus.event_search_text_trigger() OWNER TO oklab;

--
-- TOC entry 1515 (class 1255 OID 2283076)
-- Name: event_update_search_text(); Type: FUNCTION; Schema: uranus; Owner: oklab
--

CREATE FUNCTION uranus.event_update_search_text() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.search_text :=
    lower(
      unaccent_immutable(
        normalize_german(
          COALESCE(NEW.title,'') || ' ' ||
          COALESCE(NEW.subtitle,'') || ' ' ||
          COALESCE(NEW.description,'') || ' ' ||
          COALESCE(NEW.summary,'') || ' ' ||
          COALESCE(NEW.participation_info,'') || ' ' ||
          COALESCE(array_to_string(NEW.tags,' '),'')
        )
      )
    );
  RETURN NEW;
END;
$$;


ALTER FUNCTION uranus.event_update_search_text() OWNER TO oklab;

--
-- TOC entry 1478 (class 1255 OID 2265940)
-- Name: normalize_german(text); Type: FUNCTION; Schema: uranus; Owner: oklab
--

CREATE FUNCTION uranus.normalize_german(input_text text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
  RETURN lower(
    replace(
      replace(
        replace(
          replace(
            replace(input_text,
              'ä','ae'),
            'ö','oe'),
          'ü','ue'),
        'ß','ss'),
      'ẞ','ss')
  );
END;
$$;


ALTER FUNCTION uranus.normalize_german(input_text text) OWNER TO oklab;

--
-- TOC entry 973 (class 1255 OID 2307852)
-- Name: randomish_from_timestamp(timestamp without time zone, bigint); Type: FUNCTION; Schema: uranus; Owner: oklab
--

CREATE FUNCTION uranus.randomish_from_timestamp(created_at timestamp without time zone, row_id bigint) RETURNS bigint
    LANGUAGE plpgsql IMMUTABLE STRICT
    AS $$
DECLARE
    epoch_us bigint;
    combined bigint;
BEGIN
    -- Convert timestamp to microseconds since epoch
    epoch_us := (EXTRACT(EPOCH FROM created_at) * 1000000)::bigint;

    -- Combine timestamp with row ID
    combined := epoch_us # (row_id * 31);  -- XOR with row_id multiplier

    -- Optional diffusion: rotate bits
    combined := ((combined << 17) | (combined >> (64 - 17))) & 9223372036854775807;  -- keep positive

    RETURN combined;
END;
$$;


ALTER FUNCTION uranus.randomish_from_timestamp(created_at timestamp without time zone, row_id bigint) OWNER TO oklab;

--
-- TOC entry 925 (class 1255 OID 2265941)
-- Name: set_default_event_date_venue(); Type: FUNCTION; Schema: uranus; Owner: oklab
--

CREATE FUNCTION uranus.set_default_event_date_venue() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.venue_id IS NULL THEN
        SELECT venue_id INTO NEW.venue_id
        FROM uranus.event
        WHERE id = NEW.event_id;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION uranus.set_default_event_date_venue() OWNER TO oklab;

--
-- TOC entry 1072 (class 1255 OID 2265942)
-- Name: update_document_multilang(); Type: FUNCTION; Schema: uranus; Owner: oklab
--

CREATE FUNCTION uranus.update_document_multilang() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  base_text text;
BEGIN
  base_text := coalesce(NEW.title,'') || ' ' || coalesce(NEW.subtitle,'') || ' ' ||
               coalesce(NEW.description,'') || ' ' || coalesce(NEW.teaser_text,'');

  NEW.document_multilang :=
       to_tsvector('english', unaccent(base_text))
    || to_tsvector('german',  unaccent(base_text) || ' ' || uranus.normalize_german(base_text))
    || to_tsvector('danish',  unaccent(base_text));

  RETURN NEW;
END;
$$;


ALTER FUNCTION uranus.update_document_multilang() OWNER TO oklab;

--
-- TOC entry 946 (class 1255 OID 2266478)
-- Name: update_event_types_array(); Type: FUNCTION; Schema: uranus; Owner: oklab
--

CREATE FUNCTION uranus.update_event_types_array() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    eid integer;
BEGIN
    -- Determine which event_id to use
    IF TG_OP = 'DELETE' THEN
        eid := OLD.event_id;
    ELSE
        eid := NEW.event_id;
    END IF;

    -- Update the event's types column
    UPDATE uranus.event
    SET types = ARRAY(
        SELECT ARRAY[etl.type_id, COALESCE(etl.genre_id, 0)]
        FROM uranus.event_type_link etl
        WHERE etl.event_id = eid
    )
    WHERE id = eid;

    RETURN NULL; -- AFTER trigger can return NULL
END;
$$;


ALTER FUNCTION uranus.update_event_types_array() OWNER TO oklab;

--
-- TOC entry 1206 (class 1255 OID 2265943)
-- Name: update_modified_at(); Type: FUNCTION; Schema: uranus; Owner: oklab
--

CREATE FUNCTION uranus.update_modified_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.modified_at = CURRENT_TIMESTAMP;  -- sets the update time automatically
    RETURN NEW;
END;
$$;


ALTER FUNCTION uranus.update_modified_at() OWNER TO oklab;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 532 (class 1259 OID 2265944)
-- Name: accessibility_flag; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.accessibility_flag (
    flag integer NOT NULL,
    iso_639_1 character varying(2) NOT NULL,
    name text NOT NULL,
    topic_id integer NOT NULL,
    key text
);


ALTER TABLE uranus.accessibility_flag OWNER TO oklab;

--
-- TOC entry 566 (class 1259 OID 2325418)
-- Name: accessibility_topic; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.accessibility_topic (
    topic_id integer,
    iso_639_1 character varying(2),
    name text,
    key text
);


ALTER TABLE uranus.accessibility_topic OWNER TO oklab;

--
-- TOC entry 533 (class 1259 OID 2265962)
-- Name: country; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.country (
    code character varying(3) NOT NULL,
    name text NOT NULL,
    iso_639_1 character varying(2) NOT NULL
);


ALTER TABLE uranus.country OWNER TO oklab;

--
-- TOC entry 534 (class 1259 OID 2265967)
-- Name: currency; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.currency (
    id integer NOT NULL,
    code character varying(3),
    iso_639_1 character varying(2),
    name text
);


ALTER TABLE uranus.currency OWNER TO oklab;

--
-- TOC entry 535 (class 1259 OID 2265972)
-- Name: currency_id_seq; Type: SEQUENCE; Schema: uranus; Owner: oklab
--

ALTER TABLE uranus.currency ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME uranus.currency_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 597 (class 1259 OID 2351825)
-- Name: event; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.event (
    uuid uuid NOT NULL,
    external_id text,
    created_by uuid NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    modified_by uuid,
    modified_at timestamp without time zone,
    release_date date,
    release_status uranus.event_release_status DEFAULT 'draft'::uranus.event_release_status NOT NULL,
    org_uuid uuid NOT NULL,
    venue_uuid uuid,
    space_uuid uuid,
    content_iso_639_1 character varying(2),
    title text NOT NULL,
    description text,
    subtitle text,
    summary text,
    categories integer[],
    languages text[],
    tags text[],
    occasion_type_id integer,
    min_age integer,
    max_age integer,
    participation_info text,
    max_attendees integer,
    visitor_info_flags bigint,
    meeting_point text,
    source_link text,
    online_link text,
    ticket_link text,
    ticket_flags uranus.uranus_ticket_flag[] DEFAULT '{}'::uranus.uranus_ticket_flag[] NOT NULL,
    price_type uranus.uranus_price_type DEFAULT 'not_specified'::uranus.uranus_price_type NOT NULL,
    currency character varying(8),
    min_price double precision,
    max_price double precision,
    custom text,
    style text,
    search_text text
);


ALTER TABLE uranus.event OWNER TO oklab;

--
-- TOC entry 567 (class 1259 OID 2351146)
-- Name: event_category; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.event_category (
    category_id integer,
    iso_639_1 character varying(2),
    name text NOT NULL,
    schema_org_type text
);


ALTER TABLE uranus.event_category OWNER TO oklab;

--
-- TOC entry 575 (class 1259 OID 2351604)
-- Name: event_date; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.event_date (
    uuid uuid,
    created_by uuid NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    modified_by uuid,
    modified_at timestamp without time zone,
    release_status uranus.event_release_status DEFAULT 'inherited'::uranus.event_release_status NOT NULL,
    event_uuid uuid,
    venue_uuid uuid,
    space_uuid uuid,
    start_date date NOT NULL,
    start_time time without time zone,
    end_date date,
    end_time time without time zone,
    entry_time time without time zone,
    duration integer,
    all_day boolean,
    ticket_link text,
    availability_status_id integer,
    accessibility_info text,
    sold_out boolean,
    limited_tickets_remaining boolean,
    custom text
);


ALTER TABLE uranus.event_date OWNER TO oklab;

--
-- TOC entry 5863 (class 0 OID 0)
-- Dependencies: 575
-- Name: COLUMN event_date.venue_uuid; Type: COMMENT; Schema: uranus; Owner: oklab
--

COMMENT ON COLUMN uranus.event_date.venue_uuid IS 'Overrides the parent event''s venue. If NULL, the venue from uranus.event.venue_id is used.';


--
-- TOC entry 576 (class 1259 OID 2351617)
-- Name: event_date_projection; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.event_date_projection (
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    modified_at timestamp without time zone,
    release_status uranus.event_release_status DEFAULT 'inherited'::uranus.event_release_status NOT NULL,
    event_date_uuid uuid NOT NULL,
    event_uuid uuid NOT NULL,
    venue_uuid uuid,
    space_uuid uuid,
    venue_name text,
    venue_street text,
    venue_house_number text,
    venue_postal_code text,
    venue_city text,
    venue_country character(3),
    venue_state character varying(2),
    venue_point public.geometry(Point,4326),
    venue_link text,
    space_name character varying(255),
    space_description text,
    space_type text,
    space_total_capacity integer,
    space_seating_capacity integer,
    space_building_level integer,
    space_link text,
    space_accessibility_summary text,
    space_accessibility_flags bigint,
    start_date date NOT NULL,
    start_time time without time zone,
    end_date date,
    end_time time without time zone,
    entry_time time without time zone,
    duration integer,
    all_day boolean,
    ticket_link text,
    availability_status_id integer,
    accessibility_info text,
    custom text,
    event_start_at timestamp without time zone GENERATED ALWAYS AS ((start_date + COALESCE(start_time, '00:00:00'::time without time zone))) STORED,
    event_end_at timestamp without time zone GENERATED ALWAYS AS (
CASE
    WHEN (end_date IS NULL) THEN NULL::timestamp without time zone
    ELSE (end_date + COALESCE(end_time, '23:59:00'::time without time zone))
END) STORED
);


ALTER TABLE uranus.event_date_projection OWNER TO oklab;

--
-- TOC entry 572 (class 1259 OID 2351555)
-- Name: event_filter; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.event_filter (
    uuid uuid NOT NULL,
    user_id integer,
    params text,
    slug text,
    name text,
    description text
);


ALTER TABLE uranus.event_filter OWNER TO oklab;

--
-- TOC entry 551 (class 1259 OID 2266475)
-- Name: event_id_seq; Type: SEQUENCE; Schema: uranus; Owner: oklab
--

CREATE SEQUENCE uranus.event_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE uranus.event_id_seq OWNER TO oklab;

--
-- TOC entry 574 (class 1259 OID 2351572)
-- Name: event_link; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.event_link (
    id integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    modified_at timestamp without time zone,
    event_uuid uuid NOT NULL,
    type text,
    label character varying(255),
    url text NOT NULL
);


ALTER TABLE uranus.event_link OWNER TO oklab;

--
-- TOC entry 573 (class 1259 OID 2351571)
-- Name: event_link_id_seq; Type: SEQUENCE; Schema: uranus; Owner: oklab
--

ALTER TABLE uranus.event_link ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME uranus.event_link_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 536 (class 1259 OID 2266018)
-- Name: event_occasion_type; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.event_occasion_type (
    id integer NOT NULL,
    type_id integer NOT NULL,
    iso_639_1 character varying(2) NOT NULL,
    name text NOT NULL
);


ALTER TABLE uranus.event_occasion_type OWNER TO oklab;

--
-- TOC entry 537 (class 1259 OID 2266023)
-- Name: event_occasion_type_id_seq; Type: SEQUENCE; Schema: uranus; Owner: oklab
--

ALTER TABLE uranus.event_occasion_type ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME uranus.event_occasion_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 577 (class 1259 OID 2351626)
-- Name: event_projection; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.event_projection (
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    modified_at timestamp without time zone,
    event_uuid uuid NOT NULL,
    external_id text,
    release_status uranus.event_release_status DEFAULT 'draft'::uranus.event_release_status NOT NULL,
    org_uuid uuid NOT NULL,
    venue_uuid uuid,
    space_uuid uuid,
    title text NOT NULL,
    subtitle text,
    description text,
    summary text,
    org_name text,
    org_contact_email text,
    org_contact_phone text,
    org_link text,
    venue_name text,
    venue_street text,
    venue_house_number text,
    venue_postal_code text,
    venue_city text,
    venue_country character(3),
    venue_state character varying(2),
    venue_point public.geometry(Point,4326),
    venue_link text,
    space_type text,
    space_name character varying(255),
    space_description text,
    space_building_level integer,
    space_total_capacity integer,
    space_seating_capacity integer,
    space_link text,
    space_accessibility_flags bigint,
    space_accessibility_summary text,
    occasion_type_id integer,
    categories integer[],
    types jsonb,
    tags text[],
    languages text[],
    source_link text,
    online_link text,
    max_attendees integer,
    min_age integer,
    max_age integer,
    participation_info text,
    meeting_point text,
    currency character varying(8),
    min_price double precision,
    max_price double precision,
    image_alt_text text,
    image_license_id integer,
    image_creator_name text,
    image_copyright text,
    image_description text,
    ticket_flags uranus.uranus_ticket_flag[] DEFAULT '{}'::uranus.uranus_ticket_flag[] NOT NULL,
    price_type uranus.uranus_price_type DEFAULT 'not_specified'::uranus.uranus_price_type NOT NULL,
    visitor_info_flags bigint,
    image_uuid uuid,
    search_text text,
    custom text,
    style text
);


ALTER TABLE uranus.event_projection OWNER TO oklab;

--
-- TOC entry 538 (class 1259 OID 2266024)
-- Name: event_release_status_i18n; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.event_release_status_i18n (
    iso_639_1 character varying(2) NOT NULL,
    name text NOT NULL,
    key text,
    "order" integer
);


ALTER TABLE uranus.event_release_status_i18n OWNER TO oklab;

--
-- TOC entry 552 (class 1259 OID 2283091)
-- Name: event_type; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.event_type (
    type_id integer NOT NULL,
    iso_639_1 character varying(2) NOT NULL,
    name text NOT NULL,
    schema_org_type text
);


ALTER TABLE uranus.event_type OWNER TO oklab;

--
-- TOC entry 598 (class 1259 OID 2351839)
-- Name: event_type_link; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.event_type_link (
    event_uuid uuid NOT NULL,
    type_id integer NOT NULL,
    genre_id integer DEFAULT 0 NOT NULL
);


ALTER TABLE uranus.event_type_link OWNER TO oklab;

--
-- TOC entry 539 (class 1259 OID 2266047)
-- Name: genre_type; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.genre_type (
    name text NOT NULL,
    genre_id integer NOT NULL,
    type_id integer,
    iso_639_1 character varying(2)
);


ALTER TABLE uranus.genre_type OWNER TO oklab;

--
-- TOC entry 540 (class 1259 OID 2266054)
-- Name: image_type; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.image_type (
    id integer NOT NULL,
    name character varying NOT NULL,
    description character varying,
    type_id integer NOT NULL,
    iso_639_1 character varying(2)
);


ALTER TABLE uranus.image_type OWNER TO oklab;

--
-- TOC entry 541 (class 1259 OID 2266059)
-- Name: image_type_id_seq; Type: SEQUENCE; Schema: uranus; Owner: oklab
--

ALTER TABLE uranus.image_type ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME uranus.image_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 542 (class 1259 OID 2266060)
-- Name: language; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.language (
    code_iso_639_1 character varying(2) NOT NULL,
    name text NOT NULL,
    name_iso_639_1 character varying(2) NOT NULL
);


ALTER TABLE uranus.language OWNER TO oklab;

--
-- TOC entry 561 (class 1259 OID 2317098)
-- Name: legal_form; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.legal_form (
    key text NOT NULL,
    schema_org text NOT NULL
);


ALTER TABLE uranus.legal_form OWNER TO oklab;

--
-- TOC entry 562 (class 1259 OID 2317105)
-- Name: legal_form_i18n; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.legal_form_i18n (
    key text NOT NULL,
    iso_639_1 character(2) NOT NULL,
    name text NOT NULL,
    description text
);


ALTER TABLE uranus.legal_form_i18n OWNER TO oklab;

--
-- TOC entry 563 (class 1259 OID 2317191)
-- Name: license; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.license (
    key text NOT NULL,
    spdx_id text,
    url text
);


ALTER TABLE uranus.license OWNER TO oklab;

--
-- TOC entry 564 (class 1259 OID 2317198)
-- Name: license_i18n; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.license_i18n (
    key text NOT NULL,
    iso_639_1 character(2) NOT NULL,
    name text NOT NULL,
    description text
);


ALTER TABLE uranus.license_i18n OWNER TO oklab;

--
-- TOC entry 558 (class 1259 OID 2317029)
-- Name: link_type; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.link_type (
    key text NOT NULL
);


ALTER TABLE uranus.link_type OWNER TO oklab;

--
-- TOC entry 559 (class 1259 OID 2317036)
-- Name: link_type_i18n; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.link_type_i18n (
    key text NOT NULL,
    iso_639_1 character(2) NOT NULL,
    name text NOT NULL,
    description text
);


ALTER TABLE uranus.link_type_i18n OWNER TO oklab;

--
-- TOC entry 579 (class 1259 OID 2351641)
-- Name: message; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.message (
    id integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamp without time zone,
    to_user_uuid integer NOT NULL,
    from_user_uuid integer NOT NULL,
    subject text NOT NULL,
    message text NOT NULL,
    is_read boolean DEFAULT false NOT NULL
);


ALTER TABLE uranus.message OWNER TO oklab;

--
-- TOC entry 578 (class 1259 OID 2351640)
-- Name: message_id_seq; Type: SEQUENCE; Schema: uranus; Owner: oklab
--

ALTER TABLE uranus.message ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME uranus.message_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 580 (class 1259 OID 2351659)
-- Name: organization; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.organization (
    uuid uuid NOT NULL,
    created_by uuid,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    modified_by uuid,
    modified_at timestamp without time zone,
    name text NOT NULL,
    description text,
    contact_email character varying(255),
    contact_phone character varying(50),
    web_link text,
    street character varying(255),
    house_number character varying(50),
    address_addition character varying,
    postal_code character varying(20),
    city character varying(100),
    country character varying(100),
    state character varying(2),
    holding_org_uuid uuid,
    legal_form text,
    nonprofit boolean,
    point public.geometry(Point,4326),
    api_import_token text,
    api_import_enabled boolean DEFAULT false
);


ALTER TABLE uranus.organization OWNER TO oklab;

--
-- TOC entry 581 (class 1259 OID 2351676)
-- Name: organization_member_link; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.organization_member_link (
    org_uuid uuid NOT NULL,
    user_uuid uuid NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    modified_at timestamp without time zone,
    invited_at timestamp without time zone,
    invited_by_user_uuid uuid,
    accept_token text,
    has_joined boolean DEFAULT false NOT NULL
);


ALTER TABLE uranus.organization_member_link OWNER TO oklab;

--
-- TOC entry 582 (class 1259 OID 2351687)
-- Name: password_reset; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.password_reset (
    user_uuid uuid NOT NULL,
    token text NOT NULL,
    expires_at timestamp without time zone NOT NULL,
    used boolean DEFAULT false NOT NULL
);


ALTER TABLE uranus.password_reset OWNER TO oklab;

--
-- TOC entry 543 (class 1259 OID 2266118)
-- Name: permission_bit; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.permission_bit (
    group_id text NOT NULL,
    name text NOT NULL,
    "bit" smallint NOT NULL,
    mask bigint NOT NULL
);


ALTER TABLE uranus.permission_bit OWNER TO oklab;

--
-- TOC entry 544 (class 1259 OID 2266123)
-- Name: permission_label; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.permission_label (
    group_id text NOT NULL,
    name text NOT NULL,
    iso_639_1 character(2) NOT NULL,
    label text NOT NULL,
    description text NOT NULL
);


ALTER TABLE uranus.permission_label OWNER TO oklab;

--
-- TOC entry 583 (class 1259 OID 2351695)
-- Name: pluto_cache; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.pluto_cache (
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    pluto_image_uuid uuid,
    mime_type text,
    receipt text
);


ALTER TABLE uranus.pluto_cache OWNER TO oklab;

--
-- TOC entry 584 (class 1259 OID 2351703)
-- Name: pluto_context_rules; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.pluto_context_rules (
    context text NOT NULL,
    identifier text NOT NULL,
    max_width integer,
    max_height integer,
    compression integer,
    max_file_size bigint
);


ALTER TABLE uranus.pluto_context_rules OWNER TO oklab;

--
-- TOC entry 585 (class 1259 OID 2351709)
-- Name: pluto_image; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.pluto_image (
    uuid uuid NOT NULL,
    created_by uuid,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamp without time zone,
    expiration_date date,
    file_name text NOT NULL,
    gen_file_name text,
    mime_type text,
    width integer,
    height integer,
    description text,
    alt_text text,
    exif jsonb,
    creator_name text,
    copyright text,
    license character varying(32),
    focus_x double precision,
    focus_y double precision
);


ALTER TABLE uranus.pluto_image OWNER TO oklab;

--
-- TOC entry 586 (class 1259 OID 2351717)
-- Name: pluto_image_link; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.pluto_image_link (
    pluto_image_uuid uuid,
    context text NOT NULL,
    context_uuid uuid NOT NULL,
    identifier text NOT NULL
);


ALTER TABLE uranus.pluto_image_link OWNER TO oklab;

--
-- TOC entry 545 (class 1259 OID 2266135)
-- Name: price_type; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.price_type (
    type_id integer NOT NULL,
    iso_639_1 character varying(2) NOT NULL,
    name text NOT NULL
);


ALTER TABLE uranus.price_type OWNER TO oklab;

--
-- TOC entry 587 (class 1259 OID 2351724)
-- Name: space; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.space (
    uuid uuid NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    modified_at timestamp without time zone,
    venue_uuid uuid,
    name text NOT NULL,
    description text,
    web_link text,
    space_type text,
    building_level integer,
    area_sqm numeric(8,2),
    total_capacity integer,
    seating_capacity integer,
    accessibility_flags bigint,
    accessibility_summary text
);


ALTER TABLE uranus.space OWNER TO oklab;

--
-- TOC entry 554 (class 1259 OID 2316967)
-- Name: space_feature; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.space_feature (
    category text NOT NULL,
    key text NOT NULL
);


ALTER TABLE uranus.space_feature OWNER TO oklab;

--
-- TOC entry 555 (class 1259 OID 2316993)
-- Name: space_feature_link; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.space_feature_link (
    space_id integer NOT NULL,
    key text NOT NULL
);


ALTER TABLE uranus.space_feature_link OWNER TO oklab;

--
-- TOC entry 556 (class 1259 OID 2317010)
-- Name: space_type; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.space_type (
    key text NOT NULL,
    schema_org text NOT NULL
);


ALTER TABLE uranus.space_type OWNER TO oklab;

--
-- TOC entry 557 (class 1259 OID 2317017)
-- Name: space_type_i18n; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.space_type_i18n (
    key text NOT NULL,
    iso_639_1 character(2) NOT NULL,
    name text NOT NULL,
    description text
);


ALTER TABLE uranus.space_type_i18n OWNER TO oklab;

--
-- TOC entry 546 (class 1259 OID 2266155)
-- Name: state; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.state (
    code character varying(2) NOT NULL,
    country character varying(3) NOT NULL,
    name text NOT NULL
);


ALTER TABLE uranus.state OWNER TO oklab;

--
-- TOC entry 547 (class 1259 OID 2266160)
-- Name: system_email_template; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.system_email_template (
    id integer NOT NULL,
    context text NOT NULL,
    iso_639_1 character varying(2) NOT NULL,
    template text NOT NULL,
    subject text
);


ALTER TABLE uranus.system_email_template OWNER TO oklab;

--
-- TOC entry 548 (class 1259 OID 2266165)
-- Name: system_email_template_id_seq; Type: SEQUENCE; Schema: uranus; Owner: oklab
--

ALTER TABLE uranus.system_email_template ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME uranus.system_email_template_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 549 (class 1259 OID 2266166)
-- Name: team_member_role; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.team_member_role (
    type_id integer NOT NULL,
    name text NOT NULL,
    iso_639_1 character varying(2) NOT NULL,
    description text
);


ALTER TABLE uranus.team_member_role OWNER TO oklab;

--
-- TOC entry 596 (class 1259 OID 2351814)
-- Name: todo; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.todo (
    id integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    modified_at timestamp without time zone,
    user_uuid uuid NOT NULL,
    title text NOT NULL,
    description text,
    due_date date,
    completed boolean DEFAULT false NOT NULL,
    importance text
);


ALTER TABLE uranus.todo OWNER TO oklab;

--
-- TOC entry 595 (class 1259 OID 2351813)
-- Name: todo_id_seq; Type: SEQUENCE; Schema: uranus; Owner: oklab
--

ALTER TABLE uranus.todo ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME uranus.todo_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 588 (class 1259 OID 2351740)
-- Name: transport_station; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.transport_station (
    uuid uuid NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    modified_at timestamp without time zone,
    name character varying(255) NOT NULL,
    city text,
    country character varying(3),
    point public.geometry(Point,4326),
    gtfs_station_code text,
    gtfs_location_type integer,
    gtfs_parent_station text,
    gtfs_wheelchair_boarding integer,
    gtfs_zone_id text,
    type character varying(20)
);


ALTER TABLE uranus.transport_station OWNER TO oklab;

--
-- TOC entry 589 (class 1259 OID 2351751)
-- Name: user; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus."user" (
    uuid uuid NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    modified_at timestamp without time zone,
    email character varying NOT NULL,
    password_hash text NOT NULL,
    is_active boolean DEFAULT false NOT NULL,
    username text,
    display_name character varying,
    first_name character varying,
    last_name character varying,
    locale character varying(2),
    theme character varying,
    activate_token text
);


ALTER TABLE uranus."user" OWNER TO oklab;

--
-- TOC entry 590 (class 1259 OID 2351764)
-- Name: user_event_link; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.user_event_link (
    user_uuid uuid NOT NULL,
    event_uuid uuid NOT NULL,
    permissions bigint DEFAULT '0'::bigint NOT NULL
);


ALTER TABLE uranus.user_event_link OWNER TO oklab;

--
-- TOC entry 591 (class 1259 OID 2351768)
-- Name: user_organization_link; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.user_organization_link (
    user_uuid uuid NOT NULL,
    org_uuid uuid NOT NULL,
    permissions bigint DEFAULT '0'::bigint NOT NULL
);


ALTER TABLE uranus.user_organization_link OWNER TO oklab;

--
-- TOC entry 593 (class 1259 OID 2351776)
-- Name: user_space_link; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.user_space_link (
    user_uuid uuid NOT NULL,
    space_uuid uuid NOT NULL,
    permissions bigint DEFAULT '0'::bigint NOT NULL
);


ALTER TABLE uranus.user_space_link OWNER TO oklab;

--
-- TOC entry 592 (class 1259 OID 2351772)
-- Name: user_venue_link; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.user_venue_link (
    user_uuid uuid NOT NULL,
    venue_uuid uuid NOT NULL,
    permissions bigint DEFAULT '0'::bigint NOT NULL
);


ALTER TABLE uranus.user_venue_link OWNER TO oklab;

--
-- TOC entry 594 (class 1259 OID 2351780)
-- Name: venue; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.venue (
    uuid uuid NOT NULL,
    created_by uuid,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    modified_by uuid,
    modified_at timestamp without time zone,
    org_uuid uuid NOT NULL,
    type text,
    name character varying(255) NOT NULL,
    description text,
    summary text,
    contact_email character varying,
    contact_phone character varying,
    web_link text,
    street character varying(255),
    house_number character varying(50),
    postal_code character varying(20),
    city character varying(100),
    country character(3),
    state character varying(2),
    point public.geometry(Point,4326),
    opened_at date,
    closed_at date,
    ticket_info text,
    ticket_link text,
    opening_hours text,
    accessibility_flags bigint,
    accessibility_summary text,
    CONSTRAINT venue_country_check CHECK ((char_length((country)::text) = 3))
);


ALTER TABLE uranus.venue OWNER TO oklab;

--
-- TOC entry 560 (class 1259 OID 2317087)
-- Name: venue_type; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.venue_type (
    key text NOT NULL,
    schema_org text NOT NULL
);


ALTER TABLE uranus.venue_type OWNER TO oklab;

--
-- TOC entry 553 (class 1259 OID 2283098)
-- Name: venue_type_i18n; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.venue_type_i18n (
    key text NOT NULL,
    iso_639_1 character(2) NOT NULL,
    name text NOT NULL,
    description text
);


ALTER TABLE uranus.venue_type_i18n OWNER TO oklab;

--
-- TOC entry 550 (class 1259 OID 2266245)
-- Name: visitor_information_flag; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.visitor_information_flag (
    flag integer,
    iso_639_1 character varying(2),
    name character varying(255),
    topic_id integer,
    key text
);


ALTER TABLE uranus.visitor_information_flag OWNER TO oklab;

--
-- TOC entry 565 (class 1259 OID 2325409)
-- Name: visitor_information_topic; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.visitor_information_topic (
    topic_id integer NOT NULL,
    iso_639_1 character varying(2),
    name text,
    key text
);


ALTER TABLE uranus.visitor_information_topic OWNER TO oklab;

--
-- TOC entry 571 (class 1259 OID 2351186)
-- Name: wkb_polygon; Type: TABLE; Schema: uranus; Owner: oklab
--

CREATE TABLE uranus.wkb_polygon (
    id integer NOT NULL,
    context text NOT NULL,
    context_id integer NOT NULL,
    geometry public.geometry(Polygon,4326),
    name text,
    description text,
    key text
);


ALTER TABLE uranus.wkb_polygon OWNER TO oklab;

--
-- TOC entry 570 (class 1259 OID 2351185)
-- Name: wkb_poly_id_seq; Type: SEQUENCE; Schema: uranus; Owner: oklab
--

ALTER TABLE uranus.wkb_polygon ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME uranus.wkb_poly_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 5793 (class 0 OID 2265944)
-- Dependencies: 532
-- Data for Name: accessibility_flag; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.accessibility_flag (flag, iso_639_1, name, topic_id, key) FROM stdin;
7	de	Assistenzhunde Erlaubt	2	service_animals_allowed
7	da	Servicehunde tilladt	2	service_animals_allowed
7	en	Service Animals Allowed	2	service_animals_allowed
38	da	Lavt lysmiljø	5	low_light_environment
38	en	Low Light Environment	5	low_light_environment
38	de	Dämmerumgebung	5	low_light_environment
36	de	Klare Beschilderung	5	clear_signage
36	da	Klar skiltning	5	clear_signage
36	en	Clear Signage	5	clear_signage
17	de	Hilfshörgeräte	3	assistive_listening_devices
17	da	Hjælpemidler til lytning	3	assistive_listening_devices
17	en	Assistive Listening Devices	3	assistive_listening_devices
25	de	Braille Materialien	4	braille_materials
25	da	Braille-materialer	4	braille_materials
25	en	Braille Materials	4	braille_materials
15	de	Untertitel Verfügbar	3	captioning_available
15	da	Undertekster tilgængelige	3	captioning_available
15	en	Captioning Available	3	captioning_available
2	de	Aufzug Verfügbar	1	elevator_available
2	da	Elevator tilgængelig	1	elevator_available
2	en	Elevator Available	1	elevator_available
45	de	Unterstützung für Bildschirmleser	6	screen_reader_support
45	da	Skærmlæser support	6	screen_reader_support
45	en	Screen Reader Support	6	screen_reader_support
26	de	Hochkontrastbeschilderung	4	high_contrast_signage
26	da	Højkontrast skilte	4	high_contrast_signage
26	en	High Contrast Signage	4	high_contrast_signage
37	de	Ausgebildetes Personal	5	trained_staff
37	da	Trænet personale	5	trained_staff
37	en	Trained Staff	5	trained_staff
44	de	Barrierefreie Webseite	6	accessible_website
44	da	Tilgængelig hjemmeside	6	accessible_website
44	en	Accessible Website	6	accessible_website
16	de	Hörschleife	3	hearing_loop
16	da	Høreloop	3	hearing_loop
16	en	Hearing Loop	3	hearing_loop
35	de	Ruhiger Raum	5	quiet_space
35	da	Stille område	5	quiet_space
35	en	Quiet Space	5	quiet_space
6	de	Reservierte Sitzplätze	1	reserved_seating
6	da	Reserveret siddeplads	1	reserved_seating
6	en	Reserved Seating	1	reserved_seating
46	de	Tastaturnavigation	6	keyboard_navigation
46	da	Tastaturnavigation	6	keyboard_navigation
46	en	Keyboard Navigation	6	keyboard_navigation
24	de	Audio Beschreibung	3	audio_description
24	da	Audiobeskrivelse	3	audio_description
24	en	Audio Description	3	audio_description
3	de	Rampe Verfügbar	1	ramp_available
3	da	Rampe tilgængelig	1	ramp_available
3	en	Ramp Available	1	ramp_available
1	de	Barrierefreier Parkplatz	1	accessible_parking
1	da	Handicapparkering	1	accessible_parking
1	en	Accessible Parking	1	accessible_parking
34	da	Letlæselige materialer	5	easy_read_materials
34	en	Easy Read Materials	5	easy_read_materials
34	de	Leicht lesbare Materialien	5	easy_read_materials
47	de	Sprachsteuerung Unterstützung	6	voice_command_support
47	da	Stemmekommando support	6	voice_command_support
47	en	Voice Command Support	6	voice_command_support
0	de	Rollstuhlgerecht	1	wheelchair_accessible
0	da	Kørestolsadgang	1	wheelchair_accessible
0	en	Wheelchair Accessible	1	wheelchair_accessible
5	de	Barrierefreies WC	1	accessible_restroom
5	da	Handicapvenligt toilet	1	accessible_restroom
5	en	Accessible Restroom	1	accessible_restroom
14	de	Gebärdensprachdolmetschen	3	sign_language_interpretation
14	da	Tegnsprogstolkning	3	sign_language_interpretation
14	en	Sign Language Interpretation	3	sign_language_interpretation
4	de	Stufenfreier Zugang	1	step_free_access
4	da	Trinfri adgang	1	step_free_access
4	en	Step-Free Access	1	step_free_access
27	de	Taktilführer	4	tactile_guides
27	da	Taktil guider	4	tactile_guides
27	en	Tactile Guides	4	tactile_guides
\.


--
-- TOC entry 5827 (class 0 OID 2325418)
-- Dependencies: 566
-- Data for Name: accessibility_topic; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.accessibility_topic (topic_id, iso_639_1, name, key) FROM stdin;
1	de	Physische Barrierefreiheit	physical_accessibility
1	da	Fysisk tilgængelighed	physical_accessibility
1	en	Physical Accessibility	physical_accessibility
2	de	Assistenztiere	assistance_animals
2	da	Service- og hjælpedyr	assistance_animals
2	en	Assistance Animals	assistance_animals
3	de	Hörbarrierefreiheit	hearing_accessibility
3	da	Høretilgængelighed	hearing_accessibility
3	en	Hearing Accessibility	hearing_accessibility
4	de	Visuelle Barrierefreiheit	visual_accessibility
4	da	Visuel tilgængelighed	visual_accessibility
4	en	Visual Accessibility	visual_accessibility
6	de	Digitale Barrierefreiheit	digital_accessibility
6	da	Digital tilgængelighed	digital_accessibility
6	en	Digital Accessibility	digital_accessibility
5	en	Cognitive Accessibility	cognitive_accessibility
5	de	Kognitive Barrierefreiheit	cognitive_accessibility
5	da	Kognitiv tilgængelighed	cognitive_accessibility
\.


--
-- TOC entry 5794 (class 0 OID 2265962)
-- Dependencies: 533
-- Data for Name: country; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.country (code, name, iso_639_1) FROM stdin;
ABW	Aruba	en
ABW	Aruba	de
ABW	Aruba	da
AFG	Afghanistan	en
AFG	Afghanistan	de
AFG	Afghanistan	da
AGO	Angola	en
AGO	Angola	de
AGO	Angola	da
AIA	Anguilla	en
AIA	Anguilla	de
AIA	Anguilla	da
ALA	Åland Islands	en
ALA	Ålandinseln	de
ALA	Åland	da
ALB	Albania	en
ALB	Albanien	de
ALB	Albanien	da
AND	Andorra	en
AND	Andorra	de
AND	Andorra	da
ARE	United Arab Emirates	en
ARE	Vereinigte Arabische Emirate	de
ARE	De Forenede Arabiske Emirater	da
ARG	Argentina	en
ARG	Argentinien	de
ARG	Argentina	da
ARM	Armenia	en
ARM	Armenien	de
ARM	Armenien	da
ASM	American Samoa	en
ASM	Amerikanisch-Samoa	de
ASM	Amerikansk Samoa	da
ATA	Antarctica	en
ATA	Antarktis	de
ATA	Antarktis	da
ATF	French Southern Territories	en
ATF	Französische Süd- und Antarktisgebiete	de
ATF	De Franske Besiddelser i Det Sydlige Indiske Ocean og Antarktis	da
ATG	Antigua and Barbuda	en
ATG	Antigua und Barbuda	de
ATG	Antigua og Barbuda	da
AUS	Australia	en
AUS	Australien	de
AUS	Australien	da
AUT	Austria	en
AUT	Österreich	de
AUT	Østrig	da
AZE	Azerbaijan	en
AZE	Aserbaidschan	de
AZE	Aserbajdsjan	da
BDI	Burundi	en
BDI	Burundi	de
BDI	Burundi	da
BEL	Belgium	en
BEL	Belgien	de
BEL	Belgien	da
BEN	Benin	en
BEN	Benin	de
BEN	Benin	da
BES	Bonaire, Sint Eustatius and Saba	en
BES	Karibische Niederlande	de
BES	De tidligere Nederlandske Antiller	da
BFA	Burkina Faso	en
BFA	Burkina Faso	de
BFA	Burkina Faso	da
BGD	Bangladesh	en
BGD	Bangladesch	de
BGD	Bangladesh	da
BGR	Bulgaria	en
BGR	Bulgarien	de
BGR	Bulgarien	da
BHR	Bahrain	en
BHR	Bahrain	de
BHR	Bahrain	da
BHS	Bahamas	en
BHS	Bahamas	de
BHS	Bahamas	da
BIH	Bosnia and Herzegovina	en
BIH	Bosnien und Herzegowina	de
BIH	Bosnien-Hercegovina	da
BLM	Saint Barthélemy	en
BLM	St. Barthélemy	de
BLM	Saint Barthélemy	da
BLR	Belarus	en
BLR	Belarus	de
BLR	Belarus	da
BLZ	Belize	en
BLZ	Belize	de
BLZ	Belize	da
BMU	Bermuda	en
BMU	Bermuda	de
BMU	Bermuda	da
BOL	Bolivia, Plurinational State of	en
BOL	Bolivien	de
BOL	Bolivia	da
BRA	Brazil	en
BRA	Brasilien	de
BRA	Brasilien	da
BRB	Barbados	en
BRB	Barbados	de
BRB	Barbados	da
BRN	Brunei Darussalam	en
BRN	Brunei Darussalam	de
BRN	Brunei	da
BTN	Bhutan	en
BTN	Bhutan	de
BTN	Bhutan	da
BVT	Bouvet Island	en
BVT	Bouvetinsel	de
BVT	Bouvetøen	da
BWA	Botswana	en
BWA	Botsuana	de
BWA	Botswana	da
CAF	Central African Republic	en
CAF	Zentralafrikanische Republik	de
CAF	Den Centralafrikanske Republik	da
CAN	Canada	en
CAN	Kanada	de
CAN	Canada	da
CCK	Cocos (Keeling) Islands	en
CCK	Kokosinseln	de
CCK	Cocosøerne	da
CHE	Switzerland	en
CHE	Schweiz	de
CHE	Schweiz	da
CHL	Chile	en
CHL	Chile	de
CHL	Chile	da
CHN	China	en
CHN	China	de
CHN	Kina	da
CIV	Côte d'Ivoire	en
CIV	Côte d’Ivoire	de
CIV	Elfenbenskysten	da
CMR	Cameroon	en
CMR	Kamerun	de
CMR	Cameroun	da
COD	Congo, The Democratic Republic of the	en
COD	Kongo-Kinshasa	de
COD	Congo-Kinshasa	da
COG	Congo	en
COG	Kongo-Brazzaville	de
COG	Congo-Brazzaville	da
COK	Cook Islands	en
COK	Cookinseln	de
COK	Cookøerne	da
COL	Colombia	en
COL	Kolumbien	de
COL	Colombia	da
COM	Comoros	en
COM	Komoren	de
COM	Comorerne	da
CPV	Cabo Verde	en
CPV	Cabo Verde	de
CPV	Kap Verde	da
CRI	Costa Rica	en
CRI	Costa Rica	de
CRI	Costa Rica	da
CUB	Cuba	en
CUB	Kuba	de
CUB	Cuba	da
CUW	Curaçao	en
CUW	Curaçao	de
CUW	Curaçao	da
CXR	Christmas Island	en
CXR	Weihnachtsinsel	de
CXR	Juleøen	da
CYM	Cayman Islands	en
CYM	Kaimaninseln	de
CYM	Caymanøerne	da
CYP	Cyprus	en
CYP	Zypern	de
CYP	Cypern	da
CZE	Czechia	en
CZE	Tschechien	de
CZE	Tjekkiet	da
DEU	Germany	en
DEU	Deutschland	de
DEU	Tyskland	da
DJI	Djibouti	en
DJI	Dschibuti	de
DJI	Djibouti	da
DMA	Dominica	en
DMA	Dominica	de
DMA	Dominica	da
DNK	Denmark	en
DNK	Dänemark	de
DNK	Danmark	da
DOM	Dominican Republic	en
DOM	Dominikanische Republik	de
DOM	Den Dominikanske Republik	da
DZA	Algeria	en
DZA	Algerien	de
DZA	Algeriet	da
ECU	Ecuador	en
ECU	Ecuador	de
ECU	Ecuador	da
EGY	Egypt	en
EGY	Ägypten	de
EGY	Egypten	da
ERI	Eritrea	en
ERI	Eritrea	de
ERI	Eritrea	da
ESH	Western Sahara	en
ESH	Westsahara	de
ESH	Vestsahara	da
ESP	Spain	en
ESP	Spanien	de
ESP	Spanien	da
EST	Estonia	en
EST	Estland	de
EST	Estland	da
ETH	Ethiopia	en
ETH	Äthiopien	de
ETH	Etiopien	da
FIN	Finland	en
FIN	Finnland	de
FIN	Finland	da
FJI	Fiji	en
FJI	Fidschi	de
FJI	Fiji	da
FLK	Falkland Islands (Malvinas)	en
FLK	Falklandinseln	de
FLK	Falklandsøerne	da
FRA	France	en
FRA	Frankreich	de
FRA	Frankrig	da
FRO	Faroe Islands	en
FRO	Färöer	de
FRO	Færøerne	da
FSM	Micronesia, Federated States of	en
FSM	Mikronesien	de
FSM	Mikronesien	da
GAB	Gabon	en
GAB	Gabun	de
GAB	Gabon	da
GBR	United Kingdom	en
GBR	Vereinigtes Königreich	de
GBR	Storbritannien	da
GEO	Georgia	en
GEO	Georgien	de
GEO	Georgien	da
GGY	Guernsey	en
GGY	Guernsey	de
GGY	Guernsey	da
GHA	Ghana	en
GHA	Ghana	de
GHA	Ghana	da
GIB	Gibraltar	en
GIB	Gibraltar	de
GIB	Gibraltar	da
GIN	Guinea	en
GIN	Guinea	de
GIN	Guinea	da
GLP	Guadeloupe	en
GLP	Guadeloupe	de
GLP	Guadeloupe	da
GMB	Gambia	en
GMB	Gambia	de
GMB	Gambia	da
GNB	Guinea-Bissau	en
GNB	Guinea-Bissau	de
GNB	Guinea-Bissau	da
GNQ	Equatorial Guinea	en
GNQ	Äquatorialguinea	de
GNQ	Ækvatorialguinea	da
GRC	Greece	en
GRC	Griechenland	de
GRC	Grækenland	da
GRD	Grenada	en
GRD	Grenada	de
GRD	Grenada	da
GRL	Greenland	en
GRL	Grönland	de
GRL	Grønland	da
GTM	Guatemala	en
GTM	Guatemala	de
GTM	Guatemala	da
GUF	French Guiana	en
GUF	Französisch-Guayana	de
GUF	Fransk Guyana	da
GUM	Guam	en
GUM	Guam	de
GUM	Guam	da
GUY	Guyana	en
GUY	Guyana	de
GUY	Guyana	da
HKG	Hong Kong	en
HKG	Sonderverwaltungsregion Hongkong	de
HKG	SAR Hongkong	da
HMD	Heard Island and McDonald Islands	en
HMD	Heard und McDonaldinseln	de
HMD	Heard Island og McDonald Islands	da
HND	Honduras	en
HND	Honduras	de
HND	Honduras	da
HRV	Croatia	en
HRV	Kroatien	de
HRV	Kroatien	da
HTI	Haiti	en
HTI	Haiti	de
HTI	Haiti	da
HUN	Hungary	en
HUN	Ungarn	de
HUN	Ungarn	da
IDN	Indonesia	en
IDN	Indonesien	de
IDN	Indonesien	da
IMN	Isle of Man	en
IMN	Isle of Man	de
IMN	Isle of Man	da
IND	India	en
IND	Indien	de
IND	Indien	da
IOT	British Indian Ocean Territory	en
IOT	Britisches Territorium im Indischen Ozean	de
IOT	Det Britiske Territorium i Det Indiske Ocean	da
IRL	Ireland	en
IRL	Irland	de
IRL	Irland	da
IRN	Iran, Islamic Republic of	en
IRN	Iran	de
IRN	Iran	da
IRQ	Iraq	en
IRQ	Irak	de
IRQ	Irak	da
ISL	Iceland	en
ISL	Island	de
ISL	Island	da
ISR	Israel	en
ISR	Israel	de
ISR	Israel	da
ITA	Italy	en
ITA	Italien	de
ITA	Italien	da
JAM	Jamaica	en
JAM	Jamaika	de
JAM	Jamaica	da
JEY	Jersey	en
JEY	Jersey	de
JEY	Jersey	da
JOR	Jordan	en
JOR	Jordanien	de
JOR	Jordan	da
JPN	Japan	en
JPN	Japan	de
JPN	Japan	da
KAZ	Kazakhstan	en
KAZ	Kasachstan	de
KAZ	Kasakhstan	da
KEN	Kenya	en
KEN	Kenia	de
KEN	Kenya	da
KGZ	Kyrgyzstan	en
KGZ	Kirgisistan	de
KGZ	Kirgisistan	da
KHM	Cambodia	en
KHM	Kambodscha	de
KHM	Cambodja	da
KIR	Kiribati	en
KIR	Kiribati	de
KIR	Kiribati	da
KNA	Saint Kitts and Nevis	en
KNA	St. Kitts und Nevis	de
KNA	Saint Kitts og Nevis	da
KOR	Korea, Republic of	en
KOR	Südkorea	de
KOR	Sydkorea	da
KWT	Kuwait	en
KWT	Kuwait	de
KWT	Kuwait	da
LAO	Lao People's Democratic Republic	en
LAO	Laos	de
LAO	Laos	da
LBN	Lebanon	en
LBN	Libanon	de
LBN	Libanon	da
LBR	Liberia	en
LBR	Liberia	de
LBR	Liberia	da
LBY	Libya	en
LBY	Libyen	de
LBY	Libyen	da
LCA	Saint Lucia	en
LCA	St. Lucia	de
LCA	Saint Lucia	da
LIE	Liechtenstein	en
LIE	Liechtenstein	de
LIE	Liechtenstein	da
LKA	Sri Lanka	en
LKA	Sri Lanka	de
LKA	Sri Lanka	da
LSO	Lesotho	en
LSO	Lesotho	de
LSO	Lesotho	da
LTU	Lithuania	en
LTU	Litauen	de
LTU	Litauen	da
LUX	Luxembourg	en
LUX	Luxemburg	de
LUX	Luxembourg	da
LVA	Latvia	en
LVA	Lettland	de
LVA	Letland	da
MAC	Macao	en
MAC	Sonderverwaltungsregion Macau	de
MAC	SAR Macao	da
MAF	Saint Martin (French part)	en
MAF	St. Martin	de
MAF	Saint Martin	da
MAR	Morocco	en
MAR	Marokko	de
MAR	Marokko	da
MCO	Monaco	en
MCO	Monaco	de
MCO	Monaco	da
MDA	Moldova, Republic of	en
MDA	Republik Moldau	de
MDA	Moldova	da
MDG	Madagascar	en
MDG	Madagaskar	de
MDG	Madagaskar	da
MDV	Maldives	en
MDV	Malediven	de
MDV	Maldiverne	da
MEX	Mexico	en
MEX	Mexiko	de
MEX	Mexico	da
MHL	Marshall Islands	en
MHL	Marshallinseln	de
MHL	Marshalløerne	da
MKD	North Macedonia	en
MKD	Nordmazedonien	de
MKD	Nordmakedonien	da
MLI	Mali	en
MLI	Mali	de
MLI	Mali	da
MLT	Malta	en
MLT	Malta	de
MLT	Malta	da
MMR	Myanmar	en
MMR	Myanmar	de
MMR	Myanmar (Burma)	da
MNE	Montenegro	en
MNE	Montenegro	de
MNE	Montenegro	da
MNG	Mongolia	en
MNG	Mongolei	de
MNG	Mongoliet	da
MNP	Northern Mariana Islands	en
MNP	Nördliche Marianen	de
MNP	Nordmarianerne	da
MOZ	Mozambique	en
MOZ	Mosambik	de
MOZ	Mozambique	da
MRT	Mauritania	en
MRT	Mauretanien	de
MRT	Mauretanien	da
MSR	Montserrat	en
MSR	Montserrat	de
MSR	Montserrat	da
MTQ	Martinique	en
MTQ	Martinique	de
MTQ	Martinique	da
MUS	Mauritius	en
MUS	Mauritius	de
MUS	Mauritius	da
MWI	Malawi	en
MWI	Malawi	de
MWI	Malawi	da
MYS	Malaysia	en
MYS	Malaysia	de
MYS	Malaysia	da
MYT	Mayotte	en
MYT	Mayotte	de
MYT	Mayotte	da
NAM	Namibia	en
NAM	Namibia	de
NAM	Namibia	da
NCL	New Caledonia	en
NCL	Neukaledonien	de
NCL	Ny Kaledonien	da
NER	Niger	en
NER	Niger	de
NER	Niger	da
NFK	Norfolk Island	en
NFK	Norfolkinsel	de
NFK	Norfolk Island	da
NGA	Nigeria	en
NGA	Nigeria	de
NGA	Nigeria	da
NIC	Nicaragua	en
NIC	Nicaragua	de
NIC	Nicaragua	da
NIU	Niue	en
NIU	Niue	de
NIU	Niue	da
NLD	Netherlands	en
NPL	Nepal	en
NPL	Nepal	da
NRU	Nauru	da
NZL	Neuseeland	de
OMN	Oman	de
OMN	Oman	da
PAK	Pakistan	en
PAN	Panama	en
PCN	Pitcairninseln	de
PER	Peru	en
PHL	Philippines	en
PLW	Palau	en
PLW	Palau	de
PNG	Papua-Neuguinea	de
PNG	Papua Ny Guinea	da
POL	Polen	da
PRI	Puerto Rico	en
PRI	Puerto Rico	de
PRK	Korea, Democratic People's Republic of	en
PRK	Nordkorea	de
PRT	Portugal	en
PRT	Portugal	de
PRY	Paraguay	en
PRY	Paraguay	de
PRY	Paraguay	da
PSE	De palæstinensiske områder	da
PYF	Französisch-Polynesien	de
QAT	Katar	de
REU	Réunion	de
REU	Réunion	da
ROU	Romania	en
RUS	Russland	de
RWA	Rwanda	en
SAU	Saudi-Arabien	de
SDN	Sudan	de
SGS	South Georgia and the South Sandwich Islands	en
SGS	Südgeorgien und die Südlichen Sandwichinseln	de
SGS	South Georgia og De Sydlige Sandwichøer	da
SHN	Saint Helena, Ascension and Tristan da Cunha	en
SHN	St. Helena	de
SHN	St. Helena	da
SLE	Sierra Leone	da
SMR	San Marino	en
SMR	San Marino	da
SOM	Somalia	da
SPM	St. Pierre und Miquelon	de
SPM	Saint Pierre og Miquelon	da
STP	São Tomé og Príncipe	da
SUR	Suriname	en
SUR	Suriname	de
SUR	Surinam	da
SVK	Slowakei	de
SVN	Slovenia	en
SVN	Slowenien	de
SVN	Slovenien	da
SWE	Schweden	de
SWZ	Eswatini	en
SWZ	Eswatini	da
SXM	Sint Maarten (Dutch part)	en
SXM	Sint Maarten	de
SXM	Sint Maarten	da
SYC	Seychelles	en
SYR	Syrien	da
TCA	Turks and Caicos Islands	en
TCA	Turks- og Caicosøerne	da
TCD	Tchad	da
TGO	Togo	en
THA	Thailand	en
TJK	Tadschikistan	de
TKM	Turkmenistan	en
TKM	Turkmenistan	de
TLS	Timor-Leste	en
TLS	Timor-Leste	de
TLS	Timor-Leste	da
TUN	Tunisia	en
UKR	Ukraine	en
UKR	Ukraine	de
UZB	Usbekistan	da
VAT	Vatikanstaten	da
VCT	Saint Vincent og Grenadinerne	da
VEN	Venezuela	da
VGB	Virgin Islands, British	en
VGB	De Britiske Jomfruøer	da
VIR	Virgin Islands, U.S.	en
VNM	Viet Nam	en
VNM	Vietnam	de
VUT	Vanuatu	en
VUT	Vanuatu	da
WLF	Wallis and Futuna	en
WSM	Samoa	en
WSM	Samoa	da
ZAF	South Africa	en
ZAF	Südafrika	de
NOR	Norway	en
NOR	Norwegen	de
NOR	Norge	da
NZL	New Zealand	da
OMN	Oman	en
PAK	Pakistan	da
PAN	Panama	de
PAN	Panama	da
PCN	Pitcairn	en
PER	Peru	de
PHL	Philippinen	de
PHL	Filippinerne	da
PLW	Palau	da
PNG	Papua New Guinea	en
POL	Poland	en
PRT	Portugal	da
PSE	Palestine, State of	en
PSE	Palästinensische Autonomiegebiete	de
PYF	French Polynesia	en
RUS	Rusland	da
RWA	Ruanda	de
SAU	Saudi-Arabien	da
SDN	Sudan	en
SEN	Senegal	de
SEN	Senegal	da
SGP	Singapore	da
SJM	Svalbard and Jan Mayen	en
SJM	Spitzbergen und Jan Mayen	de
SJM	Svalbard og Jan Mayen	da
SLB	Solomon Islands	en
SLB	Salomonen	de
SLE	Sierra Leone	en
SLE	Sierra Leone	de
SLV	El Salvador	de
SLV	El Salvador	da
SMR	San Marino	de
SOM	Somalia	en
SRB	Serbia	en
SSD	South Sudan	en
SSD	Sydsudan	da
SVK	Slovakia	en
SVK	Slovakiet	da
SWE	Sverige	da
SYC	Seychellen	de
SYR	Syrien	de
TCA	Turks- und Caicosinseln	de
THA	Thailand	de
THA	Thailand	da
TJK	Tadsjikistan	da
TKL	Tokelau	en
TKL	Tokelau	de
TKL	Tokelau	da
TTO	Trinidad og Tobago	da
TUN	Tunesien	da
TUV	Tuvalu	en
TUV	Tuvalu	da
TWN	Taiwan	da
TZA	Tanzania, United Republic of	en
UGA	Uganda	en
UGA	Uganda	de
UMI	United States Minor Outlying Islands	en
UMI	Amerikanische Überseeinseln	de
UMI	Amerikanske oversøiske øer	da
URY	Uruguay	en
URY	Uruguay	da
USA	United States	en
USA	USA	da
UZB	Uzbekistan	en
VAT	Holy See (Vatican City State)	en
VCT	Saint Vincent and the Grenadines	en
VEN	Venezuela, Bolivarian Republic of	en
VEN	Venezuela	de
VGB	Britische Jungferninseln	de
VUT	Vanuatu	de
WLF	Wallis und Futuna	de
WLF	Wallis og Futuna	da
YEM	Yemen	en
YEM	Jemen	de
YEM	Yemen	da
ZAF	Sydafrika	da
ZMB	Zambia	da
ZWE	Zimbabwe	en
NLD	Niederlande	de
NLD	Nederlandene	da
NPL	Nepal	de
NRU	Nauru	en
NRU	Nauru	de
NZL	New Zealand	en
PAK	Pakistan	de
PCN	Pitcairn	da
PER	Peru	da
POL	Polen	de
PRI	Puerto Rico	da
PRK	Nordkorea	da
PYF	Fransk Polynesien	da
QAT	Qatar	en
QAT	Qatar	da
REU	Réunion	en
ROU	Rumänien	de
ROU	Rumænien	da
RUS	Russian Federation	en
RWA	Rwanda	da
SAU	Saudi Arabia	en
SDN	Sudan	da
SEN	Senegal	en
SGP	Singapore	en
SGP	Singapur	de
SLB	Salomonøerne	da
SLV	El Salvador	en
SOM	Somalia	de
SPM	Saint Pierre and Miquelon	en
SRB	Serbien	de
SRB	Serbien	da
SSD	Südsudan	de
STP	Sao Tome and Principe	en
STP	São Tomé und Príncipe	de
SWE	Sweden	en
SWZ	Eswatini	de
SYC	Seychellerne	da
SYR	Syrian Arab Republic	en
TCD	Chad	en
TCD	Tschad	de
TGO	Togo	de
TGO	Togo	da
TJK	Tajikistan	en
TKM	Turkmenistan	da
TON	Tonga	en
TON	Tonga	de
TON	Tonga	da
TTO	Trinidad and Tobago	en
TTO	Trinidad und Tobago	de
TUN	Tunesien	de
TUR	Turkey	en
TUR	Türkei	de
TUR	Tyrkiet	da
TUV	Tuvalu	de
TWN	Taiwan, Province of China	en
TWN	Taiwan	de
TZA	Tansania	de
TZA	Tanzania	da
UGA	Uganda	da
UKR	Ukraine	da
URY	Uruguay	de
USA	Vereinigte Staaten	de
UZB	Usbekistan	de
VAT	Vatikanstadt	de
VCT	St. Vincent und die Grenadinen	de
VIR	Amerikanische Jungferninseln	de
VIR	De Amerikanske Jomfruøer	da
VNM	Vietnam	da
WSM	Samoa	de
ZMB	Zambia	en
ZMB	Sambia	de
ZWE	Simbabwe	de
ZWE	Zimbabwe	da
\.


--
-- TOC entry 5795 (class 0 OID 2265967)
-- Dependencies: 534
-- Data for Name: currency; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.currency (id, code, iso_639_1, name) FROM stdin;
1	EUR	da	Euro
2	EUR	de	Euro
3	EUR	en	Euro
4	DKK	da	Danske kroner
5	DKK	de	Dänische Krone
6	DKK	en	Danish Krone
7	GBP	da	Britiske pund
8	GBP	de	Britisches Pfund
9	GBP	en	British Pound
10	CHF	da	Schweizerfranc
11	CHF	de	Schweizer Franken
12	CHF	en	Swiss Franc
13	NOK	da	Norske kroner
14	NOK	de	Norwegische Krone
15	NOK	en	Norwegian Krone
16	SEK	da	Svenske kroner
17	SEK	de	Schwedische Krone
18	SEK	en	Swedish Krona
19	USD	da	US Dollar
20	USD	de	US-Dollar
21	USD	en	US Dollar
22	CAD	da	Canadiske dollar
23	CAD	de	Kanadischer Dollar
24	CAD	en	Canadian Dollar
25	JPY	da	Japanske yen
26	JPY	de	Japanischer Yen
27	JPY	en	Japanese Yen
28	CNY	da	Kinesiske yuan
29	CNY	de	Chinesischer Yuan
30	CNY	en	Chinese Yuan
31	AUD	da	Australske dollar
32	AUD	de	Australischer Dollar
33	AUD	en	Australian Dollar
34	PLN	da	Polske zloty
35	PLN	de	Polnischer Zloty
36	PLN	en	Polish Zloty
37	CZK	da	Tjekkiske kroner
38	CZK	de	Tschechische Krone
39	CZK	en	Czech Koruna
40	HUF	da	Ungarske forint
41	HUF	de	Ungarischer Forint
42	HUF	en	Hungarian Forint
43	RUB	da	Russiske rubel
44	RUB	de	Russischer Rubel
45	RUB	en	Russian Ruble
\.


--
-- TOC entry 5856 (class 0 OID 2351825)
-- Dependencies: 597
-- Data for Name: event; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.event (uuid, external_id, created_by, created_at, modified_by, modified_at, release_date, release_status, org_uuid, venue_uuid, space_uuid, content_iso_639_1, title, description, subtitle, summary, categories, languages, tags, occasion_type_id, min_age, max_age, participation_info, max_attendees, visitor_info_flags, meeting_point, source_link, online_link, ticket_link, ticket_flags, price_type, currency, min_price, max_price, custom, style, search_text) FROM stdin;
019d4e9a-aa28-7f7e-845f-252213276c53	\N	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-04-02 16:30:52.19132	\N	2026-04-05 17:00:04.361452	\N	released	019d2eed-a25a-7caf-a762-a2a71917c6a1	019d3e19-c044-75bf-820b-c96fd5fe07ee	019d44c6-26bf-77d5-a7ca-e82ddd099757	\N	Konzert	aaa	111	ccc	{1,2,5}	{sq,da}	{modular,mixer}	\N	4	8	aaa	86	4690104287233	Beim Eisladen	\N	https://aktivitetshuset.de	\N	{advance_ticket,ticket_required,on_site_ticket_sales,registration_required}	regular_price	EUR	8	16	\N	\N	konzert 111 aaa ccc aaa modular mixer
\.


--
-- TOC entry 5828 (class 0 OID 2351146)
-- Dependencies: 567
-- Data for Name: event_category; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.event_category (category_id, iso_639_1, name, schema_org_type) FROM stdin;
1	de	Kultur	\N
2	de	Bildung	\N
3	de	Sport	\N
4	de	Freizeit	\N
5	de	Familie	\N
6	de	Gesellschaft	\N
1	da	Kultur	\N
2	da	Uddannelse	\N
3	da	Sport	\N
4	da	Fritid	\N
5	da	Familie	\N
6	da	Samfund	\N
1	en	Culture	\N
2	en	Education	\N
3	en	Sports	\N
4	en	Leisure	\N
5	en	Family	\N
6	en	Society	\N
\.


--
-- TOC entry 5834 (class 0 OID 2351604)
-- Dependencies: 575
-- Data for Name: event_date; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.event_date (uuid, created_by, created_at, modified_by, modified_at, release_status, event_uuid, venue_uuid, space_uuid, start_date, start_time, end_date, end_time, entry_time, duration, all_day, ticket_link, availability_status_id, accessibility_info, sold_out, limited_tickets_remaining, custom) FROM stdin;
019d5425-5c98-7837-95ed-23865668abbe	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-04-03 18:20:27.923702	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-04-05 11:14:47.80988	inherited	019d4e9a-aa28-7f7e-845f-252213276c53	019d358b-2946-7c2f-afc0-0cb0e8049f2f	019d44c5-0efb-78d5-a4a6-7e49c6b548b7	2026-04-10	20:00:00	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N
019d5425-d938-79d0-80a7-7d9bfb074fb7	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-04-03 18:20:59.81211	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-04-05 11:14:47.80988	inherited	019d4e9a-aa28-7f7e-845f-252213276c53	019d3e19-c044-75bf-820b-c96fd5fe07ee	019d4924-5882-78cb-8e59-0d32b2dcee08	2026-04-19	20:00:00	\N	\N	19:00:00	\N	\N	\N	\N	\N	\N	\N	\N
019d5426-7a7c-7f9e-9a0f-db33b71625c9	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-04-03 18:21:41.113512	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-04-05 11:14:47.80988	inherited	019d4e9a-aa28-7f7e-845f-252213276c53	019d3f5c-ba16-7c74-a7ba-533f26446ddf	019d44c0-64c0-79d7-ba1d-6e9a51da9742	2026-04-25	20:00:00	\N	\N	19:30:00	\N	\N	\N	\N	\N	\N	\N	\N
019d577b-8a78-73a9-ac75-6b50636f7bb1	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-04-04 09:53:27.395669	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-04-05 11:14:47.80988	inherited	019d4e9a-aa28-7f7e-845f-252213276c53	\N	\N	2026-04-30	20:00:00	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N
019d5cec-5eb3-7a54-8142-e1d7690eef4a	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-04-05 11:14:47.80988	\N	\N	inherited	019d4e9a-aa28-7f7e-845f-252213276c53	\N	\N	2026-05-01	20:00:00	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N
019d5cec-5eb7-7d02-b000-ef25f1c84744	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-04-05 11:14:47.80988	\N	\N	inherited	019d4e9a-aa28-7f7e-845f-252213276c53	\N	\N	2026-05-02	20:00:00	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N
019d5cec-5eb8-7b2c-8d23-a31a3aa9332c	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-04-05 11:14:47.80988	\N	\N	inherited	019d4e9a-aa28-7f7e-845f-252213276c53	\N	\N	2026-05-03	20:00:00	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N
019d5cec-5eb8-742c-95bc-d2e6bca7e786	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-04-05 11:14:47.80988	\N	\N	inherited	019d4e9a-aa28-7f7e-845f-252213276c53	\N	\N	2026-05-04	20:00:00	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N
019d5cec-5eb8-7db0-a7c4-b484908c4854	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-04-05 11:14:47.80988	\N	\N	inherited	019d4e9a-aa28-7f7e-845f-252213276c53	\N	\N	2026-05-05	20:00:00	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N
019d5cec-5eb9-78d5-8ac8-fa10fc603a51	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-04-05 11:14:47.80988	\N	\N	inherited	019d4e9a-aa28-7f7e-845f-252213276c53	\N	\N	2026-05-06	20:00:00	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N
019d5cec-5eb9-7fb3-a7fa-4ca5fe4cb312	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-04-05 11:14:47.80988	\N	\N	inherited	019d4e9a-aa28-7f7e-845f-252213276c53	\N	\N	2026-05-07	20:00:00	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N
019d5cec-5eb9-756d-b84e-4d0b7c3b6d17	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-04-05 11:14:47.80988	\N	\N	inherited	019d4e9a-aa28-7f7e-845f-252213276c53	\N	\N	2026-05-08	20:00:00	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N
\.


--
-- TOC entry 5835 (class 0 OID 2351617)
-- Dependencies: 576
-- Data for Name: event_date_projection; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.event_date_projection (created_at, modified_at, release_status, event_date_uuid, event_uuid, venue_uuid, space_uuid, venue_name, venue_street, venue_house_number, venue_postal_code, venue_city, venue_country, venue_state, venue_point, venue_link, space_name, space_description, space_type, space_total_capacity, space_seating_capacity, space_building_level, space_link, space_accessibility_summary, space_accessibility_flags, start_date, start_time, end_date, end_time, entry_time, duration, all_day, ticket_link, availability_status_id, accessibility_info, custom) FROM stdin;
2026-04-03 18:20:27.923702	2026-04-05 17:00:04.361452	inherited	019d5425-5c98-7837-95ed-23865668abbe	019d4e9a-aa28-7f7e-845f-252213276c53	019d358b-2946-7c2f-afc0-0cb0e8049f2f	019d44c5-0efb-78d5-a4a6-7e49c6b548b7	[SoundCodes~	Am Nordertor	2	24939	Flensburg	DEU	SH	0101000020E610000060A06DE86DDC2240BCB2B27DE7654B40	https://soundcodes.grain.one	Studio	Analoges(digitales Synthesizerstudio, 40 Kanal Mischpult und quadrophonischer Lautsprecheranlage.	studio	6	4	0	\N	\N	\N	2026-04-10	20:00:00	\N	\N	\N	\N	\N	\N	\N	\N	\N
2026-04-03 18:21:41.113512	2026-04-05 17:00:04.361452	inherited	019d5426-7a7c-7f9e-9a0f-db33b71625c9	019d4e9a-aa28-7f7e-845f-252213276c53	019d3f5c-ba16-7c74-a7ba-533f26446ddf	019d44c0-64c0-79d7-ba1d-6e9a51da9742	Kühlhaus	Mühlendamm	25	24937	Flensburg	DEU	SH	0101000020E6100000E0DDB640ABE12240D49DA58124634B40	https://kuehlhaus.net	Biergarten	\N	\N	\N	\N	\N	\N	\N	\N	2026-04-25	20:00:00	\N	\N	19:30:00	\N	\N	\N	\N	\N	\N
2026-04-04 09:53:27.395669	2026-04-05 17:00:04.361452	inherited	019d577b-8a78-73a9-ac75-6b50636f7bb1	019d4e9a-aa28-7f7e-845f-252213276c53	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-04-30	20:00:00	\N	\N	\N	\N	\N	\N	\N	\N	\N
2026-04-03 18:20:59.81211	2026-04-05 17:00:04.361452	inherited	019d5425-d938-79d0-80a7-7d9bfb074fb7	019d4e9a-aa28-7f7e-845f-252213276c53	019d3e19-c044-75bf-820b-c96fd5fe07ee	019d4924-5882-78cb-8e59-0d32b2dcee08	Aktivitetshuset	Norderstraße	49	24939	Flensburg	DEU	SH	0101000020E610000040CBFF7AD2DC2240F4178C0853654B40	https://aktivitetshuset.de	Aktiv Ro	Aktiv Ro er et rum, hvor du kan finde ro i hverdagen. Du kan dyrke yoga, meditere eller læse en bog, lave håndarbejde, danse alene til musik – rummet giver plads til mange muligheder. Der er en højtaler, du kan tilslutte din mobil til, der er yogamåtter, yogapuder, tæpper og klanginstrumenter.	\N	\N	\N	\N	\N	\N	263917200867359	2026-04-19	20:00:00	\N	\N	19:00:00	\N	\N	\N	\N	\N	\N
2026-04-05 11:14:47.80988	2026-04-05 17:00:04.361452	inherited	019d5cec-5eb3-7a54-8142-e1d7690eef4a	019d4e9a-aa28-7f7e-845f-252213276c53	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-01	20:00:00	\N	\N	\N	\N	\N	\N	\N	\N	\N
2026-04-05 11:14:47.80988	2026-04-05 17:00:04.361452	inherited	019d5cec-5eb7-7d02-b000-ef25f1c84744	019d4e9a-aa28-7f7e-845f-252213276c53	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-02	20:00:00	\N	\N	\N	\N	\N	\N	\N	\N	\N
2026-04-05 11:14:47.80988	2026-04-05 17:00:04.361452	inherited	019d5cec-5eb8-742c-95bc-d2e6bca7e786	019d4e9a-aa28-7f7e-845f-252213276c53	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-04	20:00:00	\N	\N	\N	\N	\N	\N	\N	\N	\N
2026-04-05 11:14:47.80988	2026-04-05 17:00:04.361452	inherited	019d5cec-5eb8-7b2c-8d23-a31a3aa9332c	019d4e9a-aa28-7f7e-845f-252213276c53	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-03	20:00:00	\N	\N	\N	\N	\N	\N	\N	\N	\N
2026-04-05 11:14:47.80988	2026-04-05 17:00:04.361452	inherited	019d5cec-5eb8-7db0-a7c4-b484908c4854	019d4e9a-aa28-7f7e-845f-252213276c53	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-05	20:00:00	\N	\N	\N	\N	\N	\N	\N	\N	\N
2026-04-05 11:14:47.80988	2026-04-05 17:00:04.361452	inherited	019d5cec-5eb9-756d-b84e-4d0b7c3b6d17	019d4e9a-aa28-7f7e-845f-252213276c53	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-08	20:00:00	\N	\N	\N	\N	\N	\N	\N	\N	\N
2026-04-05 11:14:47.80988	2026-04-05 17:00:04.361452	inherited	019d5cec-5eb9-78d5-8ac8-fa10fc603a51	019d4e9a-aa28-7f7e-845f-252213276c53	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-06	20:00:00	\N	\N	\N	\N	\N	\N	\N	\N	\N
2026-04-05 11:14:47.80988	2026-04-05 17:00:04.361452	inherited	019d5cec-5eb9-7fb3-a7fa-4ca5fe4cb312	019d4e9a-aa28-7f7e-845f-252213276c53	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-07	20:00:00	\N	\N	\N	\N	\N	\N	\N	\N	\N
\.


--
-- TOC entry 5831 (class 0 OID 2351555)
-- Dependencies: 572
-- Data for Name: event_filter; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.event_filter (uuid, user_id, params, slug, name, description) FROM stdin;
\.


--
-- TOC entry 5833 (class 0 OID 2351572)
-- Dependencies: 574
-- Data for Name: event_link; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.event_link (id, created_at, modified_at, event_uuid, type, label, url) FROM stdin;
3	2026-04-04 11:16:58.173405	\N	019d4e9a-aa28-7f7e-845f-252213276c53	website	Bandwebsite	https://band.grain.one
\.


--
-- TOC entry 5797 (class 0 OID 2266018)
-- Dependencies: 536
-- Data for Name: event_occasion_type; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.event_occasion_type (id, type_id, iso_639_1, name) FROM stdin;
1	1	de	Eröffnung
2	1	da	åbning
3	1	en	opening
4	2	de	Premiere
5	2	da	premiere
6	2	en	premiere
7	3	de	Vernissage
8	3	da	fernisering
9	3	en	opening reception
10	4	de	Finissage
11	4	da	lukning
12	4	en	closing event
13	5	de	Vorschau
14	5	da	forhåndsvisning
15	5	en	preview
16	6	de	Gala
17	6	da	gala
18	6	en	gala
19	7	de	Screening
20	7	da	visning
21	7	en	screening
22	0	de	Keine Angabe
23	0	da	Ingen oplysninger
24	0	en	Not specified
\.


--
-- TOC entry 5836 (class 0 OID 2351626)
-- Dependencies: 577
-- Data for Name: event_projection; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.event_projection (created_at, modified_at, event_uuid, external_id, release_status, org_uuid, venue_uuid, space_uuid, title, subtitle, description, summary, org_name, org_contact_email, org_contact_phone, org_link, venue_name, venue_street, venue_house_number, venue_postal_code, venue_city, venue_country, venue_state, venue_point, venue_link, space_type, space_name, space_description, space_building_level, space_total_capacity, space_seating_capacity, space_link, space_accessibility_flags, space_accessibility_summary, occasion_type_id, categories, types, tags, languages, source_link, online_link, max_attendees, min_age, max_age, participation_info, meeting_point, currency, min_price, max_price, image_alt_text, image_license_id, image_creator_name, image_copyright, image_description, ticket_flags, price_type, visitor_info_flags, image_uuid, search_text, custom, style) FROM stdin;
2026-04-03 18:09:56.671651	2026-04-05 17:00:04.361452	019d4e9a-aa28-7f7e-845f-252213276c53	\N	released	019d2eed-a25a-7caf-a762-a2a71917c6a1	019d3e19-c044-75bf-820b-c96fd5fe07ee	019d44c6-26bf-77d5-a7ca-e82ddd099757	Konzert	111	aaa	ccc	[SoundCodes~	soundcodes@grain.one	0176 59 97 80 74	https://soundcodes.grain.one	Aktivitetshuset	Norderstraße	49	24939	Flensburg	DEU	SH	0101000020E610000040CBFF7AD2DC2240F4178C0853654B40	https://aktivitetshuset.de	\N	Info	\N	\N	\N	\N	\N	\N	\N	\N	{1,2,5}	[[56, 0], [52, 0], [1, 1001], [1, 1008], [1, 1003], [3, 3002], [32, 0]]	{modular,mixer}	{sq,da}	\N	https://aktivitetshuset.de	86	4	8	aaa	Beim Eisladen	EUR	8	16	\N	\N	\N	\N	\N	{advance_ticket,ticket_required,on_site_ticket_sales,registration_required}	regular_price	4690104287233	019d5427-554d-7fd4-a73c-6fa70b6098f6	konzert 111 aaa ccc aaa modular mixer	\N	\N
\.


--
-- TOC entry 5799 (class 0 OID 2266024)
-- Dependencies: 538
-- Data for Name: event_release_status_i18n; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.event_release_status_i18n (iso_639_1, name, key, "order") FROM stdin;
de	Verschoben	deferred	50
da	Udsat	deferred	50
en	Deferred	deferred	50
de	Geerbt	inherited	0
da	Arvet	inherited	0
en	Inherited	inherited	0
de	Entwurf	draft	10
da	Udkast	draft	10
en	Draft	draft	10
de	Veröffentlicht	released	30
da	Udgivet	released	30
en	Released	released	30
de	Abgesagt	cancelled	60
da	Aflyst	cancelled	60
en	Cancelled	cancelled	60
de	Verlegt	rescheduled	40
en	Reschreduled	rescheduled	40
da	Flyttet	rescheduled	40
de	Korrektur	review	20
da	Korrektur	review	20
en	Review	review	20
\.


--
-- TOC entry 5813 (class 0 OID 2283091)
-- Dependencies: 552
-- Data for Name: event_type; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.event_type (type_id, iso_639_1, name, schema_org_type) FROM stdin;
1	da	Koncert	MusicEvent
1	de	Konzert	MusicEvent
1	en	Concert	MusicEvent
2	da	Teater & scene	TheaterEvent
2	de	Theater & Bühne	TheaterEvent
2	en	Theater & Stage	TheaterEvent
3	da	Party	SocialEvent
3	de	Party	SocialEvent
3	en	Party	SocialEvent
4	da	Comedy	ComedyEvent
4	de	Comedy	ComedyEvent
4	en	Comedy	ComedyEvent
5	da	Børneteater	TheaterEvent
5	de	Kindertheater	TheaterEvent
5	en	Children’s Theater	TheaterEvent
6	da	Oplæsning	LiteraryEvent
6	de	Lesung	LiteraryEvent
6	en	Reading	LiteraryEvent
7	da	Sport	SportsEvent
7	de	Sport	SportsEvent
7	en	Sport	SportsEvent
8	da	Kunst	VisualArtsEvent
8	de	Kunst	VisualArtsEvent
8	en	Art	VisualArtsEvent
9	da	Film	MovieEvent
9	de	Film	MovieEvent
9	en	Film	MovieEvent
10	da	Dans	DanceEvent
10	de	Tanz	DanceEvent
10	en	Dance	DanceEvent
11	da	Musik	MusicEvent
11	de	Musik	MusicEvent
11	en	Music	MusicEvent
12	da	Videnskab	ScienceEvent
12	de	Wissenschaft	ScienceEvent
12	en	Science	ScienceEvent
13	da	Marked	SocialEvent
13	de	Markt	SocialEvent
13	en	Market	SocialEvent
14	da	Kursus	EducationalEvent
14	de	Kursus	EducationalEvent
14	en	Course	EducationalEvent
15	da	Workshop	EducationalEvent
15	de	Workshop	EducationalEvent
15	en	Workshop	EducationalEvent
16	da	Poetry slam	PerformingArtsEvent
16	de	Poetry Slam	PerformingArtsEvent
16	en	Poetry Slam	PerformingArtsEvent
17	da	Udstilling	ExhibitionEvent
17	de	Ausstellung	ExhibitionEvent
17	en	Exhibition	ExhibitionEvent
18	da	Festival	Festival
18	de	Festival	Festival
18	en	Festival	Festival
19	da	Fest/fejring	SocialEvent
19	en	Celebration	SocialEvent
20	da	Foredrag	EducationalEvent
20	de	Vortrag	EducationalEvent
20	en	Lecture	EducationalEvent
21	da	Forsamling	SocialEvent
21	de	Versammlung	SocialEvent
21	en	Assembly	SocialEvent
22	da	Kongres	BusinessEvent
22	de	Kongress	BusinessEvent
22	en	Congress	BusinessEvent
23	da	Messe	ExhibitionEvent
23	de	Messe	ExhibitionEvent
23	en	Fair	ExhibitionEvent
24	da	Åbent hus	EducationalEvent
24	de	Tag der offenen Tür	EducationalEvent
24	en	Open house	EducationalEvent
25	da	Rundvisning	TouristEvent
25	de	Rundgang	TouristEvent
25	en	Tour	TouristEvent
26	da	Circus	CircusEvent
26	de	Zirkus	CircusEvent
26	en	Circus	CircusEvent
27	da	Udflugt	TouristEvent
27	de	Ausflug	TouristEvent
27	en	Trip	TouristEvent
28	da	Performance	PerformingArtsEvent
28	de	Performance	PerformingArtsEvent
28	en	Performance	PerformingArtsEvent
29	da	Wellness	SocialEvent
29	de	Wellness	SocialEvent
29	en	Wellness	SocialEvent
30	da	Velgørenhed	SocialEvent
30	de	Charity	SocialEvent
30	en	Charity	SocialEvent
31	da	Religiøs begivenhed	ReligiousEvent
31	de	Glaubensveranstaltung	ReligiousEvent
31	en	Religious event	ReligiousEvent
32	da	Hackathon	BusinessEvent
32	de	Hackathon	BusinessEvent
32	en	Hackathon	BusinessEvent
33	da	Hjælpetilbud	SocialEvent
33	de	Hilfsangebot	SocialEvent
33	en	Assistance offer	SocialEvent
34	da	Uddannelse	EducationalEvent
34	de	Bildung	EducationalEvent
34	en	Education	EducationalEvent
35	da	Politik	SocialEvent
35	de	Politik	SocialEvent
35	en	Politics	SocialEvent
36	da	Byvandring	TouristEvent
36	de	Stadtführung	TouristEvent
36	en	City tour	TouristEvent
37	da	Community event	SocialEvent
37	de	Community event	SocialEvent
37	en	Community event	SocialEvent
38	da	Litteratur	LiteraryEvent
38	de	Literatur	LiteraryEvent
38	en	Literature	LiteraryEvent
39	da	Laboratorium	ScienceEvent
39	de	Labor	ScienceEvent
39	en	Laboratory	ScienceEvent
40	da	Håndværk	EducationalEvent
40	de	Handwerk	EducationalEvent
40	en	Craft	EducationalEvent
41	da	Happening	SocialEvent
41	de	Happening	SocialEvent
41	en	Happening	SocialEvent
42	da	Udendørs	SocialEvent
42	de	Outdoor	SocialEvent
42	en	Outdoor	SocialEvent
43	da	Børn	SocialEvent
43	de	Kinder	SocialEvent
43	en	Children	SocialEvent
44	da	Familie	SocialEvent
44	de	Familie	SocialEvent
44	en	Family	SocialEvent
45	da	Natur	SocialEvent
45	de	Natur	SocialEvent
45	en	Nature	SocialEvent
46	da	Socialt	SocialEvent
46	de	Soziales	SocialEvent
46	en	Social	SocialEvent
47	da	Sundhed	HealthEvent
47	de	Gesundheit	HealthEvent
47	en	Health	HealthEvent
48	da	Retreat	SocialEvent
48	de	Retreat	SocialEvent
48	en	Retreat	SocialEvent
49	da	Dialog, debat	SocialEvent
49	de	Gespräch, Diskussion	SocialEvent
49	en	Talk, discussion	SocialEvent
50	da	Netværk	SocialEvent
50	de	Netzwerk	SocialEvent
50	en	Network	SocialEvent
51	da	Fitness	SportsEvent
51	de	Fitness	SportsEvent
51	en	Fitness	SportsEvent
52	da	Historie	SocialEvent
52	de	Geschichte	SocialEvent
52	en	History	SocialEvent
53	da	Mad og drikke	FoodEstablishment
53	de	Essen und trinken	FoodEstablishment
53	en	Food and drink	FoodEstablishment
54	da	Videreuddannelse	EducationalEvent
54	de	Weiterbildung	EducationalEvent
54	en	Further education	EducationalEvent
55	da	Ferie	SocialEvent
55	de	Ferien	SocialEvent
55	en	Holiday	SocialEvent
56	da	Fritid	SocialEvent
56	de	Freizeit	SocialEvent
56	en	Leisure	SocialEvent
57	da	Mindearrangement	SocialEvent
57	de	Gedenkveranstaltung	SocialEvent
57	en	Memorial event	SocialEvent
58	da	Unge	SocialEvent
58	de	Jugend	SocialEvent
58	en	Youth	SocialEvent
59	da	Seniorer	SocialEvent
59	de	Senioren	SocialEvent
59	en	Elderly	SocialEvent
60	da	Spil	SocialEvent
60	de	Spiel	SocialEvent
60	en	Game	SocialEvent
61	da	Konference	BusinessEvent
61	de	Konferenz	BusinessEvent
61	en	Conference	BusinessEvent
63	da	Afslapning	SocialEvent
63	de	Erholung	SocialEvent
63	en	Recreation	SocialEvent
19	de	Fest/Feier	SocialEvent
62	de	Demo	Parade
62	da	Demonstration	Parade
62	en	Demonstration	Parade
\.


--
-- TOC entry 5857 (class 0 OID 2351839)
-- Dependencies: 598
-- Data for Name: event_type_link; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.event_type_link (event_uuid, type_id, genre_id) FROM stdin;
019d4e9a-aa28-7f7e-845f-252213276c53	56	0
019d4e9a-aa28-7f7e-845f-252213276c53	52	0
019d4e9a-aa28-7f7e-845f-252213276c53	1	1001
019d4e9a-aa28-7f7e-845f-252213276c53	1	1008
019d4e9a-aa28-7f7e-845f-252213276c53	1	1003
019d4e9a-aa28-7f7e-845f-252213276c53	3	3002
019d4e9a-aa28-7f7e-845f-252213276c53	32	0
\.


--
-- TOC entry 5800 (class 0 OID 2266047)
-- Dependencies: 539
-- Data for Name: genre_type; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.genre_type (name, genre_id, type_id, iso_639_1) FROM stdin;
Elektronisk musik	1001	1	da
Elektronische Musik	1001	1	de
Electronic music	1001	1	en
Rock	1002	1	da
Rock	1002	1	de
Rock	1002	1	en
Jazz	1003	1	da
Jazz	1003	1	de
Jazz	1003	1	en
Metal	1004	1	da
Metal	1004	1	de
Metal	1004	1	en
R&B	1005	1	de
World music	1006	1	da
World Music	1006	1	de
World music	1006	1	en
Country	1007	1	da
Country	1007	1	de
Country	1007	1	en
Hip hop	1008	1	da
Hip Hop	1008	1	de
Hip hop	1008	1	en
Fusion	1009	1	da
Fusion	1009	1	de
Fusion	1009	1	en
Folk	1010	1	da
Folk	1010	1	de
Folk	1010	1	en
Pop	1011	1	da
Pop	1011	1	de
Pop	1011	1	en
Latin	1012	1	da
Latin	1012	1	de
Latin	1012	1	en
Klassik	1013	1	da
Klassik	1013	1	de
Classic	1013	1	en
Singer-songwriter	1014	1	da
Singer-Songwriter	1014	1	de
Singer-songwriter	1014	1	en
Blues	1015	1	da
Blues	1015	1	de
Blues	1015	1	en
Crossover	1016	1	da
Crossover	1016	1	de
Crossover	1016	1	en
Indie	1017	1	da
Indie	1017	1	de
Indie	1017	1	en
Alternative	1018	1	da
Alternative	1018	1	de
Alternative	1018	1	en
Punk	1019	1	da
Punk	1019	1	de
Punk	1019	1	en
Reggea	1020	1	da
Reggea	1020	1	de
Reggea	1020	1	en
Soul	1021	1	da
Soul	1021	1	de
Soul	1021	1	en
Funk	1022	1	da
Funk	1022	1	de
Funk	1022	1	en
Gospel	1023	1	da
Gospel	1023	1	de
Gospel	1023	1	en
Schlager	1024	1	da
Schlager	1024	1	de
Schlager	1024	1	en
Ny musik	1025	1	da
Neue Musik	1025	1	de
New music	1025	1	en
Ambient	1026	1	da
Ambient	1026	1	de
Ambient	1026	1	en
Industrial	1027	1	da
Industrial	1027	1	de
Industrial	1027	1	en
Techno	1028	1	da
Techno	1028	1	de
Techno	1028	1	en
House	1029	1	da
House	1029	1	de
House	1029	1	en
Balkan	1030	1	da
Balkan	1030	1	de
Balkan	1030	1	en
Eksperimentel	1031	1	da
Experimental	1031	1	de
Experimental	1031	1	en
Kammerkoncert	1032	1	da
Kammerkonzert	1032	1	de
Chamber concert	1032	1	en
Orgelkoncert	1033	1	da
Orgelkonzert	1033	1	de
Organ concert	1033	1	en
Musical	2001	2	da
Musical	2001	2	de
Musical	2001	2	en
Musikteater	2002	2	da
Musiktheater	2002	2	de
Musical theater	2002	2	en
Cirkusteater	2003	2	da
Zirkus-Theater	2003	2	de
Circus theatre	2003	2	en
Drama	2004	2	da
Drama	2004	2	de
Drama	2004	2	en
Komedie	2005	2	da
Komödie	2005	2	de
Comedy	2005	2	en
Tragedie	2006	2	da
Tragödie	2006	2	de
Tragedy	2006	2	en
Farce	2007	2	da
Farce	2007	2	de
Farce	2007	2	en
Satire	2008	2	da
Satire	2008	2	de
Satire	2008	2	en
Grotesk	2009	2	da
Groteske	2009	2	de
Grotesque	2009	2	en
Klassisk teater	2010	2	da
Klassisches Theater	2010	2	de
Classical theatre	2010	2	en
Historisk teater	2011	2	da
Historisches Theater	2011	2	de
Historical theatre	2011	2	en
Improvisationsteater	2012	2	da
Improvisationstheater	2012	2	de
Improvisational theatre	2012	2	en
Performance-teater	2013	2	da
Performance-Theater	2013	2	de
Performance theatre	2013	2	en
Pantomime	2014	2	da
Pantomime	2014	2	de
Pantomime	2014	2	en
Ballet	2015	2	da
Ballett	2015	2	de
Ballet	2015	2	en
Klassisk opera	2016	2	da
Klassisches Oper	2016	2	de
Classical opera	2016	2	en
Moderne opera	2017	2	da
Moderne Oper	2017	2	de
Modern opera	2017	2	en
Operette	2018	2	da
Operette	2018	2	de
Operetta	2018	2	en
Kammeropera	2019	2	da
Kammeroper	2019	2	de
Chamber opera	2019	2	en
Opera for børn/familier	2020	2	da
Oper für Kinder/Familien	2020	2	de
Opera for children/families	2020	2	en
Ungt teater	2021	2	da
Junges Theater	2021	2	de
Youth theater	2021	2	en
Dukketeater	2022	2	da
Puppenspiel	2022	2	de
Puppet theater	2022	2	en
Skuespil	2023	2	da
Schauspiel	2023	2	de
Theater play	2023	2	en
Opera	2024	2	da
Oper	2024	2	de
Opera	2024	2	en
Trance	3001	3	da
Trance	3001	3	de
Trance	3001	3	en
Edm	3002	3	da
EDM	3002	3	de
Edm	3002	3	en
Drum and bass	3003	3	da
Drum and Bass	3003	3	de
Drum and bass	3003	3	en
Disco	3004	3	da
Disco	3004	3	de
Disco	3004	3	en
Dancehall	3005	3	da
Dancehall	3005	3	de
Dancehall	3005	3	en
Retro	3006	3	da
Retro	3006	3	de
Retro	3006	3	en
Schlager	3007	3	da
Schlager	3007	3	de
Schlager	3007	3	en
Silent disco	3008	3	da
Silent Disco	3008	3	de
Silent disco	3008	3	en
Kostumefest	3009	3	da
Kostümparty	3009	3	de
Costume party	3009	3	en
Karaoke	3010	3	da
Karaoke	3010	3	de
Karaoke	3010	3	en
Clubbing	3011	3	da
Clubbing	3011	3	de
Clubbing	3011	3	en
Stand-up	4001	4	da
Stand-up	4001	4	de
Stand-up	4001	4	en
Kabaret	4002	4	da
Kabarett	4002	4	de
Cabaret	4002	4	en
Satire	4003	4	da
Satire	4003	4	de
Satire	4003	4	en
Sketch	4004	4	da
Sketch	4004	4	de
Sketch	4004	4	en
Parodi	4005	4	da
Parodie	4005	4	de
Parody	4005	4	en
Nonsens	4006	4	da
Nonsens	4006	4	de
Nonsense	4006	4	en
Dukketeater	5001	5	da
Puppenspiel	5001	5	de
Puppet show	5001	5	en
Eventyr	5002	5	da
Märchen	5002	5	de
Fairy tale	5002	5	en
Fabel	5003	5	da
Fabel	5003	5	de
Fable	5003	5	en
Klassiker	5004	5	da
Klassiker	5004	5	de
Classic	5004	5	en
Klovneteater	5005	5	da
Clownstheater	5005	5	de
Clown theater	5005	5	en
Figurteater	5006	5	da
Figurentheater	5006	5	de
Object theater	5006	5	en
Børnemusical	5007	5	da
Kindermusical	5007	5	de
Children’s musical	5007	5	en
Fantasy	5008	5	da
Fantasy	5008	5	de
Fantasy	5008	5	en
Oplevelse	5009	5	da
Abenteuer	5009	5	de
Adventure	5009	5	en
Dyrehistorier	5010	5	da
Tiergeschichten	5010	5	de
Animal stories	5010	5	en
Magi og trylleri	5011	5	da
Zauber- und Magie	5011	5	de
Magic & illusion	5011	5	en
Danseteater	5012	5	da
Tanztheater	5012	5	de
Dance theatre	5012	5	en
Roman	6001	6	da
Roman	6001	6	de
Novel	6001	6	en
Korthistorier	6002	6	da
Kurzgeschichten	6002	6	de
Short stories	6002	6	en
Novelle	6003	6	da
Novelle	6003	6	de
Novella	6003	6	en
Fantasy	6004	6	da
Fantasy	6004	6	de
Fantasy	6004	6	en
Science-fiction	6005	6	da
Science-Fiction	6005	6	de
Science fiction	6005	6	en
Krimi/thriller	6006	6	da
Krimi/Thriller	6006	6	de
Crime/thriller	6006	6	en
Historisk litteratur	6007	6	da
Historische Literatur	6007	6	de
Historical	6007	6	en
Børne- og ungdomsbog	6008	6	da
Jugendbuch	6008	6	de
Young adult book	6008	6	en
Digte	6009	6	da
Gedichte	6009	6	de
Poems	6009	6	en
Biografi	6010	6	da
Biografie	6010	6	de
Biography	6010	6	en
Autobiografi	6011	6	da
Autobiografie	6011	6	de
Autobiography	6011	6	en
Minder	6012	6	da
Memoiren	6012	6	de
Memoirs	6012	6	en
Rejseberetning	6013	6	da
Reisebericht	6013	6	de
Travel report	6013	6	en
Videnskab	6014	6	da
Wissenschaft	6014	6	de
Science	6014	6	en
Essay	6015	6	da
Essay	6015	6	de
Essay	6015	6	en
Politik/samfund	6016	6	da
Politik/Gesellschaft	6016	6	de
Politics/social	6016	6	en
Filosofi	6017	6	da
Philosophie	6017	6	de
Philosophy	6017	6	en
Manuskript	6018	6	da
Drehbuch	6018	6	de
Screenplay	6018	6	en
Børnehistorier	6019	6	da
Kindergeschichten	6019	6	de
Children’s stories	6019	6	en
Eventyr og sagn	6020	6	da
Märchen und Sagen	6020	6	de
Fairy tales and legends	6020	6	en
Spirituelle tekster	6021	6	da
Spirituelle Texte	6021	6	de
Spiritual texts	6021	6	en
Basketball	7001	7	da
Basketball	7001	7	de
Basketball	7001	7	en
Iskockey	7002	7	da
Eishockey	7002	7	de
Ice hockey	7002	7	en
Fodbold	7003	7	da
Fussball	7003	7	de
Soccer	7003	7	en
Golf	7004	7	da
Golf	7004	7	de
Golf	7004	7	en
Kampsport	7005	7	da
Kampfsport	7005	7	de
Martial arts	7005	7	en
Walking	7006	7	da
Walking	7006	7	de
Walking	7006	7	en
Løb	7007	7	da
Laufen	7007	7	de
Running	7007	7	en
Vandring	7008	7	da
Wandern	7008	7	de
Hiking	7008	7	en
Cykling	7009	7	da
Radfahren	7009	7	de
Cycling	7009	7	en
Motorsport	7010	7	da
Motorsport	7010	7	de
Motorsport	7010	7	en
Ridning	7011	7	da
Reiten	7011	7	de
Horse riding	7011	7	en
Flyvning	7012	7	da
Fliegen	7012	7	de
Flying	7012	7	en
Sejlads	7013	7	da
Segeln	7013	7	de
Sailing	7013	7	en
Rulleskøjte	7014	7	da
Skaten	7014	7	de
Skating	7014	7	en
Skiløb	7015	7	da
Schifahren	7015	7	de
Skiing	7015	7	en
Volleyball	7016	7	da
Volleyball	7016	7	de
Volleyball	7016	7	en
Vandsport	7017	7	da
Wassersport	7017	7	de
Water sports	7017	7	en
Vintersport	7018	7	da
Wintersport	7018	7	de
Winter sports	7018	7	en
Yoga	7019	7	da
Yoga	7019	7	de
Yoga	7019	7	en
Maleri	8001	8	da
Malerei	8001	8	de
Painting	8001	8	en
Fotografi	8002	8	da
Fotografie	8002	8	de
Photography	8002	8	en
Skulptur	8003	8	da
Skulptur	8003	8	de
Sculpture	8003	8	en
Installation	8004	8	da
Installation	8004	8	de
Installation	8004	8	en
Illustration	8005	8	da
Illustration	8005	8	de
Illustration	8005	8	en
Grafik og tryk	8006	8	da
Grafik und Druck	8006	8	de
Graphics and print	8006	8	en
Design	8007	8	da
Design	8007	8	de
Design	8007	8	en
Objektkunst	8008	8	da
Objektkunst	8008	8	de
Object art	8008	8	en
Mediekunst	8009	8	da
Medienkunst	8009	8	de
Media art	8009	8	en
Street art	8010	8	da
Street Art	8010	8	de
Street art	8010	8	en
Video / film / bevægelsesbillede	8011	8	da
Video / Film / Bewegtbild	8011	8	de
Video / film / moving image	8011	8	en
Performancekunst	8012	8	da
Performance-Kunst	8012	8	de
Performance art	8012	8	en
Arkitektur	8013	8	da
Architektur	8013	8	de
Architecture	8013	8	en
Lydkunst	8014	8	da
Klangkunst	8014	8	de
Sound art	8014	8	en
Lyskunst	8015	8	da
Lichtkunst	8015	8	de
Light art	8015	8	en
Fotografi	8016	8	da
Fotografie	8016	8	de
Photography	8016	8	en
Drama	9001	9	da
Drama	9001	9	de
Drama	9001	9	en
Komedie	9002	9	da
Komödie	9002	9	de
Comedy	9002	9	en
Dokumentarfilm	9003	9	da
Dokumentarfilm	9003	9	de
Documentary film	9003	9	en
Animationsfilm	9004	9	da
Animationsfilm	9004	9	de
Animated film	9004	9	en
Eksperimentel film	9005	9	da
Experimentalfilm	9005	9	de
Experimental film	9005	9	en
Kortfilm	9006	9	da
Kurzfilm	9006	9	de
Short film	9006	9	en
Spillefilm	9007	9	da
Spielfilm	9007	9	de
Feature film	9007	9	en
Essayfilm	9008	9	da
Essayfilm	9008	9	de
Essay film	9008	9	en
Stumfilm	9009	9	da
Stummfilm	9009	9	de
Silent film	9009	9	en
Arthouse / independent	9010	9	da
Arthouse / Independent	9010	9	de
Arthouse / independent	9010	9	en
Familiefilm	9011	9	da
Familienfilm	9011	9	de
Family film	9011	9	en
Biografi	9012	9	da
Biografie	9012	9	de
Biography	9012	9	en
Roadmovie	9013	9	da
Roadmovie	9013	9	de
Road movie	9013	9	en
Satire	9014	9	da
Satire	9014	9	de
Satire	9014	9	en
Grotesk	9015	9	da
Groteske	9015	9	de
Grotesque	9015	9	en
Science fiction	9016	9	da
Science Fiction	9016	9	de
Science fiction	9016	9	en
Fantasy	9017	9	da
Fantasy	9017	9	de
Fantasy	9017	9	en
Thriller	9018	9	da
Thriller	9018	9	de
Thriller	9018	9	en
Krimi	9019	9	da
Krimi	9019	9	de
Crime	9019	9	en
Musikfilm	9020	9	da
Musikfilm	9020	9	de
Music movie	9020	9	en
Dansefilm	9021	9	da
Tanzfilm	9021	9	de
Dance movie	9021	9	en
Litteraturfilm	9022	9	da
Literaturverfilmung	9022	9	de
Literary adaptation	9022	9	en
Klassisk ballet	10001	10	da
Klassisches Ballett	10001	10	de
Classical ballet	10001	10	en
Moderne dans / samtidsdans	10002	10	da
Modern Dance / Zeitgenössischer Tanz	10002	10	de
Modern dance / contemporary dance	10002	10	en
Jazzdans	10003	10	da
Jazz Dance	10003	10	de
Jazz dance	10003	10	en
Danseteater	10004	10	da
Tanztheater	10004	10	de
Dance theatre	10004	10	en
Børneballet	10005	10	da
Kinderballett	10005	10	de
Children’s ballet	10005	10	en
Open mic	11001	11	da
Open Mic	11001	11	de
Open mic	11001	11	en
Jam session	11002	11	da
Jam Session	11002	11	de
Samtalekoncert	11003	11	da
Gesprächskonzert	11003	11	de
Lecture concert	11003	11	en
Formidling	11004	11	da
Vermittlung	11004	11	de
Education	11004	11	en
Deep listening	11005	11	da
Deep Listening	11005	11	de
Deep listening	11005	11	en
Lyttesession	11006	11	da
Hörsession	11006	11	de
Listening session	11006	11	en
Kunstnersamtale	11007	11	da
Künstlergespräch	11007	11	de
Artist talk	11007	11	en
Lydvandring	11008	11	da
Soundwalk	11008	11	de
Sound walk	11008	11	en
Hørespil	11009	11	da
Hörspiel	11009	11	de
Audio drama	11009	11	en
Åben prøve	11010	11	da
Offene Probe	11010	11	de
Open rehearsal	11010	11	en
Verdensrummet	12001	12	da
Weltraum	12001	12	de
Space	12001	12	en
Jorden	12002	12	da
Planet Erde	12002	12	de
Planet earth	12002	12	en
Teknik	12003	12	da
Technik	12003	12	de
Technology	12003	12	en
Loppemarked	13001	13	da
Flohmarkt	13001	13	de
Flea market	13001	13	en
Julemarked	13002	13	da
Weihnachtsmarkt	13002	13	de
Christmas market	13002	13	en
Påskemarked	13003	13	da
Ostermarkt	13003	13	de
Easter market	13003	13	en
Sommermarked	13004	13	da
Sommermarkt	13004	13	de
Summer market	13004	13	en
Høstmarked	13005	13	da
Erntemarkt	13005	13	de
Harvest market	13005	13	en
Middelaldermarked	13006	13	da
Mittelaltermarkt	13006	13	de
Medieval market	13006	13	en
Vikingemarked	13007	13	da
Wikingermarkt	13007	13	de
Viking market	13007	13	en
Ugently marked	13008	13	da
Wochenmarkt	13008	13	de
Weekly market	13008	13	en
Fødevaremarked	13009	13	da
Lebensmittelmarkt	13009	13	de
Food market	13009	13	en
Fiskemarked	13010	13	da
Fischmarkt	13010	13	de
Fish market	13010	13	en
Blomstermarked	13011	13	da
Blumenmarkt	13011	13	de
Flower market	13011	13	en
Genbrugsmarked	13012	13	da
Second-Hand-Markt	13012	13	de
Second-hand market	13012	13	en
Byttemarked	13013	13	da
Tauschmarkt	13013	13	de
Swap market	13013	13	en
Antikmarked	13014	13	da
Antikmarkt	13014	13	de
Antique market	13014	13	en
Retro-marked	13015	13	da
Retromarkt	13015	13	de
Retro market	13015	13	en
Kunsthåndværkermarked	13016	13	da
Kunsthandwerkermarkt	13016	13	de
Arts and crafts market	13016	13	en
Designmarked	13017	13	da
Designmarkt	13017	13	de
Design market	13017	13	en
Bogmarked	13018	13	da
Büchermarkt	13018	13	de
Book market	13018	13	en
Plademarked	13019	13	da
Schallplattenmarkt	13019	13	de
Record fair	13019	13	en
Natmarked	13020	13	da
Nachtmarkt	13020	13	de
Night market	13020	13	en
Dyremarked	13021	13	da
Tiermarkt	13021	13	de
Animal market	13021	13	en
Dänisch	14001	14	da
Deutsch	14001	14	de
Englisch	14001	14	en
Engelsk	14002	14	da
Englisch	14002	14	de
English	14002	14	en
Fransk	14003	14	da
Französisch	14003	14	de
French	14003	14	en
Spansk	14004	14	da
Spanisch	14004	14	de
Spanish	14004	14	en
Italiensk	14005	14	da
Italienisch	14005	14	de
Italian	14005	14	en
Tysk som fremmedsprog	14006	14	da
Deutsch als Fremdsprache (DaF)	14006	14	de
German as a foreign language	14006	14	en
Kinesisk	14007	14	da
Chinesisch	14007	14	de
Chinese	14007	14	en
Japansk	14008	14	da
Japanisch	14008	14	de
Japanese	14008	14	en
Russisk	14009	14	da
Russisch	14009	14	de
Russian	14009	14	en
Tegnsprog	14010	14	da
Gebärdensprache	14010	14	de
Sign language	14010	14	en
Latin	14011	14	da
Latein	14011	14	de
Latin	14011	14	en
Oldgræsk	14012	14	da
Altgriechisch	14012	14	de
Ancient greek	14012	14	en
Maleri	14013	14	da
Malen	14013	14	de
Painting	14013	14	en
Tegning	14014	14	da
Zeichnen	14014	14	de
Drawing	14014	14	en
Akvarel	14015	14	da
Aquarell	14015	14	de
Watercolor	14015	14	en
Oliefarve	14016	14	da
Ölmalerei	14016	14	de
Oil painting	14016	14	en
Skulptur	14017	14	da
Bildhauerei	14017	14	de
Sculpture	14017	14	en
Keramik	14018	14	da
Töpfern / Keramik	14018	14	de
Pottery / ceramics	14018	14	en
Fotografi	14019	14	da
Fotografie	14019	14	de
Photography	14019	14	en
Fotoredigering	14020	14	da
Bildbearbeitung	14020	14	de
Photo editing	14020	14	en
Strikning	14021	14	da
Stricken	14021	14	de
Knitting	14021	14	en
Hækling	14022	14	da
Häkeln	14022	14	de
Crocheting	14022	14	en
Syning	14023	14	da
Nähen	14023	14	de
Sewing	14023	14	en
Smykkefremstilling	14024	14	da
Schmuckdesign	14024	14	de
Jewelry design	14024	14	en
Håndarbejde / diy	14025	14	da
Basteln / DIY	14025	14	de
Handicrafts / DIY	14025	14	en
Instrumentalundervisning	14026	14	da
Instrumentalunterricht	14026	14	de
Instrument lessons	14026	14	en
Sangundervisning	14027	14	da
Gesangsunterricht	14027	14	de
Singing lessons	14027	14	en
Kor	14028	14	da
Chorarbeit	14028	14	de
Choir	14028	14	en
Standard / latin dans	14029	14	da
Standard / Latein Tanz	14029	14	de
Ballroom / latin dance	14029	14	en
Hip-hop dans	14030	14	da
Hip-Hop Tanz	14030	14	de
Hip-hop dance	14030	14	en
Salsa	14031	14	da
Salsa	14031	14	de
Salsa	14031	14	en
Folkedans	14032	14	da
Volkstanz	14032	14	de
Folk dance	14032	14	en
Zumba	14033	14	da
Zumba	14033	14	de
Zumba	14033	14	en
Musikteori	14034	14	da
Musiktheorie	14034	14	de
Music theory	14034	14	en
Komposition	14035	14	da
Komposition	14035	14	de
Composition	14035	14	en
Ensemble / band	14036	14	da
Ensemble / Band	14036	14	de
Ensemble / band	14036	14	en
Yoga	14037	14	da
Yoga	14037	14	de
Yoga	14037	14	en
Pilates	14038	14	da
Pilates	14038	14	de
Pilates	14038	14	en
Tai chi	14039	14	da
Tai Chi	14039	14	de
Tai Chi	14039	14	en
Qigong	14040	14	da
Qigong	14040	14	de
Qigong	14040	14	en
Fitness	14041	14	da
Fitness	14041	14	de
Fitness	14041	14	en
Aerobic	14042	14	da
Aerobic	14042	14	de
Aerobics	14042	14	en
Funktionel træning	14043	14	da
Funktional Training	14043	14	de
Functional training	14043	14	en
Rygtræning	14044	14	da
Rückenschule	14044	14	de
Back exercise	14044	14	en
Svømning	14045	14	da
Schwimmen	14045	14	de
Swimming	14045	14	en
Vandfitness	14046	14	da
Aquafitness	14046	14	de
Aqua Fitness	14046	14	en
Selvforsvar	14047	14	da
Selbstverteidigung	14047	14	de
Self-defense	14047	14	en
Kampsport	14048	14	da
Kampfsport	14048	14	de
Martial Arts	14048	14	en
Meditation	14049	14	da
Meditation	14049	14	de
Meditation	14049	14	en
Autogen træning	14050	14	da
Autogenes Training	14050	14	de
Autogenic Training	14050	14	en
Retorik	14051	14	da
Rhetorik	14051	14	de
Rhetoric / public speaking	14051	14	en
Kommunikation	14052	14	da
Kommunikation	14052	14	de
Communication	14052	14	en
Præsentation	14053	14	da
Präsentation	14053	14	de
Presentation	14053	14	en
Jobtræning	14054	14	da
Bewerbungstraining	14054	14	de
Job application / career training	14054	14	en
Stresshåndtering	14055	14	da
Stressmanagement	14055	14	de
Stress management	14055	14	en
Tidsstyring	14056	14	da
Zeitmanagement	14056	14	de
Time management	14056	14	en
Psykologi	14057	14	da
Psychologie	14057	14	de
Psychology	14057	14	en
Filosofi / etik	14058	14	da
Philosophie / Ethik	14058	14	de
Philosophy / ethics	14058	14	en
Politik	14059	14	da
Politik	14059	14	de
Politics	14059	14	en
Kontorprogrammer	14060	14	da
Office-Programme	14060	14	de
Office software	14060	14	en
Programmering	14061	14	da
Programmieren	14061	14	de
Programming	14061	14	en
Python	14062	14	da
Python	14062	14	de
Python	14062	14	en
Webudvikling	14063	14	da
Webentwicklung	14063	14	de
Web development	14063	14	en
Grafik / design	14064	14	da
Grafik & Design	14064	14	de
Graphic design	14064	14	en
Photoshop	14065	14	da
Photoshop	14065	14	de
Photoshop	14065	14	en
Illustrator	14066	14	da
Illustrator	14066	14	de
Illustrator	14066	14	en
Cad	14067	14	da
CAD	14067	14	de
CAD	14067	14	en
Sociale medier	14068	14	da
Social Media	14068	14	de
Social media	14068	14	en
Blogging	14069	14	da
Blogging	14069	14	de
Blogging	14069	14	en
Youtube	14070	14	da
YouTube	14070	14	de
YouTube	14070	14	en
Smartphone / tablet	14071	14	da
Smartphone / Tablet	14071	14	de
Smartphone / tablet	14071	14	en
Sprogcertifikater	14072	14	da
Sprachzertifikate	14072	14	de
Language certificates	14072	14	en
Pleje	14073	14	da
Pflege	14073	14	de
Nursing / care	14073	14	en
Pædagogik	14074	14	da
Erziehung	14074	14	de
Education / pedagogy	14074	14	en
Håndværk	14075	14	da
Handwerk	14075	14	de
Crafts	14075	14	en
Bogføring	14076	14	da
Buchhaltung	14076	14	de
Accounting	14076	14	en
Skatteret	14077	14	da
Steuerrecht	14077	14	de
Tax law	14077	14	en
Økonomi	14078	14	da
Betriebswirtschaft	14078	14	de
Business administration	14078	14	en
Madlavning	14079	14	da
Kochkurse	14079	14	de
Cooking classes	14079	14	en
Bagning	14080	14	da
Backen	14080	14	de
Baking	14080	14	en
Ernæring / sundhed	14081	14	da
Ernährung & Gesundheit	14081	14	de
Nutrition & health	14081	14	en
Havearbejde	14082	14	da
Gartenarbeit	14082	14	de
Gardening	14082	14	en
Urban gardening	14083	14	da
Urban Gardening	14083	14	de
Urban gardening	14083	14	en
Brætspil	14084	14	da
Brettspiele	14084	14	de
Board games	14084	14	en
Rejser / kultur	14085	14	da
Reisen & Kultur	14085	14	de
Travel & culture	14085	14	en
Litteraturkreds	14086	14	da
Literaturzirkel	14086	14	de
Literature circle	14086	14	en
Skrivning	14087	14	da
Schreibwerkstatt	14087	14	de
Writing workshop	14087	14	en
R&B	1005	1	da
R&B	1005	1	en
Jam session	11002	11	en
\.


--
-- TOC entry 5801 (class 0 OID 2266054)
-- Dependencies: 540
-- Data for Name: image_type; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.image_type (id, name, description, type_id, iso_639_1) FROM stdin;
2	fotografi	\N	1	da
5	illustration	\N	2	da
8	logo	\N	3	da
1	Foto	\N	1	de
4	Illustration	\N	2	de
7	Logo	\N	3	de
3	photo	\N	1	en
6	illustration	\N	2	en
9	logo	\N	3	en
\.


--
-- TOC entry 5803 (class 0 OID 2266060)
-- Dependencies: 542
-- Data for Name: language; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.language (code_iso_639_1, name, name_iso_639_1) FROM stdin;
sq	Albanian	en
sq	Albanisch	de
sq	Albansk	da
sq	Albanais	fr
sq	Albanés	es
hy	Armenian	en
hy	Armenisch	de
hy	Armensk	da
hy	Arménien	fr
hy	Armenio	es
be	Belarusian	en
be	Belarussisch	de
be	Hviderussisk	da
be	Biélorusse	fr
be	Bielorruso	es
bs	Bosnian	en
bs	Bosnisch	de
bs	Bosnisk	da
bs	Bosnien	fr
bs	Bosnio	es
bg	Bulgarian	en
bg	Bulgarisch	de
bg	Bulgarsk	da
bg	Bulgare	fr
bg	Búlgaro	es
hr	Croatian	en
hr	Kroatisch	de
hr	Kroatisk	da
hr	Croate	fr
hr	Croata	es
cs	Czech	en
cs	Tschechisch	de
cs	Tjekkisk	da
cs	Tchèque	fr
cs	Checo	es
da	Danish	en
da	Dänisch	de
da	Dansk	da
da	Danois	fr
da	Danés	es
nl	Dutch	en
nl	Niederländisch	de
nl	Hollandsk	da
nl	Néerlandais	fr
nl	Neerlandés	es
en	English	en
en	Englisch	de
en	Engelsk	da
en	Anglais	fr
en	Inglés	es
et	Estonian	en
et	Estnisch	de
et	Estisk	da
et	Estonien	fr
et	Estonio	es
fi	Finnish	en
fi	Finnisch	de
fi	Finsk	da
fi	Finnois	fr
fi	Finés	es
fr	French	en
fr	Französisch	de
fr	Fransk	da
fr	Français	fr
fr	Francés	es
ka	Georgian	en
ka	Georgisch	de
ka	Georgisk	da
ka	Géorgien	fr
ka	Georgiano	es
de	German	en
de	Deutsch	de
de	Tysk	da
de	Allemand	fr
de	Alemán	es
el	Greek	en
el	Griechisch	de
el	Græsk	da
el	Grec	fr
el	Griego	es
hu	Hungarian	en
hu	Ungarisch	de
hu	Ungarsk	da
hu	Hongrois	fr
hu	Húngaro	es
is	Icelandic	en
is	Isländisch	de
is	Islandsk	da
is	Islandais	fr
is	Islandés	es
ga	Irish	en
ga	Irisch	de
ga	Irsk	da
ga	Irlandais	fr
ga	Irlandés	es
it	Italian	en
it	Italienisch	de
it	Italiensk	da
it	Italien	fr
it	Italiano	es
lv	Latvian	en
lv	Lettisch	de
lv	Lettisk	da
lv	Letton	fr
lv	Letón	es
lt	Lithuanian	en
lt	Litauisch	de
lt	Litauisk	da
lt	Lituanien	fr
lt	Lituano	es
lb	Luxembourgish	en
lb	Luxemburgisch	de
lb	Luxembourgsk	da
lb	Luxembourgeois	fr
lb	Luxemburgués	es
mk	Macedonian	en
mk	Mazedonisch	de
mk	Makedonsk	da
mk	Macédonien	fr
mk	Macedonio	es
mt	Maltese	en
mt	Maltesisch	de
mt	Maltesisk	da
mt	Maltais	fr
mt	Maltés	es
no	Norwegian	en
no	Norwegisch	de
no	Norsk	da
no	Norvégien	fr
no	Noruego	es
pl	Polish	en
pl	Polnisch	de
pl	Polsk	da
pl	Polonais	fr
pl	Polaco	es
pt	Portuguese	en
pt	Portugiesisch	de
pt	Portugisisk	da
pt	Portugais	fr
pt	Portugués	es
ro	Romanian	en
ro	Rumänisch	de
ro	Rumænsk	da
ro	Roumain	fr
ro	Rumano	es
ru	Russian	en
ru	Russisch	de
ru	Russisk	da
ru	Russe	fr
ru	Ruso	es
gd	Scottish Gaelic	en
gd	Schottisches Gälisch	de
gd	Skotsk gælisk	da
gd	Gaélique écossais	fr
gd	Gaélico escocés	es
sr	Serbian	en
sr	Serbisch	de
sr	Serbisk	da
sr	Serbe	fr
sr	Serbio	es
sk	Slovak	en
sk	Slowakisch	de
sk	Slovakisk	da
sk	Slovaque	fr
sk	Eslovaco	es
sl	Slovenian	en
sl	Slowenisch	de
sl	Slovensk	da
sl	Slovène	fr
sl	Esloveno	es
es	Spanish	en
es	Spanisch	de
es	Spansk	da
es	Espagnol	fr
es	Español	es
sv	Swedish	en
sv	Schwedisch	de
sv	Svensk	da
sv	Suédois	fr
sv	Sueco	es
tr	Turkish	en
tr	Türkisch	de
tr	Tyrkisk	da
tr	Turc	fr
tr	Turco	es
uk	Ukrainian	en
uk	Ukrainisch	de
uk	Ukrainsk	da
uk	Ukrainien	fr
uk	Ucraniano	es
cy	Welsh	en
cy	Walisisch	de
cy	Walisisk	da
cy	Gallois	fr
cy	Galés	es
\.


--
-- TOC entry 5822 (class 0 OID 2317098)
-- Dependencies: 561
-- Data for Name: legal_form; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.legal_form (key, schema_org) FROM stdin;
not_specified	LegalService
registered_association	LegalService
limited	LegalService
initiative	LegalService
municipal_administration	LegalService
municipal_facility	LegalService
non_profit_limited_liability_company	LegalService
stock_corporation	LegalService
registered_cooperative	LegalService
general_partnership	LegalService
limited_partnership	LegalService
civil_law_partnership	LegalService
foundation	LegalService
public_law_institution	LegalService
independent_operator	LegalService
\.


--
-- TOC entry 5823 (class 0 OID 2317105)
-- Dependencies: 562
-- Data for Name: legal_form_i18n; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.legal_form_i18n (key, iso_639_1, name, description) FROM stdin;
not_specified	de	Keine Angabe	\N
not_specified	da	Ikke angiver	\N
not_specified	en	Not specified	\N
registered_association	de	Eingetragener Verein	\N
registered_association	en	Registered association	\N
registered_association	da	Registreret forening	\N
limited	de	GmbH	\N
limited	en	Limited	\N
limited	da	Selskab med begrænset ansvar (ApS)	\N
initiative	de	Initiative	\N
initiative	en	Initiative	\N
initiative	da	Initiativ	\N
municipal_administration	en	Municipal administration	\N
municipal_administration	de	Kommunalverwaltung	\N
municipal_administration	da	Kommunalforvaltning	\N
municipal_facility	en	Municipal facility	\N
municipal_facility	de	Kommunale Einrichtung	\N
municipal_facility	da	Kommunal institution	\N
non_profit_limited_liability_company	de	gGmbH	\N
non_profit_limited_liability_company	en	Non-profit Limited Liability Company	\N
non_profit_limited_liability_company	da	Non-profit selskab med begrænset ansvar	\N
stock_corporation	de	Aktiengesellschaft	\N
stock_corporation	en	Stock Corporation / Joint-stock Company	\N
stock_corporation	da	Aktieselskab (A/S)	\N
registered_cooperative	de	Eingetragene Genossenschaft	\N
registered_cooperative	en	Registered Cooperative	\N
registered_cooperative	da	Registreret andelsselskab	\N
general_partnership	de	Offene Handelsgesellschaft	\N
general_partnership	en	General Partnership	\N
general_partnership	da	Interessentskab (I/S)	\N
limited_partnership	de	Kommanditgesellschaft	\N
limited_partnership	en	Limited Partnership	\N
limited_partnership	da	Kommanditselskab (K/S)	\N
civil_law_partnership	de	Gesellschaft bürgerlichen Rechts	\N
civil_law_partnership	en	Civil-law Partnership	\N
civil_law_partnership	da	Interessentskab (I/S)	\N
foundation	de	Stiftung	\N
foundation	en	Foundation	\N
foundation	da	Fond	\N
public_law_institution	da	Offentligretlig institution	\N
public_law_institution	de	Anstalt des öffentlichen Rechts (AöR)	\N
public_law_institution	en	Public-law Institution	\N
independent_operator	da	I fri drift / Under fri forvaltning	\N
independent_operator	de	In freier Trägerschaft	\N
independent_operator	en	Independently operated	\N
\.


--
-- TOC entry 5824 (class 0 OID 2317191)
-- Dependencies: 563
-- Data for Name: license; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.license (key, spdx_id, url) FROM stdin;
all-rights-reserved	\N	\N
cc-by	CC-BY	https://creativecommons.org/licenses/by/4.0/
cc-by-nc	CC-BY-NC	https://creativecommons.org/licenses/by-nc/4.0/
cc-by-nc-nd	CC-BY-NC-ND	https://creativecommons.org/licenses/by-nc-nd/4.0/
cc-by-nc-sa	CC-BY-NC-SA	https://creativecommons.org/licenses/by-nc-sa/4.0/
cc-by-nd	CC-BY-ND	https://creativecommons.org/licenses/by-nd/4.0/
cc-by-sa	CC-BY-SA	https://creativecommons.org/licenses/by-sa/4.0/
cc0	CC0-1.0	https://creativecommons.org/publicdomain/zero/1.0/
mit	MIT	https://opensource.org/licenses/MIT
pd	\N	\N
\.


--
-- TOC entry 5825 (class 0 OID 2317198)
-- Dependencies: 564
-- Data for Name: license_i18n; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.license_i18n (key, iso_639_1, name, description) FROM stdin;
all-rights-reserved	en	All Rights Reserved	\N
all-rights-reserved	de	Alle Rechte vorbehalten	\N
all-rights-reserved	da	Alle rettigheder forbeholdes	\N
cc-by	en	CC BY – Attribution	\N
cc-by	de	CC BY – Namensnennung	\N
cc-by	da	CC BY – Kreditering	\N
cc-by-nc	en	CC BY-NC – Attribution-NonCommercial	\N
cc-by-nc	de	CC BY-NC – Namensnennung-Nichtkommerziell	\N
cc-by-nc	da	CC BY-NC – Kreditering-Ikke-kommerciel	\N
cc-by-nc-nd	en	CC BY-NC-ND – Attribution-NonCommercial-NoDerivatives	\N
cc-by-nc-nd	de	CC BY-NC-ND – Namensnennung-Nichtkommerziell-Keine Bearbeitung	\N
cc-by-nc-nd	da	CC BY-NC-ND – Kreditering-Ikke-kommerciel-Uden afledning	\N
cc-by-nc-sa	en	CC BY-NC-SA – Attribution-NonCommercial-ShareAlike	\N
cc-by-nc-sa	de	CC BY-NC-SA – Namensnennung-Nichtkommerziell-Weitergabe unter gleichen Bedingungen	\N
cc-by-nc-sa	da	CC BY-NC-SA – Kreditering-Ikke-kommerciel-Del på samme vilkår	\N
cc-by-nd	en	CC BY-ND – Attribution-NoDerivatives	\N
cc-by-nd	de	CC BY-ND – Namensnennung-Keine Bearbeitung	\N
cc-by-nd	da	CC BY-ND – Kreditering-Uden afledning	\N
cc-by-sa	en	CC BY-SA – Attribution-ShareAlike	\N
cc-by-sa	de	CC BY-SA – Namensnennung-Weitergabe unter gleichen Bedingungen	\N
cc-by-sa	da	CC BY-SA – Kreditering-Del på samme vilkår	\N
cc0	en	CC0 – Public Domain	\N
cc0	de	CC0 – Gemeinfrei	\N
cc0	da	CC0 – Offentlig ejendom	\N
mit	en	MIT License	\N
mit	de	MIT-Lizenz	\N
mit	da	MIT-licens	\N
pd	en	Public Domain	\N
pd	de	Gemeinfrei	\N
pd	da	Offentlig ejendom	\N
\.


--
-- TOC entry 5819 (class 0 OID 2317029)
-- Dependencies: 558
-- Data for Name: link_type; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.link_type (key) FROM stdin;
website
facebook
instagram
bandcamp
spotify
vimeo
other
pdf
tickets
mastodon
x
youtube
\.


--
-- TOC entry 5820 (class 0 OID 2317036)
-- Dependencies: 559
-- Data for Name: link_type_i18n; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.link_type_i18n (key, iso_639_1, name, description) FROM stdin;
website	de	Webseite	\N
website	da	Hjemmeside	\N
website	en	Webseite	\N
facebook	de	Facebook	\N
facebook	da	Facebook	\N
facebook	en	Facebook	\N
instagram	de	Instagram	\N
instagram	da	Instagram	\N
instagram	en	Instagram	\N
x	de	X	\N
x	da	X	\N
x	en	X	\N
youtube	de	YouTube	\N
youtube	da	YouTube	\N
youtube	en	YouTube	\N
bandcamp	de	Bandcamp	\N
bandcamp	da	Bandcamp	\N
bandcamp	en	Bandcamp	\N
spotify	de	Spotify	\N
spotify	da	Spotify	\N
spotify	en	Spotify	\N
vimeo	de	Vimeo	\N
vimeo	da	Vimeo	\N
vimeo	en	Vimeo	\N
other	de	Andere	\N
other	da	Anden	\N
other	en	Other	\N
pdf	de	PDF	\N
pdf	da	PDF	\N
pdf	en	PDF	\N
tickets	de	Tickets	\N
tickets	da	Billetter	\N
tickets	en	Tickets	\N
mastodon	de	Mastodon	\N
mastodon	da	Mastodon	\N
mastodon	en	Mastodon	\N
\.


--
-- TOC entry 5838 (class 0 OID 2351641)
-- Dependencies: 579
-- Data for Name: message; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.message (id, created_at, modified_at, to_user_uuid, from_user_uuid, subject, message, is_read) FROM stdin;
\.


--
-- TOC entry 5839 (class 0 OID 2351659)
-- Dependencies: 580
-- Data for Name: organization; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.organization (uuid, created_by, created_at, modified_by, modified_at, name, description, contact_email, contact_phone, web_link, street, house_number, address_addition, postal_code, city, country, state, holding_org_uuid, legal_form, nonprofit, point, api_import_token, api_import_enabled) FROM stdin;
019d3e19-6c1c-7bf0-ad59-b1f15fb20c5c	\N	2026-03-30 11:35:46.715494	\N	2026-03-30 12:07:42.773635	Sydslesvigs danske Ungdomsforeninger e.V.	Sydslesvigs danske Ungdomsforeninger (SdU) ist der Dachverband der dänischen Jugendorganisationen in Südschleswig mit Sitz in Flensburg. Er fördert die Kultur und Identität der dänischen Minderheit durch 12 Freizeitheime, 10 Klubhäuser, Sportplätze und das Zentrum Flensborghus. SdU bietet vielfältige pädagogische Aktivitäten, Kinderhorte und Sportmöglichkeiten.	kontoret@sdu.de	+49 (0) 461 14408–0	https://sdu.de	Norderstraße	76	\N	24939	Flensburg	DEU	SH	\N	registered_association	\N	0101000020E61000004068088EE0DC2240DC42959787654B40	3cbEp6ECByoaeb0Y71vRGU	f
019d3f54-0db6-731f-8e18-03cb0c70b3fe	\N	2026-03-30 17:19:26.387293	\N	2026-03-30 17:22:44.914301	Kulturwerkstatt Kühlhaus e. V.	Die Einzigartigkeit des Kühlhauses zeigt sich bereits in der Geschichte des Hauses. Ehemals war das Kühlhaus in Flensburg Eigentum der Deutschen Bahn: ein Obst- und Kühllager direkt an den Gleisen des Flensburger Güterbahnhofsgelegen. Gebäude und Gelände standen schon einige Jahre leer, als eine handvoll junger Flensburger und Flensburgerinnen begannen, die Räume für Veranstaltungen und zur eigenen kreativen und künstlerischen Entfaltung zu nutzen.  \n  \nSie gründeten im November 1994 den Verein „Kulturwerkstatt Kühlhaus e.V.“, um eine rechtliche und organisatorische Grundlage für die gemeinsame Arbeit zu schaffen und die Möglichkeit einer öffentlichen Förderung zu gewährleisten. In ehrenamtlicher Arbeit wurde die alte Lagerhalle zum Veranstaltungssaal ausgebaut, sodass schon im Dezember 1994 die Eröffnung des Hauses mit einem Doppelkonzert stattfinden konnte. Seither lädt das Kühlhaus jährlich an den Weihnachtsfeiertagen zum Geburtstag.	info@kuehlhaus.net/	\N	https://kuehlhaus.net/	Mühlendamm	25	\N	24937^	Flensburg	DEU	SH	\N	registered_association	\N	0101000020E6100000D0B685E1A4E122405C2D94A526634B40	Apctjl1rEZxwPK39r91ea	f
019d3e2d-5c6e-78df-9fbc-930adb904621	\N	2026-03-30 11:57:33.420847	\N	2026-03-30 17:26:51.80112	Landesarbeitsgemeinschaft Soziokultur Schleswig-Holstein e. V.	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	0101000020E610000050D700EA1549244008613701D3294B40	73iFUMHzQXfcoEWS8C1C37	f
019d2eed-a25a-7caf-a762-a2a71917c6a1	\N	2026-03-27 11:53:38.77816	\N	2026-04-04 18:24:54.774852	[SoundCodes~	\\[SoundCodes~ ist ein Projekt des Flensburger Programmierers und Klangforschers Roald Christesen	soundcodes@grain.one	0176 59 97 80 74	https://soundcodes.grain.one	Am Nordertor	2	\N	24939	Flensburg	DEU	SH	\N	initiative	\N	0101000020E61000006028679D73DC2240A4524E81E7654B40	2csMkuV3tQ2RdON7KXZEKr	f
019d35a0-3cd6-7c28-b3ca-537e8577defe	\N	2026-03-28 19:06:27.030075	\N	2026-03-30 11:35:21.494096	OK Lab Flensburg	Das **OK Lab Flensburg** ist eine offene Gruppe engagierter Menschen aus Flensburg und Umgebung, die jeden **Mittwochabend** zusammenkommt. Wir arbeiten gemeinsam an spannenden lokalen Projekten rund um **Technologie, Daten und Verwaltung** – von nutzerfreundlichen Apps bis zu Prototypen, die Transparenz und Innovation in der Region fördern.\n\nEgal ob du Interesse an **Civic Tech**, **Open Data** oder an **lokaler Digitalisierung** hast – bei uns kannst du aktiv mitgestalten. Einige unserer Projekte stellen wir hier vor – schau gerne vorbei und lass dich inspirieren!	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	1u32dWGYuWywcEnzwiK67r	f
\.


--
-- TOC entry 5840 (class 0 OID 2351676)
-- Dependencies: 581
-- Data for Name: organization_member_link; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.organization_member_link (org_uuid, user_uuid, created_at, modified_at, invited_at, invited_by_user_uuid, accept_token, has_joined) FROM stdin;
019d2eed-a25a-7caf-a762-a2a71917c6a1	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-03-27 11:53:38.77816	\N	\N	\N	\N	t
019d359c-b8f6-75d6-a5fd-ae1f303e3bbe	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-03-28 19:02:36.66238	\N	\N	\N	\N	t
019d35a0-3cd6-7c28-b3ca-537e8577defe	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-03-28 19:06:27.030075	\N	\N	\N	\N	t
019d3e19-6c1c-7bf0-ad59-b1f15fb20c5c	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-03-30 11:35:46.715494	\N	\N	\N	\N	t
019d3e2d-5c6e-78df-9fbc-930adb904621	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-03-30 11:57:33.420847	\N	\N	\N	\N	t
019d3f54-0db6-731f-8e18-03cb0c70b3fe	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-03-30 17:19:26.387293	\N	\N	\N	\N	t
019d3f68-5b90-7af5-b4f6-55e592acb0d4	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-03-30 17:41:37.039682	\N	\N	\N	\N	t
019d5946-16c3-7f0d-95d7-7b73c4f4d42d	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-04-04 18:14:18.817191	\N	\N	\N	\N	t
019d594d-cc9a-7f77-bac8-e3307f0faa75	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-04-04 18:22:44.12172	\N	\N	\N	\N	t
\.


--
-- TOC entry 5841 (class 0 OID 2351687)
-- Dependencies: 582
-- Data for Name: password_reset; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.password_reset (user_uuid, token, expires_at, used) FROM stdin;
\.


--
-- TOC entry 5804 (class 0 OID 2266118)
-- Dependencies: 543
-- Data for Name: permission_bit; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.permission_bit (group_id, name, "bit", mask) FROM stdin;
venue	AddVenue	8	256
venue	EditVenue	9	512
venue	DeleteVenue	10	1024
venue	ChooseVenue	11	2048
space	AddSpace	16	65536
space	EditSpace	17	131072
space	DeleteSpace	18	262144
event	AddEvent	24	16777216
event	EditEvent	25	33554432
event	DeleteEvent	26	67108864
event	ReleaseEvent	27	134217728
event	ViewEventInsights	28	268435456
organization	EditOrganization	0	1
organization	DeleteOrganization	1	2
organization	ChooseAsEventOrganization	2	4
organization	ChooseAsEventPartner	3	8
organization	CanReceiveOrganizationMessages	4	16
organization	ManagePermissions	5	32
organization	ManageTeam	6	64
event	ImportEvents	29	536870912
\.


--
-- TOC entry 5805 (class 0 OID 2266123)
-- Dependencies: 544
-- Data for Name: permission_label; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.permission_label (group_id, name, iso_639_1, label, description) FROM stdin;
venue	AddVenue	en	Add Venue	Create new venues
venue	AddVenue	de	Ort hinzufügen	Neue Veranstaltungsorte erstellen
venue	AddVenue	da	Tilføj venue	Opret nye lokationer
venue	EditVenue	en	Edit Venue	Edit venue details
venue	EditVenue	de	Ort bearbeiten	Veranstaltungsortdetails bearbeiten
venue	EditVenue	da	Rediger venue	Rediger venue-detaljer
venue	DeleteVenue	en	Delete Venue	Remove existing venue
venue	DeleteVenue	de	Ort löschen	Bestehenden Veranstaltungsort entfernen
venue	DeleteVenue	da	Slet venue	Fjern eksisterende lokation
venue	ChooseVenue	en	Choose Venue	Assign venue when making events
venue	ChooseVenue	de	Ort wählen	Veranstaltungsort beim Erstellen eines Events auswählen
venue	ChooseVenue	da	Vælg venue	Tildel lokation ved oprettelse af events
space	AddSpace	en	Add Space	Add spaces to venues
space	AddSpace	de	Raum hinzufügen	Räume zu Veranstaltungsorten hinzufügen
space	AddSpace	da	Tilføj rum	Tilføj rum til lokationer
space	EditSpace	en	Edit Space	Modify venue spaces
space	EditSpace	de	Raum bearbeiten	Veranstaltungsräume bearbeiten
space	EditSpace	da	Rediger rum	Rediger lokationsrum
space	DeleteSpace	en	Delete Space	Remove venue spaces
space	DeleteSpace	de	Raum löschen	Veranstaltungsräume entfernen
space	DeleteSpace	da	Slet rum	Fjern lokationsrum
event	AddEvent	en	Add Event	Create events
event	AddEvent	de	Event hinzufügen	Events erstellen
event	AddEvent	da	Tilføj event	Opret events
event	EditEvent	en	Edit Event	Modify events
event	EditEvent	de	Event bearbeiten	Events bearbeiten
event	EditEvent	da	Rediger event	Rediger events
event	DeleteEvent	en	Delete Event	Delete events
event	DeleteEvent	de	Event löschen	Events löschen
event	DeleteEvent	da	Slet event	Slet events
event	ReleaseEvent	en	Release Event	Publish events
event	ReleaseEvent	de	Event freigeben	Events veröffentlichen
event	ReleaseEvent	da	Udgiv event	Udgiv events
event	ViewEventInsights	en	View Insights	View event insights & analytics
event	ViewEventInsights	de	Einblicke ansehen	Einblicke und Analysen der Events ansehen
event	ViewEventInsights	da	Se indsigter	Se event-analyse
organization	EditOrganization	en	Edit organization	Edit organization settings
organization	EditOrganization	de	Organisation bearbeiten	Organitionseinstellungen bearbeiten
organization	EditOrganization	da	Rediger arrangør	Rediger arrangørindstillinger
organization	DeleteOrganization	en	Delete organization	Delete an organization
organization	DeleteOrganization	de	Organisation löschen	Eine Organisation löschen
organization	DeleteOrganization	da	Slet arrangør	Fjern en arrangør
organization	ChooseAsEventOrganization	en	Choose as event organization	Select organization for events
organization	ChooseAsEventOrganization	de	Als Veranstalter wählen	Organisations für Events auswählen
organization	ChooseAsEventOrganization	da	Vælg som event-arrangør	Vælg arrangør for events
organization	ChooseAsEventPartner	en	Choose as event partner	Add organization as event partner
organization	ChooseAsEventPartner	de	Als Partner wählen	Organisation als Event-Partner hinzufügen
organization	ChooseAsEventPartner	da	Vælg som partner	Tilføj arrangør som event-partner
organization	CanReceiveOrganizationMessages	en	Can Receive Messages	Can receive messages sent to the organization
organization	CanReceiveOrganizationMessages	de	Kann Nachrichten erhalten	Kann Nachrichten für die Organisation empfangen
organization	CanReceiveOrganizationMessages	da	Kan modtage beskeder	Kan modtage beskeder sendt til arrangøren
organization	ManagePermissions	en	Manage permissions	Can set and remove permissions for linked users
organization	ManagePermissions	de	Berechtigungen verwalten	Kann Berechtigungen für verknüpfte Benutzer setzen und entfernen
organization	ManagePermissions	da	Administrer tilladelser	Kan sætte og fjerne tilladelser for tilknyttede brugere
organization	ManageTeam	de	Team verwalten	Teammitglieder verwalten
organization	ManageTeam	da	administrer team	Administrer tem medlemmer
organization	ManageTeam	en	Manage team	Manage team members
event	ImportEvents	da	Importer event	Importerer begivenheder fra eksterne kilder til systemet
event	ImportEvents	de	Events importieren	Importiert Veranstaltungen aus externen Quellen in das System
event	ImportEvents	en	Import events	Imports events from external sources into the system
\.


--
-- TOC entry 5842 (class 0 OID 2351695)
-- Dependencies: 583
-- Data for Name: pluto_cache; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.pluto_cache (created_at, pluto_image_uuid, mime_type, receipt) FROM stdin;
2026-03-28 14:03:30.093044	019d348a-e0e4-7466-99da-c3e0c9242b3f	webp	019d348a-e0e4-7466-99da-c3e0c9242b3f_qw_5000dc
2026-03-28 14:03:33.20697	019d348a-e0e4-7466-99da-c3e0c9242b3f	webp	019d348a-e0e4-7466-99da-c3e0c9242b3f_qw_5a0320
2026-03-28 14:35:51.387134	019d34a8-7fed-7ce8-a7ca-ef5abf112a45	webp	019d34a8-7fed-7ce8-a7ca-ef5abf112a45_qw_5000dc
2026-03-28 14:40:51.67115	019d34a8-7fed-7ce8-a7ca-ef5abf112a45	png	019d34a8-7fed-7ce8-a7ca-ef5abf112a45_qw_500078
2026-03-28 14:40:55.562664	019d348a-e0e4-7466-99da-c3e0c9242b3f	png	019d348a-e0e4-7466-99da-c3e0c9242b3f_qw_500078
2026-03-30 11:38:35.728944	019d3e1b-fffd-7312-a32c-fe0c3d344cb3	webp	019d3e1b-fffd-7312-a32c-fe0c3d344cb3_qw_5000dc
2026-03-30 11:38:45.881701	019d3e1b-fffd-7312-a32c-fe0c3d344cb3	png	019d3e1b-fffd-7312-a32c-fe0c3d344cb3_qw_500078
2026-03-30 11:48:07.026399	019d3e24-b7a5-7f04-8139-fd2bbf8ff61e	webp	019d3e24-b7a5-7f04-8139-fd2bbf8ff61e_qw_5000dc
2026-03-30 11:48:21.153567	019d3e24-eeda-7b15-8c4b-202972f2a844	webp	019d3e24-eeda-7b15-8c4b-202972f2a844_qw_5000dc
2026-03-30 11:48:31.209344	019d3e25-1620-734d-a85d-668fe9925182	webp	019d3e25-1620-734d-a85d-668fe9925182_qw_5000dc
2026-03-30 11:48:33.990337	019d3e25-1620-734d-a85d-668fe9925182	png	019d3e25-1620-734d-a85d-668fe9925182_qw_500078
2026-03-30 11:48:40.702233	019d3e24-eeda-7b15-8c4b-202972f2a844	png	019d3e24-eeda-7b15-8c4b-202972f2a844_qw_500078
2026-03-30 11:58:21.274408	019d3e2e-1714-758b-bc5f-c48df7c380ce	webp	019d3e2e-1714-758b-bc5f-c48df7c380ce_qw_5000dc
2026-03-30 11:58:32.434647	019d3e2e-42b7-71b1-80b8-08c33ca0e3bc	webp	019d3e2e-42b7-71b1-80b8-08c33ca0e3bc_qw_5000dc
2026-03-30 11:58:36.666754	019d3e2e-42b7-71b1-80b8-08c33ca0e3bc	png	019d3e2e-42b7-71b1-80b8-08c33ca0e3bc_qw_500078
2026-03-30 12:09:04.521321	019d3e2e-1714-758b-bc5f-c48df7c380ce	png	019d3e2e-1714-758b-bc5f-c48df7c380ce_qw_500078
2026-03-30 12:30:07.910964	019d3e4b-2eb4-73ea-9ed8-2026addc5cbd	webp	019d3e4b-2eb4-73ea-9ed8-2026addc5cbd_qw_5000dc
2026-03-30 12:30:16.607118	019d3e4b-50e2-7455-b70a-fbe78fb9aa90	webp	019d3e4b-50e2-7455-b70a-fbe78fb9aa90_qw_5000dc
2026-03-30 12:31:04.760497	019d3e4b-2eb4-73ea-9ed8-2026addc5cbd	webp	019d3e4b-2eb4-73ea-9ed8-2026addc5cbd_qw_5a0320
2026-03-30 14:14:20.507815	019d3e4b-50e2-7455-b70a-fbe78fb9aa90	png	019d3e4b-50e2-7455-b70a-fbe78fb9aa90_qw_500078
2026-03-30 17:24:47.308559	019d3f58-f302-7792-a69c-15d12137aa98	webp	019d3f58-f302-7792-a69c-15d12137aa98_qw_5000dc
2026-03-30 17:25:15.075577	019d3f59-5f80-74fa-b4cf-9d672a38bec8	webp	019d3f59-5f80-74fa-b4cf-9d672a38bec8_qw_5000dc
2026-03-30 17:25:23.020765	019d3f59-7e7d-7ad9-bbd2-05bcfd81906a	webp	019d3f59-7e7d-7ad9-bbd2-05bcfd81906a_qw_5000dc
2026-03-30 17:25:46.395962	019d3f59-7e7d-7ad9-bbd2-05bcfd81906a	png	019d3f59-7e7d-7ad9-bbd2-05bcfd81906a_qw_500078
2026-03-30 17:25:56.287738	019d3f59-5f80-74fa-b4cf-9d672a38bec8	png	019d3f59-5f80-74fa-b4cf-9d672a38bec8_qw_500078
2026-03-30 17:30:40.234759	019d3f5e-5591-7e2e-a0b9-df1e93d61c1e	webp	019d3f5e-5591-7e2e-a0b9-df1e93d61c1e_qw_5000dc
2026-03-30 20:25:03.196548	019d3f5e-5591-7e2e-a0b9-df1e93d61c1e	png	019d3f5e-5591-7e2e-a0b9-df1e93d61c1e_qw_500078
2026-03-30 20:25:12.19071	019d3f5e-5591-7e2e-a0b9-df1e93d61c1e	webp	019d3f5e-5591-7e2e-a0b9-df1e93d61c1e_qw_5a0320
2026-04-01 12:08:01.505477	019d4883-a95b-7e05-9b93-fc12b2267865	webp	019d4883-a95b-7e05-9b93-fc12b2267865_qw_5000dc
2026-04-01 12:08:03.905582	019d4883-a95b-7e05-9b93-fc12b2267865	webp	019d4883-a95b-7e05-9b93-fc12b2267865_qw_5a0320
2026-04-01 12:08:32.578197	019d4883-a95b-7e05-9b93-fc12b2267865	png	019d4883-a95b-7e05-9b93-fc12b2267865_qw_500078
2026-04-01 20:22:24.168042	019d4a48-4755-73a2-a49b-b7c2ec603b19	webp	019d4a48-4755-73a2-a49b-b7c2ec603b19_qw_5000dc
2026-04-01 20:22:31.065805	019d4a48-6250-7fc3-b9dd-69613aa628f9	webp	019d4a48-6250-7fc3-b9dd-69613aa628f9_qw_5000dc
2026-04-01 20:22:41.528885	019d4a48-8b12-7813-a54c-d59a6d28f5fe	webp	019d4a48-8b12-7813-a54c-d59a6d28f5fe_qw_5000dc
2026-04-01 20:22:49.853696	019d4a48-ab71-7c8d-8095-6019a9c26873	webp	019d4a48-ab71-7c8d-8095-6019a9c26873_qw_5000dc
2026-04-01 20:37:54.903923	019d4a48-6250-7fc3-b9dd-69613aa628f9	webp	019d4a48-6250-7fc3-b9dd-69613aa628f9_qw_5a0320
2026-04-02 10:08:15.136552	019d44c4-d0b4-79b5-adb2-b89e08271ccf	webp	019d44c4-d0b4-79b5-adb2-b89e08271ccf_qw_5a0320
2026-04-03 18:22:37.242011	019d5427-554d-7fd4-a73c-6fa70b6098f6	webp	019d5427-554d-7fd4-a73c-6fa70b6098f6_qw_5001a4
2026-04-03 18:27:41.751268	019d5427-554d-7fd4-a73c-6fa70b6098f6	jpg	019d5427-554d-7fd4-a73c-6fa70b6098f6_qwhr_5000a0005a_3fe38e39
2026-04-03 18:57:14.459782	019d5427-554d-7fd4-a73c-6fa70b6098f6	webp	019d5427-554d-7fd4-a73c-6fa70b6098f6_qw_5a0320
2026-04-04 14:39:09.077967	019d5427-554d-7fd4-a73c-6fa70b6098f6	jpg	019d5427-554d-7fd4-a73c-6fa70b6098f6_q_50
2026-04-05 11:03:13.691635	019d5427-554d-7fd4-a73c-6fa70b6098f6	jpg	019d5427-554d-7fd4-a73c-6fa70b6098f6_qwhr_5001e0010e_3fe38e39
2026-04-05 17:45:57.805253	019d5427-554d-7fd4-a73c-6fa70b6098f6	jpg	019d5427-554d-7fd4-a73c-6fa70b6098f6_qwhr_50050002d0_3fe38e39
2026-03-31 18:40:42.506157	019d44c4-d0b4-79b5-adb2-b89e08271ccf	webp	019d44c4-d0b4-79b5-adb2-b89e08271ccf_qw_5000dc
2026-03-31 18:40:44.315375	019d44c4-d0b4-79b5-adb2-b89e08271ccf	png	019d44c4-d0b4-79b5-adb2-b89e08271ccf_qw_500078
\.


--
-- TOC entry 5843 (class 0 OID 2351703)
-- Dependencies: 584
-- Data for Name: pluto_context_rules; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.pluto_context_rules (context, identifier, max_width, max_height, compression, max_file_size) FROM stdin;
event	main	1920	1280	85	5242880
\.


--
-- TOC entry 5844 (class 0 OID 2351709)
-- Dependencies: 585
-- Data for Name: pluto_image; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.pluto_image (uuid, created_by, created_at, modified_at, expiration_date, file_name, gen_file_name, mime_type, width, height, description, alt_text, exif, creator_name, copyright, license, focus_x, focus_y) FROM stdin;
019d3f59-5f80-74fa-b4cf-9d672a38bec8	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-03-30 17:25:14.986348	2026-03-30 17:25:14.986348	\N	kuehlhaus white.png	org_019d3f59-5f80-74fa-b4cf-9d672a38bec8.png	image/png	1280	502	\N	\N	{}	\N	\N	\N	\N	\N
019d3f59-7e7d-7ad9-bbd2-05bcfd81906a	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-03-30 17:25:22.931179	2026-03-30 17:25:22.931179	\N	kuehlhaus black.png	org_019d3f59-7e7d-7ad9-bbd2-05bcfd81906a.png	image/png	1280	502	\N	\N	{}	\N	\N	\N	\N	\N
019d3f5e-5591-7e2e-a0b9-df1e93d61c1e	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-03-30 17:30:40.123125	2026-03-30 17:30:40.123125	\N	kuehlhaus color.png	venue_019d3f5e-5591-7e2e-a0b9-df1e93d61c1e.png	image/png	1280	502	\N	Kühhaus Logo	{}	\N	\N	\N	\N	\N
019d348a-e0e4-7466-99da-c3e0c9242b3f	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-03-28 14:03:30.013343	2026-03-28 14:03:30.013343	\N	sound-codes-logo-512-dark-theme.webp	org_019d348a-e0e4-7466-99da-c3e0c9242b3f.webp	image/webp	512	180	\N	\N	{}	\N	\N	\N	\N	\N
019d34a8-7fed-7ce8-a7ca-ef5abf112a45	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-03-28 14:35:51.24312	2026-03-28 14:35:51.24312	\N	sound-codes-logo-512-light-theme.webp	org_019d34a8-7fed-7ce8-a7ca-ef5abf112a45.webp	image/webp	512	180	\N	\N	{}	\N	\N	\N	\N	\N
019d3e1b-fffd-7312-a32c-fe0c3d344cb3	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-03-30 11:38:35.598389	2026-03-30 11:38:35.598389	\N	codefor_de_fl_blau_weiss.png	org_019d3e1b-fffd-7312-a32c-fe0c3d344cb3.png	image/png	1024	1024	\N	OK Lab Flensburg Logo	{}	Roald Christesen	OK Lab Flensburg	cc0	\N	\N
019d3e24-b7a5-7f04-8139-fd2bbf8ff61e	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-03-30 11:48:06.904959	2026-03-30 11:48:06.904959	\N	SdU Logo RGB.png	org_019d3e24-b7a5-7f04-8139-fd2bbf8ff61e.png	image/png	2500	1000	\N	SdU Logo	{}	\N	\N	\N	\N	\N
019d3e24-eeda-7b15-8c4b-202972f2a844	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-03-30 11:48:21.039038	2026-03-30 11:48:21.039038	\N	SdU Logo_white.png	org_019d3e24-eeda-7b15-8c4b-202972f2a844.png	image/png	2500	1000	\N	SdU Logo	{}	\N	\N	\N	\N	\N
019d3e25-1620-734d-a85d-668fe9925182	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-03-30 11:48:31.068017	2026-03-30 11:48:31.068017	\N	SdU Logo_black.png	org_019d3e25-1620-734d-a85d-668fe9925182.png	image/png	2500	1000	\N	SdU Logo	{}	\N	\N	\N	\N	\N
019d3e2e-1714-758b-bc5f-c48df7c380ce	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-03-30 11:58:21.184836	2026-03-30 11:58:21.184836	\N	LAG white logo.png	org_019d3e2e-1714-758b-bc5f-c48df7c380ce.png	image/png	720	800	\N	\N	{}	\N	\N	\N	\N	\N
019d3e2e-42b7-71b1-80b8-08c33ca0e3bc	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-03-30 11:58:32.357397	2026-03-30 11:58:32.357397	\N	LAG black logo.png	org_019d3e2e-42b7-71b1-80b8-08c33ca0e3bc.png	image/png	720	800	\N	\N	{}	\N	\N	\N	\N	\N
019d3e4b-2eb4-73ea-9ed8-2026addc5cbd	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-03-30 12:30:07.768784	2026-03-30 12:30:07.768784	\N	Akti white.png	venue_019d3e4b-2eb4-73ea-9ed8-2026addc5cbd.png	image/png	1280	600	\N	\N	{}	\N	\N	\N	\N	\N
019d3e4b-50e2-7455-b70a-fbe78fb9aa90	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-03-30 12:30:16.529888	2026-03-30 12:30:16.529888	\N	Akti black.png	venue_019d3e4b-50e2-7455-b70a-fbe78fb9aa90.png	image/png	1280	600	\N	\N	{}	\N	\N	\N	\N	\N
019d3f58-f302-7792-a69c-15d12137aa98	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-03-30 17:24:47.196141	2026-03-30 17:24:47.196141	\N	kuehlhaus color.png	org_019d3f58-f302-7792-a69c-15d12137aa98.png	image/png	1280	502	\N	\N	{}	\N	\N	\N	\N	\N
019d4a48-ab71-7c8d-8095-6019a9c26873	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-04-01 20:22:49.634331	2026-04-01 20:22:49.634331	\N	458651964_493693810295999_7527287658839608914_n.jpg	venue_019d4a48-ab71-7c8d-8095-6019a9c26873.jpg	image/jpeg	2048	2048	\N	\N	{}	\N	\N	\N	\N	\N
019d5427-554d-7fd4-a73c-6fa70b6098f6	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-04-03 18:22:37.006713	2026-04-03 18:22:37.006713	\N	454259078_923524169582901_3005651455478534908_n.jpeg	event_019d5427-554d-7fd4-a73c-6fa70b6098f6.jpeg	image/jpeg	1920	1076	\N	\N	{}	\N	\N	\N	\N	\N
019d44c4-d0b4-79b5-adb2-b89e08271ccf	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-03-31 18:40:42.358243	2026-03-31 18:40:42.358243	\N	SoundCodes Logo 1000 x 400 px Orange.png	venue_019d44c4-d0b4-79b5-adb2-b89e08271ccf.png	image/png	1000	400	\N	SoundCodes Logo	{}	\N	\N	\N	\N	\N
019d4883-a95b-7e05-9b93-fc12b2267865	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-04-01 12:08:01.328317	2026-04-01 12:08:17.316738	\N	461120632_903235038520949_4542890900643009370_n.jpg	venue_019d4883-a95b-7e05-9b93-fc12b2267865.jpg	image/jpeg	1168	1185	\N	\N	{}	\N	\N	\N	0.5064670712129405	0.48345960324495896
019d4a48-4755-73a2-a49b-b7c2ec603b19	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-04-01 20:22:24.026677	2026-04-01 20:22:24.026677	\N	0-Roads-to-Rome-1024x640.jpg	venue_019d4a48-4755-73a2-a49b-b7c2ec603b19.jpg	image/jpeg	1024	640	\N	\N	{}	\N	\N	\N	\N	\N
019d4a48-6250-7fc3-b9dd-69613aa628f9	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-04-01 20:22:30.947154	2026-04-01 20:22:30.947154	\N	386202150_865748518252978_2817582410512565382_n.jpg	venue_019d4a48-6250-7fc3-b9dd-69613aa628f9.jpg	image/jpeg	1080	1080	\N	\N	{}	\N	\N	\N	\N	\N
019d4a48-8b12-7813-a54c-d59a6d28f5fe	019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-04-01 20:22:41.384923	2026-04-01 20:22:41.384923	\N	440150458_10232966597371209_6433723719965907448_n.jpg	venue_019d4a48-8b12-7813-a54c-d59a6d28f5fe.jpg	image/jpeg	960	960	\N	\N	{}	\N	\N	\N	\N	\N
\.


--
-- TOC entry 5845 (class 0 OID 2351717)
-- Dependencies: 586
-- Data for Name: pluto_image_link; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.pluto_image_link (pluto_image_uuid, context, context_uuid, identifier) FROM stdin;
019d348a-e0e4-7466-99da-c3e0c9242b3f	organization	019d2eed-a25a-7caf-a762-a2a71917c6a1	dark_theme_logo
019d34a8-7fed-7ce8-a7ca-ef5abf112a45	organization	019d2eed-a25a-7caf-a762-a2a71917c6a1	light_theme_logo
019d3e1b-fffd-7312-a32c-fe0c3d344cb3	organization	019d35a0-3cd6-7c28-b3ca-537e8577defe	main_logo
019d3e24-b7a5-7f04-8139-fd2bbf8ff61e	organization	019d3e19-6c1c-7bf0-ad59-b1f15fb20c5c	main_logo
019d3e24-eeda-7b15-8c4b-202972f2a844	organization	019d3e19-6c1c-7bf0-ad59-b1f15fb20c5c	dark_theme_logo
019d3e25-1620-734d-a85d-668fe9925182	organization	019d3e19-6c1c-7bf0-ad59-b1f15fb20c5c	light_theme_logo
019d3e2e-1714-758b-bc5f-c48df7c380ce	organization	019d3e2d-5c6e-78df-9fbc-930adb904621	dark_theme_logo
019d3e2e-42b7-71b1-80b8-08c33ca0e3bc	organization	019d3e2d-5c6e-78df-9fbc-930adb904621	main_logo
019d3e4b-2eb4-73ea-9ed8-2026addc5cbd	venue	019d3e19-c044-75bf-820b-c96fd5fe07ee	dark_theme_logo
019d3e4b-50e2-7455-b70a-fbe78fb9aa90	venue	019d3e19-c044-75bf-820b-c96fd5fe07ee	light_theme_logo
019d3f58-f302-7792-a69c-15d12137aa98	organization	019d3f54-0db6-731f-8e18-03cb0c70b3fe	main_logo
019d3f59-5f80-74fa-b4cf-9d672a38bec8	organization	019d3f54-0db6-731f-8e18-03cb0c70b3fe	dark_theme_logo
019d3f59-7e7d-7ad9-bbd2-05bcfd81906a	organization	019d3f54-0db6-731f-8e18-03cb0c70b3fe	light_theme_logo
019d3f5e-5591-7e2e-a0b9-df1e93d61c1e	venue	019d3f5c-ba16-7c74-a7ba-533f26446ddf	main_logo
019d44c4-d0b4-79b5-adb2-b89e08271ccf	venue	019d358b-2946-7c2f-afc0-0cb0e8049f2f	main_logo
019d4883-a95b-7e05-9b93-fc12b2267865	venue	019d358b-2946-7c2f-afc0-0cb0e8049f2f	dark_theme_logo
019d4a48-4755-73a2-a49b-b7c2ec603b19	venue	019d3e19-c044-75bf-820b-c96fd5fe07ee	main_photo
019d4a48-6250-7fc3-b9dd-69613aa628f9	venue	019d3e19-c044-75bf-820b-c96fd5fe07ee	gallery_photo_1
019d4a48-8b12-7813-a54c-d59a6d28f5fe	venue	019d3e19-c044-75bf-820b-c96fd5fe07ee	gallery_photo_2
019d4a48-ab71-7c8d-8095-6019a9c26873	venue	019d3e19-c044-75bf-820b-c96fd5fe07ee	gallery_photo_3
019d5427-554d-7fd4-a73c-6fa70b6098f6	event	019d4e9a-aa28-7f7e-845f-252213276c53	main
\.


--
-- TOC entry 5806 (class 0 OID 2266135)
-- Dependencies: 545
-- Data for Name: price_type; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.price_type (type_id, iso_639_1, name) FROM stdin;
2	de	Kostenfrei
3	de	Spende
1	de	Normalpreis
0	de	Keine Angabe
0	da	Ingen oplysninger
0	en	Not specified
2	en	Free
2	da	Gratis
1	da	Normalpris
1	en	Regular price
3	da	Donation
3	en	Donation
4	de	Gestaffelte Preise
4	da	Trinpriser
4	en	Tiered prices
\.


--
-- TOC entry 5846 (class 0 OID 2351724)
-- Dependencies: 587
-- Data for Name: space; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.space (uuid, created_at, modified_at, venue_uuid, name, description, web_link, space_type, building_level, area_sqm, total_capacity, seating_capacity, accessibility_flags, accessibility_summary) FROM stdin;
019d44bb-5f99-74e6-9b61-257d8ba25e5b	2026-03-31 18:30:23.589696	\N	019d3f5c-ba16-7c74-a7ba-533f26446ddf	Saal	\N	\N	\N	\N	\N	\N	\N	\N	\N
019d44c0-64c0-79d7-ba1d-6e9a51da9742	2026-03-31 18:35:52.572644	\N	019d3f5c-ba16-7c74-a7ba-533f26446ddf	Biergarten	\N	\N	\N	\N	\N	\N	\N	\N	\N
019d44c0-87da-77ba-83ef-4ad7f42404fd	2026-03-31 18:36:01.626016	\N	019d3f5c-ba16-7c74-a7ba-533f26446ddf	Café	\N	\N	\N	\N	\N	\N	\N	\N	\N
019d44c6-26bf-77d5-a7ca-e82ddd099757	2026-03-31 18:42:09.930443	\N	019d3e19-c044-75bf-820b-c96fd5fe07ee	Info	\N	\N	\N	\N	\N	\N	\N	\N	\N
019d44c8-b482-75d0-811c-f71735246263	2026-03-31 18:44:57.341441	\N	019d3e19-c044-75bf-820b-c96fd5fe07ee	Serigrafi	\N	\N	\N	\N	\N	\N	\N	\N	\N
019d4925-9f75-75a2-a270-2fd2eae2bfdb	2026-04-01 15:04:55.668074	2026-04-01 15:06:57.661975	019d3e19-c044-75bf-820b-c96fd5fe07ee	Musik	Alle kan låne vores lydisolerede musikøvelokale. På ca. 16 m2 er der et trommesæt, keyboard, guitar, bas og lydanlæg med mikrofoner og højtalere. Andre instrumenter skal du selv medbrin­ge. Der er plads til ca. seks personer. Alle bands har faste øvetider. Som til alle lokaler, skal du også have kørekort til Musikværkstedet. Desuden vejleder vi dig gerne, hvis du vil planlægge en kon­cert eller en workshop.  \n  \nTo gange om året afholdes der et møde for alle musikere. Vi holder en hyggelig aften og drøfter forholdene vedrørende værkstedet, fælles inte­resser og fordeler faste øvetider.	\N	\N	\N	\N	\N	\N	\N	\N
019d44c6-4471-7e94-a8c4-c0975e844b1a	2026-03-31 18:42:17.583746	2026-04-01 15:07:07.966821	019d3e19-c044-75bf-820b-c96fd5fe07ee	RISO	I vores RISO værksted kan du trykke postkort, kalendere, illustrationer, foldere, visitkort, flyere og plakater, desuden kan RISO bruges til publikationer af enhver slags og kunstneriske produktioner på fint papir. Vores maskine kan printe både i A4 og A3-format og mindre. For tiden har vi 3 farver, der også kan kombineres: Fluo Pink, Blue og Yellow. Papiret kan gerne medbringes, men du kan også købe papiret i huset. De papirer, vi bruger, er ideelle til RISO. Du er også velkommen til at bruge værkstedet, hvis du har brug for en arbejdsplads, hvor du kan sidde i fred og ro eller hvis du vil bruge vores computere til både grafiske projekter eller filmredigering.	\N	\N	\N	\N	\N	\N	\N	\N
019d44c9-3ac2-751a-b218-dd88e00bea8f	2026-03-31 18:45:31.71199	2026-04-01 15:07:42.601779	019d3e19-c044-75bf-820b-c96fd5fe07ee	Trykkeri	I Trykkeriet er der mulighed for at designe logoer eller billeder i programmet Illustrator CC, skære dem i folier på en skæreplotter og trykke dem på stof efterfølgende. Både folier og varmepresser står til rådighed. Der kan også fås vejledning til forskellige projekter som fx Blå Bog eller layout af foldere, postkort og flyere. Derudover er der mulighed for at samle, skære, hæfte, spiralbinde og limbinde papir.	\N	\N	\N	\N	\N	\N	\N	\N
019d4925-da2c-7ca1-9921-155f80dbc590	2026-04-01 15:05:10.698181	2026-04-01 15:08:02.815307	019d3e19-c044-75bf-820b-c96fd5fe07ee	Træ	I Træværkstedet kan du primært fremstille, reparere og arbejde med projekter i træ. Det kan fx være en reol, et skærebræt, blomsterkasser, en opslagstavle eller også genstande i beton. Du kan høvle brædder, reparere din cykel eller dreje på drejebænken. Der er åben vejledning en gang om ugen og desuden emnerelaterede introduktioner hver anden/tredje uge.	\N	\N	\N	\N	\N	\N	\N	\N
019d5798-5948-78d5-a716-49c52278a5b4	2026-04-04 10:24:55.326258	\N	019d358b-2946-7c2f-afc0-0cb0e8049f2f	Gruppenraum	\N	\N	\N	\N	\N	\N	\N	\N	\N
019d4924-5882-78cb-8e59-0d32b2dcee08	2026-04-01 15:03:31.957224	2026-04-02 09:38:11.204688	019d3e19-c044-75bf-820b-c96fd5fe07ee	Aktiv Ro	Aktiv Ro er et rum, hvor du kan finde ro i hverdagen. Du kan dyrke yoga, meditere eller læse en bog, lave håndarbejde, danse alene til musik – rummet giver plads til mange muligheder. Der er en højtaler, du kan tilslutte din mobil til, der er yogamåtter, yogapuder, tæpper og klanginstrumenter.	\N	\N	\N	\N	\N	\N	263917200867359	\N
019d44c5-0efb-78d5-a4a6-7e49c6b548b7	2026-03-31 18:40:58.345742	2026-04-01 15:02:18.551145	019d358b-2946-7c2f-afc0-0cb0e8049f2f	Studio	Analoges(digitales Synthesizerstudio, 40 Kanal Mischpult und quadrophonischer Lautsprecheranlage.	\N	studio	0	20.00	6	4	\N	\N
019d44c6-83ac-7bfd-9ba9-ccfe074220c4	2026-03-31 18:42:33.771228	2026-04-01 15:05:56.815745	019d3e19-c044-75bf-820b-c96fd5fe07ee	Atelier	Atelieret har udstyr til forskellige teknikker og materialer, du kan bruge til at være kreativ med. Blandt andet er der en glasovn og materiale til glasarbejde, udstyr og værktøj til at lave smykker, fremstille glasperler, male og tegne, såvel som til at lave papirflet, filte eller farve garn. Der er også mulighed for at sy på symaskine. Aktivitetshuset tilbyder mange kurser på det kreative område, men du er også velkommen til at bruge Atelieret frit til egne projekter eller komme i vejledningstimerne og få hjælp.	\N	art_studio	1	\N	16	12	\N	\N
019d4924-9445-7b59-a0b0-a7ec6ad23657	2026-04-01 15:03:47.265326	2026-04-01 15:06:10.670784	019d3e19-c044-75bf-820b-c96fd5fe07ee	Foto	Når du har et kørekort til Foto har du mulighed for at låne fire forskellige digitale spejlreflekskameraer (Nikon D5000, Nikon D5100, Fuji X-T2) med forskellige objektiver og et blitzanlæg. Desuden kan du få individuel vejledning til fotoprojekter og fotoshootings. Det er muligt at afholde fotoshootings i Fotoværkstedet med lærreder i forskellige farver.	\N	\N	\N	\N	\N	\N	\N	\N
019d4924-e0f4-72f6-9723-bfebc756aeab	2026-04-01 15:04:06.898394	2026-04-01 15:06:27.476416	019d3e19-c044-75bf-820b-c96fd5fe07ee	Keramik	Aktivitetshusets værksted for Keramik ligger i Duborg-Skolens lerkælder. Når du står på skolens skolegård og vender dit ansigt mod den gamle hovedbygning, er der på venstre side en gennemgang. Her gå du ind og åbner den sidste dør til venstre. Så går du ned af trapperne og står allerede foran værkstedet!  \nLokalet er udstyret med forskellige arbejdsborde, fire drejeskiver, værktøj til arbejdet med ler, en stor vask og køkkenudstyr, så du også kan få en kop kaffe. Og selvfølgelig kan du finde ler her!	\N	\N	\N	\N	\N	\N	\N	\N
019d4925-223c-7c0b-9dbe-179743cf7761	2026-04-01 15:04:23.610408	2026-04-01 15:06:37.66351	019d3e19-c044-75bf-820b-c96fd5fe07ee	Lyd	Vi har et veludstyret lydstudie med professionel soft- og hardware, som kan bruges til forskellige lydprojekter - lige fra indtalte tekster og musik til båndoptagelser, du skal redigere. Du kan des­uden låne et digitalt portastudie med 16 spor og indbygget harddisk og cd-brænder.	\N	\N	\N	\N	\N	\N	\N	\N
019d4925-7c00-7745-a96c-31056cec9b2b	2026-04-01 15:04:46.590065	2026-04-01 15:06:46.878607	019d3e19-c044-75bf-820b-c96fd5fe07ee	Multimedia Studio	I vores Multimedia Studio er der uanede muligheder! Du kan producere din egen podcast, fotografere, filme og streame. Vi har det tekniske udstyr til at dække dit behov, når du vil komme og boltre dig i den multimediale verden. Vil du lære noget om at streame og vil gå i gang med Youtube/Twitch, eller vil du tage produktbilleder? Vi har den tekniske hardware og er glad for at kunne hjælpe med at vejlede dig i at bruge den.	\N	\N	\N	\N	\N	\N	\N	\N
\.


--
-- TOC entry 5815 (class 0 OID 2316967)
-- Dependencies: 554
-- Data for Name: space_feature; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.space_feature (category, key) FROM stdin;
audio	audio-acoustic-treatment
lighting	lighting-spotlights
environmental	environmental-eco-friendly
misc	misc-risers
lighting	lighting-decorative-lighting
presentation	presentation-video-conferencing
lighting	lighting-led-panels
misc	misc-backstage-rooms
misc	misc-stage
climate	climate-natural-ventilation
audio	audio-wireless-mircrophones
audio	audio-subwoofer
misc	misc-parking
presentation	presentation-podium
environmental	environmental-recyclable
environmental	environmental-water-saving
audio	audio-recording-capability
audio	audio-pa-system
environmental	environmental-led-lighting
presentation	presentation-projector
environmental	environmental-green-certification
audio	audio-wired-microphones
lighting	lighting-dimmable-lighting
audio	audio-mixing-desk
presentation	presentation-screen
misc	misc-wi-fi
climate	climate-air-conditioning
lighting	lighting-stage-lighting
environmental	environmental-solar-panels
misc	misc-catering
presentation	presentation-clicker-support
audio	audio-stage-monitors
climate	climate-ventilation
climate	climate-humidity-control
presentation	presentation-whiteboards
climate	climate-heating
presentation	presentation-flip-charts
\.


--
-- TOC entry 5816 (class 0 OID 2316993)
-- Dependencies: 555
-- Data for Name: space_feature_link; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.space_feature_link (space_id, key) FROM stdin;
\.


--
-- TOC entry 5817 (class 0 OID 2317010)
-- Dependencies: 556
-- Data for Name: space_type; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.space_type (key, schema_org) FROM stdin;
auditorium	Room
art_gallery	ArtGallery
art_studio	ArtGallery
cafe	FoodEstablishment
church	Church
community_hall	CivicStructure
courtyard	Place
exhibition_room	ExhibitionEvent
foyer	Room
garden	Garden
garage	Garage
hall	Hall
living_room	Room
multifunctional_room	Room
place	Place
playground	SportsActivityLocation
pub	FoodEstablishment
rehearsal_room	Room
restaurant	FoodEstablishment
sports_hall	SportsActivityLocation
tent	EventVenue
theater_hall	Theater
studio	Studio
workshop	Workshop
meeting_room	MeetingRoom
group_room	MeetingRoom
\.


--
-- TOC entry 5818 (class 0 OID 2317017)
-- Dependencies: 557
-- Data for Name: space_type_i18n; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.space_type_i18n (key, iso_639_1, name, description) FROM stdin;
auditorium	de	Vorlesungssaal	\N
auditorium	da	Forelæsningssal	\N
auditorium	en	Auditorium	\N
art_gallery	de	Galerie	\N
art_gallery	da	Galleri	\N
art_gallery	en	Gallery	\N
art_studio	de	Atelier	\N
art_studio	da	Atelier	\N
art_studio	en	Art Studio	\N
cafe	de	Café	\N
cafe	da	Café	\N
cafe	en	Café	\N
church	de	Kirche	\N
church	da	Kirke	\N
church	en	Church	\N
community_hall	de	Bürgerhalle	\N
community_hall	da	Borgerhal	\N
community_hall	en	Community Hall	\N
courtyard	de	Hof	\N
courtyard	da	Gård	\N
courtyard	en	Courtyard	\N
exhibition_room	de	Ausstellungsraum	\N
exhibition_room	da	Udstillingsrum	\N
exhibition_room	en	Exhibition Room	\N
foyer	de	Foyer	\N
foyer	da	Foyer	\N
foyer	en	Foyer	\N
garden	de	Garten	\N
garden	da	Have	\N
garden	en	Garden	\N
garage	de	Garage	\N
garage	da	Garage	\N
garage	en	Garage	\N
hall	en	Hall	\N
living_room	de	Wohnzimmer	\N
living_room	da	Stue	\N
living_room	en	Living Room	\N
multifunctional_room	de	Multifunktionsraum	\N
multifunctional_room	da	Multifunktionsrum	\N
multifunctional_room	en	Multifunctional Room	\N
place	de	Platz	\N
place	da	Plads	\N
place	en	Place	\N
playground	de	Sportplatz	\N
playground	da	Sportsplads	\N
playground	en	Sports Field	\N
pub	de	Kneipe	\N
pub	da	Bar	\N
pub	en	Pub	\N
rehearsal_room	de	Probenraum	\N
rehearsal_room	da	Øvelokale	\N
rehearsal_room	en	Rehearsal Room	\N
restaurant	de	Restaurant	\N
restaurant	da	Restaurant	\N
restaurant	en	Restaurant	\N
sports_hall	de	Sporthalle	\N
sports_hall	da	Sportshal	\N
sports_hall	en	Sports Hall	\N
tent	de	Zelt	\N
tent	en	Tent	\N
theater_hall	de	Theatersaal	\N
theater_hall	da	Teatersal	\N
theater_hall	en	Theater Hall	\N
studio	de	Studio	\N
studio	da	Studie	\N
studio	en	Studio	\N
workshop	de	Werkstatt	\N
workshop	da	Værksted	\N
workshop	en	Workshop	\N
meeting_room	da	Mødelokale	\N
meeting_room	de	Besprechungsraum	\N
meeting_room	en	Meeting Room	\N
group_room	da	Gruppelokale	\N
group_room	de	Gruppenraum	\N
group_room	en	Group Room	\N
tent	da	Telt	\N
hall	da	Sal	\N
hall	de	Saal	\N
\.


--
-- TOC entry 5807 (class 0 OID 2266155)
-- Dependencies: 546
-- Data for Name: state; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.state (code, country, name) FROM stdin;
BW	DEU	Baden-Württemberg
BY	DEU	Bayern
BE	DEU	Berlin
BB	DEU	Brandenburg
HB	DEU	Bremen
HH	DEU	Hamburg
HE	DEU	Hessen
MV	DEU	Mecklenburg-Vorpommern
NI	DEU	Niedersachsen
NW	DEU	Nordrhein-Westfalen
RP	DEU	Rheinland-Pfalz
SL	DEU	Saarland
SN	DEU	Sachsen
ST	DEU	Sachsen-Anhalt
SH	DEU	Schleswig-Holstein
TH	DEU	Thüringen
NJ	DNK	Region Nordjylland
MJ	DNK	Region Midtjylland
SD	DNK	Region Syddanmark
SJ	DNK	Region Sjælland
HS	DNK	Region Hovedstaden
\.


--
-- TOC entry 5808 (class 0 OID 2266160)
-- Dependencies: 547
-- Data for Name: system_email_template; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.system_email_template (id, context, iso_639_1, template, subject) FROM stdin;
2	reset-email	en	<!DOCTYPE html>\n<html lang="en">\n<head>\n  <meta charset="utf-8" />\n  <meta name="viewport" content="width=device-width,initial-scale=1" />\n  <title>Uranus — Reset Password</title>\n</head>\n<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial; background:#f6f7f9; margin:0; padding:20px;">\n  <table width="100%" cellpadding="0" cellspacing="0" role="presentation">\n    <tr>\n      <td align="center">\n        <table width="600" cellpadding="0" cellspacing="0" role="presentation" style="background:#ffffff; border-radius:8px; overflow:hidden; box-shadow:0 2px 6px rgba(0,0,0,0.06);">\n          <tr>\n            <td style="padding:20px 24px; text-align:left;">\n              \n              <!-- Header -->\n              <h1 style="margin:0 0 12px 0; font-size:20px; color:#111827;">Hello,</h1>\n\n              <!-- Intro -->\n              <p style="margin:0 0 18px 0; color:#374151; line-height:1.5;">\n                We received a request to reset the password for your <strong>Uranus</strong> account.\n              </p>\n\n              <!-- Action -->\n              <p style="margin:0 0 18px 0; color:#374151; line-height:1.5;">\n                Click the button below to reset your password:\n              </p>\n\n              <p style="margin:0 0 20px 0;">\n                <a href="{{link}}"\n                   style="display:inline-block; background-color:#1a73e8; color:#ffffff; padding:12px 20px; text-decoration:none; border-radius:6px; font-weight:600; box-shadow:0 2px 0 rgba(0,0,0,0.04);"\n                   target="_blank" rel="noopener noreferrer">\n                  Reset Password\n                </a>\n              </p>\n\n              <!-- Text link fallback -->\n              <p style="margin:0 0 16px 0; color:#6b7280; font-size:14px;">\n                If the button does not work, copy this link into your browser:<br/>\n                <a href="{{link}}" style="color:#1a73e8; word-break:break-all;">{{link}}</a>\n              </p>\n\n              <!-- Optional expiry -->\n              <p style="margin:0 0 18px 0; color:#6b7280; font-size:13px;">\n                This link will expire in <strong>{{expiry_hours}}</strong> hour(s).\n              </p>\n\n              <!-- Security note -->\n              <p style="margin:0 0 22px 0; color:#374151; line-height:1.5;">\n                If you did not request a password reset, you can safely ignore this email. Your password will remain unchanged.\n              </p>\n\n              <p style="margin:0 0 8px 0; color:#374151;">\n                Thanks,<br/>\n                <strong>The Uranus Team</strong><br/>\n                <a href="https://uranus.oklabflensburg.de" style="color:#1a73e8; text-decoration:none;">uranus.oklabflensburg.de</a>\n              </p>\n\n              <hr style="border:none; border-top:1px solid #eef2f6; margin:20px 0;" />\n\n              <!-- Footer / legal -->\n              <p style="margin:0 0 4px 0; font-size:12px; color:#9ca3af;">\n                DatenSindDaten e. V., Friesische Straße 41, 24937 Flensburg\n              </p>\n              <p style="margin:0 0 8px 0; font-size:12px; color:#9ca3af;">\n                <a href="https://uranus.oklabflensburg.de/privacy" style="color:#9ca3af; text-decoration:underline;">Privacy</a>\n                &nbsp;|&nbsp;\n                <a href="https://uranus.oklabflensburg.de/imprint" style="color:#9ca3af; text-decoration:underline;">Imprint</a>\n              </p>\n\n            </td>\n          </tr>\n        </table>\n\n        <!-- Small disclaimer below the card -->\n        <table width="600" cellpadding="0" cellspacing="0" role="presentation" style="margin-top:12px;">\n          <tr>\n            <td style="text-align:center; font-size:12px; color:#9ca3af;">\n              <span>© DatenSindDaten e. V.</span>\n            </td>\n          </tr>\n        </table>\n      </td>\n    </tr>\n  </table>\n</body>\n</html>	Reset your Uranus account password
1	activate-email	de	<!DOCTYPE html>\n<html lang="de">\n<head>\n  <meta charset="utf-8" />\n  <meta name="viewport" content="width=device-width,initial-scale=1" />\n  <title>Uranus — E-Mail bestätigen</title>\n</head>\n<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial; background:#f6f7f9; margin:0; padding:20px;">\n  <table width="100%" cellpadding="0" cellspacing="0" role="presentation">\n    <tr>\n      <td align="center">\n        <table width="600" cellpadding="0" cellspacing="0" role="presentation" style="background:#ffffff; border-radius:8px; overflow:hidden; box-shadow:0 2px 6px rgba(0,0,0,0.06);">\n          <tr>\n            <td style="padding:20px 24px; text-align:left;">\n              <!-- Header -->\n              <h1 style="margin:0 0 12px 0; font-size:20px; color:#111827;">Hallo,</h1>\n\n              <!-- Intro -->\n              <p style="margin:0 0 18px 0; color:#374151; line-height:1.5;">\n                vielen Dank für deine Registrierung bei <strong>Uranus</strong>!\n              </p>\n\n              <!-- Action -->\n              <p style="margin:0 0 18px 0; color:#374151; line-height:1.5;">\n                Bitte bestätige deine E-Mail-Adresse, um dein Konto zu aktivieren:\n              </p>\n\n              <p style="margin:0 0 20px 0;">\n                <a href="{{link}}"\n                   style="display:inline-block; background-color:#1a73e8; color:#ffffff; padding:12px 20px; text-decoration:none; border-radius:6px; font-weight:600; box-shadow:0 2px 0 rgba(0,0,0,0.04);"\n                   target="_blank" rel="noopener noreferrer">\n                  Konto aktivieren\n                </a>\n              </p>\n\n              <!-- Text link fallback -->\n              <p style="margin:0 0 16px 0; color:#6b7280; font-size:14px;">\n                Falls der Button nicht funktioniert, kopiere diesen Link in deinen Browser:<br/>\n                <a href="{{link}}" style="color:#1a73e8; word-break:break-all;">{{link}}</a>\n              </p>\n\n              <!-- Optional expiry -->\n              <p style="margin:0 0 18px 0; color:#6b7280; font-size:13px;">\n                Dieser Link ist <strong>zeitlich begrenzt</strong> (z. B. {{expiry_hours}} Stunden).\n              </p>\n\n              <!-- Security note -->\n              <p style="margin:0 0 22px 0; color:#374151; line-height:1.5;">\n                Falls du dich nicht bei Uranus registriert hast, kannst du diese Nachricht einfach ignorieren.\n              </p>\n\n              <p style="margin:0 0 8px 0; color:#374151;">\n                Viele Grüße<br/>\n                <strong>Dein Uranus-Team</strong><br/>\n                <a href="https://uranus.oklabflensburg.de" style="color:#1a73e8; text-decoration:none;">uranus.oklabflensburg.de</a>\n              </p>\n\n              <hr style="border:none; border-top:1px solid #eef2f6; margin:20px 0;" />\n\n              <!-- Footer / legal -->\n              <p style="margin:0 0 4px 0; font-size:12px; color:#9ca3af;">\n                DatenSindDaten e. V., Friesische Straße 41, 24937 Flensburg\n              </p>\n              <p style="margin:0 0 8px 0; font-size:12px; color:#9ca3af;">\n                <a href="https://uranus.oklabflensburg.de/privacy" style="color:#9ca3af; text-decoration:underline;">Datenschutz</a>\n                &nbsp;|&nbsp;\n                <a href="https://uranus.oklabflensburg.de/imprint" style="color:#9ca3af; text-decoration:underline;">Impressum</a>\n              </p>\n\n            </td>\n          </tr>\n        </table>\n\n        <!-- Small disclaimer below the card -->\n        <table width="600" cellpadding="0" cellspacing="0" role="presentation" style="margin-top:12px;">\n          <tr>\n            <td style="text-align:center; font-size:12px; color:#9ca3af;">\n              <span>© DatenSindDaten e. V.</span>\n            </td>\n          </tr>\n        </table>\n      </td>\n    </tr>\n  </table>\n</body>\n</html>	Willkommen bei Uranus – bestätige deine E-Mail-Adresse
5	activate-email	da	<!DOCTYPE html>\n<html lang="da">\n<head>\n  <meta charset="utf-8" />\n  <meta name="viewport" content="width=device-width,initial-scale=1" />\n  <title>Uranus — Bekræft din e-mailadresse</title>\n</head>\n<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial; background:#f6f7f9; margin:0; padding:20px;">\n  <table width="100%" cellpadding="0" cellspacing="0" role="presentation">\n    <tr>\n      <td align="center">\n        <table width="600" cellpadding="0" cellspacing="0" role="presentation" style="background:#ffffff; border-radius:8px; overflow:hidden; box-shadow:0 2px 6px rgba(0,0,0,0.06);">\n          <tr>\n            <td style="padding:20px 24px; text-align:left;">\n              <h1 style="margin:0 0 12px 0; font-size:20px; color:#111827;">Hej,</h1>\n\n              <p style="margin:0 0 18px 0; color:#374151; line-height:1.5;">\n                Tak fordi du har registreret dig hos <strong>Uranus</strong>!\n              </p>\n\n              <p style="margin:0 0 18px 0; color:#374151; line-height:1.5;">\n                Bekræft venligst din e-mailadresse for at aktivere din konto:\n              </p>\n\n              <p style="margin:0 0 20px 0;">\n                <a href="{{link}}"\n                   style="display:inline-block; background-color:#1a73e8; color:#ffffff; padding:12px 20px; text-decoration:none; border-radius:6px; font-weight:600; box-shadow:0 2px 0 rgba(0,0,0,0.04);"\n                   target="_blank" rel="noopener noreferrer">\n                  Aktiver konto\n                </a>\n              </p>\n\n              <p style="margin:0 0 16px 0; color:#6b7280; font-size:14px;">\n                Hvis knappen ikke virker, kan du kopiere dette link og indsætte det i din browser:<br/>\n                <a href="{{link}}" style="color:#1a73e8; word-break:break-all;">{{link}}</a>\n              </p>\n\n              <p style="margin:0 0 18px 0; color:#6b7280; font-size:13px;">\n                Dette link er <strong>tidsbegrænset</strong> (f.eks. {{expiry_hours}} timer).\n              </p>\n\n              <p style="margin:0 0 22px 0; color:#374151; line-height:1.5;">\n                Hvis du ikke har registreret dig hos Uranus, kan du blot ignorere denne besked.\n              </p>\n\n              <p style="margin:0 0 8px 0; color:#374151;">\n                Venlig hilsen<br/>\n                <strong>Uranus-teamet</strong><br/>\n                <a href="https://uranus.oklabflensburg.de" style="color:#1a73e8; text-decoration:none;">uranus.oklabflensburg.de</a>\n              </p>\n\n              <hr style="border:none; border-top:1px solid #eef2f6; margin:20px 0;" />\n\n              <p style="margin:0 0 4px 0; font-size:12px; color:#9ca3af;">\n                DatenSindDaten e. V., Friesische Straße 41, 24937 Flensburg\n              </p>\n              <p style="margin:0 0 8px 0; font-size:12px; color:#9ca3af;">\n                <a href="https://uranus.oklabflensburg.de/privacy" style="color:#9ca3af; text-decoration:underline;">Databeskyttelse</a>\n                &nbsp;|&nbsp;\n                <a href="https://uranus.oklabflensburg.de/imprint" style="color:#9ca3af; text-decoration:underline;">Impressum</a>\n              </p>\n\n            </td>\n          </tr>\n        </table>\n\n        <table width="600" cellpadding="0" cellspacing="0" role="presentation" style="margin-top:12px;">\n          <tr>\n            <td style="text-align:center; font-size:12px; color:#9ca3af;">\n              <span>© DatenSindDaten e. V.</span>\n            </td>\n          </tr>\n        </table>\n      </td>\n    </tr>\n  </table>\n</body>\n</html>	Velkommen til Uranus – bekræft din e-mailadresse
6	activate-email	en	<!DOCTYPE html>\n<html lang="en">\n<head>\n  <meta charset="utf-8" />\n  <meta name="viewport" content="width=device-width,initial-scale=1" />\n  <title>Uranus — Confirm your email address</title>\n</head>\n<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial; background:#f6f7f9; margin:0; padding:20px;">\n  <table width="100%" cellpadding="0" cellspacing="0" role="presentation">\n    <tr>\n      <td align="center">\n        <table width="600" cellpadding="0" cellspacing="0" role="presentation" style="background:#ffffff; border-radius:8px; overflow:hidden; box-shadow:0 2px 6px rgba(0,0,0,0.06);">\n          <tr>\n            <td style="padding:20px 24px; text-align:left;">\n              <h1 style="margin:0 0 12px 0; font-size:20px; color:#111827;">Hello,</h1>\n\n              <p style="margin:0 0 18px 0; color:#374151; line-height:1.5;">\n                Thank you for registering with <strong>Uranus</strong>!\n              </p>\n\n              <p style="margin:0 0 18px 0; color:#374151; line-height:1.5;">\n                Please confirm your email address to activate your account:\n              </p>\n\n              <p style="margin:0 0 20px 0;">\n                <a href="{{link}}"\n                   style="display:inline-block; background-color:#1a73e8; color:#ffffff; padding:12px 20px; text-decoration:none; border-radius:6px; font-weight:600; box-shadow:0 2px 0 rgba(0,0,0,0.04);"\n                   target="_blank" rel="noopener noreferrer">\n                  Activate account\n                </a>\n              </p>\n\n              <p style="margin:0 0 16px 0; color:#6b7280; font-size:14px;">\n                If the button doesn’t work, copy and paste this link into your browser:<br/>\n                <a href="{{link}}" style="color:#1a73e8; word-break:break-all;">{{link}}</a>\n              </p>\n\n              <p style="margin:0 0 18px 0; color:#6b7280; font-size:13px;">\n                This link is <strong>time-limited</strong> (e.g. {{expiry_hours}} hours).\n              </p>\n\n              <p style="margin:0 0 22px 0; color:#374151; line-height:1.5;">\n                If you did not register with Uranus, you can safely ignore this message.\n              </p>\n\n              <p style="margin:0 0 8px 0; color:#374151;">\n                Kind regards,<br/>\n                <strong>The Uranus Team</strong><br/>\n                <a href="https://uranus.oklabflensburg.de" style="color:#1a73e8; text-decoration:none;">uranus.oklabflensburg.de</a>\n              </p>\n\n              <hr style="border:none; border-top:1px solid #eef2f6; margin:20px 0;" />\n\n              <p style="margin:0 0 4px 0; font-size:12px; color:#9ca3af;">\n                DatenSindDaten e. V., Friesische Straße 41, 24937 Flensburg\n              </p>\n              <p style="margin:0 0 8px 0; font-size:12px; color:#9ca3af;">\n                <a href="https://uranus.oklabflensburg.de/privacy" style="color:#9ca3af; text-decoration:underline;">Privacy Policy</a>\n                &nbsp;|&nbsp;\n                <a href="https://uranus.oklabflensburg.de/imprint" style="color:#9ca3af; text-decoration:underline;">Imprint</a>\n              </p>\n\n            </td>\n          </tr>\n        </table>\n\n        <table width="600" cellpadding="0" cellspacing="0" role="presentation" style="margin-top:12px;">\n          <tr>\n            <td style="text-align:center; font-size:12px; color:#9ca3af;">\n              <span>© DatenSindDaten e. V.</span>\n            </td>\n          </tr>\n        </table>\n      </td>\n    </tr>\n  </table>\n</body>\n</html>	Welcome to Uranus – please verify your email address
7	reset-email	de	<!DOCTYPE html>\n<html lang="de">\n<head>\n  <meta charset="utf-8" />\n  <meta name="viewport" content="width=device-width,initial-scale=1" />\n  <title>Uranus — Passwort zurücksetzen</title>\n</head>\n<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial; background:#f6f7f9; margin:0; padding:20px;">\n  <table width="100%" cellpadding="0" cellspacing="0" role="presentation">\n    <tr>\n      <td align="center">\n        <table width="600" cellpadding="0" cellspacing="0" role="presentation" style="background:#ffffff; border-radius:8px; overflow:hidden; box-shadow:0 2px 6px rgba(0,0,0,0.06);">\n          <tr>\n            <td style="padding:20px 24px; text-align:left;">\n              \n              <h1 style="margin:0 0 12px 0; font-size:20px; color:#111827;">Hallo,</h1>\n\n              <p style="margin:0 0 18px 0; color:#374151; line-height:1.5;">\n                Wir haben eine Anfrage erhalten, das Passwort für dein <strong>Uranus</strong>-Konto zurückzusetzen.\n              </p>\n\n              <p style="margin:0 0 18px 0; color:#374151; line-height:1.5;">\n                Klicke auf den Button unten, um dein Passwort zurückzusetzen:\n              </p>\n\n              <p style="margin:0 0 20px 0;">\n                <a href="{{link}}"\n                   style="display:inline-block; background-color:#1a73e8; color:#ffffff; padding:12px 20px; text-decoration:none; border-radius:6px; font-weight:600; box-shadow:0 2px 0 rgba(0,0,0,0.04);"\n                   target="_blank" rel="noopener noreferrer">\n                  Passwort zurücksetzen\n                </a>\n              </p>\n\n              <p style="margin:0 0 16px 0; color:#6b7280; font-size:14px;">\n                Falls der Button nicht funktioniert, kopiere diesen Link in deinen Browser:<br/>\n                <a href="{{link}}" style="color:#1a73e8; word-break:break-all;">{{link}}</a>\n              </p>\n\n              <p style="margin:0 0 18px 0; color:#6b7280; font-size:13px;">\n                Dieser Link ist <strong>zeitlich begrenzt</strong> (z. B. {{expiry_hours}} Stunden).\n              </p>\n\n              <p style="margin:0 0 22px 0; color:#374151; line-height:1.5;">\n                Falls du diese Anfrage nicht gestellt hast, kannst du diese E-Mail einfach ignorieren. Dein Passwort bleibt unverändert.\n              </p>\n\n              <p style="margin:0 0 8px 0; color:#374151;">\n                Viele Grüße,<br/>\n                <strong>Dein Uranus-Team</strong><br/>\n                <a href="https://uranus.oklabflensburg.de" style="color:#1a73e8; text-decoration:none;">uranus.oklabflensburg.de</a>\n              </p>\n\n              <hr style="border:none; border-top:1px solid #eef2f6; margin:20px 0;" />\n\n              <p style="margin:0 0 4px 0; font-size:12px; color:#9ca3af;">\n                DatenSindDaten e. V., Friesische Straße 41, 24937 Flensburg\n              </p>\n              <p style="margin:0 0 8px 0; font-size:12px; color:#9ca3af;">\n                <a href="https://uranus.oklabflensburg.de/privacy" style="color:#9ca3af; text-decoration:underline;">Datenschutz</a>\n                &nbsp;|&nbsp;\n                <a href="https://uranus.oklabflensburg.de/imprint" style="color:#9ca3af; text-decoration:underline;">Impressum</a>\n              </p>\n\n            </td>\n          </tr>\n        </table>\n\n        <table width="600" cellpadding="0" cellspacing="0" role="presentation" style="margin-top:12px;">\n          <tr>\n            <td style="text-align:center; font-size:12px; color:#9ca3af;">\n              <span>© DatenSindDaten e. V.</span>\n            </td>\n          </tr>\n        </table>\n      </td>\n    </tr>\n  </table>\n</body>\n</html>	Setze dein Uranus-Konto-Passwort zurück
8	reset-email	da	<!DOCTYPE html>\n<html lang="da">\n<head>\n  <meta charset="utf-8" />\n  <meta name="viewport" content="width=device-width,initial-scale=1" />\n  <title>Uranus — Nulstil adgangskode</title>\n</head>\n<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial; background:#f6f7f9; margin:0; padding:20px;">\n  <table width="100%" cellpadding="0" cellspacing="0" role="presentation">\n    <tr>\n      <td align="center">\n        <table width="600" cellpadding="0" cellspacing="0" role="presentation" style="background:#ffffff; border-radius:8px; overflow:hidden; box-shadow:0 2px 6px rgba(0,0,0,0.06);">\n          <tr>\n            <td style="padding:20px 24px; text-align:left;">\n              \n              <h1 style="margin:0 0 12px 0; font-size:20px; color:#111827;">Hej,</h1>\n\n              <p style="margin:0 0 18px 0; color:#374151; line-height:1.5;">\n                Vi har modtaget en anmodning om at nulstille adgangskoden for din <strong>Uranus</strong>-konto.\n              </p>\n\n              <p style="margin:0 0 18px 0; color:#374151; line-height:1.5;">\n                Klik på knappen nedenfor for at nulstille din adgangskode:\n              </p>\n\n              <p style="margin:0 0 20px 0;">\n                <a href="{{link}}"\n                   style="display:inline-block; background-color:#1a73e8; color:#ffffff; padding:12px 20px; text-decoration:none; border-radius:6px; font-weight:600; box-shadow:0 2px 0 rgba(0,0,0,0.04);"\n                   target="_blank" rel="noopener noreferrer">\n                  Nulstil adgangskode\n                </a>\n              </p>\n\n              <p style="margin:0 0 16px 0; color:#6b7280; font-size:14px;">\n                Hvis knappen ikke virker, kopier dette link ind i din browser:<br/>\n                <a href="{{link}}" style="color:#1a73e8; word-break:break-all;">{{link}}</a>\n              </p>\n\n              <p style="margin:0 0 18px 0; color:#6b7280; font-size:13px;">\n                Dette link udløber om <strong>{{expiry_hours}}</strong> time(r).\n              </p>\n\n              <p style="margin:0 0 22px 0; color:#374151; line-height:1.5;">\n                Hvis du ikke har anmodet om at nulstille adgangskoden, kan du trygt ignorere denne e-mail. Din adgangskode forbliver uændret.\n              </p>\n\n              <p style="margin:0 0 8px 0; color:#374151;">\n                Med venlig hilsen,<br/>\n                <strong>Uranus-teamet</strong><br/>\n                <a href="https://uranus.oklabflensburg.de" style="color:#1a73e8; text-decoration:none;">uranus.oklabflensburg.de</a>\n              </p>\n\n              <hr style="border:none; border-top:1px solid #eef2f6; margin:20px 0;" />\n\n              <p style="margin:0 0 4px 0; font-size:12px; color:#9ca3af;">\n                DatenSindDaten e. V., Friesische Straße 41, 24937 Flensburg\n              </p>\n              <p style="margin:0 0 8px 0; font-size:12px; color:#9ca3af;">\n                <a href="https://uranus.oklabflensburg.de/privacy" style="color:#9ca3af; text-decoration:underline;">Privatlivspolitik</a>\n                &nbsp;|&nbsp;\n                <a href="https://uranus.oklabflensburg.de/imprint" style="color:#9ca3af; text-decoration:underline;">Impressum</a>\n              </p>\n\n            </td>\n          </tr>\n        </table>\n\n        <table width="600" cellpadding="0" cellspacing="0" role="presentation" style="margin-top:12px;">\n          <tr>\n            <td style="text-align:center; font-size:12px; color:#9ca3af;">\n              <span>© DatenSindDaten e. V.</span>\n            </td>\n          </tr>\n        </table>\n      </td>\n    </tr>\n  </table>\n</body>\n</html>	Nulstil din Uranus-konto-adgangskode
11	team-invite-email	en	<!DOCTYPE html>\n<html lang="en">\n<head>\n  <meta charset="utf-8" />\n  <meta name="viewport" content="width=device-width,initial-scale=1" />\n  <title>Uranus — Team Invitation</title>\n</head>\n<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial; background:#f6f7f9; margin:0; padding:20px;">\n  <table width="100%" cellpadding="0" cellspacing="0" role="presentation">\n    <tr>\n      <td align="center">\n        <table width="600" cellpadding="0" cellspacing="0" role="presentation" style="background:#ffffff; border-radius:8px; overflow:hidden; box-shadow:0 2px 6px rgba(0,0,0,0.06);">\n          <tr>\n            <td style="padding:20px 24px; text-align:left;">\n              <h1 style="margin:0 0 12px 0; font-size:20px; color:#111827;">Hello {{display_name}},</h1>\n\n              <p style="margin:0 0 18px 0; color:#374151; line-height:1.5;">\n                You have been invited to join the team of the organizer <strong>{{organizer_name}}</strong>.\n              </p>\n\n              <p style="margin:0 0 20px 0;">\n                <a href="{{invite_link}}"\n                   style="display:inline-block; background-color:#1a73e8; color:#ffffff; padding:12px 20px; text-decoration:none; border-radius:6px; font-weight:600; box-shadow:0 2px 0 rgba(0,0,0,0.04);"\n                   target="_blank" rel="noopener noreferrer">\n                  Accept Invitation\n                </a>\n              </p>\n\n              <p style="margin:0 0 16px 0; color:#6b7280; font-size:14px;">\n                If the button does not work, copy this link into your browser:<br/>\n                <a href="{{invite_link}}" style="color:#1a73e8; word-break:break-all;">{{invite_link}}</a>\n              </p>\n\n              <p style="margin:0 0 18px 0; color:#6b7280; font-size:13px;">\n                This link is <strong>time-limited</strong> (e.g. {{expiry_hours}} hours).\n              </p>\n\n              <p style="margin:0 0 22px 0; color:#374151; line-height:1.5;">\n                If you did not request this invitation, you can safely ignore this message.\n              </p>\n\n              <p style="margin:0 0 8px 0; color:#374151;">\n                Best regards,<br/>\n                <strong>Your Uranus Team</strong><br/>\n                <a href="https://uranus.oklabflensburg.de" style="color:#1a73e8; text-decoration:none;">uranus.oklabflensburg.de</a>\n              </p>\n\n              <hr style="border:none; border-top:1px solid #eef2f6; margin:20px 0;" />\n\n              <p style="margin:0 0 4px 0; font-size:12px; color:#9ca3af;">\n                DatenSindDaten e. V., Friesische Straße 41, 24937 Flensburg\n              </p>\n              <p style="margin:0 0 8px 0; font-size:12px; color:#9ca3af;">\n                <a href="https://uranus.oklabflensburg.de/privacy" style="color:#9ca3af; text-decoration:underline;">Privacy</a>\n                &nbsp;|&nbsp;\n                <a href="https://uranus.oklabflensburg.de/imprint" style="color:#9ca3af; text-decoration:underline;">Imprint</a>\n              </p>\n\n            </td>\n          </tr>\n        </table>\n\n        <table width="600" cellpadding="0" cellspacing="0" role="presentation" style="margin-top:12px;">\n          <tr>\n            <td style="text-align:center; font-size:12px; color:#9ca3af;">\n              <span>© DatenSindDaten e. V.</span>\n            </td>\n          </tr>\n        </table>\n      </td>\n    </tr>\n  </table>\n</body>\n</html>	Welcome to Uranus – Team Invitation
10	team-invite-email	da	<!DOCTYPE html>\n<html lang="da">\n<head>\n  <meta charset="utf-8" />\n  <meta name="viewport" content="width=device-width,initial-scale=1" />\n  <title>Uranus — Team-invitation</title>\n</head>\n<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial; background:#f6f7f9; margin:0; padding:20px;">\n  <table width="100%" cellpadding="0" cellspacing="0" role="presentation">\n    <tr>\n      <td align="center">\n        <table width="600" cellpadding="0" cellspacing="0" role="presentation" style="background:#ffffff; border-radius:8px; overflow:hidden; box-shadow:0 2px 6px rgba(0,0,0,0.06);">\n          <tr>\n            <td style="padding:20px 24px; text-align:left;">\n              <h1 style="margin:0 0 12px 0; font-size:20px; color:#111827;">Hej {{display_name}},</h1>\n\n              <p style="margin:0 0 18px 0; color:#374151; line-height:1.5;">\n                Du er blevet inviteret til teamet hos arrangøren <strong>{{organizer_name}}</strong>.\n              </p>\n\n              <p style="margin:0 0 20px 0;">\n                <a href="{{invite_link}}"\n                   style="display:inline-block; background-color:#1a73e8; color:#ffffff; padding:12px 20px; text-decoration:none; border-radius:6px; font-weight:600; box-shadow:0 2px 0 rgba(0,0,0,0.04);"\n                   target="_blank" rel="noopener noreferrer">\n                  Accepter invitation\n                </a>\n              </p>\n\n              <p style="margin:0 0 16px 0; color:#6b7280; font-size:14px;">\n                Hvis knappen ikke virker, kopier linket ind i din browser:<br/>\n                <a href="{{invite_link}}" style="color:#1a73e8; word-break:break-all;">{{invite_link}}</a>\n              </p>\n\n              <p style="margin:0 0 18px 0; color:#6b7280; font-size:13px;">\n                Dette link er <strong>tidsbegrænset</strong> (f.eks. {{expiry_hours}} timer).\n              </p>\n\n              <p style="margin:0 0 22px 0; color:#374151; line-height:1.5;">\n                Hvis du ikke har bedt om denne invitation, kan du ignorere denne besked.\n              </p>\n\n              <p style="margin:0 0 8px 0; color:#374151;">\n                Venlig hilsen<br/>\n                <strong>Dit Uranus-team</strong><br/>\n                <a href="https://uranus.oklabflensburg.de" style="color:#1a73e8; text-decoration:none;">uranus.oklabflensburg.de</a>\n              </p>\n\n              <hr style="border:none; border-top:1px solid #eef2f6; margin:20px 0;" />\n\n              <p style="margin:0 0 4px 0; font-size:12px; color:#9ca3af;">\n                DatenSindDaten e. V., Friesische Straße 41, 24937 Flensburg\n              </p>\n              <p style="margin:0 0 8px 0; font-size:12px; color:#9ca3af;">\n                <a href="https://uranus.oklabflensburg.de/privacy" style="color:#9ca3af; text-decoration:underline;">Privatlivspolitik</a>\n                &nbsp;|&nbsp;\n                <a href="https://uranus.oklabflensburg.de/imprint" style="color:#9ca3af; text-decoration:underline;">Impressum</a>\n              </p>\n\n            </td>\n          </tr>\n        </table>\n\n        <table width="600" cellpadding="0" cellspacing="0" role="presentation" style="margin-top:12px;">\n          <tr>\n            <td style="text-align:center; font-size:12px; color:#9ca3af;">\n              <span>© DatenSindDaten e. V.</span>\n            </td>\n          </tr>\n        </table>\n      </td>\n    </tr>\n  </table>\n</body>\n</html>	Velkommen til Uranus – invitation til teamet
9	team-invite-email	de	<!DOCTYPE html>\n<html lang="de">\n<head>\n  <meta charset="utf-8" />\n  <meta name="viewport" content="width=device-width,initial-scale=1" />\n  <title>Uranus — Team-Einladung</title>\n</head>\n<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial; background:#f6f7f9; margin:0; padding:20px;">\n  <table width="100%" cellpadding="0" cellspacing="0" role="presentation">\n    <tr>\n      <td align="center">\n        <table width="600" cellpadding="0" cellspacing="0" role="presentation" style="background:#ffffff; border-radius:8px; overflow:hidden; box-shadow:0 2px 6px rgba(0,0,0,0.06);">\n          <tr>\n            <td style="padding:20px 24px; text-align:left;">\n              <!-- Header -->\n              <h1 style="margin:0 0 12px 0; font-size:20px; color:#111827;">Hallo {{display_name}},</h1>\n\n              <!-- Intro -->\n              <p style="margin:0 0 18px 0; color:#374151; line-height:1.5;">\n                Du wurdest zum Team des Veranstalters <strong>{{organizer_name}}</strong> eingeladen.\n              </p>\n\n              <!-- Action button -->\n              <p style="margin:0 0 20px 0;">\n                <a href="{{invite_link}}"\n                   style="display:inline-block; background-color:#1a73e8; color:#ffffff; padding:12px 20px; text-decoration:none; border-radius:6px; font-weight:600; box-shadow:0 2px 0 rgba(0,0,0,0.04);"\n                   target="_blank" rel="noopener noreferrer">\n                  Einladung annehmen\n                </a>\n              </p>\n\n              <!-- Text link fallback -->\n              <p style="margin:0 0 16px 0; color:#6b7280; font-size:14px;">\n                Falls der Button nicht funktioniert, kopiere diesen Link in deinen Browser:<br/>\n                <a href="{{invite_link}}" style="color:#1a73e8; word-break:break-all;">{{invite_link}}</a>\n              </p>\n\n              <!-- Optional expiry -->\n              <p style="margin:0 0 18px 0; color:#6b7280; font-size:13px;">\n                Dieser Link ist <strong>zeitlich begrenzt</strong> (z. B. {{expiry_hours}} Stunden).\n              </p>\n\n              <!-- Security note -->\n              <p style="margin:0 0 22px 0; color:#374151; line-height:1.5;">\n                Falls du diese Einladung nicht angefordert hast, kannst du diese Nachricht einfach ignorieren.\n              </p>\n\n              <p style="margin:0 0 8px 0; color:#374151;">\n                Viele Grüße<br/>\n                <strong>Dein Uranus-Team</strong><br/>\n                <a href="https://uranus.oklabflensburg.de" style="color:#1a73e8; text-decoration:none;">uranus.oklabflensburg.de</a>\n              </p>\n\n              <hr style="border:none; border-top:1px solid #eef2f6; margin:20px 0;" />\n\n              <!-- Footer / legal -->\n              <p style="margin:0 0 4px 0; font-size:12px; color:#9ca3af;">\n                DatenSindDaten e. V., Friesische Straße 41, 24937 Flensburg\n              </p>\n              <p style="margin:0 0 8px 0; font-size:12px; color:#9ca3af;">\n                <a href="https://uranus.oklabflensburg.de/privacy" style="color:#9ca3af; text-decoration:underline;">Datenschutz</a>\n                &nbsp;|&nbsp;\n                <a href="https://uranus.oklabflensburg.de/imprint" style="color:#9ca3af; text-decoration:underline;">Impressum</a>\n              </p>\n\n            </td>\n          </tr>\n        </table>\n\n        <!-- Small disclaimer below the card -->\n        <table width="600" cellpadding="0" cellspacing="0" role="presentation" style="margin-top:12px;">\n          <tr>\n            <td style="text-align:center; font-size:12px; color:#9ca3af;">\n              <span>© DatenSindDaten e. V.</span>\n            </td>\n          </tr>\n        </table>\n      </td>\n    </tr>\n  </table>\n</body>\n</html>	Willkommen bei Uranus – Einladung ins Team
\.


--
-- TOC entry 5810 (class 0 OID 2266166)
-- Dependencies: 549
-- Data for Name: team_member_role; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.team_member_role (type_id, name, iso_639_1, description) FROM stdin;
3	venue manager	en	Manages venues, spaces, and bookings
4	rumleder	da	Styrer individuelle rum inden for et sted
2	Administrator	de	Verwalten von Benutzern, Rollen und Systemeinstellungen
5	Veranstaltungsleiter	de	Plant, erstellt und verwaltet Veranstaltungen
2	administrator	da	Administrerer brugere, roller og systemindstillinger
7	insight viewer	en	Can view statistics and reports
1	Eigentümer	de	Volle Kontrolle über die Organisation und deren Einstellungen
1	owner	en	Full control over the organization and its settings
8	partner	da	Ekstern samarbejdspartner med begrænset adgang
2	administrator	en	Manages users, roles, and system settings
5	event manager	en	Plans, creates, and manages events
3	Standortleiter	de	Verwalten von Veranstaltungsorten, Räumen und Buchungen
5	eventchef	da	Planlægger, opretter og styrer events
6	Veranstaltungsbearbeiter	de	Kann Veranstaltungsdetails bearbeiten, aber nicht alle Einstellungen ändern
6	eventredaktør	da	Kan redigere eventdetaljer, men ikke styre alle indstillinger
7	Einsicht	de	Kann Statistiken und Berichte einsehen
1	ejer	da	Fuld kontrol over organisationen og dens indstillinger
4	space manager	en	Manages individual spaces within a venue
3	stedchef	da	Styrer steder, rum og bookinger
7	indsigt	da	Kan se statistikker og rapporter
8	Partner	de	Externer Mitarbeiter mit eingeschränktem Zugriff
8	partner	en	External collaborator with limited access
4	Raumleiter	de	Verwalten einzelner Räume innerhalb eines Veranstaltungsortes
6	event editor	en	Can edit event details but not manage all settings
\.


--
-- TOC entry 5855 (class 0 OID 2351814)
-- Dependencies: 596
-- Data for Name: todo; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.todo (id, created_at, modified_at, user_uuid, title, description, due_date, completed, importance) FROM stdin;
8	2026-04-04 15:53:47.458761	\N	019d237b-3563-74c6-8085-6d5fc5afb2b3	IDG verkaufen	Höchstpreis derzeit 700.000.000 $	\N	f	high
5	2026-03-27 08:39:30.727889	2026-04-04 18:09:08.069815	019d237b-3563-74c6-8085-6d5fc5afb2b3	Bild für Carolina Eyck Konzert anfragen	Bei der Agentur anrufen: 030 - 87293781	2026-08-15	f	low
2	2026-03-26 18:11:09.42654	2026-04-04 18:09:12.355614	019d237b-3563-74c6-8085-6d5fc5afb2b3	Wirklich Verlag anrufen	Infotermin zur API vereinbaren	2026-05-30	f	high
\.


--
-- TOC entry 5847 (class 0 OID 2351740)
-- Dependencies: 588
-- Data for Name: transport_station; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.transport_station (uuid, created_at, modified_at, name, city, country, point, gtfs_station_code, gtfs_location_type, gtfs_parent_station, gtfs_wheelchair_boarding, gtfs_zone_id, type) FROM stdin;
\.


--
-- TOC entry 5848 (class 0 OID 2351751)
-- Dependencies: 589
-- Data for Name: user; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus."user" (uuid, created_at, modified_at, email, password_hash, is_active, username, display_name, first_name, last_name, locale, theme, activate_token) FROM stdin;
019d237b-3563-74c6-8085-6d5fc5afb2b3	2026-03-25 06:32:50.404455	2026-04-05 16:31:35.17663	roald@grain.one	$2a$12$8Mj7iXkMTyNyhjP1YjNZweNfmUmOq0HcvEtLJ6vp1Wkt7f9Xe/yxq	t	roald	mapmeister	Roald	Christesen	de	light	\N
019d2fa1-dc87-7ab4-b063-8c784b5a2440	2026-03-27 15:10:30.152703	2026-03-27 15:27:50.442228	pippa@grain.one	$2a$12$02AF0tPw.R31tSGZNzWSA.9nxE1A/bghvoCahCgmiCcxX2wYZul6q	t	\N	\N	\N	\N	de	light	\N
\.


--
-- TOC entry 5849 (class 0 OID 2351764)
-- Dependencies: 590
-- Data for Name: user_event_link; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.user_event_link (user_uuid, event_uuid, permissions) FROM stdin;
\.


--
-- TOC entry 5850 (class 0 OID 2351768)
-- Dependencies: 591
-- Data for Name: user_organization_link; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.user_organization_link (user_uuid, org_uuid, permissions) FROM stdin;
019d237b-3563-74c6-8085-6d5fc5afb2b3	019d2eed-a25a-7caf-a762-a2a71917c6a1	520556415
019d237b-3563-74c6-8085-6d5fc5afb2b3	019d359c-b8f6-75d6-a5fd-ae1f303e3bbe	520556415
019d237b-3563-74c6-8085-6d5fc5afb2b3	019d35a0-3cd6-7c28-b3ca-537e8577defe	520556415
019d237b-3563-74c6-8085-6d5fc5afb2b3	019d3e19-6c1c-7bf0-ad59-b1f15fb20c5c	520556415
019d237b-3563-74c6-8085-6d5fc5afb2b3	019d3e2d-5c6e-78df-9fbc-930adb904621	520556415
019d237b-3563-74c6-8085-6d5fc5afb2b3	019d3f54-0db6-731f-8e18-03cb0c70b3fe	520556415
019d237b-3563-74c6-8085-6d5fc5afb2b3	019d3f68-5b90-7af5-b4f6-55e592acb0d4	520556415
019d237b-3563-74c6-8085-6d5fc5afb2b3	019d5946-16c3-7f0d-95d7-7b73c4f4d42d	520556415
019d237b-3563-74c6-8085-6d5fc5afb2b3	019d594d-cc9a-7f77-bac8-e3307f0faa75	520556415
\.


--
-- TOC entry 5852 (class 0 OID 2351776)
-- Dependencies: 593
-- Data for Name: user_space_link; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.user_space_link (user_uuid, space_uuid, permissions) FROM stdin;
\.


--
-- TOC entry 5851 (class 0 OID 2351772)
-- Dependencies: 592
-- Data for Name: user_venue_link; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.user_venue_link (user_uuid, venue_uuid, permissions) FROM stdin;
\.


--
-- TOC entry 5853 (class 0 OID 2351780)
-- Dependencies: 594
-- Data for Name: venue; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.venue (uuid, created_by, created_at, modified_by, modified_at, org_uuid, type, name, description, summary, contact_email, contact_phone, web_link, street, house_number, postal_code, city, country, state, point, opened_at, closed_at, ticket_info, ticket_link, opening_hours, accessibility_flags, accessibility_summary) FROM stdin;
019d358b-2946-7c2f-afc0-0cb0e8049f2f	\N	2026-03-28 18:43:25.753071	\N	2026-04-04 18:36:19.317674	019d2eed-a25a-7caf-a762-a2a71917c6a1	workshop	[SoundCodes~	Studio und Werkstatt für elektroakustische, elektronische und experimentelle Musik und Programmierung.	\N	soundcodes@grain.one	\N	https://soundcodes.grain.one	Am Nordertor	2	24939	Flensburg	DEU	SH	0101000020E610000060A06DE86DDC2240BCB2B27DE7654B40	2022-09-29	\N	\N	\N	\N	\N	\N
019d3e19-c044-75bf-820b-c96fd5fe07ee	\N	2026-03-30 11:36:08.256597	\N	2026-03-30 12:11:46.222423	019d3e19-6c1c-7bf0-ad59-b1f15fb20c5c	cultural_center	Aktivitetshuset	Das **Aktivitetshuset** ist ein Projekt- und Kulturhaus, das als Plattform für die **Entwicklung und Präsentation** dänischer Kunst und Kultur im Grenzgebiet dient. Dabei geht es nicht nur um die Vermittlung von Kunst und Kultur, sondern auch darum, die Nutzerinnen und Nutzer zu unterstützen, damit sie selbst aktiv werden und Kunst und Kultur entwickeln können.\n\nAls Kulturhaus für die dänische Minderheit in Südschleswig bietet das Aktivitätshaus einen **freien Raum**, in dem Aktivitäten und Lernen freiwillig sind. Das „aktiv sein“ wird gefördert, aber niemand wird dazu gezwungen. Angeboten werden vielfältige Aktivitäten: Kurse, Kulturprojekte, Diskussionsrunden, Ausstellungen, Konzerte und vieles mehr – alles, was begeistert, herausfordert und neue Möglichkeiten für persönliche Entwicklung in einem freien, gemeinschaftlichen Rahmen eröffnet.	\N	akti@sdu.de	0461 150 140	https://aktivitetshuset.de	Norderstraße	49	24939	Flensburg	DEU	SH	0101000020E610000040CBFF7AD2DC2240F4178C0853654B40	\N	\N	\N	\N	\N	\N	\N
019d3f5c-ba16-7c74-a7ba-533f26446ddf	\N	2026-03-30 17:28:54.802457	\N	2026-03-31 10:38:25.33187	019d3f54-0db6-731f-8e18-03cb0c70b3fe	cultural_center	Kühlhaus	\N	\N	info@kuehlhaus.net	\N	https://kuehlhaus.net	Mühlendamm	25	24937	Flensburg	DEU	SH	0101000020E6100000E0DDB640ABE12240D49DA58124634B40	1994-10-01	\N	\N	\N	\N	\N	\N
019d44ca-0797-7658-914c-3b47bf05acfc	\N	2026-03-31 18:46:24.150425	\N	2026-03-31 18:47:36.065966	019d3e19-6c1c-7bf0-ad59-b1f15fb20c5c	\N	Idrætshallen	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	0101000020E6100000B0D7B7F904D82240F421089FCA644B40	\N	\N	\N	\N	\N	\N	\N
\.


--
-- TOC entry 5821 (class 0 OID 2317087)
-- Dependencies: 560
-- Data for Name: venue_type; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.venue_type (key, schema_org) FROM stdin;
arena	SportsActivityLocation
concert_hall	MusicVenue
conference_center	ConferenceCenter
cultural_center	CulturalCenter
educational_institution	EducationalOrganization
event_house	EventVenue
food_establishment	FoodEstablishment
hall	EventVenue
library	Library
media_institution	EducationalOrganization
municipal_facility	GovernmentBuilding
museum	Museum
outdoor_area	OutdoorStructure
public_place	CivicStructure
sacred_space	PlaceOfWorship
sports_hal	SportsActivityLocation
theatre	Theater
workshop	EducationalOrganization
youth_center	CommunityCenter
art_gallery	ArtGallery
school	School
music_school	MusicSchool
movie_theater	MovieTheater
bar_or_pub	BarOrPub
night_club	NightClub
hotel	Hotel
club_house	CommunityCenter
coworking_space	CoworkingSpace
makerspace	CoworkingSpace
\.


--
-- TOC entry 5814 (class 0 OID 2283098)
-- Dependencies: 553
-- Data for Name: venue_type_i18n; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.venue_type_i18n (key, iso_639_1, name, description) FROM stdin;
art_gallery	da	Kunstgalleri	\N
art_gallery	de	Kunst Galerie	\N
art_gallery	en	Art gallery	\N
coworking_space	da	Coworking Space	\N
coworking_space	de	Coworking Space	\N
coworking_space	en	Coworking Space	\N
makerspace	da	Makerspace/Fab Lab	\N
makerspace	de	Makerspace/Fab Lab	\N
makerspace	en	Makerspace/Fab Lab	\N
sacred_space	en	Church/Sacred space	\N
theatre	de	Theater	\N
theatre	en	Theatre	\N
theatre	da	Teater	\N
workshop	de	Werkstatt	\N
workshop	en	Workshop	\N
workshop	da	Værksted	\N
cultural_center	de	Kulturzentrum	\N
cultural_center	en	Cultural Center	\N
cultural_center	da	Kulturcenter	\N
public_place	de	Platz	\N
public_place	da	Plads	\N
conference_center	de	Konferenz/Tagungsort	\N
conference_center	da	Konferencecenter	\N
museum	en	Museum/Exhibition	\N
outdoor_area	de	Außenanlage/Außenbühne	\N
outdoor_area	da	Udendørsområde/Scene	\N
educational_institution	de	Bildungseinrichtung	\N
educational_institution	en	Educational Institution	\N
educational_institution	da	Uddannelsesinstitution	\N
outdoor_area	en	Outdoor Area/Stage	\N
concert_hall	de	Konzerthalle	\N
concert_hall	en	Concert Hall	\N
concert_hall	da	Koncertsal	\N
event_house	de	Veranstaltungshaus	\N
event_house	en	Event House	\N
event_house	da	Eventhus	\N
youth_center	de	Jugendzentrum	\N
youth_center	en	Youth Center	\N
youth_center	da	Ungdomshus	\N
food_establishment	de	Gastronomie/Bar/Café	\N
food_establishment	en	Food Establishment	\N
food_establishment	da	Restaurant/Bar/Café	\N
museum	de	Museum/Ausstellung	\N
museum	da	Museum/Udstilling	\N
media_institution	de	Medieneinrichtung	\N
media_institution	en	Media Institution	\N
media_institution	da	Medieinstitution	\N
public_place	en	Square/Public Place	\N
conference_center	en	Conference center	\N
municipal_facility	en	Municipal facility	\N
municipal_facility	de	Kommunale Einrichtung	\N
municipal_facility	da	Kommunal institution	\N
library	de	Bibliothek	\N
library	en	Library	\N
library	da	Bibliotek	\N
sacred_space	de	Sakralraum/Kirche	\N
sacred_space	da	Sakralrum/Kirke	\N
hall	de	Halle	\N
hall	en	Hall	\N
hall	da	Hal	\N
arena	de	Arena	\N
arena	en	Arena	\N
arena	da	Arena	\N
sports_hal	de	Sporthalle	\N
sports_hal	en	Sports Hall	\N
sports_hal	da	Sportshal	\N
school	da	Skole	\N
school	de	Schule	\N
school	en	School	\N
music_school	da	Musikskole	\N
music_school	de	Musikschule	\N
music_school	en	Music school	\N
movie_theater	da	Biograf	\N
movie_theater	de	Kino	\N
movie_theater	en	Movie theater	\N
bar_or_pub	da	Bar	\N
bar_or_pub	de	Bar/Kneipe	\N
bar_or_pub	en	Bar/pub	\N
night_club	da	Natklub	\N
night_club	de	Nachtclub	\N
night_club	en	Night Club	\N
hotel	da	Hotel	\N
hotel	de	Hotel	\N
hotel	en	Hotel	\N
club_house	da	Foreningshus	\N
club_house	de	Vereinshaus	\N
club_house	en	Clubhouse	\N
\.


--
-- TOC entry 5811 (class 0 OID 2266245)
-- Dependencies: 550
-- Data for Name: visitor_information_flag; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.visitor_information_flag (flag, iso_639_1, name, topic_id, key) FROM stdin;
24	de	Stromanschlüsse verfügbar	3	power_sockets_available
24	da	Strømstik tilgængelige	3	power_sockets_available
24	en	Power Sockets Available	3	power_sockets_available
62	de	MSB	5	msb
62	da	MSB	5	msb
62	en	MSB	5	msb
2	de	Für Jugendliche/Erwachsene geeignet	1	youth_adult_suitable
2	da	For unge/voksne egnet	1	youth_adult_suitable
2	en	Youth/Adult Suitable	1	youth_adult_suitable
27	de	Ruhiger Raum verfügbar	3	quiet_room_available
27	da	Stille rum tilgængelig	3	quiet_room_available
27	en	Quiet Room Available	3	quiet_room_available
23	de	USB-Laden	3	usb_charging
23	da	USB-opladning	3	usb_charging
23	en	USB Charging	3	usb_charging
22	de	Shuttle-Service	3	shuttle_service
22	da	Shuttle-service	3	shuttle_service
22	en	Shuttle Service	3	shuttle_service
25	de	Fotografieren erlaubt	4	photography_allowed
25	da	Fotografere tilladt	4	photography_allowed
25	en	Photography Allowed	4	photography_allowed
34	de	Digitaler Programmführer	4	digital_program_guide
34	da	Digital programguide	4	digital_program_guide
34	en	Digital Program Guide	4	digital_program_guide
13	de	Schatten verfügbar	3	shade_available
13	da	Skal tilgængelig	3	shade_available
13	en	Shade Available	3	shade_available
17	de	Vegetarische Optionen	3	vegetarian_options
17	da	Vegetariske muligheder	3	vegetarian_options
17	en	Vegetarian Options	3	vegetarian_options
33	de	Digitale Info-Bildschirme	4	digital_info_screens
33	da	Digitale informationsskærme	4	digital_info_screens
33	en	Digital Info Screens	4	digital_info_screens
32	de	Event-App verfügbar	4	event_app_available
32	da	Event app tilgængelig	4	event_app_available
32	en	Event App Available	4	event_app_available
19	en	Picnic Allowed	3	picnic_allowed
19	de	Picknick erlaubt	3	picnic_allowed
19	da	Picnic tilladt	3	picnic_allowed
26	de	Streaming verfügbar	4	streaming_available
26	da	Streaming tilgængeligt	4	streaming_available
26	en	Streaming Available	4	streaming_available
36	de	Taschenkontrollen	5	bag_checks
36	da	Taske checks	5	bag_checks
36	en	Bag Checks	5	bag_checks
38	de	Erste Hilfe verfügbar	5	first_aid_available
38	da	Førstehjælp tilgængelig	5	first_aid_available
38	en	First Aid Available	5	first_aid_available
12	de	Sitzgelegenheiten verfügbar	3	seating_available
12	da	Siddepladser tilgængelige	3	seating_available
12	en	Seating Available	3	seating_available
16	de	Essensstände	3	food_stalls
16	da	Madboder	3	food_stalls
16	en	Food Stalls	3	food_stalls
18	de	Vegane Optionen	3	vegan_options
18	da	Veganske muligheder	3	vegan_options
18	en	Vegan Options	3	vegan_options
30	de	WLAN mit Login	4	wifi_with_login
30	da	Wi-Fi med login	4	wifi_with_login
30	en	Wifi with Login	4	wifi_with_login
21	de	Freie Platzwahl	3	free_seating
21	da	fri pladsvalg	3	free_seating
21	en	free seating	3	free_seating
35	de	Sicherheitsdienst vor Ort	5	security_staff_on_site
35	da	Sikkerhedspersonale til stede	5	security_staff_on_site
35	en	Security Staff On Site	5	security_staff_on_site
41	de	Überwachungskameras	5	surveillance_cameras
41	da	Overvågningskameraer	5	surveillance_cameras
41	en	Surveillance Cameras	5	surveillance_cameras
15	de	Kostenloses Wasser	3	free_water
15	da	Gratis vand	3	free_water
15	en	Free Water	3	free_water
10	de	Wetteralternative	2	weather_alternative
10	da	Vejralternativ	2	weather_alternative
10	en	Weather Alternative	2	weather_alternative
11	de	Naturstandort	2	nature_location
11	da	Naturlig beliggenhed	2	nature_location
8	de	Indoor	2	indoor
8	da	Indendørs	2	indoor
5	de	Haustiere erlaubt	1	pet_friendly
5	da	Kæledyr venlige	1	pet_friendly
5	en	Pet Friendly	1	pet_friendly
0	de	Familienfreundlich	1	family_friendly
0	da	Familievenligt	1	family_friendly
0	en	Family Friendly	1	family_friendly
1	de	Für Kinder geeignet	1	child_suitable
1	da	Børnevenlig	1	child_suitable
1	en	Child Suitable	1	child_suitable
4	de	Seniorenfreundlich	1	senior_friendly
4	da	Seniorvenlig	1	senior_friendly
4	en	Senior Friendly	1	senior_friendly
3	de	Queerfreundlich	1	queer_friendly
3	da	Queer venlig	1	queer_friendly
3	en	Queer Friendly	1	queer_friendly
29	de	Kostenloses WLAN	4	free_wifi
29	da	Gratis Wi-Fi	4	free_wifi
8	en	Indoor	2	indoor
42	de	Zugangsbändchen	5	access_wristbands
42	da	Adgangsarmbånd	5	access_wristbands
42	en	Access Wristbands	5	access_wristbands
39	de	Polizeipräsenz	5	police_presence
39	da	Politi til stede	5	police_presence
39	en	Police Presence	5	police_presence
28	de	Bewusstseins-Team anwesend	5	awareness_team_present
28	da	Bevidsthedsteam til stede	5	awareness_team_present
28	en	Awareness Team Present	5	awareness_team_present
20	de	Alkoholfrei	3	alcohol_free
20	da	Alkoholfri	3	alcohol_free
20	en	Alcohol Free	3	alcohol_free
29	en	Free Wifi	4	free_wifi
40	de	Feuerwehrmaßnahmen	5	fire_safety_measures
40	da	Brandsikkerhedsforanstaltninger	5	fire_safety_measures
40	en	Fire Safety Measures	5	fire_safety_measures
14	de	Nur Online-Event	2	online_only_event
14	da	Kun online event	2	online_only_event
14	en	Online Only Event	2	online_only_event
7	de	Outdoor	2	outdoor
7	da	Udendørs	2	outdoor
7	en	Outdoor	2	outdoor
31	de	Mobilfunknetz verfügbar	4	mobile_network_available
31	da	Mobilnetværk tilgængeligt	4	mobile_network_available
31	en	Mobile Network Available	4	mobile_network_available
11	en	Nature Location	2	nature_location
37	de	Zugangskontrolle	5	access_control
37	da	Adgangskontrol	5	access_control
37	en	Access Control	5	access_control
\.


--
-- TOC entry 5826 (class 0 OID 2325409)
-- Dependencies: 565
-- Data for Name: visitor_information_topic; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.visitor_information_topic (topic_id, iso_639_1, name, key) FROM stdin;
1	de	Zielgruppe & Inklusion	audience_and_inclusivity
1	da	Målgruppe & Inklusion	audience_and_inclusivity
2	de	Ort & Umgebung	location_and_setting
2	da	Lokation & Omgivelser	location_and_setting
2	en	Location & Setting	location_and_setting
1	en	Audience & Inclusivity	audience_and_inclusivity
4	en	Media & Digital	media_and_digital
4	da	Medier & Digitalt	media_and_digital
4	de	Medien & Digitales	media_and_digital
5	de	Sicherheit	safety_and_security
5	da	Sikkerhed	safety_and_security
5	en	Safety & Security	safety_and_security
3	de	Komfort & Ausstattung	comfort_and_amenities
3	en	Comfort & Amenities	comfort_and_amenities
3	da	Komfort & Faciliteter	comfort_and_amenities
\.


--
-- TOC entry 5830 (class 0 OID 2351186)
-- Dependencies: 571
-- Data for Name: wkb_polygon; Type: TABLE DATA; Schema: uranus; Owner: oklab
--

COPY uranus.wkb_polygon (id, context, context_id, geometry, name, description, key) FROM stdin;
6	organization	102	0103000020E61000000100000024020000249E2B6950E622401D9C3C4371654B409692A32860E62240620B4A3F71654B400C1E24E56FE6224030F65D5571654B403BCF1353CAE622401066B7B871654B40B9A20C9EEEE622401E2F93E071654B40A8945C69FEE622407A8CD3F971654B40927A9FD64AE72240C113027472654B400B5A97F0B5E722404E83990373654B407032C707C9E722403295301D73654B40AA525C001BE822403AC9208B73654B400C439DA235E8224075AE57AE73654B40641F4603A1E82240EF16483C74654B40C831140AA5E822401484664174654B4046C9998BE9E82240550C7D9874654B4028DEC65909E922409DBFE47C74654B40119B806E27E92240D6356F7174654B40DA45E27F45E92240F544D94F74654B40E5431A8B63E92240CD76271874654B4074A1218D81E92240755060CA73654B40F3FF406A95E92240FAC6907D73654B4093C859EDADE92240CC25C71E73654B40DE29F79AB5E92240A0EB140173654B4047A41582DEE92240931C084272654B400091DF87E9E922404A4A8C0E72654B4062E0251502EA2240E71EB08F71654B409A4A845C02EA22404E910B8E71654B40CC296F3610EA224047D3663C71654B40FE2B76901AEA224089ED63FF70654B408792A9474BEA224060C3B5AA6F654B40E79E0639AAEA2240757B52E06C654B40662C7A40E3EA2240422C53236B654B40B269CF640FEB224012CCC49D69654B4034D944563CEB2240BA6E23F067654B40BC9BB4065FEB22409CDFE18966654B40CFEEE9CF69EB224001C17D1A66654B40F9D7D03385EB224098EC4E1165654B40A4D795408BEB22409822BCD664654B40BA64F3A08DEB22405DB1B4C164654B40D871ACAEDAEB2240D097D31762654B40388C277EEFEB2240196EB65A61654B4014177C2C04EC22402F2B198B60654B40FC5DA4B618EC2240278019A95F654B406A7F8D192DEC2240A4FDD8B45E654B4044DF245241EC2240A0FE7EAE5D654B40AB57725D55EC2240B50D2D965C654B40A2627E3869EC2240F937126C5B654B4005DD43E07CEC2240D8C357305A654B40539C8C5884EC224057CB669159654B4010A652B285EC224034BCA87459654B409C63B1408EEC22403DD6EFA858654B40E0318A7590EC2240B101736E58654B406785BAB894EC22401584DB3258654B403BF1E3EAC1EC224086DE0CBB55654B400132C0FFCCEC22403F38222055654B409CF2E808C9EC22407892641A53654B4048A5B38CC5EC2240A979F70F51654B4049E84A9EC0EC2240D5F81A534E654B40AF098132BCEC224061939A914B654B40CCCE19C9B9EC2240CD4693DB49654B4086C03E4AB8EC22400472F5CB48654B40C9346D8DB5EC22404E79208C46654B4055512AE6B4EC2240AD85B20246654B40AEBBE906B2EC224003F5523643654B407378D27CB1EC22404C196B9142654B40BC17FBACAFEC224050CC5B6740654B40A87CDCD8ADEC2240A41752963D654B40E6D6E38AACEC22409DFEB8C33A654B407B089E6CABEC22402067B4DD37654B40918C5442ABEC2240E90B9E8A35654B4030D0DF3CABEC2240781A813E35654B405BD9C337ABEC224076508FF634654B40594E74ECABEC2240B154D50F32654B40DF4D3B8AADEC2240F8540E2B2F654B40EB985410B0EC22406045C2492C654B40684B5B7DB3EC22404588716D29654B40405C8DCFB7EC2240584EA49726654B40D9209504BDEC22403D7BD3C923654B40AD379862C2EC2240D31E3DF220654B4010DA9548C7EC2240C689422E1F654B407CD10DD0CDEC2240AE91CBD31C654B40C85423E8D4EC2240E2148B971A654B40838B39B9DCEC22409199526818654B40FCD8E13EE5EC224050C35D4716654B40B2843574EEEC2240D940EA3514654B40DC1A0A54F8EC22409A96203512654B4092891B6802ED22407227B44510654B40F5B98CD30CED2240B6CE08600E654B405CA369A922ED2240734D3BB30A654B40CBC31A102EED22400F49B8EC08654B409C2F92DB34ED224061E671EB07654B4079D0C3C639ED224029A0343107654B40D5425FCB45ED22408812FC8005654B405CBC2BFD46ED2240AFEF2F5805654B402DAA18C451ED22403BC20FE803654B4035C5F41B52ED2240B58056DC03654B40A6E2F1E861ED2240DBE6E9C701654B409F84DA5571ED2240B352A7A4FF644B40F7D2166080ED2240CA31E872FD644B40E5981C058FED224090B80B33FB644B40AE176F429DED2240400673E5F8644B40115F6093A8ED2240E0BCECF7F6644B40F8339F15ABED2240EA00858AF6644B402C60587CB8ED224007ACA422F4644B4045696E74C5ED224053CB3AAEF1644B40D3D2EFD1CFED224035C1B894EF644B400BBCFA8DD9ED224052BA597DED644B40E5D2AE3AE3ED22404198A540EB644B40B1507B41ECED2240307A1007E9644B40C48CCBD1F4ED22407D81C9C3E6644B40D182B7E9FCED2240D8525677E4644B40535FD50BFDED2240AEC1E46CE4644B405F76648704EE22407DA13A22E2644B40967AE1B109EE22402DC6D06BE0644B40F5A812A90BEE224016E4FFC4DF644B40F064593816EE2240934D45A6DB644B402DE8E8EE1EEE22402F995AAFD7644B4012815C7C27EE224096BDC23AD3644B40DE6D377A27EE22406463A43AD3644B40479DDCEC1DEE22409AA7E4ADD2644B40EFEB9D2B13EE2240E0C86D0FD2644B4075818E7EE8ED224008D69D9ACF644B40FCE4850BBCED22408831AA0BCD644B4007B7886DB4ED2240C9A3FA97CC644B40FF22B27AB2ED22402773607ACC644B407393ADEF95ED2240E2C6DCC8CA644B40F573C94786ED2240D57359DBC9644B40584D556E76ED2240CA602000C9644B4053E62F6766ED224097A26637C8644B404128883656ED2240C03A6181C7644B40671B57E045ED2240E2913BDEC6644B409BD8BD6835ED22401B07214EC6644B4092D3F7D324ED22401A3B35D1C5644B40589A252614ED22404AF99767C5644B4003C91FD60DED2240E174CC44C5644B403F85E80ADAEC2240B4674958C4644B4088180FB4D3EC2240CBDA563BC4644B404F360509CEEC224072487621C4644B408216740BCAEC224051A9E8CCC3644B4060699D8CC5EC22406D83FDA8C3644B40DE0267DFA2EC22401B3E2FF9C2644B40A101A95282EC2240D7042854C2644B40E2CEC9A07AEC2240B7D48C17C2644B403083530E73EC2240E68890C8C1644B4060F795A36BEC22406EF48767C1644B40530E37C167EC2240C2AAED29C1644B40CCBE916864EC22407D4ADBF4C0644B40B50818E562EC2240DE9A67D8C0644B40C0DD12655DEC2240D4170671C0644B40453BBEA056EC2240852D99DCBF644B404761E92250EC2240A3CE3638BF644B406E4F9AF249EC224026D48E84BE644B405F14614041EC2240B9A8E73BBF644B40DB28FCF432EC2240E699BE3FC0644B4009BFDE2723EC224035F3F75EC1644B403EDCBC8504EC224022C89057C3644B4038637C25F7EB2240DEF1DC19C4644B4047CDCC32F6EB2240B5FAA327C4644B400943A52DF6EB2240154C9825C4644B4067E584FAF5EB2240DF3B2711C4644B40C0F42830F2EB22407B1EB98CC2644B40E965D919BDEB22408FF88803B3644B403DF0C8AAA4EB2240B618C6E3B2644B40B3E0B03B8CEB224034EC54C3B2644B40433D6AAF6DEB2240C3D9529BB2644B40469FA9234FEB2240CBB04F73B2644B40DD539BB436EB224097589D53B2644B406C718C451EEB22408F16D733B2644B40913D81E8FEEA2240CB1C820AB2644B405EE27379E6EA22407DBFCDEAB1644B40EE135E0ACEEA224030C957CAB1644B40CA86D783AFEA224006574EA2B1644B4056CD4618AFEA22403471C0A1B1644B40D92294F790EA22401552457AB1644B405E32878878EA2240DDE37A5AB1644B401AB2721960EA2240FD28023AB1644B40BDAD75804EEA22401D938700B1644B40640583C246EA2240CF623EE7B0644B408CB2592F40EA2240CE9C84D0B0644B402978321F39EA224045C619B8B0644B4056C8202336EA2240571551ADB0644B40B38420FB2CEA224022AB3C8CB0644B408F78CA201FEA2240CC822E5AB0644B40182A27651AEA22406B6F094AB0644B40EF85A35415EA2240D012B31FB0644B403F4F4A2101EA224095504F3CAF644B40F7BA64BCE9E92240B78BB835AE644B40D466BA80CCE922409B0FB0ECAC644B40FDA11445AFE92240E7FDB9A3AB644B40E8BF2DE097E92240CBF64C9CAA644B403EC9527B80E92240E5A6B395A9644B4024F2C2D164E92240E667725EA8644B406B281C724DE92240A39F1557A7644B4061D5470D36E9224003376750A6644B40AA0CB5D118E92240799A6C07A5644B4087F47291FBE8224026F05EBEA3644B4047CBD631E4E82240739DFFB6A2644B4015F40DCDCCE822402FF661B0A1644B40C0278929BBE82240DAC1F8E9A0644B40FD3D15B5B1E82240D647D482A4644B401CB36BB682E822408CD0A203A1644B404870CC5766E82240A6DCC76C9F644B405E495E5A4BE82240070268B19D644B4089D80ABD32E822409EBBC5409C644B40BB0818262EE822404F2DF21F9C644B4090C60A662BE82240CA9E141C9C644B40DD88CD521AE822402D7F0F2C9B644B406477E2DD16E82240F6FA1B239B644B40A2A4E6DB16E8224035AA16239B644B40D49281DC16E82240AADD9E229B644B4065BC267817E82240A41B23A89A644B4078CDE05415E82240B25513979A644B4051AB08E3FCE72240970205D499644B403D4FE37CE5E72240D3C8BD2199644B40AA6A0252DBE72240A88129D798644B4052E1C284CDE722401320EF7198644B40EB4D03E7C7E72240D6600D4198644B40009489C9B8E72240DCC381BD97644B40506C7EA9AAE7224073F5FF3297644B40F5E0451F9FE722404F08EAE996644B40B172E1AF7BE72240EEC19DE195644B402B128C0066E7224022AF393A95644B406187B40753E722409B574FAA94644B40F85CEBA136E7224014A64FCE93644B40730EB5C131E72240DDB658A893644B407E34C8E92CE72240494B8F9293644B40BB7D8BD22CE72240B3D2269293644B4082B8B3A234E722406C78B4FE90644B4015D7D02639E722405F4A83818F644B40A4571E1344E72240FFE790E78B644B40FA5EE3AA47E72240B2D0B6B48A644B40176C68C94CE722404B7DE8FF88644B40DBE6C1566CE722408B9E39D77E644B40BCC8D6D06FE7224017725ABD7D644B40DEBA94C571E7224048E582D37C644B40BFCD5D0E74E722405159AACF7B644B40C90C0BD376E722403DB714937A644B40B2AD57BE7AE72240A936E2EC78644B40996D3B217CE722409AFBF67978644B40BF976A3E89E7224087FE293E74644B4053AD30659FE722408E1131196D644B40D0F47CD4A7E722402325D8616A644B40DFA949E9ADE72240F57AE55C68644B403F1B7945B3E722408A1B6E9466644B4029F480C9B6E7224031460E7C65644B40D5825343B9E72240A58A78B664644B405A180D3BC0E7224079306B8A62644B40F1A341F3C8E722400D96BDD05F644B4093C37269D4E722408B2F26045C644B40FA63D6A4DCE72240AD3B534859644B402B8BDF1CDEE72240BAA49DCB58644B4079A3935AE8E72240AF72286655644B400D37F286E8E72240FB3E725755644B405173C5D1ECE72240BDCF174954644B40171AAAE1DDE72240C5FF25A153644B405C65E9A2D7E72240BC90EE5A53644B40B3245EC9C2E7224071CF704752644B406FA77B51AEE722401C86430F51644B403D3E2A457CE7224093DA660A4E644B403748A0D471E722402B2530694D644B4017943F5C55E722401A4688B14B644B408F139AC013E72240A72757A147644B406A88201106E7224079B35CC846644B409282B7E664E62240029DB4DE3C644B404650137E64E6224087D346D93C644B403D23785161E6224094ED16AF3C644B4075E4594A61E62240F1E9CEB63C644B4091F2301661E62240596A86EF3C644B40026EAEA060E62240EA71496F3D644B40918F81C85FE62240C3375B273E644B40C080630F5BE622400239EE8440644B40CC62F7DC53E62240308FFC7F44644B40F79C40C752E62240A0A03C5045644B405B04965649E62240DA37494449644B40175ABE2444E62240C6F2CCBB49644B408CEFB34B48E62240CE05F8A749644B4097ED4F2242E622400D0C130D4E644B4087086D043FE6224040590B0A4E644B4011C0AC9B36E6224088CE1DE54D644B409A33AF7633E62240B4FC4FD74D644B40437E0FB5FFE52240A5F905F44C644B40F3C44F23BAE52240450C93C34B644B40E78A11EBB6E52240C3B8707D4E644B4044727BB8B6E522400C36C97C4E644B40903CB044A0E5224089E135324E644B403F7BFEFA9CE522405BF591F050644B40FFCB969A8DE52240B57152C55D644B406A03667B78E522404D51E96C5D644B40AB3692BC72E5224039996B495D644B4068EDC0EC80E5224058D66C9450644B4009435AD47EE5224002468A8D50644B400D4B35417BE52240EAACCB8150644B407C3A667244E5224026BB4F2B4F644B404E5F288643E522408167250150644B40E0A3744936E522401420DAA34F644B40703EB76E2AE52240C3BD6E4B4F644B40443E8E5B1DE52240E05E93E94E644B40F5A0CF950EE5224031A8BF704E644B40662A0E1FF1E4224097D9FE6F4D644B40E25A9B2ADEE42240B461B4D14C644B40B8575D35D5E422404741FF864C644B407C1ABBA2CCE42240BF83983E4C644B403541D445CCE42240BCB5873B4C644B4014EB2870BBE42240D06F91AC4B644B40C6E78DD4B1E42240D9DD71634B644B40DF955ADAAAE4224040A0212E4B644B4096445038A1E42240B1992ED54A644B4058E859AB93E42240E991F7494A644B4028C339DC7EE422404F4BB0AD49644B405C7BB5F675E422403D45656449644B40E9C731CD66E422406DD182D048644B40356B9FB766E42240E305065D47644B406D99C3C256E422408ABB5D6146644B402D4DA01846E42240DB96F77745644B40A99C33D433E42240DF8ACD4244644B40D79B9F3421E422403783374C43644B4080C8F0FC07E422405C432C0842644B40AE9E563A06E4224034A5DCDC41644B40A6C7C9F6F7E3224051321D5D41644B409B173A74F4E32240D5B0BC3641644B40C88201C2EAE32240AA1C0ED140644B40E0A37A0DE2E3224087D1A2A940644B40E6EBD704D0E32240BB74F82040644B4034070524CFE322404CE7FA8C40644B407BE229EEB9E32240FCC9221440644B408A092EC8B9E3224024286E5741644B4013380F00A0E32240A27D4F2C40644B40C74503BB92E322405B7F03923F644B406950475970E32240F0DD827B3D644B401C1853886AE322402BBA25423D644B40D9235E883AE32240395A38793A644B4001B3E44B22E32240022874FA37644B40121B1C911FE32240E38082B237644B40490B234D16E32240031E4EBE36644B40962B28CF0BE3224087793A202E644B408ECE522308E32240B7550F522C644B40F192E6C502E3224068F1514C2A644B40A1F33461FDE22240EA75D9E528644B404D600D63F6E22240CD7B7B4F27644B40FD68B4E4F5E22240817BFE3727644B4076859B65EEE2224041B419D325644B401BF46080E9E22240965C5B1225644B4019FDE97AE5E222408BC2087424644B408654E1B6DBE222404D2A5D3523644B404CDA070CD1E222407844C11622644B40009BEBF3D0E2224088A9381422644B402DB27113D0E2224081817C0022644B400297E1F2C8E2224081D80F6021644B40ABB41EC44CE22240A44DDE8116644B40A71EE91946E2224048B91AE615644B406BB547BB3FE22240E5A6FD6215644B40A4A64B363FE22240AB3A4B5815644B40C62CD31E38E22240F42CE6D814644B4022B15C1B35E222402F2E1AA814644B40A9E718D930E22240DABF4A6814644B40451DDE6A29E22240EB19D80614644B409F200BDA21E222400E30D6B413644B40B5E3A22C1AE2224012038B7213644B4096C5B46812E222407456274013644B4058AFA37FD9E1224014BB4C4012644B40D87BAF98CCE1224084FD504312644B40789A2D67C5E122401941FF4412644B40AACB3FE8C0E12240E8DC0C4612644B407A201C75BEE122403BB69E4612644B40E2D362CE82E12240BCA12DCF11644B40F7EF640C50E12240CB78DD3711644B40C32261674BE12240F8D2421D11644B400E5B88A645E12240AC6C4FFC10644B402721048541E1224059AFA7E410644B401EAA292D33E12240E8D03E6D10644B402F65614C31E12240E494B26510644B405151CF3D2DE1224099BD675510644B40324D3AAA29E12240D16FC25210644B4049957DE824E122407351C46210644B405EC8D81E23E1224049DA427010644B406418C42023E12240D3D0037512644B4026F1A82123E12240875B52F213644B40C933871524E12240DCEF8D2C16644B4085F4E58324E122405F93A22F17644B402EA8DEFA27E122404E3E51CE1B644B40602D860F28E12240F979D4E91B644B40A7EF1AD029E122401B3686401E644B40208C14AA2CE12240FFD63A7C22644B403778062727E122405A7F5FE72E644B406CB2B87225E122406FFE404231644B4047C40A0925E12240D5964AD431644B40A483E05824E12240566EBDC732644B407E25595C23E12240C5F88B3135644B40CCEB5B9E1DE122403EA7A4033C644B405114E1BC13E12240D14B43A642644B40ACB37F9EFDE0224055ED86314C644B40C1A582AC9AE02240B4EAD2EE86644B4095EFEFF488E02240AE1B6E8194644B40C0822F2027E02240CD57ABDCB7644B4099DD24941DE0224053B5ED4FBB644B409C353EA41AE02240DF23A75FBC644B40D662372A14E022406963C5AEBF644B40BBE42B7705E022407CE76A31C7644B40024C865BB9DF2240571FD8A0D3644B40480F716C93DF2240140B65D3D9644B4050B3BE3B94DF22403F4D6A80DC644B405BD9B0B994DF2240F8D07720DE644B40FB24B9146EDF2240B380EA1EE6644B40958B328B5EDF2240D1F4B055E9644B407B13FB8A53DF2240D6E43D9CEB644B40D24C884655DF2240609FCF8CEB644B406CDF9C497EDF22404591931FEA644B40153D23D97CDF2240D425FA5BE9644B400C9AA90FB7DF2240BDE8B070E7644B40DFDE16CABEDF2240AFEF3C10E8644B4008DB06CCBEDF22408A046510E8644B405500FE6DC2DF22405298635BE8644B40BDB2C3C3CCDF224058BAA89EED644B408C307D76D8DF224031942C33ED644B40CB58DF52E3DF2240444A3818F6644B40C1F30556D3DF22403E020B80F6644B402BCE34F2CFDF2240ABA10F96F6644B40BEFCD932D0DF2240EBFB6CC1F6644B4037945B81E6DF2240F25ED3580A654B40CD7BBD74EADF2240C05DCE420A654B40764A4A38D6DF22402B06EE86F8644B409ED810B3F0DF2240C1AC54230B654B4010939B16ECDF2240F639123E0B654B40233757E1F1DF2240C5D9651410654B401DD2CF8FF7DF2240719904F60F654B402173F0AC02E022403EF294BA0F654B40DE0D021903E02240C8A1591010654B400FA84A11F8DF22407790035110654B40183C1188A1DF224096F9564C12654B4093D9710A9CDF22403E1FB72111654B40F9DCF6B29ADF2240CEF8213711654B40643345B8A0DF2240800D02DB12654B40B1463C449FDF2240FA314F1614654B4032BD6DE0A0DF224057412F1514654B40E150D61AA2DF22408F73A8D412654B4021EF1F9DF5DF2240A778BB1911654B409F35E6DAF7DF2240917EC5F712654B40AD09477AFBDF224035CDD3E112654B40DF295675FDDF22406165F06014654B4063B117A7F9DF224050E12F7914654B401BD8F3B7FCDF2240D862890617654B404D6FF8DE00E022403763B7EF16654B401F20179B02E022404C96586718654B40E6E0754AF6DF22406E0693B518654B40BAE40C03F9DF2240259842D41A654B40FD23A6FB9EDF2240CF94B5041D654B4069DE956F98DF22407ABD6FEF1B654B40B5485B0397DF2240B106D0071C654B400A4C827F9DDF2240A9EA24171D654B40CDE2AF5B9EDF2240CB149DA71D654B40509113839CDF22403EF2F8CD1E654B4067974A539EDF2240631308C91E654B405D99310BA0DF22405FFF588E1D654B40670D240BFDDF2240E0D10E3F1B654B40268FAD40FEDF2240219424571C654B409116362508E02240B9E5121D1C654B40A4F18BC006E02240C41243011B654B407384FA4107E02240B4CD11FE1A654B40190EA56C0FE02240B3607DCA1A654B403AA0868D1AE02240A1EC00B824654B40C4AA574715E02240EDF1B1D824654B407A9E143C9ADF22404E475FD327654B40110C570E93DF2240069D81C026654B40761EFE9C91DF2240EE7D29CF26654B40934828C598DF22406B8EBDD927654B403F8B73A599DF2240C03EB65C28654B4055A1E20897DF2240C16563AD29654B403183345198DF22404DE74AA329654B40C274A6E89ADF224010E6E15428654B40726E4AFF15E0224075ADFF5925654B40F3E00B201BE022407E29373A25654B40EA64E0E420E022409263B06B2A654B403A2BEA541BE0224091B9F8302B654B40D3A761500FE02240948E33DB2C654B40C4458DC208E022404CBCD14731654B404B14405506E02240C4A4412E39654B40F020D1080FE02240C9F5ADEE3F654B408D7E8BF112E0224059C92AF742654B408EF9C16723E02240CD9792A046654B400231D81118E022408B8FFDAA4E654B40F910AA4F15E02240E70BE59F50654B40E777E6EE39E0224045A0590A52654B409EA8A3CD43E022402286086C52654B401060E3C546E02240D6376D8952654B408F840D0858E02240752A3B3453654B4000FB5CF16FE02240DF82E22054654B40B1911BCD74E02240E49ED25E54654B408EDAD4FF76E022407834D97A54654B405F295FE082E02240FD9B461255654B40111C4C0794E022409BE5F2EC55654B406C62609914E12240F9DA14545C654B40276A99AF7BE122404124457661654B407245AFB08FE1224048B95E5962654B40A2FF7EECA3E122409459B81E63654B40748F217CAAE12240F449705463654B408B163684B4E12240F6E093A663654B40E4F0C55AB8E12240B1F000C663654B40A76127F3CCE1224062E1F64E64654B4051E670FAE1E122400C62BBC364654B405B5CA122F7E12240984CA91265654B40DD29ED5E0CE22240186C913B65654B40013BD4F63CE2224055E31C4165654B40F46CC60F3DE222408295244165654B40F63F80A948E22240EB2B2C4E65654B4053FC88FA4CE22240E957005365654B40E3B5606354E22240F8EE4C5B65654B40C90BF34758E222400CABA75F65654B4081E36ECD79E22240D97748AB65654B40EC21CFF189E222407F7814CF65654B4035342246A0E22240834D3E1966654B40AB8D7C11AAE222406E6A305866654B401262AA01BAE2224090DA4EBD66654B40AC56C97EF3E22240C9F27A5C68654B40ED14B21461E32240650B11926B654B406341E041CDE322400DE44DC56E654B409F6C0E46CDE32240E5B76DC56E654B4099A78F660FE42240DC9943AB70654B40819A6F6215E422405FE539D770654B40E7CDBE0C73E422407220C5AC73654B40E1D1CD8EBBE4224013154DB175654B4011D7D58ABDE42240C09C6FBF75654B40D3EC5E69F5E42240AA62EE4A77654B40A825B39401E52240D5A9668777654B40574AFABF0DE522400ECDDEC377654B40F375103B26E52240FD91210B78654B40CF81FE523CE522407A155B1E78654B407857C7C73EE5224072607D2078654B40B5122C5357E522407352E50378654B401335664665E52240E9F726D777654B4052D2379168E522403ECC6DD177654B40663B63816AE52240AF0861C677654B40426B5CD56AE52240764D52C577654B40052B25CA6FE52240F75B6DB577654B40BD03914D7EE52240B567F26877654B404305C31988E522402FF0513577654B406B31E2E388E522400271822F77654B40B54BCF328EE52240C8F06A0877654B404E464D2FA0E522403AFEF78376654B407EC8FFF7B7E52240E036E7A175654B40D538CF72F3E522403A826A7973654B4024CCFE9A02E62240074548DB72654B40982E60C403E62240C1DD36D172654B4028E521F011E62240F9525C5672654B40A350826A21E62240BC3FE6EA71654B409CDA81342AE622402A12CEBC71654B4066433F612DE62240012429AC71654B40CC8BF95B36E62240E7C9088671654B406B1D08AF40E6224089B0336171654B40249E2B6950E622401D9C3C4371654B40	Flensburg 6	\N	fl6
9	organization	102	0103000020E610000001000000AD0400000C1F57DFFFDD22408EB883F274644B40FF46EAA72ADE2240D787B66965644B40BD7E49042BDE22401A3C174865644B40B63607402BDE2240FEF8283265644B40B73E2DB62BDE2240DBC6D50665644B40009DF9B72BDE2240AA642F0665644B407D1122692DDE2240501CB66764644B405A770B063ADE224054C2B2C45F644B408C84CE203ADE2240D6E4DBBA5F644B400973D0E54CDE2240CE5A75D458644B40809D93454EDE2240AE14CE2E58644B405C734A1F50DE2240DD440BD956644B40C1D14A0A51DE2240CED1267E55644B40A98E540451DE2240FB01992154644B40AFA1C33050DE22400ACF94F852644B404E801A2650DE224024E092E952644B405762B72550DE224006BB0FE952644B40E827660D50DE2240CE4FE1C652644B400684F1274EDE22401DED767151644B4088F6E8584BDE2240EA07C12450644B407C1A6FA747DE2240E9DC16E44E644B405E2CD1163BDE2240D66BE7424B644B404663B5EB3ADE22400E936F364B644B40ED5704E732DE224007BC79E548644B40C90B278C32DE2240375E39CB48644B4016213E1831DE2240B28BC85F48644B401A93141731DE224045F7715F48644B403EA6B08F25DE22402025DB0A45644B404DAEF03606DE22405F96ADFC3B644B406CBE0BD2FCDD22402BFAF24539644B40DB3F4183F8DD22406644A43838644B402EA8BDDBE0DD224087C2CE7132644B40F25F1EC6DEDD2240BFD67CEF31644B40AD518A2CD9DD2240218BAFBA30644B405C9441E7D2DD22408FDC0F982F644B409AFE5B01CCDD2240A7CF96892E644B402B19D386C4DD224090541E912D644B400A47340FC4DD2240EA9900842D644B405C4D59E6BEDD224020C32FF32C644B4023F8ED83BCDD22400B7644B02C644B40A2107507B4DD2240CC64AEE82B644B4062BEC930B2DD2240F5E9F5C42B644B4073D56055ADDD2240508899662B644B40B2F8BC30ADDD22405E0BD2632B644B405D7559A5ACDD22403FE8D1562B644B40DF3D36A6ACDD22408E093F562B644B406A0EB0B5ACDD22409B7A044C2B644B4061A84BF7ACDD22400C0AAA202B644B406C268C85AFDD22405A8F5E7029644B40C0E9D937CBDD22403A7F312317644B40171111D1CCDD22405302DE1416644B40F58E071ED0DD2240D4589EE613644B40BEC9E32FD0DD224002D2D1DA13644B40AE646032D0DD2240616430D913644B40C951E232D0DD2240375CDBD813644B400869EB40DCDD224036B6557814644B400F7E3D70DCDD22400BC4C77A14644B401333936DDDDD22408E26DC8714644B40FDE44C77DDDD2240B8EF418214644B40C486C563DFDD2240D057786113644B40C79B0AB1E0DD224055F3179E12644B40CC85032AE6DD22407A16D0680F644B402F76718CE7DD22400E966D5F0E644B40B71DE1DFE7DD2240A4A7E5070E644B40E842AE28E8DD224001598ABB0D644B402FCD995DE8DD2240E4BB77230D644B40DBD15BBAE8DD224042D5077B0C644B400C401AADE8DD224080AD273F0C644B40FA4C8CC1E8DD2240768876040C644B40B529FE58E8DD2240740B5EC20A644B40E8F486A5E6DD22406389FC0D09644B40E5BCD713E4DD2240D3BD84F607644B40F3DDD96EE3DD2240CE936BB007644B403604360CE2DD224097BBB81907644B40387662F9DBDD224082BE753B05644B4083CC5FF1DBDD22401C19953905644B4033C15D2CD5DD2240E970A4A103644B4047314B80D4DD2240C1C5237903644B40D39B6736D3DD224069B1F63B03644B40785E5AE7CBDD22401BDFFBE001644B4020F8B4B8CBDD2240A25855D801644B409B9DCE71CADD2240C449D2A201644B401EAE18A1C9DD22409EA4168001644B400653F639C8DD22400CF7DE4501644B4050353AA8C3DD2240DD4C628600644B40C561A22EC3DD2240E52D857400644B40C3FFF71CBBDD22408B6EFA44FF634B404FC2620DBBDD22404544EB42FF634B400183201DB2DD2240299F0B15FE634B40DE961FEFA9DD224007BB4A1DFD634B40E7E3FA00A9DD224063F6A901FD634B403A108EEDA8DD22408308D1FEFC634B405E4F78AFA8DD2240870A78F7FC634B40D9F0538DA8DD2240CE4D12F2FC634B402535F014A8DD2240789E0DDFFC634B40FA81EC0BA6DD22401C64A392FC634B40B5A2A342A4DD22408DA87044FC634B4027F4EE95A3DD2240764C2529FC634B403714F7F4A2DD2240CB1B620BFC634B403E7349CEA1DD22405469FCD8FB634B40583C7A2C9FDD2240656E0D5CFB634B40518B03A59CDD22402346FBD8FA634B404E95832899DD224035575B04FA634B408FDB345296DD2240E6F78A3CF9634B40A2C4B8B994DD2240F164E5B2F8634B40E14D60EA93DD22401813C271F8634B4003AD189393DD224083259E4FF8634B4019B2652292DD224050AD5ABFF7634B40F03BDECC91DD2240580AE49DF7634B401EC0184C91DD224050FB806BF7634B401BBBC7568FDD22403C45186CF6634B4089012B3C8FDD2240B4948A5EF6634B4081C1BCBD8DDD224068047F4CF5634B408E4361238BDD22401CE02058F3634B40CC661C288ADD224017983A62F2634B405CADF21C8ADD224044204557F2634B406CE25E2089DD22406E7A0B60F1634B40F64EB0B587DD22403BB43365EF634B40441700E486DD224067808E68ED634B4050BD466186DD2240C71333A4EC634B40D4CD00E085DD2240CFC80CE2EB634B404A1000DE85DD2240ACBD05C3EB634B40938D05B185DD2240D5BFDD75EB634B4006CD45D085DD224064B804EDEA634B40A79FCDC685DD2240B621C259EA634B40B333CE1186DD2240A7D2FFCDE9634B40FB0E202B86DD22407D0C325FE9634B400E0F27CE86DD2240C1A1A680E8634B40EF8840D387DD2240899EE7ACE7634B40E8A19A2B88DD2240032FE272E7634B4068C20A5488DD224085D8944FE7634B403D9A9D9588DD2240E984402DE7634B4066B8056D8CDD22404FDA9C2AE5634B4086FD959C8FDD22402F1C82D6E3634B40972E707791DD2240FED57E10E3634B405AA64ECF91DD2240CE0147F2E2634B40FE2AF66D96DD2240DE41815BE1634B40DF73026E97DD2240E7727103E1634B40EE0500AF98DD22407EC645A6E0634B4042D462D99BDD224036FB0EBBDF634B40F0EAF6C89DDD2240E932352BDF634B40F3E24CD99DDD2240CB587926DF634B408ED697109EDD224036996916DF634B40F8A7BF359EDD22404BC9A80BDF634B404A8C764A9EDD22407D0F9E05DF634B401CC69351A9DD22404BBF7B4ADF634B40782BC511ABDD2240C40C6A55DF634B40C7BEBAC3B0DD2240E856FA78DF634B4000C52F84B6DD2240B63EA392DF634B4069825E5DC3DD2240BEB4F3CBDF634B402BB3A4CDCDDD22409A4419E8DF634B40C2320BA6D2DD22402F4FCDF1DF634B40185563B5D2DD2240B354F2F1DF634B40F0E9C239DADD22408CCBFA00E0634B40C4F123AEDADD2240DDBBE401E0634B4015EF0C47DBDD2240FE721503E0634B401BA93C75DBDD2240A61B7303E0634B404CA411CDDBDD224038F42104E0634B40FCF17CCBDBDD2240F4BFC303E0634B400716D725D4DD2240ACC6C243DE634B408689EE7ED0DD2240B969CF6DDD634B40ECA8D962D0DD224028D46167DD634B409D1FFF57D0DD22405A94E364DD634B4035C9FD85CFDD22402228D434DD634B40419D3BA3CDDD2240D6975BC6DC634B4080F20F94C8DD22403321F49DDB634B400EBB06E1C6DD224099E16C57DB634B4002C34DD9C6DD2240DD592C56DB634B409FC96078C6DD2240A7687546DB634B401C472C72C6DD224016328846DB634B4032CD3776C5DD2240F0439B49DB634B400D96E1FCC4DD2240F33A164BDB634B40198391ECC2DD2240F4588951DB634B402AF03F20C1DD224078252657DB634B40A9C35605C1DD224023F67952DB634B4012B7F1F1C0DD224010DD1B4FDB634B40137E12E1C0DD2240B71F2D4CDB634B40F5E6004EA3DD22404D48B8FBD4634B40BE9FDA7696DD2240FB3BE73DD2634B40D18F991386DD22403EACC62BCF634B4047DAAE967ADD2240513EDD69CD634B40B8E41D7B78DD224088465217CD634B404389BB7578DD22401AE31117CD634B40CF51B0E177DD2240A11C0E10CD634B4002E2F22A47DD224014810AC1CA634B40A482762247DD22408E7F57BBCA634B4086822E8D26DD22409BD669D6B4634B409221C9A125DD224090F43F38B4634B40BF08C96F25DD2240EAE00A34B4634B4050F9D1CFF4DC22403E27821CB0634B40D2DA3C6DD8DC22409AA98878AE634B400BD41B3AC5DC224085356D40AD634B404F7E4AB4ABDC2240E8004D88AB634B409BDB8D0EAADC2240607DE46BAB634B40AEE89F11A3DC2240AA810BF3AA634B40BD36D78A91DC2240EE42F4C3A9634B40861B14834FDC2240A775403BA4634B40F93F370C0CDC224045D31B7E9E634B4041339AABFADB2240D127C1019D634B40310A596ED1DB2240E853584E99634B40AAFFD0A895DB2240E0CB28F193634B40AAFD57011CDB22403F5F283089634B40C762CCFD08DB2240345BF08687634B4000FE62738BDA22405F28B9557C634B40661FC32379DA224063E39F9C7A634B401FAFF2F165DA2240BDDB3ECE78634B403F94FE1945DA22408AD810B775634B402F633FF211DA2240B68E673270634B40E8B9F7DEE3D922403F4B3C616A634B40DF27FAA6E3D922408F5162596A634B4066AB4583CCD922403703871A67634B40E630B24BCCD92240D1A3991267634B40A5ABDA3BC9D92240AB55B2A266634B40D05FD050AAD92240699E81CE62634B4015492326AAD922408A6A2CC862634B40EDE495D195D92240258568C35F634B40571C163B7ED922401F1B78DE5B634B409907F42B63D9224050938EC557634B4014D256DF37D92240CF73762050634B40542B085222D922406A4085334C634B401131D21D04D9224068DD2FF545634B40F5C543F7FCD822406479427C44634B40B2AED82FF0D822405A29A7DA41634B4017BE060FE4D82240DCA428373F634B404F30A12FBDD8224070B5F03D36634B40CC957753A2D82240490AB7FF2F634B406EAA2037A2D8224047811CFE2F634B408539ACCCA0D82240B4698FE92F634B409AE3CEAC91D822409C08040E2F634B40E811677784D82240F32B504E2E634B403B8691D683D82240DA52785A2E634B405D1179A783D822409CCDE8512E634B40A321393977D822400A6B930F2C634B40BB18293E75D82240155C6DB32B634B406C0E4A095CD82240E9C0B31E27634B40468471015CD8224021B4701F27634B40B0090C9456D82240AA360FA227634B40EA1C6C5656D82240EDBFD5A727634B40DF0E7B3956D82240872D8DAA27634B40978C571156D822401F872FA127634B40EB3417A354D82240F771C04B27634B4016B8B00550D82240F8862B3826634B405819FEB745D82240741921F923634B40F73492883BD82240A5EDF6E421634B40AD9243F13AD82240A8FD14C621634B40A592990B38D8224023478D3421634B406B26134135D8224016AD5BA820634B40280004D213D82240E44EEF181A634B4007B7F48CFDD7224012693CE915634B40D008BEB2F0D72240C35B94E912634B405D573F99E8D722406955CC0511634B405E5F1711E3D722400AD8DBAC0F634B405C4C89B7DED72240EF287C3D0E634B40FD70309DDBD722401E5E2CBD0C634B405C0D14CED9D722406EE7B5310B634B4038AFBD9ED9D72240728029B60A634B40382A8C96D9D72240B285BEA00A634B4052734692D9D72240DD5893950A634B40E883D38ED9D72240FA2BA58C0A634B40142FF2FAD9D72240D0820EE809634B409B531F64D8D722408BFD698309634B406537CDEDD7D722407860256609634B406F4B20DCD7D722406521946709634B40FAA197B6D7D72240E85EA26A09634B40A132C090D7D72240811E466109634B40A946137FD7D722406ADFB46209634B4010E00604D6D72240C61BEE0409634B40174A924CCBD72240F4683C5E06634B403B6A39CBB9D72240913F9A0902634B400021C9AE8DD722408BFBF51FF7624B40587A90CF75D7224095EE1038F1624B4069CB204526D72240EBE7377ADC624B400BEB17110DD72240FDAC1F11D6624B404DB6C4F3F1D6224055558E2BCF624B40E16F9F6EEAD62240F2CAE241CD624B4015A1F28AE9D62240AE76F907CD624B40488CE0DCAFD622403B498640BE624B40BF1E2CCA94D62240991F9F16B7624B4091D2DD777AD622408119981FB0624B40C5256ADD6CD622402A359A83AC624B408092BDEC6CD62240D51FDE80AC624B405334A21C6DD62240E3AC5078AC624B40A9B2D87468D62240E791173CAB624B40AC6C0E7468D62240297FE73BAB624B409701513D68D62240E800632DAB624B405901943C68D622402FFD302DAB624B40E8822DF767D6224094F8C91AAB624B40BBD8A29666D62240F0663EBDAA624B402C0054C462D6224063B3ABB9A9624B403182993060D62240643E9E0AA9624B407996DC2F60D62240B3286E0AA9624B405D7496B65ED62240E54C51A6A8624B40965C79B25ED622402D7138A5A8624B40B3E1E6374FD622400DB1CE89A4624B407B6628244BD62240B464DC74A3624B402A7B6B234BD62240FD4EAC74A3624B400DF95EE244D62240901B39D2A1624B40668957873DD622406D1D04E69F624B40D92E2D483DD62240EDD587D59F624B401B12CE4E38D6224035F8C3DC9E624B40C647C14D38D6224048BE99DC9E624B406F15E8C534D62240F160405A9E624B407605CEC434D62240FE17185A9E624B40EC7B1C0131D62240825D72D39D624B402072DAFF30D62240710B4CD39D624B40F0047EDC30D62240AAF68CCF9D624B40077E49DB30D62240BC7D6ACF9D624B40303EEBA729D62240B039360B9D624B40B8549CA629D62240CB7E1B0B9D624B4023A1812326D62240C22696C69C624B40BC359F2126D62240F41B6CC69C624B407DF5181721D62240A4421B649C624B405353588012D6224096AA1E6C9B624B40013A625D12D622400C9F62789B624B409E9F4A4D12D6224048BE097E9B624B401F0D689910D62240E377F9169C624B401955639310D62240F16B7B169C624B40724124B40FD6224095B77D049C624B403376FE8D0FD622407909FF039C624B4000C8066F0ED62240140E4B009C624B4085FCE3EB06D6224095417BE79B624B40F2920D48FBD522406EA707C19B624B402D7EA68AC0D52240C5CA957E97624B4001FDB3DBBFD522405525618397624B40214360A9BFD52240DFC0C38497624B40585D9164BCD52240E169B59B97624B40DE00660CBCD522405676F19E97624B40A0855D2CAAD52240FA17691C98624B40AAA0291CAAD522405BAADA1C98624B40C7FE1931A8D52240EEDAB65998624B4085E49C2797D522402DEB45769A624B40B9B0E8BC8AD5224031E63D009C624B409F664DCC89D52240CD1E9FFD9B624B4045BD89CA89D52240D279D7FD9B624B4085BB78865FD522405CE5C8929B624B40F348129F55D52240B4B9406C9B624B4055D9D42655D522406617C5669B624B40EFE542D534D522401FBD2DED99624B404E4A9D39C3D422407C5B0DBA97624B4013D9D2ADBFD42240BC0579A897624B40F60E780771D422403C205EAA95624B406894D77470D42240F2ADE2AD95624B40A1E4E52F58D422400A0FCF4296624B40954CEF7F57D422400613A54096624B409C216F38EAD32240D5DE11E994624B405F90A0B2E9D322401FB40DEB94624B40B351D5C9E8D322408C5280EE94624B40BA5778689DD3224091023D0C96624B40FC9C4D609DD3224062E2C50C96624B40E7B0CE049DD32240CEC2E11296624B40CB61E3019DD32240070CEC1296624B40DF18DE0F9CD32240FF69811696624B40EAF63FA17BD32240BD469E3F98624B40458DD67144D322408E7603D89B624B40DEC7DC5D44D322405AE54FD99B624B40212416C943D32240F14303E39B624B40421EE7F826D32240F0EBC4C39D624B40D25EA62B24D3224099FC68F29D624B408132417B09D322402FCE99AF9F624B40044DEFEFDCD22240F38F9296A2624B40EE6938DCB9D22240434742E0A4624B40EE3858078CD222402C93E4A4A7624B40F893FEEC46D2224053B3E712AB624B405BFCFEBB23D22240ABAB041FAE624B4023D401F222D22240454AF11CAE624B406214CBC722D2224072D8801CAE624B402E7D66891FD22240BE7CF813AE624B40EFEF4B8914D22240755207F7AD624B406506816414D22240086782F6AD624B4094908D680DD222408AE810E4AD624B403920B5560DD22240C797E2E3AD624B403E1175AC09D22240BFFF34DAAD624B407D639751EBD1224020830C8AAD624B40B1F059BBD7D12240E83B6E0FAD624B4056744A28D6D12240A4359205AD624B40F2846AE596D1224016C496D8AC624B4068CBA57B63D122402593D41FAC624B40E73A15305DD1224025851009AC624B40EA68B29159D1224087EF35B6AB624B40AB1C09303DD12240826D292CA9624B4001DCF91D3DD12240F3758C2AA9624B4006B9F5CE3BD122403A0CAD0CA9624B40B37E441031D1224031342CC2A8624B40DE7B212C2CD12240847FCB9FA8624B40D001652D27D12240EF7F707DA8624B40BA5749D918D12240CE2D191AA8624B4069FD209A15D122400FB29F03A8624B40B465649F14D1224007D3D4FCA7624B40429D03A90FD12240AA6EF390A7624B401DFF22A0BBD0224005EA1A6EA0624B40DD30C9969BD0224005A0515E9C624B40764EF1D58ED022402468A74F9A624B40F8BC05A87CD02240BFBDE56097624B402FF9FB344ED02240B84C81ED91624B4027ABABC628D022400DB6887490624B404F9A73D005D02240349BD4138F624B4065DB21C304D0224065CE53148F624B40E7083385E4CF2240760F70238F624B405E5C84F5CCCF22401EF57B2E8F624B4088E2C4EFCCCF22401EB6372E8F624B40D32EEA74A5CF22401ACD245F8D624B402636474296CF2240C7A4E2AC8C624B409A15C1AB6CCF22403C00CE9789624B405F9F540241CF2240E176D61788624B400D742DA540CF22409191581E88624B4031BA542E40CF22402A9EA72688624B4039D6657B0ACF22404F3073E78B624B40D73DEAEA08CF22402348AD038C624B40B5A2267FDCCE2240818670FF91624B406D4F42F4A3CE22405B1BE16294624B40156F4ED7A1CE22405409BA7994624B400884E7869CCE2240E041C5C894624B40C249A2058BCE22401FCE26CD95624B40D6B5E8077ECE2240F97E0B5996624B409DF0CA1D67CE2240F900DA5297624B402F1A428650CE2240FF3E15AD98624B406009AF8649CE2240498AAF6599624B4012D5FF8648CE2240E29CC96699624B40848091FA45CE2240CE3F976999624B40549E451D39CE22403425C67C99624B409783FB4B31CE22407C34BE8999624B40F8A894AB30CE2240C19B4D8999624B40FF290C7B07CE2240A9FC2C6C99624B40F97F5725E4CD2240D11306F598624B4007D0ADF6CECD2240273F186898624B40C689D603BACD2240D4E375E997624B401D6E1F7BB7CD224052CB24DA97624B4045B81A9EB1CD22403B4BE9C697624B4005F3087EAFCD22403091F1BF97624B40285312FFAECD2240C39995C397624B407AB96DA0ABCD2240892A4FDC97624B40B4BDCDD7A1CD224015CD152498624B40764D002B9CCD2240F529FD4D98624B4071DA62299CCD2240DF15094E98624B405280F6209CCD22409EC5B24E98624B40910AA9FA9ACD2240D2C9265798624B40E3B0E0D09ACD224082C65A5898624B4044A28AA298CD2240F73D646898624B40434D849F98CD22400DD0666898624B407F91AE0096CD224040BCC26898624B40B13D5C0C90CD224030CE916998624B40676F97AD8FCD2240314C9A6998624B40417AC2B776CD22405D7554F499624B4050718BD94FCD2240B320681D9D624B4005843BAA4ECD22402E5511369D624B4099857D7EFDCC22406243EE06A3624B408E6F3C4FF1CC224035DD31D6A3624B40194E32DBE8CC22409264FE65A4624B40194109F3E3CC2240323D5FC9A4624B40A65F8BE29CCC2240AF1E9B68AA624B4048B86D3992CC224005EF8140AB624B4042168C4476CC2240A1A15B73AD624B405540B33450CC224049D91F40B0624B401B70462C50CC2240F0DFBF40B0624B40880293AD4FCC2240F634D149B0624B40BE9C86C74ECC2240FA4D485AB0624B40FCAC4BC74ECC224034220F5BB0624B4036F143C24ECC2240EF7FB36BB0624B40247F80174ECC22408842DDC9B0624B402323E4DF4CCC2240046CB775B1624B40CF3D012835CC22405ABB178ABE624B409BB0924924CC224078987ED9CA624B407E179A50DFCB22408CBD0CACFD624B4010F38155D6CB224042E30A4A04634B40BFE0E341D6CB2240F46D885804634B400B1082F7D5CB2240C8881B7304634B4044A46933D1CB224080021F3D04634B4084B8146F06CB22404591759BFD624B40DF7FBEDAD8CA2240D44FF56DFB624B40D7AA147294CA22408EFE125FF7624B405B453CBA6ACA2240027A9FCBF4624B40CF9780C552CA22404486EF50F3624B40C9E23CB752CA2240B1744E50F3624B40F0358DAF52CA2240428BD44FF3624B409B6CB29A4ECA224053A7250FF3624B40AFA484864CCA224072F232EEF2624B408F1F4660B9C92240B8B2C1FAE7624B403C898EB795C922400DFA5D53E5624B403049673D84C922404430CDFBE3624B40AC5CF82283C922408F2403E4E3624B409ABF222473C92240101B158BE2624B40927017025DC92240B0AC1F7AE0624B40FA8A974F2BC92240089CFCC1DB624B4091B38EC21CC92240F6AC216ADA624B40973852F6ECC82240F63A9400D6624B40C97537C6C9C8224021564171D2624B40F90DF950BAC8224029DAE9E0D0624B405762C3ED83C8224029F6759FCB624B404BF65B2959C82240784F8F97C7624B4055C6D1D851C822409490D8DDC6624B4076F3557D4EC822405CEF9A88C6624B40783698DC2CC822406CE7CD32C3624B409E129D872CC82240645A6145C3624B403BEECD522CC822407A48ED50C3624B402EF4D37485C52240ED11CAB257634B40A7CEC33185C522406C55B6B457634B40FCB5806862C52240B5975EB458634B40B25CEDA8E3C42240CA52D5575C634B401846B2F59DC422406B3607585E634B40B7C993A291C42240015599B25E634B401328268183C4224063F66E1A5F634B408E40006476C42240D846CB7A5F634B40AD7C096D68C422401AEC68E15F634B4055F6003868C42240D59E48E35F634B400167C59C62C42240F7DD031660634B404BF138553BC42240658B747961634B404A7A14E13AC422409EBF9E7B61634B4081332E65FFC322401AB4D29762634B40E57C2151FEC32240042A129862634B40AEDF4756E4C32240886C369E62634B40D1B1FAA5DEC32240B07D8E9F62634B40527CDAAAC6C32240A8403BA562634B40B1D8F10D72C32240295135B962634B400D8E5A0972C32240B46132B962634B40400BE5F970C32240D5B072B962634B40D732791B6DC322407B3242B262634B40D55AEB566BC32240C63CF7AE62634B40BA4AC39255C322405FD47F8662634B40567A6CD23EC322403D84335C62634B4035A80D533EC3224083AB465B62634B406D5BF3E436C32240259C754D62634B404D34141E23C32240A86B0F4662634B40DF9487F422C32240BD6E604562634B40CF9E79E4E6C22240E411E32E62634B4048C50BF2C8C22240753DAA2362634B4050849D56A3C222408FAE921562634B40DF3CEE1588C22240AC17500962634B40CE9F4AE782C222403657180A62634B408FFAE1B97CC22240C707080B62634B40494F4914BBC12240C8A2322862634B40AE4CBF299FC122408AFC814862634B405A4B7F3B94C1224078C0285562634B4083E1B13994C12240BD49955862634B4016706B7390C122408D2A885962634B40747833F575C122408E53DA5662634B40835F53016BC122401CACBF5562634B40E34069C366C122406742D94A62634B40540D6DBF4CC12240D59B010862634B4078922F46F8C02240115BABDB60634B40AF4A9F0AC1BF224062F608235C634B402EEA19D19CBF2240211755965B634B400A4B1D78B7BE224059358B3258634B4092F6CD67B7BE224092DEBC4958634B406E3E1C71B4BE224070DC2C3E58634B4050200DA872BE224045A1723D57634B40E1FCEE2C15BE22400E7198D055634B4080F1522A15BE22409D4D8FD055634B4038652BDDFCBD2240078CB37155634B40E3870DC9F0BD2240FF5AA44555634B406E37D1AFDFBD2240451D8CFA54634B40E0E560A0C3BD2240FC3026AB54634B40C1D4BC52C0BD22405AB9EEA654634B4054F43928BDBD22409E69A19D54634B40D483D3CAB7BD2240C6660A9C54634B4070E43880A7BD2240768D3A8754634B40D055C35B8BBD22401923D88E54634B40A670DA537CBD2240269DCEA754634B40AD09DD287BBD2240CF11BFA954634B400B2AE2F374BD22403CA20EB454634B401E92CE975EBD22408BD4D7F454634B40DDF6980852BD22408838DA2855634B406218CA4D48BD22400E12235155634B402FFE3D1C32BD22405205D6C855634B40C7767BEC28BD2240633C020656634B40D5406B091CBD22402E97D05B56634B4068BC9F1B06BD22401A2CE50957634B40132E0159F0BC2240E442E4D257634B40565F2EC9EDBC2240140AF1ED57634B4041C3CFC7DABC22407F9D96B658634B40BFFC6D03D0BC224074DE875759634B400152B3529ABC2240F6E1147A5C634B40097E61BE80BC22406947CFFC5D634B402C2BC12D7DBC2240DE2CB82D5E634B4035650C0870BC2240102D3CF25E634B4045952D3C6ABC224098F1FF485F634B407E7D3D2267BC2240ABF06D775F634B406DEA91505DBC224016DF680A60634B409D772D5F4ABC2240FE08F20C61634B40E449D2D537BC22404619FEF161634B40CB5F813837BC2240842395F961634B403B2B8DF12DBC22408C8F7B6062634B40A66258E123BC2240234619D062634B4047B1625E10BC2240F869499063634B40482C79430FBC2240F384D39963634B40ED4D77910DBC22402EA274A863634B407441EDCA09BC22406CCC07C963634B40AF1F86B4FCBB22404448F63964634B40BD199035FBBB2240C6DC114564634B40C624E80DFBBB22401F19394664634B40C5B680E8F2BB224048F4B4BD63634B407B23BC39F0BB22402BC0C09063634B408F85E1E5D1BB2240D9CC839461634B4092704E6AAEBB22409192BC355F634B409B594745ABBB2240FBE5F5FF5E634B407022B466A8BB22400D4C53CF5E634B40FACA1E0654BB2240D1943A3959634B405BF9333810BB22409FBAE18F54634B40EBAA9E4A05BB2240C39546CE53634B4014284F32D0BA224046B3992150634B40C475FE0C81BA2240C75DECC64A634B40C43C399723BA22407757AE7F44634B40F78D4212DCB92240665861913F634B4080B18C2DCAB92240BABB8E553E634B4059C25930A5B92240E911E8EC3B634B406C0DC78B88B922409800650F3A634B40E5E387F143B92240328AED9735634B405F7A269830B9224005EB576834634B403D314BF42BB922400BBB891F34634B407E75762011B9224083F99C7A32634B40CC3AC9010CB9224006E620DC33634B4056F9BD3009B9224064010B9F34634B40519ADD89FEB8224047EA398137634B40027C10ADF2B8224052489CB63A634B40D7852998D8B8224008A686C441634B40183AD975D8B82240176ADC0042634B40160A92ACD7B82240C79EEE6343634B4042B38540D7B82240857E672044634B408871F612DAB8224027D12AFB44634B40C5CE7F57DAB822404781780F45634B40DF67E867C3B8224012E98EFC44634B404B7A2F3DC3B82240BA528FFC44634B4026616911C3B8224049B5960645634B40A58E4DA9BBB822403FE985B846634B40F88443BEB9B822401716E02847634B409147A047B5B822409385502E48634B400F84A104AFB822405FE1219D49634B400894F634ABB822408B44C8404B634B4074A1105F95B82240F348201352634B40AD8850DDB4B72240E8F9C2B28C634B407C144C78A0B72240909A343B91634B40C830C0EE4FB72240ECDCF547A3634B405E6F8D084FB722403C944835A3634B405C705E3A0DB72240C927F567B5634B40D94ED0FED8B62240D19618D2C3634B400C4565ACE5B622402ACA6484D9634B40CB0D9567F2B62240D4BB3755F5634B40E2DF065643B72240888C59CBF9634B4043D2F4F95CB7224046673035FB634B40AE7AE4F968B72240736786DEFB634B40C581F377A9B72240EB51AE6CFF634B40E4EB461AACB72240D8F0CC91FF634B401BB2F7F9AEB72240B08198A2FF634B4052D249F77CB822402AAF7B090B644B405FEB661B87B822405A58579A0B644B40D5714257ACB82240A76A31AE0D644B40349471B5B0B8224043DAAFEC0D644B40D96283D0B9B82240A671C16F0E644B40936736D3F6B822409B53F5DD11644B403924D17076B9224083FC3A0A19644B409EAAD4FE87B922406DAED2FE19644B40B193BB7CA1B9224088C764611B644B409A6EBF27C0B92240D874E80B1D644B40DB94565DC0B92240814FF6011D644B4075DC9A9DC0B92240B58E06F61C644B409EF4F6EE54BA2240970C1D2C25644B400A0650878FBA2240B001D95F28644B40297C6F7BDDBB2240483E9F683A644B40DE734C07DFBB22400199CD7E3A644B40A641BBB909BC22409CAF3BE33C644B4033DD8AF0C4BC22403079756047644B4057B474771BBD2240A9D3379C4C644B4048DE1EB61DBD2240FEA7F8BE4C644B4086CAA85146BD22401A75D12D4F644B40B1420AB5A9BD224037976A2255644B40CC7ADABEACBE224000EAF0BF64644B40E3D821C2D5BE22408D03D23867644B409D4F5449E4BE22406A2BFEEB67644B40EF2CEA11EDBE2240C166735868644B40447D62ECF6BE224002BE06D268644B40440F0602F7BE2240F1AB10D368644B401ABF6FE6F7BE224049B613DE68644B4034137BF10CBF224027826AEA63644B40CDDB10F519BF2240A4BE6EDA60644B40D25BF0232EBF22407E0E5FC15C644B408D175C2B2EBF224071B047C05C644B405C5BB9F833BF22406D4FFCE55B644B400F09DD2D34BF2240501D2CDE5B644B40A90EF99635BF22403A980CFC5B644B40C237A40D46BF22401E823E3F5E644B40E0EB7487A8BF2240A4120DCC6B644B403B5FD617BABF22400978E0256F644B40BD33FCB6BFBF22408428225071644B40F966A97FC2BF2240AD82876372644B40977BA297C4BF22408F3F2E3273644B40D121465BB6BF224021BCFA9475644B401C98D5EBC9BF22405259B28578644B40F0B5261FF8BF2240D14A7A767F644B402275C76C25C0224007D2EC8085644B403B0848924CC02240B51831B98A644B40BA7A9EA84CC02240B2D72ABC8A644B40A73031AA4CC02240749160BC8A644B409FC6CD3C4DC0224090A3EECF8A644B4041D29C3E4EC022407D9695A88A644B402D21D19052C022400CCAB4FF89644B400755B4A352C02240860D949E89644B40368942B852C02240A1EAF53489644B4095AA4F0853C02240A9196E2B89644B4098266B2262C022404EA8EEA285644B40388BE43960C02240E2ED6D4A85644B40B00433267EC02240E9EB3CF481644B40860C041890C0224020FCF9F37F644B40E165E3FDBAC0224083200EA97A644B40A4DB55EDE0C02240CE0FBF4976644B407959F73CFCC022404614E82373644B401B99E8743DC122409D9BE2896C644B408213925D3FC12240D9BC6B586C644B40CA81B11B47C122407E7D379D6B644B405443DDF364C12240DB16A4CB68644B409510854965C122400BBA63C168644B40A434F8B168C12240C861FC5868644B40502BC03D69C122400607434868644B400C0D2FA384C122401EC5B0B365644B4021A6F2BEC7C12240B3199D755E644B405C12682E15C22240615E2A1A56644B4081F5219815C22240F24B890F56644B406D86D48A3FC2224005A8BDD751644B40902BEECE66C222402CE4A1194C644B408E6F871367C222405AF6980F4C644B40E52E416567C22240507D9B034C644B402331C74172C22240AC2A626B4A644B402433388672C22240FD6755614A644B404D7B5D8370C22240D9C2BF024A644B4022CA745171C22240B4402DE449644B40E8269E977EC22240C42611EC47644B4028776DA47EC22240BFA601EA47644B4085A0E6FC8AC22240CFA576EE45644B40A0DA52289BC22240AB205EAC43644B40604B56869BC22240102A1FA143644B40C065CA8B9BC22240632B76A043644B40AEEF65709CC2224020F48D7E43644B401C26DEBDAEC22240D9BC32F040644B407F035D82EFC2224055AEEEF338644B405A71D2CDEFC222406C899FEA38644B402FAA9903F2C22240E8237D2639644B40F0792B95F2C2224072A5E33539644B400B1AB217F3C2224059B1452639644B40B9D5A2AA11C32240C62D62623C644B404F503A5614C3224040353CA53C644B40F5E6E9D522C32240962A32103E644B400B13DD3B32C32240419DAA913F644B40274D916132C3224089795A953F644B40B993506732C32240FE14CB923F644B4017077CA032C32240407B7C793F644B40E7BF3C8233C32240B328908F3F644B405BF3018633C322404FF7ED8F3F644B40F7141F8C33C322402926688D3F644B405306FC8733C3224026C4008D3F644B40ADAC345C33C3224039BCB7883F644B40596DDAE266C32240E0AE67B428644B40C2468D5368C322409BE6412828644B4033F3498268C3224037DA351328644B400DD87E856FC322405E4A0E6C25644B4095C9FACD9EC32240A959937213644B40E95C0ADCA6C322404C46916310644B40A8A4808EA6C32240B0CDF4610F644B404D9F30DA17C422400BFB8D18E7634B40B2CBDD961AC42240400F641FE6634B40189F3FCB1AC4224046B33A22E6634B4080A304D61AC42240B9EAD222E6634B40FC8A96151BC42240FD570D0CE6634B40441EC36521C42240141A52C9E3634B40F2CB6C8721C4224043623DBDE3634B40CBE64F4022C42240123227C8E3634B400B2D396599C42240925065D2EA634B40BBC4142CB3C4224056177344EC634B40DF5882C7CAC42240367E5A97ED634B4047D36BA078C522400EBD2C8FF7634B40B4E4D66698C522405B8EF452F9634B40F717F8B7B3C52240A5F12EE5FA634B40451E1E1CD3C522406B7966B3FC634B4039E666932EC622406C4C76E601644B40A02AF46845C62240CB8E8BFC02644B406E7F74324CC622408235334F03644B40AA94D8BE52C62240C2A24CAC03644B40D5346D3653C622409524B1D603644B40071EEED253C62240893A14AC03644B40F55CC0DE53C622402950E0AC03644B4019A80B3154C62240B3AA0BCA03644B405017C36D54C622409F8196DF03644B4065C8DF7A57C62240DB9E93F404644B40076169A857C62240E5BFBB0405644B40E6ED02F357C6224028990A0A05644B40B28DCD8E58C622405776221505644B401752798858C622404E60701705644B4003FC4CF858C62240E1657E1D05644B4090D3042A59C6224033DD2E2005644B40ECF5AA6C5CC62240790E5C4D05644B40464249B75DC622400FA2415F05644B40B4B5C0B763C62240E72EA3CC05644B404D32E1007EC622400DBCA3AB07644B400A0F938CB3C62240109B667B0B644B40FFFEF26651C82240D38C72F028644B4087CD150852C82240667DE9FB28644B401F8482F751C82240BE8D5F0029644B40ABBE866652C822408857460829644B40A010D97453C8224067A3831B29644B40D31AF39E58C82240C1E39D7929644B406412DB9A59C822402A518B8B29644B4011E4C06A60C82240131611BB27644B403BE7D98961C82240BBA0AD6527644B407B3A4AEC66C822406AA8B6CB25644B40F16E52B567C82240455C6B8825644B401DD83FC06BC8224003CEE92D24644B40E72D93D26CC82240CB0A13D223644B40C586841A72C82240D17E29CF21644B40394CFC8975C822403674DF0B20644B40EADD8C928AC822403432767012644B4020AE896493C82240F24AF3580C644B40BC3230529AC82240BEBEF18F07644B4007379D40A4C82240D9D34D92FF634B405105A738A9C822401F3DBA14FB634B4081E59795ACC82240DDA8A00AF8634B40FFA3FBBFB4C82240E1A3DC2AF3634B4041BAF6D3C8C8224017C813C1E8634B40F3F0547ADEC8224068AE13C5DD634B4038AAD8D2E3C82240CD27BE0EDB634B40CA93D8ECE5C82240410B3126DA634B40F304140CE7C822407B4F74C7D9634B40AFC3830EE8C82240F77E3572D9634B40BCD7BB95E8C8224003489945D9634B40A50E05A3EAC82240121EA4ABD8634B4045E3BA4BEDC82240ED0725E4D7634B40FF61ED5BEDC82240A3C463DFD7634B4016F97280EDC822408E76AFD4D7634B4084DF4B95EEC822402EAF68E8D7634B40D3C90E94EEC822405FB7C1E8D7634B403329A99EEEC82240F36F14E9D7634B40A24622A8FEC82240EA00920DD9634B4006957C0C0FC92240BABEC829DA634B400F0AEF2B59C922403852ED2EDF634B40494A75835EC9224003E5347FDF634B40891D179565C92240781470E9DF634B404BE3DA7572C922406C7BAA71E0634B402307B5567CC92240754BD3B0E0634B40585572A87FC9224042360BC6E0634B4064EB02068DC922408E939BE5E0634B40ACC1EEE48DC92240FCB632E4E0634B400BB520C898C92240375A9ED2E0634B40FECF570499C922401FD5E4D2E0634B4065C609EA99C92240EF7DF5D3E0634B4045FB58B99AC92240398430CEE0634B40FC0CD5A4A7C92240F0E27285E0634B4045CDC4F0A8C92240EC4DC578E0634B40E4D512EEAEC9224032AD353EE0634B40B89027BEB1C922405D5EB422E0634B403204D297B4C92240E76CD406E0634B40DB2707E6B7C9224034A2FFD7DF634B4049BAC4B8BDC922407BBB7D85DF634B401CF9211AC1C92240C1AB9855DF634B408BE510D5CCC9224006D8C094DE634B40AA82FD6AD1C92240AAD45E49DE634B40A1BE82C6D6C9224014354CF1DD634B40B8A9F0E4D7C92240EA81E7DEDD634B405AB0BBBEDFC92240833DDC5DDD634B40E33E8711E0C922408E048658DD634B40DE27A801DBC92240A76A0CF2DB634B4034F3D754D6C9224018857784DA634B40FA91A013D4C92240E4377AC0D9634B407A1EE20CD2C92240DFD75310D9634B40B9F39F2BCEC9224043783996D7634B4061602A72CCC922401001D1D7D6634B4023E47FB2CAC92240B791C016D6634B407EBF7EDCC7C9224071E501AFD4634B4029B4C4EBC1C92240BF0A7834D0634B40C5A9256BC0C9224066A877EDCD634B4010BB6C3DC0C9224000300229CD634B405A25482FC1C922407EA15F4CC5634B405704A67BC2C922403DFE9833C3634B40D5C4708FCCC92240DD396918B8634B40CD51FAA8DFC92240B6AB642AA2634B405CCAE459F0C92240D034DA908F634B4040D42726F1C92240C34F33948E634B4053DEFE83F6C9224010B01AB288634B402BC17F89F6C922403B9E11AC88634B40AF1F0D8EF6C92240AB360FA788634B404A62D694F6C9224018AE2CA788634B40E15EBD9E4BCA22408ECAA1218A634B40DE8D9BCA4BCA224064F1DA228A634B40E338B12055CA224070E9734C8A634B4032AC35EF61CA2240E61083858A634B4098E54AEF78CA22402E4477EC8A634B4003F59620A6CA2240D17ABEB68B634B402BF0B87DC4CA2240C329013C8C634B40E91702DED8CA2240D3EF1F888C634B406208A1E5D8CA224002393D888C634B40475FDF35EDCA2240EF1FF5F08C634B405903C0CC2CCB2240883FD4F58E634B40B61A9CDB34CB22407D63293A8F634B401FD9A82836CB2240D28532458F634B40D442D9E655CB2240FBEE655290634B408DDDBB0076CB2240664D082791634B4014FDD0919CCB2240612955F091634B40ABF44C58E6CB22402281B12493634B406162CD3FEACB2240BBA4A93A93634B40AB074FEDECCB2240BE9A4F4B93634B40D5330987EDCB2240686B0B4F93634B401171D2E2F4CB22405EB6CF7C93634B404A034945F5CB2240C460BC7E93634B40F3DF8944F5CB2240B30DA67F93634B40DB32BE58F5CB2240F1F30B8093634B40D4FEDA7B24CC2240E939476A94634B40F73CA16245CC224037BE6A0E95634B40A0B3FCD981CC22403D31B74696634B400A078E8A84CC22402FDF9D4996634B40B3E6734BA1CC224009A5A56896634B406EDAB6FDA2CC224053C4796A96634B40F7A2970CA7CC22403818DA6E96634B40EA51E36EB5CC2240D13FDFA796634B4005B4F7D6B9CC22405C3B58B996634B405134EE12CDCC2240D6DD960597634B400E1A8069CFCC22407FCCDB0E97634B406A061D34D9CC224065BBAC3597634B40D9049D61FACC22406BC3100098634B40AD07EC4636CD2240BDCF05C899634B403B50636339CD224059A7B0E199634B4003F5C19948CD2240F73B345F9A634B407D14EA844ECD2240DA2408909A634B40444D1B8E52CD2240BD1354B19A634B40AF8E53C568CD2240104997469B634B4089AAD3736CCD2240818F545F9B634B40D22CED6B75CD2240BF4913849B634B40ECD2986D75CD224071A71A849B634B40ECA3153A88CD2240C8CC1CD19B634B40CD8FB6C092CD2240668D36E59B634B40D10D42A39ACD2240128D43F49B634B40DC2AE5ECA5CD2240F4C9D0099C634B408354628CB2CD2240FE18EB219C634B408721DFCFDBCD22401F1288F49C634B404EED062AECCD2240044D186F9D634B406156B754EFCD2240CB58D5869D634B404D974C7701CE22409AABC00E9E634B402A737EC40CCE224014A476639E634B40B5ABB1430ECE2240280DAE6E9E634B40903F8AA912CE22404D4B1C809E634B40E916AEAB12CE2240378F23809E634B40A4964A142DCE22409CA6CCE89E634B402D2A7AB32FCE22405C4E30F39E634B4003E3C47494CE22400ABA4FDAA0634B40A5C12CD49FCE2240ECDFE200A1634B404FD10279C5CE22402D248F80A1634B40D1188916D4CE2240AE3120B2A1634B40D0EDAFABE0CE22400AFACD01A2634B40CAE924CEE8CE22403C095135A2634B40371C6DBDF4CE224009C6B4B0A2634B40CC10546FF9CE2240E2EA3DE1A2634B405FD4C20105CF224061EEDE58A3634B40E4949EB906CF2240F48AA26AA3634B40E98F55D00ACF22401024E894A3634B406828AE9B14CF2240F7FA4616A4634B40E26D386A26CF2240B81E7A01A5634B4046A452D08ECF224026B05230AA634B40B37BD03191CF2240054E944EAA634B402FBDC751A0CF2240DC699210AB634B40CA061B1FC5CF2240C0FA0DE3AC634B40887AC61D58D02240D9DA3B33B4634B4046A7978962D022406043E7C3B4634B407BF9E1C969D0224002419228B5634B4023BDD9DD6ED0224070B9C063B5634B409EA6B5808AD02240C502DDA5B6634B409012711195D0224092DAFF20B7634B403D7DD6D99FD022407F81AE9EB7634B402FE1C9EF9FD022403D65AC9FB7634B4074A35720A0D022407A00E3A1B7634B401FAC927EA8D02240799F800FB8634B407B4F4755D1D022401DBE7626BA634B40FEBE3190D1D02240448A7B29BA634B4049C4F9F5E8D022404A959698BB634B406E7A533C96D12240680C3F21C9634B400257ABFD9CD122401B2952A8C9634B40BBAA50F7A5D122407C6DC55BCA634B4065EC6CBDE3D122407EF65609CF634B40921BDB4E08D2224026313FCED1634B40C0E1D7903CD22240C2C34AC3D5634B406B2D64B241D222403610C326D6634B40C6D001A2D8D222402FDEA494E1634B40154B2DD71BD322404D9968ABE6634B406C8BF93855D32240C930B003EB634B40FD4A9A8F57D32240179E0531EB634B40F2DA163C58D322402454133EEB634B40BAB27D3F58D322407F22563EEB634B404A01C7885CD32240AE700796EA634B40E2A7FF0D65D322403259C561E9634B40B57E91196FD32240156FE812E8634B40F5B8878179D322406A087BD3E6634B4003C2784184D322405B1E07A4E5634B40E23C5C328CD32240F62045D6E4634B408C38C5548FD32240A20F0D85E4634B40B427C0B69AD32240DB730777E3634B40BC3C9462A6D322406433697AE2634B404C803653B2D3224044789F8FE1634B40F2872415B8D32240EBF0AF37E1634B406650FAF3C5D3224043E2D863E0634B40189C7CFCD8D322405B068172DF634B4098A7710ADAD32240D3472265DF634B401B144C83EED3224044167194DE634B4026D3B14A03D42240AC768EF2DD634B40D98D235A3AD4224016D909A0DC634B400E99B60B4ED42240E21EF526DC634B40880D490451D422402D93B014DC634B400E0B981052D4224009A53F0EDC634B40F8C40EDC53D4224019E58E5CDE634B408153E79B54D42240C6070053DF634B405960E7EC55D42240189286A0E0634B408799B3E557D422402B593094E2634B40C4682BED5BD422406E2EE9D0E5634B4051E21FB160D42240D91E4508E9634B40DD77550263D422400FA8C884EA634B405AB88EBD65D42240E24385FDEB634B40237D0A2F66D4224037F81032EC634B40FB23BAE168D42240ADECDC71ED634B401A2E838169D42240189383B2ED634B40182C766D6CD422404F9C33E1EE634B40C2E5535F70D42240654FED4AF0634B4063DAA1B574D422403ADB73AEF1634B40CC80866E79D42240BC1D310BF3634B40FF919F2F7BD4224022639F80F3634B40D12F1B887ED42240D6C19460F4634B406295D59787D42240D91A90E3F6634B40D530E1288AD42240D1119B86F7634B405AF0EC7491D422400FE32E56F9634B4039AED5179ED42240FA1F5222FC634B40AB25851C9ED42240EB7E5923FC634B40C4CE7884E1D422401EAB390F0A644B4013D71270EBD42240ACEB3AF40B644B4088ED0E54EDD422403EA44C4A0C644B40F68830CEF5D422401EAB42CC0D644B409207DF64FBD42240D6A559BA0E644B400CAF1A6EFFD42240F9084A660F644B40E4C26E6409D52240E89623F510644B40401AB5AE13D522402B5E6F7812644B40F598684A1ED52240DD7CCBEF13644B40B9F260564FD522405BFDA86F1A644B40682E8DE150D52240415A1BA41A644B4097BFFA1E54D5224027E830121B644B407829D5AB67D52240420569AA1D644B4065ED82BA86D5224035FB9BC921644B40CE73DF6F8BD522407CD4936922644B40C7AC204D98D522409624A51E24644B401ADDB9D99AD5224095F9427524644B400C420915A4D52240AAC4E7AE25644B4091BE148CD2D52240778E8BD92B644B4088056F76E5D522402DCD2E5C2E644B40D236F662F8D522400FC6789D30644B408116A1FB0BD62240818032BF32644B407A19CAF512D622400901277033644B40E3CF932714D62240F555758E33644B407F89A23620D622409D214AC034644B403359C30935D62240EF32C19F36644B403A1774A14DD62240CBC2F9F938644B40E3C5E6FE66D6224028EBA5263B644B40A6FF4A1281D622400ACB6B243D644B409C8C66CB9BD62240EC9E0CF23E644B40A0A789C5AFD622406D4FF33B40644B407B751EF2C3D622404F75067541644B40D8CC794ED8D622405D411A9D42644B404806FED7ECD62240A3BD06B443644B408D942B168BD72240BBFAC3B24B644B40CDBD948290D72240753CEAF84B644B4073AEC82C9BD722400436B4AC4C644B40F6B228A29ED7224022C54DED4C644B40C1528FFCA3D7224058A04A514D644B4072150CA3A5D7224008B91E704D644B4050904E01A8D72240452FD6A04D644B403B122FE1AFD72240F0B8D7424E644B40E29BD9E2B9D7224027448B244F644B401FAA10A4C3D7224046C0D91450644B40E76A4C84C9D72240CE737FB250644B40C046D920CDD722400381651351644B40911DD5BACFD722401FD53E5F51644B40EE9ECA21D0D72240F01AF86A51644B4016E93755D6D72240ED57C31F52644B406214813DDFD72240C916863953644B40A552ADCAF6D722408F5BBF6F56644B401A1D561B05D82240C09F816358644B4029B7B0A407D82240F8880EBC58644B40049679FD07D822402E6F2BC858644B4093F0D3D60FD822400D3030DA59644B4030AD8E3540D822400EE8D37260644B40BF90584740D82240B13B417560644B4013F4591341D822402976478E60644B40FE60F6BB83D82240728E88BB68644B4078EFF3570AD922402095CA7678644B40FD04AE7318D92240D403E31C7A644B4052E1AF7F18D92240E4264B1E7A644B401EF877FC1DD92240BA0879C27A644B408BEB81F840D922402D5C2CD97E644B405267923B4BD922408D41340C80644B4092044C844BD922409559B41480644B4053B210474DD92240AA1B9FFE7F644B40B0AFD25D4FD92240E4F06D3080644B402F38B50255D922405239AD9D7F644B40C7A843FF55D92240E10909847F644B40952BC9A558D92240D58FCE627F644B40A8BD756059D92240C48944577F644B40534F2AD15CD922404110DC207F644B40961BDE685DD92240EFF57D177F644B407EBA3E3D70D92240F207B4ED7D644B40AFFF3D7388D9224044B9D3007C644B40786291878CD922409F5EC7AD7B644B40F840269293D922404C7F6F1E7B644B4032DB0A8DB3D92240227CCE1878644B40B705067FDAD92240ED885C7576644B40E12D8433EDD92240B5FB240C76644B40D40BBB1E01DA224002C76B8272644B407578D8EE0CDA2240EB54010970644B405A4B74CE0DDA2240BA53C11370644B409C6FF3020EDA2240B94FC30870644B402A52E5FFBADA224074A7D25978644B4003AC78D9E0DA224064CB822D7A644B403D3E9E8672DB22406205773781644B40950782A881DB2240194C6CDD81644B40C6E634B190DB2240F7444D8282644B40EC484ACF99DB2240FA4D534083644B40FED665329DDB2240774F90D283644B40A25B15BB9EDB22409513417A84644B40622883BAA1DB2240261B21F685644B408060D4E4A0DB2240322C986D87644B40E7E8B129ADDB22407919F80188644B40992C8BDAB3DB2240C10EE25288644B40F3CFCC44C7DB2240A409AD3D89644B40A06BB684D1DB22403DDAA0B989644B40FF4FA2D224DC22402DE009A98D644B405A0F81E23CDC2240967E02CC8E644B403DF302A54ADC22404E1967728F644B40EB737C714DDC22405CE53F948F644B406BFB3E8D1FDC2240D79F4CBCA1644B4018EB7A711CDC2240E16020F7A2644B405AB2C3691BDC2240262C785FA3644B4086F149C91FDC22401E634BAAA3644B40131C887C27DC2240A735092EA4644B404B326A4B5ADC22403D3A5693A7644B40DE5A483767DC2240FC8BA985AD644B40C75EC1FB66DC2240123443EDB1644B40E11B21F366DC2240D8243690B2644B40BAF2F2EA66DC2240EAB83A2BB3644B402AAAFF5C67DC22402AE24288B3644B4000E35DDF68DC224090BB84C3B4644B40AF3E6CA574DC22400C9A6713B9644B408FDF3A157DDC22404240F7F9BA644B405B4A393093DC2240A59EA95EBF644B40533E29E8B7DC2240A945D7AAC6644B40A9C11B1CC1DC2240D584127FC8644B4097A71063C2DC2240424A0DC0C8644B40324A77F9C2DC2240C3F8EFDDC8644B4068CE9BEDC5DC22407EEAB228C8644B4067495196CADC2240B2264F3EC7644B405CFD0079CDDC22403DDB6BC9C6644B408F1BF6E3CFDC2240D5B07867C6644B4060915AC7D5DC224053C296A6C5644B40CABE095BD8DC2240B159B662C5644B4026418F77D8DC224015EBC65FC5644B4097F1782FDCDC2240D92BD5FDC4644B40A970892DE6DC2240807E1A13C4644B4074E4360FF2DC2240A30470E5C2644B400450C7A3FDDC224006D126A8C1644B40050170E708DD224068FAA75BC0644B40EF75B8F110DD224073B4485CBF644B4083AD089B11DD224068074847BF644B40D19C66D613DD2240D04F6400BF644B400FBB3A8521DD2240B14FCCDBBC644B4025D860D92EDD22409B3E67ABBA644B401FF9F8FC3ADD2240B4FF0E94B8644B408492FBD03BDD2240689B866FB8644B407B8B2D6A48DD2240F3E47B28B6644B401E6B66BC53DD2240F1978DFEB3644B404B92145254DD22408036F2E1B3644B40389B1EFE54DD22406A4411C1B3644B40A62161D260DD22403F9EA945B1644B4026B102E16BDD2240D5D582B7AE644B408DDCA66070DD2240B6932591AD644B404C557C2476DD22404038E817AC644B40778CFD6A76DD224035181207AC644B40DCA4FDF37CDD2240183B8D77AA644B409D42766183DD22404704F4CEA8644B4045F0176B89DD2240C094961EA7644B406A0AA7D38ADD2240C40FCEB0A6644B40743FA1548BDD2240F79F8A89A6644B400CB1140F8FDD224084B7F466A5644B40BE4F61D593DD224023BB3AF1A2644B408EA7F71797DD2240BB4E3D43A1644B402B8C9E9F98DD22406B4FAC7EA0644B40907DD039A0DD22403F62D6AD9C644B40CD473240A1DD2240834555449C644B40DCC782C2A2DD2240C42100A99B644B4007A9BC2EA6DD224093576FB29A644B40397AE951A8DD2240DADF402E9A644B40B8A10EDFA8DD2240276B2A0C9A644B40D2A6BD47A9DD2240D6C4E0F299644B40EEB146EFA9DD2240276069CA99644B400C8C5671ACDD22407C4BB81999644B4000A3E667AEDD224011B3D55F98644B40281C2E11BBDD22408082A9CB92644B4004B68AB0BEDD22408067073391644B403F725E7AD7DD2240BE32DD4686644B402CF1D9BEE7DD2240267FD81B7F644B40580E57D0F9DD2240C92DAB2577644B400C1F57DFFFDD22408EB883F274644B40	Flensburg 9	\N	fl9
11	organization	102	0103000020E610000001000000B3020000D055C35B8BBD22401923D88E54634B4070E43880A7BD2240768D3A8754634B40D483D3CAB7BD2240C6660A9C54634B4054F43928BDBD22409E69A19D54634B40C1D4BC52C0BD22405AB9EEA654634B40E0E560A0C3BD2240FC3026AB54634B406E37D1AFDFBD2240451D8CFA54634B40E3870DC9F0BD2240FF5AA44555634B4038652BDDFCBD2240078CB37155634B4080F1522A15BE22409D4D8FD055634B40E1FCEE2C15BE22400E7198D055634B4050200DA872BE224045A1723D57634B406E3E1C71B4BE224070DC2C3E58634B4092F6CD67B7BE224092DEBC4958634B400A4B1D78B7BE224059358B3258634B402EEA19D19CBF2240211755965B634B40AF4A9F0AC1BF224062F608235C634B4078922F46F8C02240115BABDB60634B40540D6DBF4CC12240D59B010862634B40E34069C366C122406742D94A62634B40835F53016BC122401CACBF5562634B40747833F575C122408E53DA5662634B4016706B7390C122408D2A885962634B4083E1B13994C12240BD49955862634B405A4B7F3B94C1224078C0285562634B40AE4CBF299FC122408AFC814862634B40494F4914BBC12240C8A2322862634B408FFAE1B97CC22240C707080B62634B40CE9F4AE782C222403657180A62634B40DF3CEE1588C22240AC17500962634B4050849D56A3C222408FAE921562634B4048C50BF2C8C22240753DAA2362634B40CF9E79E4E6C22240E411E32E62634B40DF9487F422C32240BD6E604562634B404D34141E23C32240A86B0F4662634B406D5BF3E436C32240259C754D62634B4035A80D533EC3224083AB465B62634B40567A6CD23EC322403D84335C62634B40BA4AC39255C322405FD47F8662634B40D55AEB566BC32240C63CF7AE62634B40D732791B6DC322407B3242B262634B40400BE5F970C32240D5B072B962634B400D8E5A0972C32240B46132B962634B40B1D8F10D72C32240295135B962634B40527CDAAAC6C32240A8403BA562634B40D1B1FAA5DEC32240B07D8E9F62634B40AEDF4756E4C32240886C369E62634B40E57C2151FEC32240042A129862634B4081332E65FFC322401AB4D29762634B404A7A14E13AC422409EBF9E7B61634B404BF138553BC42240658B747961634B400167C59C62C42240F7DD031660634B4055F6003868C42240D59E48E35F634B40AD7C096D68C422401AEC68E15F634B408E40006476C42240D846CB7A5F634B401328268183C4224063F66E1A5F634B40B7C993A291C42240015599B25E634B401846B2F59DC422406B3607585E634B40B25CEDA8E3C42240CA52D5575C634B40FCB5806862C52240B5975EB458634B40A7CEC33185C522406C55B6B457634B402EF4D37485C52240ED11CAB257634B403BEECD522CC822407A48ED50C3624B409E129D872CC82240645A6145C3624B40783698DC2CC822406CE7CD32C3624B4076F3557D4EC822405CEF9A88C6624B4055C6D1D851C822409490D8DDC6624B404BF65B2959C82240784F8F97C7624B405762C3ED83C8224029F6759FCB624B40F90DF950BAC8224029DAE9E0D0624B40C97537C6C9C8224021564171D2624B40973852F6ECC82240F63A9400D6624B4091B38EC21CC92240F6AC216ADA624B40FA8A974F2BC92240089CFCC1DB624B40927017025DC92240B0AC1F7AE0624B409ABF222473C92240101B158BE2624B40AC5CF82283C922408F2403E4E3624B403049673D84C922404430CDFBE3624B403C898EB795C922400DFA5D53E5624B408F1F4660B9C92240B8B2C1FAE7624B40AFA484864CCA224072F232EEF2624B409B6CB29A4ECA224053A7250FF3624B40F0358DAF52CA2240428BD44FF3624B40C9E23CB752CA2240B1744E50F3624B40CF9780C552CA22404486EF50F3624B405B453CBA6ACA2240027A9FCBF4624B40D7AA147294CA22408EFE125FF7624B40DF7FBEDAD8CA2240D44FF56DFB624B4084B8146F06CB22404591759BFD624B4044A46933D1CB224080021F3D04634B400B1082F7D5CB2240C8881B7304634B40BFE0E341D6CB2240F46D885804634B4010F38155D6CB224042E30A4A04634B407E179A50DFCB22408CBD0CACFD624B409BB0924924CC224078987ED9CA624B40CF3D012835CC22405ABB178ABE624B402323E4DF4CCC2240046CB775B1624B40247F80174ECC22408842DDC9B0624B4036F143C24ECC2240EF7FB36BB0624B40FCAC4BC74ECC224034220F5BB0624B40BE9C86C74ECC2240FA4D485AB0624B40880293AD4FCC2240F634D149B0624B401B70462C50CC2240F0DFBF40B0624B405540B33450CC224049D91F40B0624B4042168C4476CC2240A1A15B73AD624B4048B86D3992CC224005EF8140AB624B40A65F8BE29CCC2240AF1E9B68AA624B40194109F3E3CC2240323D5FC9A4624B40194E32DBE8CC22409264FE65A4624B408E6F3C4FF1CC224035DD31D6A3624B4099857D7EFDCC22406243EE06A3624B4005843BAA4ECD22402E5511369D624B4050718BD94FCD2240B320681D9D624B40417AC2B776CD22405D7554F499624B40676F97AD8FCD2240314C9A6998624B40B13D5C0C90CD224030CE916998624B407F91AE0096CD224040BCC26898624B40434D849F98CD22400DD0666898624B4044A28AA298CD2240F73D646898624B40E3B0E0D09ACD224082C65A5898624B40910AA9FA9ACD2240D2C9265798624B405280F6209CCD22409EC5B24E98624B4071DA62299CCD2240DF15094E98624B40764D002B9CCD2240F529FD4D98624B40B4BDCDD7A1CD224015CD152498624B407AB96DA0ABCD2240892A4FDC97624B40285312FFAECD2240C39995C397624B4005F3087EAFCD22403091F1BF97624B4045B81A9EB1CD22403B4BE9C697624B401D6E1F7BB7CD224052CB24DA97624B40C689D603BACD2240D4E375E997624B4007D0ADF6CECD2240273F186898624B40F97F5725E4CD2240D11306F598624B40FF290C7B07CE2240A9FC2C6C99624B40F8A894AB30CE2240C19B4D8999624B409783FB4B31CE22407C34BE8999624B40549E451D39CE22403425C67C99624B40848091FA45CE2240CE3F976999624B4012D5FF8648CE2240E29CC96699624B406009AF8649CE2240498AAF6599624B402F1A428650CE2240FF3E15AD98624B409DF0CA1D67CE2240F900DA5297624B40D6B5E8077ECE2240F97E0B5996624B40C249A2058BCE22401FCE26CD95624B400884E7869CCE2240E041C5C894624B40156F4ED7A1CE22405409BA7994624B406D4F42F4A3CE22405B1BE16294624B40B5A2267FDCCE2240818670FF91624B40D73DEAEA08CF22402348AD038C624B4039D6657B0ACF22404F3073E78B624B4031BA542E40CF22402A9EA72688624B400D742DA540CF22409191581E88624B405F9F540241CF2240E176D61788624B409A15C1AB6CCF22403C00CE9789624B402636474296CF2240C7A4E2AC8C624B40D32EEA74A5CF22401ACD245F8D624B4088E2C4EFCCCF22401EB6372E8F624B405E5C84F5CCCF22401EF57B2E8F624B40E7083385E4CF2240760F70238F624B4065DB21C304D0224065CE53148F624B404F9A73D005D02240349BD4138F624B4027ABABC628D022400DB6887490624B402FF9FB344ED02240B84C81ED91624B40F8BC05A87CD02240BFBDE56097624B40764EF1D58ED022402468A74F9A624B40DD30C9969BD0224005A0515E9C624B401DFF22A0BBD0224005EA1A6EA0624B40429D03A90FD12240AA6EF390A7624B40B465649F14D1224007D3D4FCA7624B4069FD209A15D122400FB29F03A8624B40BA5749D918D12240CE2D191AA8624B40D001652D27D12240EF7F707DA8624B40DE7B212C2CD12240847FCB9FA8624B40B37E441031D1224031342CC2A8624B4006B9F5CE3BD122403A0CAD0CA9624B4001DCF91D3DD12240F3758C2AA9624B40AB1C09303DD12240826D292CA9624B40EA68B29159D1224087EF35B6AB624B40E73A15305DD1224025851009AC624B4068CBA57B63D122402593D41FAC624B40F2846AE596D1224016C496D8AC624B4056744A28D6D12240A4359205AD624B40B1F059BBD7D12240E83B6E0FAD624B407D639751EBD1224020830C8AAD624B403E1175AC09D22240BFFF34DAAD624B403920B5560DD22240C797E2E3AD624B4094908D680DD222408AE810E4AD624B406506816414D22240086782F6AD624B40EFEF4B8914D22240755207F7AD624B402E7D66891FD22240BE7CF813AE624B406214CBC722D2224072D8801CAE624B4023D401F222D22240454AF11CAE624B405BFCFEBB23D22240ABAB041FAE624B40F893FEEC46D2224053B3E712AB624B40EE3858078CD222402C93E4A4A7624B40EE6938DCB9D22240434742E0A4624B40044DEFEFDCD22240F38F9296A2624B408132417B09D322402FCE99AF9F624B40D25EA62B24D3224099FC68F29D624B40421EE7F826D32240F0EBC4C39D624B40212416C943D32240F14303E39B624B40DEC7DC5D44D322405AE54FD99B624B40458DD67144D322408E7603D89B624B40EAF63FA17BD32240BD469E3F98624B40DF18DE0F9CD32240FF69811696624B40CB61E3019DD32240070CEC1296624B40E7B0CE049DD32240CEC2E11296624B40FC9C4D609DD3224062E2C50C96624B40BA5778689DD3224091023D0C96624B40B351D5C9E8D322408C5280EE94624B405F90A0B2E9D322401FB40DEB94624B409C216F38EAD32240D5DE11E994624B40954CEF7F57D422400613A54096624B40A1E4E52F58D422400A0FCF4296624B406894D77470D42240F2ADE2AD95624B40F60E780771D422403C205EAA95624B4013D9D2ADBFD42240BC0579A897624B404E4A9D39C3D422407C5B0DBA97624B40EFE542D534D522401FBD2DED99624B4055D9D42655D522406617C5669B624B40F348129F55D52240B4B9406C9B624B4085BB78865FD522405CE5C8929B624B4045BD89CA89D52240D279D7FD9B624B409F664DCC89D52240CD1E9FFD9B624B40B9B0E8BC8AD5224031E63D009C624B4085E49C2797D522402DEB45769A624B40C7FE1931A8D52240EEDAB65998624B40AAA0291CAAD522405BAADA1C98624B40A0855D2CAAD52240FA17691C98624B40DE00660CBCD522405676F19E97624B40585D9164BCD52240E169B59B97624B40214360A9BFD52240DFC0C38497624B4001FDB3DBBFD522405525618397624B402D7EA68AC0D52240C5CA957E97624B40F2920D48FBD522406EA707C19B624B4085FCE3EB06D6224095417BE79B624B4000C8066F0ED62240140E4B009C624B403376FE8D0FD622407909FF039C624B40724124B40FD6224095B77D049C624B401955639310D62240F16B7B169C624B401F0D689910D62240E377F9169C624B409E9F4A4D12D6224048BE097E9B624B40013A625D12D622400C9F62789B624B405353588012D6224096AA1E6C9B624B407DF5181721D62240A4421B649C624B40BC359F2126D62240F41B6CC69C624B4023A1812326D62240C22696C69C624B40B8549CA629D62240CB7E1B0B9D624B40303EEBA729D62240B039360B9D624B40077E49DB30D62240BC7D6ACF9D624B40F0047EDC30D62240AAF68CCF9D624B402072DAFF30D62240710B4CD39D624B40EC7B1C0131D62240825D72D39D624B407605CEC434D62240FE17185A9E624B406F15E8C534D62240F160405A9E624B40C647C14D38D6224048BE99DC9E624B401B12CE4E38D6224035F8C3DC9E624B40D92E2D483DD62240EDD587D59F624B40668957873DD622406D1D04E69F624B400DF95EE244D62240901B39D2A1624B402A7B6B234BD62240FD4EAC74A3624B407B6628244BD62240B464DC74A3624B40B3E1E6374FD622400DB1CE89A4624B40965C79B25ED622402D7138A5A8624B405D7496B65ED62240E54C51A6A8624B407996DC2F60D62240B3286E0AA9624B403182993060D62240643E9E0AA9624B402C0054C462D6224063B3ABB9A9624B40BBD8A29666D62240F0663EBDAA624B40E8822DF767D6224094F8C91AAB624B40DE30020B68D6224096404217AB624B402B52A2426BD62240308CAC84AA624B4004EFC0E96CD62240313D3739AA624B40519F563A6FD622409B138ACFA9624B4076B54AE776D62240667DD571A8624B40F5CE4BF97FD622401C218ED4A6624B40831F145290D622408142C0EBA3624B40B581B50F93D622401B71E26EA3624B40C33B4A38AED622407BEB9D659E624B40D709A642DBD622408C01750B96624B40FFE93021E1D62240A3D5D2F494624B4095EDA07DE1D6224077508AE394624B40AB5242B790D72240B82F785574624B40A0541F65C8D7224099FC65AE69624B401E9650B0CAD722406D230F3E69624B4054C070C2CAD722405CC6F53A69624B40B9E36D4BD1D72240061BE2FA67624B40608FBA2FE4D7224021F7B44964624B40F7F7A2B7F4D7224011C1A20E61624B40C1CD1EBDF4D72240937C8F0D61624B400B2182F2F4D722404BAE120361624B400A56F7FB1ED82240075D3CC058624B4022F4294731D82240777FCF1455624B40DF32CA1D37D8224054B09EE753624B4096EF156437D822401BD9E2DA53624B408273FFAA6FD82240DC31DC9048624B40F238522EBAD82240E6CB520A39624B40F97F3CF5C6D822400B1B605236624B40FB42AA3ECAD8224091C1599F35624B408B5D0D4125D92240C7FD234222624B4004F6D57A3CD92240DB4E46341D624B4081701B6240D922405E44D05A1C624B40B0FE175879D9224046DC8FF50F624B408070EC78B6D922403CEAB0E601624B40B7A13634B8D9224076A0BF8001624B40CEEE955DF2D92240CE572718F4614B40C0D06E1B42DA224040BF1B09E1614B40411555838CDA2240905A4140CF614B40BF3EAE67A0DA22400EA5CA55CA614B40E0C2D679A3DA224090618193C9614B40A9B18D31C0DA2240DF9BAB7AC2614B40A7645D2ECEDA2240E345BC05BF614B402A182475EADA22407079C408B8614B40B0DF00ACEADA2240E3B135FBB7614B408ED2848C2ADB2240D335B61AA7614B408CD27DA72ADB22400B249613A7614B401E8B054338DB22403BBA2D7BA3614B40243C86403DDB224038C4A229A2614B40AE82DCF05DDB22407F1AAA3999614B4024863B6C5FDB2240A884F1D198614B40A7532AFC5FDB2240B5B695AA98614B408583998361DB2240CAE2923F98614B40521FB4D673DB22404AFBF73C93614B404870A63476DB2240CC6F548192614B402572B9AF92DB2240273F97AF89614B4012774AB792DB2240F5423FAD89614B40BB044FB793DB224084800B4A89614B4026A5BE429CDB224066F0ADA486614B400FD5372EC1DB22409241ED617A614B40ACB8A925DEDB22400CB2BBF46E614B4098FC92E7DFDB2240E59ACD556E614B4076181A0BE1DB22403020D2E26D614B40FFCE3891E1DB224016B1E4AD6D614B400FD663F7E1DB2240125099856D614B40201EF3D4F1DB2240EA668D7966614B40293F68E0F4DB22407423531F65614B4032E5B19D06DC224079532D3E5D614B40A53C76180ADC2240788980B25B614B405D4B747024DC2240E0DA910C4E614B40DFA2B90726DC2240F2038A394D614B40E85316443BDC224031E272953F614B406AA3DF264ADC22400C14DA7835614B40774697F04CDC2240BE84059433614B40183DF2E54EDC2240459D773F32614B404FE722D150DC2240CB4D797730614B409D812AA15CDC22408A92608025614B4053FC342F6ADC2240C9AC97A014614B40BA49CA366ADC224046FE619214614B40701F032973DC22409117ECC103614B40DE2FA4B876DC22402BAD028AF8604B406907F1C876DC22400FD6E7B1F6604B4048771AD676DC22401A83AF35F5604B4063D145E676DC2240BD3EA460F3604B405271A6E876DC224034B75D1BF3604B402AD57DEA76DC224007ABF0E6F2604B4010DDC3EC76DC22400FD25BA5F2604B40DE4846F676DC224044597A91F1604B40F127407276DC2240FB0A6DEBEE604B40270F2D2876DC22402A5B166FED604B4043EB7EB575DC2240B2CA3922EB604B407907D15A75DC2240623C9050E9604B409EDEC53374DC22404B235865E3604B40E512D19B6FDC22406B60AD6ED6604B40520B93D169DC2240167E7EFBCC604B40E7B1A55963DC22408DC0C82BC5604B4043962E305CDC2240CDF0AB85BC604B40E056DCB950DC22404EDC17AEB2604B40351E633C48DC224051FB8955AC604B406CBCFEF246DC224065D6F34DAA604B40884BC03544DC2240DBA8568CA8604B409FD1622144DC224020994E7FA8604B40F4F7675524DC22407FA2B91C94604B4082B2565324DC2240509AEB1B94604B40CC9AB0EF1BDC22406E12C64F90604B4010652F5619DC224084AB20E98E604B409B41290600DC2240E48CE25482604B40718A3C4DE1DB2240C506523275604B400C91F3B4D9DB22403E6AC73472604B40044DBD83D7DB2240677CCD5771604B40727D6F95CCDB22401F7FA87D71604B40E0D976F637DB2240C3554F8073604B40D801928619DB22401D0B73EB73604B40E624C46BF9DA2240B697EC5974604B40E989B551A3DA22403BC2028275604B406B88BA4B76DA2240464CDF1C76604B40EDC14D5D61DA2240EC6AFBE275604B4045D83EAF43DA22406E38E29075604B40A7C33A11C8D922408F92C2DE73604B40F0D89D8EACD8224028D92CF46F604B409ADDEB1880D82240412068536F604B4095F5BCD8F6D722407E890C636D604B40FD088D70ECD7224025BFB7486D604B40AB52661DD5D72240B3A09E116D604B40168B6EC995D72240491E067C6C604B4090E00F7388D722406C06855C6C604B408F84955F85D7224098B559D96B604B40FC866BA882D7224051E1E3D56B604B407441CD1F81D72240EFCB42D66B604B4042B857FB5CD722407D36F2BB6B604B403841A79E5AD722402266FABD6B604B406BA1653D58D72240208F07C36B604B4036C49C3242D72240EC3D52E56B604B403F6DB02EBFD62240B92ABB6A6A604B4044C6915E60D622401E7261B069604B405C1531F0F4D52240AB40929168604B4042CBB44BDCD5224002B6235068604B40F0087742C5D522408ABA3C4F68604B4036ABB528B9D522400B51C24E68604B401563408DB3D5224013F0363A68604B40B0C1BF7EB3D52240F33B003A68604B403E2D8ECCAAD522409684221A68604B40ECE2C8B535D4224064B3E78C65604B40234E6A7CE0D3224052C7FB4566604B407A22847891D32240E48FCD1567604B4043AABC4C16D322405BC376D068604B40B5A2B46FA3D222401FDCA64D6A604B40E8C97A2711D22240744C05336C604B408C24287CA1D1224006D5678D6D604B406A496DD2A0D12240424F4A8F6D604B409A9C8F7602D12240BF0053516F604B402D33486802D1224036BF7A516F604B400CEF37B5FFD02240ADA427596F604B40BB8E13E8F2D022404B7C93516F604B40FD6A30A4F2D02240DD226A516F604B40EF993A00F2D02240462995516F604B407C4AEE99CDCF22405824939B6F604B400B24F4F61ECF22407C975F3C6E604B4091FE37C31ECF2240ECD6F63B6E604B4065F1B9871ECF2240454AD33B6E604B406EB7DF0D1ECF22408CDF8A3B6E604B40C12C861AE8CE224072467E1B6E604B40B1CC88B0D4CE2240133C8BC26D604B401E69891FCFCE2240FF0E0BA96D604B40E20128B5C7CE2240773A3F086E604B40C259CD7AC7CE2240B272E3076E604B40BCDE014BB5CE2240310EBD576D604B40C04BFD77B1CE22405880B3326D604B40DDB99D5544CE22407D3553B46C604B40464F65EB3ECE224074FF6FAF6C604B40E4328ED27BCD22404C7B46FF6B604B40E7251D679ACC224065828D4D6A604B409054871D9ACC2240A5C5FE4C6A604B402672BA8B56CC2240F211F3CA69604B409378B40750CC22400D5D86DD69604B40448E00FF4FCC2240D75A9FDD69604B40F751ABE8EECA2240CB5A79A76B604B40CA99755A8BCA2240DD22BBEE6B604B40CCF8D685F8C92240D1663BAD6C604B401433E21A74C92240DABB3B5D6D604B40366A026942C92240450569596D604B40A63E9BAD1FC9224092AC8C546D604B4025E9245DFAC82240190138506D604B4038845C7DC6C822400C992F486D604B40D6EA6553A6C82240C8DD87436D604B403CEED39967C822402DBD753B6D604B406BAD6E4658C822404511F0376D604B4081A4FA3258C8224007D6C3376D604B40679D980658C8224086105D376D604B40566E3F8A57C8224023D73C376D604B4074851D6D4BC822405C6389346D604B40BEBCE8B92CC82240EA4B4D2D6D604B403E8EA39924C82240C6F9CB2B6D604B4028B4618824C82240CFBEC92B6D604B40B7CB17411FC822407C81D32A6D604B409ADED52F1FC822406158CF2A6D604B400DBB75251FC8224000B2CB2A6D604B40D8C7F6181DC822403585802A6D604B40D626B5071DC822403D14842A6D604B403AFA7D0816C822403B92732D6D604B404B7F3CF715C8224038FD7A2D6D604B40DBECBB9D11C822403EB61D2F6D604B40DED7109C11C822404C0E1E2F6D604B40E25E7A8C11C822401E33232F6D604B40ACE4EC5CFEC72240089ACC136D604B40A0975A4BFEC72240ACC8C0136D604B4009554C36FDC72240193738126D604B404E3EEE55F8C7224049AEAF0E6D604B406B123EF7E8C72240C55D8D036D604B409D88497EA5C722400A00AFD26C604B40135FDF587DC72240C4E697B56C604B40D69E961749C72240DDA36F9B6C604B40CB0C8C168FC622409DF53D3E6C604B40F66A978E65C622407CC377336C604B408E13A11B24C62240CFDF01226C604B4051AD20E714C62240ED78282E6C604B405018111B0EC622401F9911346C604B4028DC4740FCC52240D791DD246C604B4088C881FDF9C5224090AE10236C604B406B694AE4B4C52240B75FDBE86B604B40DA50D387A9C522404406DDDF6B604B40BC746D5BA5C5224037B330DC6B604B40153C3DA2A0C522405E0AE0D76B604B40A5E8B18A9CC522405B6E2FD46B604B40CDB8736E97C522401BE6F2CF6B604B40F80C143E80C522409CB48BBC6B604B4061FBFA815EC52240758054A56B604B4089E448E45BC52240C48C6BF06B604B402C06952446C52240019711646E604B407C961147FDC42240935548226E604B402DEA9DF9FCC42240F85708496F604B40DEE7848C9BC42240D08BE4CF6E604B40DF816ABD49C42240C51A2C6A6E604B408273E6A72AC42240BD5DEB686E604B4051CCF42021C42240C6FF077E6E604B403D6FBB5FF7C322402CC78FDA6E604B4020EBD960F3C32240F238DD3B6F604B40D8BA8CA7F0C32240CDB9F9E86F604B40FA2E169CF0C32240E4D73B1170604B403C106075F0C32240B582589970604B4006D3B7A8F9C3224026AC394873604B40794CD0FEF3C322407877FE3274604B40BF0F0BA8EDC3224087642E7D72604B400FBF97B0DBC32240003D49A46D604B40F6B495C0D9C322402742731E6D604B406FF29FAFD9C32240714BE1196D604B406463DE25CEC3224058ECF7FC69604B4003600A1ECDC322401380590E6A604B400EA9AFCAAEC322403A4334536A604B40511EEEF995C32240417FAA3E6A604B40C481545375C322401116A5236A604B40916A7F0436C32240044E3BEF69604B4070C5DD0337C32240B24EA9DA69604B40BC65F7342CC322402424D36969604B404E408D4521C3224002144AD369604B40505A027514C3224047D273396A604B40E72B787B14C322407F3AC7336A604B40A6C07BF2FCC222405F7A62206A604B408B647E83A1C222401C0E95D469604B407369E1087BC2224072D72BB569604B401D696F2A45C22240C42D018969604B400DF92DB723C222406E67056D69604B40A52012CD17C2224079B9E6256E604B40495090DAF7C12240F94E1ECD7A604B4017FCCB1DEAC12240E295A53C80604B40A091E710E8C1224008826C0980604B401BCA6033DCC122408E1207E17E604B4099A48299DBC1224075EFB6237F604B400A807D37A4C122405A0DDA2397604B40E1DCE334E7C0224093B56EB8DE604B401D384E25C0C02240727A7EC0E3604B40945B4E31DEBF22403298F7D800614B401E509EE0CBBF2240826E713403614B40618749F5B3BF2240764B8C0707614B40AC172089B9BF224023F9122D08614B408C3D129BBABF22405351636508614B40406AADB29ABF22408D63476811614B4035D9A24684BF22401D8B92BB17614B4020754FDB76BF2240F6BAEB691B614B4017FC9ACF71BF22409A4DF00F1C614B401835DBCD61BF22402BBAE21E1E614B40A45BEFED54BF224016CF702D1F614B40417FEC944EBF2240BDA4D4B21F614B40C084690E41BF2240C216832A21614B400EEE845E36BF22409D1A64E222614B408E08ECA731BF2240C2540E4424614B40DC83D58830BF22402A74DFDB24614B4050D002D52EBF22404B785DC225614B4097A40D102DBF22401DAEECB126614B40EB5DD7AE2CBF2240D8ED6EE426614B404872D36A2DBF2240BA616F6E28614B407FE6E2A62DBF2240D94143EC28614B40451C42B22DBF224001B6E20529614B40739AF3CF2DBF2240C25D704329614B40342F14942EBF224062BA64DA2A614B4018EECA0B2EBF22407D1EA0542B614B40FA695E0D15BF22407ACED1512E614B4049E363BC13BF2240E9E81D7A2E614B40328FED10F2BE2240C2740C8032614B40210390BDC9BE22408468135237614B409380D8B3BBBE2240BDB31A1339614B403F4C51FBA2BE224019CDD1293C614B4056FE586C86BE224070585BC83F614B4024FD75F666BE2240A99AC5B243614B4012B6580FC9BD22403292007A56614B407D0B0B8CA7BD2240D2FDEE7F5A614B40F182D604A1BD22409ADEE8485B614B405B214E9BA1BD2240E3DB1F5F5B614B408035B89781BD22407D581A0F5F614B40BCB20032B2BD22400F2FDA3E66614B405D03938CC1BD224082D0DF8368614B40489AEAD70ABE2240AB67CC5973614B405197C0AF26BE2240B4E8E87777614B406C92D4F80EBE2240411115DC7D614B40BA256591BDBD2240F17650E993614B40D6B62891A4BD224007091CD39B614B40C1EBAA3F8DBD2240389A8934A3614B405E5337398CBD224037599C87A3614B40363CC40D57BD2240AA9C685CB4614B40C91CFB4A32BD224020382EF5BF614B40C1E475421EBD22407FF93F47C6614B40E102D59006BD2240410FD2DECD614B40C6C09134E0BC22403D4F765BDA614B40F5CE6409BCBC22405A44E912E6614B40E3C6CF42A0BC22405AD2431DEF614B4026B330D34BBC224074BB1F810A624B40BE6F99F63ABC2240B009EA1F10624B406387796625BC2240D73A7BEF1A624B40567EFF851ABC22407C5FDC7E20624B40755856D818BC2240A35DE75821624B400E408AC718BC2240857C6D6121624B40F13D73D313BC2240D474FEE423624B40B1F2D68910BC22408E4DFF8F25624B4024F08D7C0DBC2240EA9A641C27624B40FDB60521FDBB2240DC5F236B2F624B40A4E9085FDFBB22400E9260823E624B405458FC3DC2BB22405A997C7B4D624B400EB75E17BCBB2240973FF97C52624B404BF5FE34C4BB2240D54BCE7C52624B40B70DC1D3C4BB2240B999CA7C52624B40566F2B5472BB224094D264CC74624B40CC54AFD471BB2240BD74670175624B4010DAA0593EBB2240C57A416A8A624B4009B6F40134BB2240AA7E49B78E624B404D1456572ABB22404C1656BC92624B40D26C712724BB22403C64004F95624B4005910CD016BB22405E7B22DB9A624B4051170F1B11BB22408573C83A9D624B40138EF790D2BA2240793DBC3BB7624B40FDD71211CABA224085C305E8B9624B407B942581B0BA2240219CFDF1C1624B406245CB4DACBA224078912B44C3624B40D771F2A38FBA22405B302B05CB624B408FA4D43089BA224084C7DAC3CC624B40F4F1081E7EBA22409411D2C2CF624B4042A302BC3DBA22404E62E12DE1624B404F087D8FFEB92240DF575544F2624B4068BF1ED2FAB92240D11A3E47F3624B40784D76C6CFB9224033AF48EBFE624B40557DBD1BCEB92240725EAE5EFF624B40D286862D65B9224038CF1CC01B634B4013CCCD9359B9224035624EE31E634B400EDF79BF4DB92240077C311622634B401F0D489345B92240B2DFBC4B24634B4031EA5BCF37B922402D0A7D0428634B40B2C4D49617B922403B1336BB30634B4044C1C6D414B92240AD28287A31634B40132AAF4112B92240811C652C32634B407E75762011B9224083F99C7A32634B403D314BF42BB922400BBB891F34634B405F7A269830B9224005EB576834634B40E5E387F143B92240328AED9735634B406C0DC78B88B922409800650F3A634B4059C25930A5B92240E911E8EC3B634B4080B18C2DCAB92240BABB8E553E634B40F78D4212DCB92240665861913F634B40C43C399723BA22407757AE7F44634B40C475FE0C81BA2240C75DECC64A634B4014284F32D0BA224046B3992150634B40EBAA9E4A05BB2240C39546CE53634B405BF9333810BB22409FBAE18F54634B40FACA1E0654BB2240D1943A3959634B407022B466A8BB22400D4C53CF5E634B409B594745ABBB2240FBE5F5FF5E634B4092704E6AAEBB22409192BC355F634B408F85E1E5D1BB2240D9CC839461634B407B23BC39F0BB22402BC0C09063634B40C5B680E8F2BB224048F4B4BD63634B40C624E80DFBBB22401F19394664634B40BD199035FBBB2240C6DC114564634B40AF1F86B4FCBB22404448F63964634B407441EDCA09BC22406CCC07C963634B40ED4D77910DBC22402EA274A863634B40482C79430FBC2240F384D39963634B4047B1625E10BC2240F869499063634B40A66258E123BC2240234619D062634B403B2B8DF12DBC22408C8F7B6062634B40CB5F813837BC2240842395F961634B40E449D2D537BC22404619FEF161634B409D772D5F4ABC2240FE08F20C61634B406DEA91505DBC224016DF680A60634B407E7D3D2267BC2240ABF06D775F634B4045952D3C6ABC224098F1FF485F634B4035650C0870BC2240102D3CF25E634B402C2BC12D7DBC2240DE2CB82D5E634B40097E61BE80BC22406947CFFC5D634B400152B3529ABC2240F6E1147A5C634B40BFFC6D03D0BC224074DE875759634B4041C3CFC7DABC22407F9D96B658634B40565F2EC9EDBC2240140AF1ED57634B40132E0159F0BC2240E442E4D257634B4068BC9F1B06BD22401A2CE50957634B40D5406B091CBD22402E97D05B56634B40C7767BEC28BD2240633C020656634B402FFE3D1C32BD22405205D6C855634B406218CA4D48BD22400E12235155634B40DDF6980852BD22408838DA2855634B401E92CE975EBD22408BD4D7F454634B400B2AE2F374BD22403CA20EB454634B40AD09DD287BBD2240CF11BFA954634B40A670DA537CBD2240269DCEA754634B40D055C35B8BBD22401923D88E54634B40	Flensburg 11	\N	fl11
13	organization	102	0103000020E6100000010000008E040000D3232B0093FB22402D81276958694B40FF62DAC7B0FB22407E2D6E4352694B40CCDE2B1AEFFB2240A8A502DB4C694B40F58386AE02FC2240936411284B694B405800A78825FC2240C39355343E694B40888B47BC32FC224053248A4D39694B4012E31B6043FC22409473191B33694B40A52A3F2F44FC2240D5D7BA8B32694B4006C919B351FC224096DF39E029694B40B4462C2C4DFC2240F976A4B329694B4006EFFB5827FC2240AD50414B29694B400B5018681EFC2240E36DED2129694B40C7FFA2DA16FC224072D0F2FE28694B400BFBFDEA15FC2240A95215FE28694B40CFABB44B01FC224072C2FCEA28694B4087A9ADAAFCFB2240938EE65429694B40844AE983F7FB22407D32707D29694B409532C9C0BFFB224060CA876227694B404E74C386B6FB2240FD755B0927694B40B71FD0FEB7FB22402E49A88126694B406A874809B8FB2240488DE27D26694B40805E4454B8FB2240FF12D26226694B406BDCD388BAFB2240D3EE149725694B409B4ABFBAC1FB22406A38C9FE22694B4050B05EE3CEFB22401C38EA191E694B40A29AF6EAD2FB22406CD3F1441C694B40CDF05B64D5FB224028BB62211B694B40E53CFAF9D5FB22409AD185BE1A694B400CA514C5D8FB2240EBEF0EE618694B40FBB52D72DCFB2240449331E316694B40679737B8DEFB224086A3B2E713694B40BBD86C03DFFB22405609048513694B4038EC097DE1FB2240C15A2D9D0E694B40552AB49AE2FB224087F904640C694B405FB2079EE5FB2240B89AC0900A694B40F8B719B9E6FB224051E165E509694B40C36A55BFE6FB22402E937CE109694B4020B3062EE7FB22404DB77F9E09694B401D828E9DECFB22401E58840906694B405AA9AEEAEFFB2240AEBE0CC004694B406688A49EF4FB2240117569EC02694B401F18FFF1F9FB2240D49ACBDA00694B4008B3478CFEFB224005CF3A10FF684B40B58E540701FC22403890E619FE684B403AA16CCB08FC2240EF01FB14FB684B4018DEBE8E0DFC2240DC598AA3F9684B40AB62848F0DFC2240DC644CA3F9684B4084A6499E0DFC224046EBD59EF9684B401B9E03140FFC2240FD4E9A2DF9684B40052ED59C10FC2240BB6F93B6F8684B40FEDC86B213FC22406C9333C8F7684B407D4759EC16FC22400E69EBCEF6684B40EF78C2201CFC2240A86CE83BF5684B401E35D20223FC22406F229BBAF3684B4034036D1223FC2240AAB230B7F3684B4041682F132FFC22406BC84517F1684B402714B83541FC2240E7C6ED72ED684B40A75279104BFC224028396F98EA684B409F66DFE952FC224090248E10E9684B401B876D7653FC22407B02BEEDE8684B40194E5A0656FC22401FD74D4BE8684B40677F029661FC2240212A8C13E6684B408D75240469FC2240E2CDA8A6E4684B403D5602E86DFC2240237A4C52E3684B40E3387FA950FC224027ABD76EE2684B406D0DF67938FC224087B79ED5E2684B40E8CAE86A25FC224068C0401EE2684B40C7742E201BFC2240CCFE22DAE1684B40C45DC4C114FC22407DAF5BB8E1684B40EFFBB8AFFBFB2240FC70A699E3684B4043E92E9DF1FB2240195519C0E5684B4017D96C12EAFB2240A8D96AA9E6684B40A274D37EE3FB2240650096D4E6684B406E861E5CDDFB2240193A7CE1E6684B40F7C5D143D7FB224087B99EEDE6684B40936D0703D4FB22405251FCE9E6684B40D1128A93CCFB2240436315E5E6684B40D546C0EDC3FB224074D791D7E6684B40AA35C088A5FB22404B5F3935E6684B401C67313386FB2240EB31F380E5684B4036386C575FFB2240C8784081E3684B40D7190C435EFB224087EFBA71E3684B406F98D4105EFB22402CA4E86EE3684B40635BA5F956FB22409C26FF08E3684B404525A73754FB2240DC8BA8C2E2684B40F7FDEEFC4AFB2240313D3DD7E1684B407FC3885353FB22407E1FAABCDC684B40AE10C0B964FB2240BAD56516D2684B406B477D0665FB2240204DD6EAD1684B407BA4C81B65FB224099E0C2DED1684B406E0D43B565FB22404ECFA387D1684B4049BC6DFA65FB22408B596060D1684B405819219977FB22405C86F05FC7684B40FD455D1A78FB22407FEE9516C7684B40A36514C278FB224004C0E426BF684B4023AB783179FB2240E36414BABA684B4052950A3579FB2240A5F1E395BA684B406C86B5CC79FB2240331250E1B5684B40BBEF17277AFB2240D1348613B3684B40D84F0FFD7DFB2240A94937C2AC684B40CAC73E4581FB2240D74B655AA7684B407664C6D985FB2240C09119399F684B403C5AB95686FB224061624E5B9E684B4099FA0F8A8DFB2240946A6AE190684B403D75EC8F91FB2240EE9B187084684B407CEF389F91FB22400CB9C04084684B40C3DFB7A391FB2240FA89E03284684B40ACB1D2DE91FB2240FCB2BF0784684B40FBF2929B93FB2240984E49C382684B40EA19A9549BFB2240F256EA207D684B40D8A0778F9EFB2240B82BB7C57A684B406355022C9FFB224002DDA3537A684B40B48111BF9FFB2240371573E879684B40D736291CA7FB2240FF94858974684B401C548241A8FB22400C3A7BA573684B401F44130DAEFB22405D1A42706D684B40BCB319FEAEFB22405B8479566C684B401C6DC8C8AFFB2240485886696B684B40948AF7E3B0FB2240FECE94C86A684B40AF41C519B7FB2240D27E204167684B4032F70DF7BEFB2240ED9BD9B462684B40C9BAD4ECC2FB22407EE2326B60684B40A775CA5DC7FB22404148A0CC5E684B40777DFFABF9FB22403AF32D9B4B684B40A23304E3FAFB2240F1B583244B684B408BE0B9F9FAFB22405038D81B4B684B4062EF5113FBFB2240298D5B124B684B40F7B7C3FFFCFB22407993E95B4A684B40ED79DD1208FC2240D9B8A0044A684B401ABA092D08FC22404026D3034A684B40BAC9E8C909FC2240AB6325324A684B40FE54908C12FC2240E967C62D4B684B402AD0BBF224FC22406A8EF4024D684B40248C888D3AFC224014EFD2884E684B40578B8DB952FC2240B19FC0294F684B40A74504CD62FC22407D9EBF144F684B4037EAB6D769FC22403BA28B0B4F684B4075E66E1981FC2240A4A886784E684B408529E45996FC224096BBA25A4D684B40FEC8EECCACFC2240FE7AACA84B684B4045CC4C9F10FD22409E991A3B4D684B4036A6F64034FD2240A49E112E48684B40F688030459FD2240849FFEF742684B40A5DB6D3D92FD22404B9130F43A684B407EB4A12DA0FD22405DE76B0039684B40E184909EA1FD224020BCF0CC38684B409B1DBC9EA3FD2240C3A5788538684B40DACF8A91C4FD2240159B38E833684B405CE4E928D7FD22409D067A5431684B4053C5BF23DFFD22400DEB453930684B404633153CEFFD2240E7F43BA631684B404F5016FF79FE22404A577E8C42684B40B996B7C87DFE2240E7FC940243684B402CC335CC7EFE2240D99C302243684B407B42E83D82FE224060BC908D43684B403DBD7795AAFE2240EBC08C913B684B40EE79A05AB1FE2240F938873A3A684B4059809131BBFE22402F64830138684B4081DB5D5BC0FE22409B5CEED636684B40FB624B88C9FE22402B8551C434684B405B12FEC8D5FE2240DDECC2AA32684B40B1BD1F3EE6FE22400A6631A230684B407B83D97D05FF2240A446ECB32F684B404DBC3BF10FFF2240AF1A3B642F684B40FC596CF30FFF224000172B642F684B400FC79BFC2CFF22408404C4862E684B402A0ECB444CFF2240D1AF792D2C684B40BADAD63B61FF2240CB0224792B684B405702FD8484FF22402776ABA327684B40507587359BFF2240E2576FC323684B40A990CC9AA3FF224087E2485422684B40F98F9EAEABFF2240822B0DF320684B40241198CBCDFF2240C43930FD1E684B40755C8946FAFF224060FB49B71A684B4021FD154506002340D8DA6AB519684B40A227586C09002340CBAE9E7119684B40339FFCF60E00234049D47AFA18684B401A217000340023405544928F15684B40E0273AC55D002340EAD020BC11684B4051F2260A71002340AB02652810684B40AC137C137B00234033AA700A0F684B40A498A95C7E002340227231AD0E684B40AC24A467840023406B81B4010E684B406CEEE8A785002340EF2966C30D684B40DFFBE5428600234051223EA50D684B40C51E8135910023404E5B01880B684B40B5E8194A940023403F70B7EF0A684B403B1419B2A0002340B5DB5A8A08684B408789F813A9002340D282EEEB06684B407726844AB10023401EA80D0505684B40F49FC823C200234015263B1E01684B40066B7379CF002340A5EAB907FE674B40857083EFD60023407ECD772DFD674B4005198212F60023400B7CE22BF9674B40F3DCCF5017012340102194DBF4674B40E1B9F3361C01234080ACC938F4674B4098CD7A551E012340F3A46FBAF3674B40A690CD3C2C012340BEC5767DF0674B40AE543B5638012340D887CE3FEE674B408D73AF6F4A01234094CA1CB8EB674B40F247D68054012340E3B46095E9674B40338A43F360012340C5C28FE9E6674B40703A9F4B92012340D92678FEE0674B404EB3774AA60123401B730996DB674B40078F0BE6D401234026BF7831D4674B4004D0E8E5DA0123403C45DB3DD3674B4021CF9551DE012340150CA00CD3674B40609F4FEBEF0123409A1C530FD2674B404151497FF9012340FEE4332CD1674B408D3822F6FC012340DCB2FA90D1674B4009C5D4B505022340F7410200D0674B40B6D0AD8010022340DACE11EDCE674B40C22F0387180223407C1F8527CD674B40801ABAE21C02234004FA358FCC674B4023EF21D42002234027306905CC674B401AA692EC230223406EA4D536CB674B40A8FBF925340223402D4922FCC6674B40F878878C3702234032F1E519C6674B40B29156D14C022340E361EE91C2674B406E144256780223402C01022ABD674B40F4675B5587022340DCC630C2BA674B40987E4AB4BF0223406C92F4B6B1674B4019E76E57C0022340B01AD4B8B1674B40E46AF98EC5022340BFAB2AC8B1674B405D0846B3C5022340575F2CC2B1674B401F3413C7C60223404A054CE8B0674B40B1F81FDDC602234063ECDFD6B0674B403D1BAC5EC80223405FA445A6AF674B408A2E6C30C9022340D3888E00AF674B400536F64EC9022340474772E8AE674B409DAC5FE1C8022340B2D797D5AE674B40340D57F8C402234087F87029AE674B40CE9768CFC5022340A832B22AAD674B40407AA3B3C602234082A95E1CAC674B4005F1B1BDC602234087857810AC674B40BAAA6EFDC60223409DC3FCC4AB674B40434676BDC5022340B9F2E448AB674B408CDE6F96C5022340CE84C039AB674B40C1A537A7BC0223405891BDC2A7674B40ED19350EBC02234073986587A7674B401AA516DFB9022340752C8EAEA6674B403D96AB32A00223407CE3796AA5674B407CB5704F9E02234033C9A652A5674B40B69BBD718C02234018EE1F71A4674B401F0793566A0223403094B697A1674B40AD83A6B1680223401021935AA1674B40FD56F89964022340E6CF6AC2A0674B4048B2C6665D022340FB20B8B69F674B402C08F70A4E022340D3ADAD7B9D674B4095690E2843022340FD7D176F9B674B406A07CE2D450223403027334598674B40D71911584C0223402C9AC31F91674B40546C7BE85A02234045BDDC8889674B4095D50E6D5C022340DBD9A0EA88674B404D1725FB5F0223402BB6077887674B40A79FE8855C0223404D2F436E85674B407B5AA8CD520223402956B1B37F674B40035BEBE3470223409323064579674B40258F8EC23502234041792A716C674B406D396C23260223401602079960674B40843B9092250223409B1F322B60674B40612555FB28022340074D69B05F674B40972FA7622A022340A250DC7D5F674B405338DC272C02234017421A3E5F674B40959DC1462D0223402487BC155F674B4000ADC4802D0223406E62940D5F674B40837CD7822D0223401F91480D5F674B40E17721FE41022340FC5AB92B5C674B40C239FB9B4D0223408A9854EB5A674B40AB60C6A84F0223401D8920C75A674B40FD5EA81956022340787863555A674B40D4C500B36D022340D46334FE58674B40EA2328B476022340DDBDB97B58674B409A37C2E88F02234076A37E0D57674B40FB2DF2F4920223406377F1DD56674B405D86973E9702234099FC759A56674B406D90E06AA50223408CCA675156674B403799251CAD02234038DA0D4355674B4097131E29B00223405450C71855674B40C63553DEBA022340CBBB1BD854674B40B11CAC36C402234037E9569F54674B403EE63CA4D1022340A71DDA7C54674B40D61AED53DD0223400A63516C54674B40EFF6BE75DD022340C8C5216C54674B405022BAAEEE0223400C86FFFD53674B40795816D4F40223405A9A96C753674B4072A4D3CB67032340F23A5BC84F674B401515C1857F0323408CD4F6F44E674B40A083453E9903234041457B104E674B4099A27936A30323408888EBB74D674B40AD978E66B00323405065E5444D674B40C92794839B032340F48E14EE43674B40253501B6980323409EA7C5B042674B40F524490D7E032340A9703EF536674B40BBFAE4DE6203234063C02E9A2A674B40A629A3725B0323409E11107126674B40FD50222153032340B6A014F223674B409CD41C5E5103234043D0BD6A23674B4011CA829345032340A01E7C581E674B40EC2A4B2D42032340ED75D3C61C674B40C456201E3F032340E42D575D1B674B400D9DF6D53B032340A275A0EA19674B40A68FC6463203234093C7FA6F15674B40EAB2CAAE2D0323406E1C864913674B4094D9B99429032340A03305F611674B402346BD5A2503234073F17C9610674B4078972547FD02234013DD7E4E11674B406512356AEC0223408C441E9C11674B404907D381DD022340DCF5D50812674B40921E5229D1022340E6FBDD6212674B40314684EEBC022340F1CB776213674B40244FC4379002234075EA334E14674B40909CA0046802234017425D3414674B40683EF8D566022340A3D3993314674B40947B63EF27022340BC939D0D15674B4029287A61F7012340F334A56315674B4094AAD2E4F4012340DF4C136815674B40D6223C17EC01234007D1F3A114674B40A4B6ADBAEA012340F359265014674B40465DB373E90123403F77EA0214674B40FF9D05F7E5012340177DD53013674B4019C75698E2012340DB0BA86512674B40087999F6DD012340CC225F4E11674B403F1EC603DA01234080254E9810674B404981B282D5012340CD3D00C80F674B404AF69ACFD4012340F432C5A70F674B4092FE5640D10123403C83B1030F674B40BD8D56B7CF012340EB5D64DB0E674B40C34562C8AD012340AA22F8F10E674B4009AB6B18A9012340D58A79F50E674B409B284AA3A2012340A90E7F020F674B407FB718C78B012340F45F58310F674B40EA4282B582012340DCEB94430F674B4008867A607C012340E5F289500F674B40A235835C7C0123404DCA90500F674B40A7BB16DA76012340E475D95B0F674B40784536666C012340E1D773710F674B4091DE25211F012340D5E79C090F674B4063231824EA002340D57CD45C0E674B40A1C5E0D5CB002340770795000E674B407D5F5C17B5002340A2DA43860D674B4069AF55A8AF0023402CAB0A690D674B40C852E1CDA2002340F09928270D674B404FA1FE0B7B002340D9DC28200C674B40DCCAD72158002340C07B582A0B674B40B7115E54500023409EB469F30A674B40386D1B3D480023401DE938AD0A674B400E638D233C002340520B42440A674B403FFE13E33A0023400CCAAC980A674B4063EFB23B38002340D8B460A00B674B409A2D63B0350023400037309D0C674B40C0D3158233002340AD003F8A0C674B40A1C2A3A21800234011C0DBA00B674B4028E49C9E18002340D936B6A00B674B40E098189D18002340CF2CA7A00B674B405BAAA4B0FBFF2240A32F08940A674B4064AF2375EFFF224098E17E160A674B40D807C9B2E6FF2240833599BC09674B4036358C2DE0FF22405851AD7909674B40F4B899CCD4FF2240A6E1CBFC08674B406F71A014CAFF2240A2C12A8708674B4041A145CEC4FF22409C9E474D08674B4045681E95A9FF2240F995EF0E07674B400B7949848EFF22405899C1BE05674B40327F1E3C71FF2240C9E0554C04674B40732FA5A55CFF2240B40FE64703674B40B2A96CD948FF2240AA4FDE4502674B40F3CC462C2CFF22407B1F1FD000674B403792EB25EFFE22403D08C1B4FD664B40FBB9528CEEFE2240D984EFACFD664B401017BDBBE6FE22400E450947FD664B4046ECD2C6ABFD2240490B2D3CED664B401CA27ED312FD22407EF29A71E5664B40D43A67330FFD2240DA466543E5664B40FAC6D21308FD2240E57C6DE5E4664B40AF597CD925FA22400C62C748BF664B40021D5AD525FA22401C699248BF664B4006099FA70CFA2240C3DC4106BE664B408D9948A3C9F9224020EDB19EBA664B40530D87A28AF922405759506BB7664B405647FDDE29F9224024EB736FB2664B40A98B4E5F1EF922407065D6D7B1664B40511DE7D0B9F8224008ABF9AFAC664B4081B42E8668F822405B5BEE65A8664B40F0D863A166F8224075B35A4CA8664B404AB9A3B751F82240CE7CDC31A7664B4080B6EAD409F822400CB6D566A3664B40B0FC2CE7E8F72240DBAF6997A1664B401035DA3BE5F72240946CC463A1664B40896D338AC4F722405687C3619F664B4085F76732C1F722406D86342D9F664B40704031C69DF72240F7D2F8C39C664B40951484047BF722400A72F9289A664B404CD9232658F722402FE96C6A97664B40D235D08835F722402FB7E79A94664B407AD21B2E13F72240754B8ABA91664B40215E14E80BF72240EC66D91991664B40D6F78B17F1F62240031975C98E664B40609856A5AAF622401CB73FA787664B403CB5F355A3F622406055E8DA86664B40A436BAF179F6224087E6DE5582664B40621EFA1377F6224020330F0282664B40282692D274F622409E471CC081664B40B440482E71F62240859F9F5581664B4093F0DF8E6DF62240ED86B0EB80664B40ED37A7A06BF6224019623DB380664B40312ED7E36AF6224050D539A080664B40736901A650F622402DB3569E7D664B408239D3E127F622408737686578664B40C18836791BF622409E9A17C576664B4078D41687FFF52240C61B801B73664B40081E0120D6F522407081D7226D664B400FDA2CFABCF522404F05BD4569664B4034B75319B0F52240E443374B67664B408CDCF8F08EF5224056F316C261664B402EBF62806DF52240219F3EF35B664B4002ACD2C52BF5224095A0032F50664B40B6C4461424F5224094516DCE4E664B4042C420C579F42240999E2A6331664B40C4510FBA5FF42240902006822D664B40B994FC4C58F42240886F30682C664B405D162E5158F42240FC1B76672C664B40E9679789AEF32240E0E3CE1C13664B40F2AFD59CADF32240C0C624FA12664B401B0C8CDA69F322407C37300E09664B406A49448C2FF3224052D4340901664B40D4AA835821F3224082132215FF654B40815946D513F32240E89B5539FD654B40FA6EE2999CF222407B480066ED654B40CB0AA26640F2224024EE59ECE1654B408117EA6DE0F1224089C89579D6654B40B2CB2A6687F1224022F2FE96CC654B401D7E080B1DF12240B923D7C7C0654B40749203AD12F12240AD27D1B1BF654B4026A2B352A2F022409890C2ECB3654B40628A11DF42F0224060521413AA654B4004B16DA91DF022404B2DCB1CA6654B40D44EC3470DF022402EF8765AA4654B4027C04809D6EF2240BD7CCB6B9E654B40781557F7ADEF22403ED13C1E9A654B40697E99D032EF2240BD8362698F654B40C07E5D880DEF2240E1CF4E8F8C654B40E75FD968FAEE2240AFADD3188B654B401E09D835DCEE2240CEAA7CEA88654B400D8A9F7ABDEE22403BFF61E586654B406FC8B4419EEE22406183340A85654B403227C4957EEE2240C772995983654B40FE69FB2E51EE22408476BEEA80654B40B3A5B990F3ED22401DB1D2897C654B40F8405CD9D8ED2240E61C9C237B654B409898658DC7ED22409479242E7A654B40E273F5ACC7ED2240B443BE557A654B40427BB9D0C7ED2240DECC86827A654B40605087EAC7ED22404A14EBA27A654B4063E95BEBC7ED2240F833F5A37A654B40ED72583BC7ED2240F7891D927B654B40D4D6D732C0ED22407BB70B1685654B401545F271D0ED2240AB06AD5385654B406E9A4CE2FEED2240970FD60386654B403AB40473F4ED2240A2F711D396654B4000A114E2F1ED22403F27388B99654B40FC4C9C58EDED2240DF6CE089A6654B40B6F83D0AECED2240D7D809A4A7654B406D0FEEE8EBED2240431F21C0A7654B408E69E596E4ED2240CD1BA3EEAD654B40DFC7A275E4ED2240A55EBA0AAE654B40C1C42F23E3ED224092F00627AF654B402FF4C401E3ED2240224F1C43AF654B40C2D78E2DE3ED2240E04F4EE1AF654B40E6CE9014EDED2240E3731D4CB0654B402714707EEFED2240629CD2F5B0654B40D82CB59BF3ED224061B75C66B1654B40A719262512EE2240BD949CA9B4654B405B531C2845EE22404C2476DFBB654B408CDCD99F49EE2240645829E7C4654B4060C4496997EE224014F05D5EC8654B40D42D046A0AEF2240A09BFF7DCD654B40851FA0D22EEF22406BD5C61DCF654B40B02BAAC32FEF2240ED528728CF654B400BF7E14948EF2240C5279640D0654B4058445C6747EF22406927024AD1654B40F00AC1102EEF2240E5435DFAEE654B40FB2E138B15EF224067ADA6B50B664B4042C7363C18EF2240A0B7A9BF0B664B40982BD65E5CEF2240E15F17BD0C664B405C7A31BE66EF22401BFA072A0D664B40C8B0F0B27AEF2240AFD31B970E664B40CBC159B77DEF2240C84996BF0D664B4097EBEA8A84EF2240988CE0280E664B40A8710AD08DEF22400E0F1FFE0E664B40080B99C2AFEF2240F11C8BF211664B4021D619DBB9EF2240ECB90A8F12664B406631424BBDEF22402D5DEFDF12664B40AA6AB07FDAEF2240869B168F15664B40D35260860AF022408175C5AC16664B4040423E7030F02240E75CE32218664B4045AF81BB38F02240114DDB9418664B406AAF2F4241F022401EE8C06D19664B40F4D0F9783FF0224007908CA119664B40C52EDD7A3DF02240584FD3D519664B40B44EBE533CF022401AD2C6FC19664B40B2C9791C39F02240CAC06B691A664B400CE7334435F02240749EBF0F1B664B405A5E2EAE33F0224095B47A681B664B40718FE87C20F02240C84D746D21664B402FB78C8818F02240222E190A24664B40EEABF30E0FF0224007F34C1127664B40BE054F2F0EF02240B4E4766127664B40832523710DF02240EC7114AA27664B40B3A82D3F02F02240DE0796F02B664B408F7C1678FAEF224093CD35472F664B40CE3F6A23F9EF22401B6D21E62F664B40A5F83FF2F7EF224021FD7B7430664B408166A235EDEF2240775C380435664B40EC6F4116E4EF2240173C17C439664B400F2A266ED1EF2240181CA27A43664B40F9BDABB3CBEF224019FBAE2947664B403D39DD31CBEF22400CE3733748664B40C5EAF667CBEF22406CA4C44549664B407E7CAAE8CBEF2240142A20D749664B40AC703317CCEF2240769EAD0B4A664B401D427C55CCEF224070D4FF514A664B40AC0603F8CDEF22404BF293594B664B4079AB4047CFEF2240C54DE4E94B664B40C354904BD0EF2240D8BBF3594C664B40CF3D714AD3EF2240EAA7A5504D664B405190CBC9D6EF224010B75D324E664B40E96958E0D6EF224030150D384E664B40B8BD0A01D7EF22405E394F3F4E664B40F66DD82ADBEF2240CB7295174F664B408C154184DFEF22407BE8E71B50664B407A2DC719E2EF2240658390B650664B40FAE7A7B8E2EF2240EA6DB6DB50664B402E6569E9E2EF2240B0E81DE750664B40AF6C8848E9EF2240D14866D252664B405D062FF8EDEF22409E15C8BA54664B402A62E435EEEF2240C1C9E4D354664B40BBA648A3F1EF2240E0ECCEE556664B407556944404F022402B30881B63664B4023AA852706F022402580DB0865664B405DDBDBE306F02240DA1E65FA66664B405FAD447806F022402ADD6FEC68664B4082FC76E504F02240140A46DB6A664B409C7A7A1B02F022403E45F8AC6E664B40BDE64A54FDEF22406E9D4F1E76664B40A0677DC4FDEF22407AD5AF7578664B402AADD36EFFEF224033131BCA7A664B4052D3528803F02240FFDF2C397D664B40A6098E3206F022405B5B317D7E664B4020A4189408F02240FD9BAB9E7F664B407D9C168E0EF02240B78FA0F881664B405E4AF53D10F022400EC6C18882664B400581D48114F02240DC6E31F583664B4027214E7115F02240C8E41E4584664B4099DEF3E01AF0224010FD124C86664B40D0EC1CB120F02240BCC6017788664B407AF88E5723F02240D26CFDA689664B401312002425F02240CCEE5CDF8A664B40B7F58B4225F02240A4AB2B088B664B403F5EF97F25F022408AC93E5A8B664B40C66EA41126F02240A2A1E31C8C664B405D48FB1D26F02240FDFB405C8D664B4025947BD925F02240EE3376C28D664B409366EA4825F02240DFED219A8E664B40E2A20ED824F02240A7ED1BEB8E664B40AC94969423F02240B57E3CD38F664B401345A60521F02240DBE04B0491664B40D192D7A21DF0224063D8232A92664B409A58CD0317F022408DE0D53F94664B405E9261D40FF022400A8A744B96664B40D7BF4E1708F022400CA5304C98664B40E0D4C7CFFFEF2240F0BF3E419A664B40714905AFF4EF224063CE58669C664B40B3C689D6E8EF22409F4188769E664B4013EBBC4DDCEF224048178570A0664B406C9F641CCFEF22402BA61653A2664B4083649AA9C3EF2240968AA422A4664B408131A643C1EF2240F09B5091A4664B40E522000CB9EF2240B9DA880CA6664B404D547AF5B5EF2240EF2493AFA6664B4077DB7048B2EF2240601EAD71A7664B405B89DCCAAFEF2240A7822DF5A7664B40A76EEC4EAFEF22402F88BD0EA8664B401F27D17CA6EF2240F1FF1927AA664B40C05C2744A6EF2240C1174F36AA664B406712271299EF224006C9C0C0AD664B402C0B8A1796EF2240C0F1668DAE664B40C18A08D893EF22401239D427AF664B404972912D8EEF2240BF71E2C4B0664B40AB3AF01A8EEF2240592484C9B0664B40ED73CCE087EF2240159B3255B2664B4098B924F780EF2240F0C36DD7B3664B4012C5BBF97FEF2240F4975B08B4664B400E2B2F727EEF22409EC1F453B4664B40442CB4147BEF22400E374EFAB4664B4006B3637679EF22403D544C4AB5664B40E1E5F36471EF224082FC95ACB6664B40921FABC968EF2240040B1AFDB7664B4011C3822467EF224076BB6A36B8664B40E93A4D9165EF22408C6C4D6DB8664B40F971D8AB5FEF2240BDEABC3AB9664B40203A69155BEF2240C09D0FC9B9664B4046D8431356EF22404D6B7064BA664B40774588C14AEF224031D89E04BC664B40A05CDF4D40EF2240FA19BCC2BD664B40A39B0CC736EF2240B74A539CBF664B40D975833A2EEF2240DC73C38EC1664B40585CE74223EF22401F359E02C4664B4054F28BEF1AEF2240AB18F0F6C5664B408D541BAB18EF2240964C317FC6664B406B985C740EEF22400D3D2F04C9664B406F93F59F04EF2240EEA94691CB664B40E6FB2C48F2EE2240B32A5E45D1664B401B354614F1EE224030A159A7D1664B400E906C89E8EE2240B9494A5FD4664B406215B958E5EE22408FCF3363D5664B401F1A42F7D7EE22401E3D6979D9664B402EFA7AE1D3EE22409AF671EFDA664B40C35A503DD0EE224060EAB16BDC664B408408FD93CDEE2240D1EF6FADDD664B40CF0F6056CDEE22401D028BCADD664B40661E800CCDEE2240C3666FEDDD664B40CFB59250CAEE224013C7F073DF664B40174FE80AC8EE22404A9478FEE0664B40A0196953C6EE22408EAE9878E2664B409271584AC6EE224091B1A67EE2664B40138DDA86BEEE2240C3745E6BE2664B404F4D0631BBEE224009D5A26AE2664B406A5642225BED224075322D1DE2664B404F5863B8C9EC2240DE19DCCDE6664B40FFC7DFEEC2EC22401B5EA427DC664B4074DDA025C0EC22405B61DCAED9664B405CC7DD68C1EC2240DB0D01A6D9664B40EF0ECC09C9EC224071FE8070D9664B405A30D806CBEC2240A30B8E62D9664B40BAA6FA67D8EC2240AFF728E6D8664B4033DE6D4EE9EC2240F7B71A20D8664B406A8586CDF9EC22404D97F72FD7664B40A4F422C403ED2240F79BFD86D6664B4073592A740DED2240E9735BC9D5664B40B38FD3D412ED224054D52651D5664B402A06F2CE16ED22409ED83FF8D4664B4007BD99D516ED2240688CABF7D4664B404FAFA4E01FED22404B6E9F12D4664B401FE8E24424ED2240297A4495D3664B4029D6DC8D28ED2240F41FF41AD3664B40912F04A634ED224075CC6580D1664B4021695FB238ED2240EC25FBF6D0664B4085E8461C40ED22409C5D74CCCF664B401E691D3947ED2240B036A581CE664B408E1CB70150ED2240A1584EAACC664B40F91CED2E54ED22408C13B0C9CB664B4050C7F8005AED2240CB57FE5DCA664B40354B3A5E5FED2240E925D6E8C8664B40D813C14364ED22408011FD6AC7664B40ABD05A8664ED22403A750D54C7664B40ACE607AF68ED2240093A42E5C5664B40AEE8969D6CED22409CBB7458C4664B4055E4D8C87BED22400A55C905BE664B4026AED02E6CED2240BA8ABF29BD664B404046D47066ED2240AF0EC3D8BC664B40163A6BDB64ED22404B736DC2BC664B40900695621FED2240DFFE93EEB8664B40EC012BAF1AED2240A32726BDB8664B40E4CDAFDF15ED2240FD022F9DB8664B401C806B0011ED22405369028FB8664B40E4F886500CED22403A959A92B8664B40DEFC2C470CED22405C8C6E92B8664B40E9AE99410CED224061F2A592B8664B408328891D0CED2240F20CC292B8664B403AFC594307ED2240DF2165A8B8664B4042292D7E02ED22409679B6CFB8664B40EE09F2D9FDEC2240C2CF4E08B9664B40C3935362F9EC2240F433A451B9664B408C20FD96E0EC22408D577DD6BB664B40840C6BF2D3EC2240808C466EBB664B4080476E9665EC2240C68F08DDB8664B4067F79C3A12EC2240C023C90BB7664B405DEF50250FEC224081B8DB03B7664B407F8A7C24D6EB2240846E67BCB5664B40B1D5E9DEBAEB2240A1C36E23B5664B404D414B3DAAEB2240BF3E25C6B4664B407FDB032E82EB2240EBDF44ACB3664B406A9D2A627CEB22401455F381B3664B40C063D9F347EB22407DC6D5C1B2664B401C188BC231EB22407D548470B2664B40D49402FEF3EA2240BBF00BAEB1664B406B87A61EF1EA22407F1994AFB1664B4028D7B30EF4EA224033AC3417B0664B40FFFFF737F4EA22401886D000B0664B406E2C3305F7EA2240E0478B91AF664B4014289220F8EA2240D922EE24AF664B409D3C495504EB224040B5D0ABA8664B40CDC7959E04EB2240D9D2EF84A8664B40A53D086E06EB2240CDCC2A8FA7664B40AB09247505EB2240A4A0B794A7664B4025983C1204EB2240C3279F9CA7664B40097232C7FEEA22401969DBBFA7664B407AA17F47F1EA2240D269300FA8664B40A6043CD6DFEA2240C2CEB275A8664B4098065B0DDCEA2240CB60D590A8664B4002866C34D8EA2240C25D129AA8664B40DAE0A3CFD7EA2240E4FE2B99A8664B40A78F577DD7EA2240B4786F98A8664B400BA25A5BD4EA22403A0B4791A8664B40AECFCF91D0EA22406C389676A8664B4082325FE7CCEA224096FE6D4AA8664B40128ED53CCCEA22409701C93EA8664B40491555C8CBEA2240B42ED436A8664B406F5C196BC9EA2240B722800DA8664B40F2332F2BC6EA224042D2CBC0A7664B4056A00B35C3EA224044748665A7664B408CA21F5CC1EA2240ED3C9804A7664B409A747167C0EA224032EC6FD2A6664B4072D5E66ABEEA224074A02E2EA6664B40C904FF6DBDEA224054852390A5664B4092D3F75CBDEA22403A9D8285A5664B40A10B5552BDEA2240C402DF7EA5664B40FC793528BDEA224097B309CBA4664B40328B5CDCBCEA22400894F7B3A3664B400FA4EB53BCEA22408A0BCE31A3664B40238BF2BABBEA224014B6D39FA2664B4086469EC7B9EA2240F3990392A1664B403DC042AAB9EA2240FBFC2587A1664B40E44F6C08B7EA224067DED88DA0664B40BCF13C63B3EA2240D30435439F664B40A1B6B374B0EA224060AF47399E664B407D134AEDAEEA2240C31741D49D664B40FD31503EAEEA22406DCE18A79D664B40D42F14EAACEA2240808A484F9D664B402801D71CACEA2240CF77501A9D664B40CA42224DA7EA22404395BE059C664B40402B540AA2EA224013349BFC9A664B4015237B599CEA2240F4C6E5FF99664B409F204A2495EA22405C8579DD9A664B40C24A249A94EA224086CE11EE9A664B402F053A6E92EA2240AF50D2309B664B40A799DFDF91EA224032FDEA419B664B40AD3C011D87EA22403F03C1769C664B403F27E3137CEA2240F743109E9D664B403900BEC770EA2240700B83B79E664B40F3F275CD58EA22401246699BA0664B4055952E4842EA22401E8BC7ADA2664B40BC3F506934EA2240A7E3608EA3664B40F2D207E127EA2240A8EE4D59A4664B403A70086A20EA2240C2739F99A4664B400880ADF71FEA2240C5B97E9EA4664B40077B3F9E17EA2240F48682F9A4664B40FA5737BC08EA224001E6A465A5664B4045D61844E2E922406F7F6F01A6664B40210171AABBE9224045749B67A6664B4092FF5F5D34E922400D62849FA7664B402B887D3925E922402F7E6AC2A7664B4073A98BAA20E92240CB23EDCCA7664B401F9505F71CE92240EE5C1B5DA5664B40C1063DE61CE922405A7CA65DA5664B40430DB39307E922403FF8110EA6664B4002CC7CA47FE8224088BCBF72AA664B4064D675587CE822402984078EAA664B40C5E6D55D7CE822401CAA2696AA664B40F12E5C637DE8224096DF4E23AC664B4073C9202C7DE8224029050A1AAE664B409BCD22717EE82240F1CB4C18B0664B401414FF3F81E822406A85E080B4664B408428122E82E822409C847160B8664B408097277B82E822404F515EA1B9664B4087F7270382E82240878F480ABA664B40F00AEA077BE82240A4878D24C0664B40FA279D077BE8224023F0D624C0664B40E9A4913475E822404A8D393CC5664B40E3900BE96CE822402729066BCD664B401BD99EFB6BE82240160A607DCE664B406E3515F36BE82240FEBE3487CE664B402B96322F6BE82240FE919069CF664B408908C5B36AE82240CD212DF8CF664B40C61A59C867E822404964FB0DD1664B402CCF79DC67E8224099D9800DD1664B405CE4C81062E8224062404243D3664B40E25629695DE822409764E1E8D4664B40EBF331633FE8224040577168D4664B404DD97AAB2DE822403D6BF3CFD3664B40A00EBB6120E8224057925A5ED3664B4007CCCC0814E82240DD939F0CD3664B40F8DF96BF13E82240CB715F0ED3664B4030F15B870FE82240BD07DCEED2664B402A00E5760FE822407B9760EED2664B4084573CDC1CE82240D11FBB33DB664B4020E2F6FF26E822403C4C6CE0E0664B40E109647931E8224082F034BDE6664B4091CEDE493EE82240F98D90E6ED664B4087FB0F9240E82240F941042DEF664B406F9784B142E822400934DE5CF0664B40DE3595D051E8224012E7A0D0F8664B40EC7E475961E82240B8C1708001674B4039921B916FE822404AC6287109674B40EB804CEF7EE822403A8A290E12674B404AFBB8FFA0E822400962295224674B404B1AD615A9E822406D26A5A829674B40ABAF56DCAFE82240FC51A4742D674B4065E5F1A4B2E822402CDE1C042F674B40224FA489B8E822405199AF5132674B40CADA1A63BAE8224069ACC1B333674B4067B9A516BCE82240AB1A71F934674B40D6B524A9BCE822401AFDFF6635674B4024745014BDE822405A2C24B735674B401E3FC087BDE82240829D7C0D36674B405FE8C8A5BDE822401250F22336674B4011235127B0E822403A19731536674B40C650CD58ADE822403BA06D1236674B40ADE4E769A8E822407185200D36674B40EAFA4F3AA2E82240C6817B0636674B404E42BF4A9FE82240300533FB35674B40E95226EE92E822409C52B2CB35674B40F95BB8117BE822400CDD007035674B40BABDEE7078E822401F9FE96535674B40F513204175E82240456EF34B35674B40508B726956E82240C4C2BB5034674B406C7E384E4FE8224060BC4D0A34674B4072C0A2F031E82240B20BE6BD32674B4008583A9230E8224080F966AE32674B4030614A672FE82240EB002EA132674B40110B35CF2EE822401B5AB89832674B404A05B77B2DE822401012D68532674B4023DA62861FE82240DDCE0DBF31674B40F9C42C7712E822405B49130531674B4019C790A90CE8224025CB6BB230674B403FF2F4540AE8224022213C9130674B40D7B829E507E82240506B2C6830674B4014D523FAF2E72240B8F592072F674B4008C1F2A5F2E72240615D07022F674B40BF11376CDFE722404580D3972D674B40774C38D3C8E722403FEC580D2C674B40C3BEBC24C7E72240783788A22C674B40CF158EF3BBE72240B647728330674B4077EAE4B78BE72240F4AA578140674B40B9C235D270E722402507436C49674B40B7ACE2E16EE72240CF7BD1104A674B40D178FB876EE72240C1F8902B4A674B402829AF0C6CE72240023298E84A674B40A25EC69F5AE72240FBD2001850674B406DBA3BEC53E72240A4A87B1652674B403867AFD953E72240A80BFD1B52674B406E597F9A50E722407D66521353674B40853EC313E8E72240CC4081935C674B40A5E1FD4179E82240654CB80C81674B406EE3B4076CE82240511EE7E682674B40986C38496EE822403F79B83A83674B405E28ADC432E82240EAF886858B674B40CBA066C730E82240B40DF0398B674B4015EAA4DD24E822402BC7F8E18C674B4066967ADB26E822405BE0632E8D674B40C9596EFAF7E722406EB3BAAF93674B4060A50907F6E7224048034D6393674B40367A6785EAE72240D4AAF8F994674B4075173D83ECE7224075E2634695674B40BA957B54AFE722408558D3C49D674B40CDBFBAD3ACE72240DC5B7B6F9D674B4008E075DE9CE72240772E9AC39F674B4064D7E3499CE72240F8EFD677A0674B40A036C1D8A4E722404E539CC3A1674B402CFA9ABCA9E72240C0D9A0B5A1674B40F317FB39BAE72240713AAC699F674B40B4CC54F8B7E72240AB87D6129F674B40B6F60D27F5E72240C08BA59396674B406931B568F7E72240B2668EEA96674B409E44ADE502E8224014B3A45495674B4069BD77A300E822407803FBFC94674B404047137A2FE822402D45A67B8E674B403ADE48BC31E8224015D94FD38E674B402F10F5AF3DE82240CC4B312B8D674B40501A456E3BE82240019F87D38C674B402CA6369372E82240AEF9103185674B4047F275BA7BE8224048DB889286674B406CE7BDE389E822405AAB54E486674B40247A941B8EE82240188FAAA186674B408C169B798EE82240F22CDD9B86674B407DDBAB16A8E822406F3DC2918D674B405E6A3EF9ABE82240F40A0AA08E674B40BF59B65BAFE8224053EABC2392674B4081B458F0C8E8224072B066B3AC674B4014BD9053C3E82240609DFCD3AC674B406195B920B7E822409DF24113AD674B403F6DFD55AAE82240DC2E9C55AD674B404BDA6D38ADE822404A516A3AB0674B40DAD60EDCADE82240769189DEB0674B40B92F8356CCE822401951174CB0674B4002AB6F99DBE82240B207C009C0674B40266AB561E8E82240FC28B238CD674B405B07F920E9E8224073C8BE31CE674B403DC2FB05EBE8224002A04BA9D0674B40FCF78D04EFE82240224E0880D6674B4026A1F3ECE6E822401484A7A8D6674B40D5D574ABE6E8224072106469D6674B4026C194F6C3E8224040484912D7674B406AE012BEC6E82240253C0783D9674B404AD15492D4E82240B7685B3AD9674B4080813ED0D8E82240BD6E77ABDE674B4036901ECAD9E822405A93B5A6DE674B40806A4787F4E82240DBA9BE12FA674B40118CA251F5E822405B6F4AE2FA674B40207164D817E8224034F6150800684B40ED139723E9E72240C76F8BE3D3674B40C4FF74F8B0E722409B89AF20D5674B4047B63FFCE7E722403158EDE109684B40516BC691FCE722407D66AC9E1D684B402730AF131CE8224004DAEEE51C684B404A5BC62339E822405813863B1C684B406B56525E25E82240A63C2A1209684B402B577EA122E822408271FB6A06684B404A2E919D92E822401B7A22AF03684B400961FCBBD1E822402E3803E701684B40CD465D35EAE8224046C7263601684B4072E48B31EBE82240BA5E946401684B407E3F210EEBE82240D7DA5D6501684B407F7261CFE9E82240B837736C01684B4034117DDFF2E8224080A7691903684B4066C027AAF8E822404213882B04684B401524A0624CE92240ADF610A613684B40C7A229495AE92240768649AC12684B4034D67C3C5BE92240721E2BF212684B40FD1D6B6639E92240711CB56915684B40A5F8F0850FE92240897E4E7718684B40387F2310D7E82240703134E716684B40C82AA376D5E8224015CCF71118684B4050CA64CE0DE92240892EAFB219684B40D4EA9B6F3DE922401BBFE42616684B4007FF2EDB5EE922404EA9EBA913684B402F86998566E92240F072CEE715684B401466E03873E92240E045A7FF14684B40F8D8E2A27EE92240ED7FD7A317684B40237C53C07BE922409E65CCD717684B40AE81692F81E92240DC8C5E7019684B4028E712B47FE922402C3BAE9819684B409C958DAA7DE9224020E9141A1A684B401FF99B2F7DE92240E614EDB61A684B40F2675B867DE92240ACD1B1091B684B404D70667F80E92240D9F438491C684B4001084C5884E922400C9899851D684B406E5996E186E92240260E79221E684B409520001AB8E92240BBD571A327684B40D884FE96C0E92240634A044729684B40E7682BF7ABE92240B9B127642A684B40D376D62C82E92240BA2EE8A52C684B4015E0B52F85E9224060F729E32D684B4082EC7FF4B1E92240C0A2E87C2B684B40E4483847B7E92240C9E5DF332B684B40A610E5A2B6E92240EF54B0F12A684B40EEE7C0FEC4E92240976D512D2A684B4045F5D2FAC7E922405036BCC62A684B40F69A1C76D6E922405D581DAF2D684B405268BE91E6E922405A662EC731684B407106F527EEE9224049CDE51134684B40F8D9AFE2E2E922400AED85CB34684B40336B4752E6E92240AC9B1DEB36684B40CAA06B7FFDE9224035BDC6AD3E684B40EE8D837406EA22403B026DDD42684B40B41CC771FCE92240D1BF165043684B4075456126FEE9224068969F1644684B407EF51C7B0AEA2240DF09438843684B40743136800CEA2240E281E47E44684B40C77A6E5500EA2240485FC00545684B40CA47F7C501EA224049D184BC45684B40AF0A79F20BEA22401CA8BD4945684B40A456BC5D1FEA224039A9D9B151684B40F4AFBD822BEA2240F12DAF005B684B403E15A24B23EA2240C5DEC7EA5B684B402DF1770525EA22402AAE44195D684B40EC59AF7023EA22401146CD255D684B40099C453FD7E922404E81AC815F684B402BFECB4CD6E922400C6D5FDB5E684B4037AA51D0D2E9224031382D655E684B409D2BF1E39DE922404947291342684B4003EAB6C6BCE92240E022561E41684B404645FFEEBBE922405018428640684B409961F32C89E92240B1E25B1142684B407BB3FF048AE922408E7DE6B042684B40FA42225A99E92240042BBB4042684B400F94ECE2CEE9224015C1138E5E684B408688423BCDE92240331FE9F15E684B409A5CB873CEE922409DBBE2C65F684B40CEEB482A92E92240F4DF19A161684B4013E23E9995E92240F31CF49663684B40F6EE3D5924EA2240E73828145F684B40729568C127EA22402E9498F85E684B401F1AF16D28EA2240265C0D715F684B403472C9102BEA2240B6F3FC8C5F684B40FECCCA922EEA22400E608F3263684B4088EEDD692DEA224051ED9B3663684B4069AF22682EEA2240E7ACA07964684B409BD3ED0331EA22408F18036D64684B4046CB726941EA22408DACD7B082684B408903F9C835EA2240C029924A83684B401BD3E19D09EA224043EC889285684B40BB5790810AEA2240AAD70E3387684B4085E894C339EA2240976F38C284684B40BAEAA80F47EA2240376D661284684B4094449DA789EA224075BCD6919F684B40EF3FE3B495EA2240463A738BA4684B40FB0FBD62A1EA224084D129FDA3684B40AC03C57AB2EA22400B84DDE3AA684B4097D897D9E3EA22401A0A36F5B8684B40F881658D14EB22405E50EEA9C2684B404432FA2A1BEB2240868A78A6C4684B4086072AC339EB224008DD8A58CD684B40C23582A64FEB22404948D82CD1684B40DED955E5B3EB22405E7F03F2DC684B4085BE4B3D09EC224093E9D57CEB684B40E64E2BCA18EC2240B61F4FB9EE684B40463BA5D118EC2240D27B7FB9EE684B40F6BF35A62CEC2240291D5FDBF2684B401FC892CA64EC2240444BD3D800694B40107199C69EEC224093A6F1BE0B694B40E0D60DF5A3EC2240EE5242B80C694B407E3DE096BDEC224093FCFB1412694B4025EDFBCCBFEC224047703FD515694B4062328387D1EC224066FEE5B519694B404C9B610BD6EC224078F0B6B21A694B4017ECD714E5EC2240D3F3B94D1C694B40595F0CAFF5EC2240CB8C85131E694B40A14C39CDFFEC22402C7EE8D81F694B40F1C98F7E0BED2240B11FDDE421694B404E8745A757ED224093FDEF912B694B4000EAB0AF67ED22404A24587F2D694B404DD040AB6DED2240ECCCDAF62D694B40E40E165A73ED2240798B60682E694B402A45FD4F72ED224064AFAADF2E694B40F68572160CEE22409C63105F42694B4080A7DE3C65EE2240D17E08AC4E694B40FFE899B889EE224042B29FE654694B4096C385939DEE2240FDA9DA4B58694B4040B076BEAEEE2240DA5297F959694B40A273689DFEEE22400A7CB2C861694B407B9CFAC6A7EF22407238E59355694B4028B388D7ACEF2240079A573655694B402425FD25AFEF2240249185FB54694B40CC87FA6DCBEF224095989CF051694B40750126BACCEF2240F6EBDFCC51694B408B246BBDD8EF22406290058250694B402C9359A001F02240FC89EB1B4C694B405D94796E36F022404F30658147694B409BB6EF243BF02240779E330947694B4022A8144BA9F022407FE4F70F3C694B40726CDDDEB9F022400FBEB9DB3B694B4079945FA2BDF02240227BBE863B694B40A8E133B4D9F022400F267A9738694B4060C28BBC12F122404905318C38694B40DB47C4BA22F12240F55AF49539694B40180E23A2C0F12240D80676A936694B40DBC04810C7F12240AECCFA8A36694B4060481BEAC5F12240F235E58E38694B40B39D7D89BDF122405CF2014047694B402275A3887CF122402697E12A54694B40010438A56BF122408588179352694B40879E9A5D69F1224013C40A1453694B40CDCD478805F22240B6C923CF61694B401D416CD007F2224026417D4E61694B40140F127280F12240FEF8538A54694B407F88278AB8F122400F86C95149694B40E8E2073F22F22240D93680D653694B40503AC9DC24F2224038EC144A53694B40323E4B25BBF12240134525C548694B4010627789C1F1224014FB3B9647694B40F1F8B3C7C5F122401E2D4EF745694B405648B945C9F122409E92756B42694B40DAEA5CA6C4F12240863A351E42694B40A8013B5FCAF12240E57CD78038694B40BB0BA996CBF12240C679857536694B40291CFBE8CDF12240F962866A36694B40F3C163200BF222406750DDB534694B40CD233DE579F222409B038B1539694B40B33288DAA1F22240B7AB6FA93A694B4099C15263A3F222400DEA19C13A694B40FCB276EC00F32240E2FE8B4141694B40DED529F229F322406A49545443694B4084AA753827F32240A0391B7643694B406C1C5ECB24F32240CD9E407E43694B40654A9708F7F22240E4C9144141694B40C23DF08AF0F22240E69C3AF443694B40807C9F8DC3F222402229A7AA56694B4004984D85BFF222408EE5573F57694B405C6B963465F222408C514BBF5D694B404A3E22B266F22240D77C47355E694B40803F751DC1F222401BD6C7BF57694B40701F735BC7F222404B91B4E956694B407727B017F4F222408104F22444694B4084FBD749F9F22240249DE0F641694B40AEBFD5DC4AF3224092EB4F0A46694B4056B511FB44F32240016FF07A48694B40F190A5E605F322403C2D86A562694B400E5238E98DF2224036D84F906C694B407E6373A564F222404A081FBE6C694B409A7732BA64F22240F161A82A6D694B403D07DBFE8EF2224095BFB4116D694B40DC29832393F222402FE686BA6C694B40C35B0EDB08F322402B2E7F0D63694B40F2874A8948F32240E563BCAB48694B40DD52D2CC4FF322403C8F55A945694B406F42AB6334F32240FB068A4044694B40E2C6287032F322407416A8F843694B400D89FFEF31F32240F64A8CBC43694B404A9782BB8CF32240D202C75248694B400C3DA7699CF32240E4FC8F1D49694B404FFF83549EF322409EDAC53349694B4054E4A1D5A7F32240087DDFA149694B40AC14D4DD1BF42240F8ABF8E14E694B408595FCFE66F42240329395AE52694B400FC3F96C6EF42240682BC30E53694B4011D8EB1A71F4224037AE733153694B402B70C3F08BF422402E873A1154694B40D5F326DCD9F422408BE10F3D59694B40DF5E148C16F52240B77665DB5B694B40CC72F26C24F52240FB9F53795C694B40DD13686F24F52240CF056E795C694B40B443F5AC76F522409A11412160694B40E801BC2DE5F52240032D05F265694B40BFB8881CE6F52240B3AE95FE65694B402BE66CB748F622407E4E7F7C64694B400356DAE6B8F62240A78E876660694B40A64231BADBF62240336E0AE55E694B40868CABDDE3F62240ECB173A95E694B40965F58A0E9F62240BA58477F5E694B40BD4C83A8E9F622404834B57F5E694B404C3B0605ECF622407FEB6E9F5E694B400C212C7501F72240BB9B17855E694B4048C2CBFD08F72240FE59D57B5E694B4052E213BB0FF7224076C27E605E694B4020234A9023F72240E80F0E105E694B408820086D29F7224099B71CF25D694B40326442EC40F7224016F7197A5D694B409A08A34859F722401C4C4DFD5B694B40F58D45515FF72240049A815B5C694B40821BBB0A72F72240A37692D75C694B407C46131D74F722403D2F30C95C694B40A098DA7B8EF72240FFA91D125C694B4024DCBE5B9FF722408CBBF79C5B694B40E8AF86AAABF72240FF1E4CBB59694B400C97C100B2F7224037854BC358694B408A190403BAF72240710815A058694B40C093EEC3EDF722401895997353694B40039F119A1BF822405C48992951694B4093C4DAA548F822401CCF4E6E4C694B4044DCA8F170F822409079F62E4B694B40EC61005D91F822409539FF2D4A694B405933B1F19DF8224000EF88A34C694B404ACA7379BAF82240F47D2D3752694B407D3FF32FF9F822404A073FC64C694B40730B14432FF92240F17B34354C694B40490ABD1C3FF922406F08C48B4D694B405CB031DE58F92240C020A88658694B4000262A2598F9224053FD425656694B408E56728BAAF922402FF75ABC56694B4007C0B3251DFA224094243B3859694B40C4C1F58F4CFA22400D26E1485E694B40848D4EF964FA2240EF3C56F367694B40E425315C9AFA22405CEA47556D694B40E157CB81B7FA224017A5B3866F694B40A9DE7F06DCFA22409B85923670694B409B0F0A55FDFA2240E99A12E16F694B402E58D03628FB22409493C9686C694B405F6E258030FB2240CBF6411B6C694B40B6620FE834FB22405752A0D16B694B40CDD62DA33CFB2240B4426B506B694B409070CB6B44FB2240B34B7D5C6A694B40E7F8E8B186FB2240849A33EC5E694B40E3CCB87C9DFB22402C56899B5A694B40D3232B0093FB22402D81276958694B40	Flensburg 13	\N	fl13
1	organization	102	0103000020E610000001000000EB030000F9CB4235CED2224041640F587F694B40B1FA693BCED22240BF3AD2577F694B405E3F7B1DE4D2224010E7DE5C7F694B4085C342F5F0D22240ECBFDADC7F694B40DA662149FDD2224085AB97BB7F694B4078F938E815D32240406AF0697E694B406C4F77A201D32240238A205C7A694B4032A5CFF800D32240D0718B327A694B40AD7A6DA4F0D22240FF8FC83176694B40EC0BE1B2F2D22240CC9E1E2474694B40B007BFA801D32240F795BF6572694B40BECD4F0D1CD3224052C367FE70694B4016F94C8523D3224092BDB69870694B40B4E8F8D72BD322405741F42D6F694B407DA305A76DD32240C401E7F019694B404A55782E6ED322407BEB4AF419694B404CFC32316ED32240E3ECC8F019694B40403A5F0263D42240FF8DF01120694B4049F8D66F63D422405641AE1420694B402475AC3977D42240C148C91B1E694B40938E548B77D422402A6FA6131E694B40ED7AD8217FD4224048EB42271F694B408ADB44EC85D42240576F682221694B400B4C093885D42240EFCB17DD23694B404D9A2E238BD42240CCCB027825694B4070446E6992D42240FDD8744F26694B40C36DC74294D422400DE7572B28694B40AE3B9F4B9AD4224009ADE01E29694B40EE05437DA6D42240F8666A162A694B4087496C00ABD422404ED033BB2A694B40363DF94FC4D42240250B295733694B4065266938C1D42240509187FE34694B4008CB650CCFD422400FACF80B38694B40C4498342DED4224031685A0439694B40F8F0993EF0D422400022FFF33A694B4078290374EFD422409A47880C3C694B406A333EF1FAD422402B815BBD3C694B406CB02E280AD52240699065043D694B401F1E0B7D0DD52240DCEE643B3C694B4052D79B2419D5224089980EF13A694B40DE6E67A319D52240042333F23A694B40B70DCAAE19D52240BF46F0F03A694B4070CC158927D5224050F6DA103B694B40F481F20528D522405F21FA113B694B401CBB9BA435D52240F90927CC39694B40D67722B235D522400BB5E3CA39694B4020C030753BD52240302D6ED839694B40CB2C61DB3BD52240A3345ED939694B4039E17AFB44D522405762A39C39694B409424DE1B4DD522400E75C25739694B408F2208FD56D522405FC0981538694B409C12DA1657D52240936F4F1238694B40A8324AEE5DD52240F286AF4338694B40B609475161D5224059D2205C38694B40FDEA71F866D5224051715FA539694B4037FD500A67D5224088966FA939694B40D490CDE579D522401944C70139694B4078F1F73F7DD522405CA84F4037694B4008924C517DD52240DBF93F3737694B40AAC554A07DD522405F11D70D37694B404F7B40A17DD5224048365F0D37694B40231838F981D522408DB62F1037694B4002DF91C187D522403A513F9E37694B403E8C73EE87D5224076FF8EA237694B40744646A38FD52240FA4DEA4437694B40A2E02D0390D52240EDC95C4037694B40C3A7EE389BD52240D58C786D38694B407CF7A66B9BD522407F8CC97238694B4036772154A0D522407576AF2438694B40E6BEFA76A0D5224032A3852238694B40A7FEB423ADD52240C3E2D36238694B40572BF38AADD522408F5AD4C83A694B404466BD8CADD52240F9824ED33A694B40089DACEBADD522402244CD073D694B400C2A211ADAD52240EA7D72B63E694B404C469F71EED52240326D724C3D694B4058DC503BF1D52240409C60E33C694B40A31222410DD622409FA130C338694B4022E5FDF619D6224080AF2B6538694B409F52F20D1AD62240A48C626838694B40DA072C811AD622402B390D6538694B40250F0B4424D62240E93DF6C239694B406BE17C6D24D6224052D7C2C839694B40233729B425D622406FCF80F639694B403202F5AA29D622403F6A9F273B694B4045990ED52BD62240CCFE932D3D694B40F12D89B333D6224030C5AC1E3F694B406BA530DF39D622404C4E31673F694B40F7C41E8D57D622409DE8339343694B40C1F0A6ED69D62240E4E849A147694B4002F034456ED62240E7D97B9249694B40C439338D73D622404C2E348C4A694B404CD5D25A7FD622402E3640794B694B407A494AB299D622406F4A5FC94B694B403F77CDCCA1D62240C0FE2F7D4C694B40BBC4943AACD622401059DAF54C694B4095779AEBC3D62240C771FB074E694B40DCEA8A02D2D62240A3F4DA7750694B4063EF7476D2D622400EC2F5F850694B404DB71B86D7D622402E0B1A9C56694B403A472FB1E5D6224087C708F958694B4005C4A20AF2D622407B13BDBB59694B4082F74C4A05D72240935410AB5B694B40876819AE21D72240C8195DDA5D694B40324848B651D7224099150F1E5C694B4010D4F90F66D72240207FFBBE59694B40E62F510AC3D7224029454EE94E694B40A2087E74CFD72240555EB1CF4D694B4099E6DD4DCFD722401BAC3DDF4D694B40E62E2729C4D722401999F25952694B403C54ABAAB8D72240A0ACA1FE56694B40ED7D01D4C6D722403F9763B857694B40E9118EE8D2D7224064B1DD5658694B40AAA77D08D8D722404C57189A58694B40DB97F7C707D82240DDB77A0C5B694B40804208E70BD8224071A671425B694B40201544EC0BD822404BF6B5425B694B4039C6F1111ED822405929BF305C694B40B99ED72F1ED82240BDF2142B5C694B40D1D8209C1ED822407C69A0305C694B408F2C09391FD822409C3BD1F85B694B403ECAB5D930D82240E9D9A5B355694B40CF77335836D82240D0CC5DBF53694B4097EF67BF67D8224031727EAB49694B4023FEDF4988D8224095493E0347694B407CC7A5088AD822407746C4DE46694B40A5E095CE8DD822401E56925746694B408DE7914C9BD8224022E4217444694B4036BF78F3B8D822408072A94D40694B405122985009D9224013B2328132694B4098A71AD017D922403F05DF872F694B40A97666C82DD9224076575B7129694B409C16BA5635D92240F3C1450C28694B409550B1EE41D92240C35A876D26694B40A0569BC95AD92240FDBE5ADF24694B40D1D312DA67D922409DE192B623694B4071E9FEA76AD92240E660B29D1F694B403CB37F457ED9224003A8A03E1A694B400D42A3C8A2D9224019139EA016694B40097CF0E7DAD9224081CA1D9F0A694B4079F6E5ABDAD92240E1B664F407694B400F8F32CDDFD92240CDE69EFDFF684B40C187829B03DA2240AD17A6E9F1684B403E4F6C00F5D922407D535263EF684B40F34597C4E7D9224035BF5F65EE684B405EC4F047ECD9224099062BB6E9684B40C9A92E52EED922409804EE1FE7684B40EEAB7214F1D922403DC248A0E3684B40C7D252DEF3D922401A9DCF24E2684B406E37AB30F5D92240804DF970E1684B40B635789DF9D92240E05EF916DD684B408B18128007DA22400ADDA240D4684B40201A698207DA22402414283FD4684B40E500490608DA2240040A36EBD3684B40CF6E0FD725DA22402C599430C8684B407A1158B459DA224032374FC9B3684B4067EE5E196EDA224061266CACAB684B40CDFAEB2082DA224094C58C3EA1684B400CCC68D097DA2240BA2F10F295684B40A7074B0B8CDA2240117DEBCC90684B408EE7E6C88BDA224053C0E8AF90684B400F0419508ADA2240A568300B90684B4074E70FC8D9DA2240C73E145C69684B406871DE8F57DB22409CAA29CC47684B40DD1845A272DB224069E9429140684B40A9B57A79BFDB2240D81AB64130684B4087A68F70D8DB2240ED2C4B192C684B401D34B4AE0DDC2240C98BF76A23684B400065F4BC17DC2240D3083EC721684B40DE1367212EDC224039BB45201E684B401AA3A3592EDC22405FCD51CA1D684B400302756A2EDC224069B0A2B01D684B40AC0FB3412EDC224066234BA71D684B408B0414AA27DC2240E6E059241C684B40E3EA63222FDC22409D24303F1A684B405550364D30DC224092A0E04C1A684B408ACDCD7C33DC2240ED08717619684B4014CF38E936DC2240D9D5039018684B402BEF465A37DC224074FF7E9618684B40BFDA29CFEDDC224048756C0A23684B404C699E75EFDC22405322F71D23684B4039EFF83FF2DC2240ACEA9F2F24684B40013F2571F3DC22405DEA383F24684B407BAF369706DD2240F0F1265325684B408630A4040FDD22404504CDFC24684B40D49C20232BDD224050D0948C26684B40F4B474CA28DD22403439F46F27684B4018C2931E3ADD22408CC3236628684B409CB0E4F540DD224030EC82D325684B40D4F5483E2FDD22403AF58DD624684B400C4E0CD62CDD224083E433BC25684B40091B501A11DD22405FF1EA2D24684B408CA48B090CDD2240178ED80023684B40035D0903F9DC22402C612AF221684B402764433CF2DC224004BD084222684B40B4A9484B3ADC2240FB1983D017684B40DF0613DA39DC2240137C15CA17684B407BCBC17239DC2240DD4B38C417684B403619CCDF43DC2240505AB11E15684B406F9E53DE43DC22407EB6581815684B40394601D843DC22405B603AFD14684B4016E0A0CF43DC2240248F12D914684B40FA90099F43DC22401647730714684B4037F1BB2879DC2240AD73042507684B4086D0D5827FDC22401B04AB9D05684B402F61874D87DC22400C2FAE7D03684B4085B68425C8DC2240537985CEF1674B4030E494F5DADC22409F2E1E26EE674B4078123F38DDDC22406F2698B5ED674B40D18641323EDD224014DF7ADADA674B40D2B4A80E6FDD2240F361641BD4674B408C01699C70DD2240467A9FDED3674B408C945BBF71DD22401E112CB2D3674B403CB2F3F078DD2240F122D198D2674B40C102651379DD224087EE8D93D2674B409DF3A8EC82DD2240AF0A7312D1674B40FE873C506BDD2240A89CB32ECC674B406708370E67DD2240FC3FF84CCB674B40296BE35A72DD22408BA8ABBAC9674B40B2CB9D637DDD2240B215D331C8674B402023C6CFF7DD22408D90182BB7674B40961FAB76FCDD224002A67685B6674B406A9B0795FCDD22401BC13C81B6674B403A9A22EB00DE2240603C8EABB6674B4048B5B25701DE2240C116B0AFB6674B4006E0547A03DE2240B8CB86C4B6674B40122EB0A137DE2240F02B52C6B8674B401D8150D837DE224081D007C3B8674B4039047A1C3ADE2240DA680FA0B8674B40CFBC4A363ADE22403E76B5A6B8674B40406850683CDE224026AF6637B9674B40715CE3B73FDE2240699A9A11BA674B403E19E81A43DE22405293DC25BA674B4010093E6443DE2240E2703824BA674B408E2CBA1E51DE224053CAB4D5B9674B405C38F9CD54DE224018EAA2C0B9674B403E96010755DE2240ADA953C2B9674B407B8365918CDE2240BD0E5F67BB674B40C27A81548EDE22404AAC88A9BB674B402A24A68194DE224012A17091BC674B40D0A96ACAA0DE22409BDD854CBD674B40D98DB53DBFDE22401F0D4D19BE674B40E85701A6DFDE2240E1D3CA73BE674B4020FCDBB2EBDE2240B9DA4F7ABF674B40625A3512F1DE2240ADEC96BABF674B403D27BE6CF1DE2240483D3DB8BF674B40B09D1E2105DF224006E57635BF674B40E4E125680ADF22402BFF7012BF674B4084956FB50ADF2240B2426F10BF674B406556B65F12DF22400958EA9CBE674B40317BE2B012DF2240DCCD1E94BE674B4071C64E771BDF22409B449EA0BD674B40BB8B44A91BDF2240B8126494BD674B4062A0D28E28DF2240B153B86CBA674B40FD01FFA435DF2240F599A842B4674B4079F8BB055CDF22409F7993DFA6674B4001347C8771DF22403DD31F21A2674B4088DE351679DF22402F80B5B69E674B4034835FA775DF2240ACD81E9C9D674B404FBB4B0A86DF22403B79C5E595674B40BC9E6BD98DDF22407B50ED3892674B405F86DA5C8EDF2240E1AEF73B92674B40913A61C8C1DF2240C3FBBA6B93674B406D268634C3DF2240022D1A7493674B4048479A64C3DF2240FF70347593674B40DBD0AFD8C4DF22401E0BB9B793674B40062B437DC5DF2240A22E24D593674B40C5D64B8FC5DF22406B8E66CE93674B40C3581EA2C6DF2240AF74A46793674B40F2DA2DC9D0DF2240808230B78A674B40DEF6D281D3DF22400175F26288674B4058DD6308D4DF22404EC9036688674B4035F893BBD7DF2240DCC19A7B88674B40FB9825BFD7DF22405196697888674B404003C138D8DF22401BB1FE0B88674B40DE0A45BFD8DF22400B9C1B0F88674B4073B9CC4DDADF224099B5521888674B40F3D19B5B18E0224025CB528789674B40E9FD2C5F18E0224032F9178489674B4020875FEE29E0224096CE9D9879674B40D9D9D8B419E022403BE7643C79674B40FED7504FECDF224013C95A3A78674B4087D7B72F7EDF2240887D5EC875674B4045B4CD2F7EDF224025903CA775674B403EB60B307EDF22403A234F5975674B407F34D8307EDF22403050AA4B74674B40649FB2367EDF224035248B1F6C674B403C6A47377EDF22405795688E6B674B4039F55B3A7EDF2240FBD6999C67674B40EBBA73C47EDF2240F69B369F67674B4027FB0A1982DF22405D6953AF67674B40E64BD4B0C1E02240376A2FBB6D674B40844545B3C1E022402BE07DB86D674B404DE43F85C2E022407399AAD26C674B4040F701BDC5E02240AB73E24C69674B40307E493595DF22404FE21A8863674B40160F746EAFDF22403F9DC58446674B4068C262338BDF2240E85526D845674B40638449C054DF2240EBB5B8D444674B40DE231BC155DF22405B70E8C144674B40E9923D4056DF224039B898B844674B40FA89B44D57DF22401105DCA444674B402625C13957DF224019812D9C44674B4081A5D0FA56DF2240FF7EC18044674B403982BC9151DF2240B17B922542674B40DBA71D9134DF22408FB81C8435674B40838381C3EADE2240258C915F15674B4057914E02E1DE2240AD5337AF10674B406DD507CBE0DE22408489A59410674B405527031FD4DE224000FD4C7D0A674B40A1218BF0D3DE2240A589AA7A0A674B40221E70E7D3DE2240C688257A0A674B40AE83CFA6D3DE22409AFE7A760A674B40DBBB504FD3DE224065E685710A674B401C956CCFD2DE22405775C47D0A674B4000A4CF78D2DE2240E2100C860A674B407E1A67DAD1DE224068B536950A674B4091E8D836D1DE2240B20BDEA40A674B40203CA2D2CCDE22401A63A3DA0A674B4052C41546CBDE2240F55E99ED0A674B408C47DD3CCBDE2240BF6B0BEE0A674B402110D3C8B5DE2240131A9C5701674B4035BB6692A6DE2240DF9FC089FA664B40C090CBC2AADE224063720151FA664B405B0CA8A0A3DE224060885D07F7664B40487B91B39DDE2240CF035496F4664B4031A328E282DE22404D1FB789E9664B4084BF8CC761DE2240D8DC6B4CDA664B405B0C1CAF53DE224013D54B52D5664B40DDA7863653DE2240C158D54FD5664B40B54A43C701DE22403B968AA5D3664B400EE67E3EB7DD22402980FA7DCF664B40C14F52D6B0DD224068EE91FCCE664B40D19827F58FDD2240D2557464CC664B40AEDACD6586DD2240A2C00BE5CB664B406974EBA489DD2240FF8F2536CB664B40182F60228ADD2240C271BD1BCB664B40334565817DDD22407B016652CA664B402915E3FD7CDD2240D7FA524ECA664B4048F5C4AA5ADD22409230493EC9664B4010925A3E4FDD2240FEAD431BC9664B402EC496914EDD22409BBC3119C9664B40A253E54E4EDD2240D9ED6418C9664B4087188D4A36DD22405604BF67C9664B401B9E2BE010DD2240FE2BFE6FCB664B4064467E1A10DD22407D3F507CCB664B40D28EC7D1FFDC2240C04F2D80CC664B4087D95AD1DFDC2240095112DFCD664B402B7590E1CBDC22405E418E3DCF664B4099EFBE6EC5DC224008EC3776D0664B40126A03ECC3DC22409AE7A7B1D1664B40101F4CEAC3DC2240757709B3D1664B40CB325188BDDC2240DEAFF4A3D1664B4063A15FBDB6DC2240E8ADE593D1664B40B45D6B8FB6DC2240B6787893D1664B4020957DD3A1DC2240796EC9B2D1664B405AE38168A1DC2240A1C36AB3D1664B4099C48D6A85DC22409308D93DD1664B401F94275D85DC22404BA43A3ED1664B408B06281F81DC22403B87582CD1664B400F3589537DDC22403367DE1BD1664B40AE99F26D60DC2240F8018EC8CF664B4039AD8FA650DC2240F6C9ECC2CE664B40B743A22D41DC2240D4E5C67FCD664B404B0DE7D63FDC22401872D163CD664B40BC41A9F535DC224056048A20CC664B406CE052CE37DC22402D8B16E9CB664B40F9900EFA2FDC2240156CC985CA664B407B3FE5642FDC22403A59586BCA664B40248F5A2E2FDC22404213AD61CA664B40EAF4DA0D2DDC2240946E83A1CA664B40E0CEDDB92CDC2240D4A05BABCA664B402579DC121FDC22401C23CF52C8664B40574E2C491DDC2240EDBA1404C8664B406A3310F619DC22406A1EE271C7664B40001EDDAA15DC224079E0FAB4C6664B401B423D0713DC2240B7A55E1CC6664B405D1CDBCD11DC2240428194D5C5664B405B3C6CB30FDC2240E4F0F35BC5664B407A89931A0BDC224000631A52C4664B40996FFEF10ADC2240E51AF148C4664B40745AB014B2DB2240E17510FBB0664B40BF5EDCEDB1DB2240A409A0F2B0664B40529F4199B0DB224032BB0010B1664B40312D517F66DB224065EFBCF19F664B402B9EA8EB41DB2240AE88D22F95664B407166A0CC3FDB224023B21C9094664B408666AB163EDB224028D53FAE92664B40B26F4AB23CDB22402391607888664B403699795041DB2240C0B7B27B7B664B40581405F841DB2240FBE18C7B7B664B40A06C54F941DB22405061BB767B664B4005145B7442DB2240A8E5B2767B664B40CE8AC96B48DB2240EBC35E7968664B405B1EDE0855DB224017B2A29C64664B40B42D6A9154DB22407CF4029764664B405283C56954DB22404393259564664B40943E47D9C8DA22407CABC5035E664B40E41C3482AADA2240E3B385305C664B4099A64C979BDA22406C1DC94A5B664B40BBD9B16E98DA22405055A2985A664B408BBD17D392DA2240788AE58D59664B40A5D1831A8DDA2240FAC9689F58664B409293E0DD89DA2240AA09232558664B40416FDAE289DA2240FE0D132358664B40794F1A0C88DA22400AA1EADE57664B40CCBF509287DA2240F14170CE57664B40A454C9F383DA2240D02B105157664B40919DC52F83DA224060818A3657664B408320024281DA22409CFAB8F356664B4076000E0281DA22404534F2EB56664B407EF9EBD37BDA2240FE1EAB4A56664B4064104C257ADA224098924A1656664B40F5A524247ADA22401718281656664B40073BB07D79DA2240F628B50456664B401759C4E278DA22401E6A74F455664B40C0995C3E6DDA2240A72DF3BB54664B405BD8D18C5FDA2240A244688E53664B40BE87612C51DA2240465B079052664B40F9E24F6B44DA22409343EEE051664B404F036DA842DA22404425C0C851664B407A32DFBD40DA2240B5A7D1B151664B408C14E7BD1CDA22407BB9030350664B40B6C69E69D7D92240BEE4BAC64C664B40C66D2A50D4D92240FEAFB3A14C664B40B689712ED2D922406C663B884C664B40581A2BA4C9D92240644B0F164C664B40FE4F8988C2D92240D84005A24B664B40B8D87C55C1D9224032B0708E4B664B40DAEBA1AFB8D9224011CBFEE44A664B40C170CE66B0D92240764E4F244A664B40C5EABE86A8D92240F8A6714D49664B409428761AA1D92240FD39966148664B4035CBD9C05ED92240BB09E1813F664B40A8C624995ED9224049BD337D3F664B40D94DED5C5ED9224091BE19763F664B40EEC4E9FD58D92240E3E703D43E664B40601E170457D92240C29BBBA53E664B40702EB2B552D922408167D9403E664B40B8CFC86B52D922404DE5C13B3E664B407EE140FF4BD92240AC7480CA3D664B401F313DF344D9224028B1A7723D664B40D8307DAB3DD922407C68913A3D664B40BF4DB54236D92240F3D70D233D664B40F8FD9D2A33D92240F41CF7263D664B406B57198F31D92240FFADFD283D664B40915354962FD9224043877B2B3D664B40508AF7142FD922400C8F1F2C3D664B40AB9495E52ED92240C6675A2C3D664B4099050DD42ED922405EA0712C3D664B40CC60A3AB2ED92240E19A582D3D664B405EDD7A042DD92240A682D4363D664B407A17B9F228D922404DE92C4E3D664B40788BC17A27D9224026B799563D664B40974BFEDFB9D82240EAD46BC640664B408483C829B1D82240B677590C41664B40D48F529CAFD822404E86CF1841664B405617E59BAFD82240FBDC911841664B403A4B33E2ACD822404EBE14683F664B40F81D15DFACD82240AAA0E9653F664B408A761958ACD82240139033683F664B40D0F7FBF7ABD822405EE8A3213F664B403AFEA00A9DD8224064DF8A2C34664B40BBD2048B97D82240E11D482330664B406AC3047C8BD82240D201314927664B40D2AB5E938BD822403A99704827664B406004311290D8224015873C2327664B40B8B9837E80D822402A2830E51A664B404F562C6080D8224038A585D91A664B4000F0FB2380D82240CF9303D81A664B4081D51A4F7FD822400C339E701A664B407C4A481C7FD822407774EF571A664B4060E441DD7BD8224050AA10B217664B400883BE1471D82240AE964AE60E664B409C95B57970D82240EF63AE680E664B40F0C44EA46CD82240263564500B664B40578F802E6BD82240AB3D17BB09664B40169131266BD8224050CA18B209664B40A18C733E69D82240B3E9EDA007664B40BFA213FE61D82240D02101C3FF654B4063AE5D9A5DD822405B3752FFFE654B406C964EF248D82240C8216E66FB654B405E9793FB42D82240A9B6905CFA654B406667B60441D822406D1EFD04FA654B4011A3B2E240D82240B00012FFF9654B40C71C7C41EAD722404A675906FF654B404E5D6AD011D722400FE56EBB03664B406031E9B111D7224098B119BC03664B4094BF67A411D72240811764BC03664B406297EAEFC7D62240B41F4D4205664B40D70D9476C7D62240AA3A8A4705664B408FA76545C7D6224004C3A94905664B40C80F0530C2D622402C96D16405664B40B396F34F90D622403BC63D6F06664B401FAB1FDD8FD6224042D7A17106664B40793A0A668AD62240EE49F9D007664B405C6B1EEA89D62240504918F007664B40A6F13D6F80D62240632887510A664B40E01AF55A79D62240D60AA8180C664B40110678066BD622408087E9EA0A664B40654176C966D62240DFA8AB910A664B4023E2FC6C66D62240DBEA588A0A664B407BA45B6266D62240992F81890A664B4092C88A7461D6224013976B2F0A664B4002E90A5A58D62240ADFCEE7709664B409B9DFDF156D62240369A685B09664B40E1B1803A36D622402514C5C306664B401B9FDE432ED62240D94417EA05664B40FADB0CEA2CD62240810F72BB05664B40F362BFE52CD622407032E4BA05664B40811434932AD62240CC2CA86A05664B400318C10627D6224032E228F004664B400B61302F23D6224088EB1E4904664B4024EA2F9C20D62240F9DA3DD903664B4041D1E2F81FD622401BA206B603664B40795E9FF61FD62240817A8FB503664B40E0A6B4751CD6224004AC2CF402664B40378E17191BD62240DC4E01A902664B40B6ABD34A18D62240479F34F401664B40E6717F5517D622404AE389B001664B4007BF2AB516D62240026C598401664B40DB5B266A16D622403B98B26F01664B40A3B97F6516D6224087BA4A6E01664B409A120C8515D62240D4EB4F2401664B406967FA8215D62240B5F27F2301664B40FCBF64AE13D62240B2BE188900664B40B6D8AC3411D62240BED52866FF654B4048E1BAD310D62240813F0320FF654B40872664970FD62240448D0C3BFE654B404130AC6D0FD6224075750882FD654B40071886660FD6224080AD7562FD654B408042A3650FD62240885E3961FD654B406CA4A0500FD6224055B9F402FD654B4094EDF54B0FD62240E3CD32EEFC654B40E97B2ADB0DD62240638C0AA9FB654B40ED86D6D70DD62240CBCE8BA5FB654B4059D9BE6B0DD622409A639D71FB654B4022BB44680CD62240B344E8F4FA654B40FD0A32E70BD62240E59DDEB6FA654B4014CE35400BD6224017089D66FA654B404FF1F5770AD622408D4F5A26FA654B40F212891408D62240BCEB4E62F9654B4001363EEF07D6224087824156F9654B404B9801E907D62240B18C5C54F9654B4071D3DB6701D6224057F3AE7FF7654B400C1A245D01D622406E12B57CF7654B4077FD725B01D62240105A2E7CF7654B4068AF9B4A01D6224075748777F7654B404268ED639ED52240F8198AFFFE654B4084AF123987D52240391DA5AAFF654B4092752C5B82D52240D15FAE40FF654B4015128B4C6FD52240F953BEA1FD654B40E04102496AD52240697A7140FD654B40D10C026962D5224019EFF104FD654B4080FF59834BD522401944F557FC654B40F4485EF82FD52240B162E146FB654B40DD5E0D5617D52240EFDF39D8F8654B4044691B390BD52240828F2995F6654B40666B923909D52240D599B135F6654B40758A91DB04D5224020360465F5654B40235FF12A03D52240A1AFFFF9F4654B4046E8750C03D52240B21550F2F4654B406620AF6AFED42240B733442EF5654B40AEF4A514FDD42240CCC74F48F5654B400AD5AC29E1D4224083BB6C68F7654B40BDAD6424A7D42240704A43D3FA654B4034D6803AA1D42240EBBAFC43FB654B40E018541695D4224094EA4B18FC654B405E83118681D422401ADA52A0FD654B40BB57489676D422409973C970FE654B404D36F8885AD422402C15BCB5FF654B40470AB55630D422400E15F46202664B4021EEA4C318D422405EEA41F803664B402FD0EDEB0CD42240DCD2B2E004664B40372F085EFAD322404F990D2206664B408D6F0452D0D322403879B3FB08664B40EA4E5640C3D3224027109FDD09664B4085427B069DD32240F51DCAFA0B664B403B1501B996D322409660034F0C664B4057431FAB73D32240FB074A430D664B4093C321EF4CD32240E41E46EA0E664B400ADC264037D32240B539EFD60F664B4033B0F3E136D32240740EF5DA0F664B40EB41B40328D3224085F521910E664B40A2CE5F211CD32240EC70E4820D664B40CD5EA16D17D32240A0D612150D664B40773F9A9207D322406387C6A20B664B405A9BBDEEF1D22240CADBFC360A664B4000EF14D3E5D222400187F77509664B40F88A3488E5D2224084BE4D7109664B40620B8D8FD1D222407B7874F40A664B402F819C9DCED22240946EA22D0B664B409010991CCDD222400CA45C4B0B664B40CDDED72FCAD222407D2CB5830B664B401FDD1474C7D22240C10C1CB90B664B4087E97E42C7D222409C1DE2BC0B664B401D2131FCC3D222408389619A0B664B401484F679C3D2224013C502950B664B4084DA505EC3D222407C83A2A80B664B40F14BEF74BFD22240F733AF6B0E664B40E60D43CEBAD2224036D7353D11664B40013B4108B9D22240245EBD2D12664B400E016D87B5D222409580D10814664B4009262407B5D22240AAE7034414664B4025153CF6B4D222405529D14B14664B40942D003FADD22240FC45FA9014664B40CAB4977BA9D22240C231B7B214664B405E281E0FA6D22240CEDB68D114664B4073094B62A5D22240987775D714664B400B11C32CA4D22240EA454CE214664B40B827580CA4D2224070006FE314664B40E6EE4AE184D2224007E3ED9115664B40B521D6CE80D222407A34B8A815664B408956B1DA3DD22240B4EDD49117664B4015C469D13DD22240FB8D189217664B40A19181B723D2224053DA708A17664B409524593323D2224004E9498A17664B40DF49692811D22240FB712B5B18664B4055D1EF99F9D12240F22C896619664B40F0B3F223EDD122400AFF9DB419664B40B4233575E8D122409ACE85D119664B40FF7CE3F0B6D12240F650C3111A664B40F7457831B3D122409ED4A0161A664B403F651331B3D122409C8435171A664B4087B9E697AED122407E7E2D1D1A664B40E601D872A2D122409C75B44527664B409E64D21B9ED12240F67709D32A664B40A15C3E5B9DD122404038E2862B664B404361880C9DD12240563B66D02B664B403E04F8239BD12240CF5217582D664B40AB9E884299D1224028961BDA2E664B4067A53F2F99D1224094CAC3DA2E664B40F40431D498D12240A068DBDD2E664B40D57DF0EB96D12240E95D004430664B40F1E2537496D12240126C454830664B40C7F365478AD122407B1D65B130664B407CA597307BD12240E97BAD3331664B403CA9A1907BD122400341153E31664B402D4ABCDE7AD12240DB26992C32664B4029D3462676D122404FA88D2932664B408DF44C1F76D12240C018FF2932664B4098482D9C75D122405E73AB2932664B40590435CF71D1224086874E6832664B4037F3A22F6FD12240ADD6169332664B403BF3AFBD6CD1224044E7AE1033664B4083A7CA436BD122407C65E55D33664B40B88372526AD12240B3271AC033664B402F43740F69D12240FCC8784334664B40C1FE815168D1224093B1759435664B4008B9B9D267D1224071D05F7136664B40FAE27A1067D1224037D13DCC37664B403C35CA5464D12240CD7F25A83C664B40B34F6E2D62D12240E3DE5F7C40664B4043A247875FD12240C7B303FF42664B40B9E197405ED12240606C7C3644664B408DB18D1C5AD12240CA0BC59646664B40662D4E9B56D12240F09BEC2648664B40EB13628354D12240F910EFC448664B40D9C6FA3551D12240706E45BE49664B403950240C47D122407B54E9EB4B664B4048C03AE043D12240A0BAE8994C664B4099077AFD3CD1224051DF17374F664B4002DD38F438D12240B0E1983451664B40D1D7D8202AD122409023B08158664B404220671B1AD12240D76E87FE5F664B405D3DED7E0CD122402D68A42A65664B40E83A265106D12240C00DB88367664B40523A7D29F8D022409E461B3E6C664B40CE4D7F3AF6D02240DF3872E36C664B4029EF136DD3D0224029A4571E78664B40C173D11FD3D0224087EA093878664B40FCFD82CCCED022407F01799D79664B4081ABE784BFD02240A43426FE7C664B406EB9A405BED022400AC2DF527D664B400DFDB1CFBDD02240FBEE1D5F7D664B40F400D7E3A1D02240D33F887884664B40980A2B418BD022402D6BA5388A664B40AE19BC3366D02240616A325292664B4076BC04D953D022401F09C66B95664B4005F6BD6E42D02240F678BD5C98664B40E783A93E2BD022403CD0D5939D664B407BE001921DD02240658B7CA6A0664B40E32C0A3D14D0224090BE2B41A3664B406C12D24812D0224051C839CCA3664B40BED550D802D0224004668E1CA8664B40601B1C19DACF22408289C893B4664B40DA17D97DC5CF2240C04038ACBA664B403B761942B5CF2240BFB08079BF664B402AFBE6CCB1CF22401E27567FC0664B40C6C9A8E0B0CF2240E0372FCBC0664B40CA93C9BEA8CF2240B8C78767C3664B40176C857396CF22405F149FB9C9664B40E40C3D1085CF22404EB3F9C3CF664B404B95999275CF22408FE7738ED6664B40E358FC4C75CF22405A7FF9ACD6664B406A626D4B6ACF22409CFED4CADB664B409EB229395CCF22401FBEC2BBE2664B408361B05E50CF224018149F97E8664B404D3AF0A244CF224098303565EE664B40D01441833ACF224073D26738F4664B40B83EAE5430CF22409C6B6612FA664B402DF7FB3426CF2240DD1A6DE6FF664B40A50AC1151CCF224034489FB905674B407DFEB86112CF22400C5868E00B674B40B55FCCE00BCF22404DC8F4FB11674B40885DB4F408CF2240EC12297718674B40F74ACD5007CF2240EFB765EE1E674B4037AA5AAD05CF22407BF80C6425674B403CA3278004CF2240BFE3EF922F674B404859247F04CF22407FE88F9B2F674B402DE7899204CF22401C1D002934674B40D0D78F3705CF224043FFC75443674B4026BE753805CF2240C106A95743674B409A66953206CF2240AB3F2B7D46674B405A9ACC160ACF224040F9DC064A674B405A63B4950DCF2240485BDC484C674B4075E64C6C12CF2240ED8B47824E674B40099E4A1318CF2240F268F8B050674B407C8AAED122CF224027BEB0C653674B40EDC830DC42CF2240E1DCC6DE5A674B40969E2B833FCF2240504550E860674B4058CA93B93FCF22402AA615A762674B40515D499640CF22409116F25264674B4043762D1146CF22402E10DEDA67674B40C7300E374CCF22405E09C2B76B674B40CF51A90151CF224089EB924B6E674B40D5B98FE657CF22401D9698FF71674B40D48CA0CE66CF2240AF30A0C178674B4076263E337BCF22400376199E81674B407F2FCB9D84CF2240926EDB2585674B40292279C486CF2240F39CE1F385674B404E4C8F398DCF22402DE7F35D88674B4064702F61B6CF22404B653E8D94674B40A1736ADAC5CF2240E7B31FA598674B40C642AFA5D2CF2240BAF121789B674B40B02F2D34DECF224015EC70EE9C674B4036589DF8E1CF2240F75E8BC69D674B404499E6E3E4CF22404B7FFC6D9E674B40FA3DCCE6E4CF22400EEB9F6E9E674B40049CB327E5CF2240683B2C7D9E674B407F8936D4ECCF2240F68F8609A0674B409D3BDEA4EECF2240F2D398BAA0674B406B40B739FFCF22406BDB220CA7674B40A022BC9D12D02240E02CF4BDAC674B4009EFE80322D022409597B77DB0674B40161CF9E12ED02240E21E0298B2674B4016C594312CD02240D85B052DB3674B408FDC7B9C4ED022404F92C859B7674B40578235CB5BD022408F1ADCB6B8674B4047AE175A6BD02240DE0EC052BA674B40D74F45C36FD0224046E9E605BB674B407823AD6A70D0224055E17020BB674B4029E1BF2586D0224005896792BE674B4044106F5989D022403BB72214BF674B408F440D35A9D02240AE689A86C6674B4027563C1EBED022404BA96573CB674B40CA03A539E2D022406651EFFED3674B408E84AE31F7D02240D6D250F5D8674B40F6F7D3DDFFD02240004696B1DA674B400673183E0BD12240859485F4DB674B405572F6811FD122404A68CA33DE674B40F5A22F5029D12240DC69E0B3DF674B40ACA960BE2AD12240EEF42901E0674B40AE9D74C13BD1224090814898E3674B40F9F0960541D1224088B3CBB4E4674B40D7BFFADB4DD12240C607771AE7674B409CF1D02360D1224062C7D073EA674B404DC4ADB198D12240DCD82435F7674B40EAC4C817A4D122400D8EF19CF9674B405F11A32AA4D122406354ECA0F9674B40F58D0174A3D12240AEFA57A2F9674B402A9F3941B2D1224022E5F2F8FC674B4057CE56B5B1D122406EADAEF8FC674B40C7420CA92FD1224099CA24B9FC674B40B441A3A92FD12240CC1687B9FC674B409F106A534AD12240A6F2C12A0D684B40FE4E0D9051D122406F5B2EA111684B40C63450587AD1224063D31AC72A684B40115FCD1F93D12240D0E36E9A38684B4055D4B7B07ED12240600C87D13D684B401A0A37A27BD12240ACBB3E993E684B40A58D2AA874D12240B2633E7C40684B4083B3F598C3D12240BCAEE16D49684B400C2415A7CAD12240D4201B7D4A684B406A4EE108F9D12240C68C7DCD4E684B40EC000012F9D12240059657CE4E684B40DE2A5F8126D222409B6453774E684B4068266E0C27D222405BDA49764E684B40A7617E6828D22240360DAE734E684B40754365F328D22240608BA4724E684B403CC481CE0CD222408E3A0CC673684B408F4F95C00CD222407A7B87D873684B40B9A9ED420BD22240E03EAAD275684B403947EFB70AD2224046CB0A8B76684B40F41A4F221DD22240E694D36C78684B40302F72F41ED22240B015769C78684B40019132326DD22240593670CE82684B4062508FD584D22240B28ABA9885684B40CE7C358787D222403F9222EA85684B40942C60359AD222409EBE9A1E88684B40848EFD3FD1D222405553BD5E8F684B40189021ABD2D2224000838AA48F684B40613F83E4DCD22240DB116D8892684B40EADCCE7CDDD22240FB6F7AB392684B4022911C68E2D2224026A7741794684B408C32B19518D32240830F3D619E684B40C83286E718D322407927C6709E684B40FC0118CD21D3224029FE4621A0684B40FFD93FF80DD32240257F787AA1684B408EF3E2410DD322400935E086A1684B40D703300106D3224066591E05A2684B40C5825B8DD9D222408DF01290AF684B40A1D63B54DAD22240BD6EF9ACAF684B409E1FA3AEDAD22240BBD61EBAAF684B4035918104E9D222401F3575CFB1684B40172B2F96E9D222403C8DC143B4684B40B115DFBED9D22240718EEA59C2684B40A625D5FEBBD22240BD872B62C7684B4039915606ACD22240983CF144C9684B40574B2DB099D2224019CE93A9CA684B402ADB3ED08DD2224084963DFFCB684B4084D3525473D2224034A4C822CE684B4038F8027763D22240FEA45622D1684B40D6AA16D646D2224004B5C6A9D3684B403BCE820034D222400DDD15DBD3684B406488B79232D22240387FB448D4684B40BB05599618D22240D882EEA1D4684B40462EFC8618D22240D43466A0D4684B40CE6C15F208D222407CEE2512D3684B4042B5683005D22240CCB2480DD3684B40F454F1B304D22240497CA60CD3684B4042B7278DF3D1224067F66EF6D2684B4007CE0282F3D12240715C32F7D2684B409D81E089A8D122401123B015D8684B4090467869A6D12240022DDE3AD8684B4057F4D6BEA3D12240271E2860D8684B40A687163083D12240F38D4599DA684B40A747D8AF4FD12240A867C9F7DC684B40EC60574349D122407730A151DD684B40611C91AD45D1224035F6567CDD684B402F827FB520D122407930BC34DF684B40EC488F4702D12240A6CC9E8DE0684B40CA7E8643F3D02240BE2EEEFCE1684B40C335EC8DF2D022409645490EE2684B4086F3A3DDDBD0224049C84839E4684B40D72E9BF6D3D022405C8C28BCE4684B40AD8CF1B4AAD022404771D998E7684B40FB579D1692D02240CD9620FFE8684B400C4AD7B18DD02240E453103FE9684B405B0FAD887DD0224029BAEAFFEA684B4099A8827775D022400BFFDB3BEC684B4027FF5FD012D02240CBB26508FF684B40253FF5C2DECF2240A4FD81F308694B407AD6EACDB8CF22401EFFA2680F694B40829FAAA08FCF2240452B34F317694B40A8F0AD0F20CF2240C87C7ADC2D694B40D454E2EC15CF22405A1BA3F438694B402DFF07F714CF224074B5AB7F3A694B408F8B80480ACF22402860941946694B40298C6ACD08CF22409D6676CA47694B404C259C020ACF2240D687951949694B4056EC7B030ACF2240D65E8C1A49694B401B7CB6180CCF22405205785C4B694B40729CBD050DCF2240C7875E5D4C694B402A09525F0DCF2240EEF9FDF34C694B400F71C80C18CF2240F2E0F5BF4C694B4057A367132ACF224039AB2A364D694B405D5204EF2ACF224013E1BA224D694B40C13740E32FCF22404B2682B24C694B404C75768235CF2240D37467614D694B40A19E2C8B35CF224067B675624D694B40CE27B63C49CF2240997ACB344D694B40797658DF4CCF2240022E0AD44B694B4019E8C3215BCF224069B3BFEE49694B403FBE13AD6ACF2240EF4FF38D49694B40E8C35C3774CF224076FC184548694B40D6D7866A74CF22402C5AB34448694B40F77E17D474CF224052BEDD4348694B40AFF00F4E80CF2240C7C91D8448694B408A3A456580CF224011EC9F8448694B40CCA8D66289CF2240834A267848694B401C8AC38C8ECF22400B8E2A1048694B4055B5749A8ECF22408F83170F48694B40AFD9765995CF2240145C3E8747694B4005E7A49A95CF2240549C1D8247694B402F4B50169CCF224067F9FCF347694B408995FC229CCF2240F521DAF447694B4068E966DE9FCF22402FDF663648694B40972CE012A0CF2240C6B8013A48694B402D8A628CA8CF22405324E8DB47694B40E2A8A6A7A8CF2240C81BB9DA47694B40669FE05DADCF2240CD6866A647694B4084E7EFC5ADCF2240964FE3A147694B40F9520F1AAFCF224047F5C1CD47694B4052F53221AFCF2240D9E0ABCE47694B40D101994DB5CF22409CEB839A48694B403AEF447BB5CF2240490C67A048694B4012324753BECF224004E98C0D48694B407A6FC87DBECF22408F20CB0A48694B40F0501B7CCBCF2240F14D8E6648694B400B9FBCA3CBCF22401961A56748694B406C88BFD0F2CF224019BFBFEC47694B4039C29A16F8CF2240C7771D4E47694B401EE7E41CF8CF2240E7EB604D47694B406AAAC18AFFCF2240326A595647694B407090851100D02240A59CFB5647694B4096F73DDC00D02240CD9E5B2A47694B409182D9E000D0224034F5592947694B4003DAF4AA05D0224075637F1B46694B409C4D24B711D0224040622C6845694B40A8E3D5FE11D022409A3B016445694B405B4A4FD01ED02240EDEDF82B46694B40A4FE0E8A23D0224099F8A9E346694B401358279023D02240A50A96E446694B409DB1C9D733D02240855E635D49694B40A70D1FED33D022406282A06049694B401B8D30CE3ED02240304BAB1049694B40BBB3363B3FD02240862B8A0D49694B40700A82794BD022401B688C514A694B402BEB6ABE4BD0224090E2AA584A694B407EAE440251D02240E877E4CB49694B404AB7AA1551D02240C8F4DEC949694B4084AF9DF25FD02240F75506074A694B40A46FB86860D02240DF6AEC084A694B406489097166D02240C940D76D49694B40778984656CD022407E6A2EA848694B40CBEB79C56CD02240A5CCBC9B48694B405CD8373D6DD02240DC16858E48694B404F8184AB74D022409F968EBC47694B402748CD6378D02240915B8DF246694B403A26ED9D86D02240802C7DBA45694B40CE018B059BD022408357718243694B4047775F609FD0224033A9794A43694B408D1C8B89C5D022403B273FE73F694B4063F2858EF8D02240782B7FA23A694B4077C5A2E5F8D02240D96E7F993A694B405561BA3E13D1224055246B2E3F694B4095E426C219D1224092EB227346694B401CD3CE3524D122404EEEC8C84C694B405ABF1C6B3CD122401783665E52694B40C0420F6949D12240C30E96F257694B40A5938A6256D12240003AC2A05B694B40EB23988E7CD12240DBFF351962694B4022B36165B5D12240E4B6ADC764694B40D66954BFB5D12240E21EECCB64694B40F2019CD9F8D12240BA5419BC5E694B408973CD16F9D12240C71191B65E694B4027932F1606D2224031DCFA895D694B4012C81E0E11D222404914CE085E694B40B6DE1AD147D22240C87D018260694B401532502148D222406F16788960694B405BBB1A6652D22240C290395F62694B40017FAAA35AD22240B75832D863694B403570201D59D222402F65417564694B402D8ED6097DD222402A3C6D4C68694B40A23860657DD22240B7CDED4668694B401A0006947DD222404D494F4C68694B40B926D74582D22240199F200468694B40A61449A582D22240B78364FE67694B407F2CDDDF8BD222409DE9D03469694B40B20787FE8BD22240089ED63869694B408E7C21FA8ED222409A886E1B69694B40104D3F6F8FD22240DB27EC1669694B40756472F495D2224088A826736A694B40801537C796D222401D55F3A16B694B40721BD77F8ED222403390612E6C694B406FF60F318CD2224044143A136D694B40BC70D42887D22240E68E12BB6D694B40EAB79DE980D222401E0A708B6E694B402114FE5A7ED22240F7E8C7036F694B404177AF4B7CD2224063D0B8646F694B40B9D7928C7FD222403902962371694B4009B823187FD222401DDEF70074694B40EE1F208484D22240729C218374694B401F9556B984D22240B33E1F8874694B40773EB19E90D222405DDE05D173694B406A4D5BFD90D22240458155CB73694B408A0852379AD22240246CBEF974694B4085E1DF379AD22240E3224E0876694B40426F38649BD22240A29D5E5777694B40A6D24A8698D22240267F76B577694B404BF7967093D222403200595C78694B40F29B61C78FD22240D71FA31679694B40FD53D0E98DD2224015A68F7579694B40A58CF1E48DD2224009CD857679694B40F931F0B68DD22240A803AD7F79694B40DEB3337C8DD22240D984DB7579694B40AB44FF758DD22240F889D27479694B40A59035748DD222401CBB857479694B40D77BFAA287D222405AA78D7B78694B405FED764687D222406EA72F8978694B40EDD60D8C81D2224005BC5A6179694B40F585908581D22240B34E4F6279694B4028B73A247FD22240AAE020BC79694B40F4B5706E7BD22240E04A31457D694B40A7D0448E8BD22240934EA79A7D694B4093D91FD894D22240269AA48C7E694B40D5AB25EF94D22240A5AAFB8E7E694B40EEE70D93A9D22240A6CA1D1E7E694B40F897DA05AAD22240BAC3AA1B7E694B400B5245E6BCD2224083B092FD7F694B406822EC0BBDD222405C53530180694B40F9CB4235CED2224041640F587F694B40	Flensburg 1	\N	fl1
4	organization	102	0103000020E61000000100000093030000DF49692811D22240FB712B5B18664B409524593323D2224004E9498A17664B40A19181B723D2224053DA708A17664B4015C469D13DD22240FB8D189217664B408956B1DA3DD22240B4EDD49117664B40B521D6CE80D222407A34B8A815664B40E6EE4AE184D2224007E3ED9115664B40B827580CA4D2224070006FE314664B400B11C32CA4D22240EA454CE214664B4073094B62A5D22240987775D714664B405E281E0FA6D22240CEDB68D114664B40CAB4977BA9D22240C231B7B214664B40942D003FADD22240FC45FA9014664B4025153CF6B4D222405529D14B14664B4009262407B5D22240AAE7034414664B400E016D87B5D222409580D10814664B40013B4108B9D22240245EBD2D12664B40E60D43CEBAD2224036D7353D11664B40F14BEF74BFD22240F733AF6B0E664B4084DA505EC3D222407C83A2A80B664B401484F679C3D2224013C502950B664B401D2131FCC3D222408389619A0B664B4087E97E42C7D222409C1DE2BC0B664B401FDD1474C7D22240C10C1CB90B664B40CDDED72FCAD222407D2CB5830B664B409010991CCDD222400CA45C4B0B664B402F819C9DCED22240946EA22D0B664B40620B8D8FD1D222407B7874F40A664B40F88A3488E5D2224084BE4D7109664B4000EF14D3E5D222400187F77509664B405A9BBDEEF1D22240CADBFC360A664B40773F9A9207D322406387C6A20B664B40CD5EA16D17D32240A0D612150D664B40A2CE5F211CD32240EC70E4820D664B40EB41B40328D3224085F521910E664B4033B0F3E136D32240740EF5DA0F664B400ADC264037D32240B539EFD60F664B4093C321EF4CD32240E41E46EA0E664B4057431FAB73D32240FB074A430D664B403B1501B996D322409660034F0C664B4085427B069DD32240F51DCAFA0B664B40EA4E5640C3D3224027109FDD09664B408D6F0452D0D322403879B3FB08664B40372F085EFAD322404F990D2206664B402FD0EDEB0CD42240DCD2B2E004664B4021EEA4C318D422405EEA41F803664B40470AB55630D422400E15F46202664B404D36F8885AD422402C15BCB5FF654B40BB57489676D422409973C970FE654B405E83118681D422401ADA52A0FD654B40E018541695D4224094EA4B18FC654B4034D6803AA1D42240EBBAFC43FB654B40BDAD6424A7D42240704A43D3FA654B400AD5AC29E1D4224083BB6C68F7654B40AEF4A514FDD42240CCC74F48F5654B406620AF6AFED42240B733442EF5654B4046E8750C03D52240B21550F2F4654B40235FF12A03D52240A1AFFFF9F4654B40758A91DB04D5224020360465F5654B40666B923909D52240D599B135F6654B4044691B390BD52240828F2995F6654B40DD5E0D5617D52240EFDF39D8F8654B40F4485EF82FD52240B162E146FB654B4080FF59834BD522401944F557FC654B40D10C026962D5224019EFF104FD654B40E04102496AD52240697A7140FD654B4015128B4C6FD52240F953BEA1FD654B4092752C5B82D52240D15FAE40FF654B4084AF123987D52240391DA5AAFF654B404268ED639ED52240F8198AFFFE654B4068AF9B4A01D6224075748777F7654B4077FD725B01D62240105A2E7CF7654B400C1A245D01D622406E12B57CF7654B4071D3DB6701D6224057F3AE7FF7654B404B9801E907D62240B18C5C54F9654B4001363EEF07D6224087824156F9654B40F212891408D62240BCEB4E62F9654B404FF1F5770AD622408D4F5A26FA654B4014CE35400BD6224017089D66FA654B40FD0A32E70BD62240E59DDEB6FA654B4022BB44680CD62240B344E8F4FA654B4059D9BE6B0DD622409A639D71FB654B40ED86D6D70DD62240CBCE8BA5FB654B40E97B2ADB0DD62240638C0AA9FB654B4094EDF54B0FD62240E3CD32EEFC654B406CA4A0500FD6224055B9F402FD654B408042A3650FD62240885E3961FD654B40071886660FD6224080AD7562FD654B404130AC6D0FD6224075750882FD654B40872664970FD62240448D0C3BFE654B4048E1BAD310D62240813F0320FF654B40B6D8AC3411D62240BED52866FF654B40FCBF64AE13D62240B2BE188900664B406967FA8215D62240B5F27F2301664B409A120C8515D62240D4EB4F2401664B40A3B97F6516D6224087BA4A6E01664B40DB5B266A16D622403B98B26F01664B4007BF2AB516D62240026C598401664B40E6717F5517D622404AE389B001664B40B6ABD34A18D62240479F34F401664B40378E17191BD62240DC4E01A902664B40E0A6B4751CD6224004AC2CF402664B40795E9FF61FD62240817A8FB503664B4041D1E2F81FD622401BA206B603664B4024EA2F9C20D62240F9DA3DD903664B400B61302F23D6224088EB1E4904664B400318C10627D6224032E228F004664B40811434932AD62240CC2CA86A05664B40F362BFE52CD622407032E4BA05664B40FADB0CEA2CD62240810F72BB05664B401B9FDE432ED62240D94417EA05664B40E1B1803A36D622402514C5C306664B409B9DFDF156D62240369A685B09664B4002E90A5A58D62240ADFCEE7709664B4092C88A7461D6224013976B2F0A664B407BA45B6266D62240992F81890A664B408C67F2D767D62240B9DB15310A664B4017FD38366CD622402EFA322809664B40D19CDD5D6CD62240DE36CF1E09664B400615E5926FD6224087A0555C08664B402E4DEB9BD8D62240817DFE7AEF654B4089B50E0AD9D6224009D1E760EF654B406EE25E1AE6D6224003D3C0DCEB654B40E4AF3389EFD62240F8915F01E9654B402FE22ABEF5D622406D04A9EAE6654B408AB6ABB4F6D622404CB2B797E6654B409307EA2DF8D62240C089C518E6654B40DF01020500D7224096BA1C24E3654B4030DD660B07D72240C8D69424E0654B4092314E6D0BD72240C0C50426DE654B4084346BD10DD72240A8A63CEDDC654B40D50092420ED72240FE536AB3DC654B4052511D5E0FD722400E488C22DC654B400C32DCDC12D72240EB9BB41ADA654B405212A0E815D722406D0E050FD8654B40A51DA68018D722408E070100D6654B40201DA0EB18D72240F8CA8298D5654B40364339A41AD72240629235EED3654B40264ACC521CD72240D2E629DAD1654B4076B1FBE01CD7224015B7D0E7D0654B400BE98DF51CD722402EB1C9C4D0654B406A25081A1DD72240C202F79ED0654B406AC605311DD722401448745FD0654B400238FA8B1DD72240D10F69C4CF654B4064A6310720D72240E2AB0112CB654B40140CB11521D722405CAABC5CC6654B40E2A8F1B620D7224040A5EAA6C1654B40539E27EB1ED722407B2FD8F2BC654B40FB3B121A1DD72240BA55B57DB9654B4032FC5E151DD722408205D374B9654B40A9EEF9001DD722406CA7E42FB9654B40B6D30CE01CD722401F434D0FB9654B40ABF4C69E1CD722403C011D93B8654B404A5CF84D19D722402617E136B4654B40EB3E92F914D722405A8A66DFAF654B40FC9BF0A20FD722408B55EF8DAB654B4080CDD0830ED72240F162D8D7AA654B403B521B630ED72240123171B7AA654B406591DA7D18D72240DDF8BC76AA654B4078E38CFB22D72240FA028D33AA654B40AE14B12B6DD72240C1FEA10DA8654B400CA1629776D72240C5B4CCC7A7654B40BEA57E3A76D722409356208EA7654B401A09141574D72240E103F538A6654B400EDA47FD77D722403580ED19A6654B40F65F32DC96D72240B9E3AB13A5654B4042D4BC43C6D72240EEE926ACA3654B4090BBEB32C9D72240863D0694A3654B40068A6BEBC9D7224061DB188EA3654B40607C594DD3D722409C0AEF40A3654B406970100BDED7224022D19AE8A2654B40C59D896CE1D7224017DC4CEAA4654B40D6BF11DDE1D72240D2EE152DA5654B40DA3E1CA7E4D7224030CFE0D4A6654B4052F89B7404D822402BCFC8D9A5654B40C2F65B2F3AD82240E33598A9A9654B40EBEC05873ED8224045963C60AC654B40575AA40045D822402FF2262DAC654B40A4C8AE8D45D822402EC8CE28AC654B40AE5AF5596DD82240EC5DD5EEAA654B40BBB835C3A8D82240DB3F1A1AA9654B40EC4B606A57D922405BE216B8A3654B40140C665A58D922407EC0BFC1A2654B40A97D21D058D92240BB7DDC48A2654B40E70B040F51D92240925F2BFE9C654B40E0BA40BD54D92240D2123F499C654B4067AF725B7FD9224096DB7B069C654B4079A712ED85D9224031E896429B654B40E2C6240B9ED9224026B06DB89A654B4064C833C6A0D922406322937B9A654B4062EEE08AA4D9224047F384449A654B402ADB4B81A8D92240F60540259A654B40E7A86046F1D9224009C803CD98654B40D3F9A0CFF1D92240A67879CA98654B40B577F9DFFFD92240045EF28798654B40D2307046FCD922400CEFDC0B97654B404DF444BDE5D92240FDA654C08D654B4012289122D7D9224076AA44BA87654B40B58FFD6BD1D9224057F7249E85654B404ABA4F18A3D9224082BA5B8274654B4099588514A2D92240801E6C2274654B40F28FFE937DD9224006CB64A766654B4040C183CC78D922404F18C80B65654B40B7421F6962D92240DE7299905F654B40108F4C0B5BD92240ACF7ECBE5D654B40C2D078E059D92240727F20755D654B40469C5F8552D92240837B6D425B654B40B34D66F64ED92240D8A0BCED59654B40B2F0B09A55D922400CB2D5DC58654B40B14907BA5ED922402C0C036657654B4065A443D75ED9224029E4516157654B40E20F5A928CD922406CF3490A50654B40B8BCB886AED922404D591D974A654B401D464145C4D92240BD39FF9B47654B40904111B4CCD92240712E0B7446654B4038409A50D9D92240E7D871B944654B40C0712BC708DA224002E7040B3E654B40C6E1FD0D9BDA224019697B7329654B4030FBBFC3A2DA2240F470315628654B40A0A89F27A9DA22409407684527654B404443E078A9DA224059FDDC3727654B40B4C6F9E7A9DA22408759552527654B40FA407271B0DA224051C976E225654B404719AC57B6DA2240EEAC348F24654B4083E7CBE0C9DA22404181A9C71F654B40E3317543CEDA2240C43BFDB41E654B40121406DCE4DA22403EA871CC18654B40A97AE3EAE4DA2240B74390C818654B406D1FC403E5DA2240F7EF0EC218654B40600D740CEEDA224099C229C115654B40C370061BF6DA224075B28FB112654B40679F7E2DFADA224045B740E610654B40C174E96AFBDA224024EF645A10654B40591C112BFDDA22402B11F2940F654B40BC1C953803DB2240C0CF096D0C654B40F0863E6809DB2240CA3B579108654B40813D50E70FDB22405B841E8404654B405B68CF5C10DB22400A8FD23A04654B40247EB3C012DB224008CC33BD02654B40B921899F14DB224079A38E9201654B4030C43EBB14DB224069C3488101654B401D47A9C913DB2240553ABF3D01654B406BD6593715DB22404095DD3301654B4072344B7C15DB22409325E10801654B4052D5A6BE42DB22406AA147ACFF644B4088598CA765DB2240605F639FFE644B4000023822FFDB224074469BB5FA644B4028C5EC00FFDB2240157CEDDCFA644B40B633CA6F06DC2240DA6EEF85FA644B40632649B919DC2240AC1C0A08FA644B4071A4E7E127DC224066BA9DABF9644B406C3FCAF932DC224032AAEF45F9644B408914D99A34DC2240D0F3EA2DF9644B40D36789F935DC22409A50B819F9644B40A22B89973DDC22402E3F66A9F8644B409082B38847DC2240863AECD8F7644B407868072E4CDC2240FCBFB055F7644B404976E99D50DC2240FEE95CD8F6644B402BF3AADD56DC22409BA6BBEFF5644B407AF86DA957DC224092311BD2F5644B4097C5F4AB58DC2240ADF981ACF5644B40269424BE5EDC2240A2497F82F4644B405EBF9C8C5FDC22400FBCEA5AF4644B405D1C031F65DC2240E4A3DCE9F2644B409980EF2C65DC2240EB00BDE4F2644B40AED81C4865DC22405FFDB1DAF2644B40EDB87B4E65DC2240CD5758D8F2644B4053A1C84869DC2240570E3660F1644B40AA4E8ED971DC22402F3D8F70ED644B404F0C51E583DC2240AC019F25E5644B40FCD7F0C99EDC2240FE6CE0C9D8644B40123ED3E99EDC2240AD4D35BBD8644B406B4B3417B8DC2240337C3729CD644B4036BFB95FB8DC2240F21CE807CD644B409EA23E3CBCDC2240C8409B41CB644B408B696E2ABDDC224028C328D4CA644B403B7C01B6C0DC22402711C485C9644B40892D5AE8C0DC224039B33673C9644B40337D9362C1DC22401F14CA53C9644B40324A77F9C2DC2240C3F8EFDDC8644B4097A71063C2DC2240424A0DC0C8644B40A9C11B1CC1DC2240D584127FC8644B40533E29E8B7DC2240A945D7AAC6644B405B4A393093DC2240A59EA95EBF644B408FDF3A157DDC22404240F7F9BA644B40AF3E6CA574DC22400C9A6713B9644B4000E35DDF68DC224090BB84C3B4644B402AAAFF5C67DC22402AE24288B3644B40BAF2F2EA66DC2240EAB83A2BB3644B40E11B21F366DC2240D8243690B2644B40C75EC1FB66DC2240123443EDB1644B40DE5A483767DC2240FC8BA985AD644B404B326A4B5ADC22403D3A5693A7644B40131C887C27DC2240A735092EA4644B4086F149C91FDC22401E634BAAA3644B405AB2C3691BDC2240262C785FA3644B4018EB7A711CDC2240E16020F7A2644B406BFB3E8D1FDC2240D79F4CBCA1644B40EB737C714DDC22405CE53F948F644B403DF302A54ADC22404E1967728F644B405A0F81E23CDC2240967E02CC8E644B40FF4FA2D224DC22402DE009A98D644B40A06BB684D1DB22403DDAA0B989644B40F3CFCC44C7DB2240A409AD3D89644B40992C8BDAB3DB2240C10EE25288644B40E7E8B129ADDB22407919F80188644B408060D4E4A0DB2240322C986D87644B40622883BAA1DB2240261B21F685644B40A25B15BB9EDB22409513417A84644B40FED665329DDB2240774F90D283644B40EC484ACF99DB2240FA4D534083644B40C6E634B190DB2240F7444D8282644B40950782A881DB2240194C6CDD81644B403D3E9E8672DB22406205773781644B4003AC78D9E0DA224064CB822D7A644B402A52E5FFBADA224074A7D25978644B409C6FF3020EDA2240B94FC30870644B405A4B74CE0DDA2240BA53C11370644B407578D8EE0CDA2240EB54010970644B40D40BBB1E01DA224002C76B8272644B40E12D8433EDD92240B5FB240C76644B40B705067FDAD92240ED885C7576644B4032DB0A8DB3D92240227CCE1878644B40F840269293D922404C7F6F1E7B644B40786291878CD922409F5EC7AD7B644B40AFFF3D7388D9224044B9D3007C644B407EBA3E3D70D92240F207B4ED7D644B40961BDE685DD92240EFF57D177F644B40534F2AD15CD922404110DC207F644B40A8BD756059D92240C48944577F644B40952BC9A558D92240D58FCE627F644B40C7A843FF55D92240E10909847F644B402F38B50255D922405239AD9D7F644B40B0AFD25D4FD92240E4F06D3080644B4053B210474DD92240AA1B9FFE7F644B4092044C844BD922409559B41480644B405267923B4BD922408D41340C80644B408BEB81F840D922402D5C2CD97E644B401EF877FC1DD92240BA0879C27A644B4052E1AF7F18D92240E4264B1E7A644B40FD04AE7318D92240D403E31C7A644B4078EFF3570AD922402095CA7678644B40FE60F6BB83D82240728E88BB68644B4013F4591341D822402976478E60644B40BF90584740D82240B13B417560644B4030AD8E3540D822400EE8D37260644B4093F0D3D60FD822400D3030DA59644B40049679FD07D822402E6F2BC858644B4029B7B0A407D82240F8880EBC58644B401A1D561B05D82240C09F816358644B40A552ADCAF6D722408F5BBF6F56644B406214813DDFD72240C916863953644B4016E93755D6D72240ED57C31F52644B40EE9ECA21D0D72240F01AF86A51644B40911DD5BACFD722401FD53E5F51644B40C046D920CDD722400381651351644B40E76A4C84C9D72240CE737FB250644B401FAA10A4C3D7224046C0D91450644B40E29BD9E2B9D7224027448B244F644B403B122FE1AFD72240F0B8D7424E644B4050904E01A8D72240452FD6A04D644B4072150CA3A5D7224008B91E704D644B40C1528FFCA3D7224058A04A514D644B40F6B228A29ED7224022C54DED4C644B4073AEC82C9BD722400436B4AC4C644B40CDBD948290D72240753CEAF84B644B408D942B168BD72240BBFAC3B24B644B404806FED7ECD62240A3BD06B443644B40D8CC794ED8D622405D411A9D42644B407B751EF2C3D622404F75067541644B40A0A789C5AFD622406D4FF33B40644B409C8C66CB9BD62240EC9E0CF23E644B40A6FF4A1281D622400ACB6B243D644B40E3C5E6FE66D6224028EBA5263B644B403A1774A14DD62240CBC2F9F938644B403359C30935D62240EF32C19F36644B407F89A23620D622409D214AC034644B40E3CF932714D62240F555758E33644B407A19CAF512D622400901277033644B408116A1FB0BD62240818032BF32644B40D236F662F8D522400FC6789D30644B4088056F76E5D522402DCD2E5C2E644B4091BE148CD2D52240778E8BD92B644B400C420915A4D52240AAC4E7AE25644B401ADDB9D99AD5224095F9427524644B40C7AC204D98D522409624A51E24644B40CE73DF6F8BD522407CD4936922644B4065ED82BA86D5224035FB9BC921644B407829D5AB67D52240420569AA1D644B4097BFFA1E54D5224027E830121B644B40682E8DE150D52240415A1BA41A644B40B9F260564FD522405BFDA86F1A644B40F598684A1ED52240DD7CCBEF13644B40401AB5AE13D522402B5E6F7812644B40E4C26E6409D52240E89623F510644B400CAF1A6EFFD42240F9084A660F644B409207DF64FBD42240D6A559BA0E644B40F68830CEF5D422401EAB42CC0D644B4088ED0E54EDD422403EA44C4A0C644B4013D71270EBD42240ACEB3AF40B644B40C4CE7884E1D422401EAB390F0A644B40AB25851C9ED42240EB7E5923FC634B4039AED5179ED42240FA1F5222FC634B405AF0EC7491D422400FE32E56F9634B40D530E1288AD42240D1119B86F7634B406295D59787D42240D91A90E3F6634B40D12F1B887ED42240D6C19460F4634B40FF919F2F7BD4224022639F80F3634B40CC80866E79D42240BC1D310BF3634B4063DAA1B574D422403ADB73AEF1634B40C2E5535F70D42240654FED4AF0634B40182C766D6CD422404F9C33E1EE634B401A2E838169D42240189383B2ED634B40FB23BAE168D42240ADECDC71ED634B40237D0A2F66D4224037F81032EC634B405AB88EBD65D42240E24385FDEB634B40DD77550263D422400FA8C884EA634B4051E21FB160D42240D91E4508E9634B40C4682BED5BD422406E2EE9D0E5634B408799B3E557D422402B593094E2634B405960E7EC55D42240189286A0E0634B408153E79B54D42240C6070053DF634B40F8C40EDC53D4224019E58E5CDE634B400E0B981052D4224009A53F0EDC634B40880D490451D422402D93B014DC634B400E99B60B4ED42240E21EF526DC634B40D98D235A3AD4224016D909A0DC634B4026D3B14A03D42240AC768EF2DD634B401B144C83EED3224044167194DE634B4098A7710ADAD32240D3472265DF634B40189C7CFCD8D322405B068172DF634B406650FAF3C5D3224043E2D863E0634B40F2872415B8D32240EBF0AF37E1634B404C803653B2D3224044789F8FE1634B40BC3C9462A6D322406433697AE2634B40B427C0B69AD32240DB730777E3634B408C38C5548FD32240A20F0D85E4634B40E23C5C328CD32240F62045D6E4634B4003C2784184D322405B1E07A4E5634B40F5B8878179D322406A087BD3E6634B40B57E91196FD32240156FE812E8634B40E2A7FF0D65D322403259C561E9634B404A01C7885CD32240AE700796EA634B40BAB27D3F58D322407F22563EEB634B40F2DA163C58D322402454133EEB634B40FD4A9A8F57D32240179E0531EB634B406C8BF93855D32240C930B003EB634B40154B2DD71BD322404D9968ABE6634B40C6D001A2D8D222402FDEA494E1634B406B2D64B241D222403610C326D6634B40C0E1D7903CD22240C2C34AC3D5634B40921BDB4E08D2224026313FCED1634B4065EC6CBDE3D122407EF65609CF634B40BBAA50F7A5D122407C6DC55BCA634B400257ABFD9CD122401B2952A8C9634B406E7A533C96D12240680C3F21C9634B4049C4F9F5E8D022404A959698BB634B40FEBE3190D1D02240448A7B29BA634B407B4F4755D1D022401DBE7626BA634B401FAC927EA8D02240799F800FB8634B4074A35720A0D022407A00E3A1B7634B402FE1C9EF9FD022403D65AC9FB7634B403D7DD6D99FD022407F81AE9EB7634B409012711195D0224092DAFF20B7634B409EA6B5808AD02240C502DDA5B6634B4023BDD9DD6ED0224070B9C063B5634B407BF9E1C969D0224002419228B5634B4046A7978962D022406043E7C3B4634B40887AC61D58D02240D9DA3B33B4634B40CA061B1FC5CF2240C0FA0DE3AC634B402FBDC751A0CF2240DC699210AB634B40B37BD03191CF2240054E944EAA634B4046A452D08ECF224026B05230AA634B40E26D386A26CF2240B81E7A01A5634B406828AE9B14CF2240F7FA4616A4634B40E98F55D00ACF22401024E894A3634B40E4949EB906CF2240F48AA26AA3634B405FD4C20105CF224061EEDE58A3634B40CC10546FF9CE2240E2EA3DE1A2634B40371C6DBDF4CE224009C6B4B0A2634B40CAE924CEE8CE22403C095135A2634B40D0EDAFABE0CE22400AFACD01A2634B40D1188916D4CE2240AE3120B2A1634B404FD10279C5CE22402D248F80A1634B40A5C12CD49FCE2240ECDFE200A1634B4003E3C47494CE22400ABA4FDAA0634B402D2A7AB32FCE22405C4E30F39E634B40A4964A142DCE22409CA6CCE89E634B40E916AEAB12CE2240378F23809E634B40903F8AA912CE22404D4B1C809E634B40B5ABB1430ECE2240280DAE6E9E634B402A737EC40CCE224014A476639E634B404D974C7701CE22409AABC00E9E634B406156B754EFCD2240CB58D5869D634B404EED062AECCD2240044D186F9D634B408721DFCFDBCD22401F1288F49C634B408354628CB2CD2240FE18EB219C634B40DC2AE5ECA5CD2240F4C9D0099C634B40D10D42A39ACD2240128D43F49B634B40CD8FB6C092CD2240668D36E59B634B40ECA3153A88CD2240C8CC1CD19B634B40ECD2986D75CD224071A71A849B634B40D22CED6B75CD2240BF4913849B634B4089AAD3736CCD2240818F545F9B634B40AF8E53C568CD2240104997469B634B40444D1B8E52CD2240BD1354B19A634B407D14EA844ECD2240DA2408909A634B4003F5C19948CD2240F73B345F9A634B403B50636339CD224059A7B0E199634B40AD07EC4636CD2240BDCF05C899634B40D9049D61FACC22406BC3100098634B406A061D34D9CC224065BBAC3597634B400E1A8069CFCC22407FCCDB0E97634B405134EE12CDCC2240D6DD960597634B4005B4F7D6B9CC22405C3B58B996634B40EA51E36EB5CC2240D13FDFA796634B40F7A2970CA7CC22403818DA6E96634B406EDAB6FDA2CC224053C4796A96634B40B3E6734BA1CC224009A5A56896634B400A078E8A84CC22402FDF9D4996634B40A0B3FCD981CC22403D31B74696634B40F73CA16245CC224037BE6A0E95634B40D4FEDA7B24CC2240E939476A94634B40DB32BE58F5CB2240F1F30B8093634B40F3DF8944F5CB2240B30DA67F93634B404A034945F5CB2240C460BC7E93634B401171D2E2F4CB22405EB6CF7C93634B40D5330987EDCB2240686B0B4F93634B40AB074FEDECCB2240BE9A4F4B93634B406162CD3FEACB2240BBA4A93A93634B40ABF44C58E6CB22402281B12493634B4014FDD0919CCB2240612955F091634B408DDDBB0076CB2240664D082791634B40D442D9E655CB2240FBEE655290634B401FD9A82836CB2240D28532458F634B40B61A9CDB34CB22407D63293A8F634B405903C0CC2CCB2240883FD4F58E634B40475FDF35EDCA2240EF1FF5F08C634B406208A1E5D8CA224002393D888C634B40E91702DED8CA2240D3EF1F888C634B402BF0B87DC4CA2240C329013C8C634B4003F59620A6CA2240D17ABEB68B634B4098E54AEF78CA22402E4477EC8A634B4032AC35EF61CA2240E61083858A634B40E338B12055CA224070E9734C8A634B40DE8D9BCA4BCA224064F1DA228A634B40E15EBD9E4BCA22408ECAA1218A634B404A62D694F6C9224018AE2CA788634B40AF1F0D8EF6C92240AB360FA788634B402BC17F89F6C922403B9E11AC88634B4053DEFE83F6C9224010B01AB288634B4040D42726F1C92240C34F33948E634B405CCAE459F0C92240D034DA908F634B40CD51FAA8DFC92240B6AB642AA2634B40D5C4708FCCC92240DD396918B8634B405704A67BC2C922403DFE9833C3634B405A25482FC1C922407EA15F4CC5634B4010BB6C3DC0C9224000300229CD634B40C5A9256BC0C9224066A877EDCD634B4029B4C4EBC1C92240BF0A7834D0634B407EBF7EDCC7C9224071E501AFD4634B4023E47FB2CAC92240B791C016D6634B4061602A72CCC922401001D1D7D6634B40B9F39F2BCEC9224043783996D7634B407A1EE20CD2C92240DFD75310D9634B40FA91A013D4C92240E4377AC0D9634B4034F3D754D6C9224018857784DA634B40DE27A801DBC92240A76A0CF2DB634B40E33E8711E0C922408E048658DD634B405AB0BBBEDFC92240833DDC5DDD634B40B8A9F0E4D7C92240EA81E7DEDD634B40A1BE82C6D6C9224014354CF1DD634B40AA82FD6AD1C92240AAD45E49DE634B408BE510D5CCC9224006D8C094DE634B401CF9211AC1C92240C1AB9855DF634B4049BAC4B8BDC922407BBB7D85DF634B40DB2707E6B7C9224034A2FFD7DF634B403204D297B4C92240E76CD406E0634B40B89027BEB1C922405D5EB422E0634B40E4D512EEAEC9224032AD353EE0634B4045CDC4F0A8C92240EC4DC578E0634B40FC0CD5A4A7C92240F0E27285E0634B4045FB58B99AC92240398430CEE0634B4065C609EA99C92240EF7DF5D3E0634B40FECF570499C922401FD5E4D2E0634B400BB520C898C92240375A9ED2E0634B40ACC1EEE48DC92240FCB632E4E0634B4064EB02068DC922408E939BE5E0634B40585572A87FC9224042360BC6E0634B402307B5567CC92240754BD3B0E0634B404BE3DA7572C922406C7BAA71E0634B40891D179565C92240781470E9DF634B40494A75835EC9224003E5347FDF634B400F0AEF2B59C922403852ED2EDF634B4006957C0C0FC92240BABEC829DA634B40A24622A8FEC82240EA00920DD9634B403329A99EEEC82240F36F14E9D7634B40D3C90E94EEC822405FB7C1E8D7634B4084DF4B95EEC822402EAF68E8D7634B4016F97280EDC822408E76AFD4D7634B40FF61ED5BEDC82240A3C463DFD7634B4045E3BA4BEDC82240ED0725E4D7634B40A50E05A3EAC82240121EA4ABD8634B40BCD7BB95E8C8224003489945D9634B40AFC3830EE8C82240F77E3572D9634B40F304140CE7C822407B4F74C7D9634B40CA93D8ECE5C82240410B3126DA634B4038AAD8D2E3C82240CD27BE0EDB634B40F3F0547ADEC8224068AE13C5DD634B4041BAF6D3C8C8224017C813C1E8634B40FFA3FBBFB4C82240E1A3DC2AF3634B4081E59795ACC82240DDA8A00AF8634B405105A738A9C822401F3DBA14FB634B4007379D40A4C82240D9D34D92FF634B40BC3230529AC82240BEBEF18F07644B4020AE896493C82240F24AF3580C644B40EADD8C928AC822403432767012644B40394CFC8975C822403674DF0B20644B40C586841A72C82240D17E29CF21644B40E72D93D26CC82240CB0A13D223644B401DD83FC06BC8224003CEE92D24644B40F16E52B567C82240455C6B8825644B407B3A4AEC66C822406AA8B6CB25644B403BE7D98961C82240BBA0AD6527644B4011E4C06A60C82240131611BB27644B406412DB9A59C822402A518B8B29644B40D31AF39E58C82240C1E39D7929644B40A010D97453C8224067A3831B29644B40ABBE866652C822408857460829644B401F8482F751C82240BE8D5F0029644B4087CD150852C82240667DE9FB28644B40FFFEF26651C82240D38C72F028644B400A0F938CB3C62240109B667B0B644B404D32E1007EC622400DBCA3AB07644B40B4B5C0B763C62240E72EA3CC05644B40464249B75DC622400FA2415F05644B40ECF5AA6C5CC62240790E5C4D05644B4090D3042A59C6224033DD2E2005644B4003FC4CF858C62240E1657E1D05644B401752798858C622404E60701705644B40B28DCD8E58C622405776221505644B40E6ED02F357C6224028990A0A05644B40076169A857C62240E5BFBB0405644B4065C8DF7A57C62240DB9E93F404644B405017C36D54C622409F8196DF03644B4019A80B3154C62240B3AA0BCA03644B40F55CC0DE53C622402950E0AC03644B40071EEED253C62240893A14AC03644B40D5346D3653C622409524B1D603644B40AA94D8BE52C62240C2A24CAC03644B406E7F74324CC622408235334F03644B40A02AF46845C62240CB8E8BFC02644B4039E666932EC622406C4C76E601644B40451E1E1CD3C522406B7966B3FC634B40F717F8B7B3C52240A5F12EE5FA634B40B4E4D66698C522405B8EF452F9634B4047D36BA078C522400EBD2C8FF7634B40DF5882C7CAC42240367E5A97ED634B40BBC4142CB3C4224056177344EC634B400B2D396599C42240925065D2EA634B40CBE64F4022C42240123227C8E3634B40F2CB6C8721C4224043623DBDE3634B40441EC36521C42240141A52C9E3634B40FC8A96151BC42240FD570D0CE6634B4080A304D61AC42240B9EAD222E6634B40189F3FCB1AC4224046B33A22E6634B40B2CBDD961AC42240400F641FE6634B404D9F30DA17C422400BFB8D18E7634B40A8A4808EA6C32240B0CDF4610F644B40E95C0ADCA6C322404C46916310644B4095C9FACD9EC32240A959937213644B400DD87E856FC322405E4A0E6C25644B4033F3498268C3224037DA351328644B40C2468D5368C322409BE6412828644B40596DDAE266C32240E0AE67B428644B40ADAC345C33C3224039BCB7883F644B405306FC8733C3224026C4008D3F644B40F7141F8C33C322402926688D3F644B405BF3018633C322404FF7ED8F3F644B40E7BF3C8233C32240B328908F3F644B4017077CA032C32240407B7C793F644B40B993506732C32240FE14CB923F644B40274D916132C3224089795A953F644B400B13DD3B32C32240419DAA913F644B40F5E6E9D522C32240962A32103E644B404F503A5614C3224040353CA53C644B40B9D5A2AA11C32240C62D62623C644B400B1AB217F3C2224059B1452639644B40F0792B95F2C2224072A5E33539644B402FAA9903F2C22240E8237D2639644B405A71D2CDEFC222406C899FEA38644B407F035D82EFC2224055AEEEF338644B401C26DEBDAEC22240D9BC32F040644B40AEEF65709CC2224020F48D7E43644B40C065CA8B9BC22240632B76A043644B40604B56869BC22240102A1FA143644B40A0DA52289BC22240AB205EAC43644B4085A0E6FC8AC22240CFA576EE45644B4028776DA47EC22240BFA601EA47644B40E8269E977EC22240C42611EC47644B4022CA745171C22240B4402DE449644B404D7B5D8370C22240D9C2BF024A644B402433388672C22240FD6755614A644B402331C74172C22240AC2A626B4A644B40E52E416567C22240507D9B034C644B408E6F871367C222405AF6980F4C644B40902BEECE66C222402CE4A1194C644B406D86D48A3FC2224005A8BDD751644B4081F5219815C22240F24B890F56644B405C12682E15C22240615E2A1A56644B4021A6F2BEC7C12240B3199D755E644B400C0D2FA384C122401EC5B0B365644B40502BC03D69C122400607434868644B40A434F8B168C12240C861FC5868644B409510854965C122400BBA63C168644B405443DDF364C12240DB16A4CB68644B40CA81B11B47C122407E7D379D6B644B408213925D3FC12240D9BC6B586C644B401B99E8743DC122409D9BE2896C644B407959F73CFCC022404614E82373644B40A4DB55EDE0C02240CE0FBF4976644B40E165E3FDBAC0224083200EA97A644B40860C041890C0224020FCF9F37F644B40B00433267EC02240E9EB3CF481644B40388BE43960C02240E2ED6D4A85644B4098266B2262C022404EA8EEA285644B4095AA4F0853C02240A9196E2B89644B40368942B852C02240A1EAF53489644B400755B4A352C02240860D949E89644B402D21D19052C022400CCAB4FF89644B40FB52B57B5BC02240179CC1EA8C644B40514F6FC35BC02240B9B038028D644B40DC147C9E5BC022405FC2E19C8E644B405E33CAE667C02240E8B7DCCF91644B40D261A79673C022403C8C1C3E93644B40A2B3495A79C022402F2F3CB093644B40D3098A6C8DC02240E64F734394644B4003B5B4F891C02240D6DBCD6494644B40101D5E96A4C022401139D34D95644B4058F9FA1EB3C0224029FAB08C96644B40266466CABAC0224077C6ECA198644B40DD1D9C47C3C022404E8223F09A644B40C6108B12CBC02240913002559D644B406618C001CFC0224014BE6D8A9E644B40BFCDCD37D8C022405E1666D8A1644B40A28871D1D8C0224026C2CCECA1644B4069900662E4C022400555F775A3644B40FB9969FAE4C0224007CB8580A3644B40D2A4044903C122402E97D199A5644B408EA1155019C12240D02E5620A7644B40A7D3DA3F22C12240A2B82E08A8644B406E4F349F29C1224070705892A9644B40739AD3712CC122403A41070BAA644B40188289063AC122407A51A54FAC644B400B76FAE346C122406EE57E42AF644B40B9556D8E4BC1224070FFE866B1644B403FFC6AD84BC122407A8995DCB1644B405DE1573D4FC122406C3C8642B7644B4038FAD6AB5DC122403058EB38BB644B408CBD3EF45DC122401148FDD7BB644B40E7A681725FC122401036D11FBF644B40504BBDBD61C12240081BA5F7BF644B40037540EF72C12240315DF202C2644B4052DAB5D477C122400BC97677C5644B4006FDFE6B79C12240923FF996C6644B40F71BCC277DC122404753203AC8644B408C5E9ADE7EC12240D65E8EFAC8644B404A92318286C12240C7B4870BCB644B4063CC184F8EC122406FA9E9A0CC644B40D8FECB3EA2C122404B920890CF644B40CE7428F2A5C122407941761BD0644B40ECE37D62A6C122409A59FD2BD0644B4044F8B878AFC122407AF11EA4D1644B40CA509C68B9C12240151D743FD3644B401F78C66EBEC12240B467320FD4644B408D450022D9C12240E808E283D7644B40BD1FBCD9DBC122400E4E67C0D7644B40D4F113F0DAC12240587FB11CD8644B40FC4A7C57D9C1224044A30DBED8644B4025570B24D3C12240A2AFBE2DDB644B40311E2924C4C1224021AC6812E1644B408A4FD80DC3C12240B678C17FE1644B40C0EFCB4DCFC122403480941CE2644B40B68DA63BD7C12240139F1682E2644B405AED29A2DFC122402397A1EDE2644B40A8DDC57DD5C122402B1471EBE7644B4011FCCA02C9C12240DEADE00FEE644B40BB3FF1D2BDC12240E42D5391F3644B40DF29AEEFBAC12240111EF0D0F4644B40B5BD4D02ADC12240079C8AD6FA644B40714D4F069FC12240AF7A6DE200654B4080EAE7D7C8C12240CD57A29C01654B40267F7368D2C122408BBC39C701654B405DA0AB7009C2224024F4AC4503654B4096E867D34EC222408925FC8205654B406CA1AAA960C22240405D833306654B4028AFB5E665C22240B2223FAD06654B402C25D8826FC22240C61A8E8C07654B40F92210C670C22240AC28E6A907654B40E8974716BDC22240264C37F009654B4041DC3007BFC22240233A08FF09654B40E31ED6CAEFC2224015FF45B40B654B40B83D4ED8F4C22240C99093E10B654B405BFB3C9A0FC32240C0B47ED10C654B40C9DFD7982CC3224048A1AB550D654B407287E01433C32240C0E13A730D654B40085432DD36C322401C22A0C10D654B403C4623343FC32240FA38826C0E654B40C79D2D094AC322408E2D6A4C0F654B40D71509F001C42240D08B8FF618654B401722E6A59EC4224020294F4F22654B406964739058C52240B7E655E32D654B40346198A6C3C52240D14758E734654B409B74240859C622405A8B51543F654B40D3B8DA1B11C722404C59D42E4D654B402D0EBE92B9C7224033C0F1BF5A654B409794B1A5BEC72240A8238C285B654B4014CF247A8CC8224039D7E5806B654B40E6BA6B59A8C82240D047DDDE6D654B4039556257E1C822404936E5B572654B4069DEBE58E1C8224009CF03B672654B40AEC36655FEC82240B154322C75654B404B48BD132DC9224059F8A40079654B40F9A207CC6CC922405F2B26397E654B404D05BE678BC92240743A25BB80654B40DB13B7B990C92240A4A0BA2A81654B40CE87D79593C922405FB8BE5D81654B4008D95E84C2C922408DD7E9A284654B402AB2DF6BD0C9224047E5EE9A85654B406073D675D4C92240733BFAE285654B408DDC184AD5C922402D6F31FE85654B4039E7F9ADDEC92240B0426F3287654B409ED9B593DFC92240846260BB87654B40FADF92D0DFC922402842351488654B40F73C5686F4C9224025DBE51F88654B407B10D20C03CA2240B8EB172888654B40A6006EE02BCA2240BA13E2AC89654B4060C8DC9932CA2240D61DEBEC89654B40C72D916B44CA22408CA5BF308A654B40811F485E43CA224023CDF3C78A654B409A9EEEF741CA22400D2C2A918B654B4059C0374B41CA2240969627F28B654B401DEF80463FCA22404C1B4F148D654B4048C70BEEB1CA22403B1718A095654B40ABE7F50D5ACB224098531F34A1654B409EDD90E180CB2240F882B618A4654B407F478D608ECB22409E3D221AA5654B4087DF8A6A0BCC2240A5C9CD8EAE654B4006F494E90BCC2240C3CC6898AE654B40B54FC2290ECC2240A11BF1C1AE654B4063C7A1973BCC2240470B5308B2654B4006BE25E250CC224041B39C79B3654B40EE0C17DC76CC2240FA0E45D3B5654B407CDCD7AF79CC224024799401B6654B40464FD5968BCC22401029D526B7654B409376D6A88CCC224000475E38B7654B403E844A7BCDCC2240D8572F5EBB654B4039C437320ECD22401D69F6ECBE654B407B254C3018CD224006CF9679BF654B4030ECFD58B3CD2240B725F4A0C8654B40491E47E3D2CD2240BDCCA788CA654B401F6F6D98D9CD22408AAE8BA6CC654B4038B74572FFCD22401328B266CF654B403CD4F4BDA0CE2240FB712FAADC654B4000719680B5CE2240E963335FDE654B40DDC883E9B8CE22404B50FBA6DE654B406FDDACFFBCCE2240AF583E90DD654B402DCB0B05BDCE22409973D08EDD654B40F6307A25BDCE224060992D86DD654B407D5D9B75CECE2240B8E54424DF654B40A5233046DFCE22409DDF70B6E0654B40D2C841230BCF224054FC8CCFE4654B403948FC5480CF224023E679C2EF654B402CB2E2CFDCCF2240016072B1F7654B40B2B24D8061D022405212571303664B407977A55360D02240E9D4B4A203664B40568ECD5160D02240930697A303664B403BA061A858D022401C59E04A07664B40F332815353D022407D9BA4D509664B40CD38A6B455D022405F8476190A664B404D83A2B0A8D022406387A95613664B406026430FA8D022409C8BA87413664B40A4B62E1CA4D02240B072903014664B40028118EE9FD02240797071F714664B404D9601E695D022403241B7D416664B40DACFAE849CD022406484009317664B401E3C74EBF7D02240934253D621664B40B0F83A19FCD022403CB5956122664B40DD632EED07D12240BFF2C0EB23664B405B63A4D42AD122408B7DF27628664B4009A099EC2AD1224049CB907928664B40721F8CCC2CD1224028810FAE28664B40CE25E07348D1224047154DB42B664B40100D933672D122409499AE3A30664B40E5A2D6FC72D12240CE802A5030664B407CA597307BD12240E97BAD3331664B40C7F365478AD122407B1D65B130664B40F1E2537496D12240126C454830664B40D57DF0EB96D12240E95D004430664B40F40431D498D12240A068DBDD2E664B4067A53F2F99D1224094CAC3DA2E664B40AB9E884299D1224028961BDA2E664B403E04F8239BD12240CF5217582D664B404361880C9DD12240563B66D02B664B40A15C3E5B9DD122404038E2862B664B409E64D21B9ED12240F67709D32A664B40E601D872A2D122409C75B44527664B4087B9E697AED122407E7E2D1D1A664B403F651331B3D122409C8435171A664B40F7457831B3D122409ED4A0161A664B40FF7CE3F0B6D12240F650C3111A664B40B4233575E8D122409ACE85D119664B40F0B3F223EDD122400AFF9DB419664B4055D1EF99F9D12240F22C896619664B40DF49692811D22240FB712B5B18664B40	Flensburg 4	\N	fl4
7	organization	102	0103000020E610000001000000FC030000BDA9253108F12240000FB6DBCB644B40A22385850CF12240D0CB2FA5CB644B406780FF40ADF12240897B13A1CE644B40E93AF8E3AEF12240043AE5B7CE644B40B6BFDAA6B6F122401F951824CF644B40FA0553E4D5F12240864ACFBDCF644B403D713E733CF22240CFF96BB6D1644B404602FCB45FF22240FECF6956D2644B40249B2C6925F322409839BF0BD6644B40D706ADAF29F32240FE444620D6644B405B426E7933F3224016D8444FD6644B40E9CE5EC93AF3224064686072D6644B402FA0E9FB3AF32240CF0F8332D6644B40FEFA7B043BF32240847EAF27D6644B403EB6910E3EF32240CE5F7E34D6644B40B463E54B3FF32240D43BE596D5644B404C7B466043F3224023074290D3644B40DC213C6B46F322405A84660DD2644B4072F42BE44BF322409E5B9C2CD3644B4086BEC10562F32240363F70AFD3644B40E185BB4562F32240F731345DD3644B4086DABCF39DF322401FFBE2DBD3644B4072750780B9F322408F1AC0E4D3644B4004C128A4C1F3224089E404B4D3644B4012A2F645E2F322407299DBF1D3644B40AA5F8FCA0BF42240A0274E40D4644B409F2DBD1B34F42240FD281898D4644B4003E2C9285EF422404FABFAF6D4644B40B010A2B28AF42240C775FC64D5644B4072F15691B4F4224079BFB7D0D5644B40F79053F4DBF422404580DA43D6644B40F47C82BF03F52240B1446BBED6644B40D157F24831F52240D3EFE129D7644B40C13445B33AF522406B7D9038D7644B40A933A1296FF52240458E5E8AD7644B40231A9BDF7FF522401A496DA4D7644B409A05972A7FF52240E55AFE77D3644B40E0518A147FF52240B7CDFBFCD2644B4072EEF9A87EF5224090A8DF85D0644B4042200B2575F52240E78393ECCD644B40CAE024746EF522400BE6849CCB644B4053F633C35AF52240744F19BFC0644B408838553450F52240F51CB7EBBA644B40BADACD5D4FF52240E77E6C77BA644B40D2DBF2354FF52240FBC8585FBA644B40D41B8FA245F52240CF61FD95B4644B40C6F271393BF52240CFBFCEB3AD644B40F7822F4551F5224083260FF6AC644B40E913D4285BF522402C73F1A0AC644B408A3B229D99F5224099064F7DAB644B40DDA30725CEF522401DDED0C1AA644B40B54450A7ECF52240406BE954AA644B408FB560C103F62240002B7302AA644B40845B500F07F6224040F1A7F5A9644B402D15EC7956F6224069D042C2A8644B4012D1B36563F622404F671297A8644B400346EFDE7FF622405290E537A8644B40359615278FF6224019E1D004A8644B40B4035B68A1F62240EAF4CBC7A7644B402454DD2EC8F62240E982FC20A7644B403129B0D1D9F62240F45A1CD5A6644B40D53E40EE03F7224035F39067A6644B40B09F9E8414F72240F78D0012A6644B40155359B224F7224012D11D19A6644B40FA0504E64AF72240AEA5DB46A5644B406086C0F56AF72240D9851228A5644B40B1EB970D94F72240FC909BBEA4644B4042D48B94FCF72240A916A053A3644B40C39226880AF8224097CEF73DA3644B408C0F2AC02EF82240E0282427A3644B408B543D0743F82240F7AB13D8A2644B4048D4ADF160F8224023140691A2644B40F26BCB52A5F822408D12EF4CA2644B40161DB2C5ABF82240FA5D4023A2644B40D907130EBBF8224021766CC0A1644B401EF25482ECF82240C2E10185A1644B4078CEFC4AFFF82240B3E4A516A1644B406A83BAA627F92240B2443A9EA0644B40701EC6113CF92240E8C296BBA0644B40712F0DB46EF9224079E0B026A0644B40010EACD772F9224072E9831AA0644B4033A8583278F9224076FA62819A644B408AC1F34979F92240DC8695C997644B400244D9907BF922400865E06F96644B406F1AEDD97DF92240F7703E4192644B400E2403DA81F92240EB077B2C8E644B40873F42F886F922402F89EB068A644B40376CED378AF92240B32510DE85644B4097164C768AF92240A9482C8E85644B4022CD69D1B9F92240FB8DB39886644B40D833516BE0F9224084C2373688644B40735B0905F6F9224079167D9089644B40A2763B1B02FA224076FC5A8B8A644B40867C32FE04FA22409D7622C28A644B404B6A943207FA224042DAF8EB8A644B40523F35FF19FA224028858E5B8D644B4058173F0340FA22405C1519D892644B408C2178B94AFA22401D15EA9094644B4028B8C07F50FA2240D3B28D7E95644B40B7FEB3287CFA2240CCC23D839D644B4042AC8499A9FA22404614FB95A6644B404E7675B9B6FA22403061E234A9644B4009155400B8FA2240C90B2876A9644B4072B30F73D2FA2240A4C52B82A9644B401C0BD0C2E7FA22403E676B8CA9644B400B609B82EAFA224017363D79A9644B4078C4B646FAFA2240B9983E0BA9644B40300AE4F5FAFA2240A22528DDA8644B4030F4D0C91AFB224027C30264A9644B40949703CF27FB2240C7B921CAA9644B404B703F9145FB22409D9C65F1A9644B405F85865257FB22400845E176A9644B403389F93559FB2240C7CF0E59A9644B405C65174662FB2240F0099C71A8644B40B5BFF4D577FB22401BC5A680A6644B40108A44EA9CFB2240B01D369FA0644B40072BB568B5FB22409E4E0758A0644B40C003586EC5FB2240A48DD5ECA0644B401462E3B8CCFB22402732D6E4A0644B403B8CEA59D7FB2240E54732ECA0644B4042889D59DDFB2240D3BA5AF0A0644B40834107370DFC22403113D36B9F644B403A00024819FC2240B95A19B69E644B40C43F7E6D3FFC22404F10CFAC9A644B4079B174739BFC224073C3506499644B40761E55D8EAFC2240E6594EB997644B40CDE3F7D6F3FC224085F9738497644B40620F673005FD2240CAECFD5A97644B40492854392EFD22407814EEDA97644B4014EF1D5D7FFD2240A5C447B797644B40FBDB7C4A97FD224002A9C31B97644B404BD7FA4BB8FD224006A1F82297644B400096F3EED6FD2240E36A0CDB97644B40B05B8CFBD6FD2240C473214698644B40B5D305E8D7FD2240B3157413A0644B404998BF53E2FD2240FC0AAAEAA4644B40160A4A44E3FD2240624A965AA5644B4087CFAFC1E6FD224092AB53E7A5644B40742A4115F1FD2240298F92ABA6644B40000023F60FFE22407AA0063DAA644B408EAD09081EFE224084F56252AB644B400E08894021FE22400B21904DAB644B40120EE4A228FE2240EF1B8042AB644B40B101B38A31FE2240D2932735AB644B4075A06FF34BFE22407D60DC74AA644B409EA67F7C55FE22401F991FA3A9644B40A6F738586AFE2240F31A42ABA6644B40D05D705173FE2240782CC983A5644B40C4A4D0527FFE2240B9ADA87FA4644B40EB771E528FFE224053AB8352A3644B4029B4F39497FE2240ED7A3EB7A2644B40C1BEF59D9CFE2240002B9658A2644B402E408009D2FE22407D8C5930A3644B40F80DCCCEF9FE2240823D24D4A4644B403073224B13FF224059326CDBA6644B409529380A20FF2240C7702135A9644B404093FAB12CFF224046D017E9AA644B407265C4D040FF2240285F559EAD644B40F7FBA48F42FF22404C08BFE5B9644B409A8BC6F535FF22404D26F25ABE644B405536886235FF2240B1E10B8FBE644B40046AB2AB3AFF2240F878E5CEC0644B40F5B37E7D4EFF2240CE135207C4644B40BDFD6EA382FF2240BE0B51ABCB644B403A5043AC84FF2240C3A79796CB644B406F17B09AA8FF224096288928CA644B407BAC745FCCFF224017C4217EC7644B4036BB59A2D9FF2240F58DA068C7644B40028F72CADBFF2240FA3C2265C7644B409FBEE93EE4FF224069786C57C7644B40892338791D002340A7A5AF5FCB644B4072F95A2550002340B63ABAA5CE644B4032E804435300234082EC40D9CE644B403A0C31027E0023409F54F683D1644B40E3468B4D7F00234029A05E88D1644B409EC528A084002340BDE1886AD1644B40389C77029E00234099924010CE644B401ABE9FF6B60023408F99CF58CF644B402B2C4976BD002340A92660AECF644B40B8E9427ABD0023400B3593AECF644B404051EBBFE400234041A8A5B3D1644B404BAE26A9030123402346A14AD3644B40D0084E7B0E01234015941AD9D3644B4021DDA3BF1101234093331D04D4644B40229858EA3201234058942C49D2644B40DD9F9DEC490123409684D130D1644B40AD2DCC7861012340C49DE0FFCE644B40B5DDB7DE7B012340D7B54533CD644B4036D4F99D870123400D4C292FCC644B40128E1FA0A1012340366B4384C9644B406E9627EC9F0123405EE1A9D4C8644B40E9D206819F012340756786A9C8644B402D6C265DB00123401DE1B795BC644B40DAD3225EBA0123405ABCE89CB5644B40A2711B59BC01234083EFB8ADB5644B4063769E29CC01234069625D67AA644B4063D65780D70123404C8DDE51A2644B40458E7E64D7012340195C772EA2644B403D7D9863E40123400057BDEA99644B40C822E198EC0123401195D72894644B4042AD04C1F801234093B959A08B644B4024332E23F9012340EE646F5B8B644B40F04F17EEFE01234095428D9086644B4072DD12D30002234011A6932785644B407825B2CE0602234025FC9BB380644B40A4420F4C080223407D4C004F7F644B40EBB990BA0902234072754BF87D644B406678E78A37022340AAD81F1E7D644B40A1BD75DB3D0223408BC40D007D644B4067B2053638022340CE0ECB0878644B40FE924D2833022340C678CD5D6D644B40D07143432B0223404B7039F364644B40499EF37C260223402AE9A4EE61644B40556A560224022340996C78895D644B40C221CB7320022340549F33DE5A644B406C896E9D1B022340D6135ADC52644B40CE7A175F1B022340D9CBE77852644B40A09B99C617022340F1C7F2A850644B4072448E54160223400BC0E0BB4B644B4002FB40E412022340B9CCEA934A644B403AA508850B0223405C83006D49644B402CF441F306022340C3DD9D1648644B403423DEDA05022340C07AB8C447644B40004FCAB70202234018B0DB1E46644B40BE279D11F80123409B56A5C743644B40F304473BF4012340AEE47A8243644B4041A85783EA012340399E4CD342644B40A068FA64E80123401ECAD4CD42644B40244844E0EB01234073EDACD040644B40DE2F5D6AEC012340AF37CC8140644B409003A10DEB0123408E99B3573F644B4052575FF4E60123405FD934073E644B405076DC0ADE01234059EC767F38644B40D935297BDF0123405A7CA44736644B405FE35706E50123409920790B33644B4014283ACDEE012340271860F630644B40D2EA0B2AF6012340A6E45CA62E644B40E7B0FDA2FE012340A05863842A644B40632F642EFD012340B332871329644B40E671782CFD0123406E0C6F0E26644B40B1C9A126FB0123403CFCD4F325644B4018101C28F9012340A97D700326644B403BF7858EE601234069BCD7001F644B401341A930E4012340657F7D1C1E644B4067FE09F0E3012340865473131E644B4071AE4275DB0123405A99BAE31C644B40243FC679D8012340F7E2E7781C644B4045571148C70123407D924ECA18644B400B797AA5BF012340729332FC15644B4037A607C8BA01234002449F3214644B40D7A31A78BA0123403A2C441514644B407DBC6CB0AF012340287A5D1F10644B40FD56F0A8B1012340C1C67C0A10644B4025A9328DAD0123403335C34B0D644B40B6C02994AB012340EA09A4600D644B405F542C69A301234083DE0F9808644B400F97BDE49F012340740EBA8806644B408B7F5AE89F012340B259E78803644B40CE9DF99099012340E496FE2400644B40B4B45F3E8D0123409201DF46FB634B40627A1CD88C012340A3472CFDFA634B405DA5831C810123405F04797AF4634B40DDEC73487A01234091B6FAB0F0634B40390536F97C012340D58D0CD3ED634B40D286C59077012340516B0759EA634B40E65374D46B012340B8152437E6634B40B26CDEBB56012340918E143AE0634B4049FCCB95530123401BADD327DF634B40FE9FF14B4E012340C1E8C94CDD634B403388CDA149012340CB14CFA9DB634B40894D8669460123400777A286DA634B40352C775C45012340B2DE9927DA634B4087DB5D2344012340A3E7205ED9634B404704D2FE3F012340C6C7ACB3D6634B40152C16B63D012340433770EDD2634B4096A1F8493E0123409D527167D2634B405E34763140012340409AC3ADD0634B401F83D3194501234032446F3BCC634B40F4CD85C13F012340423E6905CA634B40784512A839012340A16364FAC6634B402D44687730012340CB72CB12C4634B403F0B33B02E01234013FB1A84C3634B40E782833629012340072207BEBE634B406B02097E28012340B29ACE1CBE634B40CB9BFACE280123408665218CBD634B401B9B6CD1280123402D1EC987BD634B404B09020829012340B67D2F26BD634B403DB7FCC22E012340C69EDDE7B2634B4028825AB736012340C30A6BFFA9634B403ACF62CE360123406B6BA2E5A9634B40B32430DB360123408CFA51D7A9634B405616E40537012340C7DC7EA7A9634B40363B9AA163012340ED349500A3634B40E86E38BF7601234093344E419D634B40D0EB61F47A01234067D174FD9B634B406DA8E6C07F012340AD1AFA1F9B634B409A879DB38E012340420B5D6E98634B4055040EE69D012340D4A3F31696634B401EA8AE99A10123404C6BF08495634B408FAE70BEA101234033F2467F95634B406A0B2005A2012340880CD47695634B40C6E96BD5AD0123400D20150D94634B40695F73DFBD0123401E734ABF91634B40472A5943C80123409C42BBDD8E634B40246F2782D0012340391C05558C634B40C2268CFCD0012340B7B9263F8C634B401F1DFF85D2012340ADC3DFF88B634B407882DE19D8012340E0FCCDF98A634B40B7D49785EE012340CF423E1885634B4092CF846EF001234044E24F6984634B40A02B8EE3F601234013D0E41982634B4041CA4B8DFB012340E338F16E80634B40650A27FA020223408F5134497E634B4011CFD658050223403D61BE997D634B40EABFBF2009022340B622D0817C634B40BC3C7D0613022340E82227447A634B406C319C3118022340D985951879634B407C1B07AE3702234046E99BF771634B40DEAE1D1D4D02234054E3531D6D634B40A3B179A1520223406B017ED26B634B40959CE8E954022340C526935F6B634B4080F72AB069022340F381DF4967634B4044AF38286D0223408D4FA29B66634B4033D697C26F022340D35AC41766634B40A589CF637602234055A4493B64634B4056E4A2E97A022340C3056F865E634B409AC4E75176022340DBE735DF5B634B40E59EA09A720223405FCEC8C85A634B402726BA9972022340A49183C85A634B40A4033BA16D0223402F03155459634B401B7EE5946D022340CDEF795059634B408DD6B0BA6C0223406EE39B1059634B40889BA3796A02234013B9E86658634B405AF2019A68022340A9FE2E9B57634B400D85469160022340E1D4ED2D54634B40BAB117055D022340E69A296953634B408543408D53022340FCC0475C51634B40FD4E0079530223407624E45751634B40FBEC00AE510223408D90147151634B40DF0F593F30022340EB14C24653634B40B8B544A02E022340915517A252634B405876540B2E022340D1E5456852634B40F6D082092E022340BB1E696852634B40F986C7782A022340DCC3C60151634B40FDF6523F260223403A8555CF4D634B400D1493BA25022340232BDC6A4D634B405295A9FF2102234099796A854D634B4067C2FCC91F022340BC1C26954D634B4004AE4150190223402B21714D48634B40FE7264F5FB012340513B6DAA34634B40618D6FD1F3012340FD320DDC2D634B404BBCEA57EB012340A076017A26634B405DD8FCC7E1012340E10D4BF01E634B40D134B224DC0123405613E1461B634B40B63C9634CA01234011904EA00F634B40A709E858CC012340D26F60910F634B4026005C2AD0012340A2BEC4760F634B4090AA7BD0BF01234080BC7E8504634B40D9FBED0AB201234091F7103AFA624B40F0900317B0012340162A5C99F6624B40EE211053B001234053161C66F6624B40BADBCA61B401234011A89BCDF2624B40CCF073C6E30123403E4E8C96F5624B405E345484E5012340C6AF19CCF5624B40326B11C7F20123404F65D463F7624B402B9A7B0FF3012340C4A4856CF7624B4088B6C828F3012340D1125027F7624B404C0E082BF30123409C271B21F7624B4041100B32F301234016168D21F7624B4023B50C470A022340F67E3298F8624B407F1CCAA1300223407D12BEF1F8624B407C79D35050022340FFF9B33BF9624B403485E28772022340B9460263FA624B40F27A5A6A85022340A47A51D5FB624B40F1F8F1369802234087FBF145FD624B40B9B46783AD0223406B7067AEFF624B408ED18231AE0223402F5E16C2FF624B4013CB4508AF02234065F581C6FF624B4044D6763BC7022340428DF94500634B409154667BDB022340C93252FAFE624B40FAA17E11E30223407578127EFE624B406FE8E1CEE50223406BDF9E25FE624B40C70BCA49F7022340C65240F1FB624B40F2CDA895F70223403F16CCDAFB624B40D9B16D5605032340117B1AC9F7624B40F23B38041203234033130157F4624B40EAB96D3D150323408F29429BF3624B40BF79189F22032340969A9E95F1624B402782D65A2203234067EDA48CF1624B4016EAEA0420032340E5B47240F1624B40E9100BED1F0323406697EF44F1624B4065801CFA1A032340F948CBB0F0624B4066BB1937100323406640A46EEF624B404F7CDE160D032340096B1311EF624B401B925225EB022340B2B56DD1EC624B407B7F3BE1A8022340EC3D53FEE8624B40B48C15BA5B0223403E4FD589E4624B405103AD094D022340BB1659A0E3624B40F38ACA324B0223401CBA6F83E3624B40335FF99537022340D80F414CE2624B40BEE636382602234015595639E1624B40FE5AC29A0D0223407CDF3632DF624B408FA51449FF01234054A01104DE624B40259F1230D501234058B70E8CDA624B4044FDF877BF0123403183AAC1D8624B40B7B6B64CA001234094D2E42FD6624B400481930E42012340E45433BFCE624B40E9187C4B3E012340815A987BCE624B407A5EA9B5340123403634A2CECD624B40152E5EB3EA0023409FD0F498C8624B40B6B8F390CF00234064F50E41C7624B408900D7F2BB002340D2BBB65FC6624B400A2F0D506800234061A847B7C2624B40704BB69B67002340D95B64AFC2624B40E85345F72D00234020FFEC29C0624B40666683AFCDFF2240B4DA51F4BB624B40F9378AEC77FE2240C45D1B01AD624B4082837ABC56FE2240B525408DAB624B405370C70957FE2240CFBDAD30AB624B4083311A9858FE224025A69A53A9624B406C7BBF5F60FE224049501A02A0624B40ACED83624DFE22401CF216369E624B40E07E8DA045FE22407E3E623A9E624B400E9C719942FE22408C107A9B9E624B40722DB16840FE22406653B7E19E624B40D0F019423EFE2240D48DB1269F624B401A9D43453CFE224080D8447D9F624B40157A242D31FE224053BF7760A1624B40453AF40430FE2240E78BDF92A1624B407A89628F2DFE2240706E02FEA1624B4055FEF1891DFE2240457304B8A4624B4084FD9C0F0BFE2240986716B3AB624B4004B9D29E05FE2240565982C1AD624B403982098605FE2240CBEEE1CAAD624B405A4D3276FEFD2240116DAC94AF624B40761C1BDDECFD22402AF17908B4624B4012E51DCBEBFD2240E6CCCB4DB4624B4000A0281AE0FD224070692240B6624B402F820D41CFFD2240F04F450EB9624B40BD31E005C8FD224096897F42BA624B4029635AEDC6FD22400E623371BA624B4042897770BCFD2240A8FA3C30BC624B4081C17B91AFFD22401E14580DBD624B40A5AE77A4AEFD22403165401DBD624B40C37508169FFD22404CA17C28BE624B40800D44354AFD2240A0D6C9B6BC624B40D511614542FD2240D4A891D3BB624B408EDA41AF2EFD2240EBF5DBA2B9624B40E64EE9D627FD22409E17C67AB7624B401A3281902FFD2240C4D31F42B4624B40CC1A76A730FD22405DB6CFCDB3624B4065B6078335FD2240614840C7B1624B40D140A1772BFD2240930BB624AD624B4044340B7B24FD22401BF11274A6624B408178E72923FD2240B948B87AA6624B40CACB6B0B23FD22407EE8527BA6624B401D56813A20FD2240CC9E8989A6624B402FA677B225FD2240AC01A49DA3624B408D16520E28FD2240989F0F5BA2624B40E75B7F3128FD2240C0D04448A2624B409AB0C1872AFD22408069A608A1624B40ECB0A2412BFD2240DD43F1F1A0624B4066CA221E40FD2240C18CA1659E624B40D628777149FD22400FC208429D624B40CDB53A554BFD22406ABEF1959C624B4097F2B3844BFD224088FD0B859C624B40C8CFB69753FD2240C104B3A599624B4075E35D7349FD2240CA3DA8CF91624B4054C5843349FD2240C904569E91624B40EFC7827042FD2240924BFBA38E624B4008CF4EA540FD2240A4B9B9D98D624B40BD8ED6BA31FD22408D24C7568A624B4081609BC735FD22401119BC498A624B4049FA28D82AFD2240792E091089624B40A1DF93671EFD22404905573B86624B40A4E7CFB317FD2240C137C55E85624B40B3E2FF45FCFC22407BD4359282624B40EB2867E2F3FC2240C84C0DB781624B4030F1E9EFEEFC2240CA6E207E80624B40B5CAD410EEFC22409DCC607F7E624B40478F4AFFE6FC2240E7DF628D7B624B40D1EB7C99DBFC22400437719D79624B406E731C73BDFC2240CCEC486077624B40D57E7B02A1FC2240FD7BDF2476624B40234757BCA0FC2240B69DD62176624B4015D3063B9BFC22401A5BC8E475624B4039EB117898FC224038C227C675624B40E69FF3E999FC22406967892876624B407BC88B1B7AFC22402B18D9617D624B40F9F74B9169FC224077C554CC7F624B403306CE3358FC22407B8F0E0C82624B4053F30AB23CFC224028A777B984624B404A8FF9C327FC2240499A3E1186624B4023B82A4E19FC2240EA8C0AEE86624B4075BD02B60BFC2240FA3E95F587624B403E681B27EEFB2240D7BE47A288624B40C82500AAD6FB2240D6392AEF88624B4078A61E2DCDFB2240F7506DFB88624B404142423AABFB22405D22783088624B40321E017399FB22403831CD2F88624B40A2E4C6E080FB22402128038687624B40413B4DF264FB2240D53E01C586624B40C0F98B8056FB2240B19A316186624B40E8ED01603BFB2240BB8DBDA585624B40519F0C1034FB2240B373357385624B40A783FD972DFB2240CD36814685624B405C2D752F29FB2240BC0E0B2885624B40605EDBFA26FB2240F1155F1F85624B409F0133ED1FFB2240D31CA30385624B407E64ED5514FB22403E5B10D684624B4009F34BA4FFFA2240D701465E84624B407678751AECFA2240DC6259C783624B40C9FCF84DE7FA2240119835C183624B4066690444E5FA224048AE99BE83624B40F2FFC4EDDBFA2240590BA7B283624B4030462C47D1FA22402BD8957983624B40404F04A6AFFA2240590D64C582624B406758A110A3FA2240BCE6A57E82624B409A6669F7A2FA22406CCF177E82624B402B1BD9CC7DFA224005BD27AD81624B40E25C444159FA224064FC00A580624B403D4E203354FA224044FB881583624B4050779C3E4BFA22404408B6B185624B40C4B85EFE4AFA224071246FC485624B4048D0CAF94AFA2240FDFCC3C585624B4011CC1AB441FA2240AABA987988624B40A80D667330FA22406AE30FBD8B624B4085D44CF72EFA2240190EF5048C624B404997DEA625FA22401AE7FEC78D624B4022A90CAB18FA22402998A3A78F624B4005271F1000FA224045DD35CF93624B40206D60F5D4F922401C1BB67F99624B409459E998B7F922400250011B9D624B403F69E787B7F92240457C161D9D624B404DDE8774B5F92240F2515D5E9D624B40007C6288B0F922401B4328F99D624B40255CFA3CA0F9224012C68CF99F624B40E886661B95F9224052C1ACDCA0624B4055C4FD768CF92240A7FB028DA1624B408964266181F92240FE44346FA2624B4044BBE63179F92240084654E5A2624B40C4B044AA76F92240D7BCB03FA3624B409BDCB4C56DF9224093AE96F6A2624B40AC14F26644F92240B1A722A6A6624B402552DBE533F92240712BC1C5A7624B404522B42D2CF9224002D270B8A8624B406D8E678C27F92240BDED004AA9624B40E46B29A320F9224049DD7A52AA624B400A7920841BF9224046967716AB624B40F834176D1BF92240265EC015AB624B4003F6885018F92240163CE7FCAA624B4041478EF810F92240F68891C2AA624B407B474758E0F82240D9AF4D40A9624B4007BFDB2A34F822404A8984E8A3624B40BA11DE6F15F822400B9960F4A2624B40FBA05BD70FF82240A72128E3A2624B40E6503C8AFBF72240AB661651A2624B4049BBCF83E2F72240C64B7157A2624B40BA1EE72E9BF622400BA856AAA2624B40E212BF8182F62240ED1821D1A2624B40B85D305D51F622402EE8621EA3624B409E62ED684AF6224023785129A3624B40372E603C49F62240915E292BA3624B40FB182F0645F622403A155D3FA3624B4005D55F9724F622407E69F1DAA3624B4091794F961FF6224089E9F2F2A3624B40FEBE8A8BFCF52240BF96C5BFA4624B401956BEF2E9F52240A957772CA5624B40C2C17C6BE9F52240A6238E2FA5624B40AA2526DECBF52240EA5448DCA5624B40CB079347C0F522400B2C0320A6624B40BA8B6CFDABF52240A300C38FA6624B408209D2A8A2F522405FBC27C3A6624B4082D0EBAF99F52240E7B192F4A6624B404081677590F5224079280D52A7624B405B8641A737F522408017C132AC624B406AFDF02B36F52240A4FB3E9BAC624B40283544F035F52240E1C3AFABAC624B40DFFF3F6C35F52240534A0CD0AC624B40BF8E86462FF52240CB23F138AD624B4060C1D26128F5224088A38FAEAD624B406BD5729821F5224014A10723AE624B40907E42601FF522409E2D2049AE624B409AA2E1A8FDF4224091A36441B0624B408F242EA2EAF422403E21F35DB1624B4011F18602CAF42240FFDF5A6FB3624B40E21E71B5AAF42240C79E4A6BB5624B406F82B760A5F42240B1E1CCC1B5624B40B1315B4A8FF42240EB9C25CFB6624B4051A6E6BC70F4224035A070EEB7624B40396E86A464F4224083512D60B8624B409D6D4B4660F42240864A3F89B8624B40FBBAC7902DF322409A6814CDC3624B4087A0048312F3224084101CF2C4624B406918B5D7FDF22240FDE4F9D1C5624B408E9AB7A0DAF222405D8E2D18C7624B40EAC103F4D5F2224045457B43C7624B40FEAB8D68D5F222407D75E044C7624B40757EF23ED2F22240943DF54CC7624B40A38900D7CAF22240F5BAE45FC7624B40C7BEB409CAF22240962DF499C7624B406AF470D8C9F222406367E3A7C7624B40D3A20238B3F222405E122A0ECE624B409E7AFBE6B2F222402B0B1425CE624B404A2BC18DB2F2224083E588CACC624B40EFF584C5B2F2224034879599CC624B403629C857B8F22240472A2FB5C7624B40C433A747B9F222400AC61F2AC6624B40006D2153B9F22240A49B3617C6624B4043D4B921BCF2224056BD594EC5624B407AFED435C6F222401084A47CC2624B4036F9AA89CAF2224065A6170CC1624B4033046654CFF22240FCD8F773BF624B4033E6D1C8D4F22240089D6AA3BD624B4024E39720D5F22240B3643586BD624B40841C741BE4F22240229F6B8AB8624B4053236ED0E9F22240E35E490FB6624B40F834F67502F322402D692E58AB624B404D1FA9D005F322401D027C21A9624B408167CD9D09F322406BFF439FA6624B4056A5219F18F32240D9FB2CB89C624B4068F8B0DB24F3224004A0817391624B40359AB28125F32240424E6D0A8F624B40A53DB59A25F3224065FA78AD8E624B40448850C417F32240B43FB62D8D624B409039BAC4F8F22240D8F9FFD189624B40ECD1A9D4D3F22240E14F90D185624B40E2C46E85CAF222407B1BFC7384624B4051207538A5F22240FE0F68BD80624B401E97980DA2F222409040E43B81624B4024F557C49DF222400B390FE781624B408AD5A7A598F22240CAFD83B382624B40F7FD07A298F2224013A415B482624B405EE2B30F98F22240A466E7CA82624B40393F0D1078F222403B66B70D7F624B4019DFA4F674F2224096A902B17E624B4092174E9767F2224067E83BE67C624B40195AE3F560F22240B422BE027C624B407925381D41F22240E6F626BE77624B40EC5243C440F222402E61C09977624B4042BF2F0E3DF222401A54E11476624B40190BABC438F222402E36AF5374624B40D1E3F03E33F22240BD250E1172624B40A74BBC0132F2224053AA62AA71624B40B97CA9D130F222405984F04771624B407863D22E1AF222406708C1F369624B40D1DF136AF1F1224010F4775364624B40AA7004BEE4F122408F7A9D0262624B4008173425D4F12240B3BBB9F75D624B40BB3B5CB2BCF12240466F964158624B408DB4DF31B2F122409D3665E554624B4093AA4600ACF1224097EABFB652624B40C1AAAA30A2F12240B663DE414F624B40893C96FD9FF1224058933AF04D624B409B217F1B9FF12240484CA7684D624B40976934F69AF122407AA73BEC4A624B407A47A74699F122405E95B8284A624B4019CBAF9C74F122401FEDBB6042624B403611DCC54DF122401B4E88223A624B40720839AC36F122405CD4C24F34624B40215E1D9335F122405792DE2234624B4031BCB92222F12240EE46260831624B40B820E3F3F7F02240A7D78D5B29624B40CBFFBF1FD2F02240D7F673ED22624B40D520E79BCDF022408F691E2922624B40E5BA85ECCBF022402BE568FC20624B403EF309EACAF022403591364820624B40C7804387D0F02240A6FACB6617624B40DDD01E29CAF0224089AEE5C915624B4004A1C502C1F022407425FFE015624B40165BF543BAF02240F2BA06F215624B4066E6982732F022401B5ABF0A11624B404D24E61925F022404D6B5F9210624B4045E6AB75D9EF22403B5FCE130E624B40A21842F5A9EF22403D499C530C624B407AB901328AEF224082D8E8270B624B40DBEE44888AEF22405C86FBF30A624B404D240A798CEF22403876F2C809624B40F4E7DB2306EF22402B90CCBD04624B40E93CAA3CFFEE2240ED7F707B04624B40E7E143D0E3EE2240C8D0987C02624B4094A8C9B4DAEE224043BBF0D201624B40C9758C7AD8EE2240D2AF75A601624B408DA57DF7D7EE2240B1183E9C01624B4010A8D097C3EE2240F9D5730500624B40EE8F6CF1A4EE224076D2B5F2FC614B40094F83CC89EE2240BDB6E3F4F9614B40F09484AA6BEE22400C46AC94F5614B40C6050EA66BEE224098890394F5614B40E446A34F6BEE22409D287887F5614B40E78BA0FE6AEE22407E5FAE7BF5614B4017F691FA3AEE224040FB8D7FEE614B406C04E3BB39EE2240E0073251EE614B40CF63945B37EE22405E68C4ECED614B4097CAF38E12EE2240FC0C5AD9E7614B40B0E4035308EE22403BE40D7AE6614B4057E9F3CEFBED22404E4C6CCCE4614B405853BDABE3ED2240D4F5DE8FE1614B40B9F02B18E0ED2240D1A15E0AE1614B407C812C72A1ED224034D1B5E7D7614B400BF31D0E52ED22405AA08CA9CC614B4021020E8727ED22405290EF58C6614B403B933FE500ED2240413FC192C0614B40628A50A6D5EC22406574DDADB9614B409CA92837C3EC224030DF72CDB6614B40BB3ED315A7EC22406F0EB469B2614B401F93ED61A0EC22406FFBEE5DB1614B40A9746DB193EC22401CD72186AF614B404767D0AC69EC224070F2DD6BA9614B40D87F046B68EC224073A9213DA9614B40CDC5B5DA0CEC22405498A2F09B614B409F2BCA01BCEB224035528BD08F614B4042FD7BF9B6EB2240426854B28E614B40EA16B695B6EB22403F99299C8E614B40D3FD4F38B6EB2240EAFE69878E614B4094D3ABDBB0EB2240898874568D614B40B262D48EB0EB2240D35C2BB58D614B40A1EC6C6DAEEB2240C02F4C5590614B40435B1280ACEB224086134CB592614B40A9BF677CACEB22405B9489B992614B40DF22261B9EEB2240FAA5DF4CA3614B408B1E3E047EEB22407BA5CCD0B0614B405235A79279EB22408A39944CB4614B4095E7FF1666EB22407C56AB67C1614B4006E2864B5DEB22402E8C2E07C5614B4026662FCD4DEB2240CB49A8B9C8614B4051AC3AF245EB22400B254928CA614B408321991245EB22404A538A3BCA614B4051B174C639EB224067258634CB614B40BFDB822B21EB224095A92408CC614B4053D2C3C700EB22408E7B7F42CC614B404B32DA8AEFEA2240F65E8D2DCB614B40C4EC5BF3DBEA2240C964E765C9614B40A3F0F8F2ABEA2240CD170BF8C5614B40B5311405ABEA2240F2D7EAEDC5614B409CAE34D295EA2240886F4881C5614B403BD066F883EA22409446E0BBC5614B4029DB8DFB71EA2240691FCD7EC6614B405C4D80BE47EA2240BCBCBE6ECA614B40CB69BBF33EEA22405EBF944BCB614B400D508E2D48EA224040C6B5F7CC614B4074E4AB7859EA2240ED533B1AD0614B4069F0309473EA22404495A600D5614B40A52712F88BEA2240794767BED9614B40A8878B848CEA2240734AB4D9D9614B404753471C8DEA2240CE0B34F7D9614B40B185170FA6EA2240588089FDDE614B405AD93231BFEA22404119D756E4614B407FE245F5C6EA224038752016E6614B403EBB5E56C9EA22401839A695E6614B409875DB1BCBEA22406E9C2F05E7614B40CA73185FD7EA2240706578C7E9614B40245FB994EEEA224070ED844EEF614B40022F2FFFF2EA224044AFF56BF0614B406E568620F3EA2240470C6174F0614B40DE1C21CE04EB2240E75610EBF4614B407D966F0908EB22400D6044CBF5614B40E2B4D07910EB2240C836BD14F8614B40489104FE12EB2240278B50C3F8614B4085B5613319EB22408E4B0972FA614B400FFA31B42CEB224011E7230A00624B403180DF4D3FEB224070169AB205624B401CCADFFD50EB22406FCEA36A0B624B407411335D55EB2240051497EA0C624B40E194E1A856EB22400A0D5C5C0D624B40AD0B589F5EEB2240F54C951710624B40BB5CAEC06BEB22404FCE29CC14624B407737246178EB2240A82F188819624B40D6B9ED7F84EB22403451174B1E624B40B0497EF294EB2240F6729EBB25624B40E5283E3AA4EB2240BD2769392D624B40D3451855B2EB224072F780C334624B4007DF93BAB2EB2240F7CD0DFF34624B400508DC05B3EB2240B91E3C2B35624B40DF184741BFEB224055C1E3583C624B405E634EDBC8EB22407305B13343624B40FB338D2CCDEB2240279D41B446624B404888BE41CEEB2240704C1F9547624B400BFB3858D1EB22402D1755164A624B409D7BC7B6D8EB2240FC43D9FF50624B404626FDF5DEEB224027DA44EF57624B401BAF5F81E2EB2240E94F41955D624B40811A7ED0E4EB224080276A0E63624B40A10FDAD8E4EB2240FFB93D2263624B40F339C6E4E4EB22407749783E63624B40572EA91FE6EB22403F7AABE968624B40D48FB531E6EB224059298B956E624B40D9302710E6EB2240761E28BE72624B408BBFBBEEE4EB22405712F5E576624B40F185CECDE2EB2240F2D7A90B7B624B407E1D0609E0EB22409F7E05CE7E624B40CDD3DEF1DFEB2240AAB63FEE7E624B40D5E45D82DDEB2240E97AA35282624B4027CD51D4DCEB2240EAF2490A83624B405A553732DCEB2240C5C450B583624B40FCA7038BDAEB22404E66CE7385624B4050739D3DD2EB2240AA2B62A78B624B404BE7D31EC9EB22404D0722AF91624B40956C942EC7EB2240779989CC92624B408AEACEF7C5EB22405226467F93624B400AC622B6BEEB224001F1AEAB97624B405E0C0606B3EB224053008E9B9D624B4065467211A6EB224090E64B7DA3624B404FE73261A3EB2240EB0170CDA4624B404A392060A1EB2240213D0BC8A5624B402684ABD9A0EB2240599EB409A6624B40445E60D0A0EB22408B27180EA6624B40BD21E8839AEB2240A4F2C306A9624B40BE21092493EB2240FE425781AC624B401E9A2D5E8BEB224027BE0A2CB0624B4025893F4E85EB2240FCB02608B3624B404099308277EB2240FB99C02FB9624B4036D8C75268EB22409446D4F5BF624B40CE67625D60EB2240C513BA1EC4624B4021CBA8515CEB22405E919E89C6624B40371F3D505BEB2240E41B7323C7624B40ECD0435859EB2240D3C19F50C8624B40AA884D4553EB22409E64638ACC624B40158A2B264EEB22403B2EE1CAD0624B401F2CAE254AEB22402C7B4593D4624B406A5AACC546EB2240CD09EF5ED8624B4017A8B20644EB2240600D4B2DDC624B4099B018E941EB2240F36BD0FDDF624B40322D034940EB22408970A825E3624B40B79BE2E73FEB22404F194BE2E3624B40B69299613FEB22408614FFE6E4624B404309FAC93DEB2240C9FF45D2E9624B40EAFFA7223DEB224026D7B3BEEE624B40CD990C2A3DEB22408E7F4A3FEF624B4087CAC92E3DEB2240EC36D590EF624B407DF3986B3DEB22405C9651ABF3624B40A01A25013FEB2240FDC276F0F7624B40C810911941EB2240BC166C34FC624B402661E74541EB2240DBF5EA7CFC624B40B128A4B443EB22402A7EE27600634B40960F40D246EB2240082783B704634B401A37F5A248EB2240A796069D06634B401BDCFFEF48EB224019BF88ED06634B40049CCF014BEB2240ADDA051709634B40C89571B94FEB22402220A7730D634B40CDA6C4F854EB2240516A0ACD11634B402818337356EB2240B50509E912634B4089E874BF5AEB2240B716D52216634B403661250E62EB22404B3D13A41A634B406E43067168EB22400266C51B1E634B4042BAC71469EB22401F98AF741E634B403102454A6AEB22404D66BD1C1F634B40C52C09826FEB22400E2FA9A321634B40684121837DEB22404FDB37F027634B404330182187EB2240D3076FD72B634B4088FC51788EEB224067A46B9D2E634B40724AB1628FEB2240079EF3F52E634B4095344C5F91EB224074271DB62F634B401DE2333C9CEB22406DC4B38B33634B40C2ED60B6A7EB22408008AE5737634B401E03E3D7ABEB2240E0D9FBB638634B401DEEFFA2ACEB2240955A77FA38634B4026F3013FB3EB22408FCE8D2C3B634B40C358EC7ABCEB22407A8D51193E634B401199623FBFEB22403901B7F93E634B405D8174B6CBEB22407EABDCBE42634B40AD5A51A3D8EB224084CEB17B46634B401D965B20DEEB224076E887D147634B405B82C98DE3EB22408E3C912349634B40216FE366FCEB224084CF262F4F634B4014172A1907EC2240433357C951634B407AAD40D526EC224018DB24A759634B4076375F3127EC22400C60F9BD59634B402B5D1C3227EC2240757129BE59634B40DA3A21702BEC2240F7D25CCB5A634B40F53606EA46EC2240ACA8EE9A61634B402F37F61047EC2240F41D95A461634B40DE8B3D8157EC22400A2BB9B765634B40F452E95158EC2240FB9673EB65634B405CF0322882EC2240293504CA70634B4001595CC590EC2240D001F99574634B40DD5BEB10A2EC2240048ABDA279634B40D25E9805A9EC224068FBA5AA7B634B40397982D0AEEC2240E4C3A15B7D634B40C2D82B7FB3EC2240ECDFF9BF7E634B40ACE2DDCBBEEC2240AE9BEF1B82634B407D6C4AB5D2EC224064BCE13089634B40DF19A8B6E5EC224021C2185390634B40E3006799E7EC224063D3662791634B40F0AA91E70CED22408809728FA1634B40AD55A80F15ED2240E109BC25A5634B40785F2B7116ED224050AAE655A6634B4089D833A21CED2240823D27BDA9634B40A7891F6A24ED2240802CE4B8AE634B40EBA291FA2AED22406E1BF7BDB3634B40C04070B231ED224069B65138B8634B40D0403AD937ED2240CA9C04B7BC634B40903A656E3DED22402586AD39C1634B40DFC3667142ED2240DF29EABFC5634B405B7DF11848ED2240344212D8CC634B40C9314EC94AED22401C2F7EFBD0634B4014548EB74CED22402D3D3AF4D3634B40B835AD4C50ED224087C19313DB634B4037C3D8D752ED22409B6E5035E2634B40C69C23CA53ED22408DC8142AE9634B40218C37C753ED2240AC5E897FF9634B40705D8C5053ED2240599B2509FE634B407747A3794FED2240C8320DA303644B406F4339454EED22402F0313A605644B4023A04C834DED2240F96A02EA06644B40E2AC64944CED22403A13097908644B403A71858B4CED22401F02CE8708644B40801D287C4CED2240BB3F79A108644B40D582A3094CED2240BA057F2B09644B4021C1AB024BED2240A9CED8CE0A644B40AA06087A4AED224088CEB7A80B644B4026CF604749ED22407D074DCD0E644B4015768BA148ED224068746F8010644B4087CDFDED46ED22400CA125F714644B407E9B0CE544ED22404939EC4D1A644B40978CEED644ED22400C06E6721A644B407E8F99D644ED22406C5154791A644B40ACF3874144ED2240675D6EF424644B403863DD3E44ED224055A53A2425644B40F53EAB6244ED22405E82905D25644B40C6520B8E4BED2240959D6AD630644B40E1ECEB994BED2240CD0369E930644B403F712ECF4BED22402736D51631644B40EBF391F854ED224092C8F5E738644B40AE33B18862ED224090ED687A44644B40280ED5D273ED2240CBA5AE2F4D644B40065ECE7474ED2240781B03784D644B406421B4A977ED22400B839EE64E644B40879D6F0780ED22403C400BA352644B4018A5C62085ED2240F96BFCE954644B40682E58DA86ED2240DC3361AF55644B407291A1D787ED2240DE55271356644B405151CE7B8AED22405C9F7D1D57644B40D9FCCD228BED22400B9B475F57644B40DF7B3CC3A0ED224089DC0BE45F644B40F5BC8D00A2ED224074350B6160644B40BB2C10AEA4ED2240639F754561644B4037B3062AB1ED22401E654E6E65644B4074A01F4BCEED2240DF41E9226F644B4023DE3F7ED2ED2240E9D61F8970644B40EA7B39DEE5ED224079F92E0C77644B40D03AEE7BEBED22409F3065EF78644B40E9909A2EEFED22405280922D7A644B40E54CDF3EEFED2240BBA007337A644B40D849FA39EFED22407DE1482B7A644B401DDEBA37EFED22402106C8277A644B40C1885FDCF6ED2240C6ED979D78644B40D97724111DEE2240DCDA1CEB70644B4088D4A29921EE22405007F72B70644B409B5BF6B521EE2240812F4D2770644B4028294FFF25EE224088FDB5876F644B40912708EC2AEE2240111247E76E644B40523DDE1F30EE2240B70B52536E644B406969E69435EE224004567ECC6D644B406101E5443BEE224002DC67536D644B400F3B752941EE2240416A93E86C644B40BC74D43B47EE2240422C7E8C6C644B40F0A8FD2A55EE22408A624CF56B644B403B12A84363EE2240C19349746B644B40B93367F373EE2240C480A6F96A644B404D7A0CE776EE2240870148E06A644B409283EE7F79EE22401DE381A66A644B4010C398AD7CEE22403E9BD5EA69644B4023F621727DEE22407AF73BA469644B408343D6A77EEE2240E94AB16669644B401792F03B80EE224074FDE73569644B4054C4351682EE2240B9E2D01469644B402B637BB488EE224050309DB368644B403B29B6C088EE2240E07DECB268644B40D8891E4789EE2240322B6B0269644B40950450D089EE22408726C76669644B40EED09C5490EE2240CC72202E6D644B4018B90A2098EE2240F66575E870644B40A2043DF09BEE22407DACF37372644B40BE422F569DEE224080C08C1673644B4037D520DB9EEE224048FD8DA273644B40E4AFBF2DA1EE224020AE769374644B40CE693478ABEE224041C9DE2C78644B40EC61728A15EF22405ABE5A789E644B406EB7BC0145EF2240DB76DFB2AF644B406F999A9779EF22403576EBC8C2644B4074B0EA5087EF224033994925C8644B4037431C2D8CEF224069EBE7EAC9644B409F3ECDA490EF224006E702B6CB644B40429ADFB694EF2240891A2586CD644B40B01E356298EF22404838D55ACF644B403C01E5A59BEF22404CE59933D1644B40162D21819EEF2240E5BFF90FD3644B40CA5E1BF3A0EF22403A8A77EFD4644B402EBEE698A4EF22405B8BDDB5D8644B403AABBBCBA5EF2240381ECB9BDA644B40AD2F7E93A6EF22400D4FE182DC644B40E4C5E5EFA6EF2240719AA66ADE644B40803FECE0A6EF224026C69752E0644B400F577E66A6EF22403E65373AE2644B40F990CB80A5EF224021FA0721E4644B40E4710330A4EF224017078C06E6644B407CAEEABE9FEF22409E3958BFE9644B4095EA8D749FEF2240C19013F2E9644B40582E19D39FEF2240D5F16CF6E9644B4011A5F540B5EF2240A34EDEF2EA644B40EA3CF248D6EF2240ACAB7578EC644B40C46FDCCFD6EF22407840AF7EEC644B4081E392D3D6EF2240F4B8DA7EEC644B40D0B256D7D6EF2240222E067FEC644B404BD68A42EBEF22400DDCD06FED644B406FFB34F909F02240566EE96CEE644B402195B8B414F02240A41859C5EE644B405359F6DD14F022405763DEC6EE644B40CEA6DFB23EF022403930711FF0644B4033D74A9C60F02240DA4214C5EF644B40CE1AA34A6DF02240FD5549A3EF644B407CE906E992F0224012E30A3FEF644B40914113FEADF022406E75530AE7644B4014163595ADF0224093A81487E6644B4067392DFDF6F02240E307FBEBD0644B400D86855400F1224030F75C17CE644B402ABB7BD103F12240E95ABB19CD644B40CF2EF69F06F1224037D1A94DCC644B40BDA9253108F12240000FB6DBCB644B40	Flensburg 7	\N	fl7
2	organization	102	0103000020E61000000100000080020000C3BEBC24C7E72240783788A22C674B40774C38D3C8E722403FEC580D2C674B40BF11376CDFE722404580D3972D674B4008C1F2A5F2E72240615D07022F674B4014D523FAF2E72240B8F592072F674B40D7B829E507E82240506B2C6830674B403FF2F4540AE8224022213C9130674B4019C790A90CE8224025CB6BB230674B40F9C42C7712E822405B49130531674B4023DA62861FE82240DDCE0DBF31674B404A05B77B2DE822401012D68532674B40110B35CF2EE822401B5AB89832674B4030614A672FE82240EB002EA132674B4008583A9230E8224080F966AE32674B4072C0A2F031E82240B20BE6BD32674B406C7E384E4FE8224060BC4D0A34674B40508B726956E82240C4C2BB5034674B40F513204175E82240456EF34B35674B40BABDEE7078E822401F9FE96535674B40F95BB8117BE822400CDD007035674B40E95226EE92E822409C52B2CB35674B404E42BF4A9FE82240300533FB35674B40EAFA4F3AA2E82240C6817B0636674B40ADE4E769A8E822407185200D36674B40C650CD58ADE822403BA06D1236674B4011235127B0E822403A19731536674B405FE8C8A5BDE822401250F22336674B401E3FC087BDE82240829D7C0D36674B4024745014BDE822405A2C24B735674B40D6B524A9BCE822401AFDFF6635674B4067B9A516BCE82240AB1A71F934674B40CADA1A63BAE8224069ACC1B333674B40224FA489B8E822405199AF5132674B4065E5F1A4B2E822402CDE1C042F674B40ABAF56DCAFE82240FC51A4742D674B404B1AD615A9E822406D26A5A829674B404AFBB8FFA0E822400962295224674B40EB804CEF7EE822403A8A290E12674B4039921B916FE822404AC6287109674B40EC7E475961E82240B8C1708001674B40DE3595D051E8224012E7A0D0F8664B406F9784B142E822400934DE5CF0664B4087FB0F9240E82240F941042DEF664B4091CEDE493EE82240F98D90E6ED664B40E109647931E8224082F034BDE6664B4020E2F6FF26E822403C4C6CE0E0664B4084573CDC1CE82240D11FBB33DB664B402A00E5760FE822407B9760EED2664B4030F15B870FE82240BD07DCEED2664B40F8DF96BF13E82240CB715F0ED3664B4007CCCC0814E82240DD939F0CD3664B40A00EBB6120E8224057925A5ED3664B404DD97AAB2DE822403D6BF3CFD3664B40EBF331633FE8224040577168D4664B40E25629695DE822409764E1E8D4664B405CE4C81062E8224062404243D3664B402CCF79DC67E8224099D9800DD1664B40C61A59C867E822404964FB0DD1664B408908C5B36AE82240CD212DF8CF664B402B96322F6BE82240FE919069CF664B406E3515F36BE82240FEBE3487CE664B401BD99EFB6BE82240160A607DCE664B40E3900BE96CE822402729066BCD664B40E9A4913475E822404A8D393CC5664B40FA279D077BE8224023F0D624C0664B40F00AEA077BE82240A4878D24C0664B4087F7270382E82240878F480ABA664B408097277B82E822404F515EA1B9664B408428122E82E822409C847160B8664B401414FF3F81E822406A85E080B4664B409BCD22717EE82240F1CB4C18B0664B4073C9202C7DE8224029050A1AAE664B40F12E5C637DE8224096DF4E23AC664B40C5E6D55D7CE822401CAA2696AA664B4064D675587CE822402984078EAA664B4002CC7CA47FE8224088BCBF72AA664B40430DB39307E922403FF8110EA6664B40C1063DE61CE922405A7CA65DA5664B401F9505F71CE92240EE5C1B5DA5664B4073A98BAA20E92240CB23EDCCA7664B402B887D3925E922402F7E6AC2A7664B4092FF5F5D34E922400D62849FA7664B40210171AABBE9224045749B67A6664B4045D61844E2E922406F7F6F01A6664B40FA5737BC08EA224001E6A465A5664B40077B3F9E17EA2240F48682F9A4664B400880ADF71FEA2240C5B97E9EA4664B403A70086A20EA2240C2739F99A4664B40F2D207E127EA2240A8EE4D59A4664B40BC3F506934EA2240A7E3608EA3664B4055952E4842EA22401E8BC7ADA2664B40F3F275CD58EA22401246699BA0664B403900BEC770EA2240700B83B79E664B403F27E3137CEA2240F743109E9D664B40AD3C011D87EA22403F03C1769C664B40A799DFDF91EA224032FDEA419B664B402F053A6E92EA2240AF50D2309B664B40C24A249A94EA224086CE11EE9A664B409F204A2495EA22405C8579DD9A664B4015237B599CEA2240F4C6E5FF99664B40402B540AA2EA224013349BFC9A664B40CA42224DA7EA22404395BE059C664B402801D71CACEA2240CF77501A9D664B40D42F14EAACEA2240808A484F9D664B40FD31503EAEEA22406DCE18A79D664B407D134AEDAEEA2240C31741D49D664B40A1B6B374B0EA224060AF47399E664B40BCF13C63B3EA2240D30435439F664B40E44F6C08B7EA224067DED88DA0664B403DC042AAB9EA2240FBFC2587A1664B4086469EC7B9EA2240F3990392A1664B40238BF2BABBEA224014B6D39FA2664B400FA4EB53BCEA22408A0BCE31A3664B40328B5CDCBCEA22400894F7B3A3664B40FC793528BDEA224097B309CBA4664B40A10B5552BDEA2240C402DF7EA5664B4092D3F75CBDEA22403A9D8285A5664B40C904FF6DBDEA224054852390A5664B4072D5E66ABEEA224074A02E2EA6664B409A747167C0EA224032EC6FD2A6664B408CA21F5CC1EA2240ED3C9804A7664B4056A00B35C3EA224044748665A7664B40F2332F2BC6EA224042D2CBC0A7664B406F5C196BC9EA2240B722800DA8664B40491555C8CBEA2240B42ED436A8664B40128ED53CCCEA22409701C93EA8664B4082325FE7CCEA224096FE6D4AA8664B40AECFCF91D0EA22406C389676A8664B400BA25A5BD4EA22403A0B4791A8664B40A78F577DD7EA2240B4786F98A8664B40DAE0A3CFD7EA2240E4FE2B99A8664B4002866C34D8EA2240C25D129AA8664B4098065B0DDCEA2240CB60D590A8664B40A6043CD6DFEA2240C2CEB275A8664B407AA17F47F1EA2240D269300FA8664B40097232C7FEEA22401969DBBFA7664B4025983C1204EB2240C3279F9CA7664B40AB09247505EB2240A4A0B794A7664B40A53D086E06EB2240CDCC2A8FA7664B40CDC7959E04EB2240D9D2EF84A8664B409D3C495504EB224040B5D0ABA8664B4014289220F8EA2240D922EE24AF664B406E2C3305F7EA2240E0478B91AF664B40FFFFF737F4EA22401886D000B0664B4028D7B30EF4EA224033AC3417B0664B406B87A61EF1EA22407F1994AFB1664B40D49402FEF3EA2240BBF00BAEB1664B401C188BC231EB22407D548470B2664B40C063D9F347EB22407DC6D5C1B2664B406A9D2A627CEB22401455F381B3664B407FDB032E82EB2240EBDF44ACB3664B404D414B3DAAEB2240BF3E25C6B4664B40B1D5E9DEBAEB2240A1C36E23B5664B407F8A7C24D6EB2240846E67BCB5664B405DEF50250FEC224081B8DB03B7664B4067F79C3A12EC2240C023C90BB7664B4080476E9665EC2240C68F08DDB8664B40840C6BF2D3EC2240808C466EBB664B408C20FD96E0EC22408D577DD6BB664B40C3935362F9EC2240F433A451B9664B40EE09F2D9FDEC2240C2CF4E08B9664B4042292D7E02ED22409679B6CFB8664B403AFC594307ED2240DF2165A8B8664B408328891D0CED2240F20CC292B8664B40E9AE99410CED224061F2A592B8664B40DEFC2C470CED22405C8C6E92B8664B40E4F886500CED22403A959A92B8664B401C806B0011ED22405369028FB8664B40E4CDAFDF15ED2240FD022F9DB8664B40EC012BAF1AED2240A32726BDB8664B40900695621FED2240DFFE93EEB8664B40163A6BDB64ED22404B736DC2BC664B404046D47066ED2240AF0EC3D8BC664B4026AED02E6CED2240BA8ABF29BD664B4055E4D8C87BED22400A55C905BE664B40AEE8969D6CED22409CBB7458C4664B40ACE607AF68ED2240093A42E5C5664B40ABD05A8664ED22403A750D54C7664B40D813C14364ED22408011FD6AC7664B40354B3A5E5FED2240E925D6E8C8664B4050C7F8005AED2240CB57FE5DCA664B40F91CED2E54ED22408C13B0C9CB664B408E1CB70150ED2240A1584EAACC664B401E691D3947ED2240B036A581CE664B4085E8461C40ED22409C5D74CCCF664B4021695FB238ED2240EC25FBF6D0664B40912F04A634ED224075CC6580D1664B4029D6DC8D28ED2240F41FF41AD3664B401FE8E24424ED2240297A4495D3664B404FAFA4E01FED22404B6E9F12D4664B4007BD99D516ED2240688CABF7D4664B402A06F2CE16ED22409ED83FF8D4664B40B38FD3D412ED224054D52651D5664B4073592A740DED2240E9735BC9D5664B40A4F422C403ED2240F79BFD86D6664B406A8586CDF9EC22404D97F72FD7664B4033DE6D4EE9EC2240F7B71A20D8664B40BAA6FA67D8EC2240AFF728E6D8664B405A30D806CBEC2240A30B8E62D9664B40EF0ECC09C9EC224071FE8070D9664B405CC7DD68C1EC2240DB0D01A6D9664B4074DDA025C0EC22405B61DCAED9664B40FFC7DFEEC2EC22401B5EA427DC664B404F5863B8C9EC2240DE19DCCDE6664B406A5642225BED224075322D1DE2664B404F4D0631BBEE224009D5A26AE2664B40138DDA86BEEE2240C3745E6BE2664B409271584AC6EE224091B1A67EE2664B40A0196953C6EE22408EAE9878E2664B40174FE80AC8EE22404A9478FEE0664B40CFB59250CAEE224013C7F073DF664B40661E800CCDEE2240C3666FEDDD664B40CF0F6056CDEE22401D028BCADD664B408408FD93CDEE2240D1EF6FADDD664B40C35A503DD0EE224060EAB16BDC664B402EFA7AE1D3EE22409AF671EFDA664B401F1A42F7D7EE22401E3D6979D9664B406215B958E5EE22408FCF3363D5664B400E906C89E8EE2240B9494A5FD4664B401B354614F1EE224030A159A7D1664B40E6FB2C48F2EE2240B32A5E45D1664B406F93F59F04EF2240EEA94691CB664B406B985C740EEF22400D3D2F04C9664B408D541BAB18EF2240964C317FC6664B4054F28BEF1AEF2240AB18F0F6C5664B40585CE74223EF22401F359E02C4664B40D975833A2EEF2240DC73C38EC1664B40A39B0CC736EF2240B74A539CBF664B40A05CDF4D40EF2240FA19BCC2BD664B40774588C14AEF224031D89E04BC664B4046D8431356EF22404D6B7064BA664B40203A69155BEF2240C09D0FC9B9664B40F971D8AB5FEF2240BDEABC3AB9664B40E93A4D9165EF22408C6C4D6DB8664B4011C3822467EF224076BB6A36B8664B40921FABC968EF2240040B1AFDB7664B40E1E5F36471EF224082FC95ACB6664B4006B3637679EF22403D544C4AB5664B40442CB4147BEF22400E374EFAB4664B400E2B2F727EEF22409EC1F453B4664B4012C5BBF97FEF2240F4975B08B4664B4098B924F780EF2240F0C36DD7B3664B40ED73CCE087EF2240159B3255B2664B40AB3AF01A8EEF2240592484C9B0664B404972912D8EEF2240BF71E2C4B0664B40C18A08D893EF22401239D427AF664B402C0B8A1796EF2240C0F1668DAE664B406712271299EF224006C9C0C0AD664B40C05C2744A6EF2240C1174F36AA664B401F27D17CA6EF2240F1FF1927AA664B40A76EEC4EAFEF22402F88BD0EA8664B405B89DCCAAFEF2240A7822DF5A7664B4077DB7048B2EF2240601EAD71A7664B404D547AF5B5EF2240EF2493AFA6664B40E522000CB9EF2240B9DA880CA6664B408131A643C1EF2240F09B5091A4664B4083649AA9C3EF2240968AA422A4664B406C9F641CCFEF22402BA61653A2664B4013EBBC4DDCEF224048178570A0664B40B3C689D6E8EF22409F4188769E664B40714905AFF4EF224063CE58669C664B40E0D4C7CFFFEF2240F0BF3E419A664B40D7BF4E1708F022400CA5304C98664B405E9261D40FF022400A8A744B96664B409A58CD0317F022408DE0D53F94664B40D192D7A21DF0224063D8232A92664B401345A60521F02240DBE04B0491664B40AC94969423F02240B57E3CD38F664B40E2A20ED824F02240A7ED1BEB8E664B409366EA4825F02240DFED219A8E664B4025947BD925F02240EE3376C28D664B405D48FB1D26F02240FDFB405C8D664B40C66EA41126F02240A2A1E31C8C664B403F5EF97F25F022408AC93E5A8B664B40B7F58B4225F02240A4AB2B088B664B401312002425F02240CCEE5CDF8A664B407AF88E5723F02240D26CFDA689664B40D0EC1CB120F02240BCC6017788664B4099DEF3E01AF0224010FD124C86664B4027214E7115F02240C8E41E4584664B400581D48114F02240DC6E31F583664B405E4AF53D10F022400EC6C18882664B407D9C168E0EF02240B78FA0F881664B4020A4189408F02240FD9BAB9E7F664B40A6098E3206F022405B5B317D7E664B4052D3528803F02240FFDF2C397D664B402AADD36EFFEF224033131BCA7A664B40A0677DC4FDEF22407AD5AF7578664B40BDE64A54FDEF22406E9D4F1E76664B409C7A7A1B02F022403E45F8AC6E664B4082FC76E504F02240140A46DB6A664B405FAD447806F022402ADD6FEC68664B405DDBDBE306F02240DA1E65FA66664B4023AA852706F022402580DB0865664B407556944404F022402B30881B63664B40BBA648A3F1EF2240E0ECCEE556664B402A62E435EEEF2240C1C9E4D354664B405D062FF8EDEF22409E15C8BA54664B40AF6C8848E9EF2240D14866D252664B402E6569E9E2EF2240B0E81DE750664B40FAE7A7B8E2EF2240EA6DB6DB50664B407A2DC719E2EF2240658390B650664B408C154184DFEF22407BE8E71B50664B40F66DD82ADBEF2240CB7295174F664B40B8BD0A01D7EF22405E394F3F4E664B40E96958E0D6EF224030150D384E664B405190CBC9D6EF224010B75D324E664B40CF3D714AD3EF2240EAA7A5504D664B40C354904BD0EF2240D8BBF3594C664B4079AB4047CFEF2240C54DE4E94B664B40AC0603F8CDEF22404BF293594B664B401D427C55CCEF224070D4FF514A664B40AC703317CCEF2240769EAD0B4A664B407E7CAAE8CBEF2240142A20D749664B40C5EAF667CBEF22406CA4C44549664B403D39DD31CBEF22400CE3733748664B40F9BDABB3CBEF224019FBAE2947664B400F2A266ED1EF2240181CA27A43664B40EC6F4116E4EF2240173C17C439664B408166A235EDEF2240775C380435664B40A5F83FF2F7EF224021FD7B7430664B40CE3F6A23F9EF22401B6D21E62F664B408F7C1678FAEF224093CD35472F664B40B3A82D3F02F02240DE0796F02B664B40832523710DF02240EC7114AA27664B40BE054F2F0EF02240B4E4766127664B40EEABF30E0FF0224007F34C1127664B402FB78C8818F02240222E190A24664B40718FE87C20F02240C84D746D21664B405A5E2EAE33F0224095B47A681B664B400CE7334435F02240749EBF0F1B664B40B2C9791C39F02240CAC06B691A664B40B44EBE533CF022401AD2C6FC19664B40C52EDD7A3DF02240584FD3D519664B40F4D0F9783FF0224007908CA119664B406AAF2F4241F022401EE8C06D19664B4045AF81BB38F02240114DDB9418664B4040423E7030F02240E75CE32218664B40D35260860AF022408175C5AC16664B40AA6AB07FDAEF2240869B168F15664B406631424BBDEF22402D5DEFDF12664B4021D619DBB9EF2240ECB90A8F12664B40080B99C2AFEF2240F11C8BF211664B40A8710AD08DEF22400E0F1FFE0E664B4097EBEA8A84EF2240988CE0280E664B40CBC159B77DEF2240C84996BF0D664B40C8B0F0B27AEF2240AFD31B970E664B405C7A31BE66EF22401BFA072A0D664B40982BD65E5CEF2240E15F17BD0C664B4042C7363C18EF2240A0B7A9BF0B664B40FB2E138B15EF224067ADA6B50B664B40F00AC1102EEF2240E5435DFAEE654B4058445C6747EF22406927024AD1654B400BF7E14948EF2240C5279640D0654B40B02BAAC32FEF2240ED528728CF654B40851FA0D22EEF22406BD5C61DCF654B40D42D046A0AEF2240A09BFF7DCD654B4060C4496997EE224014F05D5EC8654B408CDCD99F49EE2240645829E7C4654B405B531C2845EE22404C2476DFBB654B40A719262512EE2240BD949CA9B4654B40D82CB59BF3ED224061B75C66B1654B402714707EEFED2240629CD2F5B0654B40E6CE9014EDED2240E3731D4CB0654B40C2D78E2DE3ED2240E04F4EE1AF654B402FF4C401E3ED2240224F1C43AF654B40C1C42F23E3ED224092F00627AF654B40DFC7A275E4ED2240A55EBA0AAE654B408E69E596E4ED2240CD1BA3EEAD654B406D0FEEE8EBED2240431F21C0A7654B40B6F83D0AECED2240D7D809A4A7654B40FC4C9C58EDED2240DF6CE089A6654B4000A114E2F1ED22403F27388B99654B403AB40473F4ED2240A2F711D396654B406E9A4CE2FEED2240970FD60386654B401545F271D0ED2240AB06AD5385654B40D4D6D732C0ED22407BB70B1685654B40ED72583BC7ED2240F7891D927B654B4063E95BEBC7ED2240F833F5A37A654B40605087EAC7ED22404A14EBA27A654B40427BB9D0C7ED2240DECC86827A654B40E273F5ACC7ED2240B443BE557A654B409898658DC7ED22409479242E7A654B40196F4951BEED224013FC16AB79654B4052FE16E4B3ED22407505D90E79654B4001DE3893ABED2240D7DC399278654B4089E9CEFAA3ED22403F6D672078654B403297FED995ED22404A8DB42977654B40BB144CDC7AED2240F100760575654B400EB319787AED22406F5F81FD74654B4069C5A0E572ED22401F6E9D4C74654B40BAAC52206FED22405F1C87F473654B40ABC698426DED22401080EFC873654B402144FE4666ED22405818CF0E73654B4046F690EA53ED2240598E642571654B40CD07D1243CED2240C0ABC9376E654B4095AF53451DED22400357F3D869654B407B3918210DED2240F0AFE41A67654B40918165990AED2240A9CDD7AC66654B40870CC3DF01ED2240434F820465654B405F5E5D92F9EC2240A2CEB95063654B4092F4F1B3F1EC2240B92B149261654B4017D027C4E6EC2240DE9CC2925E654B408E4EEFFBDCEC224090DA657E5B654B40F415F562D4EC224033C4615758654B400132C0FFCCEC22403F38222055654B403BF1E3EAC1EC224086DE0CBB55654B406785BAB894EC22401584DB3258654B40E0318A7590EC2240B101736E58654B409C63B1408EEC22403DD6EFA858654B4010A652B285EC224034BCA87459654B40539C8C5884EC224057CB669159654B4005DD43E07CEC2240D8C357305A654B40A2627E3869EC2240F937126C5B654B40AB57725D55EC2240B50D2D965C654B4044DF245241EC2240A0FE7EAE5D654B406A7F8D192DEC2240A4FDD8B45E654B40FC5DA4B618EC2240278019A95F654B4014177C2C04EC22402F2B198B60654B40388C277EEFEB2240196EB65A61654B40D871ACAEDAEB2240D097D31762654B40BA64F3A08DEB22405DB1B4C164654B40A4D795408BEB22409822BCD664654B40F9D7D03385EB224098EC4E1165654B40CFEEE9CF69EB224001C17D1A66654B40BC9BB4065FEB22409CDFE18966654B4034D944563CEB2240BA6E23F067654B40B269CF640FEB224012CCC49D69654B40662C7A40E3EA2240422C53236B654B40E79E0639AAEA2240757B52E06C654B408792A9474BEA224060C3B5AA6F654B40FE2B76901AEA224089ED63FF70654B40CC296F3610EA224047D3663C71654B409A4A845C02EA22404E910B8E71654B4062E0251502EA2240E71EB08F71654B400091DF87E9E922404A4A8C0E72654B4047A41582DEE92240931C084272654B40DE29F79AB5E92240A0EB140173654B4093C859EDADE92240CC25C71E73654B40F3FF406A95E92240FAC6907D73654B4074A1218D81E92240755060CA73654B40E5431A8B63E92240CD76271874654B40DA45E27F45E92240F544D94F74654B40119B806E27E92240D6356F7174654B4028DEC65909E922409DBFE47C74654B4046C9998BE9E82240550C7D9874654B40C831140AA5E822401484664174654B40641F4603A1E82240EF16483C74654B400C439DA235E8224075AE57AE73654B40AA525C001BE822403AC9208B73654B407032C707C9E722403295301D73654B400B5A97F0B5E722404E83990373654B40927A9FD64AE72240C113027472654B40A8945C69FEE622407A8CD3F971654B40B9A20C9EEEE622401E2F93E071654B403BCF1353CAE622401066B7B871654B400C1E24E56FE6224030F65D5571654B409692A32860E62240620B4A3F71654B40249E2B6950E622401D9C3C4371654B406B1D08AF40E6224089B0336171654B40CC8BF95B36E62240E7C9088671654B4066433F612DE62240012429AC71654B409CDA81342AE622402A12CEBC71654B40A350826A21E62240BC3FE6EA71654B4028E521F011E62240F9525C5672654B40982E60C403E62240C1DD36D172654B4024CCFE9A02E62240074548DB72654B40D538CF72F3E522403A826A7973654B407EC8FFF7B7E52240E036E7A175654B404E464D2FA0E522403AFEF78376654B40B54BCF328EE52240C8F06A0877654B406B31E2E388E522400271822F77654B404305C31988E522402FF0513577654B40BD03914D7EE52240B567F26877654B40052B25CA6FE52240F75B6DB577654B40426B5CD56AE52240764D52C577654B40663B63816AE52240AF0861C677654B4052D2379168E522403ECC6DD177654B401335664665E52240E9F726D777654B40B5122C5357E522407352E50378654B407857C7C73EE5224072607D2078654B40CF81FE523CE522407A155B1E78654B40F375103B26E52240FD91210B78654B40574AFABF0DE522400ECDDEC377654B40A825B39401E52240D5A9668777654B40D3EC5E69F5E42240AA62EE4A77654B4011D7D58ABDE42240C09C6FBF75654B40E1D1CD8EBBE4224013154DB175654B40E7CDBE0C73E422407220C5AC73654B40819A6F6215E422405FE539D770654B4099A78F660FE42240DC9943AB70654B409F6C0E46CDE32240E5B76DC56E654B406341E041CDE322400DE44DC56E654B40ED14B21461E32240650B11926B654B40AC56C97EF3E22240C9F27A5C68654B401262AA01BAE2224090DA4EBD66654B40AB8D7C11AAE222406E6A305866654B4035342246A0E22240834D3E1966654B40EC21CFF189E222407F7814CF65654B4081E36ECD79E22240D97748AB65654B40C90BF34758E222400CABA75F65654B40E3B5606354E22240F8EE4C5B65654B4053FC88FA4CE22240E957005365654B40F63F80A948E22240EB2B2C4E65654B40F46CC60F3DE222408295244165654B40013BD4F63CE2224055E31C4165654B40DD29ED5E0CE22240186C913B65654B405B5CA122F7E12240984CA91265654B4051E670FAE1E122400C62BBC364654B40A76127F3CCE1224062E1F64E64654B40E4F0C55AB8E12240B1F000C663654B408B163684B4E12240F6E093A663654B40748F217CAAE12240F449705463654B40A2FF7EECA3E122409459B81E63654B407245AFB08FE1224048B95E5962654B40276A99AF7BE122404124457661654B406C62609914E12240F9DA14545C654B40111C4C0794E022409BE5F2EC55654B405F295FE082E02240FD9B461255654B408EDAD4FF76E022407834D97A54654B40B1911BCD74E02240E49ED25E54654B4000FB5CF16FE02240DF82E22054654B408F840D0858E02240752A3B3453654B401060E3C546E02240D6376D8952654B409EA8A3CD43E022402286086C52654B40E777E6EE39E0224045A0590A52654B40F910AA4F15E02240E70BE59F50654B40A8FBDE7B0CE02240D05E5D8B7A654B403939EAF2FADF224063AE629A8E654B40AB4592A4AADF22400EB4444408664B40AA30325AAADF2240896353E008664B407B59544EAADF2240F6074CF908664B40C361160CA6DF2240650568E811664B408B419584A0DF224021C28DC12A664B40F599EC7899DF2240280D5C6C4A664B4012365F5D98DF224017F63A6C4F664B4057BEE51AA5DF2240B72858814F664B40769BD7BD93DF22401AFD4D5772664B40003C4E84E2DF2240DC18F10792664B40205607B2E3DF22408B6A508192664B400FEB7D0E83E0224025C1D77CCF664B407B59C7588CE022405BAFE30AD3664B40E1B56A3D9FE02240472DE420D2664B40EA0FA346AEE022407E8FCB62D4664B407A8F57BEE8E02240347D1942E4664B40DB0FEB0300E12240B1CB1B17EB664B4097AEC91E0BE122400077B459EE664B402726E7830FE12240942EAB8BEF664B403EAFEC4B29E122402788728EF6664B40A507B90C3EE122405B759CCDFA664B402F1AB04D4AE12240EDF0DF51FC664B40618BB75F61E12240CD8E70A0FD664B40D6D413EA98E12240977EB218FE664B40E0AAFE4CB5E12240AEE62656FE664B40CDD88B1EC8E12240E67F81EEFE664B40BCEDC2B611E22240CBC5C82BFF664B40BC87DF7223E22240FD4E803AFF664B40F89D103931E22240F09CAB15FF664B40E2014DE641E2224099688DFAFD664B40AE2B35AE4DE222407BAE38F1FB664B405417F7A94EE22240CAEF86C2F9664B40C17C91C93FE222407FC2EF96F5664B40C9C0886E28E222402794D60AEF664B40EEFE20780BE222400D151737E4664B403390019F08E22240028D8326E3664B40BA15692C08E2224064249028E3664B40027FD974FFE12240B5D98650E3664B4009C20C7BFAE12240E3779A97E0664B400EA8E6EDFAE122401798EF7CDE664B40226F056FC3E1224097C8AD07C9664B4012F9BA7A9EE12240BE219FBDBA664B400D2E0F036BE122403CBCCCD6A6664B4032F5B72A3EE122401E6A677F95664B402810143739E122401C5152EB91664B4076A20DC336E122402494732590664B409D31379021E1224077E09CD380664B407F369E5520E1224016A43EF07F664B401E6641D95EE12240A4F350CA7C664B40DF502C4B8EE12240CBB2A3667A664B404FF3F5498FE122405DA4CF597A664B407FAF8F962FE2224006CDD54AB5664B40B6E11B072FE2224038A2FC52B5664B40A028F65926E22240880D1CD1B5664B405AF91B4419E2224057907B2AB1664B40F25DA3400DE222402706DFDFB1664B4008A3EB312BE222402BD07D9DBC664B40D853B85937E22240A797CAE2BB664B40B5D0AD3E2AE2224039AF9D31B7664B40B340B0DB32E22240F1916FBAB6664B4096E17D6933E222400EA2C4B2B6664B4002B086BF3CE22240D6BB9631B6664B407D5FA54247E22240DD722548BA664B40A3A8FD696EE2224031C79066C9664B409915029405E32240D0878BF703674B40A417B0410DE32240D0459B8206674B409ED5809F12E3224033236C9107674B40BCBE44AB1BE322403AF0FF5709674B40F26B0A0F27E322408884478E0B674B401A6DF1873AE32240F997D9840D674B4080FE2B323CE32240AB87959C0D674B409FF5016849E322401D31E6580E674B40E95A604E64E322401FE02D0711674B401A8A4B7370E3224094A957D711674B40B062DD1D85E32240CB3C570B13674B40DDE153E1ADE32240FB6BD76A15674B400E2FB220B6E3224099FC570E16674B4069C00A57CEE32240C4F357EE17674B4079246E19D1E32240487AF72018674B40BF06DDA51AE422400C638B661D674B408BDD58AE1AE422404FA527671D674B40727EDFD46CE42240DA9B894A23674B40C4220FC988E422404621754B25674B40B16CC36FD8E4224007564BB72A674B402B362FE10BE5224062D79E372E674B40F5F652986CE52240AB9852CA34674B4053E043E972E5224075A2EE3335674B406C68104C99E522403AF3CCB537674B408D2AAB4A9AE5224068016CC637674B40683F37939AE52240D1D7C3CA37674B40976DAB2BF8E522408224A7623D674B408020812100E622403A8F963F3E674B4024F9254D00E6224052D951443E674B40B90C054303E622407B60CD6C3E674B40A0D79D642AE62240D6F7DF8340674B4076A235853BE62240ECFB339941674B4020BD0B903BE622402309E19941674B404890FE598AE62240C0FD4B9546674B409CF8FA75C5E622405C7229524A674B4006DFA4D0FAE62240F2D5D8B14D674B406E597F9A50E722407D66521353674B403867AFD953E72240A80BFD1B52674B406DBA3BEC53E72240A4A87B1652674B40A25EC69F5AE72240FBD2001850674B402829AF0C6CE72240023298E84A674B40D178FB876EE72240C1F8902B4A674B40B7ACE2E16EE72240CF7BD1104A674B40B9C235D270E722402507436C49674B4077EAE4B78BE72240F4AA578140674B40CF158EF3BBE72240B647728330674B40C3BEBC24C7E72240783788A22C674B40	Flensburg 2	\N	fl2
5	organization	102	0103000020E610000001000000E9020000BF447E1A1BDD2240205BFC16EB654B40753ED8A351DD2240A294E4E2DE654B40512B27864EDD2240ED8A8A8ADE654B408AABD99B7FDD224019E56779C9654B40090C60127EDD2240A7F53D0CC9654B40854CB5D87BDD22404C32326EC8654B40B46E2D3F7ADD2240288E91FCC7654B407182513485DD224071F1318BC3654B40CAD36BB489DD2240075705CAC3654B40C17A71078FDD2240D1EE5714C4654B40E70EBC688FDD224022979BE8C3654B40323FAA5599DD22408DACF26AC4654B4027817DD098DD2240F550DEA5C4654B402192E627B9DD22408A5C4B5AC6654B4032A80238C7DD2240BBAB1018C7654B40B26E747CD2DD224001944FCCC2654B405F60F561D4DD2240B499A5CFC2654B40F2DFBB76D5DD2240CAB6DB65C2654B40368BD302D4DD2240608FC939C2654B40CE23CDDEDCDD224023A79BD3BE654B407677702CD7DD22408C37D485BE654B40C3A0D2A4C3DD224064BA39F8C5654B402BAA2C3BBCDD22404DA97294C5654B40BAA095CAADDD2240B4C014D2C4654B4022CBE412B2DD2240AEDCEA09C3654B405B1A0AE8AADD2240085C22ABC2654B406C7C0A70A6DD224079DDBD6EC4654B40CC84B3E59ADD2240409E62D2C3654B4090E048849ADD2240E1542EFBC3654B406801065490DD2240042CE384C3654B40CDBFD6C490DD224099060C56C3654B409AA27F578BDD2240CFAA950CC3654B40161233B3ACDD2240BAC22AF8B3654B401D8BED03C0DD22403D71B4E3B4654B401DF34DDEBFDD22401B2376F2B4654B40DDB67E26BBDD2240DE2EF9CBB6654B40C502B993CFDD224087B385EEB7654B4021FD6808D3DD224067DB14A7B6654B40E1CAC8AACCDD2240D3C6E74AB6654B4009D728F0CDDD22402D3BF9ACB5654B40B7CCB971D6DD224014D24019B6654B40B53B12F2E7DD2240EAE8F05FAF654B407CC6F79FF3DD22405E07339DAF654B4006134C95F4DD224079C438C5AF654B40E1AF3FAA01DE22400BFA96E7B1654B409AC50F6C00DE224066CA6AEBB1654B40BA887F9207DE2240CEBBF4CAB7654B40D25E3B440FDE2240534D189DB7654B4089AF657409DE2240B306A5CFB1654B40716D75FE03DE2240BF526CE0B1654B404842BE42F5DD224001978176AF654B40FE595D65F8DD2240D37D3C0AAE654B407CE97377FBDD224002D0B236AE654B40B6835551FADD2240F0E073DAAE654B406AF678AD0EDE2240640C717AAF654B4097DF785623DE224004FD815CA2654B4082A50F832BDE2240895707A2A2654B400B5492F52CDE224010C22BC6A1654B40276CF11425DE22405A81277BA1654B40F99B79492ADE2240DB1ABD429E654B40277CF54F32DE224056D237889E654B40527E0AE833DE224084A053AC9D654B40A0BB2E072CDE224060A7CE5B9D654B404C2DC0EF30DE22400C6DF6289A654B40930BB38438DE224096E70B749A654B402BA2ED423ADE22402D9B308D99654B40CD7F5A8832DE2240F21C124D99654B4038DBC0BA37DE2240833F47E395654B4094C7CAE73FDE2240BDAFBA3396654B40D9E7DC8041DE22405DE6D76295654B404866ED7839DE224098525A0795654B40D7802E3949DE2240FCA6421C8B654B402B7FBCF350DE2240E0F7605C8B654B40D08EFF6552DE22402E8C047B8A654B4041AF4ED14ADE2240F40A70358A654B40839E816452DE22408BB0C33185654B40BFE7CF5C56DE2240490BFE9082654B402A76247937DE224070FA56F781654B402B5025FC50DE2240D4873E5B4A654B405734390266DE22405CD1415E41654B4005402E3B6ADE2240B1421C903F654B404BDAE26A66DE224054BDAB5E3F654B4015AC667E63DE22406FCFC5383F654B40EF4D58C766DE2240A775E49A3D654B40A59997DC67DE2240457F6D123D654B409CDE242967DE22401702C1BC3B654B40339091E266DE22404E655B363B654B40D689781C62DE2240C598DE7638654B406445213961DE2240517DFDF337654B40D91099825CDE2240F88F42E736654B4090648DA259DE22404A0FB9E135654B4024D2E18C4BDE22405569962827654B40FCEC6D1F57DE22400F5C81B41D654B40E1B00F315ADE224030F2568A1D654B4060EB11D676DE22402A45252420654B4023F3D00C7EDE22400DA6D1CB20654B402E5A516784DE2240CEA897451F654B403F4BE51178DE2240F2AE45241E654B4090BD656A5EDE2240C87F7ACA1B654B40BCE6D62C5BDE224027ADC2601A654B404CFD70887FDE22408F0BB00B12654B400CB67ED684DE2240966D71D410654B406316C6D68BDE22405B15A3AB10654B404DB2B9BFB3DE224042233E4B14654B40ADBCBC2EBADE2240C1B971C912654B401971E4B38ADE2240B239BC6A0E654B40D2C67E5690DE22405731433B0D654B40BFA069B8C7DE224024BBB89401654B40BC38CE03CBDE224098E920DD01654B4028E87F37CBDE2240B15791E101654B40FB922223CCDE2240C9EA90B001654B407A432288DCDE224023CBC547FE644B407B13FB8A53DF2240D6E43D9CEB644B40958B328B5EDF2240D1F4B055E9644B40FB24B9146EDF2240B380EA1EE6644B405BD9B0B994DF2240F8D07720DE644B4050B3BE3B94DF22403F4D6A80DC644B40480F716C93DF2240140B65D3D9644B40024C865BB9DF2240571FD8A0D3644B40BBE42B7705E022407CE76A31C7644B40D662372A14E022406963C5AEBF644B409C353EA41AE02240DF23A75FBC644B4099DD24941DE0224053B5ED4FBB644B40C0822F2027E02240CD57ABDCB7644B4095EFEFF488E02240AE1B6E8194644B40C1A582AC9AE02240B4EAD2EE86644B40ACB37F9EFDE0224055ED86314C644B405114E1BC13E12240D14B43A642644B40CCEB5B9E1DE122403EA7A4033C644B407E25595C23E12240C5F88B3135644B40A483E05824E12240566EBDC732644B4047C40A0925E12240D5964AD431644B406CB2B87225E122406FFE404231644B403778062727E122405A7F5FE72E644B40208C14AA2CE12240FFD63A7C22644B40A7EF1AD029E122401B3686401E644B40602D860F28E12240F979D4E91B644B402EA8DEFA27E122404E3E51CE1B644B4085F4E58324E122405F93A22F17644B40C933871524E12240DCEF8D2C16644B4026F1A82123E12240875B52F213644B406418C42023E12240D3D0037512644B405EC8D81E23E1224049DA427010644B409E65931E23E122403273101D10644B40CAB2DD1D23E12240E94CC5600F644B402EC79D1923E122403AB65C0E0E644B40AEF9541821E1224063F9A5830C644B40F76209EA1EE122403C9A59D60A644B408BDE46F419E122400FABFA0507644B408E0F4D4510E1224063DDFE4301644B4097C390AD0AE1224085D118ABFE634B4062F2FD4705E12240FA35085CFC634B404D230C67FFE022409EA74B37FA634B4096653823FBE02240FEB5CA9FF8634B40A7FE51ABFAE02240C49D0973F8634B4023695553F3E022405C07AE49F6634B40C9A6B876F1E02240C0F5D9BFF5634B4036B96F42EEE022407974DAD2F4634B4016DCCBB2EDE022404B1FA4A9F4634B40C12C378AECE02240CB1F7B54F4634B40B38F6501EBE022406000D8E2F3634B40C5E9A629E9E022405F8F8A5AF3634B40A658CC83E7E0224075D4D2DFF2634B40B8D0CE25E7E02240F70EA6C4F2634B40E87FB73EE6E022405B6FDE81F2634B40290928D5E5E02240E2765B63F2634B403D46B28FE0E0224076124CDDF0634B405BA4CC8EE0E02240E77310DDF0634B40593BE68AE0E022405ED627DCF0634B40E8A2F6BAD2E02240661C629CED634B402CB60099CDE0224003424B67EC634B40809ADC87C7E02240D2CD4F3CEB634B40418F08C0C3E02240EA684480EA634B40772CF443B9E022409003C776E8634B40B6E8C374B1E02240DCF47FF1E6634B40D34A4B98AEE02240D3F8E771E6634B40A0C5DE5BADE022401015473AE6634B404B64C803ACE02240697786FDE5634B405ED66197A5E02240F0EDBBDCE4634B40B1F2F7A9A1E02240543E002CE4634B407C0D38399FE02240F63C2BBEE3634B40A47FAA989BE02240D74BF71AE3634B4090B53B159BE022400CFEB603E3634B404153B1DF99E022406C402ECDE2634B40FDE2588B98E022407DF64291E2634B402381095094E0224068330DD3E1634B40A710351891E0224073EA4242E1634B40B8D1FBF590E02240F01D3D3CE1634B402222515880E02240B166DF86DE634B40EE48287A66E022406F7F3C69DA634B40AB24CF3054E02240283F99CDD7634B40555357FC43E022405687F37DD5634B40F59B92AD2FE0224053C7656CD2634B401071E4C92DE022401BB1B32FD3634B408415F60C23E02240FA00BB85D7634B4098F9C23521E02240DF6E9144D8634B408246332A21E02240EA1CAA48D8634B40AD92BBAE10E02240D5BDAD22DE634B40110767DF06E0224039F5409EE1634B40DF41D8E8FDDF2240D2B8DFCCE4634B40ED9789BFF7DF2240204E24E7E6634B40B5FC0AF9F5DF224016073B82E7634B4014FF800AF0DF224006215541E9634B4095764701EDDF22402C622926EA634B40837EA908E3DF22407B6596B6EC634B40EEF3E6E6DCDF2240AB0D541AEE634B4042ECC066D8DF2240F4EF691FEF634B400AF52217D8DF2240CC327531EF634B409AEEFA58D4DF22402CA695C6EF634B40BA89A637D1DF2240C660FE2EF0634B404F2D816BD0DF2240C2EA9549F0634B40F2772443D0DF224055A6D84EF0634B40A42FF03ED0DF224037FE584FF0634B40F4EC4D33D0DF2240F7759050F0634B405AF858EAC9DF22400B1CA6F8F0634B4037ED3B0FC3DF224017B62583F1634B40A9CDCCCEC1DF22407B634F95F1634B40F86492C9BBDF2240BC74A7ECF1634B40159338CBBADF224083D4F1F5F1634B4081A94BFDB8DF2240F536D306F2634B40FCAEB4C1B8DF2240CF2E0109F2634B40DCCE727FB8DF2240CB836C0BF2634B40355BD136B4DF224055E57D33F2634B405D36A960AADF2240CEE33292F1634B405C1A21CB81DF2240312A6186EF634B40700B259642DF2240E85A8D56EC634B401903F09C3FDF22404AA52B30EC634B40C682B3BE23DF2240560F76C8EA634B4082109D5314DF224080A77001EA634B403702A7C3F3DE224042591F5DE8634B4081C68B88DADE22404B976E17E7634B4037497AD78DDE22404BFC7439E3634B40F187C5EA88DE22402961CD03E3634B406F9BCB5975DE22408D7D8741E2634B4017052A2D6CDE22401DA55EF4E1634B409E5EA6F566DE2240E2BA7DC8E1634B40F06C238266DE2240EC6EB2C4E1634B400DEF9F9861DE2240F627619BE1634B4004E2BAAE4DDE224075339C11E1634B406CD8D6A339DE2240120669A4E0634B40E4F8857F25DE22408133F453E0634B407D9A9C4911DE22408FBE5C20E0634B405028B909FDDD2240B622B609E0634B4077D9B6C2E9DD2240649DB90FE0634B40F78D79C7E8DD2240CA470810E0634B404CA411CDDBDD224038F42104E0634B401BA93C75DBDD2240A61B7303E0634B4015EF0C47DBDD2240FE721503E0634B40C4F123AEDADD2240DDBBE401E0634B40F0E9C239DADD22408CCBFA00E0634B40185563B5D2DD2240B354F2F1DF634B40C2320BA6D2DD22402F4FCDF1DF634B402BB3A4CDCDDD22409A4419E8DF634B4069825E5DC3DD2240BEB4F3CBDF634B4000C52F84B6DD2240B63EA392DF634B40C7BEBAC3B0DD2240E856FA78DF634B40782BC511ABDD2240C40C6A55DF634B401CC69351A9DD22404BBF7B4ADF634B404A8C764A9EDD22407D0F9E05DF634B40F8A7BF359EDD22404BC9A80BDF634B408ED697109EDD224036996916DF634B40F3E24CD99DDD2240CB587926DF634B40F0EAF6C89DDD2240E932352BDF634B4042D462D99BDD224036FB0EBBDF634B40EE0500AF98DD22407EC645A6E0634B40DF73026E97DD2240E7727103E1634B40FE2AF66D96DD2240DE41815BE1634B405AA64ECF91DD2240CE0147F2E2634B40972E707791DD2240FED57E10E3634B4086FD959C8FDD22402F1C82D6E3634B4066B8056D8CDD22404FDA9C2AE5634B403D9A9D9588DD2240E984402DE7634B4068C20A5488DD224085D8944FE7634B40E8A19A2B88DD2240032FE272E7634B40EF8840D387DD2240899EE7ACE7634B400E0F27CE86DD2240C1A1A680E8634B40FB0E202B86DD22407D0C325FE9634B40B333CE1186DD2240A7D2FFCDE9634B40A79FCDC685DD2240B621C259EA634B4006CD45D085DD224064B804EDEA634B40938D05B185DD2240D5BFDD75EB634B404A1000DE85DD2240ACBD05C3EB634B40D4CD00E085DD2240CFC80CE2EB634B4050BD466186DD2240C71333A4EC634B40441700E486DD224067808E68ED634B40F64EB0B587DD22403BB43365EF634B406CE25E2089DD22406E7A0B60F1634B405CADF21C8ADD224044204557F2634B40CC661C288ADD224017983A62F2634B408E4361238BDD22401CE02058F3634B4081C1BCBD8DDD224068047F4CF5634B4089012B3C8FDD2240B4948A5EF6634B401BBBC7568FDD22403C45186CF6634B401EC0184C91DD224050FB806BF7634B40F03BDECC91DD2240580AE49DF7634B4019B2652292DD224050AD5ABFF7634B4003AD189393DD224083259E4FF8634B40E14D60EA93DD22401813C271F8634B40A2C4B8B994DD2240F164E5B2F8634B408FDB345296DD2240E6F78A3CF9634B404E95832899DD224035575B04FA634B40518B03A59CDD22402346FBD8FA634B40583C7A2C9FDD2240656E0D5CFB634B403E7349CEA1DD22405469FCD8FB634B403714F7F4A2DD2240CB1B620BFC634B4027F4EE95A3DD2240764C2529FC634B40B5A2A342A4DD22408DA87044FC634B40FA81EC0BA6DD22401C64A392FC634B402535F014A8DD2240789E0DDFFC634B40D9F0538DA8DD2240CE4D12F2FC634B405E4F78AFA8DD2240870A78F7FC634B403A108EEDA8DD22408308D1FEFC634B40E7E3FA00A9DD224063F6A901FD634B40DE961FEFA9DD224007BB4A1DFD634B400183201DB2DD2240299F0B15FE634B404FC2620DBBDD22404544EB42FF634B40C3FFF71CBBDD22408B6EFA44FF634B40C561A22EC3DD2240E52D857400644B4050353AA8C3DD2240DD4C628600644B400653F639C8DD22400CF7DE4501644B401EAE18A1C9DD22409EA4168001644B409B9DCE71CADD2240C449D2A201644B4020F8B4B8CBDD2240A25855D801644B40785E5AE7CBDD22401BDFFBE001644B40D39B6736D3DD224069B1F63B03644B4047314B80D4DD2240C1C5237903644B4033C15D2CD5DD2240E970A4A103644B4083CC5FF1DBDD22401C19953905644B40387662F9DBDD224082BE753B05644B403604360CE2DD224097BBB81907644B40F3DDD96EE3DD2240CE936BB007644B40E5BCD713E4DD2240D3BD84F607644B40E8F486A5E6DD22406389FC0D09644B40B529FE58E8DD2240740B5EC20A644B40FA4C8CC1E8DD2240768876040C644B400C401AADE8DD224080AD273F0C644B40DBD15BBAE8DD224042D5077B0C644B402FCD995DE8DD2240E4BB77230D644B40E842AE28E8DD224001598ABB0D644B40B71DE1DFE7DD2240A4A7E5070E644B402F76718CE7DD22400E966D5F0E644B40CC85032AE6DD22407A16D0680F644B40C79B0AB1E0DD224055F3179E12644B40C486C563DFDD2240D057786113644B40FDE44C77DDDD2240B8EF418214644B401333936DDDDD22408E26DC8714644B400F7E3D70DCDD22400BC4C77A14644B400869EB40DCDD224036B6557814644B40C951E232D0DD2240375CDBD813644B40AE646032D0DD2240616430D913644B40BEC9E32FD0DD224002D2D1DA13644B40F58E071ED0DD2240D4589EE613644B40171111D1CCDD22405302DE1416644B40C0E9D937CBDD22403A7F312317644B406C268C85AFDD22405A8F5E7029644B4061A84BF7ACDD22400C0AAA202B644B406A0EB0B5ACDD22409B7A044C2B644B40DF3D36A6ACDD22408E093F562B644B405D7559A5ACDD22403FE8D1562B644B40B2F8BC30ADDD22405E0BD2632B644B4073D56055ADDD2240508899662B644B4062BEC930B2DD2240F5E9F5C42B644B40A2107507B4DD2240CC64AEE82B644B4023F8ED83BCDD22400B7644B02C644B405C4D59E6BEDD224020C32FF32C644B400A47340FC4DD2240EA9900842D644B402B19D386C4DD224090541E912D644B409AFE5B01CCDD2240A7CF96892E644B405C9441E7D2DD22408FDC0F982F644B40AD518A2CD9DD2240218BAFBA30644B40F25F1EC6DEDD2240BFD67CEF31644B402EA8BDDBE0DD224087C2CE7132644B40DB3F4183F8DD22406644A43838644B406CBE0BD2FCDD22402BFAF24539644B404DAEF03606DE22405F96ADFC3B644B403EA6B08F25DE22402025DB0A45644B401A93141731DE224045F7715F48644B4016213E1831DE2240B28BC85F48644B40C90B278C32DE2240375E39CB48644B40ED5704E732DE224007BC79E548644B404663B5EB3ADE22400E936F364B644B405E2CD1163BDE2240D66BE7424B644B407C1A6FA747DE2240E9DC16E44E644B4088F6E8584BDE2240EA07C12450644B400684F1274EDE22401DED767151644B40E827660D50DE2240CE4FE1C652644B405762B72550DE224006BB0FE952644B404E801A2650DE224024E092E952644B40AFA1C33050DE22400ACF94F852644B40A98E540451DE2240FB01992154644B40C1D14A0A51DE2240CED1267E55644B405C734A1F50DE2240DD440BD956644B40809D93454EDE2240AE14CE2E58644B400973D0E54CDE2240CE5A75D458644B408C84CE203ADE2240D6E4DBBA5F644B405A770B063ADE224054C2B2C45F644B407D1122692DDE2240501CB66764644B40009DF9B72BDE2240AA642F0665644B40B73E2DB62BDE2240DBC6D50665644B40B63607402BDE2240FEF8283265644B40BD7E49042BDE22401A3C174865644B40FF46EAA72ADE2240D787B66965644B400C1F57DFFFDD22408EB883F274644B40580E57D0F9DD2240C92DAB2577644B402CF1D9BEE7DD2240267FD81B7F644B403F725E7AD7DD2240BE32DD4686644B4004B68AB0BEDD22408067073391644B40281C2E11BBDD22408082A9CB92644B4000A3E667AEDD224011B3D55F98644B400C8C5671ACDD22407C4BB81999644B40EEB146EFA9DD2240276069CA99644B40D2A6BD47A9DD2240D6C4E0F299644B40B8A10EDFA8DD2240276B2A0C9A644B40397AE951A8DD2240DADF402E9A644B4007A9BC2EA6DD224093576FB29A644B40DCC782C2A2DD2240C42100A99B644B40CD473240A1DD2240834555449C644B40907DD039A0DD22403F62D6AD9C644B402B8C9E9F98DD22406B4FAC7EA0644B408EA7F71797DD2240BB4E3D43A1644B40BE4F61D593DD224023BB3AF1A2644B400CB1140F8FDD224084B7F466A5644B40743FA1548BDD2240F79F8A89A6644B406A0AA7D38ADD2240C40FCEB0A6644B4045F0176B89DD2240C094961EA7644B409D42766183DD22404704F4CEA8644B40DCA4FDF37CDD2240183B8D77AA644B40778CFD6A76DD224035181207AC644B404C557C2476DD22404038E817AC644B408DDCA66070DD2240B6932591AD644B4026B102E16BDD2240D5D582B7AE644B40A62161D260DD22403F9EA945B1644B40389B1EFE54DD22406A4411C1B3644B404B92145254DD22408036F2E1B3644B401E6B66BC53DD2240F1978DFEB3644B407B8B2D6A48DD2240F3E47B28B6644B408492FBD03BDD2240689B866FB8644B401FF9F8FC3ADD2240B4FF0E94B8644B4025D860D92EDD22409B3E67ABBA644B400FBB3A8521DD2240B14FCCDBBC644B40D19C66D613DD2240D04F6400BF644B4083AD089B11DD224068074847BF644B40EF75B8F110DD224073B4485CBF644B40050170E708DD224068FAA75BC0644B400450C7A3FDDC224006D126A8C1644B4074E4360FF2DC2240A30470E5C2644B40A970892DE6DC2240807E1A13C4644B4097F1782FDCDC2240D92BD5FDC4644B4026418F77D8DC224015EBC65FC5644B40CABE095BD8DC2240B159B662C5644B4060915AC7D5DC224053C296A6C5644B408F1BF6E3CFDC2240D5B07867C6644B405CFD0079CDDC22403DDB6BC9C6644B4067495196CADC2240B2264F3EC7644B4068CE9BEDC5DC22407EEAB228C8644B40324A77F9C2DC2240C3F8EFDDC8644B40337D9362C1DC22401F14CA53C9644B40892D5AE8C0DC224039B33673C9644B403B7C01B6C0DC22402711C485C9644B408B696E2ABDDC224028C328D4CA644B409EA23E3CBCDC2240C8409B41CB644B4036BFB95FB8DC2240F21CE807CD644B406B4B3417B8DC2240337C3729CD644B40123ED3E99EDC2240AD4D35BBD8644B40FCD7F0C99EDC2240FE6CE0C9D8644B404F0C51E583DC2240AC019F25E5644B40AA4E8ED971DC22402F3D8F70ED644B4053A1C84869DC2240570E3660F1644B40EDB87B4E65DC2240CD5758D8F2644B40AED81C4865DC22405FFDB1DAF2644B409980EF2C65DC2240EB00BDE4F2644B405D1C031F65DC2240E4A3DCE9F2644B405EBF9C8C5FDC22400FBCEA5AF4644B40269424BE5EDC2240A2497F82F4644B4097C5F4AB58DC2240ADF981ACF5644B407AF86DA957DC224092311BD2F5644B402BF3AADD56DC22409BA6BBEFF5644B404976E99D50DC2240FEE95CD8F6644B407868072E4CDC2240FCBFB055F7644B409082B38847DC2240863AECD8F7644B40A22B89973DDC22402E3F66A9F8644B40D36789F935DC22409A50B819F9644B408914D99A34DC2240D0F3EA2DF9644B406C3FCAF932DC224032AAEF45F9644B4071A4E7E127DC224066BA9DABF9644B40632649B919DC2240AC1C0A08FA644B40B633CA6F06DC2240DA6EEF85FA644B4028C5EC00FFDB2240157CEDDCFA644B4000023822FFDB224074469BB5FA644B4088598CA765DB2240605F639FFE644B4052D5A6BE42DB22406AA147ACFF644B4072344B7C15DB22409325E10801654B406BD6593715DB22404095DD3301654B401D47A9C913DB2240553ABF3D01654B4030C43EBB14DB224069C3488101654B40B921899F14DB224079A38E9201654B40247EB3C012DB224008CC33BD02654B405B68CF5C10DB22400A8FD23A04654B40813D50E70FDB22405B841E8404654B40F0863E6809DB2240CA3B579108654B402167673E1EDB2240E319AB5909654B40DAC4C95823DB2240AE63499B09654B404B96C51928DB2240F6DC3BFA09654B404FEA157D2ADB22403C1C2D3E0A654B4023511D262BDB2240E8DEF6500A654B40ACBDFE612CDB2240558712740A654B409E57401530DB22406633A9050B654B402DE2381B33DB2240C45A42AB0B654B4069A2006035DB22401E4E9A600C654B40A14193D436DB224065E807210D654B401D7C636F37DB2240DBCB8DE70D654B40B487CF1238DB224064A8D5CA10654B40DFF8229138DB22406D6D500613654B4023A7854D3ADB2240EFED20CF14654B403A9740F53ADB2240FBD0CC2F15654B400A47F2863BDB22400D00C48315654B403631F8553DDB22405B7B9C8E16654B405022D0A141DB22406410B63F18654B4012D96A9B43DB22401CE300D418654B407A6CC6CE44DB2240F6AB282E19654B408BDABD2447DB2240B8CA8FDD19654B40F3666FAD4CDB224071B40D231B654B40A3C17D1652DB2240B0449E1B1C654B4053E89EA352DB224004BEF1341C654B40F6E9533253DB22401F328E4E1C654B40FFACDC9C5ADB22408831045C1D654B405DD942D362DB224081C7C5471E654B404DE578A966DB22407F2DC9991E654B404B36B95668DB22404C70CDB41E654B408778525C68DB224007CF28B51E654B40300F1EC668DB2240AA29D0BB1E654B40CA1CD5C968DB22407F140DBC1E654B40E30A7BB96ADB2240DCEF3EDB1E654B40B72EFFF56EDB2240B3D6530B1F654B4087612A5173DB22407FF866291F654B40BA3FACBC77DB2240632419351F654B409FBF201C7CDB2240A6AE572E1F654B4097F61B2A7CDB2240E338412E1F654B409F1071AC7EDB22408776C31F1F654B40BAC2F88A80DB224008B8F7141F654B404BC0173C82DB22409E19C6031F654B403E9BD1D084DB22402A188DE91E654B40DB14154E8CDB22406F0FCD7F1E654B4026E152408DDB2240F08570721E654B40F63FB6A791DB2240A07142341E654B40CDEAF01092DB2240E1C04D2C1E654B403BD4A83192DB22407410D5291E654B402DE45B1393DB2240F5BFC6181E654B40377B59E593DB2240840DE9081E654B40646936D59DDB22402050A8481D654B40485C8C3EA1DB2240DAD97AF21C654B4020EF8F2EA9DB224047AEFA291C654B40AAB74331ABDB2240F50F3AE91B654B40114C794FABDB224030586CE51B654B40DE3FBF8BB3DB22408E2E2EDC1A654B40545BC681BEDB2240C57A38B219654B401A715FCAC2DB22400EE5414A19654B40403D70D5C4DB22403A3AAC1819654B40CB184DE1C9DB2240F9F2319E18654B407E341DA2D5DB2240245BDFA017654B40E4B7AFBBE1DB22407207F8BA16654B407ED7DEFFE6DB2240E923EB5516654B40217222ACEADB224047B0710F16654B40B99A9404F1DB2240AD78AE9515654B40A9F3339D00DC22408E89C68714654B40809EFF7E10DC2240FD8FB39113654B4087B372061BDC2240BAD1FD0013654B40C9B8ADC51BDC2240D051BAF612654B40485EC92A1CDC2240D9054DF112654B407FCD26581CDC2240ACEC6B5013654B40AC4B3CF020DC2240CFB6A5F11C654B40250AB4A315DC22404A372B3026654B404126FF9C15DC22401191AD3526654B4043BEFC9B15DC2240994B7C3626654B408FA0863715DC224011A9AD8826654B409B7AC21D14DC2240478338B332654B402BBCEDB500DC2240267160AE32654B400FFEEA4EF4DB2240847E2ABD32654B40C9218BF9E7DB224058B39CEF32654B4029A67795E7DB224032A05CF232654B40619C62A1DDDB22403A516B3833654B408E03E4C8DBDB2240A867694533654B4005B3FBCFCFDB2240571209BE33654B40B6E6F2429FDB22400AE53CF335654B40949F962599DB2240DD78D24036654B40E03E48A099DB2240067A306C36654B4039B896C2A1DB2240C72B444C39654B406F41A747A4DB22403D445BDF39654B4043097F48A4DB2240D0528BDF39654B40C738737BA4DB2240775B29EB39654B4067199436A8DB2240DF737D563A654B40613F4F5FACDB2240B7878BA93A654B4004E13A60AFDB2240866F7CCF3A654B4042A036F5AFDB2240E52FD5D63A654B40092860D8B0DB224020A80BE23A654B40F325A982B5DB224009A96DFE3A654B403738C121DADB224071BFCC123B654B40A4B42876E8DB22403796C51A3B654B402F1DFD1EEADB2240DE9988293B654B4091B63054EADB22409BF4602B3B654B406E932C35EBDB22408D6833333B654B40DA869A16EFDB22406842B7553B654B40E476AC65F5DB2240B22E19B53B654B407CE81E3EFBDB2240D9B0B4363C654B406243FC0FFDDB224020A27C6E3C654B400867A2B2FDDB22404051F7813C654B40EB77940EFEDB22400C5FF98C3C654B40004E7B7D00DC224033928FD73C654B40BDB2B40405DC22401EB5F1933D654B406CD7BC0D07DC2240538A2E083E654B40303C34DF07DC224049DCE8363E654B40217E19B908DC2240DFBE83673E654B40BBA9CC840BDC22406E24664D3F654B4003F128160CDC2240ED4F14993F654B4072683D740CDC2240448616CA3F654B40E10D3F570DDC224084254A4040654B40E40DEF750EDC2240EE20666C4E654B4055AD45F611DC224035DAC0F667654B407A3EC39915DC2240FEB959CB84654B405FC5799E15DC22401108A0F084654B4070893ECF19DC2240B41FFED084654B40455FAD992BDC2240D78127D88F654B402AD92AA32CDC224087791F7290654B40D9F4F78D2DDC2240113C54CD90654B40467CD6A52DDC22400FE13AE090654B406401B5A82DDC224055036FE190654B40D973483031DC224071A620AE93654B40E597B94331DC2240C9C08ABD93654B402089925831DC2240EEE119CE93654B40AEC1E3F132DC224033AA8CB795654B40AD75EE963BDC224056BFB6729A654B4056495BFC3DDC224026DD70C29B654B40BAAFF67440DC22404DFAA61C9D654B40A5C6145E43DC22404DAD18EF9E654B40AA631F2E46DC22403C047CD09E654B4096C4C12B48DC2240F6A2D1BA9E654B404112F13F4CDC22400503C5A2A0654B40216700864CDC2240FB16F4C6A0654B40FDE161714DDC22401EA84F53A1654B408CD17C1E4FDC2240576B3353A2654B4026E192204FDC2240EFCC6554A2654B401531E77350DC2240B33AC917A3654B401F73506751DC2240EFEFCC82A3654B40B0266F6851DC2240026D5D83A3654B40FBC6A7D852DC2240F7C41D40A4654B4011FCFD7854DC2240EE2E4B1AA5654B4013E29CB756DC2240690D781AA6654B4059E8910457DC2240B817651EA7654B405DA46E0557DC224054167E21A7654B40D73A7E4E5ADC2240848C98D5AA654B406FCA918258DC2240C0E3AAEEAC654B401BD1AD8058DC22408D0FD9F0AC654B40F6B5B8B255DC22405AAAB62FAF654B4053EEDFE754DC2240A85227A4B0654B40D2BDCEF24CDC2240B2AC1662B0654B40C659F3F149DC2240D7B9AA3BB0654B405E7D8E6E43DC2240E17FFADCB1654B4063EEC45743DC224084F857E2B1654B40226727B233DC224089FA9891B5654B409FA91A3331DC2240AE0E42D5B5654B40FF26081A2FDC2240593E155AB6654B40FACEE93526DC22404EEC018DB8654B401E88C9B025DC2240CF556FC9B8654B400ECE200C21DC22403D6E5EC6BA654B40A97B8F431DDC2240EB169BE2BB654B404AC38E4413DC22404E48F407BE654B405117AFCE0EDC224055171747BF654B40061A24E60ADC22407058A192C0654B40F4F668A309DC224081E2FA64C2654B406D586B690FDC2240AF9B34BEC6654B40B82170891BDC2240E205F802C7654B4021AB70941CDC2240225F1D19C7654B40D5DAB0A116DC22409DC3787ACA654B40B037ECA616DC224041B4C67ACA654B402250131A17DC22401C957381CA654B40ED7EB2E412DC22400E531984CC654B403F26B7760DDC224080AD515DCE654B402601230B07DC2240C9965240D0654B406F894CA406DC224045FF835ED0654B40E412057103DC22406709914FD1654B40CB353F7003DC2240F609CD4FD1654B4075A248A902DC2240465B7B9AD1654B40CC91EF7800DC22404C89356DD2654B4033B9BEAE00DC22407A1CF586D3654B400F0EBDC400DC2240106DDFF9D3654B403CB506E400DC22401C7CDE9CD4654B401FE0A8E500DC2240060E9EA4D4654B406B5AB5E202DC224017B20ED3D4654B407F07FD2D04DC22408EDE47F1D4654B40F9F7FE0405DC22409CE10E07D5654B40A1692A7505DC224008213611D5654B409BF458A905DC224094EEEF15D5654B403B7C495B06DC224065457C26D5654B401D7FC42907DC22402DB3C93BD5654B40FB2F126508DC2240DC2D515CD5654B4022D0647D08DC2240381DD45ED5654B408D9E461209DC22405695AA6FD5654B409B3F583909DC22401E5F1474D5654B40AF53C1CD09DC2240285EDF84D5654B403CF017CD0ADC22400DFEBCA1D5654B40021F50F60ADC2240D9E867A6D5654B404D84F9600BDC224042DED0B4D5654B40023429070CDC2240081F43CBD5654B40914439FB26DC224000FB5E6FD9654B4081E94B292DDC22402B37BD44DA654B40B1662CED37DC2240718769B8DB654B4081ED37EF8CDC22402637582FE7654B40031DB48E92DC2240A7347AF1E7654B405A78D9549FDC2240046F7FAAE9654B40194A6746B0DC2240F47B2CEAE7654B40C24FAA10B5DC224016C61969E7654B40B65A6421B5DC22402B39B469E7654B4089F03440B8DC2240C2BD2317E7654B402D179F95B9DC22403C0DC747E7654B405AFBACA8C2DC22405F462710E6654B402520CF18C0DC22401E17247CE5654B4011A5CFF3D0DC22407A37D99EE3654B40302E6537D8DC2240AF4332B9E2654B40C72F7B9DDBDC22401349BE4DE2654B4076332470DEDC22409B747DBBE2654B40BF2E0219DFDC22401466BA5CE3654B404BFF0CACDEDC224095B92EFBE3654B40B567C5A4DDDC224042D9A262E4654B40F23CA39FDDDC2240E05EA564E4654B405C8FF49CDCDC224054D8CCAEE4654B4006DFF1E6DBDC22405482FCE2E4654B40E6398AF4D6DC2240FF2C9426E6654B404EE54895D6DC22402345EC3EE6654B409A529EC8D5DC2240B029B7FEE6654B4074904EC5D5DC224054E5D601E7654B40CF6C5568D4DC224028F5FFEEE7654B40F4752C47DBDC2240D0FB386CE8654B40C653AC07E5DC2240A9BCF51DE9654B40DE489AF9E4DC22408BE35A23E9654B409DF5A420E4DC2240AF24E077E9654B40D4C72A1EEDDC2240487E5C17EA654B40FF5EEFA3F1DC22402587E37FEA654B40EC4B8655F4DC22408EFB25BEEA654B40BB77FBAAF9DC2240C038C33AEB654B4091D2A1CAFFDC22406832D3C9EB654B40FE5E9AA305DD2240B9B77152EC654B40552F9F2808DD22400DF7AA90EC654B40FD160E3208DD2240FC439491EC654B40B77DB00211DD224076372459ED654B40BF447E1A1BDD2240205BFC16EB654B40	Flensburg 5	\N	fl5
8	organization	102	0103000020E6100000010000007D0200004E147FC63DEE224087FAD514BE644B40B2C189283EEE22402D7B3937BD644B40B9B71DD63EEE22406115C8AEBB644B403FD6D7BF3FEE22400F5C3C06B7644B4031BA9F533FEE22407F234F5DB2644B40FCDC9B913DEE22405D3F0FB6AD644B406D5397BC3CEE224050D34076AC644B408AB5AF013CEE2240C5DE955DAB644B40AE2DA07A3AEE22404F7B8712A9644B402AD73C7737EE224043EA8A35A4644B4032DD4A9733EE2240BE10D25B9F644B405BB674DB2EEE224089302D869A644B40A9FF8C4429EE2240FF6E6EB595644B40B010197322EE2240485CBAA790644B40CF674FEE18EE2240CFFA39728B644B402712262E0EEE22406CED994986644B402801DF3502EE224014DB682F81644B40F8F90B09F5ED2240068C2F257C644B40E54CDF3EEFED2240BBA007337A644B40E9909A2EEFED22405280922D7A644B40D03AEE7BEBED22409F3065EF78644B40EA7B39DEE5ED224079F92E0C77644B4023DE3F7ED2ED2240E9D61F8970644B4074A01F4BCEED2240DF41E9226F644B4037B3062AB1ED22401E654E6E65644B40BB2C10AEA4ED2240639F754561644B40F5BC8D00A2ED224074350B6160644B40DF7B3CC3A0ED224089DC0BE45F644B40D9FCCD228BED22400B9B475F57644B405151CE7B8AED22405C9F7D1D57644B407291A1D787ED2240DE55271356644B40682E58DA86ED2240DC3361AF55644B4018A5C62085ED2240F96BFCE954644B40879D6F0780ED22403C400BA352644B406421B4A977ED22400B839EE64E644B40065ECE7474ED2240781B03784D644B40280ED5D273ED2240CBA5AE2F4D644B40AE33B18862ED224090ED687A44644B40EBF391F854ED224092C8F5E738644B403F712ECF4BED22402736D51631644B40E1ECEB994BED2240CD0369E930644B40C6520B8E4BED2240959D6AD630644B40F53EAB6244ED22405E82905D25644B403863DD3E44ED224055A53A2425644B40ACF3874144ED2240675D6EF424644B407E8F99D644ED22406C5154791A644B40978CEED644ED22400C06E6721A644B407E9B0CE544ED22404939EC4D1A644B4087CDFDED46ED22400CA125F714644B4015768BA148ED224068746F8010644B4026CF604749ED22407D074DCD0E644B40AA06087A4AED224088CEB7A80B644B4021C1AB024BED2240A9CED8CE0A644B40D582A3094CED2240BA057F2B09644B40801D287C4CED2240BB3F79A108644B403A71858B4CED22401F02CE8708644B40E2AC64944CED22403A13097908644B4023A04C834DED2240F96A02EA06644B406F4339454EED22402F0313A605644B407747A3794FED2240C8320DA303644B40705D8C5053ED2240599B2509FE634B40218C37C753ED2240AC5E897FF9634B40C69C23CA53ED22408DC8142AE9634B4037C3D8D752ED22409B6E5035E2634B40B835AD4C50ED224087C19313DB634B4014548EB74CED22402D3D3AF4D3634B40C9314EC94AED22401C2F7EFBD0634B405B7DF11848ED2240344212D8CC634B40DFC3667142ED2240DF29EABFC5634B40903A656E3DED22402586AD39C1634B40D0403AD937ED2240CA9C04B7BC634B40C04070B231ED224069B65138B8634B40EBA291FA2AED22406E1BF7BDB3634B40A7891F6A24ED2240802CE4B8AE634B4089D833A21CED2240823D27BDA9634B40785F2B7116ED224050AAE655A6634B40AD55A80F15ED2240E109BC25A5634B40F0AA91E70CED22408809728FA1634B40E3006799E7EC224063D3662791634B40DF19A8B6E5EC224021C2185390634B407D6C4AB5D2EC224064BCE13089634B40ACE2DDCBBEEC2240AE9BEF1B82634B40C2D82B7FB3EC2240ECDFF9BF7E634B40397982D0AEEC2240E4C3A15B7D634B40D25E9805A9EC224068FBA5AA7B634B40DD5BEB10A2EC2240048ABDA279634B4001595CC590EC2240D001F99574634B405CF0322882EC2240293504CA70634B40F452E95158EC2240FB9673EB65634B40DE8B3D8157EC22400A2BB9B765634B402F37F61047EC2240F41D95A461634B40F53606EA46EC2240ACA8EE9A61634B40DA3A21702BEC2240F7D25CCB5A634B402B5D1C3227EC2240757129BE59634B4076375F3127EC22400C60F9BD59634B407AAD40D526EC224018DB24A759634B4014172A1907EC2240433357C951634B40216FE366FCEB224084CF262F4F634B405B82C98DE3EB22408E3C912349634B401D965B20DEEB224076E887D147634B40AD5A51A3D8EB224084CEB17B46634B405D8174B6CBEB22407EABDCBE42634B401199623FBFEB22403901B7F93E634B40C358EC7ABCEB22407A8D51193E634B4026F3013FB3EB22408FCE8D2C3B634B401DEEFFA2ACEB2240955A77FA38634B401E03E3D7ABEB2240E0D9FBB638634B40C2ED60B6A7EB22408008AE5737634B401DE2333C9CEB22406DC4B38B33634B4095344C5F91EB224074271DB62F634B40724AB1628FEB2240079EF3F52E634B4088FC51788EEB224067A46B9D2E634B404330182187EB2240D3076FD72B634B40684121837DEB22404FDB37F027634B40C52C09826FEB22400E2FA9A321634B403102454A6AEB22404D66BD1C1F634B4042BAC71469EB22401F98AF741E634B406E43067168EB22400266C51B1E634B403661250E62EB22404B3D13A41A634B4089E874BF5AEB2240B716D52216634B402818337356EB2240B50509E912634B40CDA6C4F854EB2240516A0ACD11634B40C89571B94FEB22402220A7730D634B40049CCF014BEB2240ADDA051709634B401BDCFFEF48EB224019BF88ED06634B401A37F5A248EB2240A796069D06634B40960F40D246EB2240082783B704634B40B128A4B443EB22402A7EE27600634B402661E74541EB2240DBF5EA7CFC624B40C810911941EB2240BC166C34FC624B40A01A25013FEB2240FDC276F0F7624B407DF3986B3DEB22405C9651ABF3624B4087CAC92E3DEB2240EC36D590EF624B40CD990C2A3DEB22408E7F4A3FEF624B40EAFFA7223DEB224026D7B3BEEE624B404309FAC93DEB2240C9FF45D2E9624B40B69299613FEB22408614FFE6E4624B40B79BE2E73FEB22404F194BE2E3624B40322D034940EB22408970A825E3624B4099B018E941EB2240F36BD0FDDF624B4017A8B20644EB2240600D4B2DDC624B406A5AACC546EB2240CD09EF5ED8624B401F2CAE254AEB22402C7B4593D4624B40158A2B264EEB22403B2EE1CAD0624B40AA884D4553EB22409E64638ACC624B40ECD0435859EB2240D3C19F50C8624B40371F3D505BEB2240E41B7323C7624B4021CBA8515CEB22405E919E89C6624B40CE67625D60EB2240C513BA1EC4624B4036D8C75268EB22409446D4F5BF624B404099308277EB2240FB99C02FB9624B4025893F4E85EB2240FCB02608B3624B401E9A2D5E8BEB224027BE0A2CB0624B40BE21092493EB2240FE425781AC624B40BD21E8839AEB2240A4F2C306A9624B40445E60D0A0EB22408B27180EA6624B402684ABD9A0EB2240599EB409A6624B404A392060A1EB2240213D0BC8A5624B404FE73261A3EB2240EB0170CDA4624B4065467211A6EB224090E64B7DA3624B405E0C0606B3EB224053008E9B9D624B400AC622B6BEEB224001F1AEAB97624B408AEACEF7C5EB22405226467F93624B40956C942EC7EB2240779989CC92624B404BE7D31EC9EB22404D0722AF91624B4050739D3DD2EB2240AA2B62A78B624B40FCA7038BDAEB22404E66CE7385624B405A553732DCEB2240C5C450B583624B4027CD51D4DCEB2240EAF2490A83624B40D5E45D82DDEB2240E97AA35282624B40CDD3DEF1DFEB2240AAB63FEE7E624B407E1D0609E0EB22409F7E05CE7E624B4068C09C00E0EB2240778DB4CD7E624B40C95CE3FEDFEB2240389AA3CD7E624B40EAC6FFF6DFEB2240BA5258CD7E624B4029918752DFEB2240A92A2BC77E624B407B369D7CD6EB2240044D76727E624B407CD83620D1EB22407C09B53E7E624B4066A57E68AFEB2240BBCD39F97C624B40BD5B4AF74DEA2240A1C183E770624B401806B26648EA2240B878DCB670624B40B271753948EA2240071C52B570624B4028FDF12142EA22409B34ED7D70624B40FF76753B48EA2240A58F52AB70624B404985D04748EA22404D8F34AB70624B402EBD1F5942EA22401AE3DF7D70624B401DD2CD2242EA2240CDBE4E7D70624B4059CF448C3DEA224092FBFE7070624B40B2C9B3E07BE92240020132696E624B409B3127C27BE922409AB082696E624B40E6FEC0FF21E922401D51AD526F624B40CB2F96FB21E922403D44CB526F624B400C14E4A81BE9224088A475806F624B4057E370A4A8E8224075D120BF72624B40791A59A549E822408103B46175624B4047DD645349E8224052F87E6275624B40CE9E57CC71E72240D0226D5681624B4056AAA83D6CE7224081C8B4B281624B401029ECDE51E722401FC2916883624B40652ED2BF18E72240AC07081D87624B40CBE82E15A0E62240AEE8574B90624B40FCF4E78D53E6224030B00E7A96624B40330B186846E622401762F88997624B40BF7D42A315E62240C0078E7A9B624B407B31058A18E62240F362042D9C624B40919777F818E622405F838E479C624B403FD6EC4526E622400AE6C2799F624B40C8E2BDBBDBE5224040AC87ADA6624B40926CAD408EE52240F23E6727AE624B407F17447442E5224025F6DA7EB5624B40F8E2C5B8F1E42240B29AAA32BD624B405EF33113A8E4224018F67365C4624B40D2F3C84A5BE422408D6C86A6CB624B409BBA587C32E42240611345AFCF624B401D2A4AD927E422404AA979BCD0624B4091524F740FE42240C6E3D825D3624B401C8D3B88D4E32240C218AB0BD9624B40FD61DA50B8E322407200FE40DA624B40680AFA30A9E32240F3CACBE6DA624B4098989F0794E32240809CC7CEDB624B400DC4E87A75E32240AD89EFB4DE624B4083CAA62C35E32240587E1FCFE4624B40FB77434906E3224045F3F6DBE3624B40DECF000D05E32240C2F5BB97E3624B4009BE3899FAE22240A4A77156E1624B401B323204EAE22240DD6F617CE3624B40E827398ED8E22240371DBC7BE5624B40EFBD1E48C6E22240585F9752E7624B402B145643B3E22240E6592FFFE8624B40287DF48F76E222400A0EF1AFED624B405F31F9886AE22240FE1961AAEE624B4085ACC6933AE2224086C7F790F2624B400457EA55FFE122406A65ADA1F7624B409C8E8ADDC4E12240DBD679E1FC624B4068E05C649BE122406931C0F900634B40361D5BA271E1224015D5780205634B40A555B79847E12240A97E86FB08634B400525A0EE26E12240BFD77C000C634B40BDCE7B481DE1224081BED1E40C634B4083EABFB2F2E02240D8573DBE10634B405D18B6D8C7E022400AC0B38714634B40925068BB9CE02240A6CF154118634B4061C3FB5B71E0224078ED4FEA1B634B40BF91A19B5CE02240174879951D634B40F105D13518E022404C39691523634B40DF9C29DD13E02240EEF1467923634B4096EEEF1510E022402FBEE7F823634B403585DE000DE022404BE1FB8F24634B401FE094300CE02240F52662CC24634B402B6DA7B80AE022400483663925634B407A1D135109E022408D466AEF25634B40251D55D608E02240648DDDAB26634B4044727B4C09E0224028A2606827634B404F5CA6AF0AE022402EB5931E28634B4079F256340DE022402F5B05FD28634B400F848F660EE0224027D6AB6629634B40579BA0FC17E022409F316CB52C634B408D33C92625E02240B189404031634B40D3E821A032E0224075C565E635634B4098F53E7938E0224032A5AAE637634B40BCC1D6F13EE02240C5107E1D3A634B40FBBDE4B542E0224077455E673B634B40C1C1863A65E02240F2CDEA3647634B4047A134947CE0224027B8C1BD4F634B406FFA378E87E02240B2E2E1BF53634B409106E28093E02240B267C61C58634B4031C1E5209DE02240E62F46A85B634B40E4B133BEB1E022407FB5E73F63634B40DDC72073B2E022406DC18A8263634B402BA3EBDEB5E02240F5E05B0D65634B4096157478B6E022403382586A65634B404800E878B8E02240C29AA4A066634B40415E623DBAE0224035860F3A68634B40B1B1A429BBE02240563541D769634B4013EC2544B3E02240BAA2DF1D6A634B402B1386A3ABE02240C84052856A634B4035FD7BD8A7E022404CA7D3CB6A634B4008793861A4E022403C71410C6B634B4012366B959DE022408BE0E7B06B634B40743BC55697E022408CE125716C634B4083F922BA91E022406BFA734A6D634B40033C3AD28CE02240C9DA013A6E634B40266A64AF88E02240B7AFAE3C6F634B40E714320663E0224060022EC479634B40095CF7F75BE02240A1E2F2CC7B634B408854545756E022404FC2FDEC7D634B40A33DD90D53E02240EA58B3AA7F634B400E6C593252E022408EF5F61E80634B4010F0DE4E51E0224052A1BAE180634B40239BC89B50E02240DB55047B81634B409E6D6E934FE0224035445B5D82634B404A98F4844EE022408BA4B68884634B4092C83AE34EE02240BC6D47B586634B40318A5CAD50E02240874C0EDE88634B4069EF39DF53E02240BD3F18FE8A634B40A75BB25170E022400A87E5E49A634B40F23CE64C72E02240FFC6ED929C634B40ECCEE4DC72E02240C13C020D9D634B4060068AF574E022403882B0379F634B40213DCB6E75E022405A9772D29F634B409942DD3B76E02240828F1ED8A0634B40566EA72F77E02240285B7EB3A2634B4093133E4C78E0224069C885DEA4634B40782F66D278E022400CC994E7A8634B403135D4CD77E022401A0E23F0AC634B40E5CB543F75E022404AA10BF5B0634B403FBC903071E02240249AB8EBB4634B401521F52871E02240594029F3B4634B40225CDB8D6BE0224091FA61E7B8634B40069EA67A65E0224007947B3DBC634B4026EC607264E0224088849DCEBC634B40322113DC5BE022407DBAD2A5C0634B405229235F4CE02240E0BE61D3C6634B40D7DB38F83BE022401BA98B74CD634B403E8D9F6234E02240D7D35585D0634B40F811B7A932E02240097D8A37D1634B40369C24A032E022409B2AF636D1634B4023681EF430E02240B9FC4CE4D1634B400E2AA4A62FE02240491F5B6BD2634B40F59B92AD2FE0224053C7656CD2634B40555357FC43E022405687F37DD5634B40AB24CF3054E02240283F99CDD7634B40EE48287A66E022406F7F3C69DA634B402222515880E02240B166DF86DE634B40B8D1FBF590E02240F01D3D3CE1634B40A710351891E0224073EA4242E1634B402381095094E0224068330DD3E1634B40FDE2588B98E022407DF64291E2634B404153B1DF99E022406C402ECDE2634B4090B53B159BE022400CFEB603E3634B40A47FAA989BE02240D74BF71AE3634B407C0D38399FE02240F63C2BBEE3634B40B1F2F7A9A1E02240543E002CE4634B405ED66197A5E02240F0EDBBDCE4634B404B64C803ACE02240697786FDE5634B40A0C5DE5BADE022401015473AE6634B40D34A4B98AEE02240D3F8E771E6634B40B6E8C374B1E02240DCF47FF1E6634B40772CF443B9E022409003C776E8634B40418F08C0C3E02240EA684480EA634B40809ADC87C7E02240D2CD4F3CEB634B402CB60099CDE0224003424B67EC634B40E8A2F6BAD2E02240661C629CED634B40593BE68AE0E022405ED627DCF0634B405BA4CC8EE0E02240E77310DDF0634B403D46B28FE0E0224076124CDDF0634B40290928D5E5E02240E2765B63F2634B40E87FB73EE6E022405B6FDE81F2634B40B8D0CE25E7E02240F70EA6C4F2634B40A658CC83E7E0224075D4D2DFF2634B40C5E9A629E9E022405F8F8A5AF3634B40B38F6501EBE022406000D8E2F3634B40C12C378AECE02240CB1F7B54F4634B4016DCCBB2EDE022404B1FA4A9F4634B4036B96F42EEE022407974DAD2F4634B40C9A6B876F1E02240C0F5D9BFF5634B4023695553F3E022405C07AE49F6634B40A7FE51ABFAE02240C49D0973F8634B4096653823FBE02240FEB5CA9FF8634B404D230C67FFE022409EA74B37FA634B4062F2FD4705E12240FA35085CFC634B4097C390AD0AE1224085D118ABFE634B408E0F4D4510E1224063DDFE4301644B408BDE46F419E122400FABFA0507644B40F76209EA1EE122403C9A59D60A644B40AEF9541821E1224063F9A5830C644B402EC79D1923E122403AB65C0E0E644B40CAB2DD1D23E12240E94CC5600F644B409E65931E23E122403273101D10644B405EC8D81E23E1224049DA427010644B4049957DE824E122407351C46210644B40324D3AAA29E12240D16FC25210644B405151CF3D2DE1224099BD675510644B402F65614C31E12240E494B26510644B401EAA292D33E12240E8D03E6D10644B402721048541E1224059AFA7E410644B400E5B88A645E12240AC6C4FFC10644B40C32261674BE12240F8D2421D11644B40F7EF640C50E12240CB78DD3711644B40E2D362CE82E12240BCA12DCF11644B407A201C75BEE122403BB69E4612644B40AACB3FE8C0E12240E8DC0C4612644B40789A2D67C5E122401941FF4412644B40D87BAF98CCE1224084FD504312644B4058AFA37FD9E1224014BB4C4012644B4096C5B46812E222407456274013644B40B5E3A22C1AE2224012038B7213644B409F200BDA21E222400E30D6B413644B40451DDE6A29E22240EB19D80614644B40A9E718D930E22240DABF4A6814644B4022B15C1B35E222402F2E1AA814644B40C62CD31E38E22240F42CE6D814644B40A4A64B363FE22240AB3A4B5815644B406BB547BB3FE22240E5A6FD6215644B40A71EE91946E2224048B91AE615644B40ABB41EC44CE22240A44DDE8116644B400297E1F2C8E2224081D80F6021644B402DB27113D0E2224081817C0022644B40009BEBF3D0E2224088A9381422644B404CDA070CD1E222407844C11622644B408654E1B6DBE222404D2A5D3523644B4019FDE97AE5E222408BC2087424644B401BF46080E9E22240965C5B1225644B4076859B65EEE2224041B419D325644B40FD68B4E4F5E22240817BFE3727644B404D600D63F6E22240CD7B7B4F27644B40A1F33461FDE22240EA75D9E528644B40F192E6C502E3224068F1514C2A644B408ECE522308E32240B7550F522C644B40962B28CF0BE3224087793A202E644B40490B234D16E32240031E4EBE36644B40121B1C911FE32240E38082B237644B4001B3E44B22E32240022874FA37644B40D9235E883AE32240395A38793A644B401C1853886AE322402BBA25423D644B406950475970E32240F0DD827B3D644B40C74503BB92E322405B7F03923F644B4013380F00A0E32240A27D4F2C40644B408A092EC8B9E3224024286E5741644B407BE229EEB9E32240FCC9221440644B4034070524CFE322404CE7FA8C40644B40E6EBD704D0E32240BB74F82040644B40E0A37A0DE2E3224087D1A2A940644B40C88201C2EAE32240AA1C0ED140644B409B173A74F4E32240D5B0BC3641644B40A6C7C9F6F7E3224051321D5D41644B40AE9E563A06E4224034A5DCDC41644B4080C8F0FC07E422405C432C0842644B40D79B9F3421E422403783374C43644B40A99C33D433E42240DF8ACD4244644B402D4DA01846E42240DB96F77745644B406D99C3C256E422408ABB5D6146644B40356B9FB766E42240E305065D47644B40E9C731CD66E422406DD182D048644B405C7BB5F675E422403D45656449644B4028C339DC7EE422404F4BB0AD49644B4058E859AB93E42240E991F7494A644B4096445038A1E42240B1992ED54A644B40DF955ADAAAE4224040A0212E4B644B40C6E78DD4B1E42240D9DD71634B644B4014EB2870BBE42240D06F91AC4B644B403541D445CCE42240BCB5873B4C644B407C1ABBA2CCE42240BF83983E4C644B40B8575D35D5E422404741FF864C644B40E25A9B2ADEE42240B461B4D14C644B40662A0E1FF1E4224097D9FE6F4D644B40F5A0CF950EE5224031A8BF704E644B40443E8E5B1DE52240E05E93E94E644B40703EB76E2AE52240C3BD6E4B4F644B40E0A3744936E522401420DAA34F644B404E5F288643E522408167250150644B407C3A667244E5224026BB4F2B4F644B400D4B35417BE52240EAACCB8150644B4009435AD47EE5224002468A8D50644B4068EDC0EC80E5224058D66C9450644B40AB3692BC72E5224039996B495D644B406A03667B78E522404D51E96C5D644B40FFCB969A8DE52240B57152C55D644B403F7BFEFA9CE522405BF591F050644B40903CB044A0E5224089E135324E644B4044727BB8B6E522400C36C97C4E644B40E78A11EBB6E52240C3B8707D4E644B40F3C44F23BAE52240450C93C34B644B40437E0FB5FFE52240A5F905F44C644B409A33AF7633E62240B4FC4FD74D644B4011C0AC9B36E6224088CE1DE54D644B4087086D043FE6224040590B0A4E644B4097ED4F2242E622400D0C130D4E644B408CEFB34B48E62240CE05F8A749644B40175ABE2444E62240C6F2CCBB49644B405B04965649E62240DA37494449644B40F79C40C752E62240A0A03C5045644B40CC62F7DC53E62240308FFC7F44644B40C080630F5BE622400239EE8440644B40918F81C85FE62240C3375B273E644B40026EAEA060E62240EA71496F3D644B4091F2301661E62240596A86EF3C644B4075E4594A61E62240F1E9CEB63C644B403D23785161E6224094ED16AF3C644B404650137E64E6224087D346D93C644B409282B7E664E62240029DB4DE3C644B406A88201106E7224079B35CC846644B408F139AC013E72240A72757A147644B4017943F5C55E722401A4688B14B644B403748A0D471E722402B2530694D644B403D3E2A457CE7224093DA660A4E644B406FA77B51AEE722401C86430F51644B40B3245EC9C2E7224071CF704752644B405C65E9A2D7E72240BC90EE5A53644B40171AAAE1DDE72240C5FF25A153644B405173C5D1ECE72240BDCF174954644B400D37F286E8E72240FB3E725755644B4079A3935AE8E72240AF72286655644B402B8BDF1CDEE72240BAA49DCB58644B40FA63D6A4DCE72240AD3B534859644B4093C37269D4E722408B2F26045C644B40F1A341F3C8E722400D96BDD05F644B405A180D3BC0E7224079306B8A62644B40D5825343B9E72240A58A78B664644B4029F480C9B6E7224031460E7C65644B403F1B7945B3E722408A1B6E9466644B40DFA949E9ADE72240F57AE55C68644B40D0F47CD4A7E722402325D8616A644B4053AD30659FE722408E1131196D644B40BF976A3E89E7224087FE293E74644B40996D3B217CE722409AFBF67978644B40B2AD57BE7AE72240A936E2EC78644B40C90C0BD376E722403DB714937A644B40BFCD5D0E74E722405159AACF7B644B40DEBA94C571E7224048E582D37C644B40BCC8D6D06FE7224017725ABD7D644B40DBE6C1566CE722408B9E39D77E644B40176C68C94CE722404B7DE8FF88644B40FA5EE3AA47E72240B2D0B6B48A644B40A4571E1344E72240FFE790E78B644B4015D7D02639E722405F4A83818F644B4082B8B3A234E722406C78B4FE90644B40BB7D8BD22CE72240B3D2269293644B407E34C8E92CE72240494B8F9293644B40730EB5C131E72240DDB658A893644B40F85CEBA136E7224014A64FCE93644B406187B40753E722409B574FAA94644B402B128C0066E7224022AF393A95644B40B172E1AF7BE72240EEC19DE195644B40F5E0451F9FE722404F08EAE996644B40506C7EA9AAE7224073F5FF3297644B40009489C9B8E72240DCC381BD97644B40EB4D03E7C7E72240D6600D4198644B4052E1C284CDE722401320EF7198644B40AA6A0252DBE72240A88129D798644B403D4FE37CE5E72240D3C8BD2199644B4051AB08E3FCE72240970205D499644B4078CDE05415E82240B25513979A644B4065BC267817E82240A41B23A89A644B40D49281DC16E82240AADD9E229B644B40A2A4E6DB16E8224035AA16239B644B406477E2DD16E82240F6FA1B239B644B40DD88CD521AE822402D7F0F2C9B644B4090C60A662BE82240CA9E141C9C644B40BB0818262EE822404F2DF21F9C644B4089D80ABD32E822409EBBC5409C644B405E495E5A4BE82240070268B19D644B404870CC5766E82240A6DCC76C9F644B401CB36BB682E822408CD0A203A1644B40FD3D15B5B1E82240D647D482A4644B40C0278929BBE82240DAC1F8E9A0644B4015F40DCDCCE822402FF661B0A1644B4047CBD631E4E82240739DFFB6A2644B4087F47291FBE8224026F05EBEA3644B40AA0CB5D118E92240799A6C07A5644B4061D5470D36E9224003376750A6644B406B281C724DE92240A39F1557A7644B4024F2C2D164E92240E667725EA8644B403EC9527B80E92240E5A6B395A9644B40E8BF2DE097E92240CBF64C9CAA644B40FDA11445AFE92240E7FDB9A3AB644B40D466BA80CCE922409B0FB0ECAC644B40F7BA64BCE9E92240B78BB835AE644B403F4F4A2101EA224095504F3CAF644B40EF85A35415EA2240D012B31FB0644B40182A27651AEA22406B6F094AB0644B408F78CA201FEA2240CC822E5AB0644B40B38420FB2CEA224022AB3C8CB0644B4056C8202336EA2240571551ADB0644B402978321F39EA224045C619B8B0644B408CB2592F40EA2240CE9C84D0B0644B40640583C246EA2240CF623EE7B0644B40BDAD75804EEA22401D938700B1644B401AB2721960EA2240FD28023AB1644B405E32878878EA2240DDE37A5AB1644B40D92294F790EA22401552457AB1644B4056CD4618AFEA22403471C0A1B1644B40CA86D783AFEA224006574EA2B1644B40EE135E0ACEEA224030C957CAB1644B405EE27379E6EA22407DBFCDEAB1644B40913D81E8FEEA2240CB1C820AB2644B406C718C451EEB22408F16D733B2644B40DD539BB436EB224097589D53B2644B40469FA9234FEB2240CBB04F73B2644B40433D6AAF6DEB2240C3D9529BB2644B40B3E0B03B8CEB224034EC54C3B2644B403DF0C8AAA4EB2240B618C6E3B2644B40E965D919BDEB22408FF88803B3644B40C0F42830F2EB22407B1EB98CC2644B4067E584FAF5EB2240DF3B2711C4644B400943A52DF6EB2240154C9825C4644B4047CDCC32F6EB2240B5FAA327C4644B4038637C25F7EB2240DEF1DC19C4644B403EDCBC8504EC224022C89057C3644B4009BFDE2723EC224035F3F75EC1644B40DB28FCF432EC2240E699BE3FC0644B405F14614041EC2240B9A8E73BBF644B406E4F9AF249EC224026D48E84BE644B404761E92250EC2240A3CE3638BF644B40453BBEA056EC2240852D99DCBF644B40C0DD12655DEC2240D4170671C0644B40B50818E562EC2240DE9A67D8C0644B40CCBE916864EC22407D4ADBF4C0644B40530E37C167EC2240C2AAED29C1644B4060F795A36BEC22406EF48767C1644B403083530E73EC2240E68890C8C1644B40E2CEC9A07AEC2240B7D48C17C2644B40A101A95282EC2240D7042854C2644B40DE0267DFA2EC22401B3E2FF9C2644B4060699D8CC5EC22406D83FDA8C3644B408216740BCAEC224051A9E8CCC3644B404F360509CEEC224072487621C4644B4088180FB4D3EC2240CBDA563BC4644B403F85E80ADAEC2240B4674958C4644B4003C91FD60DED2240E174CC44C5644B40589A252614ED22404AF99767C5644B4092D3F7D324ED22401A3B35D1C5644B409BD8BD6835ED22401B07214EC6644B40671B57E045ED2240E2913BDEC6644B404128883656ED2240C03A6181C7644B4053E62F6766ED224097A26637C8644B40584D556E76ED2240CA602000C9644B40F573C94786ED2240D57359DBC9644B407393ADEF95ED2240E2C6DCC8CA644B40FF22B27AB2ED22402773607ACC644B4007B7886DB4ED2240C9A3FA97CC644B40FCE4850BBCED22408831AA0BCD644B4075818E7EE8ED224008D69D9ACF644B40EFEB9D2B13EE2240E0C86D0FD2644B40479DDCEC1DEE22409AA7E4ADD2644B40DE6D377A27EE22406463A43AD3644B4012815C7C27EE224096BDC23AD3644B40034A8FA127EE2240C45BE73CD3644B40E634F4A327EE2240E38BA23BD3644B40989D37C928EE22406978C583D2644B40C5BC2B782EEE22409120A4F3CE644B40FB169B8034EE2240CD952E2CCA644B40F4E9C4C737EE2240EED359D9C6644B403B438F1839EE2240252BDD83C5644B409963E63E39EE2240E2F0FA5CC5644B4024C228B13CEE2240AA6FE487C0644B404E147FC63DEE224087FAD514BE644B40	Flensburg 8	\N	fl8
10	organization	102	0103000020E610000001000000B8020000110767DF06E0224039F5409EE1634B40AD92BBAE10E02240D5BDAD22DE634B408246332A21E02240EA1CAA48D8634B4098F9C23521E02240DF6E9144D8634B408415F60C23E02240FA00BB85D7634B401071E4C92DE022401BB1B32FD3634B40F59B92AD2FE0224053C7656CD2634B400E2AA4A62FE02240491F5B6BD2634B4023681EF430E02240B9FC4CE4D1634B40369C24A032E022409B2AF636D1634B40F811B7A932E02240097D8A37D1634B403E8D9F6234E02240D7D35585D0634B40D7DB38F83BE022401BA98B74CD634B405229235F4CE02240E0BE61D3C6634B40322113DC5BE022407DBAD2A5C0634B4026EC607264E0224088849DCEBC634B40069EA67A65E0224007947B3DBC634B40225CDB8D6BE0224091FA61E7B8634B401521F52871E02240594029F3B4634B403FBC903071E02240249AB8EBB4634B40E5CB543F75E022404AA10BF5B0634B403135D4CD77E022401A0E23F0AC634B40782F66D278E022400CC994E7A8634B4093133E4C78E0224069C885DEA4634B40566EA72F77E02240285B7EB3A2634B409942DD3B76E02240828F1ED8A0634B40213DCB6E75E022405A9772D29F634B4060068AF574E022403882B0379F634B40ECCEE4DC72E02240C13C020D9D634B40F23CE64C72E02240FFC6ED929C634B40A75BB25170E022400A87E5E49A634B4069EF39DF53E02240BD3F18FE8A634B40318A5CAD50E02240874C0EDE88634B4092C83AE34EE02240BC6D47B586634B404A98F4844EE022408BA4B68884634B409E6D6E934FE0224035445B5D82634B40239BC89B50E02240DB55047B81634B4010F0DE4E51E0224052A1BAE180634B400E6C593252E022408EF5F61E80634B40A33DD90D53E02240EA58B3AA7F634B408854545756E022404FC2FDEC7D634B40095CF7F75BE02240A1E2F2CC7B634B40E714320663E0224060022EC479634B40266A64AF88E02240B7AFAE3C6F634B40033C3AD28CE02240C9DA013A6E634B4083F922BA91E022406BFA734A6D634B40743BC55697E022408CE125716C634B4012366B959DE022408BE0E7B06B634B4008793861A4E022403C71410C6B634B4035FD7BD8A7E022404CA7D3CB6A634B402B1386A3ABE02240C84052856A634B4013EC2544B3E02240BAA2DF1D6A634B40B1B1A429BBE02240563541D769634B40415E623DBAE0224035860F3A68634B404800E878B8E02240C29AA4A066634B4096157478B6E022403382586A65634B402BA3EBDEB5E02240F5E05B0D65634B40DDC72073B2E022406DC18A8263634B40E4B133BEB1E022407FB5E73F63634B4031C1E5209DE02240E62F46A85B634B409106E28093E02240B267C61C58634B406FFA378E87E02240B2E2E1BF53634B4047A134947CE0224027B8C1BD4F634B40C1C1863A65E02240F2CDEA3647634B40FBBDE4B542E0224077455E673B634B40BCC1D6F13EE02240C5107E1D3A634B4098F53E7938E0224032A5AAE637634B40D3E821A032E0224075C565E635634B408D33C92625E02240B189404031634B40579BA0FC17E022409F316CB52C634B400F848F660EE0224027D6AB6629634B4079F256340DE022402F5B05FD28634B404F5CA6AF0AE022402EB5931E28634B4044727B4C09E0224028A2606827634B40251D55D608E02240648DDDAB26634B407A1D135109E022408D466AEF25634B402B6DA7B80AE022400483663925634B401FE094300CE02240F52662CC24634B403585DE000DE022404BE1FB8F24634B4096EEEF1510E022402FBEE7F823634B40DF9C29DD13E02240EEF1467923634B40F105D13518E022404C39691523634B40BF91A19B5CE02240174879951D634B4061C3FB5B71E0224078ED4FEA1B634B40925068BB9CE02240A6CF154118634B405D18B6D8C7E022400AC0B38714634B4083EABFB2F2E02240D8573DBE10634B40BDCE7B481DE1224081BED1E40C634B400525A0EE26E12240BFD77C000C634B40A555B79847E12240A97E86FB08634B40361D5BA271E1224015D5780205634B4068E05C649BE122406931C0F900634B409C8E8ADDC4E12240DBD679E1FC624B400457EA55FFE122406A65ADA1F7624B4085ACC6933AE2224086C7F790F2624B405F31F9886AE22240FE1961AAEE624B40287DF48F76E222400A0EF1AFED624B402B145643B3E22240E6592FFFE8624B40EFBD1E48C6E22240585F9752E7624B40E827398ED8E22240371DBC7BE5624B401B323204EAE22240DD6F617CE3624B4009BE3899FAE22240A4A77156E1624B40DECF000D05E32240C2F5BB97E3624B40FB77434906E3224045F3F6DBE3624B4083CAA62C35E32240587E1FCFE4624B400DC4E87A75E32240AD89EFB4DE624B4098989F0794E32240809CC7CEDB624B40680AFA30A9E32240F3CACBE6DA624B40FD61DA50B8E322407200FE40DA624B401C8D3B88D4E32240C218AB0BD9624B4091524F740FE42240C6E3D825D3624B401D2A4AD927E422404AA979BCD0624B409BBA587C32E42240611345AFCF624B40D2F3C84A5BE422408D6C86A6CB624B405EF33113A8E4224018F67365C4624B40F8E2C5B8F1E42240B29AAA32BD624B407F17447442E5224025F6DA7EB5624B40926CAD408EE52240F23E6727AE624B40C8E2BDBBDBE5224040AC87ADA6624B403FD6EC4526E622400AE6C2799F624B40919777F818E622405F838E479C624B407B31058A18E62240F362042D9C624B40BF7D42A315E62240C0078E7A9B624B40330B186846E622401762F88997624B40FCF4E78D53E6224030B00E7A96624B40CBE82E15A0E62240AEE8574B90624B40652ED2BF18E72240AC07081D87624B401029ECDE51E722401FC2916883624B4056AAA83D6CE7224081C8B4B281624B40CE9E57CC71E72240D0226D5681624B4047DD645349E8224052F87E6275624B40791A59A549E822408103B46175624B4057E370A4A8E8224075D120BF72624B400C14E4A81BE9224088A475806F624B40CB2F96FB21E922403D44CB526F624B40E6FEC0FF21E922401D51AD526F624B409B3127C27BE922409AB082696E624B40B2C9B3E07BE92240020132696E624B4059CF448C3DEA224092FBFE7070624B401DD2CD2242EA2240CDBE4E7D70624B402EBD1F5942EA22401AE3DF7D70624B404985D04748EA22404D8F34AB70624B40FF76753B48EA2240A58F52AB70624B4028FDF12142EA22409B34ED7D70624B40B271753948EA2240071C52B570624B401806B26648EA2240B878DCB670624B40BD5B4AF74DEA2240A1C183E770624B4066A57E68AFEB2240BBCD39F97C624B407CD83620D1EB22407C09B53E7E624B407B369D7CD6EB2240044D76727E624B4029918752DFEB2240A92A2BC77E624B40EAC6FFF6DFEB2240BA5258CD7E624B40C95CE3FEDFEB2240389AA3CD7E624B4068C09C00E0EB2240778DB4CD7E624B407E1D0609E0EB22409F7E05CE7E624B40F185CECDE2EB2240F2D7A90B7B624B408BBFBBEEE4EB22405712F5E576624B40D9302710E6EB2240761E28BE72624B40D48FB531E6EB224059298B956E624B40572EA91FE6EB22403F7AABE968624B40F339C6E4E4EB22407749783E63624B40A10FDAD8E4EB2240FFB93D2263624B40811A7ED0E4EB224080276A0E63624B401BAF5F81E2EB2240E94F41955D624B404626FDF5DEEB224027DA44EF57624B409D7BC7B6D8EB2240FC43D9FF50624B400BFB3858D1EB22402D1755164A624B404888BE41CEEB2240704C1F9547624B40FB338D2CCDEB2240279D41B446624B405E634EDBC8EB22407305B13343624B40DF184741BFEB224055C1E3583C624B400508DC05B3EB2240B91E3C2B35624B4007DF93BAB2EB2240F7CD0DFF34624B40D3451855B2EB224072F780C334624B40E5283E3AA4EB2240BD2769392D624B40B0497EF294EB2240F6729EBB25624B40D6B9ED7F84EB22403451174B1E624B407737246178EB2240A82F188819624B40BB5CAEC06BEB22404FCE29CC14624B40AD0B589F5EEB2240F54C951710624B40E194E1A856EB22400A0D5C5C0D624B407411335D55EB2240051497EA0C624B401CCADFFD50EB22406FCEA36A0B624B403180DF4D3FEB224070169AB205624B400FFA31B42CEB224011E7230A00624B4085B5613319EB22408E4B0972FA614B40489104FE12EB2240278B50C3F8614B40E2B4D07910EB2240C836BD14F8614B407D966F0908EB22400D6044CBF5614B40DE1C21CE04EB2240E75610EBF4614B406E568620F3EA2240470C6174F0614B40022F2FFFF2EA224044AFF56BF0614B40245FB994EEEA224070ED844EEF614B40CA73185FD7EA2240706578C7E9614B409875DB1BCBEA22406E9C2F05E7614B403EBB5E56C9EA22401839A695E6614B407FE245F5C6EA224038752016E6614B405AD93231BFEA22404119D756E4614B40B185170FA6EA2240588089FDDE614B404753471C8DEA2240CE0B34F7D9614B40A8878B848CEA2240734AB4D9D9614B40A52712F88BEA2240794767BED9614B4069F0309473EA22404495A600D5614B4074E4AB7859EA2240ED533B1AD0614B400D508E2D48EA224040C6B5F7CC614B40CB69BBF33EEA22405EBF944BCB614B405C4D80BE47EA2240BCBCBE6ECA614B4029DB8DFB71EA2240691FCD7EC6614B403BD066F883EA22409446E0BBC5614B409CAE34D295EA2240886F4881C5614B40B5311405ABEA2240F2D7EAEDC5614B40A3F0F8F2ABEA2240CD170BF8C5614B40C4EC5BF3DBEA2240C964E765C9614B404B32DA8AEFEA2240F65E8D2DCB614B4053D2C3C700EB22408E7B7F42CC614B40BFDB822B21EB224095A92408CC614B4051B174C639EB224067258634CB614B408321991245EB22404A538A3BCA614B4051AC3AF245EB22400B254928CA614B4026662FCD4DEB2240CB49A8B9C8614B4006E2864B5DEB22402E8C2E07C5614B4095E7FF1666EB22407C56AB67C1614B405235A79279EB22408A39944CB4614B408B1E3E047EEB22407BA5CCD0B0614B40DF22261B9EEB2240FAA5DF4CA3614B40A9BF677CACEB22405B9489B992614B40435B1280ACEB224086134CB592614B40A1EC6C6DAEEB2240C02F4C5590614B40B262D48EB0EB2240D35C2BB58D614B4094D3ABDBB0EB2240898874568D614B40E9B5CC399AEB22405C81070E8A614B403E2A120F9AEB224088D6D5078A614B40F52538F695EB22405013B26F89614B409C841E2B90EB2240727D7FDC87614B40D3F11B458BEB2240DEA2108184614B4056E9FBCF88EB2240F5BF1FF881614B405750BC5C86EB224049C96C7E80614B4033296DD880EB2240D02B15BA7E614B4057DE6C937DEB2240553CB4747A614B4093E3749D7FEB2240DD8FBE197A614B403C8F0B508FEB2240E491132179614B40C75BDC598FEB2240EDD88C1379614B401B0532A095EB22405E0F363E78614B40818BFBDB9CEB22405DE8208B76614B40E2F9B52A9EEB224014AB152E76614B403BF081A79EEB2240BF8E91F275614B40DA91F0C89EEB224018639FE275614B40CFE4AF69A0EB2240BD72E67175614B40378F36D2A1EB2240C100877771614B40BD506CCFA0EB2240587D8B4970614B40E4517C54A0EB2240AE5F650770614B40442A21F29DEB2240277B161C6F614B407D14A8159DEB2240E16539E76E614B40B60AD0B59CEB2240941F3FD06E614B408472AFB49BEB22403E85CA396E614B40C6AC823F99EB2240C26952EE6D614B401EF0E9798DEB22402F74C1596B614B40AC29826582EB2240F4BC06EC68614B408767213985EB2240F03E53D264614B400D3F574186EB224081F6415363614B40EDAD0C648CEB22404C27F8C560614B408EF6FC5996EB2240A4D53ED35C614B40940BA30B9FEB2240CBB212A95A614B40082DB66EA2EB2240C3A52BD159614B40BE74E2DCA9EB2240D88E58F857614B406C7AE339A9EB224080D7336953614B40FF188314A7EB22406C52DC0653614B40625E89939FEB22401881FCAE51614B409DEFAB33A3EB224035FC3FC850614B40015119CFA8EB2240312D24B54E614B40FE038402A9EB2240DE249D994E614B40B15D5DA6ACEB2240F10769BC4D614B4005BF3045AEEB22402D00F2594D614B40ACEA31EEAEEB22409F77D2314D614B408FD4A3D6AEEB22405B1F3AA94B614B40359BD740B1EB22404E3B1EE34A614B4092A6F601CEEB22404BC347AC41614B4019F56156CFEB22400C8345E740614B406A9C5F3CDEEB22400E1EF04E38614B40A7F643C7EAEB224024A4593A30614B40A6301C18F8EB2240AF6C1E512B614B4090DF5697F6EB2240414957F62A614B40EB9ED3D4FEEB22408C8454FB24614B4077E1EF3DFFEB22400A04BC9A24614B40D953973704EC2240BCE1006F1F614B40917CF76904EC224021CFC4971C614B4099A60F550FEC2240B54E539415614B40ACD8DA381CEC2240D92998A30C614B40BC3BD3C521EC2240720D8E3A0A614B40E65A83C529EC22405AC1541D06614B400806FA1B2AEC22406EDFF00006614B40CBEC145A30EC2240D9B31EF403614B406744F3AC36EC2240CB38AD9101614B40EC70869C39EC2240E5B257D7FF604B40FCFD3F6939EC224043C72205FF604B409B4B036A39EC2240CD480429FA604B40F9895B3B3AEC224019D05C60F9604B40E0E13B4D3BEC224043D987CAF3604B40EAA950823BEC2240949AB414F2604B40E8215F593BEC224033FD1F5BF0604B403085DF393BEC2240E7A80E34ED604B40B83C808236EC2240BA065B90DF604B4086567CD63EEC22408C3E566DDC604B40E68CC40C3FEC22403BE6B7ECD9604B40482D77F63FEC2240D970D58BD8604B40F6717E5E3FEC2240C3C1EB3DD6604B40F96759A03BEC224070B3C208D0604B408A2EFDC938EC22409222C4C2CC604B404D8527D133EC2240AD97CF1FC9604B401E5D9D062FEC224070D1137EC4604B40090E22C32AEC2240B6902CA7C1604B40CC7DF92B27EC2240CF68AA98BC604B402D31C24321EC22402B09ADF3B8604B40D606DA5F1EEC22402FA9BFF5B4604B40CD0D58E119EC22406EC1627BB1604B40B9B45B9C09EC2240C13088D9A9604B40E46516E500EC2240F169843DA6604B40CC726D14F6EB2240553115CEA0604B40F3BE8263F2EB224028B4684F9F604B4042364553ECEB22400D9B14B09C604B40E47CA401E7EB224087E535639A604B401B943FD8E5EB2240829C51E099604B409AD7F2B0E5EB2240F3205DCF99604B40D503D554C8EB2240E72A42AC8C604B40FFF36DC2A9EB22409B0485D37F604B4084D82513A2EB2240DD7C5C7D7C604B40EB28BE5E95EB224059BF15A476604B4079783C718BEB2240532C6B7171604B40564B4C0B8AEB2240DC2E3FCD6F604B400777458E8AEB2240D28C52826E604B4093A34F8A89EB22402DCB46396D604B408D42CC7785EB2240283E67806A604B406CEF26977DEB22407A2018186A604B400873297D77EB2240C15C7AC769604B40E7E41F2A76EB22401C08D9BA69604B40D6DCF11176EB2240DE84F1B969604B40B05E22DD6CEB22404E6A226269604B4025D777AB6BEB22405021BF5669604B404610D4CC62EB22403E66260269604B400BDAAB4C62EB224049F860FD68604B401722C4C763EA2240591FA11060604B40FA914D7E39EA22400A0029A85E604B40398915FB96E92240BD1C6A0E59604B40D5D114CE51E82240C37592C34D604B400823A0262AE82240966A72754C604B40FD1CCB8CF7E7224055FECDD14A604B4016577BC9CEE722403E37A1D948604B408B68936FB7E72240773DDBEB47604B40E0D0F86791E72240C41A5FF546604B40D510754354E7224067E8C4E245604B400942F70BEFE6224038427C1F44604B405893A6F37EE622401744F12342604B40DEBCD14272E62240D98AE8EC41604B40DA93877A6AE62240AAFED8CF41604B4090C096275FE622409A1622A641604B40A39D71C40EE622403CE2DC2940604B40FB4209C802E6224069CD29F13F604B403777037CE2E5224069939F323F604B40A13EA108CFE52240B27B006C3F604B40775B9F12BDE52240C339FEAE40604B40A1B80115F2E422408A36A5A74F604B40E4B4696358E422404F2368455B604B40DB7B1A7A4DE422409F869D345C604B4043B338551DE4224090C4BF8E5E604B40915501B014E42240E4F49D775E604B409BB4A4A314E42240A1317C775E604B40F5EF7FB411E422400426A26F5E604B408CFB551C0DE42240C23364935E604B40501964D708E42240CB4B89BE5E604B40C01AD9F006E42240F9CD24D15E604B4035DA36C2B1E32240D757091362604B40B1BC674AD0E222407F5200256B604B40C5E7A5EE75E2224038AC4B956E604B4017499B9AF8E12240B3B4233071604B40BE0F4D11D4E12240A5151E3572604B4016C3A58A9BE122405AE7D04D73604B406B52D14265E12240A58FA48574604B407023BC392BE1224031BD189175604B402797116B2AE122402674EF9575604B40C430A467F3E0224013C37EDF76604B40C2EC60B0F2E02240142102E376604B40774AD226C6E0224090C291E477604B402A89B84686E02240C0485EF778604B40A8B31C9254E022408F9F37D279604B40D6A9BABE2DE02240C0EA287D7A604B40BCBBCCFB03E02240A5CCD8E977604B406C7B96E8A7DF22404A632D3C72604B4016E4CB9862DF2240BA580C156E604B40D715F4821EDF224083E8BD056A604B406CB8C1A615DF22407BFA4B7969604B40363FFD1E15DF22403AFB6F6F69604B4071228B7C11DF224025ADE12B69604B4037E0A8710EDF224076EF54F368604B40B780428607DF2240DC09E17268604B407CE948A306DF22402F176C6268604B404E5A7D4000DF2240B888DFEB67604B40DE23D535F7DE224030E3056A67604B408DD3FC1DF2DE22409E2A154767604B40BE3BC0F1E7DE2240966F76F066604B400C77AAD2D7DE22408E46B4FB66604B408728EC007EDE22403131BF5268604B4054EEDE697DDE224039640C5668604B405038FC7422DE2240876515B569604B40FCDF83CB03DE224004EF020C6A604B402A1960A032DD2240060C35C36C604B40C8B2CD8479DC2240E341472A6F604B40447F23CF21DC2240E9DEE05570604B40460C96631FDC22405655F75D70604B4087043FB3EDDB22404C0CF80A71604B40BCB587D3E3DB224075CF292D71604B40044DBD83D7DB2240677CCD5771604B400C91F3B4D9DB22403E6AC73472604B40718A3C4DE1DB2240C506523275604B409B41290600DC2240E48CE25482604B4010652F5619DC224084AB20E98E604B40CC9AB0EF1BDC22406E12C64F90604B4082B2565324DC2240509AEB1B94604B40F4F7675524DC22407FA2B91C94604B409FD1622144DC224020994E7FA8604B40884BC03544DC2240DBA8568CA8604B406CBCFEF246DC224065D6F34DAA604B40351E633C48DC224051FB8955AC604B40E056DCB950DC22404EDC17AEB2604B4043962E305CDC2240CDF0AB85BC604B40E7B1A55963DC22408DC0C82BC5604B40520B93D169DC2240167E7EFBCC604B40E512D19B6FDC22406B60AD6ED6604B409EDEC53374DC22404B235865E3604B407907D15A75DC2240623C9050E9604B4043EB7EB575DC2240B2CA3922EB604B40270F2D2876DC22402A5B166FED604B40F127407276DC2240FB0A6DEBEE604B40DE4846F676DC224044597A91F1604B4010DDC3EC76DC22400FD25BA5F2604B402AD57DEA76DC224007ABF0E6F2604B405271A6E876DC224034B75D1BF3604B4063D145E676DC2240BD3EA460F3604B4048771AD676DC22401A83AF35F5604B406907F1C876DC22400FD6E7B1F6604B40DE2FA4B876DC22402BAD028AF8604B40701F032973DC22409117ECC103614B40BA49CA366ADC224046FE619214614B4053FC342F6ADC2240C9AC97A014614B409D812AA15CDC22408A92608025614B404FE722D150DC2240CB4D797730614B40183DF2E54EDC2240459D773F32614B40774697F04CDC2240BE84059433614B406AA3DF264ADC22400C14DA7835614B40E85316443BDC224031E272953F614B40DFA2B90726DC2240F2038A394D614B405D4B747024DC2240E0DA910C4E614B40A53C76180ADC2240788980B25B614B4032E5B19D06DC224079532D3E5D614B40293F68E0F4DB22407423531F65614B40201EF3D4F1DB2240EA668D7966614B400FD663F7E1DB2240125099856D614B40FFCE3891E1DB224016B1E4AD6D614B4076181A0BE1DB22403020D2E26D614B4098FC92E7DFDB2240E59ACD556E614B40ACB8A925DEDB22400CB2BBF46E614B400FD5372EC1DB22409241ED617A614B4026A5BE429CDB224066F0ADA486614B40BB044FB793DB224084800B4A89614B4012774AB792DB2240F5423FAD89614B402572B9AF92DB2240273F97AF89614B404870A63476DB2240CC6F548192614B40521FB4D673DB22404AFBF73C93614B408583998361DB2240CAE2923F98614B40A7532AFC5FDB2240B5B695AA98614B4024863B6C5FDB2240A884F1D198614B40AE82DCF05DDB22407F1AAA3999614B40243C86403DDB224038C4A229A2614B401E8B054338DB22403BBA2D7BA3614B408CD27DA72ADB22400B249613A7614B408ED2848C2ADB2240D335B61AA7614B40B0DF00ACEADA2240E3B135FBB7614B402A182475EADA22407079C408B8614B40A7645D2ECEDA2240E345BC05BF614B40A9B18D31C0DA2240DF9BAB7AC2614B40E0C2D679A3DA224090618193C9614B40BF3EAE67A0DA22400EA5CA55CA614B40411555838CDA2240905A4140CF614B40C0D06E1B42DA224040BF1B09E1614B40CEEE955DF2D92240CE572718F4614B40B7A13634B8D9224076A0BF8001624B408070EC78B6D922403CEAB0E601624B40B0FE175879D9224046DC8FF50F624B4081701B6240D922405E44D05A1C624B4004F6D57A3CD92240DB4E46341D624B408B5D0D4125D92240C7FD234222624B40FB42AA3ECAD8224091C1599F35624B40F97F3CF5C6D822400B1B605236624B40F238522EBAD82240E6CB520A39624B408273FFAA6FD82240DC31DC9048624B4096EF156437D822401BD9E2DA53624B40DF32CA1D37D8224054B09EE753624B4022F4294731D82240777FCF1455624B400A56F7FB1ED82240075D3CC058624B400B2182F2F4D722404BAE120361624B40C1CD1EBDF4D72240937C8F0D61624B40F7F7A2B7F4D7224011C1A20E61624B40608FBA2FE4D7224021F7B44964624B40B9E36D4BD1D72240061BE2FA67624B4054C070C2CAD722405CC6F53A69624B401E9650B0CAD722406D230F3E69624B40A0541F65C8D7224099FC65AE69624B40AB5242B790D72240B82F785574624B4095EDA07DE1D6224077508AE394624B40FFE93021E1D62240A3D5D2F494624B40D709A642DBD622408C01750B96624B40C33B4A38AED622407BEB9D659E624B40B581B50F93D622401B71E26EA3624B40831F145290D622408142C0EBA3624B40F5CE4BF97FD622401C218ED4A6624B4076B54AE776D62240667DD571A8624B40519F563A6FD622409B138ACFA9624B4004EFC0E96CD62240313D3739AA624B402B52A2426BD62240308CAC84AA624B40DE30020B68D6224096404217AB624B40E8822DF767D6224094F8C91AAB624B405901943C68D622402FFD302DAB624B409701513D68D62240E800632DAB624B40AC6C0E7468D62240297FE73BAB624B40A9B2D87468D62240E791173CAB624B405334A21C6DD62240E3AC5078AC624B408092BDEC6CD62240D51FDE80AC624B40C5256ADD6CD622402A359A83AC624B4091D2DD777AD622408119981FB0624B40BF1E2CCA94D62240991F9F16B7624B40488CE0DCAFD622403B498640BE624B4015A1F28AE9D62240AE76F907CD624B40E16F9F6EEAD62240F2CAE241CD624B404DB6C4F3F1D6224055558E2BCF624B400BEB17110DD72240FDAC1F11D6624B4069CB204526D72240EBE7377ADC624B40587A90CF75D7224095EE1038F1624B400021C9AE8DD722408BFBF51FF7624B403B6A39CBB9D72240913F9A0902634B40174A924CCBD72240F4683C5E06634B4010E00604D6D72240C61BEE0409634B40A946137FD7D722406ADFB46209634B40A132C090D7D72240811E466109634B40FAA197B6D7D72240E85EA26A09634B406F4B20DCD7D722406521946709634B406537CDEDD7D722407860256609634B409B531F64D8D722408BFD698309634B40142FF2FAD9D72240D0820EE809634B40E883D38ED9D72240FA2BA58C0A634B4052734692D9D72240DD5893950A634B40382A8C96D9D72240B285BEA00A634B4038AFBD9ED9D72240728029B60A634B405C0D14CED9D722406EE7B5310B634B40FD70309DDBD722401E5E2CBD0C634B405C4C89B7DED72240EF287C3D0E634B405E5F1711E3D722400AD8DBAC0F634B405D573F99E8D722406955CC0511634B40D008BEB2F0D72240C35B94E912634B4007B7F48CFDD7224012693CE915634B40280004D213D82240E44EEF181A634B406B26134135D8224016AD5BA820634B40A592990B38D8224023478D3421634B40AD9243F13AD82240A8FD14C621634B40F73492883BD82240A5EDF6E421634B405819FEB745D82240741921F923634B4016B8B00550D82240F8862B3826634B40EB3417A354D82240F771C04B27634B40978C571156D822401F872FA127634B40DF0E7B3956D82240872D8DAA27634B40EA1C6C5656D82240EDBFD5A727634B40B0090C9456D82240AA360FA227634B40468471015CD8224021B4701F27634B406C0E4A095CD82240E9C0B31E27634B40BB18293E75D82240155C6DB32B634B40A321393977D822400A6B930F2C634B405D1179A783D822409CCDE8512E634B403B8691D683D82240DA52785A2E634B40E811677784D82240F32B504E2E634B409AE3CEAC91D822409C08040E2F634B408539ACCCA0D82240B4698FE92F634B406EAA2037A2D8224047811CFE2F634B40CC957753A2D82240490AB7FF2F634B404F30A12FBDD8224070B5F03D36634B4017BE060FE4D82240DCA428373F634B40B2AED82FF0D822405A29A7DA41634B40F5C543F7FCD822406479427C44634B401131D21D04D9224068DD2FF545634B40542B085222D922406A4085334C634B4014D256DF37D92240CF73762050634B409907F42B63D9224050938EC557634B40571C163B7ED922401F1B78DE5B634B40EDE495D195D92240258568C35F634B4015492326AAD922408A6A2CC862634B40D05FD050AAD92240699E81CE62634B40A5ABDA3BC9D92240AB55B2A266634B40E630B24BCCD92240D1A3991267634B4066AB4583CCD922403703871A67634B40DF27FAA6E3D922408F5162596A634B40E8B9F7DEE3D922403F4B3C616A634B402F633FF211DA2240B68E673270634B403F94FE1945DA22408AD810B775634B401FAFF2F165DA2240BDDB3ECE78634B40661FC32379DA224063E39F9C7A634B4000FE62738BDA22405F28B9557C634B40C762CCFD08DB2240345BF08687634B40AAFD57011CDB22403F5F283089634B40AAFFD0A895DB2240E0CB28F193634B40310A596ED1DB2240E853584E99634B4041339AABFADB2240D127C1019D634B40F93F370C0CDC224045D31B7E9E634B40861B14834FDC2240A775403BA4634B40BD36D78A91DC2240EE42F4C3A9634B40AEE89F11A3DC2240AA810BF3AA634B409BDB8D0EAADC2240607DE46BAB634B404F7E4AB4ABDC2240E8004D88AB634B400BD41B3AC5DC224085356D40AD634B40D2DA3C6DD8DC22409AA98878AE634B4050F9D1CFF4DC22403E27821CB0634B40BF08C96F25DD2240EAE00A34B4634B409221C9A125DD224090F43F38B4634B4086822E8D26DD22409BD669D6B4634B40A482762247DD22408E7F57BBCA634B4002E2F22A47DD224014810AC1CA634B40CF51B0E177DD2240A11C0E10CD634B404389BB7578DD22401AE31117CD634B40B8E41D7B78DD224088465217CD634B4047DAAE967ADD2240513EDD69CD634B40D18F991386DD22403EACC62BCF634B40BE9FDA7696DD2240FB3BE73DD2634B40F5E6004EA3DD22404D48B8FBD4634B40137E12E1C0DD2240B71F2D4CDB634B4012B7F1F1C0DD224010DD1B4FDB634B40A9C35605C1DD224023F67952DB634B402AF03F20C1DD224078252657DB634B40198391ECC2DD2240F4588951DB634B400D96E1FCC4DD2240F33A164BDB634B4032CD3776C5DD2240F0439B49DB634B401C472C72C6DD224016328846DB634B409FC96078C6DD2240A7687546DB634B4002C34DD9C6DD2240DD592C56DB634B400EBB06E1C6DD224099E16C57DB634B4080F20F94C8DD22403321F49DDB634B40419D3BA3CDDD2240D6975BC6DC634B4035C9FD85CFDD22402228D434DD634B409D1FFF57D0DD22405A94E364DD634B40ECA8D962D0DD224028D46167DD634B408689EE7ED0DD2240B969CF6DDD634B400716D725D4DD2240ACC6C243DE634B40FCF17CCBDBDD2240F4BFC303E0634B404CA411CDDBDD224038F42104E0634B40F78D79C7E8DD2240CA470810E0634B4077D9B6C2E9DD2240649DB90FE0634B405028B909FDDD2240B622B609E0634B407D9A9C4911DE22408FBE5C20E0634B40E4F8857F25DE22408133F453E0634B406CD8D6A339DE2240120669A4E0634B4004E2BAAE4DDE224075339C11E1634B400DEF9F9861DE2240F627619BE1634B40F06C238266DE2240EC6EB2C4E1634B409E5EA6F566DE2240E2BA7DC8E1634B4017052A2D6CDE22401DA55EF4E1634B406F9BCB5975DE22408D7D8741E2634B40F187C5EA88DE22402961CD03E3634B4037497AD78DDE22404BFC7439E3634B4081C68B88DADE22404B976E17E7634B403702A7C3F3DE224042591F5DE8634B4082109D5314DF224080A77001EA634B40C682B3BE23DF2240560F76C8EA634B401903F09C3FDF22404AA52B30EC634B40700B259642DF2240E85A8D56EC634B405C1A21CB81DF2240312A6186EF634B405D36A960AADF2240CEE33292F1634B40355BD136B4DF224055E57D33F2634B40DCCE727FB8DF2240CB836C0BF2634B40FCAEB4C1B8DF2240CF2E0109F2634B4081A94BFDB8DF2240F536D306F2634B40159338CBBADF224083D4F1F5F1634B40F86492C9BBDF2240BC74A7ECF1634B40A9CDCCCEC1DF22407B634F95F1634B4037ED3B0FC3DF224017B62583F1634B405AF858EAC9DF22400B1CA6F8F0634B40F4EC4D33D0DF2240F7759050F0634B40A42FF03ED0DF224037FE584FF0634B40F2772443D0DF224055A6D84EF0634B404F2D816BD0DF2240C2EA9549F0634B40BA89A637D1DF2240C660FE2EF0634B409AEEFA58D4DF22402CA695C6EF634B400AF52217D8DF2240CC327531EF634B4042ECC066D8DF2240F4EF691FEF634B40EEF3E6E6DCDF2240AB0D541AEE634B40837EA908E3DF22407B6596B6EC634B4095764701EDDF22402C622926EA634B4014FF800AF0DF224006215541E9634B40B5FC0AF9F5DF224016073B82E7634B40ED9789BFF7DF2240204E24E7E6634B40DF41D8E8FDDF2240D2B8DFCCE4634B40110767DF06E0224039F5409EE1634B40	Flensburg 10	\N	fl10
12	organization	102	0103000020E610000001000000480300008D37E9FBC7012340D7C8533280664B4088FB8B1AD601234047353D1D80664B40C7792776E4012340D50EA14F80664B409678F452ED012340554200AA80664B40AB197B0A10022340B7506C0D82664B40594A5CBB34022340A3B8D7F280664B4015B9B25146022340F718B10D81664B40D56A072E4A02234065D7951381664B40EA2D99394F02234038884A4C81664B402DFF6B94580223409CBE87B581664B40361CCD4B720223404E7C0DD682664B408A438D2D81022340A625798A82664B409518CE27A602234094135F3C80664B40675C8D07B1022340FCDF7A387F664B40E490FE23B5022340E65C88B37E664B406B5D9BE4B502234056D9C2887E664B408FE0C360B60223408CD4326D7E664B4054BC506AB60223403AFB116B7E664B40ADBD6D57B702234025026C367E664B40C3D5B764C1022340762302FB7B664B40E4C51F66C90223409DA476F275664B4039C3D2D1CA0223400DCE58E074664B4008611534C8022340DDFBE9B472664B408F7812ACC7022340F9E14F4672664B40E134D147C2022340246A609A6D664B40257BBCE6C4022340AF96FD006B664B40C71E6960C9022340127C68C169664B40409CE266CF022340A1D1241368664B4038099323D30223402FC9450867664B40AA5CECEAD7022340EAB702B365664B40CF82EEDCD9022340CCB0182865664B40FF71A1C3D902234032D8F5AB64664B40E5F464B9D9022340655DA87964664B404F469B21D9022340DDA8279061664B4090713D97D8022340DAA6A5E85E664B40CFABEFE1D4022340AA02E65A5D664B40EBCD08CBCD0223402C2F81625A664B401A1348A4CC0223406ECB02E759664B407D8F801FC8022340EA11AB3259664B40E8527C6AC30223405B8DCE7658664B4047DCDCF1C20223400EC5FE6358664B4031BF64A7B9022340F057C59E57664B4035894171AD022340375AF0BF56664B404B4B3148A4022340879FC06E56664B408A734F06940223407910ABDE55664B40DA1EA0486D022340B6BED6E255664B4054FAA84469022340A74E44E355664B409736DB8167022340BD21A4FE55664B407AC7CE1B5F022340514B318156664B4089DD46BA5C0223403159E38D56664B400E556BBE3802234055A9824C57664B40908806873002234083A8097857664B40CD13C7672D02234037A1872357664B40E3974EBE0E0223407C7F9AE553664B40FDDCAEB60C022340F47AA8AE53664B400E72CD7D000223409E73D20053664B40EB420446E70123401297D4A051664B4032529246E701234051467EA151664B4060E01E39E701234057DBC0A051664B40FA5476DCE4012340F7569F7F51664B40AFD8480ED7012340CE26F6724F664B405CF5829FD10123409C7680A44E664B40785D2DBECF0123401C8C5BC84E664B4024DBFA41CD012340E0E8C1F74E664B404FD21A41C5012340DF70A9D34D664B40CBB4A02ABD012340B2847BAC4C664B40DA23410CB0012340DCD8B2CD4A664B40532D52CD9B0123408A88323848664B407E43EB9B840123403E1EC34245664B407A4D93E6820123408111F80A45664B406481C554580123401DDFD3E243664B4029A19FCC570123407711ECD943664B40911964C65701234013C97DD943664B401D7F57503C0123402F876AF741664B40F393B8CB29012340F1FBFCE940664B40F721FE1F09012340AAB9E2A13F664B40F6382EEBF20023400A8C33583D664B40C1FB6D9DD3002340271D10CE37664B405052F370C6002340E588587935664B40098B3825C50023403B4BA33E35664B4024E0BEC3C30023406A9E190035664B40F20B5154C20023401EC316BF34664B40FCF0CD04BF00234082CEC68C34664B405CDE8401BF002340522FD58C34664B40CE5F8F80B2002340ED3D6FC134664B404F3A10D06C002340E93097E635664B408506828835002340950FE28B36664B40A989957317002340E5A34CF136664B402D4CFEFBE1FF22400FCC9D8B37664B40AF6CD2A4A1FF2240D332284F38664B40821ECE288FFF224010E2CA5738664B404CECF5898DFF2240DF720CA638664B40F219882E8DFF224025FC4CB738664B401A24174B7DFF22406C1CABE238664B40895DF1827BFF2240558F80E738664B400A46019375FF2240F1B58FF738664B403A98D45876FF2240E6F1D08D38664B40D45F0C0F82FF2240AE2E942332664B405D70394582FF2240B462E50532664B4091FE5E8383FF2240CBD0A25731664B403D6C7D8483FF2240F30E0A5731664B40BB559E0893FF224051AE4DD728664B4017E996B1ACFF22406405CD9B1A664B40823CEAEBC9FF22400AD43AC60A664B405FEA70BFD5FF2240EE598E5D04664B40B7A7EC15D6FF22401423F92D04664B4006C5A517D8FF2240264F7EA604664B40722AC755DAFF2240DD392F2D05664B402EF13C01E0FF2240E8CFB48106664B40D1BCA9F2E1FF2240630C28D905664B40E4D5DC4FE4FF224063528E0B05664B409B8DF088E5FF22402B6642A004664B403CF305D0F5FF224071DEEB0B00664B406A629391F5FF2240E34ACEB6FF654B40B3E7B0D9F4FF22409B80D6B9FE654B40666B1ADEF3FF22406E870167FD654B405976B0B4F8FF2240A1E2FB22FB654B40B5C6023FF9FF2240AB7331FDFA654B400E6515CCFDFF2240B670E6BEF9654B408785C11A000023404E51891DF9654B4040B5C07BFFFF22406004A182F8654B40CE35D36DFFFF224037340975F8654B40D938EC01FFFF224092FCEB0BF8654B40522F4A50FCFF224037230D6CF5654B4098BBEFEDF4FF2240E7CA5ED2F2654B4094C2382BF5FF22404F447E84F1654B4010B2DDA2EDFF22400E9BB64AEF654B4003F25882EBFF2240FE35D3A9EE654B40EEFCC042EBFF2240EC354A96EE654B40A9BBBAF0EAFF2240EAC089A3EC654B40E18059AAEBFF224064F424D9EA654B40F849D7CBEBFF2240CFAE24CCEA654B408B6F205DEDFF224019917430EA654B40C5F8EF52EEFF2240710918D1E9654B40FC8FB8C8EEFF2240F7D362A3E9654B40886A62DCEEFF224039D121A3E9654B4030B5686FF0FF22401EDFF39DE9654B4082FE00AA0B002340546E5444E9654B40FB9100DB1A0023401D4D5412E9654B40152BFA1B3C002340A0EEFA8AE8654B400095DA454A0023403677510FE4654B4054CA92CC510023405EF1DBB7E0654B40AE466B1D56002340686552CDDE654B408737146F5600234073450DA9DE654B406108D15C60002340BF7A9940DA654B4069F038DC610023406068639FD9654B407A34CDD965002340D870D9F1D7654B407AF3D8EA69002340E63A969DD5654B40203170426D0023404F5E86B3D3654B40AE4543EE700023407C9EDE09D2654B409E7460E0730023404ABB51B4D0654B4082A09A4A7500234010ED4110D0654B40B5A5AAA67A0023401D044484CE654B408520A1C97D002340F8C2869CCD654B406941DAB18900234010F459E0CA654B404600106B8A00234014CDE9B5CA654B402D70370D94002340267EF97EC8654B40EEB0765C9C0023400C6FFE91C5654B40AF03AA219D00234044804753C5654B407AF55BC1A7002340AEFC5BF2C1654B4012AF05C2AA002340C4086004C1654B402CC95BC3AA0023403289F503C1654B40C08F62BDBA002340F616AA11BC654B40180EEEC0BA00234076AA8710BC654B40F17A8CA5BC002340F7030082BB654B40791B8FD9BD002340A8197A1ABB654B40BDF7A48BC5002340E9ED4281B8654B405B4AF11CC9002340EFF6354CB7654B4084104121C9002340035AC04AB7654B404ECA520ACD002340B86601F8B5654B40ACD3B2DAD40023404923F754B3654B4044F2DED6D6002340E61E61A9B2654B400D01CCA2E10023404CA32EB9B0654B408A070E98E40023403AEA3C31B0654B40A1B578C3EA002340DF114676AF654B400168976117012340034E332EAA654B404DB5F7541B012340F0D47AB6A9654B40C5FC5FBD41012340B6FC48ACA4654B40E01C948251012340CA89879AA2654B409608BF0F5F0123408EA6F151A0654B40B8A1D2CA6E0123408D5458AB9D654B401C8574A7760123403732CA579C654B406F63E04D7801234065868A109C654B40B4AB3F7C78012340587DB8089C654B40DE59707D78012340FF1084089C654B40FB091081780123408692EC079C654B404E05396F7C012340280F325E9B654B40E29196F684012340A7E57B239A654B4031E4C06496012340D2064DA097654B40C2DCA1DD97012340DE5AC55F97654B40B3E8008AAE0123404006F17D93654B400A9D770ECD012340F34E707490654B40A287A6F0D8012340875BCD8D8F654B404403C5EBD90123405341C37A8F654B40EBC13FAFE1012340E01A15E48E654B40E3298A88ED012340C9E6E7778D654B403582920807022340B67A22208B654B40DD8A40220B02234001877BD88A654B401F84B00A1A0223402D2CFAD389654B40EC1867E22E0223405E81E5E286654B40957DFE313B0223407965596185654B40329749DC3B0223404413864C85654B401C8DB9004102234082777AAB84654B406415265942022340F247578184654B40F2FD18144E0223402FC0534E83654B40C217A5F16D022340B8DD530C80654B4064AA607A88022340B96CD8557D654B4008A4894A940223405026CC637C654B40D27CBD69A7022340B7936A557B654B40DD94E2A6A7022340608D2B6E7B654B40E52C2334A8022340C9AD60A77B654B408B1627A8DF022340D4F903E478654B40E3EF3530E0022340218C41E678654B40F1735953E50223400213E1FB78654B40E8728447ED022340F7F15E1D79654B40B45856DF03032340D7408A5B77654B40EDEFB3031003234039D5F03E75654B409D487E2F42032340EDA4538D6D654B40B8C6EE14530323404BB023C26A654B40364B08B469032340F49DDE8A65654B4072B9293C820323403B72CF2B60654B40503E55538F032340A920BCFD56654B402A80BF1D8803234033C5C13C54654B40E40B1C3F7F0323405371460A50654B40053546137D03234068822C034F654B40C67966BB7603234085039AC948654B40A75EB7EB760323403C54BE3945654B40173F25C76E032340CCABE59644654B4013A3F57F6A032340C51B1B0644654B40359B524B6A032340385B26FF43654B4094F844DA6503234087E5D06843654B4014E465B2650323407FE48C6343654B40AEE3211F5E0323403899276342654B40704121B95C03234016FD332442654B4076AB6AA74D032340F8C8FF783F654B408BAE11F03C0323404F74D7113C654B4049C06E091C03234093C4C0CF32654B4022AB9D1817032340FC8DD76B31654B409C18ED771603234068781A0431654B40E7C489730903234086D2089D28654B40C9CB44C3E2022340CAA2E2D823654B406C96FBEEBB0223403855F3B41E654B40C8FE66AB88022340C921B66019654B4037A1FB8F640223400BF0A4C315654B401E74DB7354022340017315F313654B4062B448B83F0223408652379D11654B401905B17026022340299FE2300B654B40CB179E7427022340BB9B91270B654B4047B6998028022340DA2DBAD708654B406AD2930B30022340C03F170906654B4074FA5A3E43022340241E2D7402654B40D1DDC9E546022340C94F7A8201654B40D7A2442A58022340C0434E0CFD644B4059F2C72A6A0223406B3BA9BBF6644B403566AF9771022340713FB5BCF3644B4038328922730223400160671DF3644B40555C62D877022340E653C1BCF0644B40B79A17787D02234073BA4DE0ED644B40961B5A837C022340C0D9AAD6ED644B40393C4C447C0223405F542FD4ED644B4044239E917702234011EBE2A4ED644B40604D2A5C660223406217E0F6EC644B40C36294756C022340A0E845D2E7644B40E14EEB3E6D02234086902E18E5644B407FD524076E022340BDFAE961E2644B40D5884B536F02234093733FE2DD644B40AA53CE09750223408F3C6E5BC8644B40204604A1770223407DE92CFCC5644B4037CAC0DC7B022340E18B67ACC4644B4021AC9DCD820223406314674BC3644B40A8A096C08A022340AA9C668EC2644B40101DD5E9780223407ACB604FC2644B40FCD78CE72D022340C23DF10BC0644B4053B5BAD8FF012340A8BB23A8BE644B40C804C933F50123405D9A1A61BE644B402D6C265DB00123401DE1B795BC644B40E9D206819F012340756786A9C8644B406E9627EC9F0123405EE1A9D4C8644B40128E1FA0A1012340366B4384C9644B4036D4F99D870123400D4C292FCC644B40B5DDB7DE7B012340D7B54533CD644B40AD2DCC7861012340C49DE0FFCE644B40DD9F9DEC490123409684D130D1644B40229858EA3201234058942C49D2644B4021DDA3BF1101234093331D04D4644B40D0084E7B0E01234015941AD9D3644B404BAE26A9030123402346A14AD3644B404051EBBFE400234041A8A5B3D1644B40B8E9427ABD0023400B3593AECF644B402B2C4976BD002340A92660AECF644B401ABE9FF6B60023408F99CF58CF644B40389C77029E00234099924010CE644B409EC528A084002340BDE1886AD1644B40E3468B4D7F00234029A05E88D1644B403A0C31027E0023409F54F683D1644B4032E804435300234082EC40D9CE644B4072F95A2550002340B63ABAA5CE644B40892338791D002340A7A5AF5FCB644B409FBEE93EE4FF224069786C57C7644B40028F72CADBFF2240FA3C2265C7644B4036BB59A2D9FF2240F58DA068C7644B407BAC745FCCFF224017C4217EC7644B406F17B09AA8FF224096288928CA644B403A5043AC84FF2240C3A79796CB644B40BDFD6EA382FF2240BE0B51ABCB644B40F5B37E7D4EFF2240CE135207C4644B40046AB2AB3AFF2240F878E5CEC0644B405536886235FF2240B1E10B8FBE644B409A8BC6F535FF22404D26F25ABE644B40F7FBA48F42FF22404C08BFE5B9644B407265C4D040FF2240285F559EAD644B404093FAB12CFF224046D017E9AA644B409529380A20FF2240C7702135A9644B403073224B13FF224059326CDBA6644B40F80DCCCEF9FE2240823D24D4A4644B402E408009D2FE22407D8C5930A3644B40C1BEF59D9CFE2240002B9658A2644B4029B4F39497FE2240ED7A3EB7A2644B40EB771E528FFE224053AB8352A3644B40C4A4D0527FFE2240B9ADA87FA4644B40D05D705173FE2240782CC983A5644B40A6F738586AFE2240F31A42ABA6644B409EA67F7C55FE22401F991FA3A9644B4075A06FF34BFE22407D60DC74AA644B40B101B38A31FE2240D2932735AB644B40120EE4A228FE2240EF1B8042AB644B400E08894021FE22400B21904DAB644B408EAD09081EFE224084F56252AB644B40000023F60FFE22407AA0063DAA644B40742A4115F1FD2240298F92ABA6644B4087CFAFC1E6FD224092AB53E7A5644B40160A4A44E3FD2240624A965AA5644B404998BF53E2FD2240FC0AAAEAA4644B40B5D305E8D7FD2240B3157413A0644B40B05B8CFBD6FD2240C473214698644B400096F3EED6FD2240E36A0CDB97644B404BD7FA4BB8FD224006A1F82297644B40FBDB7C4A97FD224002A9C31B97644B4014EF1D5D7FFD2240A5C447B797644B40492854392EFD22407814EEDA97644B40620F673005FD2240CAECFD5A97644B40CDE3F7D6F3FC224085F9738497644B40761E55D8EAFC2240E6594EB997644B4079B174739BFC224073C3506499644B40C43F7E6D3FFC22404F10CFAC9A644B403A00024819FC2240B95A19B69E644B40834107370DFC22403113D36B9F644B4042889D59DDFB2240D3BA5AF0A0644B403B8CEA59D7FB2240E54732ECA0644B401462E3B8CCFB22402732D6E4A0644B40C003586EC5FB2240A48DD5ECA0644B40072BB568B5FB22409E4E0758A0644B40108A44EA9CFB2240B01D369FA0644B40B5BFF4D577FB22401BC5A680A6644B405C65174662FB2240F0099C71A8644B403389F93559FB2240C7CF0E59A9644B405F85865257FB22400845E176A9644B404B703F9145FB22409D9C65F1A9644B40949703CF27FB2240C7B921CAA9644B4030F4D0C91AFB224027C30264A9644B40300AE4F5FAFA2240A22528DDA8644B4078C4B646FAFA2240B9983E0BA9644B400B609B82EAFA224017363D79A9644B401C0BD0C2E7FA22403E676B8CA9644B4072B30F73D2FA2240A4C52B82A9644B4009155400B8FA2240C90B2876A9644B404E7675B9B6FA22403061E234A9644B4042AC8499A9FA22404614FB95A6644B40B7FEB3287CFA2240CCC23D839D644B4028B8C07F50FA2240D3B28D7E95644B408C2178B94AFA22401D15EA9094644B4058173F0340FA22405C1519D892644B40523F35FF19FA224028858E5B8D644B404B6A943207FA224042DAF8EB8A644B40867C32FE04FA22409D7622C28A644B40A2763B1B02FA224076FC5A8B8A644B40735B0905F6F9224079167D9089644B40D833516BE0F9224084C2373688644B4022CD69D1B9F92240FB8DB39886644B4097164C768AF92240A9482C8E85644B40376CED378AF92240B32510DE85644B40873F42F886F922402F89EB068A644B400E2403DA81F92240EB077B2C8E644B406F1AEDD97DF92240F7703E4192644B400244D9907BF922400865E06F96644B408AC1F34979F92240DC8695C997644B4033A8583278F9224076FA62819A644B40010EACD772F9224072E9831AA0644B40712F0DB46EF9224079E0B026A0644B40701EC6113CF92240E8C296BBA0644B406A83BAA627F92240B2443A9EA0644B4078CEFC4AFFF82240B3E4A516A1644B401EF25482ECF82240C2E10185A1644B40D907130EBBF8224021766CC0A1644B40161DB2C5ABF82240FA5D4023A2644B40F26BCB52A5F822408D12EF4CA2644B4048D4ADF160F8224023140691A2644B408B543D0743F82240F7AB13D8A2644B408C0F2AC02EF82240E0282427A3644B40C39226880AF8224097CEF73DA3644B4042D48B94FCF72240A916A053A3644B40B1EB970D94F72240FC909BBEA4644B406086C0F56AF72240D9851228A5644B40FA0504E64AF72240AEA5DB46A5644B40155359B224F7224012D11D19A6644B40B09F9E8414F72240F78D0012A6644B40D53E40EE03F7224035F39067A6644B403129B0D1D9F62240F45A1CD5A6644B402454DD2EC8F62240E982FC20A7644B40B4035B68A1F62240EAF4CBC7A7644B40359615278FF6224019E1D004A8644B400346EFDE7FF622405290E537A8644B4012D1B36563F622404F671297A8644B402D15EC7956F6224069D042C2A8644B40845B500F07F6224040F1A7F5A9644B408FB560C103F62240002B7302AA644B40B54450A7ECF52240406BE954AA644B40DDA30725CEF522401DDED0C1AA644B408A3B229D99F5224099064F7DAB644B40E913D4285BF522402C73F1A0AC644B40F7822F4551F5224083260FF6AC644B40C6F271393BF52240CFBFCEB3AD644B40D41B8FA245F52240CF61FD95B4644B40D2DBF2354FF52240FBC8585FBA644B40BADACD5D4FF52240E77E6C77BA644B408838553450F52240F51CB7EBBA644B4053F633C35AF52240744F19BFC0644B40CAE024746EF522400BE6849CCB644B4042200B2575F52240E78393ECCD644B4072EEF9A87EF5224090A8DF85D0644B40E0518A147FF52240B7CDFBFCD2644B409A05972A7FF52240E55AFE77D3644B40231A9BDF7FF522401A496DA4D7644B40A933A1296FF52240458E5E8AD7644B40C13445B33AF522406B7D9038D7644B40D157F24831F52240D3EFE129D7644B40F47C82BF03F52240B1446BBED6644B40F79053F4DBF422404580DA43D6644B4072F15691B4F4224079BFB7D0D5644B40B010A2B28AF42240C775FC64D5644B4003E2C9285EF422404FABFAF6D4644B409F2DBD1B34F42240FD281898D4644B40AA5F8FCA0BF42240A0274E40D4644B4012A2F645E2F322407299DBF1D3644B4004C128A4C1F3224089E404B4D3644B4072750780B9F322408F1AC0E4D3644B4086DABCF39DF322401FFBE2DBD3644B40E185BB4562F32240F731345DD3644B4086BEC10562F32240363F70AFD3644B4072F42BE44BF322409E5B9C2CD3644B40DC213C6B46F322405A84660DD2644B404C7B466043F3224023074290D3644B40B463E54B3FF32240D43BE596D5644B403EB6910E3EF32240CE5F7E34D6644B40FEFA7B043BF32240847EAF27D6644B402FA0E9FB3AF32240CF0F8332D6644B40E9CE5EC93AF3224064686072D6644B405B426E7933F3224016D8444FD6644B40D706ADAF29F32240FE444620D6644B40249B2C6925F322409839BF0BD6644B404602FCB45FF22240FECF6956D2644B403D713E733CF22240CFF96BB6D1644B40FA0553E4D5F12240864ACFBDCF644B40B6BFDAA6B6F122401F951824CF644B40E93AF8E3AEF12240043AE5B7CE644B406780FF40ADF12240897B13A1CE644B40A22385850CF12240D0CB2FA5CB644B40BDA9253108F12240000FB6DBCB644B40CF2EF69F06F1224037D1A94DCC644B402ABB7BD103F12240E95ABB19CD644B400D86855400F1224030F75C17CE644B4067392DFDF6F02240E307FBEBD0644B4014163595ADF0224093A81487E6644B40914113FEADF022406E75530AE7644B407CE906E992F0224012E30A3FEF644B40CE1AA34A6DF02240FD5549A3EF644B4033D74A9C60F02240DA4214C5EF644B40CEA6DFB23EF022403930711FF0644B405359F6DD14F022405763DEC6EE644B402195B8B414F02240A41859C5EE644B406FFB34F909F02240566EE96CEE644B404BD68A42EBEF22400DDCD06FED644B40D0B256D7D6EF2240222E067FEC644B4081E392D3D6EF2240F4B8DA7EEC644B40C46FDCCFD6EF22407840AF7EEC644B40EA3CF248D6EF2240ACAB7578EC644B4011A5F540B5EF2240A34EDEF2EA644B40582E19D39FEF2240D5F16CF6E9644B4095EA8D749FEF2240C19013F2E9644B407CAEEABE9FEF22409E3958BFE9644B40E4710330A4EF224017078C06E6644B40F990CB80A5EF224021FA0721E4644B400F577E66A6EF22403E65373AE2644B40803FECE0A6EF224026C69752E0644B40E4C5E5EFA6EF2240719AA66ADE644B40AD2F7E93A6EF22400D4FE182DC644B403AABBBCBA5EF2240381ECB9BDA644B402EBEE698A4EF22405B8BDDB5D8644B40CA5E1BF3A0EF22403A8A77EFD4644B40162D21819EEF2240E5BFF90FD3644B403C01E5A59BEF22404CE59933D1644B40B01E356298EF22404838D55ACF644B40429ADFB694EF2240891A2586CD644B409F3ECDA490EF224006E702B6CB644B4037431C2D8CEF224069EBE7EAC9644B4074B0EA5087EF224033994925C8644B406F999A9779EF22403576EBC8C2644B406EB7BC0145EF2240DB76DFB2AF644B40EC61728A15EF22405ABE5A789E644B40CE693478ABEE224041C9DE2C78644B40E4AFBF2DA1EE224020AE769374644B4037D520DB9EEE224048FD8DA273644B40BE422F569DEE224080C08C1673644B40A2043DF09BEE22407DACF37372644B4018B90A2098EE2240F66575E870644B40EED09C5490EE2240CC72202E6D644B40950450D089EE22408726C76669644B40D8891E4789EE2240322B6B0269644B408312B6C088EE2240D68FEAB268644B402B637BB488EE224050309DB368644B4054C4351682EE2240B9E2D01469644B401792F03B80EE224074FDE73569644B408343D6A77EEE2240E94AB16669644B4023F621727DEE22407AF73BA469644B4010C398AD7CEE22403E9BD5EA69644B409283EE7F79EE22401DE381A66A644B404D7A0CE776EE2240870148E06A644B40B93367F373EE2240C480A6F96A644B403B12A84363EE2240C19349746B644B40F0A8FD2A55EE22408A624CF56B644B40BC74D43B47EE2240422C7E8C6C644B400F3B752941EE2240416A93E86C644B406101E5443BEE224002DC67536D644B406969E69435EE224004567ECC6D644B40523DDE1F30EE2240B70B52536E644B40912708EC2AEE2240111247E76E644B4028294FFF25EE224088FDB5876F644B409B5BF6B521EE2240812F4D2770644B4088D4A29921EE22405007F72B70644B40D97724111DEE2240DCDA1CEB70644B40C1885FDCF6ED2240C6ED979D78644B401DDEBA37EFED22402106C8277A644B40D849FA39EFED22407DE1482B7A644B40E54CDF3EEFED2240BBA007337A644B40F8F90B09F5ED2240068C2F257C644B402801DF3502EE224014DB682F81644B402712262E0EEE22406CED994986644B40CF674FEE18EE2240CFFA39728B644B40B010197322EE2240485CBAA790644B40A9FF8C4429EE2240FF6E6EB595644B405BB674DB2EEE224089302D869A644B4032DD4A9733EE2240BE10D25B9F644B402AD73C7737EE224043EA8A35A4644B40AE2DA07A3AEE22404F7B8712A9644B408AB5AF013CEE2240C5DE955DAB644B406D5397BC3CEE224050D34076AC644B40FCDC9B913DEE22405D3F0FB6AD644B4031BA9F533FEE22407F234F5DB2644B403FD6D7BF3FEE22400F5C3C06B7644B40B9B71DD63EEE22406115C8AEBB644B40B2C189283EEE22402D7B3937BD644B404E147FC63DEE224087FAD514BE644B4024C228B13CEE2240AA6FE487C0644B409963E63E39EE2240E2F0FA5CC5644B403B438F1839EE2240252BDD83C5644B40F4E9C4C737EE2240EED359D9C6644B40FB169B8034EE2240CD952E2CCA644B40C5BC2B782EEE22409120A4F3CE644B40989D37C928EE22406978C583D2644B40E634F4A327EE2240E38BA23BD3644B40034A8FA127EE2240C45BE73CD3644B4012815C7C27EE224096BDC23AD3644B402DE8E8EE1EEE22402F995AAFD7644B40F064593816EE2240934D45A6DB644B40F5A812A90BEE224016E4FFC4DF644B40967AE1B109EE22402DC6D06BE0644B405F76648704EE22407DA13A22E2644B40535FD50BFDED2240AEC1E46CE4644B40D182B7E9FCED2240D8525677E4644B40C48CCBD1F4ED22407D81C9C3E6644B40B1507B41ECED2240307A1007E9644B40E5D2AE3AE3ED22404198A540EB644B400BBCFA8DD9ED224052BA597DED644B40D3D2EFD1CFED224035C1B894EF644B4045696E74C5ED224053CB3AAEF1644B402C60587CB8ED224007ACA422F4644B40F8339F15ABED2240EA00858AF6644B40115F6093A8ED2240E0BCECF7F6644B40AE176F429DED2240400673E5F8644B40E5981C058FED224090B80B33FB644B40F7D2166080ED2240CA31E872FD644B409F84DA5571ED2240B352A7A4FF644B40A6E2F1E861ED2240DBE6E9C701654B4035C5F41B52ED2240B58056DC03654B402DAA18C451ED22403BC20FE803654B405CBC2BFD46ED2240AFEF2F5805654B40D5425FCB45ED22408812FC8005654B4079D0C3C639ED224029A0343107654B409C2F92DB34ED224061E671EB07654B40CBC31A102EED22400F49B8EC08654B405CA369A922ED2240734D3BB30A654B40F5B98CD30CED2240B6CE08600E654B4092891B6802ED22407227B44510654B40DC1A0A54F8EC22409A96203512654B40B2843574EEEC2240D940EA3514654B40FCD8E13EE5EC224050C35D4716654B40838B39B9DCEC22409199526818654B40C85423E8D4EC2240E2148B971A654B407CD10DD0CDEC2240AE91CBD31C654B4010DA9548C7EC2240C689422E1F654B40AD379862C2EC2240D31E3DF220654B40D9209504BDEC22403D7BD3C923654B40405C8DCFB7EC2240584EA49726654B40684B5B7DB3EC22404588716D29654B40EB985410B0EC22406045C2492C654B40DF4D3B8AADEC2240F8540E2B2F654B40594E74ECABEC2240B154D50F32654B405BD9C337ABEC224076508FF634654B4030D0DF3CABEC2240781A813E35654B40918C5442ABEC2240E90B9E8A35654B407B089E6CABEC22402067B4DD37654B40E6D6E38AACEC22409DFEB8C33A654B40A87CDCD8ADEC2240A41752963D654B40BC17FBACAFEC224050CC5B6740654B407378D27CB1EC22404C196B9142654B40AEBBE906B2EC224003F5523643654B4055512AE6B4EC2240AD85B20246654B40C9346D8DB5EC22404E79208C46654B4086C03E4AB8EC22400472F5CB48654B40CCCE19C9B9EC2240CD4693DB49654B40AF098132BCEC224061939A914B654B4049E84A9EC0EC2240D5F81A534E654B4048A5B38CC5EC2240A979F70F51654B409CF2E808C9EC22407892641A53654B400132C0FFCCEC22403F38222055654B40F415F562D4EC224033C4615758654B408E4EEFFBDCEC224090DA657E5B654B4017D027C4E6EC2240DE9CC2925E654B4092F4F1B3F1EC2240B92B149261654B405F5E5D92F9EC2240A2CEB95063654B40870CC3DF01ED2240434F820465654B40918165990AED2240A9CDD7AC66654B407B3918210DED2240F0AFE41A67654B4095AF53451DED22400357F3D869654B40CD07D1243CED2240C0ABC9376E654B4046F690EA53ED2240598E642571654B402144FE4666ED22405818CF0E73654B40ABC698426DED22401080EFC873654B40BAAC52206FED22405F1C87F473654B4069C5A0E572ED22401F6E9D4C74654B400EB319787AED22406F5F81FD74654B40BB144CDC7AED2240F100760575654B403297FED995ED22404A8DB42977654B4089E9CEFAA3ED22403F6D672078654B4001DE3893ABED2240D7DC399278654B4052FE16E4B3ED22407505D90E79654B40196F4951BEED224013FC16AB79654B409898658DC7ED22409479242E7A654B40F8405CD9D8ED2240E61C9C237B654B40B3A5B990F3ED22401DB1D2897C654B40FE69FB2E51EE22408476BEEA80654B403227C4957EEE2240C772995983654B406FC8B4419EEE22406183340A85654B400D8A9F7ABDEE22403BFF61E586654B401E09D835DCEE2240CEAA7CEA88654B40E75FD968FAEE2240AFADD3188B654B40C07E5D880DEF2240E1CF4E8F8C654B40697E99D032EF2240BD8362698F654B40781557F7ADEF22403ED13C1E9A654B4027C04809D6EF2240BD7CCB6B9E654B40D44EC3470DF022402EF8765AA4654B4004B16DA91DF022404B2DCB1CA6654B40628A11DF42F0224060521413AA654B4026A2B352A2F022409890C2ECB3654B40749203AD12F12240AD27D1B1BF654B401D7E080B1DF12240B923D7C7C0654B40B2CB2A6687F1224022F2FE96CC654B408117EA6DE0F1224089C89579D6654B40CB0AA26640F2224024EE59ECE1654B40FA6EE2999CF222407B480066ED654B40815946D513F32240E89B5539FD654B40D4AA835821F3224082132215FF654B406A49448C2FF3224052D4340901664B401B0C8CDA69F322407C37300E09664B40F2AFD59CADF32240C0C624FA12664B40E9679789AEF32240E0E3CE1C13664B405D162E5158F42240FC1B76672C664B40B994FC4C58F42240886F30682C664B40C4510FBA5FF42240902006822D664B4042C420C579F42240999E2A6331664B40B6C4461424F5224094516DCE4E664B4002ACD2C52BF5224095A0032F50664B402EBF62806DF52240219F3EF35B664B408CDCF8F08EF5224056F316C261664B4034B75319B0F52240E443374B67664B400FDA2CFABCF522404F05BD4569664B40081E0120D6F522407081D7226D664B4078D41687FFF52240C61B801B73664B40C18836791BF622409E9A17C576664B408239D3E127F622408737686578664B40736901A650F622402DB3569E7D664B40312ED7E36AF6224050D539A080664B40ED37A7A06BF6224019623DB380664B4093F0DF8E6DF62240ED86B0EB80664B40B440482E71F62240859F9F5581664B40282692D274F622409E471CC081664B40621EFA1377F6224020330F0282664B40A436BAF179F6224087E6DE5582664B403CB5F355A3F622406055E8DA86664B40609856A5AAF622401CB73FA787664B40D6F78B17F1F62240031975C98E664B40215E14E80BF72240EC66D91991664B407AD21B2E13F72240754B8ABA91664B40D235D08835F722402FB7E79A94664B404CD9232658F722402FE96C6A97664B40951484047BF722400A72F9289A664B40704031C69DF72240F7D2F8C39C664B4085F76732C1F722406D86342D9F664B40896D338AC4F722405687C3619F664B401035DA3BE5F72240946CC463A1664B40B0FC2CE7E8F72240DBAF6997A1664B4080B6EAD409F822400CB6D566A3664B404AB9A3B751F82240CE7CDC31A7664B40F0D863A166F8224075B35A4CA8664B4081B42E8668F822405B5BEE65A8664B40511DE7D0B9F8224008ABF9AFAC664B40A98B4E5F1EF922407065D6D7B1664B405647FDDE29F9224024EB736FB2664B40530D87A28AF922405759506BB7664B408D9948A3C9F9224020EDB19EBA664B4006099FA70CFA2240C3DC4106BE664B40021D5AD525FA22401C699248BF664B40AF597CD925FA22400C62C748BF664B40FAC6D21308FD2240E57C6DE5E4664B40D43A67330FFD2240DA466543E5664B401CA27ED312FD22407EF29A71E5664B4046ECD2C6ABFD2240490B2D3CED664B401017BDBBE6FE22400E450947FD664B40FBB9528CEEFE2240D984EFACFD664B403792EB25EFFE22403D08C1B4FD664B40F3CC462C2CFF22407B1F1FD000674B40B2A96CD948FF2240AA4FDE4502674B40732FA5A55CFF2240B40FE64703674B40327F1E3C71FF2240C9E0554C04674B400B7949848EFF22405899C1BE05674B4045681E95A9FF2240F995EF0E07674B4041A145CEC4FF22409C9E474D08674B406F71A014CAFF2240A2C12A8708674B40F4B899CCD4FF2240A6E1CBFC08674B4036358C2DE0FF22405851AD7909674B40D807C9B2E6FF2240833599BC09674B4064AF2375EFFF224098E17E160A674B405BAAA4B0FBFF2240A32F08940A674B40E098189D18002340CF2CA7A00B674B4028E49C9E18002340D936B6A00B674B40A1C2A3A21800234011C0DBA00B674B40C0D3158233002340AD003F8A0C674B409A2D63B0350023400037309D0C674B4063EFB23B38002340D8B460A00B674B403FFE13E33A0023400CCAAC980A674B400E638D233C002340520B42440A674B407F84F1243C002340981CE3430A674B40FF9ADCD640002340CA26480709674B402E7145844900234097491FBE06674B40D220161A43002340FDDD623905674B40F1BC34ED20002340491DC4FFFF664B400723CDF707002340F35F7E0BFC664B40C46F1445F9FF224007150EF0F9664B40EBDFDE19EDFF2240627CB6B6F8664B4024D07E5EE8FF22405E99663CF8664B404F5E6061E5FF2240092392F5F7664B406E2A40FEDDFF22407D8FD390F6664B40BA9EBB48D8FF2240F981F1E5F5664B40EEACAF6CD7FF224005D236CCF5664B40D4415795D4FF22402C212C77F5664B40713E2C0CD8FF224093B2B5F5F4664B40A3A60579DAFF2240DAE1129BF4664B40A5B8C8A5DAFF2240DC3D0291F4664B40C8ABE6AEDBFF22403C517B55F4664B40A4D118A3DDFF2240FBF662E5F3664B40BD51146CDEFF22405994B831F3664B403A1D4079DEFF2240F5C0F41DF3664B40D42FC8B0DFFF2240E797674BF1664B40C5C361BFDFFF2240E06CE47DF0664B4095BFA62EE0FF2240BCD0055EEA664B40EAB0AB35E0FF224072A919FBE9664B40215B2241E0FF22408ACBCE57E9664B402D1B94BEE0FF22400B3FC242E9664B40D8F823DCE0FF2240074CCC3DE9664B40DC1278E0E6FF224059CA543BE8664B40690292C7F6FF2240A2513490E5664B40CBB8893BFBFF22406768EBD0E4664B40EFCFA42EFFFF224048AF4027E4664B40E494C92EE8FF2240385D96ACE0664B40AEEEBC7AD3FF2240A5A65B4DDE664B402FA4423AD1FF224005B93F0BDE664B401091B212D0FF22404AAD57E9DD664B40FCDF0523CBFF22400F8C6058DD664B40EECA427BCAFF22405EDEB948DD664B40BDBA1417BDFF22403092FC08DC664B404FB39C14BAFF2240006C25BFDB664B40CFC374850500234049662515D4664B4004B334162D002340CCEF9B10D0664B405048C77E46002340AD33AA75CD664B40E05D340269002340932212EBC9664B403077FA1D91002340B6277FCDC5664B401EB7965DB8002340C523A8DBC1664B4016657CA0C70023408876FC52C0664B40D1344171D7002340F14814B1BE664B4036498F9D00012340C3102272BA664B40A4B3DD06370123407A5DADD5B4664B40F7420A9E44012340B6D5C191B3664B40D8C4DFF166012340CDAE535FB0664B40ACA9EDC87401234009435815AF664B401E738718760123402B831AF6AE664B40A58AC0597A012340122F5883AE664B40BA5EEC397F0123401AD1D7FFAD664B405B05FEC6B2012340A5B0C991A8664B401AFBBA90CB0123406730A368A5664B40E86AD086D0012340A3BB2364A4664B40C7BF79A4D00123408A0FC056A4664B40C2C2E8DDD00123400E5ED13CA4664B40558364E4D001234077D7E239A4664B4046B1D40BD2012340C3DF7BB4A3664B40136223F5D20123406438214BA3664B4087E1B399D3012340F4B67DB0A2664B40116997FFD70123408983D58B9E664B408B675191DA012340EF4F34219C664B40561550ABDC012340EDB03AEB98664B4010E1F1DCD1012340B0F999F793664B403BA7E2EEAB0123402833B06C8C664B401F90DA9EA00123405A26C92C8A664B40E89980F59F0123408441009489664B40C1E819CF9F012340E1E09B7089664B40D194C0A89F012340B37C374D89664B40903529929E0123407B15DD5188664B40AB6F1686A2012340C68960A784664B4089ACA4A7AC012340FDA0C94382664B4036F01571C20123404362953A80664B408D37E9FBC7012340D7C8533280664B40	Flensburg 12	\N	fl12
3	organization	102	0103000020E610000001000000E90100002D4031575BDB22400266757A62664B40B749340C81DB2240C10202B956664B40716207D68BDB2240D7C5D95457664B40DA7AE0DFBFDB2240F6F79E9D46664B4081DB2134DBDB22405AB93E8D3F664B4031B21B5803DC2240A7AC0C6D33664B40BE4DE9BB00DC22400AAC183933664B40706B9CD23BDC22400D0A92E221664B40C39D7B6F3CDC224072BC88B921664B40B3F6A5BD41DC2240C9F1DB8521664B40554A7B7248DC2240129D12C821664B40162DC4D475DC2240693B298823664B409552982A7ADC2240ACF49ADB21664B40AC08E8A27FDC2240586EDDBE1F664B40557119C180DC2240519E65BA1F664B40FD160E3208DD2240FC439491EC654B40552F9F2808DD22400DF7AA90EC654B40FE5E9AA305DD2240B9B77152EC654B4091D2A1CAFFDC22406832D3C9EB654B40BB77FBAAF9DC2240C038C33AEB654B40EC4B8655F4DC22408EFB25BEEA654B40FF5EEFA3F1DC22402587E37FEA654B40D4C72A1EEDDC2240487E5C17EA654B409DF5A420E4DC2240AF24E077E9654B40DE489AF9E4DC22408BE35A23E9654B40C653AC07E5DC2240A9BCF51DE9654B40F4752C47DBDC2240D0FB386CE8654B40CF6C5568D4DC224028F5FFEEE7654B4074904EC5D5DC224054E5D601E7654B409A529EC8D5DC2240B029B7FEE6654B404EE54895D6DC22402345EC3EE6654B40E6398AF4D6DC2240FF2C9426E6654B4006DFF1E6DBDC22405482FCE2E4654B405C8FF49CDCDC224054D8CCAEE4654B40F23CA39FDDDC2240E05EA564E4654B40B567C5A4DDDC224042D9A262E4654B404BFF0CACDEDC224095B92EFBE3654B40BF2E0219DFDC22401466BA5CE3654B4076332470DEDC22409B747DBBE2654B40C72F7B9DDBDC22401349BE4DE2654B40302E6537D8DC2240AF4332B9E2654B4011A5CFF3D0DC22407A37D99EE3654B402520CF18C0DC22401E17247CE5654B405AFBACA8C2DC22405F462710E6654B402D179F95B9DC22403C0DC747E7654B4089F03440B8DC2240C2BD2317E7654B40B65A6421B5DC22402B39B469E7654B40C24FAA10B5DC224016C61969E7654B40194A6746B0DC2240F47B2CEAE7654B405A78D9549FDC2240046F7FAAE9654B40031DB48E92DC2240A7347AF1E7654B4081ED37EF8CDC22402637582FE7654B40B1662CED37DC2240718769B8DB654B4081E94B292DDC22402B37BD44DA654B40914439FB26DC224000FB5E6FD9654B40023429070CDC2240081F43CBD5654B404D84F9600BDC224042DED0B4D5654B40021F50F60ADC2240D9E867A6D5654B403CF017CD0ADC22400DFEBCA1D5654B40AF53C1CD09DC2240285EDF84D5654B409B3F583909DC22401E5F1474D5654B408D9E461209DC22405695AA6FD5654B4022D0647D08DC2240381DD45ED5654B40FB2F126508DC2240DC2D515CD5654B401D7FC42907DC22402DB3C93BD5654B403B7C495B06DC224065457C26D5654B409BF458A905DC224094EEEF15D5654B40A1692A7505DC224008213611D5654B40F9F7FE0405DC22409CE10E07D5654B407F07FD2D04DC22408EDE47F1D4654B406B5AB5E202DC224017B20ED3D4654B401FE0A8E500DC2240060E9EA4D4654B403CB506E400DC22401C7CDE9CD4654B400F0EBDC400DC2240106DDFF9D3654B4033B9BEAE00DC22407A1CF586D3654B40CC91EF7800DC22404C89356DD2654B4075A248A902DC2240465B7B9AD1654B40CB353F7003DC2240F609CD4FD1654B40E412057103DC22406709914FD1654B406F894CA406DC224045FF835ED0654B402601230B07DC2240C9965240D0654B403F26B7760DDC224080AD515DCE654B40ED7EB2E412DC22400E531984CC654B402250131A17DC22401C957381CA654B40B037ECA616DC224041B4C67ACA654B40D5DAB0A116DC22409DC3787ACA654B4021AB70941CDC2240225F1D19C7654B40B82170891BDC2240E205F802C7654B406D586B690FDC2240AF9B34BEC6654B40F4F668A309DC224081E2FA64C2654B40061A24E60ADC22407058A192C0654B405117AFCE0EDC224055171747BF654B404AC38E4413DC22404E48F407BE654B40A97B8F431DDC2240EB169BE2BB654B400ECE200C21DC22403D6E5EC6BA654B401E88C9B025DC2240CF556FC9B8654B40FACEE93526DC22404EEC018DB8654B40FF26081A2FDC2240593E155AB6654B409FA91A3331DC2240AE0E42D5B5654B40226727B233DC224089FA9891B5654B4063EEC45743DC224084F857E2B1654B405E7D8E6E43DC2240E17FFADCB1654B40C659F3F149DC2240D7B9AA3BB0654B40D2BDCEF24CDC2240B2AC1662B0654B4053EEDFE754DC2240A85227A4B0654B40F6B5B8B255DC22405AAAB62FAF654B401BD1AD8058DC22408D0FD9F0AC654B406FCA918258DC2240C0E3AAEEAC654B40D73A7E4E5ADC2240848C98D5AA654B405DA46E0557DC224054167E21A7654B4059E8910457DC2240B817651EA7654B4013E29CB756DC2240690D781AA6654B4011FCFD7854DC2240EE2E4B1AA5654B40FBC6A7D852DC2240F7C41D40A4654B40B0266F6851DC2240026D5D83A3654B401F73506751DC2240EFEFCC82A3654B401531E77350DC2240B33AC917A3654B4026E192204FDC2240EFCC6554A2654B408CD17C1E4FDC2240576B3353A2654B40FDE161714DDC22401EA84F53A1654B40216700864CDC2240FB16F4C6A0654B404112F13F4CDC22400503C5A2A0654B4096C4C12B48DC2240F6A2D1BA9E654B40AA631F2E46DC22403C047CD09E654B40A5C6145E43DC22404DAD18EF9E654B40BAAFF67440DC22404DFAA61C9D654B4056495BFC3DDC224026DD70C29B654B40AD75EE963BDC224056BFB6729A654B40AEC1E3F132DC224033AA8CB795654B402089925831DC2240EEE119CE93654B40E597B94331DC2240C9C08ABD93654B40D973483031DC224071A620AE93654B406401B5A82DDC224055036FE190654B40467CD6A52DDC22400FE13AE090654B40D9F4F78D2DDC2240113C54CD90654B402AD92AA32CDC224087791F7290654B40455FAD992BDC2240D78127D88F654B4070893ECF19DC2240B41FFED084654B405FC5799E15DC22401108A0F084654B407A3EC39915DC2240FEB959CB84654B4055AD45F611DC224035DAC0F667654B40E40DEF750EDC2240EE20666C4E654B40E10D3F570DDC224084254A4040654B4072683D740CDC2240448616CA3F654B4003F128160CDC2240ED4F14993F654B40BBA9CC840BDC22406E24664D3F654B40217E19B908DC2240DFBE83673E654B40303C34DF07DC224049DCE8363E654B406CD7BC0D07DC2240538A2E083E654B40BDB2B40405DC22401EB5F1933D654B40004E7B7D00DC224033928FD73C654B40EB77940EFEDB22400C5FF98C3C654B400867A2B2FDDB22404051F7813C654B406243FC0FFDDB224020A27C6E3C654B407CE81E3EFBDB2240D9B0B4363C654B40E476AC65F5DB2240B22E19B53B654B40DA869A16EFDB22406842B7553B654B406E932C35EBDB22408D6833333B654B4091B63054EADB22409BF4602B3B654B402F1DFD1EEADB2240DE9988293B654B40A4B42876E8DB22403796C51A3B654B403738C121DADB224071BFCC123B654B40F325A982B5DB224009A96DFE3A654B40092860D8B0DB224020A80BE23A654B4042A036F5AFDB2240E52FD5D63A654B4004E13A60AFDB2240866F7CCF3A654B40613F4F5FACDB2240B7878BA93A654B4067199436A8DB2240DF737D563A654B40C738737BA4DB2240775B29EB39654B4043097F48A4DB2240D0528BDF39654B406F41A747A4DB22403D445BDF39654B4039B896C2A1DB2240C72B444C39654B40E03E48A099DB2240067A306C36654B40949F962599DB2240DD78D24036654B40B6E6F2429FDB22400AE53CF335654B4005B3FBCFCFDB2240571209BE33654B408E03E4C8DBDB2240A867694533654B40619C62A1DDDB22403A516B3833654B4029A67795E7DB224032A05CF232654B40C9218BF9E7DB224058B39CEF32654B400FFEEA4EF4DB2240847E2ABD32654B402BBCEDB500DC2240267160AE32654B409B7AC21D14DC2240478338B332654B408FA0863715DC224011A9AD8826654B4043BEFC9B15DC2240994B7C3626654B404126FF9C15DC22401191AD3526654B40250AB4A315DC22404A372B3026654B40AC4B3CF020DC2240CFB6A5F11C654B407FCD26581CDC2240ACEC6B5013654B40485EC92A1CDC2240D9054DF112654B40C9B8ADC51BDC2240D051BAF612654B4087B372061BDC2240BAD1FD0013654B40809EFF7E10DC2240FD8FB39113654B40A9F3339D00DC22408E89C68714654B40B99A9404F1DB2240AD78AE9515654B40217222ACEADB224047B0710F16654B407ED7DEFFE6DB2240E923EB5516654B40E4B7AFBBE1DB22407207F8BA16654B407E341DA2D5DB2240245BDFA017654B40CB184DE1C9DB2240F9F2319E18654B40403D70D5C4DB22403A3AAC1819654B401A715FCAC2DB22400EE5414A19654B40545BC681BEDB2240C57A38B219654B40DE3FBF8BB3DB22408E2E2EDC1A654B40114C794FABDB224030586CE51B654B40AAB74331ABDB2240F50F3AE91B654B4020EF8F2EA9DB224047AEFA291C654B40485C8C3EA1DB2240DAD97AF21C654B40646936D59DDB22402050A8481D654B40377B59E593DB2240840DE9081E654B402DE45B1393DB2240F5BFC6181E654B403BD4A83192DB22407410D5291E654B40CDEAF01092DB2240E1C04D2C1E654B40F63FB6A791DB2240A07142341E654B4026E152408DDB2240F08570721E654B40DB14154E8CDB22406F0FCD7F1E654B403E9BD1D084DB22402A188DE91E654B404BC0173C82DB22409E19C6031F654B40BAC2F88A80DB224008B8F7141F654B409F1071AC7EDB22408776C31F1F654B4097F61B2A7CDB2240E338412E1F654B409FBF201C7CDB2240A6AE572E1F654B40BA3FACBC77DB2240632419351F654B4087612A5173DB22407FF866291F654B40B72EFFF56EDB2240B3D6530B1F654B40E30A7BB96ADB2240DCEF3EDB1E654B40CA1CD5C968DB22407F140DBC1E654B40300F1EC668DB2240AA29D0BB1E654B408778525C68DB224007CF28B51E654B404B36B95668DB22404C70CDB41E654B404DE578A966DB22407F2DC9991E654B405DD942D362DB224081C7C5471E654B40FFACDC9C5ADB22408831045C1D654B40F6E9533253DB22401F328E4E1C654B4053E89EA352DB224004BEF1341C654B40A3C17D1652DB2240B0449E1B1C654B40F3666FAD4CDB224071B40D231B654B408BDABD2447DB2240B8CA8FDD19654B407A6CC6CE44DB2240F6AB282E19654B4012D96A9B43DB22401CE300D418654B405022D0A141DB22406410B63F18654B403631F8553DDB22405B7B9C8E16654B400A47F2863BDB22400D00C48315654B403A9740F53ADB2240FBD0CC2F15654B4023A7854D3ADB2240EFED20CF14654B40DFF8229138DB22406D6D500613654B40B487CF1238DB224064A8D5CA10654B401D7C636F37DB2240DBCB8DE70D654B40A14193D436DB224065E807210D654B4069A2006035DB22401E4E9A600C654B402DE2381B33DB2240C45A42AB0B654B409E57401530DB22406633A9050B654B40ACBDFE612CDB2240558712740A654B4023511D262BDB2240E8DEF6500A654B404FEA157D2ADB22403C1C2D3E0A654B404B96C51928DB2240F6DC3BFA09654B40DAC4C95823DB2240AE63499B09654B402167673E1EDB2240E319AB5909654B40F0863E6809DB2240CA3B579108654B40BC1C953803DB2240C0CF096D0C654B40591C112BFDDA22402B11F2940F654B40C174E96AFBDA224024EF645A10654B40679F7E2DFADA224045B740E610654B40C370061BF6DA224075B28FB112654B40600D740CEEDA224099C229C115654B406D1FC403E5DA2240F7EF0EC218654B40A97AE3EAE4DA2240B74390C818654B40121406DCE4DA22403EA871CC18654B40E3317543CEDA2240C43BFDB41E654B4083E7CBE0C9DA22404181A9C71F654B404719AC57B6DA2240EEAC348F24654B40FA407271B0DA224051C976E225654B40B4C6F9E7A9DA22408759552527654B404443E078A9DA224059FDDC3727654B40A0A89F27A9DA22409407684527654B4030FBBFC3A2DA2240F470315628654B40C6E1FD0D9BDA224019697B7329654B40C0712BC708DA224002E7040B3E654B4038409A50D9D92240E7D871B944654B40904111B4CCD92240712E0B7446654B401D464145C4D92240BD39FF9B47654B40B8BCB886AED922404D591D974A654B40E20F5A928CD922406CF3490A50654B4065A443D75ED9224029E4516157654B40B14907BA5ED922402C0C036657654B40B2F0B09A55D922400CB2D5DC58654B40B34D66F64ED92240D8A0BCED59654B40469C5F8552D92240837B6D425B654B40C2D078E059D92240727F20755D654B40108F4C0B5BD92240ACF7ECBE5D654B40B7421F6962D92240DE7299905F654B4040C183CC78D922404F18C80B65654B40F28FFE937DD9224006CB64A766654B4099588514A2D92240801E6C2274654B404ABA4F18A3D9224082BA5B8274654B40B58FFD6BD1D9224057F7249E85654B4012289122D7D9224076AA44BA87654B404DF444BDE5D92240FDA654C08D654B40D2307046FCD922400CEFDC0B97654B40B577F9DFFFD92240045EF28798654B40D3F9A0CFF1D92240A67879CA98654B40E7A86046F1D9224009C803CD98654B402ADB4B81A8D92240F60540259A654B4062EEE08AA4D9224047F384449A654B4064C833C6A0D922406322937B9A654B40E2C6240B9ED9224026B06DB89A654B4079A712ED85D9224031E896429B654B4067AF725B7FD9224096DB7B069C654B40E0BA40BD54D92240D2123F499C654B40E70B040F51D92240925F2BFE9C654B40A97D21D058D92240BB7DDC48A2654B40140C665A58D922407EC0BFC1A2654B40EC4B606A57D922405BE216B8A3654B40BBB835C3A8D82240DB3F1A1AA9654B40AE5AF5596DD82240EC5DD5EEAA654B40A4C8AE8D45D822402EC8CE28AC654B40575AA40045D822402FF2262DAC654B40EBEC05873ED8224045963C60AC654B40C2F65B2F3AD82240E33598A9A9654B4052F89B7404D822402BCFC8D9A5654B40DA3E1CA7E4D7224030CFE0D4A6654B40D6BF11DDE1D72240D2EE152DA5654B40C59D896CE1D7224017DC4CEAA4654B406970100BDED7224022D19AE8A2654B40607C594DD3D722409C0AEF40A3654B40068A6BEBC9D7224061DB188EA3654B4090BBEB32C9D72240863D0694A3654B4042D4BC43C6D72240EEE926ACA3654B40F65F32DC96D72240B9E3AB13A5654B400EDA47FD77D722403580ED19A6654B401A09141574D72240E103F538A6654B40BEA57E3A76D722409356208EA7654B400CA1629776D72240C5B4CCC7A7654B40AE14B12B6DD72240C1FEA10DA8654B4078E38CFB22D72240FA028D33AA654B406591DA7D18D72240DDF8BC76AA654B403B521B630ED72240123171B7AA654B4080CDD0830ED72240F162D8D7AA654B40FC9BF0A20FD722408B55EF8DAB654B40EB3E92F914D722405A8A66DFAF654B404A5CF84D19D722402617E136B4654B40ABF4C69E1CD722403C011D93B8654B40B6D30CE01CD722401F434D0FB9654B40A9EEF9001DD722406CA7E42FB9654B4032FC5E151DD722408205D374B9654B40FB3B121A1DD72240BA55B57DB9654B40539E27EB1ED722407B2FD8F2BC654B40E2A8F1B620D7224040A5EAA6C1654B40140CB11521D722405CAABC5CC6654B4064A6310720D72240E2AB0112CB654B400238FA8B1DD72240D10F69C4CF654B406AC605311DD722401448745FD0654B406A25081A1DD72240C202F79ED0654B400BE98DF51CD722402EB1C9C4D0654B4076B1FBE01CD7224015B7D0E7D0654B40264ACC521CD72240D2E629DAD1654B40364339A41AD72240629235EED3654B40201DA0EB18D72240F8CA8298D5654B40A51DA68018D722408E070100D6654B405212A0E815D722406D0E050FD8654B400C32DCDC12D72240EB9BB41ADA654B4052511D5E0FD722400E488C22DC654B40D50092420ED72240FE536AB3DC654B4084346BD10DD72240A8A63CEDDC654B4092314E6D0BD72240C0C50426DE654B4030DD660B07D72240C8D69424E0654B40DF01020500D7224096BA1C24E3654B409307EA2DF8D62240C089C518E6654B408AB6ABB4F6D622404CB2B797E6654B402FE22ABEF5D622406D04A9EAE6654B40E4AF3389EFD62240F8915F01E9654B406EE25E1AE6D6224003D3C0DCEB654B4089B50E0AD9D6224009D1E760EF654B402E4DEB9BD8D62240817DFE7AEF654B400615E5926FD6224087A0555C08664B40D19CDD5D6CD62240DE36CF1E09664B4017FD38366CD622402EFA322809664B408C67F2D767D62240B9DB15310A664B407BA45B6266D62240992F81890A664B4023E2FC6C66D62240DBEA588A0A664B40654176C966D62240DFA8AB910A664B40110678066BD622408087E9EA0A664B40E01AF55A79D62240D60AA8180C664B40A6F13D6F80D62240632887510A664B405C6B1EEA89D62240504918F007664B40793A0A668AD62240EE49F9D007664B401FAB1FDD8FD6224042D7A17106664B40B396F34F90D622403BC63D6F06664B40C80F0530C2D622402C96D16405664B408FA76545C7D6224004C3A94905664B40D70D9476C7D62240AA3A8A4705664B406297EAEFC7D62240B41F4D4205664B4094BF67A411D72240811764BC03664B406031E9B111D7224098B119BC03664B404E5D6AD011D722400FE56EBB03664B40C71C7C41EAD722404A675906FF654B4011A3B2E240D82240B00012FFF9654B406667B60441D822406D1EFD04FA654B405E9793FB42D82240A9B6905CFA654B406C964EF248D82240C8216E66FB654B4063AE5D9A5DD822405B3752FFFE654B40BFA213FE61D82240D02101C3FF654B40A18C733E69D82240B3E9EDA007664B40169131266BD8224050CA18B209664B40578F802E6BD82240AB3D17BB09664B40F0C44EA46CD82240263564500B664B409C95B57970D82240EF63AE680E664B400883BE1471D82240AE964AE60E664B4060E441DD7BD8224050AA10B217664B407C4A481C7FD822407774EF571A664B4081D51A4F7FD822400C339E701A664B4000F0FB2380D82240CF9303D81A664B404F562C6080D8224038A585D91A664B40B8B9837E80D822402A2830E51A664B406004311290D8224015873C2327664B40D2AB5E938BD822403A99704827664B406AC3047C8BD82240D201314927664B40BBD2048B97D82240E11D482330664B403AFEA00A9DD8224064DF8A2C34664B40D0F7FBF7ABD822405EE8A3213F664B408A761958ACD82240139033683F664B40F81D15DFACD82240AAA0E9653F664B403A4B33E2ACD822404EBE14683F664B405617E59BAFD82240FBDC911841664B40D48F529CAFD822404E86CF1841664B408483C829B1D82240B677590C41664B40974BFEDFB9D82240EAD46BC640664B40788BC17A27D9224026B799563D664B407A17B9F228D922404DE92C4E3D664B405EDD7A042DD92240A682D4363D664B40CC60A3AB2ED92240E19A582D3D664B4099050DD42ED922405EA0712C3D664B40AB9495E52ED92240C6675A2C3D664B40508AF7142FD922400C8F1F2C3D664B40915354962FD9224043877B2B3D664B406B57198F31D92240FFADFD283D664B40F8FD9D2A33D92240F41CF7263D664B40BF4DB54236D92240F3D70D233D664B40D8307DAB3DD922407C68913A3D664B401F313DF344D9224028B1A7723D664B407EE140FF4BD92240AC7480CA3D664B40B8CFC86B52D922404DE5C13B3E664B40702EB2B552D922408167D9403E664B40601E170457D92240C29BBBA53E664B40EEC4E9FD58D92240E3E703D43E664B40D94DED5C5ED9224091BE19763F664B40A8C624995ED9224049BD337D3F664B4035CBD9C05ED92240BB09E1813F664B409428761AA1D92240FD39966148664B40C5EABE86A8D92240F8A6714D49664B40C170CE66B0D92240764E4F244A664B40DAEBA1AFB8D9224011CBFEE44A664B40B8D87C55C1D9224032B0708E4B664B40FE4F8988C2D92240D84005A24B664B40581A2BA4C9D92240644B0F164C664B40B689712ED2D922406C663B884C664B40C66D2A50D4D92240FEAFB3A14C664B40B6C69E69D7D92240BEE4BAC64C664B408C14E7BD1CDA22407BB9030350664B407A32DFBD40DA2240B5A7D1B151664B404F036DA842DA22404425C0C851664B40F9E24F6B44DA22409343EEE051664B40BE87612C51DA2240465B079052664B405BD8D18C5FDA2240A244688E53664B40C0995C3E6DDA2240A72DF3BB54664B401759C4E278DA22401E6A74F455664B40073BB07D79DA2240F628B50456664B40F5A524247ADA22401718281656664B4064104C257ADA224098924A1656664B407EF9EBD37BDA2240FE1EAB4A56664B4076000E0281DA22404534F2EB56664B408320024281DA22409CFAB8F356664B40919DC52F83DA224060818A3657664B40A454C9F383DA2240D02B105157664B40CCBF509287DA2240F14170CE57664B40794F1A0C88DA22400AA1EADE57664B40416FDAE289DA2240FE0D132358664B409293E0DD89DA2240AA09232558664B40A5D1831A8DDA2240FAC9689F58664B408BBD17D392DA2240788AE58D59664B40BBD9B16E98DA22405055A2985A664B4099A64C979BDA22406C1DC94A5B664B40E41C3482AADA2240E3B385305C664B40943E47D9C8DA22407CABC5035E664B405283C56954DB22404393259564664B40B42D6A9154DB22407CF4029764664B40A9F68FD45ADB224071A92DAC62664B40345599725BDB2240B3A8C87B62664B402D4031575BDB22400266757A62664B40	Flensburg 3	\N	fl3
\.


--
-- TOC entry 5864 (class 0 OID 0)
-- Dependencies: 535
-- Name: currency_id_seq; Type: SEQUENCE SET; Schema: uranus; Owner: oklab
--

SELECT pg_catalog.setval('uranus.currency_id_seq', 45, true);


--
-- TOC entry 5865 (class 0 OID 0)
-- Dependencies: 551
-- Name: event_id_seq; Type: SEQUENCE SET; Schema: uranus; Owner: oklab
--

SELECT pg_catalog.setval('uranus.event_id_seq', 1540, true);


--
-- TOC entry 5866 (class 0 OID 0)
-- Dependencies: 573
-- Name: event_link_id_seq; Type: SEQUENCE SET; Schema: uranus; Owner: oklab
--

SELECT pg_catalog.setval('uranus.event_link_id_seq', 3, true);


--
-- TOC entry 5867 (class 0 OID 0)
-- Dependencies: 537
-- Name: event_occasion_type_id_seq; Type: SEQUENCE SET; Schema: uranus; Owner: oklab
--

SELECT pg_catalog.setval('uranus.event_occasion_type_id_seq', 24, true);


--
-- TOC entry 5868 (class 0 OID 0)
-- Dependencies: 541
-- Name: image_type_id_seq; Type: SEQUENCE SET; Schema: uranus; Owner: oklab
--

SELECT pg_catalog.setval('uranus.image_type_id_seq', 9, true);


--
-- TOC entry 5869 (class 0 OID 0)
-- Dependencies: 578
-- Name: message_id_seq; Type: SEQUENCE SET; Schema: uranus; Owner: oklab
--

SELECT pg_catalog.setval('uranus.message_id_seq', 1, false);


--
-- TOC entry 5870 (class 0 OID 0)
-- Dependencies: 548
-- Name: system_email_template_id_seq; Type: SEQUENCE SET; Schema: uranus; Owner: oklab
--

SELECT pg_catalog.setval('uranus.system_email_template_id_seq', 11, true);


--
-- TOC entry 5871 (class 0 OID 0)
-- Dependencies: 595
-- Name: todo_id_seq; Type: SEQUENCE SET; Schema: uranus; Owner: oklab
--

SELECT pg_catalog.setval('uranus.todo_id_seq', 8, true);


--
-- TOC entry 5872 (class 0 OID 0)
-- Dependencies: 570
-- Name: wkb_poly_id_seq; Type: SEQUENCE SET; Schema: uranus; Owner: oklab
--

SELECT pg_catalog.setval('uranus.wkb_poly_id_seq', 13, true);


--
-- TOC entry 5533 (class 2606 OID 2266252)
-- Name: currency currency_pkey; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.currency
    ADD CONSTRAINT currency_pkey PRIMARY KEY (id);


--
-- TOC entry 5586 (class 2606 OID 2351848)
-- Name: event_date_projection event_date_projection_event_date_uuid_key; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.event_date_projection
    ADD CONSTRAINT event_date_projection_event_date_uuid_key UNIQUE (event_date_uuid);


--
-- TOC entry 5584 (class 2606 OID 2351882)
-- Name: event_date event_date_uuid_key; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.event_date
    ADD CONSTRAINT event_date_uuid_key UNIQUE (uuid);


--
-- TOC entry 5580 (class 2606 OID 2351561)
-- Name: event_filter event_filter_pkey; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.event_filter
    ADD CONSTRAINT event_filter_pkey PRIMARY KEY (uuid);


--
-- TOC entry 5582 (class 2606 OID 2351579)
-- Name: event_link event_link_pkey; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.event_link
    ADD CONSTRAINT event_link_pkey PRIMARY KEY (id);


--
-- TOC entry 5535 (class 2606 OID 2266262)
-- Name: event_occasion_type event_occasion_type_pkey; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.event_occasion_type
    ADD CONSTRAINT event_occasion_type_pkey PRIMARY KEY (id);


--
-- TOC entry 5618 (class 2606 OID 2351835)
-- Name: event event_pkey; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.event
    ADD CONSTRAINT event_pkey PRIMARY KEY (uuid);


--
-- TOC entry 5588 (class 2606 OID 2351846)
-- Name: event_projection event_projection_event_uuid_key; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.event_projection
    ADD CONSTRAINT event_projection_event_uuid_key UNIQUE (event_uuid);


--
-- TOC entry 5537 (class 2606 OID 2325446)
-- Name: event_release_status_i18n event_status_unique_key_lang; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.event_release_status_i18n
    ADD CONSTRAINT event_status_unique_key_lang UNIQUE (key, iso_639_1);


--
-- TOC entry 5620 (class 2606 OID 2351850)
-- Name: event_type_link event_type_link_unique; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.event_type_link
    ADD CONSTRAINT event_type_link_unique UNIQUE (event_uuid, type_id, genre_id);


--
-- TOC entry 5548 (class 2606 OID 2283097)
-- Name: event_type event_type_pkey; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.event_type
    ADD CONSTRAINT event_type_pkey PRIMARY KEY (type_id, iso_639_1);


--
-- TOC entry 5600 (class 2606 OID 2351723)
-- Name: pluto_image_link image_context_identifier_unique; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.pluto_image_link
    ADD CONSTRAINT image_context_identifier_unique UNIQUE (context, context_uuid, identifier);


--
-- TOC entry 5540 (class 2606 OID 2266272)
-- Name: image_type image_type_pkey; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.image_type
    ADD CONSTRAINT image_type_pkey PRIMARY KEY (id);


--
-- TOC entry 5570 (class 2606 OID 2317111)
-- Name: legal_form_i18n legal_form_i18n_pkey; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.legal_form_i18n
    ADD CONSTRAINT legal_form_i18n_pkey PRIMARY KEY (key, iso_639_1);


--
-- TOC entry 5568 (class 2606 OID 2317104)
-- Name: legal_form legal_form_pkey; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.legal_form
    ADD CONSTRAINT legal_form_pkey PRIMARY KEY (key);


--
-- TOC entry 5574 (class 2606 OID 2317204)
-- Name: license_i18n license_i18n_pkey; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.license_i18n
    ADD CONSTRAINT license_i18n_pkey PRIMARY KEY (key, iso_639_1);


--
-- TOC entry 5572 (class 2606 OID 2317197)
-- Name: license license_pkey; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.license
    ADD CONSTRAINT license_pkey PRIMARY KEY (key);


--
-- TOC entry 5564 (class 2606 OID 2317042)
-- Name: link_type_i18n link_type_i18n_pkey; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.link_type_i18n
    ADD CONSTRAINT link_type_i18n_pkey PRIMARY KEY (key, iso_639_1);


--
-- TOC entry 5562 (class 2606 OID 2317035)
-- Name: link_type link_type_pkey; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.link_type
    ADD CONSTRAINT link_type_pkey PRIMARY KEY (key);


--
-- TOC entry 5590 (class 2606 OID 2351649)
-- Name: message message_pkey; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.message
    ADD CONSTRAINT message_pkey PRIMARY KEY (id);


--
-- TOC entry 5592 (class 2606 OID 2351667)
-- Name: organization organization_pkey; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.organization
    ADD CONSTRAINT organization_pkey PRIMARY KEY (uuid);


--
-- TOC entry 5594 (class 2606 OID 2351694)
-- Name: password_reset password_reset_token_key; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.password_reset
    ADD CONSTRAINT password_reset_token_key UNIQUE (token);


--
-- TOC entry 5542 (class 2606 OID 2266292)
-- Name: permission_bit permission_bit_pkey; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.permission_bit
    ADD CONSTRAINT permission_bit_pkey PRIMARY KEY (group_id, name);


--
-- TOC entry 5544 (class 2606 OID 2266294)
-- Name: permission_label permission_label_pkey; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.permission_label
    ADD CONSTRAINT permission_label_pkey PRIMARY KEY (group_id, name, iso_639_1);


--
-- TOC entry 5596 (class 2606 OID 2351702)
-- Name: pluto_cache pluto_cache_receipt_key; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.pluto_cache
    ADD CONSTRAINT pluto_cache_receipt_key UNIQUE (receipt);


--
-- TOC entry 5598 (class 2606 OID 2351716)
-- Name: pluto_image pluto_image_pkey; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.pluto_image
    ADD CONSTRAINT pluto_image_pkey PRIMARY KEY (uuid);


--
-- TOC entry 5552 (class 2606 OID 2316992)
-- Name: space_feature space_feature_feature_name_key; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.space_feature
    ADD CONSTRAINT space_feature_feature_name_key UNIQUE (key);


--
-- TOC entry 5556 (class 2606 OID 2316999)
-- Name: space_feature_link space_feature_link_pkey; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.space_feature_link
    ADD CONSTRAINT space_feature_link_pkey PRIMARY KEY (space_id, key);


--
-- TOC entry 5554 (class 2606 OID 2316973)
-- Name: space_feature space_feature_pkey; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.space_feature
    ADD CONSTRAINT space_feature_pkey PRIMARY KEY (category, key);


--
-- TOC entry 5602 (class 2606 OID 2351731)
-- Name: space space_pkey; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.space
    ADD CONSTRAINT space_pkey PRIMARY KEY (uuid);


--
-- TOC entry 5560 (class 2606 OID 2317023)
-- Name: space_type_i18n space_type_i18n_pkey; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.space_type_i18n
    ADD CONSTRAINT space_type_i18n_pkey PRIMARY KEY (key, iso_639_1);


--
-- TOC entry 5558 (class 2606 OID 2317016)
-- Name: space_type space_type_pkey; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.space_type
    ADD CONSTRAINT space_type_pkey PRIMARY KEY (key);


--
-- TOC entry 5546 (class 2606 OID 2266308)
-- Name: system_email_template system_email_template_pkey; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.system_email_template
    ADD CONSTRAINT system_email_template_pkey PRIMARY KEY (id);


--
-- TOC entry 5616 (class 2606 OID 2351822)
-- Name: todo todo_pkey; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.todo
    ADD CONSTRAINT todo_pkey PRIMARY KEY (id);


--
-- TOC entry 5604 (class 2606 OID 2351749)
-- Name: transport_station transport_station_gtfs_station_code_key; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.transport_station
    ADD CONSTRAINT transport_station_gtfs_station_code_key UNIQUE (gtfs_station_code);


--
-- TOC entry 5606 (class 2606 OID 2351747)
-- Name: transport_station transport_station_pkey; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.transport_station
    ADD CONSTRAINT transport_station_pkey PRIMARY KEY (uuid);


--
-- TOC entry 5608 (class 2606 OID 2351761)
-- Name: user user_email_key; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus."user"
    ADD CONSTRAINT user_email_key UNIQUE (email);


--
-- TOC entry 5610 (class 2606 OID 2351759)
-- Name: user user_pkey; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus."user"
    ADD CONSTRAINT user_pkey PRIMARY KEY (uuid);


--
-- TOC entry 5612 (class 2606 OID 2351763)
-- Name: user user_user_name_key; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus."user"
    ADD CONSTRAINT user_user_name_key UNIQUE (username);


--
-- TOC entry 5614 (class 2606 OID 2351788)
-- Name: venue venue_pkey; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.venue
    ADD CONSTRAINT venue_pkey PRIMARY KEY (uuid);


--
-- TOC entry 5550 (class 2606 OID 2317080)
-- Name: venue_type_i18n venue_type_pkey; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.venue_type_i18n
    ADD CONSTRAINT venue_type_pkey PRIMARY KEY (key, iso_639_1);


--
-- TOC entry 5566 (class 2606 OID 2317093)
-- Name: venue_type venue_type_pkey1; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.venue_type
    ADD CONSTRAINT venue_type_pkey1 PRIMARY KEY (key);


--
-- TOC entry 5576 (class 2606 OID 2351206)
-- Name: wkb_polygon wkb_poly_key_key; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.wkb_polygon
    ADD CONSTRAINT wkb_poly_key_key UNIQUE (key);


--
-- TOC entry 5578 (class 2606 OID 2351192)
-- Name: wkb_polygon wkb_poly_pkey; Type: CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.wkb_polygon
    ADD CONSTRAINT wkb_poly_pkey PRIMARY KEY (id);


--
-- TOC entry 5531 (class 1259 OID 2266332)
-- Name: country_code_iso_unique; Type: INDEX; Schema: uranus; Owner: oklab
--

CREATE UNIQUE INDEX country_code_iso_unique ON uranus.country USING btree (code, iso_639_1);


--
-- TOC entry 5538 (class 1259 OID 2266340)
-- Name: genre_type_type_id_idx; Type: INDEX; Schema: uranus; Owner: oklab
--

CREATE INDEX genre_type_type_id_idx ON uranus.genre_type USING btree (genre_id);


--
-- TOC entry 5632 (class 2620 OID 2351805)
-- Name: event_date_projection set_modified_at; Type: TRIGGER; Schema: uranus; Owner: oklab
--

CREATE TRIGGER set_modified_at BEFORE UPDATE ON uranus.event_date_projection FOR EACH ROW EXECUTE FUNCTION uranus.update_modified_at();


--
-- TOC entry 5630 (class 2620 OID 2351806)
-- Name: event_link set_modified_at; Type: TRIGGER; Schema: uranus; Owner: oklab
--

CREATE TRIGGER set_modified_at BEFORE UPDATE ON uranus.event_link FOR EACH ROW EXECUTE FUNCTION uranus.update_modified_at();


--
-- TOC entry 5633 (class 2620 OID 2351807)
-- Name: event_projection set_modified_at; Type: TRIGGER; Schema: uranus; Owner: oklab
--

CREATE TRIGGER set_modified_at BEFORE UPDATE ON uranus.event_projection FOR EACH ROW EXECUTE FUNCTION uranus.update_modified_at();


--
-- TOC entry 5634 (class 2620 OID 2351808)
-- Name: message set_modified_at; Type: TRIGGER; Schema: uranus; Owner: oklab
--

CREATE TRIGGER set_modified_at BEFORE UPDATE ON uranus.message FOR EACH ROW EXECUTE FUNCTION uranus.update_modified_at();


--
-- TOC entry 5635 (class 2620 OID 2351809)
-- Name: organization set_modified_at; Type: TRIGGER; Schema: uranus; Owner: oklab
--

CREATE TRIGGER set_modified_at BEFORE UPDATE ON uranus.organization FOR EACH ROW EXECUTE FUNCTION uranus.update_modified_at();


--
-- TOC entry 5636 (class 2620 OID 2351683)
-- Name: organization_member_link set_modified_at; Type: TRIGGER; Schema: uranus; Owner: oklab
--

CREATE TRIGGER set_modified_at BEFORE UPDATE ON uranus.organization_member_link FOR EACH ROW EXECUTE FUNCTION uranus.update_modified_at();


--
-- TOC entry 5637 (class 2620 OID 2351810)
-- Name: pluto_image set_modified_at; Type: TRIGGER; Schema: uranus; Owner: oklab
--

CREATE TRIGGER set_modified_at BEFORE UPDATE ON uranus.pluto_image FOR EACH ROW EXECUTE FUNCTION uranus.update_modified_at();


--
-- TOC entry 5638 (class 2620 OID 2351732)
-- Name: space set_modified_at; Type: TRIGGER; Schema: uranus; Owner: oklab
--

CREATE TRIGGER set_modified_at BEFORE UPDATE ON uranus.space FOR EACH ROW EXECUTE FUNCTION uranus.update_modified_at();


--
-- TOC entry 5642 (class 2620 OID 2351823)
-- Name: todo set_modified_at; Type: TRIGGER; Schema: uranus; Owner: oklab
--

CREATE TRIGGER set_modified_at BEFORE UPDATE ON uranus.todo FOR EACH ROW EXECUTE FUNCTION uranus.update_modified_at();


--
-- TOC entry 5639 (class 2620 OID 2351750)
-- Name: transport_station set_modified_at; Type: TRIGGER; Schema: uranus; Owner: oklab
--

CREATE TRIGGER set_modified_at BEFORE UPDATE ON uranus.transport_station FOR EACH ROW EXECUTE FUNCTION uranus.update_modified_at();


--
-- TOC entry 5640 (class 2620 OID 2351812)
-- Name: user set_modified_at; Type: TRIGGER; Schema: uranus; Owner: oklab
--

CREATE TRIGGER set_modified_at BEFORE UPDATE ON uranus."user" FOR EACH ROW EXECUTE FUNCTION uranus.update_modified_at();


--
-- TOC entry 5641 (class 2620 OID 2351789)
-- Name: venue set_modified_at; Type: TRIGGER; Schema: uranus; Owner: oklab
--

CREATE TRIGGER set_modified_at BEFORE UPDATE ON uranus.venue FOR EACH ROW EXECUTE FUNCTION uranus.update_modified_at();


--
-- TOC entry 5643 (class 2620 OID 2351836)
-- Name: event trg_update_modified_at; Type: TRIGGER; Schema: uranus; Owner: oklab
--

CREATE TRIGGER trg_update_modified_at BEFORE UPDATE ON uranus.event FOR EACH ROW EXECUTE FUNCTION uranus.update_modified_at();


--
-- TOC entry 5631 (class 2620 OID 2351611)
-- Name: event_date trg_update_modified_at; Type: TRIGGER; Schema: uranus; Owner: oklab
--

CREATE TRIGGER trg_update_modified_at BEFORE UPDATE ON uranus.event_date FOR EACH ROW EXECUTE FUNCTION uranus.update_modified_at();


--
-- TOC entry 5644 (class 2620 OID 2351837)
-- Name: event trg_update_search_text; Type: TRIGGER; Schema: uranus; Owner: oklab
--

CREATE TRIGGER trg_update_search_text BEFORE INSERT OR UPDATE ON uranus.event FOR EACH ROW EXECUTE FUNCTION uranus.event_update_search_text();


--
-- TOC entry 5627 (class 2606 OID 2351871)
-- Name: event_date event_date_event_uuid_fkey; Type: FK CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.event_date
    ADD CONSTRAINT event_date_event_uuid_fkey FOREIGN KEY (event_uuid) REFERENCES uranus.event(uuid) ON DELETE CASCADE;


--
-- TOC entry 5628 (class 2606 OID 2351883)
-- Name: event_date_projection event_date_projection_event_date_uuid_fkey; Type: FK CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.event_date_projection
    ADD CONSTRAINT event_date_projection_event_date_uuid_fkey FOREIGN KEY (event_date_uuid) REFERENCES uranus.event_date(uuid) ON DELETE CASCADE;


--
-- TOC entry 5629 (class 2606 OID 2351876)
-- Name: event_projection event_projection_event_uuid_fkey; Type: FK CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.event_projection
    ADD CONSTRAINT event_projection_event_uuid_fkey FOREIGN KEY (event_uuid) REFERENCES uranus.event(uuid) ON DELETE CASCADE;


--
-- TOC entry 5625 (class 2606 OID 2317112)
-- Name: legal_form_i18n legal_form_i18n_key_fkey; Type: FK CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.legal_form_i18n
    ADD CONSTRAINT legal_form_i18n_key_fkey FOREIGN KEY (key) REFERENCES uranus.legal_form(key) ON DELETE CASCADE;


--
-- TOC entry 5626 (class 2606 OID 2317205)
-- Name: license_i18n license_i18n_key_fkey; Type: FK CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.license_i18n
    ADD CONSTRAINT license_i18n_key_fkey FOREIGN KEY (key) REFERENCES uranus.license(key) ON DELETE CASCADE;


--
-- TOC entry 5624 (class 2606 OID 2317043)
-- Name: link_type_i18n link_type_i18n_key_fkey; Type: FK CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.link_type_i18n
    ADD CONSTRAINT link_type_i18n_key_fkey FOREIGN KEY (key) REFERENCES uranus.link_type(key) ON DELETE CASCADE;


--
-- TOC entry 5621 (class 2606 OID 2283040)
-- Name: permission_label permission_label_group_id_name_fkey; Type: FK CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.permission_label
    ADD CONSTRAINT permission_label_group_id_name_fkey FOREIGN KEY (group_id, name) REFERENCES uranus.permission_bit(group_id, name) ON DELETE CASCADE;


--
-- TOC entry 5622 (class 2606 OID 2317005)
-- Name: space_feature_link space_feature_link_feature_name_fkey; Type: FK CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.space_feature_link
    ADD CONSTRAINT space_feature_link_feature_name_fkey FOREIGN KEY (key) REFERENCES uranus.space_feature(key);


--
-- TOC entry 5623 (class 2606 OID 2317024)
-- Name: space_type_i18n space_type_i18n_key_fkey; Type: FK CONSTRAINT; Schema: uranus; Owner: oklab
--

ALTER TABLE ONLY uranus.space_type_i18n
    ADD CONSTRAINT space_type_i18n_key_fkey FOREIGN KEY (key) REFERENCES uranus.space_type(key) ON DELETE CASCADE;


-- Completed on 2026-04-05 19:24:42 CEST

--
-- PostgreSQL database dump complete
--
