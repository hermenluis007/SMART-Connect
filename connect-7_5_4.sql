-- GENERATES A SMART7 database from scratch
-- requires:
-- 1) postgis extension to be installed: CREATE EXTENSION postgis;
-- 2) uuid-ossp extension to be installed: CREATE EXTENSION "uuid-ossp";

CREATE SCHEMA connect;
CREATE SCHEMA smart;
CREATE SCHEMA query_temp;
CREATE EXTENSION postgis;
CREATE EXTENSION "uuid-ossp";

CREATE OR REPLACE FUNCTION public.manage_user_roles() RETURNS TRIGGER AS $$
    BEGIN
        --
        -- should only be called on insert; adds necessary smart role
        -- for web access
        --
        IF (TG_OP = 'INSERT') THEN
            INSERT INTO connect.user_roles (username, role_id) VALUES (NEW.username, 'smart');
            RETURN NEW;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$ LANGUAGE plpgsql;


CREATE TYPE connect.alert_status AS ENUM (
    'ACTIVE',
    'DISABLED'
);

--If we upgrade to Postgresql 9.6 this function can be removed
--and changed to current_setting('ca.trigger.t' || NEW.ca_uuid, true)
CREATE FUNCTION connect.dolog(cauuid uuid) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    canrun boolean;
BEGIN
    --check if we should log this ca
    select current_setting('ca.trigger.t' || cauuid) into canrun;
    return canrun;
    EXCEPTION WHEN others THEN
        RETURN TRUE;
END$$;

CREATE FUNCTION connect.dq_update_modified_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.lastmodified_date = now();
    RETURN NEW;
END;
$$;

CREATE FUNCTION connect.i_profile_entity_type() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
  INSERT INTO connect.change_log
 (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
 SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'entity_type_uuid', ROW.entity_type_uuid, 'profile_uuid', ROW.profile_uuid, null, i.CA_UUID
   FROM smart.i_profile_config i WHERE i.uuid = row.profile_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.i_profile_record_source() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
  INSERT INTO connect.change_log
 (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
 SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'record_source_uuid', ROW.record_source_uuid, 'profile_uuid', ROW.profile_uuid, null, i.CA_UUID
   FROM smart.i_profile_config i WHERE i.uuid = row.profile_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.toutm(lat double precision, long double precision) RETURNS integer
    LANGUAGE plpgsql
    AS $$

 DECLARE
  zone integer;
  issouth boolean;
  sql varchar;
  srid integer;
  rec record;
 BEGIN
 IF (lat < -80 OR lat > 84) THEN
         RETURN NULL;
        END IF;

  zone := floor((long+180) / 6 ) + 1;

  IF (lat >= 0) THEN
   issouth := false;
  ELSE
   issouth := true;
  END IF;

        IF ( lat >= 56.0 AND lat < 64.0 AND long >= 3.0 AND long < 12.0 ) THEN
         zone := 32;
        END IF;

         IF ( lat >= 72.0 AND lat < 84.0 ) THEN
         IF (long >= 0 AND long < 9.0) THEN
          zone := 31;
         ELSIF (long >= 9.0 and long < 21.0 ) THEN
          zone := 33;
         ELSIF (long >= 21.0 and long < 33.0 ) THEN
          zone := 35;
         ELSIF (long >= 33.0 and long < 42.0 ) THEN
          zone := 37;
         END IF;
 END IF;

 sql := 'SELECT srid FROM spatial_ref_sys WHERE proj4text like ''%proj=utm %'' AND proj4text like ''%zone=' || zone || ' %'' AND proj4text like ''%datum=WGS84 %''';
 IF (issouth = true) THEN
  sql := sql || ' AND proj4text like ''%south %''';
 ELSE
  sql := sql || ' AND proj4text not like ''%south %''';
 END IF;

 srid := null;
 FOR rec IN EXECUTE sql LOOP
  IF (srid is not null) THEN
   RETURN NULL;
  END IF;
  srid := rec.srid;
 END LOOP;

 RETURN srid;
END;

$$;


CREATE OR REPLACE FUNCTION connect.trg_asset_deployment_disruption() RETURNS trigger AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
 	INSERT INTO connect.change_log 
 		(uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid) 
 		SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, asset.ca_uuid 
 		FROM smart.asset_deployment deploy, smart.asset asset WHERE asset.uuid = deploy.asset_uuid and deploy.uuid = row.asset_deployment_uuid ;
RETURN ROW; END$$ LANGUAGE 'plpgsql';

CREATE FUNCTION connect.trg_asset_attribute_list_item() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, i.CA_UUID
         from smart.asset_attribute i WHERE i.uuid = ROW.attribute_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_asset_attribute_value() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'asset_uuid', ROW.asset_uuid, 'attribute_uuid', ROW.attribute_uuid, null, i.CA_UUID
         from smart.asset_attribute i WHERE i.uuid = ROW.attribute_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_asset_deployment() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, i.CA_UUID
         from smart.asset  i WHERE i.uuid = ROW.asset_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_asset_deployment_attribute_value() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'asset_deployment_uuid', ROW.asset_deployment_uuid, 'attribute_uuid', ROW.attribute_uuid, null, i.CA_UUID
         from smart.asset_attribute i WHERE i.uuid = ROW.attribute_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_asset_history_record() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, i.CA_UUID
         from smart.asset i WHERE i.uuid = ROW.asset_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_asset_station_attribute() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'attribute_uuid', ROW.attribute_uuid, null, null, null, i.CA_UUID
         from smart.asset_attribute i WHERE i.uuid = ROW.attribute_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_asset_station_attribute_value() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'station_uuid', ROW.station_uuid, 'attribute_uuid', ROW.attribute_uuid, null, i.CA_UUID
         from smart.asset_attribute i WHERE i.uuid = ROW.attribute_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_asset_station_location() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, i.CA_UUID
         from smart.asset_station i WHERE i.uuid = ROW.station_uuid;
RETURN ROW; END$$;

CREATE FUNCTION connect.trg_asset_station_location_attribute() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'attribute_uuid', ROW.attribute_uuid, null, null, null, i.CA_UUID
         from smart.asset_attribute i WHERE i.uuid = ROW.attribute_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_asset_station_location_attribute_value() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'station_location_uuid', ROW.station_location_uuid, 'attribute_uuid', ROW.attribute_uuid, null, i.CA_UUID
         from smart.asset_attribute i WHERE i.uuid = ROW.attribute_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_asset_station_location_history() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, i.CA_UUID
         from smart.asset_station_location loc, smart.asset_station i WHERE i.uuid = loc.station_uuid and loc.uuid = ROW.station_location_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_asset_type_attribute() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'asset_type_uuid', ROW.asset_type_uuid, 'attribute_uuid', ROW.attribute_uuid, null, i.CA_UUID
         from smart.asset_attribute i WHERE i.uuid = ROW.attribute_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_asset_waypoint() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, i.CA_UUID
         from smart.waypoint i WHERE i.uuid = ROW.wp_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_asset_waypoint_attachment() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'wp_attachment_uuid', ROW.wp_attachment_uuid, 'asset_waypoint_uuid', ROW.asset_waypoint_uuid, null, i.CA_UUID
         from smart.asset_waypoint wp, smart.waypoint i WHERE i.uuid = wp.wp_uuid and wp.uuid = ROW.asset_waypoint_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_changelog_after() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
    PERFORM pg_advisory_unlock(a.lock_key) FROM connect.ca_info a WHERE a.ca_uuid = NEW.ca_uuid;
RETURN NEW; END$$;


CREATE FUNCTION connect.trg_changelog_before() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  canlock boolean;
BEGIN
    --check if we should log this ca
    IF (NOT connect.dolog(NEW.ca_uuid)) THEN RETURN NULL; END IF;
    SELECT pg_try_advisory_lock(a.lock_key) into canlock FROM connect.ca_info a WHERE a.ca_uuid = NEW.ca_uuid;
    IF (canlock) THEN return NEW; ELSE RAISE EXCEPTION 'Database Locked to Editing'; END IF;
END$$;


CREATE FUNCTION connect.trg_changelog_common() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str,  ca_uuid)
         VALUES
         (uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.UUID, null, null, null, ROW.CA_UUID);
 RETURN ROW;
END$$;


CREATE FUNCTION connect.trg_cm_attribute() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, a.CA_UUID
         FROM smart.dm_attribute a WHERE a.uuid = ROW.attribute_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_cm_attribute_config() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, cm.CA_UUID
         FROM smart.configurable_model cm where cm.uuid = ROW.cm_uuid;
RETURN ROW; END$$;

CREATE FUNCTION connect.trg_cm_attribute_list() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, cm.CA_UUID
         FROM smart.configurable_model cm, smart.cm_attribute_config cf where cm.uuid = cf.cm_uuid and cf.uuid = ROW.config_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_cm_attribute_option() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, dm.CA_UUID
         FROM smart.cm_attribute cm, smart.dm_attribute dm where cm.attribute_uuid = dm.uuid and cm.uuid = ROW.cm_attribute_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_cm_attribute_tree_node() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, cm.CA_UUID
         FROM smart.configurable_model cm, smart.cm_attribute_config cf where cm.uuid = cf.cm_uuid and cf.uuid = ROW.config_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_cm_ct_properties_profile() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'cm_uuid', ROW.CM_UUID, null, null, null, cm.CA_UUID FROM smart.configurable_model cm WHERE cm.uuid = ROW.cm_uuid;
     RETURN ROW;
END$$;


CREATE FUNCTION connect.trg_cm_node() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, cm.CA_UUID
         FROM smart.configurable_model cm where cm.uuid = ROW.cm_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_compound_query_layer() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, cq.CA_UUID
         FROM smart.compound_query cq where cq.uuid = ROW.compound_query_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_connect_account() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'employee_uuid', ROW.EMPLOYEE_UUID, null, null, null, server.CA_UUID FROM smart.connect_server server WHERE server.uuid = ROW.connect_uuid;
 RETURN ROW;
END$$;

CREATE FUNCTION connect.trg_connect_alert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, cm.CA_UUID
         FROM smart.configurable_model cm WHERE cm.uuid = ROW.cm_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_connect_ct_properties() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, cm.CA_UUID
         FROM smart.configurable_model cm WHERE cm.uuid = ROW.cm_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_conservation_area() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         VALUES (uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, ROW.UUID);
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_ct_incident_link() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.UUID, null, null, null, wp.CA_UUID
         FROM smart.waypoint wp WHERE wp.uuid = ROW.wp_uuid;
 RETURN ROW;
END$$;


CREATE FUNCTION connect.trg_ct_metadata_value_uuid() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.UUID, null, null, null, iset.CA_UUID
         FROM smart.ct_metadata_value iset WHERE iset.uuid = ROW.field_uuid;
 RETURN ROW;
END$$;


CREATE FUNCTION connect.trg_ct_mission_link() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'ct_uuid', ROW.ct_uuid, null, null, null, sd.CA_UUID
         FROM smart.mission mm, smart.survey s, smart.survey_design sd WHERE mm.survey_uuid = s.uuid and s.survey_design_uuid = sd.uuid and mm.uuid = ROW.mission_uuid;
RETURN ROW; END$$;


CREATE OR REPLACE FUNCTION connect.trg_ct_mission_wplink() RETURNS trigger
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
  INSERT INTO connect.change_log
 (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
 SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, sd.CA_UUID
   FROM smart.mission mm, smart.survey s, smart.survey_design sd, smart.ct_mission_link l
   WHERE mm.survey_uuid = s.uuid and s.survey_design_uuid = sd.uuid and mm.uuid = l.mission_uuid and l.ct_uuid = row.ct_mission_link_uuid;
RETURN ROW; END$$ LANGUAGE 'plpgsql';


CREATE FUNCTION connect.trg_ct_patrol_link() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'ct_uuid', ROW.ct_uuid, null, null, null, pp.CA_UUID
         FROM smart.patrol pp, smart.patrol_leg pl WHERE pl.patrol_uuid = pp.uuid and pl.uuid = ROW.patrol_leg_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_ct_patrol_wplink() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
  INSERT INTO connect.change_log
 (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
 SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, pp.CA_UUID
  FROM smart.patrol pp, smart.patrol_leg pl, smart.ct_patrol_link l
  WHERE pl.patrol_uuid = pp.uuid and pl.uuid = l.patrol_leg_uuid and l.ct_uuid = row.ct_patrol_link_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_ct_properties_profile_option() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.UUID, null, null, null, p.CA_UUID FROM smart.ct_properties_profile p WHERE p.uuid = ROW.profile_uuid;
 RETURN ROW;
END$$;


CREATE FUNCTION connect.trg_dm_att_agg_map() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'attribute_uuid', ROW.attribute_uuid, 'agg_name', null, ROW.agg_name, a.CA_UUID
         FROM smart.dm_attribute a WHERE a.uuid = ROW.attribute_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_dm_attribute_list() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, da.CA_UUID
         FROM smart.dm_attribute da WHERE da.uuid = ROW.attribute_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_dm_attribute_tree() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, da.CA_UUID
         FROM smart.dm_attribute da WHERE da.uuid = ROW.attribute_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_dm_cat_att_map() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'attribute_uuid', ROW.attribute_uuid, 'category_uuid', ROW.category_uuid, null, a.CA_UUID
         FROM smart.dm_attribute a WHERE a.uuid = ROW.attribute_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_e_action_parameter_value() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'action_uuid', ROW.action_uuid, 'parameter_key', null, ROW.parameter_key, a.CA_UUID
         FROM smart.e_action a
         WHERE a.uuid = ROW.action_uuid;
     RETURN ROW;
END$$;


CREATE FUNCTION connect.trg_e_event_action() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, a.CA_UUID
         FROM smart.e_action a
         WHERE a.uuid = ROW.action_uuid;
     RETURN ROW;
END$$;


CREATE FUNCTION connect.trg_employee_team_member() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'team_uuid', ROW.team_uuid, 'employee_uuid', ROW.employee_uuid, null, t.CA_UUID
         FROM smart.employee_team t WHERE t.uuid = ROW.team_uuid;
 RETURN ROW;
END$$;


CREATE FUNCTION connect.trg_entity() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.UUID, null, null, null, et.CA_UUID FROM smart.entity_type et WHERE et.uuid = ROW.entity_type_uuid;
     RETURN ROW;
END$$;

CREATE FUNCTION connect.trg_entity_attribute() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.UUID, null, null, null, et.CA_UUID FROM smart.entity_type et WHERE et.uuid = ROW.entity_type_uuid;
     RETURN ROW;
END$$;

CREATE FUNCTION connect.trg_entity_attribute_value() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'entity_attribute_uuid', ROW.entity_attribute_uuid, 'entity_uuid', ROW.entity_uuid, null, et.CA_UUID FROM smart.entity_type et, smart.entity e WHERE e.entity_type_uuid = et.uuid and e.uuid = ROW.entity_uuid;
     RETURN ROW;
END$$;

CREATE FUNCTION connect.trg_i18n_label() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'element_uuid', ROW.element_uuid, 'language_uuid', ROW.language_uuid, null, l.CA_UUID
         FROM smart.language l WHERE l.uuid = ROW.language_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_i_attribute_list_item() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, i.CA_UUID
         FROM smart.i_attribute i
         WHERE i.uuid = ROW.attribute_uuid;
 RETURN ROW; END$$;


CREATE FUNCTION connect.trg_i_diagram_entity_type_style() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, a.CA_UUID
         FROM smart.i_diagram_style a
         WHERE a.uuid = ROW.style_uuid;
     RETURN ROW;
END$$;


CREATE FUNCTION connect.trg_i_diagram_relationship_type_style() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, a.CA_UUID
         FROM smart.i_diagram_style a
         WHERE a.uuid = ROW.style_uuid;
     RETURN ROW;
END$$;


CREATE FUNCTION connect.trg_i_entity_attachment() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'entity_uuid', ROW.entity_uuid, 'attachment_uuid', ROW.attachment_uuid, null, i.CA_UUID
         from smart.i_entity i where i.uuid = ROW.entity_uuid;
RETURN ROW; END$$;

CREATE FUNCTION connect.trg_i_entity_attribute_value() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'entity_uuid', ROW.entity_uuid, 'attribute_uuid', ROW.attribute_uuid, null, i.CA_UUID
         from smart.i_entity i where i.uuid = ROW.entity_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_i_entity_location() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'entity_uuid', ROW.entity_uuid, 'location_uuid', ROW.location_uuid, null, i.CA_UUID
         from smart.i_entity i where i.uuid = ROW.entity_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_i_entity_record() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'entity_uuid', ROW.entity_uuid, 'record_uuid', ROW.record_uuid, null, i.CA_UUID
         from smart.i_entity i where i.uuid = ROW.entity_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_i_entity_relationship() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, i.CA_UUID
         from smart.i_relationship_type i where i.uuid = ROW.relationship_type_uuid;
RETURN ROW; END$$;

CREATE FUNCTION connect.trg_i_entity_relationship_attribute_value() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'entity_relationship_uuid', ROW.entity_relationship_uuid, 'attribute_uuid', ROW.attribute_uuid, null, i.CA_UUID
         from smart.i_attribute i where i.uuid = ROW.attribute_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_i_entity_type_attribute() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'entity_type_uuid', ROW.entity_type_uuid, 'attribute_uuid', ROW.attribute_uuid, null, i.CA_UUID
         from smart.i_entity_type i where i.uuid = ROW.entity_type_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_i_entity_type_attribute_group() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, i.CA_UUID
         from smart.i_entity_type i where i.uuid = ROW.entity_type_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_i_observation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, i.CA_UUID
         from smart.i_location i where i.uuid = ROW.location_uuid;
RETURN ROW; END$$;


CREATE OR REPLACE FUNCTION connect.trg_i_observation_attribute() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, a.CA_UUID
         FROM smart.dm_attribute a WHERE a.uuid = ROW.attribute_uuid;
RETURN ROW; END$$;

CREATE OR REPLACE FUNCTION connect.trg_i_observation_attribute_list() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'list_element_uuid', ROW.list_element_uuid, 'observation_attribute_uuid', ROW.observation_attribute_uuid, null, a.CA_UUID
         FROM smart.i_observation_attribute b join smart.dm_attribute a ON a.uuid = b.attribute_uuid WHERE a.uuid = ROW.observation_attribute_uuid; 
RETURN ROW; END$$;

CREATE FUNCTION connect.trg_i_permission() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
  INSERT INTO connect.change_log
 (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
 SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'employee_uuid', ROW.employee_uuid, 'profile_uuid', ROW.profile_uuid, null, i.CA_UUID
   FROM smart.i_profile_config i WHERE i.uuid = row.profile_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_i_record_attachment() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'record_uuid', ROW.record_uuid, 'attachment_uuid', ROW.attachment_uuid, null, i.CA_UUID
         from smart.i_record i where i.uuid = ROW.record_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_i_record_attribute_value() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'record_uuid', ROW.record_uuid, 'attribute_uuid', ROW.attribute_uuid, null, i.CA_UUID
         from smart.i_record i where i.uuid = ROW.record_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_i_record_attribute_value_list() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'value_uuid', ROW.value_uuid, 'element_uuid', ROW.element_uuid, null, i.CA_UUID
         from smart.i_record_attribute_value v, smart.i_record i where v.uuid = ROW.value_uuid and i.uuid = v.record_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_i_recordsource_attribute() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, i.CA_UUID
         from smart.i_recordsource i WHERE i.uuid = ROW.source_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_i_relationship_type_attribute() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'relationship_type_uuid', ROW.relationship_type_uuid, 'attribute_uuid', ROW.attribute_uuid, null, i.CA_UUID
         from smart.i_attribute i where i.uuid = ROW.attribute_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_i_working_set_entity() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'working_set_uuid', ROW.working_set_uuid, 'entity_uuid', ROW.entity_uuid, null, i.CA_UUID
         from smart.i_working_set i where i.uuid = ROW.working_set_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_i_working_set_query() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'working_set_uuid', ROW.working_set_uuid, 'query_uuid', ROW.query_uuid, null, i.CA_UUID
         from smart.i_working_set i where i.uuid = ROW.working_set_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_i_working_set_record() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'working_set_uuid', ROW.working_set_uuid, 'record_uuid', ROW.record_uuid, null, i.CA_UUID
         from smart.i_working_set i where i.uuid = ROW.working_set_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_iconfile() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.UUID, null, null, null, iset.CA_UUID
         FROM smart.iconset iset WHERE iset.uuid = ROW.iconset_uuid;
 RETURN ROW;
END$$;


--CREATE FUNCTION connect.trg_intelligence_attachment() RETURNS trigger
--    LANGUAGE plpgsql
--    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
--     INSERT INTO connect.change_log
--         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
--         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, i.CA_UUID
--         from smart.intelligence i where i.uuid = ROW.intelligence_uuid;
--RETURN ROW; END$$;
--
--
--CREATE FUNCTION connect.trg_intelligence_point() RETURNS trigger
--    LANGUAGE plpgsql
--    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
--     INSERT INTO connect.change_log
--         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
--         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, i.CA_UUID
--         from smart.intelligence i where i.uuid = ROW.intelligence_uuid;
--RETURN ROW; END$$;


CREATE FUNCTION connect.trg_mission() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, sd.CA_UUID FROM smart.survey s, smart.survey_design sd WHERE s.survey_design_uuid = sd.uuid and s.uuid = ROW.survey_uuid;
     RETURN ROW;
END$$;

CREATE FUNCTION connect.trg_mission_attribute_list() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, ma.CA_UUID FROM smart.mission_attribute ma WHERE ma.uuid = ROW.mission_attribute_uuid;
     RETURN ROW;
END$$;


CREATE FUNCTION connect.trg_mission_day() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, sd.CA_UUID FROM smart.mission m, smart.survey s, smart.survey_design sd
         WHERE s.survey_design_uuid = sd.uuid and s.uuid = m.survey_uuid and m.uuid = ROW.mission_uuid;
     RETURN ROW;
END$$;


CREATE FUNCTION connect.trg_mission_member() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'mission_uuid', ROW.mission_uuid, 'employee_uuid', ROW.employee_uuid, null, e.CA_UUID FROM smart.employee e
         WHERE e.uuid = ROW.employee_uuid;
     RETURN ROW;
END$$;


CREATE FUNCTION connect.trg_mission_property() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'survey_design_uuid', ROW.survey_design_uuid, 'mission_attribute_uuid', ROW.mission_attribute_uuid, null, sd.CA_UUID FROM smart.survey_design sd
         WHERE sd.uuid = ROW.survey_design_uuid;
     RETURN ROW;
END$$;


CREATE FUNCTION connect.trg_mission_property_value() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'mission_uuid', ROW.mission_uuid, 'mission_attribute_uuid', ROW.mission_attribute_uuid, null, ma.CA_UUID
         FROM smart.mission_attribute ma
         WHERE ma.uuid = ROW.mission_attribute_uuid;
     RETURN ROW;
END$$;


CREATE FUNCTION connect.trg_mission_track() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, sd.CA_UUID
         FROM smart.mission_day md, smart.mission m, smart.survey s, smart.survey_design sd
         WHERE s.survey_design_uuid = sd.uuid and s.uuid = m.survey_uuid and m.uuid = md.mission_uuid and md.uuid = ROW.mission_day_uuid;
     RETURN ROW;
END$$;


CREATE FUNCTION connect.trg_observation_attachment() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
  INSERT INTO connect.change_log
 (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
 SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, wp.CA_UUID
   FROM smart.wp_observation ob, smart.waypoint wp, smart.wp_observation_group g where ob.wp_group_uuid = g.uuid and g.wp_uuid = wp.uuid and ob.uuid = ROW.obs_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_observation_options() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         VALUES (uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'ca_uuid', ROW.ca_uuid, null, null, null, ROW.ca_UUID);
RETURN ROW; END$$;

CREATE FUNCTION connect.trg_patrol_attribute_list() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, t.CA_UUID
         FROM smart.patrol_attribute t WHERE t.uuid = ROW.patrol_attribute_uuid;
 RETURN ROW;
END$$;


CREATE FUNCTION connect.trg_patrol_attribute_value() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'patrol_uuid', ROW.patrol_uuid, 'patrol_attribute_uuid', ROW.patrol_attribute_uuid, null, t.CA_UUID
         FROM smart.patrol_attribute t WHERE t.uuid = ROW.patrol_attribute_uuid;
 RETURN ROW;
END$$;

CREATE FUNCTION connect.trg_patrol_leg() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, p.CA_UUID
         FROM smart.patrol p WHERE p.uuid = ROW.patrol_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_patrol_leg_day() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, p.CA_UUID
         FROM smart.patrol p, smart.patrol_leg pl where pl.patrol_uuid = p.uuid and pl.uuid = ROW.patrol_leg_uuid;
RETURN ROW; END$$;

CREATE FUNCTION connect.trg_patrol_leg_members() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'patrol_leg_uuid', ROW.patrol_leg_uuid, 'employee_uuid', ROW.employee_uuid, null, e.CA_UUID
         FROM smart.employee e WHERE e.uuid = ROW.employee_uuid;
RETURN ROW; END$$;



CREATE FUNCTION connect.trg_patrol_plan() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'patrol_uuid', ROW.patrol_uuid, 'plan_uuid', ROW.plan_uuid, null, p.CA_UUID
         FROM smart.patrol p where p.uuid = ROW.patrol_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_patrol_type() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         VALUES (uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'ca_uuid', ROW.ca_uuid, 'patrol_type', null, ROW.patrol_type,  ROW.CA_UUID);
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_patrol_waypoint() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'leg_day_uuid', ROW.leg_day_uuid, 'wp_uuid', ROW.wp_uuid, null, wp.CA_UUID
         FROM smart.waypoint wp WHERE wp.uuid = ROW.wp_uuid;
RETURN ROW; END$$;

CREATE FUNCTION connect.trg_plan_target() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, p.CA_UUID
         from smart.plan p where p.uuid = ROW.plan_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_plan_target_point() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, p.CA_UUID
         FROM smart.plan_target pt, smart.plan p WHERE p.uuid = pt.plan_uuid and pt.uuid = ROW.plan_target_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_qa_routine_parameter() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.UUID, null, null, null, r.CA_UUID FROM smart.qa_routine r WHERE r.uuid = ROW.qa_routine_uuid;
 RETURN ROW;
END$$;


CREATE FUNCTION connect.trg_rank() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, a.CA_UUID
         FROM smart.agency a WHERE a.uuid = ROW.agency_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_report_query() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'report_uuid', ROW.report_uuid, 'query_uuid', ROW.query_uuid, null, r.CA_UUID
         from smart.report r where r.uuid = ROW.report_uuid;
RETURN ROW; END$$;



CREATE FUNCTION connect.trg_sampling_unit() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, sd.CA_UUID
         FROM smart.survey_design sd
         WHERE sd.uuid = ROW.survey_design_uuid;
     RETURN ROW;
END$$;


CREATE FUNCTION connect.trg_sampling_unit_attribute_list() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, sa.CA_UUID
         FROM smart.sampling_unit_attribute sa
         WHERE sa.uuid = ROW.sampling_unit_attribute_uuid;
     RETURN ROW;
END$$;

CREATE FUNCTION connect.trg_sampling_unit_attribute_value() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'su_attribute_uuid', ROW.su_attribute_uuid, 'su_uuid', ROW.su_uuid, null, sa.CA_UUID
         FROM smart.sampling_unit_attribute sa
         WHERE sa.uuid = ROW.su_attribute_uuid;
     RETURN ROW;
END$$;


CREATE FUNCTION connect.trg_screen_option_uuid() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, op.CA_UUID
         FROM smart.screen_option op where op.uuid = ROW.option_uuid;
RETURN ROW; END$$;



CREATE FUNCTION connect.trg_survey() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, sd.CA_UUID
         FROM smart.survey_design sd
         WHERE sd.uuid = ROW.survey_design_uuid;
     RETURN ROW;
END$$;



CREATE FUNCTION connect.trg_survey_design_property() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, sd.CA_UUID
         FROM smart.survey_design sd
         WHERE sd.uuid = ROW.survey_design_uuid;
     RETURN ROW;
END$$;



CREATE FUNCTION connect.trg_survey_design_sampling_unit() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'survey_design_uuid', ROW.survey_design_uuid, 'su_attribute_uuid', ROW.su_attribute_uuid, null, sd.CA_UUID
         FROM smart.survey_design sd
         WHERE sd.uuid = ROW.survey_design_uuid;
     RETURN ROW;
END$$;


CREATE FUNCTION connect.trg_survey_waypoint() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'wp_uuid', ROW.wp_uuid, 'mission_day_uuid', ROW.mission_day_uuid, null, wp.CA_UUID
         FROM smart.waypoint wp
         WHERE wp.uuid = ROW.wp_uuid;
     RETURN ROW;
END$$;


CREATE FUNCTION connect.trg_track() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, p.CA_UUID
         FROM smart.patrol p, smart.patrol_leg pl, smart.patrol_leg_day pld WHERE p.uuid = pl.patrol_uuid and pl.uuid = pld.patrol_leg_uuid and pld.uuid = ROW.patrol_leg_day_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_wp_attachments() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, wp.CA_UUID
         FROM smart.waypoint wp WHERE wp.uuid = ROW.wp_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_wp_group_observation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
  INSERT INTO connect.change_log
 (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
 SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, wp.CA_UUID
   FROM smart.waypoint wp WHERE wp.uuid = ROW.wp_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_wp_observation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
  INSERT INTO connect.change_log
 (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
 SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, wp.CA_UUID
   FROM smart.waypoint wp, smart.wp_observation_group g WHERE wp.uuid = g.wp_uuid and g.uuid = ROW.wp_group_uuid;
RETURN ROW; END$$;


CREATE FUNCTION connect.trg_wp_observation_attributes() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, a.CA_UUID
         FROM smart.dm_attribute a WHERE a.uuid = ROW.attribute_uuid;
RETURN ROW; END$$;

CREATE OR REPLACE FUNCTION connect.trg_wp_observation_attributes_list() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'list_element_uuid', ROW.list_element_uuid, 'observation_attribute_uuid', ROW.observation_attribute_uuid, null, a.CA_UUID
         FROM smart.wp_observation_attributes b join smart.dm_attribute a ON a.uuid = b.attribute_uuid WHERE b.uuid = ROW.observation_attribute_uuid; 
RETURN ROW; END$$;


CREATE FUNCTION connect.utmarea(geom public.geometry) RETURNS double precision
    LANGUAGE plpgsql
    AS $$

DECLARE
 srid integer;
 centroid geometry;
BEGIN
 centroid := st_centroid(geom);
 srid := connect.toutm(st_y(centroid), st_x(centroid));
 IF (srid is null) THEN
  return st_area(geography(geom));
 END IF;
 RETURN st_area(st_transform( st_setsrid(geom, 4326), srid));
END;
$$;


CREATE FUNCTION smart.computehours(geometry bytea, linestring bytea) RETURNS double precision
    LANGUAGE plpgsql
    AS $$
DECLARE
  type varchar;
  value double precision;
  i integer;
  p geometry;
BEGIN
    p := st_geomfromwkb(geometry);
    type := st_geometrytype(p);
    IF (upper(type) = 'ST_POLYGON') THEN
        RETURN smart.computeHoursPoly(geometry, linestring);
    ELSIF (upper(type) = 'ST_MULTIPOLYGON') THEN
        value := 0;
        FOR i in 1..ST_NumGeometries(p) LOOP
            value := value + computeHoursPoly( st_asewkb(ST_GeometryN(p, i), 'XDR'), linestring);
        END LOOP;
        RETURN value;
    ELSIF (upper(type) = 'ST_GEOMETRYCOLLECTION') THEN
        value := 0;
        FOR i in 1..ST_NumGeometries(p) LOOP
            value := value + computeHours(ST_GeometryN(p, i), linestring);
        END LOOP;
        RETURN value;
    END IF;
    RETURN 0;

END;
$$;


CREATE FUNCTION smart.computehourspoly(polygon bytea, linestring bytea) RETURNS double precision
    LANGUAGE plpgsql
    AS $$
DECLARE
  ls geometry;
  p geometry;
  value double precision;
  ctime double precision;
  clength double precision;
  i integer;
  pnttemp geometry;
  pnttemp2 geometry;
  lstemp geometry;
BEGIN
 ls := st_geomfromwkb(linestring);
 p := st_geomfromwkb(polygon);

 IF (UPPER(st_geometrytype(ls)) = 'ST_MULTILINESTRING' ) THEN
  ctime = 0;
  FOR i in 1..ST_NumGeometries(ls) LOOP
   ctime := ctime + smart.computeHoursPoly(polygon, st_geometryn(ls, i));
  END LOOP;
  RETURN ctime;
 END IF;

 --wholly contained use entire time
 IF not st_isvalid(ls) and st_length(ls) = 0 THEN
  pnttemp = st_pointn(ls, 1);
  IF (smart.pointinpolygon(st_x(pnttemp),st_y(pnttemp), null, null, p)) THEN
   RETURN (st_z(st_endpoint(ls)) - st_z(st_startpoint(ls))) / 3600000.0;
  END IF;
  RETURN 0;
 END IF;

 IF (st_contains(p, ls)) THEN
  return (st_z(st_endpoint(ls)) - st_z(st_startpoint(ls))) / 3600000.0;
 END IF;

 value := 0;
 FOR i in 1..ST_NumPoints(ls)-1 LOOP
  pnttemp := st_pointn(ls, i);
  pnttemp2 := st_pointn(ls, i+1);
  lstemp := st_makeline(pnttemp, pnttemp2);
  IF (NOT st_intersects(st_envelope(ls), st_envelope(lstemp))) THEN
   --do nothing; outside envelope
  ELSE
   IF (ST_COVERS(p, lstemp)) THEN
    value := value + st_z(pnttemp2) - st_z(pnttemp);
   ELSIF (ST_INTERSECTS(p, lstemp)) THEN
    ctime := st_z(pnttemp2) - st_z(pnttemp);
    clength := st_distance(pnttemp, pnttemp2);
    IF (clength = 0) THEN
     --points are the same and intersect so include the entire time
     value := value + ctime;
    ELSE
     --part in part out so linearly interpolate
     value := value + (ctime * (st_length(st_intersection(p, lstemp)) / clength));
    END IF;
   END IF;
  END IF;
 END LOOP;
 RETURN value / 3600000.0;
END;
$$;


CREATE FUNCTION smart.computetileid(x double precision, y double precision, distance double precision, direction double precision, srid integer, originx double precision, originy double precision, gridsize double precision) RETURNS character varying
    LANGUAGE plpgsql
    AS $$
DECLARE
  pnt geometry;
  tx integer;
  ty integer;
BEGIN
 IF (distance is not null and direction is not null) THEN
  pnt := st_transform(st_setsrid(smart.projectPoint(x,y,distance,direction), 4326), srid);
 ELSE
  pnt := st_transform(st_setsrid(st_makepoint(x,y), 4326), srid);
 END IF;
 tx := floor ( (st_x(pnt) - originX ) / gridSize) + 1;
 ty := floor ( (st_y(pnt) - originY ) / gridSize) + 1;
 RETURN tx || '_' || ty;
END;
$$;


CREATE FUNCTION smart.distanceinmeter(geom bytea) RETURNS double precision
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN ST_Length_Spheroid(st_force2d(st_geomfromwkb(geom)), 'SPHEROID["WGS 84",6378137,298.257223563]');

END;
$$;



CREATE FUNCTION smart.hkeylength(hkey character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN length(hkey) - length(replace(hkey, '.', '')) - 1;

END;
$$;


CREATE FUNCTION smart.intersection(geom1 bytea, geom2 bytea) RETURNS bytea
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN st_asewkb(ST_INTERSECTION(st_geomfromwkb(geom1), st_geomfromwkb(geom2)), 'XDR');

END;
$$;


CREATE FUNCTION smart.intersects(geom1 bytea, geom2 bytea) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN ST_INTERSECTS(st_geomfromwkb(geom1), st_geomfromwkb(geom2));

END;
$$;


CREATE FUNCTION smart.metaphonecontains(metaphone character varying, searchstring character varying) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    part varchar;
BEGIN
    IF (metaphone IS NULL OR searchstring IS NULL) THEN RETURN false; END IF;
    FOREACH PART IN ARRAY string_to_array(searchstring, ' ')
    LOOP
            IF (metaphone = part) THEN RETURN TRUE; END IF;
    END LOOP;
    RETURN FALSE;
END;
$$;


CREATE FUNCTION smart.pointinpolygon(x double precision, y double precision, distance double precision, direction double precision, geom bytea) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
 IF (distance IS NOT NULL AND direction IS NOT NULL) THEN
  RETURN ST_INTERSECTS(smart.projectPoint(x, y, distance, direction), st_geomfromwkb(geom));
 END IF;
 RETURN ST_INTERSECTS(ST_MAKEPOINT(x, y), st_geomfromwkb(geom));

END;
$$;


CREATE FUNCTION smart.projectpoint(x double precision, y double precision, distance double precision, direction double precision) RETURNS public.geometry
    LANGUAGE plpgsql
    AS $$
DECLARE
 a double precision;
 dR double precision;
 rx double precision;
 ry double precision;
 prjy1 double precision;
 prjx1 double precision;
 prjy double precision;
 prjx double precision;
BEGIN
  a := radians(direction);
  dR := distance / 6378100;
  ry := radians(y);
  rx := radians(x);
  prjy1 := asin( sin(ry) * cos(dR) + cos(ry) * sin(dR) * cos(a) );
  prjx1 := rx + atan2(sin(a) * sin(dR) * cos(ry), cos(dR) - sin(ry) * sin(prjy1));
  prjx := degrees(prjx1);
  prjy := degrees(prjy1);
  RETURN ST_MAKEPOINT(prjx, prjy);
END;
$$;


CREATE FUNCTION smart.trackintersects(geom1 bytea, geom2 bytea) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
  ls geometry;
  pnt geometry;
BEGIN
 ls := st_geomfromwkb(geom1);

 IF (UPPER(st_geometrytype(ls)) = 'ST_MULTILINESTRING' ) THEN
  FOR i in 1..ST_NumGeometries(ls) LOOP
   IF (smart.trackIntersects(st_geometryn(ls, i), geom2)) THEN
    RETURN true;
   END IF;
  END LOOP;
 END IF;
 if not st_isvalid(ls) and st_length(ls) = 0 then
  pnt = st_pointn(ls, 1);
  return smart.pointinpolygon(st_x(pnt),st_y(pnt), null, null, geom2);
 else
  RETURN ST_INTERSECTS(ls, st_geomfromwkb(geom2));
 end if;

END;
$$;


CREATE FUNCTION smart.trimhkeytolevel(level integer, str character varying) RETURNS character varying
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN (regexp_matches(str, '(?:[a-zA-Z_0-9]*\.){' || level+1 || '}'))[1];
END;
$$;


SET default_with_oids = false;

CREATE TABLE connect.alert_filter_defaults (
    uuid uuid NOT NULL,
    default_past_hours integer,
    default_type_uuids character varying(925),
    default_active boolean,
    default_disabled boolean,
    default_level1 boolean,
    default_level2 boolean,
    default_level3 boolean,
    default_level4 boolean,
    default_level5 boolean,
    default_ca_uuids character varying(925),
    default_text character varying(128),
    seconds_refresh integer,
    starting_zoom_level integer,
    starting_long real,
    starting_lat real
);


CREATE TABLE connect.alert_types (
    uuid uuid NOT NULL,
    label character varying(64),
    color character varying(16),
    fillcolor character varying(16),
    opacity character varying(8),
    markericon character varying(16),
    markercolor character varying(16),
    spin boolean NOT NULL,
    custom_icon character varying(2),
    PRIMARY KEY(uuid)
);


CREATE TABLE connect.alerts (
    uuid uuid NOT NULL,
    user_generated_id character varying NOT NULL,
    date timestamp without time zone NOT NULL,
    description character varying,
    type_uuid uuid NOT NULL,
    level smallint NOT NULL,
    ca_uuid uuid,
    status connect.alert_status NOT NULL,
    x double precision NOT NULL,
    y double precision NOT NULL,
    track character varying NOT NULL,
    creator_uuid uuid,
    source character varying(32) DEFAULT 'USER'::character varying NOT NULL,
    primary key (uuid),
    CONSTRAINT valid_level CHECK (((level > 0) AND (level < 6)))
);


CREATE TABLE connect.ca_info (
    ca_uuid uuid NOT NULL,
    version uuid,
    label character varying NOT NULL,
    status character varying NOT NULL,
    lock_key serial not null,
    unique(lock_key),
    PRIMARY KEY (ca_uuid)
);


COMMENT ON TABLE connect.ca_info IS 'Contains server details for Conservation Areas.';
COMMENT ON COLUMN connect.ca_info.ca_uuid IS 'The unique Conservation Area identifier.';
COMMENT ON COLUMN connect.ca_info.version IS 'The version of the data for the conservation area.';


-- Name: ca_plugin_version; Type: TABLE; Schema: connect; Owner: smart

CREATE TABLE connect.ca_plugin_version (
    ca_uuid uuid NOT NULL,
    plugin_id character varying NOT NULL,
    version character varying NOT NULL,
    PRIMARY KEY (ca_uuid, plugin_id)

);
COMMENT ON TABLE connect.ca_plugin_version IS 'A list of SMART plugins and their database schema version for each Conservation Area.';
COMMENT ON COLUMN connect.ca_plugin_version.ca_uuid IS 'The unique Conservation Area identifier.';
COMMENT ON COLUMN connect.ca_plugin_version.plugin_id IS 'The unique plugin identifier.';
COMMENT ON COLUMN connect.ca_plugin_version.version IS 'The plugin database schema version.';


CREATE TABLE connect.change_log (
    uuid uuid,
    revision BIGSERIAL NOT NULL,
    action character varying(15),
    filename character varying(32672),
    tablename character varying(256),
    ca_uuid uuid,
    key1_fieldname character varying(256),
    key1 uuid,
    key2_fieldname character varying(256),
    key2_str character varying(256),
    key2_uuid uuid,
    datetime timestamp without time zone DEFAULT now(),
    CONSTRAINT action_check CHECK (((action)::text = ANY ((ARRAY['INSERT'::character varying, 'UPDATE'::character varying, 'DELETE'::character varying, 'FS_INSERT'::character varying, 'FS_DELETE'::character varying, 'FS_UPDATE'::character varying])::text[]))),
    PRIMARY KEY (revision)
);

COMMENT ON TABLE connect.change_log IS 'Change log items.';
COMMENT ON COLUMN connect.change_log.uuid IS 'A unique identifier for each change log item.';
COMMENT ON COLUMN connect.change_log.revision IS 'The server defined revision number.';
COMMENT ON COLUMN connect.change_log.action IS 'Change log action.';
COMMENT ON COLUMN connect.change_log.filename IS 'The filename, if a datastore action.';
COMMENT ON COLUMN connect.change_log.tablename IS 'The tablename if a database action.';
COMMENT ON COLUMN connect.change_log.ca_uuid IS 'The conservation area uuid.';
COMMENT ON COLUMN connect.change_log.key1_fieldname IS 'The first unique key field name (required if database action).';
COMMENT ON COLUMN connect.change_log.key1 IS 'The first unique key uuid value (required if database action).';
COMMENT ON COLUMN connect.change_log.key2_fieldname IS 'The second unique key field name (optional, only required for composite primary keys).';
COMMENT ON COLUMN connect.change_log.key2_str IS 'The second unique key uuid value (optional).';
COMMENT ON COLUMN connect.change_log.key2_uuid IS 'The second unique key string value (optional)';
COMMENT ON COLUMN connect.change_log.datetime IS 'The server managed datetime the action is added to the table.';



CREATE TABLE connect.change_log_history (
    ca_uuid uuid NOT NULL,
    last_delete_revision bigint,
    PRIMARY KEY (ca_uuid)
);

COMMENT ON TABLE connect.change_log_history IS 'Tracks history infor about the change log table, in particular the last removed records for each conservation area';
COMMENT ON COLUMN connect.change_log_history.ca_uuid IS 'The conservation area unique identifier.';
COMMENT ON COLUMN connect.change_log_history.last_delete_revision IS 'The last deleted revision number.';

CREATE TABLE connect.connect_plugin_version (
    plugin_id character varying NOT NULL,
    version character varying NOT NULL,
    PRIMARY KEY (plugin_id)
);
COMMENT ON TABLE connect.connect_plugin_version IS 'The list of plugin supported by the SMART Connect Server and their associated versions.  The version field should be the database schema version not the code version.';
COMMENT ON COLUMN connect.connect_plugin_version.plugin_id IS 'The unique plugin identifier.';
COMMENT ON COLUMN connect.connect_plugin_version.version IS 'The plugin database schema version.';


CREATE TABLE connect.connect_version (
    version character varying(16),
    last_updated timestamp without time zone DEFAULT now(),
    filestore_version character varying(5) DEFAULT '-1'::character varying
);

CREATE TABLE connect.ct_api_key(
    ca_uuid uuid not null,
    key_type varchar(32) not null, 
    api_key varchar(64) not null,
    primary key (ca_uuid, key_type), unique(api_key)
);


CREATE TABLE connect.ct_navigation_layer (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    uploaded_date timestamp with time zone NOT NULL,
    filename character varying(256) NOT NULL,
    name character varying(256) NOT NULL,
    status character varying(16) NOT NULL,
    work_item_uuid uuid,
    PRIMARY KEY (uuid)
);


CREATE TABLE connect.ct_package (
    uuid uuid NOT NULL,
    package_uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    uploaded_date timestamp with time zone NOT NULL,
    version character varying(256) NOT NULL,
    filename character varying(256) NOT NULL,
    name character varying(256) NOT NULL,
    status character varying(16) NOT NULL,
    work_item_uuid uuid,
    package_type varchar(256) NOT NULL,
	is_private boolean DEFAULT FALSE NOT NULL,
    UNIQUE(package_uuid),
    primary key(uuid)
);


CREATE TABLE connect.dashboards (
    uuid uuid NOT NULL,
    label character varying(256),
    report_uuid_1 uuid,
    report_uuid_2 uuid,
    date_range1 integer NOT NULL,
    date_range2 integer NOT NULL,
    custom_date1_from text,
    custom_date1_to text,
    custom_date2_from text,
    custom_date2_to text,
    report_parameterlist_1 text,
    report_parameterlist_2 text,
    PRIMARY KEY (uuid)
);


CREATE TABLE connect.data_queue (
    uuid uuid NOT NULL,
    type character varying(32) NOT NULL,
    ca_uuid uuid NOT NULL,
    name character varying,
    uploaded_date timestamp with time zone NOT NULL,
    lastmodified_date timestamp with time zone,
    uploaded_by character varying NOT NULL,
    file character varying,
    status character varying(32) NOT NULL,
    status_message character varying,
    work_item_uuid uuid,
    CONSTRAINT status_chk CHECK (((status)::text = ANY ((ARRAY['UPLOADING'::character varying, 'QUEUED'::character varying, 'PROCESSING'::character varying, 'COMPLETE'::character varying, 'ERROR'::character varying])::text[]))),
    PRIMARY KEY (uuid)
);

CREATE TABLE connect.map_layers (
    uuid uuid NOT NULL,
    active boolean NOT NULL,
    token character varying(256),
    wms_layer_list text,
    layer_name character varying(32),
    layer_order integer NOT NULL,
    layer_type character varying(16) NOT NULL,
    CONSTRAINT type_chk CHECK (((layer_type)::text = 'WMS'::text)),
    PRIMARY KEY (uuid)
);


CREATE TABLE connect.quicklinks (
    uuid uuid NOT NULL,
    url text NOT NULL,
    label character varying(256),
    created_on timestamp without time zone NOT NULL,
    created_by_user_uuid uuid NOT NULL,
    is_admin_created boolean NOT NULL,
    PRIMARY KEY(uuid)
);


CREATE TABLE connect.role_actions (
    uuid uuid NOT NULL,
    role_id character varying(32) NOT NULL,
    action character varying NOT NULL,
    resource uuid,
    PRIMARY KEY (uuid)
);
CREATE UNIQUE INDEX roleactions_unq1 ON connect.role_actions USING btree (role_id, action) WHERE (resource IS NULL);
CREATE UNIQUE INDEX roleactions_unq2 ON connect.role_actions USING btree (role_id, action, resource) WHERE (resource IS NOT NULL);


CREATE TABLE connect.roles (
    role_id character varying(32) NOT NULL,
    rolename character varying NOT NULL,
    is_system boolean DEFAULT false NOT NULL,
    PRIMARY KEY (role_id)
);


CREATE TABLE connect.shared_links (
    uuid uuid NOT NULL,
    ca_uuid uuid,
    owner_uuid uuid NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    url character varying(262143),
    is_user_token boolean DEFAULT false NOT NULL,
    allowed_ip character varying(24),
    date_created timestamp with time zone DEFAULT now() NOT NULL,
    permissionuser_uuid uuid,
    PRIMARY KEY (uuid)
);

CREATE TABLE connect.style_configuration (
    uuid uuid NOT NULL,
    style_id character varying(64) NOT NULL,
    active boolean NOT NULL,
    header_image bytea,
    header_style character varying(256),
    background_image bytea,
    body_style character varying(256),
    login_image bytea,
    server_name character varying(256),
    footer_text text,
    PRIMARY KEY (style_id)
);

CREATE TABLE connect.user_actions (
    username character varying NOT NULL,
    action character varying NOT NULL,
    resource uuid,
    uuid uuid NOT NULL,
    PRIMARY KEY (username, action, uuid)
);
CREATE UNIQUE INDEX useractions_unq1 ON connect.user_actions USING btree (username, action) WHERE (resource IS NULL);
CREATE UNIQUE INDEX useractions_unq2 ON connect.user_actions USING btree (username, action, resource) WHERE (resource IS NOT NULL);

COMMENT ON TABLE connect.user_actions IS 'A table for listing user permissions and associated resources.';
COMMENT ON COLUMN connect.user_actions.username IS 'The unique user identifier.';
COMMENT ON COLUMN connect.user_actions.action IS 'The action the user has permission to perform.';
COMMENT ON COLUMN connect.user_actions.resource IS 'Unique identifier to the resource (null implies all resources)';
COMMENT ON COLUMN connect.user_actions.uuid IS 'A unqiue identifier for hibernate.';

CREATE TABLE connect.user_quicklinks (
    uuid uuid NOT NULL,
    user_uuid uuid NOT NULL,
    quicklink_uuid uuid NOT NULL,
    label_override character varying(256),
    link_order integer,
    PRIMARY KEY(uuid)
);

CREATE TABLE connect.user_roles (
    username character varying NOT NULL,
    role_id character varying(32) NOT NULL,
    PRIMARY KEY (username, role_id)
);
COMMENT ON TABLE connect.user_roles IS 'A list of webserver roles supported by each user.';
COMMENT ON COLUMN connect.user_roles.username IS 'The unique username.';
COMMENT ON COLUMN connect.user_roles.role_id IS 'The webserver role.';


CREATE TABLE connect.users (
    uuid uuid NOT NULL,
    username character varying(256) NOT NULL,
    password character(60) NOT NULL,
    email character varying,
    resetid character varying,
    resetdatetime timestamp without time zone,
    home_ca_uuid uuid,
    default_basemaps varchar,
    UNIQUE(username),
    UNIQUE (uuid),
    UNIQUE(resetid),
    PRIMARY KEY (uuid, username)
);
COMMENT ON TABLE connect.users IS 'A list of smart connect users.';
COMMENT ON COLUMN connect.users.uuid IS 'A unqiue identifier for hibernate.';
COMMENT ON COLUMN connect.users.username IS 'The unique username';
COMMENT ON COLUMN connect.users.password IS 'The bcrypt has encoded password for the user.';
COMMENT ON COLUMN connect.users.email IS 'The user email address';
COMMENT ON COLUMN connect.users.resetid IS 'A unique key sent to the users for resetting their password.';
COMMENT ON COLUMN connect.users.resetdatetime IS 'The date/time the last reset link was sent to the user.';

CREATE TABLE connect.users_default_dashboard (
    user_uuid uuid NOT NULL,
    dashboard_uuid uuid NOT NULL,
    date_range1 integer NOT NULL,
    date_range2 integer NOT NULL,
    custom_date1_from text,
    custom_date1_to text,
    custom_date2_from text,
    custom_date2_to text,
    PRIMARY KEY(user_uuid)
);


CREATE TABLE connect.work_item (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    start_datetime timestamp without time zone NOT NULL,
    total_bytes bigint NOT NULL,
    local_filename character varying NOT NULL,
    type character varying(16) NOT NULL,
    status character varying(16) NOT NULL,
    locale character varying(56) NOT NULL,
    message character varying,
    PRIMARY KEY (uuid),
    CONSTRAINT status_chk CHECK (((status)::text = ANY ((ARRAY['UPLOADING'::character varying, 'PROCESSING'::character varying, 'COMPLETE'::character varying, 'ERROR'::character varying])::text[]))),
    CONSTRAINT type_chk CHECK (((type)::text = ANY ((ARRAY['UP_CA'::character varying, 'UP_SYNC'::character varying, 'DOWN_CA'::character varying, 'DOWN_SYNC'::character varying, 'UP_DATAQUEUE'::character varying, 'UP_CTPACKAGE'::character varying, 'UP_NAVIGATION'::character varying])::text[])))
);
COMMENT ON TABLE connect.work_item IS 'A table for tracking uploads and supporting upload apis.';
COMMENT ON COLUMN connect.work_item.uuid IS 'A unique system generated identifier.';
COMMENT ON COLUMN connect.work_item.ca_uuid IS 'The unique Conservation Area identifier.';
COMMENT ON COLUMN connect.work_item.start_datetime IS 'The start time of the upload.';
COMMENT ON COLUMN connect.work_item.total_bytes IS 'Total number of bytes to upload.';
COMMENT ON COLUMN connect.work_item.local_filename IS 'Name of the file in the local filestore.';
COMMENT ON COLUMN connect.work_item.type IS 'File type.';
COMMENT ON COLUMN connect.work_item.status IS 'Status of upload and processing';
COMMENT ON COLUMN connect.work_item.message IS 'Error message or other info message asociated with upload.';

CREATE TABLE connect.smartcollect_user(
  uuid uuid not null, 
  state varchar(32) not null, 
  source varchar(4096) not null,
  device_id varchar(32) not null, 
  validation_sent_date timestamp, 
  validation_key varchar(64), 
  primary key (uuid), 
  unique(source, device_id)
);



CREATE TABLE smart.conservation_area_property(
 uuid uuid not null, 
 ca_uuid uuid not null, 
 pkey varchar(256) not null, 
 value varchar(1024), 
 primary key (uuid), 
 unique(ca_uuid, pkey)
);

CREATE TABLE smart.signature_type (
  uuid uuid not null, 
  ca_uuid uuid not null, 
  keyid varchar(128) not null, 
  primary key (uuid), 
  unique(ca_uuid, keyid)
);

-- SMART TABLES
CREATE TABLE smart.agency (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    keyid character varying(128),
    PRIMARY KEY(uuid)
);

CREATE TABLE smart.area_geometries (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    area_type character varying(5) NOT NULL,
    keyid character varying(256),
    geom bytea NOT NULL,
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.asset (
    uuid uuid NOT NULL,
    asset_type_uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    id character varying(128) NOT NULL,
    is_retired boolean DEFAULT false NOT NULL,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.asset_attribute (
    uuid uuid NOT NULL,
    keyid character varying(128) NOT NULL,
    type character(8) NOT NULL,
    ca_uuid uuid NOT NULL,
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.asset_attribute_list_item (
    uuid uuid NOT NULL,
    attribute_uuid uuid NOT NULL,
    keyid character varying(128) NOT NULL,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.asset_attribute_value (
    asset_uuid uuid NOT NULL,
    attribute_uuid uuid NOT NULL,
    string_value character varying(8200),
    list_item_uuid uuid,
    double_value1 double precision,
    double_value2 double precision,
    PRIMARY KEY (asset_uuid, attribute_uuid)
);

CREATE TABLE smart.asset_deployment (
    uuid uuid NOT NULL,
    asset_uuid uuid NOT NULL,
    station_location_uuid uuid NOT NULL,
    start_date timestamp without time zone NOT NULL,
    end_date timestamp without time zone,
    track bytea,
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.asset_deployment_disruption (
    uuid uuid not null,
    asset_deployment_uuid uuid not null,
    start_date timestamp not null,
    end_date timestamp not null,
    comment varchar(32672),
    primary key (uuid)
);


CREATE TABLE smart.asset_deployment_attribute_value (
    asset_deployment_uuid uuid NOT NULL,
    attribute_uuid uuid NOT NULL,
    string_value character varying(8200),
    list_item_uuid uuid,
    double_value1 double precision,
    double_value2 double precision,
    PRIMARY KEY (asset_deployment_uuid, attribute_uuid)
);

CREATE TABLE smart.asset_history_record (
    uuid uuid NOT NULL,
    asset_uuid uuid NOT NULL,
    date timestamp without time zone NOT NULL,
    comment character varying(32672),
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.asset_map_style (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    name character varying(1024),
    style_string character varying(32672),
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.asset_metadata_mapping (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    metadata_type character varying(16) NOT NULL,
    metadata_key character varying(32672) NOT NULL,
    search_order integer NOT NULL,
    asset_field character varying(32),
    category_uuid uuid,
    attribute_uuid uuid,
    attribute_list_item_uuid uuid,
    attribute_tree_node_uuid uuid,
    state varchar(10) not null,
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.asset_module_settings (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    keyid character varying(128),
    value character varying(32000),
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.asset_observation_query (
    uuid uuid NOT NULL,
    id character varying(6) NOT NULL,
    creator_uuid uuid NOT NULL,
    query_filter character varying(32672),
    ca_filter character varying(32672),
    ca_uuid uuid NOT NULL,
    folder_uuid uuid,
    column_filter character varying(32672),
    style character varying,
    shared boolean NOT NULL,
    show_data_columns_only boolean,
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.asset_station (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    id character varying(128) NOT NULL,
    x double precision NOT NULL,
    y double precision NOT NULL,
    buffer double precision not null,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.asset_station_attribute (
    attribute_uuid uuid NOT NULL,
    seq_order integer NOT NULL,
    PRIMARY KEY (attribute_uuid)
);

CREATE TABLE smart.asset_station_attribute_value (
    station_uuid uuid NOT NULL,
    attribute_uuid uuid NOT NULL,
    string_value character varying(8200),
    list_item_uuid uuid,
    double_value1 double precision,
    double_value2 double precision,
    PRIMARY KEY (station_uuid, attribute_uuid)
);

CREATE TABLE smart.asset_station_location (
    uuid uuid NOT NULL,
    station_uuid uuid NOT NULL,
    id character varying(128) NOT NULL,
    x double precision NOT NULL,
    y double precision NOT NULL,
    buffer double precision not null,
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.asset_station_location_attribute (
    attribute_uuid uuid NOT NULL,
    seq_order integer NOT NULL,
    PRIMARY KEY (attribute_uuid)
);

CREATE TABLE smart.asset_station_location_attribute_value (
    station_location_uuid uuid NOT NULL,
    attribute_uuid uuid NOT NULL,
    string_value character varying(1024),
    list_item_uuid uuid,
    double_value1 double precision,
    double_value2 double precision,
    PRIMARY KEY (station_location_uuid, attribute_uuid)
);

CREATE TABLE smart.asset_station_location_history (
    uuid uuid NOT NULL,
    station_location_uuid uuid NOT NULL,
    date timestamp without time zone NOT NULL,
    comment character varying(32672),
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.asset_summary_query (
    uuid uuid NOT NULL,
    id character varying(6) NOT NULL,
    creator_uuid uuid NOT NULL,
    query_def character varying(32672),
    ca_filter character varying(32672),
    ca_uuid uuid NOT NULL,
    folder_uuid uuid,
    shared boolean NOT NULL,
    style character varying,
    query_type_key varchar(32) not null,
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.asset_type (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    keyid character varying(128),
    icon bytea,
    incident_cutoff integer,
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.asset_type_attribute (
    asset_type_uuid uuid NOT NULL,
    attribute_uuid uuid NOT NULL,
    seq_order integer NOT NULL,
    PRIMARY KEY (asset_type_uuid, attribute_uuid)
);

CREATE TABLE smart.asset_type_deployment_attribute (
    asset_type_uuid uuid NOT NULL,
    attribute_uuid uuid NOT NULL,
    seq_order integer NOT NULL,
    PRIMARY KEY (asset_type_uuid, attribute_uuid)
);

CREATE TABLE smart.asset_waypoint (
    uuid uuid NOT NULL,
    wp_uuid uuid NOT NULL,
    asset_deployment_uuid uuid NOT NULL,
    state smallint NOT NULL,
    incident_length integer NOT NULL,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.asset_waypoint_attachment (
    wp_attachment_uuid uuid NOT NULL,
    asset_waypoint_uuid uuid NOT NULL,
    PRIMARY KEY (wp_attachment_uuid, asset_waypoint_uuid)
);

CREATE TABLE smart.asset_waypoint_query (
    uuid uuid NOT NULL,
    id character varying(6) NOT NULL,
    creator_uuid uuid NOT NULL,
    query_filter character varying(32672),
    ca_filter character varying(32672),
    ca_uuid uuid NOT NULL,
    folder_uuid uuid,
    column_filter character varying(32672),
    surveydesign_key character varying(128),
    shared boolean NOT NULL,
    style character varying,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.ca_projection (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    name character varying(1024) NOT NULL,
    definition character varying NOT NULL,
    is_default boolean,
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.cm_attribute (
    uuid uuid NOT NULL,
    node_uuid uuid NOT NULL,
    attribute_uuid uuid NOT NULL,
    attribute_order smallint,
    config_uuid uuid,
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.cm_attribute_config (
    uuid uuid NOT NULL,
    cm_uuid uuid NOT NULL,
    dm_attribute_uuid uuid NOT NULL,
    display_mode character varying(10),
    is_default boolean,
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.cm_attribute_list (
    uuid uuid NOT NULL,
    list_element_uuid uuid NOT NULL,
    is_active boolean NOT NULL,
    list_order smallint,
    config_uuid uuid NOT NULL,
    imagetype character varying(32),
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.cm_attribute_option (
    uuid uuid NOT NULL,
    cm_attribute_uuid uuid NOT NULL,
    option_id character varying(128) NOT NULL,
    number_value double precision,
    string_value character varying(32672),
    uuid_value uuid,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.cm_attribute_tree_node (
    uuid uuid NOT NULL,
    dm_tree_node_uuid uuid,
    is_active boolean NOT NULL,
    parent_uuid uuid,
    node_order smallint,
    display_mode character varying(10),
    config_uuid uuid NOT NULL,
    imagetype character varying(32),
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.cm_ct_properties_profile (
    cm_uuid uuid NOT NULL,
    profile_uuid uuid NOT NULL,
    PRIMARY KEY (cm_uuid)
);


CREATE TABLE smart.cm_node (
    uuid uuid NOT NULL,
    cm_uuid uuid NOT NULL,
    category_uuid uuid,
    parent_node_uuid uuid,
    node_order smallint,
    photo_allowed boolean,
    photo_required boolean,
    collect_multiple_obs boolean,
    use_single_gps_point boolean,
    display_mode character varying(10),
    imagetype character varying(32),
    signatures varchar,
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.compound_query (
    uuid uuid NOT NULL,
    creator_uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    ca_filter character varying(32672),
    folder_uuid uuid,
    shared boolean,
    id character varying(6),
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.compound_query_layer (
    uuid uuid NOT NULL,
    compound_query_uuid uuid NOT NULL,
    query_uuid uuid NOT NULL,
    query_type character varying(32),
    style character varying,
    layer_order integer NOT NULL,
    date_filter character varying(256),
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.configurable_model (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    display_mode character varying(10),
    instant_gps boolean,
    photo_first boolean,
    iconset_uuid uuid,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.connect_account (
    employee_uuid uuid NOT NULL,
    connect_uuid uuid NOT NULL,
    connect_user character varying(32),
    connect_pass character varying(1024),
    PRIMARY KEY (employee_uuid, connect_uuid)
);


CREATE TABLE smart.connect_alert (
    uuid uuid NOT NULL,
    cm_uuid uuid NOT NULL,
    alert_item_uuid uuid NOT NULL,
    cm_attribute_uuid uuid,
    level smallint NOT NULL,
    type character varying(64),
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.connect_ct_properties (
    uuid uuid NOT NULL,
    cm_uuid uuid NOT NULL,
    ping_frequency integer,
    data_frequency integer,
    ping_type uuid,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.connect_data_queue (
    uuid uuid NOT NULL,
    type character varying(32) NOT NULL,
    ca_uuid uuid,
    name character varying(4096),
    status character varying(32) NOT NULL,
    queue_order integer,
    error_message character varying(8192),
    local_file character varying(4096),
    date_processed timestamp without time zone,
    server_item_uuid uuid,
    CONSTRAINT status_chk CHECK (((status)::text = ANY ((ARRAY['DOWNLOADING'::character varying, 'REQUEUED'::character varying, 'QUEUED'::character varying, 'PROCESSING'::character varying, 'COMPLETE'::character varying, 'COMPLETE_WARN'::character varying, 'ERROR'::character varying])::text[]))),
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.connect_data_queue_option (
    ca_uuid uuid NOT NULL,
    keyid character varying(256) NOT NULL,
    value character varying(512),
    PRIMARY KEY (ca_uuid, keyid)
);


CREATE TABLE smart.connect_server (
    uuid uuid NOT NULL,
    ca_uuid uuid,
    url character varying(2064),
    certificate character varying(32000),
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.connect_server_option (
    server_uuid uuid NOT NULL,
    option_key character varying(32) NOT NULL,
    value character varying(2048),
    PRIMARY KEY (server_uuid, option_key)
);

CREATE TABLE smart.conservation_area (
    uuid uuid NOT NULL,
    id character varying(8) NOT NULL,
    name character varying(256),
    designation character varying(1024),
    description character varying(2056),
    organization character varying(256),
    pointofcontact character varying(256),
    country character varying(256),
    owner character varying(256),
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.ct_incident_link (
    uuid uuid NOT NULL,
    ct_group_id uuid,
    wp_uuid uuid NOT NULL,
    ct_root_id uuid,
    obs_group_uuid uuid,
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.ct_incident_package(
	uuid uuid not null, 
	name varchar(512), 
	ca_uuid uuid not null,
	cm_uuid uuid, 
	ctprofile_uuid uuid, 
	basemapdef varchar(32672), 
	maplayersdef varchar(32672),
	primary key (uuid)
);


CREATE TABLE smart.ct_metadata_value (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    package_uuid uuid NOT NULL,
    keyid character varying(32) NOT NULL,
    is_visible boolean NOT NULL,
    string_value character varying(8192),
    boolean_value boolean,
    uuid_value uuid,
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.ct_metadata_value_uuid (
    uuid uuid NOT NULL,
    field_uuid uuid NOT NULL,
    uuid_value uuid NOT NULL,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.ct_mission_link (
    ct_uuid uuid NOT NULL,
    mission_uuid uuid NOT NULL,
    ct_device_id character varying(36) NOT NULL,
    last_observation_cnt integer,
    group_start_time timestamp without time zone,
    su_uuid uuid,
    PRIMARY KEY (ct_uuid)
);

CREATE TABLE smart.ct_mission_wplink (
    uuid uuid NOT NULL,
    ct_mission_link_uuid uuid,
    ct_root_id uuid,
    ct_group_id uuid,
    wp_uuid uuid,
    obs_group_uuid uuid,
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.ct_navigation_layer (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    name character varying(512),
    targets bytea,
    created_date date NOT NULL,
    last_modified_date date,
    last_modified_by uuid,
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.ct_patrol_link (
    ct_uuid uuid NOT NULL,
    patrol_leg_uuid uuid NOT NULL,
    ct_device_id character varying(36) NOT NULL,
    last_observation_cnt integer,
    group_start_time timestamp without time zone,
    PRIMARY KEY (ct_uuid)
);

CREATE TABLE smart.ct_patrol_package (
    uuid uuid NOT NULL,
    name character varying(512),
    ca_uuid uuid NOT NULL,
    cm_uuid uuid,
    ctprofile_uuid uuid,
    has_incident boolean DEFAULT false,
    incident_uuid uuid,
    basemapdef character varying(32672),
    maplayersdef varchar(32672),
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.ct_patrol_wplink (
    uuid uuid NOT NULL,
    ct_patrol_link_uuid uuid,
    ct_root_id uuid,
    ct_group_id uuid,
    wp_uuid uuid,
    obs_group_uuid uuid,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.ct_properties_option (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    option_id character varying(32) NOT NULL,
    double_value double precision,
    integer_value integer,
    string_value character varying(1024),
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.ct_properties_profile (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    is_default boolean,
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.ct_properties_profile_option (
    uuid uuid NOT NULL,
    profile_uuid uuid NOT NULL,
    option_id character varying(32) NOT NULL,
    double_value double precision,
    integer_value integer,
    string_value character varying(1024),
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.ct_survey_package (
    uuid uuid NOT NULL,
    name character varying(512),
    ca_uuid uuid NOT NULL,
    sd_uuid uuid,
    ctprofile_uuid uuid,
    has_incident boolean DEFAULT false,
    incident_uuid uuid,
    basemapdef character varying(32672),
    maplayersdef varchar(32672),
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.db_version (
    version character varying(15) NOT NULL,
    plugin_id character varying(512) NOT NULL
);

CREATE TABLE smart.dm_aggregation (
    name character varying(16) NOT NULL,
    PRIMARY KEY (name)
);


CREATE TABLE smart.dm_aggregation_i18n (
    name character varying(16) NOT NULL,
    lang_code character varying(5) NOT NULL,
    gui_name character varying(96) NOT NULL,
    PRIMARY KEY (name, lang_code)
);


CREATE TABLE smart.dm_att_agg_map (
    attribute_uuid uuid NOT NULL,
    agg_name character varying(16) NOT NULL,
    PRIMARY KEY (attribute_uuid, agg_name)
);

CREATE TABLE smart.dm_attribute (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    keyid character varying(128) NOT NULL,
    is_required boolean NOT NULL,
    att_type character varying(7) NOT NULL,
    min_value double precision,
    max_value double precision,
    regex character varying(1024),
    icon_uuid uuid,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.dm_attribute_list (
    uuid uuid NOT NULL,
    attribute_uuid uuid NOT NULL,
    keyid character varying(128) NOT NULL,
    list_order smallint NOT NULL,
    is_active boolean NOT NULL,
    icon_uuid uuid,
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.dm_attribute_tree (
    uuid uuid NOT NULL,
    keyid character varying(128) NOT NULL,
    node_order smallint NOT NULL,
    parent_uuid uuid,
    attribute_uuid uuid,
    is_active boolean NOT NULL,
    hkey character varying NOT NULL,
    icon_uuid uuid,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.dm_cat_att_map (
    category_uuid uuid NOT NULL,
    attribute_uuid uuid NOT NULL,
    att_order smallint NOT NULL,
    is_active boolean NOT NULL,
    PRIMARY KEY (category_uuid, attribute_uuid)
);

CREATE TABLE smart.dm_category (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    keyid character varying(128) NOT NULL,
    parent_category_uuid uuid,
    is_multiple boolean,
    cat_order smallint,
    is_active boolean NOT NULL,
    hkey character varying NOT NULL,
    icon_uuid uuid,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.e_action (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    id character varying(128) NOT NULL,
    type_key character varying(128) NOT NULL,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.e_action_parameter_value (
    action_uuid uuid NOT NULL,
    parameter_key character varying(128) NOT NULL,
    parameter_value character varying(4096) NOT NULL,
    PRIMARY KEY (action_uuid, parameter_key)
);


CREATE TABLE smart.e_event_action (
    uuid uuid NOT NULL,
    filter_uuid uuid NOT NULL,
    action_uuid uuid NOT NULL,
    is_enabled boolean DEFAULT true NOT NULL,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.e_event_filter (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    id character varying(128) NOT NULL,
    filter_string character varying(32000) NOT NULL,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.employee (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    id character varying(32) NOT NULL,
    givenname character varying(64) NOT NULL,
    familyname character varying(64) NOT NULL,
    startemploymentdate date NOT NULL,
    endemploymentdate date,
    datecreated date NOT NULL,
    birthdate date,
    gender character(1) NOT NULL,
    smartuserid character varying(16),
    smartpassword character varying(256),
    agency_uuid uuid,
    rank_uuid uuid,
    smartuserlevel character varying(5000),
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.employee_team (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.employee_team_member (
    employee_uuid uuid NOT NULL,
    team_uuid uuid NOT NULL,
    PRIMARY KEY (employee_uuid, team_uuid)
);

CREATE TABLE smart.entity (
    uuid uuid NOT NULL,
    entity_type_uuid uuid NOT NULL,
    id character varying(32) NOT NULL,
    status character varying(8) NOT NULL,
    attribute_list_item_uuid uuid NOT NULL,
    x double precision,
    y double precision,
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.entity_attribute (
    uuid uuid NOT NULL,
    entity_type_uuid uuid NOT NULL,
    dm_attribute_uuid uuid NOT NULL,
    is_required boolean DEFAULT false NOT NULL,
    is_primary boolean DEFAULT true NOT NULL,
    attribute_order integer DEFAULT 1 NOT NULL,
    keyid character varying(128) NOT NULL,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.entity_attribute_value (
    entity_attribute_uuid uuid NOT NULL,
    entity_uuid uuid NOT NULL,
    number_value double precision,
    string_value character varying(8200),
    list_element_uuid uuid,
    tree_node_uuid uuid,
    PRIMARY KEY (entity_attribute_uuid, entity_uuid)
);


CREATE TABLE smart.entity_gridded_query (
    uuid uuid NOT NULL,
    creator_uuid uuid NOT NULL,
    query_filter character varying,
    ca_filter character varying,
    query_def character varying,
    folder_uuid uuid,
    shared boolean NOT NULL,
    ca_uuid uuid NOT NULL,
    id character varying(6) NOT NULL,
    crs_definition character varying NOT NULL,
    style character varying,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.entity_observation_query (
    uuid uuid NOT NULL,
    creator_uuid uuid NOT NULL,
    query_filter character varying,
    ca_filter character varying,
    ca_uuid uuid NOT NULL,
    folder_uuid uuid,
    column_filter character varying,
    shared boolean DEFAULT false NOT NULL,
    id character varying(6) NOT NULL,
    style character varying,
    show_data_columns_only boolean,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.entity_summary_query (
    uuid uuid NOT NULL,
    creator_uuid uuid NOT NULL,
    ca_filter character varying,
    query_def character varying,
    folder_uuid uuid,
    shared boolean NOT NULL,
    ca_uuid uuid NOT NULL,
    id character varying(6) NOT NULL,
    PRIMARY KEY (uuid)
);



CREATE TABLE smart.entity_type (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    keyid character varying(128) NOT NULL,
    date_created timestamp without time zone NOT NULL,
    creator_uuid uuid NOT NULL,
    status character varying(16) NOT NULL,
    dm_attribute_uuid uuid NOT NULL,
    entity_type character varying(16),
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.entity_waypoint_query (
    uuid uuid NOT NULL,
    creator_uuid uuid NOT NULL,
    query_filter character varying,
    ca_filter character varying,
    ca_uuid uuid NOT NULL,
    folder_uuid uuid,
    column_filter character varying,
    shared boolean DEFAULT false NOT NULL,
    id character varying(6) NOT NULL,
    style character varying,
    PRIMARY KEY (uuid)
);



CREATE TABLE smart.gridded_query (
    uuid uuid NOT NULL,
    creator_uuid uuid NOT NULL,
    query_filter character varying,
    ca_filter character varying,
    query_def character varying,
    folder_uuid uuid,
    shared boolean NOT NULL,
    ca_uuid uuid NOT NULL,
    id character varying(6) NOT NULL,
    crs_definition character varying NOT NULL,
    style character varying,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.i18n_label (
    language_uuid uuid NOT NULL,
    element_uuid uuid NOT NULL,
    value character varying(1024) NOT NULL,
    PRIMARY KEY (language_uuid, element_uuid)
);


CREATE TABLE smart.i_attachment (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    date_created timestamp without time zone NOT NULL,
    created_by uuid NOT NULL,
    description character varying(2048),
    filename character varying(1024) NOT NULL,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.i_attribute (
    uuid uuid NOT NULL,
    keyid character varying(128) NOT NULL,
    type character(8) NOT NULL,
    ca_uuid uuid NOT NULL,
    PRIMARY KEY (uuid)
);



CREATE TABLE smart.i_attribute_list_item (
    uuid uuid NOT NULL,
    attribute_uuid uuid NOT NULL,
    keyid character varying(128) NOT NULL,
    list_order integer DEFAULT 0 NOT NULL,
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.i_config_option (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    keyid character varying(32000) NOT NULL,
    value character varying(32000),
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.i_diagram_entity_type_style (
    uuid uuid NOT NULL,
    style_uuid uuid NOT NULL,
    entity_type_uuid uuid NOT NULL,
    options character varying(1024),
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.i_diagram_relationship_type_style (
    uuid uuid NOT NULL,
    style_uuid uuid NOT NULL,
    relationship_type_uuid uuid NOT NULL,
    options character varying(1024),
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.i_diagram_style (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    is_default boolean,
    options character varying(2048),
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.i_entity (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    date_created timestamp without time zone NOT NULL,
    date_modified timestamp without time zone,
    created_by uuid NOT NULL,
    last_modified_by uuid,
    primary_attachment_uuid uuid,
    entity_type_uuid uuid NOT NULL,
    comment character varying,
    profile_uuid uuid NOT NULL,
    dm_list_item_uuid uuid,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.i_entity_attachment (
    entity_uuid uuid NOT NULL,
    attachment_uuid uuid NOT NULL,
    PRIMARY KEY (entity_uuid, attachment_uuid)
);


CREATE TABLE smart.i_entity_attribute_value (
    entity_uuid uuid NOT NULL,
    attribute_uuid uuid NOT NULL,
    string_value character varying(8200),
    double_value double precision,
    double_value2 double precision,
    list_item_uuid uuid,
    metaphone character varying(32600),
    employee_uuid uuid,
    PRIMARY KEY (entity_uuid, attribute_uuid)
);


CREATE TABLE smart.i_entity_location (
    entity_uuid uuid NOT NULL,
    location_uuid uuid NOT NULL,
    PRIMARY KEY (entity_uuid, location_uuid)
);


CREATE TABLE smart.i_entity_record (
    entity_uuid uuid NOT NULL,
    record_uuid uuid NOT NULL,
    PRIMARY KEY (entity_uuid, record_uuid)
);


CREATE TABLE smart.i_entity_record_query (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    query_string character varying,
    date_created timestamp without time zone NOT NULL,
    last_modified_date timestamp without time zone,
    created_by uuid NOT NULL,
    last_modified_by uuid,
    profile_filter character varying(32672),
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.i_entity_relationship (
    uuid uuid NOT NULL,
    src_entity_uuid uuid NOT NULL,
    relationship_type_uuid uuid NOT NULL,
    target_entity_uuid uuid NOT NULL,
    source character varying(16) NOT NULL,
    source_uuid uuid,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.i_entity_relationship_attribute_value (
    entity_relationship_uuid uuid NOT NULL,
    attribute_uuid uuid NOT NULL,
    string_value character varying(8200),
    double_value double precision,
    double_value2 double precision,
    list_item_uuid uuid,
    employee_uuid uuid,
    PRIMARY KEY (entity_relationship_uuid, attribute_uuid)
);


CREATE TABLE smart.i_entity_search (
    uuid uuid NOT NULL,
    search_string character varying,
    ca_uuid uuid NOT NULL,
    PRIMARY KEY (uuid)
);



CREATE TABLE smart.i_entity_summary_query (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    query_string character varying,
    date_created timestamp without time zone NOT NULL,
    last_modified_date timestamp without time zone,
    created_by uuid NOT NULL,
    last_modified_by uuid,
    profile_filter character varying(32672),
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.i_entity_type (
    uuid uuid NOT NULL,
    keyid character varying(128) NOT NULL,
    ca_uuid uuid NOT NULL,
    id_attribute_uuid uuid NOT NULL,
    icon bytea,
    birt_template character varying(4096),
    dm_attribute_uuid uuid,
    dm_active_filter varchar,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.i_entity_type_attribute (
    entity_type_uuid uuid NOT NULL,
    attribute_uuid uuid NOT NULL,
    attribute_group_uuid uuid,
    is_duplicate_check boolean not null,
    seq_order integer NOT NULL,
    PRIMARY KEY (entity_type_uuid, attribute_uuid)
);


CREATE TABLE smart.i_entity_type_attribute_group (
    uuid uuid NOT NULL,
    entity_type_uuid uuid NOT NULL,
    seq_order integer NOT NULL,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.i_location (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    geometry bytea NOT NULL,
    datetime timestamp without time zone,
    comment character varying(4096),
    id character varying(1028),
    record_uuid uuid,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.i_observation (
    uuid uuid NOT NULL,
    location_uuid uuid NOT NULL,
    category_uuid uuid,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.i_observation_attribute (
	uuid uuid not null,
    observation_uuid uuid NOT NULL,
    attribute_uuid uuid NOT NULL,
    list_element_uuid uuid,
    tree_node_uuid uuid,
    string_value character varying(8200),
    double_value double precision,
    PRIMARY KEY (uuid),
    UNIQUE (observation_uuid, attribute_uuid)
);

CREATE TABLE smart.i_observation_attribute_list (
	list_element_uuid uuid not null,
	observation_attribute_uuid uuid not null,
	primary key (list_element_uuid, observation_attribute_uuid)
);

CREATE TABLE smart.i_permission (
    employee_uuid uuid NOT NULL,
    profile_uuid uuid NOT NULL,
    permissions integer NOT NULL,
    primary key(employee_uuid, profile_uuid)
);


CREATE TABLE smart.i_profile_config (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    keyid character varying(128) NOT NULL,
    color integer,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.i_profile_entity_type (
    entity_type_uuid uuid NOT NULL,
    profile_uuid uuid NOT NULL,
    PRIMARY KEY (entity_type_uuid, profile_uuid)
);


CREATE TABLE smart.i_profile_record_source (
    record_source_uuid uuid NOT NULL,
    profile_uuid uuid NOT NULL,
    PRIMARY KEY (record_source_uuid, profile_uuid)
);


CREATE TABLE smart.i_record (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    source_uuid uuid,
    title character varying(1024) NOT NULL,
    date_created timestamp without time zone NOT NULL,
    last_modified_date timestamp without time zone,
    created_by uuid NOT NULL,
    last_modified_by uuid,
    date_exported timestamp without time zone,
    status character varying(16) NOT NULL,
    description character varying,
    comment character varying,
    primary_date timestamp without time zone NOT NULL,
    smart_source character varying(2048),
    profile_uuid uuid NOT NULL,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.i_record_attachment (
    record_uuid uuid NOT NULL,
    attachment_uuid uuid NOT NULL,
    PRIMARY KEY (record_uuid, attachment_uuid)
);


CREATE TABLE smart.i_record_attribute_value (
    uuid uuid NOT NULL,
    record_uuid uuid NOT NULL,
    attribute_uuid uuid NOT NULL,
    string_value character varying(8200),
    double_value double precision,
    double_value2 double precision,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.i_record_attribute_value_list (
    value_uuid uuid NOT NULL,
    element_uuid uuid NOT NULL,
    PRIMARY KEY (value_uuid, element_uuid)
);


CREATE TABLE smart.i_record_obs_query (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    style character varying,
    query_string character varying,
    column_filter character varying,
    date_created timestamp without time zone NOT NULL,
    last_modified_date timestamp without time zone,
    created_by uuid NOT NULL,
    last_modified_by uuid,
    profile_filter character varying(32672),
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.i_record_query (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    query_string character varying(32700),
    date_created timestamp without time zone NOT NULL,
    last_modified_date timestamp without time zone,
    created_by uuid NOT NULL,
    last_modified_by uuid,
    profile_filter character varying(32672),
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.i_record_summary_query (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    query_string character varying(32700),
    date_created timestamp without time zone NOT NULL,
    last_modified_date timestamp without time zone,
    created_by uuid NOT NULL,
    last_modified_by uuid,
    profile_filter character varying(32672),
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.i_recordsource (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    keyid character varying(128) NOT NULL,
    icon bytea,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.i_recordsource_attribute (
    uuid uuid NOT NULL,
    source_uuid uuid NOT NULL,
    attribute_uuid uuid,
    entity_type_uuid uuid,
    seq_order integer,
    is_multi boolean,
    is_duplicate_check boolean not null,
    keyid character varying(128) NOT NULL,
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.i_relationship_group (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    keyid character varying(128) NOT NULL,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.i_relationship_type (
    uuid uuid NOT NULL,
    keyid character varying(128) NOT NULL,
    ca_uuid uuid NOT NULL,
    icon bytea,
    relationship_group_uuid uuid,
    src_entity_type uuid,
    target_entity_type uuid,
    src_profile_uuid uuid NOT NULL,
    target_profile_uuid uuid NOT NULL,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.i_relationship_type_attribute (
    relationship_type_uuid uuid NOT NULL,
    attribute_uuid uuid NOT NULL,
    seq_order integer NOT NULL,
    PRIMARY KEY (relationship_type_uuid, attribute_uuid)
);


CREATE TABLE smart.i_working_set (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    date_created timestamp without time zone NOT NULL,
    last_modified_date timestamp without time zone,
    created_by uuid NOT NULL,
    last_modified_by uuid,
    entity_date_filter character varying(1024),
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.i_working_set_entity (
    working_set_uuid uuid NOT NULL,
    entity_uuid uuid NOT NULL,
    map_style character varying,
    is_visible boolean DEFAULT true NOT NULL,
    PRIMARY KEY (working_set_uuid, entity_uuid)
);


CREATE TABLE smart.i_working_set_query (
    working_set_uuid uuid NOT NULL,
    query_uuid uuid NOT NULL,
    date_filter character varying(1024),
    map_style character varying,
    is_visible boolean DEFAULT true NOT NULL,
    query_type character varying(32) NOT NULL,
    PRIMARY KEY (working_set_uuid, query_uuid)
);


CREATE TABLE smart.i_working_set_record (
    working_set_uuid uuid NOT NULL,
    record_uuid uuid NOT NULL,
    map_style character varying,
    is_visible boolean DEFAULT true NOT NULL,
    PRIMARY KEY (working_set_uuid, record_uuid)
);

CREATE TABLE smart.icon (
    uuid uuid NOT NULL,
    keyid character varying(64) NOT NULL,
    ca_uuid uuid NOT NULL,
    UNIQUE (keyid, ca_uuid),
    PRIMARY KEY (uuid)
);



CREATE TABLE smart.iconfile (
    uuid uuid NOT NULL,
    icon_uuid uuid NOT NULL,
    iconset_uuid uuid NOT NULL,
    filename character varying(2064) NOT NULL,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.iconset (
    uuid uuid NOT NULL,
    keyid character varying(64) NOT NULL,
    ca_uuid uuid NOT NULL,
    is_default boolean DEFAULT false NOT NULL,
    PRIMARY KEY (uuid)
);

--CREATE TABLE smart.informant (
--    uuid uuid NOT NULL,
--    ca_uuid uuid NOT NULL,
--    id character varying(128),
--    is_active boolean NOT NULL,
--    PRIMARY KEY (uuid)
--);
--
--CREATE TABLE smart.intel_record_query (
--    uuid uuid NOT NULL,
--    creator_uuid uuid NOT NULL,
--    query_filter character varying,
--    ca_filter character varying,
--    ca_uuid uuid NOT NULL,
--    folder_uuid uuid,
--    column_filter character varying,
--    shared boolean DEFAULT false NOT NULL,
--    id character varying(6) NOT NULL,
--    style character varying,
--    PRIMARY KEY (uuid)
--);
--
--
--CREATE TABLE smart.intel_summary_query (
--    uuid uuid NOT NULL,
--    creator_uuid uuid NOT NULL,
--    ca_filter character varying,
--    ca_uuid uuid NOT NULL,
--    folder_uuid uuid,
--    shared boolean DEFAULT false NOT NULL,
--    id character varying(6) NOT NULL,
--    PRIMARY KEY (uuid)
--);
--
--CREATE TABLE smart.intelligence (
--    uuid uuid NOT NULL,
--    ca_uuid uuid NOT NULL,
--    received_date date NOT NULL,
--    patrol_uuid uuid,
--    from_date date NOT NULL,
--    to_date date,
--    description character varying,
--    creator_uuid uuid,
--    source_uuid uuid,
--    informant_uuid uuid,
--    PRIMARY KEY (uuid)
--);
--
--
--CREATE TABLE smart.intelligence_attachment (
--    uuid uuid NOT NULL,
--    intelligence_uuid uuid NOT NULL,
--    filename character varying(1024) NOT NULL,
--    PRIMARY KEY (uuid)
--);
--
--
--CREATE TABLE smart.intelligence_point (
--    uuid uuid NOT NULL,
--    intelligence_uuid uuid NOT NULL,
--    x double precision NOT NULL,
--    y double precision NOT NULL,
--    PRIMARY KEY (uuid)
--);
--
--CREATE TABLE smart.intelligence_source (
--    uuid uuid NOT NULL,
--    ca_uuid uuid NOT NULL,
--    keyid character varying(128),
--    is_active boolean NOT NULL,
--    PRIMARY KEY (uuid)
--);
--

CREATE TABLE smart.language (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    isdefault boolean DEFAULT false NOT NULL,
    code character varying(8),
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.map_styles (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    style_string character varying NOT NULL,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.mission (
    uuid uuid NOT NULL,
    survey_uuid uuid NOT NULL,
    id character varying(128) NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    comment character varying,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.mission_attribute (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    keyid character varying(128) NOT NULL,
    att_type character varying(7) NOT NULL,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.mission_attribute_list (
    uuid uuid NOT NULL,
    mission_attribute_uuid uuid NOT NULL,
    keyid character varying(128) NOT NULL,
    list_order smallint NOT NULL,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.mission_day (
    uuid uuid NOT NULL,
    mission_uuid uuid NOT NULL,
    mission_day date NOT NULL,
    start_time time without time zone NOT NULL,
    end_time time without time zone NOT NULL,
    rest_minutes integer,
    PRIMARY KEY (uuid)
);



CREATE TABLE smart.mission_member (
    mission_uuid uuid NOT NULL,
    employee_uuid uuid NOT NULL,
    is_leader boolean NOT NULL,
    PRIMARY KEY (mission_uuid, employee_uuid)
);


CREATE TABLE smart.mission_property (
    survey_design_uuid uuid NOT NULL,
    mission_attribute_uuid uuid NOT NULL,
    attribute_order integer NOT NULL,
    PRIMARY KEY (survey_design_uuid, mission_attribute_uuid)
);


CREATE TABLE smart.mission_property_value (
    mission_uuid uuid NOT NULL,
    mission_attribute_uuid uuid NOT NULL,
    number_value double precision,
    string_value character varying(8200),
    list_element_uuid uuid,
    PRIMARY KEY (mission_uuid, mission_attribute_uuid)
);


CREATE TABLE smart.mission_track (
    uuid uuid NOT NULL,
    mission_day_uuid uuid NOT NULL,
    sampling_unit_uuid uuid,
    track_type character varying(32) NOT NULL,
    geometry bytea NOT NULL,
    id character varying(128),
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.obs_gridded_query (
    uuid uuid NOT NULL,
    creator_uuid uuid NOT NULL,
    query_filter character varying,
    ca_filter character varying,
    query_def character varying,
    folder_uuid uuid,
    shared boolean NOT NULL,
    ca_uuid uuid NOT NULL,
    id character varying(6) NOT NULL,
    crs_definition character varying NOT NULL,
    style character varying,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.obs_observation_query (
    uuid uuid NOT NULL,
    creator_uuid uuid NOT NULL,
    query_filter character varying,
    ca_filter character varying,
    ca_uuid uuid NOT NULL,
    folder_uuid uuid,
    column_filter character varying,
    shared boolean DEFAULT false NOT NULL,
    id character varying(6) NOT NULL,
    style character varying,
    show_data_columns_only boolean,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.obs_summary_query (
    uuid uuid NOT NULL,
    creator_uuid uuid NOT NULL,
    ca_filter character varying,
    query_def character varying,
    folder_uuid uuid,
    shared boolean NOT NULL,
    ca_uuid uuid NOT NULL,
    id character varying(6) NOT NULL,
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.obs_waypoint_query (
    uuid uuid NOT NULL,
    creator_uuid uuid NOT NULL,
    query_filter character varying,
    ca_filter character varying,
    ca_uuid uuid NOT NULL,
    folder_uuid uuid,
    column_filter character varying,
    shared boolean DEFAULT false NOT NULL,
    id character varying(6) NOT NULL,
    style character varying,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.observation_attachment (
    uuid uuid NOT NULL,
    obs_uuid uuid NOT NULL,
    filename character varying(1024) NOT NULL,
    PRIMARY KEY (uuid)
);



CREATE TABLE smart.observation_options (
    ca_uuid uuid NOT NULL,
    distance_direction boolean NOT NULL,
    edit_time smallint,
    observer boolean DEFAULT false NOT NULL,
    PRIMARY KEY (ca_uuid)
);


CREATE TABLE smart.observation_query (
    uuid uuid NOT NULL,
    creator_uuid uuid NOT NULL,
    query_filter character varying,
    ca_filter character varying,
    ca_uuid uuid NOT NULL,
    folder_uuid uuid,
    column_filter character varying,
    shared boolean DEFAULT false NOT NULL,
    id character varying(6) NOT NULL,
    style character varying,
    show_data_columns_only boolean,
    PRIMARY KEY (uuid)
);



CREATE TABLE smart.patrol (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    id character varying(256) NOT NULL,
    station_uuid uuid,
    team_uuid uuid,
    objective character varying,
    patrol_type character varying(6) NOT NULL,
    is_armed boolean NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    comment character varying,
    folder_uuid uuid,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.patrol_attribute (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    keyid character varying(128) NOT NULL,
    att_type character varying(7) NOT NULL,
    is_active boolean NOT NULL,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.patrol_attribute_list (
    uuid uuid NOT NULL,
    patrol_attribute_uuid uuid NOT NULL,
    keyid character varying(128) NOT NULL,
    list_order smallint NOT NULL,
    is_active boolean NOT NULL,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.patrol_attribute_value (
    patrol_uuid uuid NOT NULL,
    patrol_attribute_uuid uuid NOT NULL,
    string_value character varying(8200),
    number_value double precision,
    list_item_uuid uuid,
    PRIMARY KEY (patrol_uuid, patrol_attribute_uuid)
);


CREATE TABLE smart.patrol_folder (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    parent_uuid uuid,
    folder_order smallint,
    PRIMARY KEY (uuid)
);


--CREATE TABLE smart.patrol_intelligence (
--    patrol_uuid uuid NOT NULL,
--    intelligence_uuid uuid NOT NULL,
--    PRIMARY KEY (patrol_uuid, intelligence_uuid)
--);


CREATE TABLE smart.patrol_leg (
    uuid uuid NOT NULL,
    patrol_uuid uuid NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    transport_uuid uuid NOT NULL,
    id character varying(50) NOT NULL,
    mandate_uuid uuid,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.patrol_leg_day (
    uuid uuid NOT NULL,
    patrol_leg_uuid uuid NOT NULL,
    patrol_day date NOT NULL,
    start_time time without time zone,
    rest_minutes integer,
    end_time time without time zone,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.patrol_leg_members (
    patrol_leg_uuid uuid NOT NULL,
    employee_uuid uuid NOT NULL,
    is_leader boolean NOT NULL,
    is_pilot boolean NOT NULL,
    PRIMARY KEY (patrol_leg_uuid, employee_uuid)
);


CREATE TABLE smart.patrol_mandate (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    is_active boolean NOT NULL,
    keyid character varying(128),
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.patrol_plan (
    patrol_uuid uuid NOT NULL,
    plan_uuid uuid NOT NULL,
    PRIMARY KEY (patrol_uuid, plan_uuid)
);

CREATE TABLE smart.patrol_query (
    uuid uuid NOT NULL,
    creator_uuid uuid NOT NULL,
    query_filter character varying,
    ca_filter character varying,
    ca_uuid uuid NOT NULL,
    folder_uuid uuid,
    column_filter character varying,
    shared boolean DEFAULT false NOT NULL,
    id character varying(6) NOT NULL,
    style character varying,
    PRIMARY KEY (uuid)
);



CREATE TABLE smart.patrol_transport (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    is_active boolean NOT NULL,
    patrol_type character varying(6) NOT NULL,
    keyid character varying(128),
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.patrol_type (
    ca_uuid uuid NOT NULL,
    patrol_type character varying(6) NOT NULL,
    is_active boolean NOT NULL,
    max_speed integer,
    PRIMARY KEY (ca_uuid, patrol_type)
);


CREATE TABLE smart.patrol_waypoint (
    wp_uuid uuid NOT NULL,
    leg_day_uuid uuid NOT NULL,
    PRIMARY KEY (wp_uuid, leg_day_uuid)
);


CREATE TABLE smart.paws_configuration(uuid uuid NOT NULL, ca_uuid uuid NOT NULL, name varchar(8192) NOT NULL, PRIMARY KEY (uuid));
CREATE TABLE smart.paws_parameter( uuid uuid NOT NULL, config_uuid uuid NOT NULL, keyid varchar(8192) NOT NULL, value varchar(8192), PRIMARY KEY (uuid));
CREATE TABLE smart.paws_query_class(uuid uuid NOT NULL, config_uuid uuid NOT NULL, query_uuid uuid NOT NULL, query_type varchar(32) NOT NULL, classification varchar(512) NOT NULL, PRIMARY KEY (uuid));
CREATE TABLE smart.paws_run(uuid uuid NOT NULL, ca_uuid uuid NOT NULL, config_uuid uuid, id varchar(256) NOT NULL, server_run_id varchar(256), run_date timestamp, package_file varchar(256), result_location varchar(256), status varchar(32) NOT NULL, status_message varchar, server_status_json varchar, train_start_year smallint, train_end_year smallint, forecast_start_year smallint, forecast_end_year smallint, container varchar(8192), paws_task_id varchar(8192), PRIMARY KEY (uuid));
CREATE TABLE smart.paws_service(uuid uuid NOT NULL, ca_uuid uuid NOT NULL UNIQUE, paws_api varchar(8192), task_api varchar(8192), paws_api_key varchar(8192), oauth_url varchar(8192), client_id varchar(8192), storage_account_url varchar(8192), PRIMARY KEY (uuid));
CREATE TABLE smart.paws_simple_class(uuid uuid NOT NULL, config_uuid uuid NOT NULL, classification varchar(512) NOT NULL, date_range varchar(512), category_hkey varchar(32672) NOT NULL, attribute_key varchar(128), list_key varchar(128), tree_hkey varchar(32672), PRIMARY KEY (uuid));


CREATE TABLE smart.plan (
    uuid uuid NOT NULL,
    id character varying(32) NOT NULL,
    start_date date NOT NULL,
    end_date date,
    type character varying(32) NOT NULL,
    description character varying(256),
    ca_uuid uuid NOT NULL,
    station_uuid uuid,
    team_uuid uuid,
    active_employees integer,
    unavailable_employees integer,
    parent_uuid uuid,
    creator_uuid uuid,
    comment character varying,
    PRIMARY KEY (uuid)
);



CREATE TABLE smart.plan_target (
    uuid uuid NOT NULL,
    name character varying(32) NOT NULL,
    description character varying(256),
    value double precision,
    op character varying(10),
    type character varying(32),
    plan_uuid uuid NOT NULL,
    category character varying(16) NOT NULL,
    completed boolean DEFAULT false NOT NULL,
    success_distance integer,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.plan_target_point (
    uuid uuid NOT NULL,
    plan_target_uuid uuid NOT NULL,
    x double precision NOT NULL,
    y double precision NOT NULL,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.qa_error (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    qa_routine_uuid uuid NOT NULL,
    data_provider_id character varying(128) NOT NULL,
    status character varying(32) NOT NULL,
    validate_date timestamp without time zone NOT NULL,
    error_id character varying(1024) NOT NULL,
    error_description character varying(32600),
    fix_message character varying(32600),
    src_identifier uuid NOT NULL,
    geometry bytea,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.qa_routine (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    routine_type_id character varying(1024) NOT NULL,
    description character varying(32600),
    auto_check boolean DEFAULT false NOT NULL,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.qa_routine_parameter (
    uuid uuid NOT NULL,
    qa_routine_uuid uuid NOT NULL,
    id character varying(256) NOT NULL,
    str_value character varying(32600),
    byte_value bytea,
    PRIMARY KEY (uuid, qa_routine_uuid)
);

CREATE TABLE smart.query_folder (
    uuid uuid NOT NULL,
    employee_uuid uuid,
    ca_uuid uuid NOT NULL,
    parent_uuid uuid,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.r_query (
    uuid uuid NOT NULL,
    script_uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    config character varying(32672),
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.r_script (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    filename character varying(2048) NOT NULL,
    creator_uuid uuid NOT NULL,
    default_parameters character varying(32672),
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.rank (
    uuid uuid NOT NULL,
    agency_uuid uuid NOT NULL,
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.report (
    uuid uuid NOT NULL,
    creator_uuid uuid NOT NULL,
    id character varying(6) NOT NULL,
    filename character varying(2048) NOT NULL,
    ca_uuid uuid NOT NULL,
    shared boolean NOT NULL,
    folder_uuid uuid,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.report_folder (
    uuid uuid NOT NULL,
    employee_uuid uuid,
    ca_uuid uuid NOT NULL,
    parent_uuid uuid,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.report_query (
    report_uuid uuid NOT NULL,
    query_uuid uuid NOT NULL,
    PRIMARY KEY (report_uuid, query_uuid)
);


CREATE TABLE smart.sampling_unit (
    uuid uuid NOT NULL,
    survey_design_uuid uuid NOT NULL,
    unit_type character varying(32) NOT NULL,
    id character varying(128),
    state character varying(8) NOT NULL,
    geometry bytea NOT NULL,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.sampling_unit_attribute (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    keyid character varying(128),
    att_type character varying(7),
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.sampling_unit_attribute_list (
    uuid uuid NOT NULL,
    sampling_unit_attribute_uuid uuid NOT NULL,
    keyid character varying(128) NOT NULL,
    list_order smallint NOT NULL,
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.sampling_unit_attribute_value (
    su_attribute_uuid uuid NOT NULL,
    su_uuid uuid NOT NULL,
    string_value character varying(8200),
    number_value double precision,
    list_element_uuid uuid,
    PRIMARY KEY (su_attribute_uuid, su_uuid)
);



CREATE TABLE smart.saved_maps (
    uuid uuid NOT NULL,
    ca_uuid uuid,
    is_default boolean NOT NULL,
    map_def text NOT NULL,
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.screen_option (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    type character varying(10),
    is_visible boolean,
    string_value character varying,
    boolean_value boolean,
    uuid_value uuid,
    resource character varying(10),
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.screen_option_uuid (
    uuid uuid NOT NULL,
    option_uuid uuid NOT NULL,
    uuid_value uuid NOT NULL,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.station (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    desc_uuid uuid,
    is_active boolean NOT NULL,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.summary_query (
    uuid uuid NOT NULL,
    creator_uuid uuid NOT NULL,
    ca_filter character varying,
    query_def character varying,
    folder_uuid uuid,
    shared boolean NOT NULL,
    ca_uuid uuid NOT NULL,
    id character varying(6) NOT NULL,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.survey (
    uuid uuid NOT NULL,
    survey_design_uuid uuid NOT NULL,
    id character varying(128) NOT NULL,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.survey_design (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    keyid character varying(128) NOT NULL,
    state character varying(16) NOT NULL,
    distance_direction boolean DEFAULT false NOT NULL,
    description character varying,
    configurable_model_uuid uuid,
    observer boolean DEFAULT false NOT NULL,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.survey_design_property (
    uuid uuid NOT NULL,
    survey_design_uuid uuid NOT NULL,
    name character varying(256) NOT NULL,
    value character varying,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.survey_design_sampling_unit (
    survey_design_uuid uuid NOT NULL,
    su_attribute_uuid uuid NOT NULL,
    PRIMARY KEY (survey_design_uuid, su_attribute_uuid)
);


CREATE TABLE smart.survey_gridded_query (
    uuid uuid NOT NULL,
    creator_uuid uuid NOT NULL,
    query_filter character varying,
    ca_filter character varying,
    ca_uuid uuid NOT NULL,
    folder_uuid uuid,
    query_def character varying,
    shared boolean NOT NULL,
    id character varying(6) NOT NULL,
    crs_definition character varying,
    surveydesign_key character varying(128),
    style character varying,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.survey_mission_query (
    uuid uuid NOT NULL,
    creator_uuid uuid NOT NULL,
    query_filter character varying,
    ca_filter character varying,
    ca_uuid uuid NOT NULL,
    folder_uuid uuid,
    column_filter character varying,
    surveydesign_key character varying(128),
    shared boolean NOT NULL,
    id character varying(6) NOT NULL,
    style character varying,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.survey_mission_track_query (
    uuid uuid NOT NULL,
    creator_uuid uuid NOT NULL,
    query_filter character varying,
    ca_filter character varying,
    ca_uuid uuid NOT NULL,
    folder_uuid uuid,
    column_filter character varying,
    surveydesign_key character varying(128),
    shared boolean NOT NULL,
    id character varying(6) NOT NULL,
    style character varying,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.survey_observation_query (
    uuid uuid NOT NULL,
    creator_uuid uuid NOT NULL,
    query_filter character varying,
    ca_filter character varying,
    ca_uuid uuid NOT NULL,
    folder_uuid uuid,
    column_filter character varying,
    surveydesign_key character varying(128),
    shared boolean NOT NULL,
    id character varying(6) NOT NULL,
    style character varying,
    show_data_columns_only boolean,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.survey_summary_query (
    uuid uuid NOT NULL,
    creator_uuid uuid NOT NULL,
    query_def character varying,
    ca_filter character varying,
    ca_uuid uuid NOT NULL,
    folder_uuid uuid,
    shared boolean NOT NULL,
    id character varying(6) NOT NULL,
    surveydesign_key character varying(128),
    PRIMARY KEY (uuid)
);



CREATE TABLE smart.survey_waypoint (
    wp_uuid uuid NOT NULL,
    mission_day_uuid uuid NOT NULL,
    sampling_unit_uuid uuid,
    mission_track_uuid uuid,
    PRIMARY KEY (wp_uuid)
);


CREATE TABLE smart.survey_waypoint_query (
    uuid uuid NOT NULL,
    creator_uuid uuid NOT NULL,
    query_filter character varying,
    ca_filter character varying,
    ca_uuid uuid NOT NULL,
    folder_uuid uuid,
    column_filter character varying,
    surveydesign_key character varying(128),
    shared boolean NOT NULL,
    id character varying(6) NOT NULL,
    style character varying,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.team (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    is_active boolean NOT NULL,
    desc_uuid uuid,
    patrol_mandate_uuid uuid,
    keyid character varying(128),
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.track (
    uuid uuid NOT NULL,
    patrol_leg_day_uuid uuid NOT NULL,
    geometry bytea NOT NULL,
    distance real NOT NULL,
    PRIMARY KEY (uuid, patrol_leg_day_uuid)
);


CREATE TABLE smart.waypoint (
    uuid uuid NOT NULL,
    ca_uuid uuid NOT NULL,
    source character varying(16) NOT NULL,
    id varchar(256) NOT NULL,
    x double precision NOT NULL,
    y double precision NOT NULL,
    datetime timestamp without time zone NOT NULL,
    direction real,
    distance real,
    wp_comment character varying,
    last_modified timestamp without time zone NOT NULL,
    last_modified_by uuid,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.waypoint_query (
    uuid uuid NOT NULL,
    creator_uuid uuid NOT NULL,
    query_filter character varying,
    ca_filter character varying,
    ca_uuid uuid NOT NULL,
    folder_uuid uuid,
    column_filter character varying,
    shared boolean DEFAULT false NOT NULL,
    id character varying(6) NOT NULL,
    style character varying,
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.wp_attachments (
    uuid uuid NOT NULL,
    wp_uuid uuid NOT NULL,
    signature_type_uuid uuid,
    filename character varying(1024) NOT NULL,
    PRIMARY KEY (uuid)
);
	
	
CREATE TABLE smart.wp_observation (
    uuid uuid NOT NULL,
    category_uuid uuid NOT NULL,
    employee_uuid uuid,
    wp_group_uuid uuid,
    PRIMARY KEY (uuid)
);

CREATE TABLE smart.wp_observation_attributes (
	uuid uuid not null,
    observation_uuid uuid NOT NULL,
    attribute_uuid uuid NOT NULL,
    list_element_uuid uuid,
    tree_node_uuid uuid,
    number_value double precision,
    string_value character varying(8200),
    PRIMARY KEY (uuid),
    unique(observation_uuid, attribute_uuid)
);

CREATE TABLE smart.wp_observation_attributes_list (
	list_element_uuid uuid not null, 
	observation_attribute_uuid uuid not null,
	primary key (list_element_uuid, observation_attribute_uuid)
);

CREATE TABLE smart.wp_observation_group (
    uuid uuid NOT NULL,
    wp_uuid uuid NOT NULL,
    PRIMARY KEY (uuid)
);


CREATE TABLE smart.smartcollect_waypoint(
  wp_uuid uuid not null,  
  source varchar(32000), 
  primary key(wp_uuid)
);

CREATE TABLE smart.smartcollect_package(
  uuid uuid not null, 
  name varchar(512), 
  ca_uuid uuid not null, 
  cm_uuid uuid, 
  ctprofile_uuid uuid,
  basemapdef varchar(32672), 
  maplayersdef varchar(32672),
  primary key (uuid));

CREATE TABLE smart.data_link(
  uuid uuid not null, 
  ca_uuid uuid not null, 
  data_type varchar(128) not null, 
  provider_id uuid not null, 
  smart_id uuid not null, 
  last_modified timestamp without time zone, 
  unique(provider_id), 
  primary key (uuid)
);


ALTER TABLE SMART.conservation_area_property ADD FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_attribute_list_item ADD CONSTRAINT asset_li_keyid_attribute_uuid_unq UNIQUE (keyid, attribute_uuid);
ALTER TABLE ONLY smart.asset_module_settings ADD CONSTRAINT asset_module_key_ca_unq UNIQUE (keyid, ca_uuid);
ALTER TABLE ONLY smart.asset_station ADD CONSTRAINT asset_sn_id_ca_unq UNIQUE (id, ca_uuid);
ALTER TABLE ONLY smart.asset_station_location ADD CONSTRAINT asset_snlc_id_ca_unq UNIQUE (id, station_uuid);
ALTER TABLE ONLY smart.asset_type ADD CONSTRAINT asset_type_ca_keyid_unq UNIQUE (keyid, ca_uuid);
ALTER TABLE ONLY smart.asset_waypoint ADD CONSTRAINT asset_waypoint_wp_uuid_asset_deployment_uuid_key UNIQUE (wp_uuid, asset_deployment_uuid);
ALTER TABLE ONLY smart.dm_attribute ADD CONSTRAINT dm_attribute_keyid_unq UNIQUE (ca_uuid, keyid) DEFERRABLE;
ALTER TABLE ONLY smart.dm_attribute_list ADD CONSTRAINT dm_attribute_list_keyid_unq UNIQUE (attribute_uuid, keyid) DEFERRABLE;
ALTER TABLE ONLY smart.dm_attribute_tree ADD CONSTRAINT dm_attribute_tree_keyid_unq UNIQUE (attribute_uuid, hkey) DEFERRABLE;
ALTER TABLE ONLY smart.dm_category ADD CONSTRAINT dm_category_keyid_unq UNIQUE (ca_uuid, hkey) DEFERRABLE;
ALTER TABLE ONLY smart.entity_attribute ADD CONSTRAINT entity_attribute_keyid_unq UNIQUE (entity_type_uuid, keyid) DEFERRABLE;
ALTER TABLE ONLY smart.entity_type ADD CONSTRAINT entity_type_keyid_unq UNIQUE (ca_uuid, keyid) DEFERRABLE;
ALTER TABLE ONLY smart.i_config_option ADD CONSTRAINT i_config_option_ca_uuid_keyid_key UNIQUE (ca_uuid, keyid);
ALTER TABLE ONLY smart.i_record_attribute_value ADD CONSTRAINT i_record_attribute_value_record_uuid_attribute_uuid_key UNIQUE (record_uuid, attribute_uuid);
ALTER TABLE ONLY smart.i_recordsource_attribute ADD CONSTRAINT i_recordsource_attribute_source_uuid_attribute_uuid_entity__key UNIQUE (source_uuid, attribute_uuid, entity_type_uuid);
ALTER TABLE ONLY smart.asset ADD CONSTRAINT id_ca_uuid_unq UNIQUE (id, ca_uuid);
--ALTER TABLE ONLY smart.intelligence_source ADD CONSTRAINT intell_source_keyid_unq UNIQUE (ca_uuid, keyid) DEFERRABLE;
ALTER TABLE ONLY smart.asset_attribute ADD CONSTRAINT keyid_ca_uuid_unq UNIQUE (keyid, ca_uuid);
ALTER TABLE ONLY smart.agency ADD CONSTRAINT keyunq UNIQUE (keyid, ca_uuid);
ALTER TABLE ONLY smart.mission_attribute ADD CONSTRAINT mission_attribute_keyid_unq UNIQUE (ca_uuid, keyid) DEFERRABLE;
ALTER TABLE ONLY smart.mission_attribute_list ADD CONSTRAINT mission_attribute_list_keyid_unq UNIQUE (mission_attribute_uuid, keyid) DEFERRABLE;
ALTER TABLE ONLY smart.patrol_mandate ADD CONSTRAINT patrol_mandate_keyid_unq UNIQUE (ca_uuid, keyid) DEFERRABLE;
ALTER TABLE ONLY smart.patrol_transport ADD CONSTRAINT patrol_transport_keyid_unq UNIQUE (ca_uuid, keyid) DEFERRABLE;
ALTER TABLE ONLY smart.paws_service ADD CONSTRAINT paws_service_ca_uuid_unq_key UNIQUE (ca_uuid);
ALTER TABLE ONLY smart.employee ADD CONSTRAINT smartuseridunq UNIQUE (ca_uuid, smartuserid);
ALTER TABLE ONLY smart.sampling_unit_attribute ADD CONSTRAINT su_attribute_keyid_unq UNIQUE (ca_uuid, keyid) DEFERRABLE;
ALTER TABLE ONLY smart.sampling_unit_attribute_list ADD CONSTRAINT su_list_attribute_keyid_unq UNIQUE (sampling_unit_attribute_uuid, keyid) DEFERRABLE;
ALTER TABLE ONLY smart.survey_design ADD CONSTRAINT survey_design_keyid_unq UNIQUE (ca_uuid, keyid) DEFERRABLE;
ALTER TABLE ONLY smart.team ADD CONSTRAINT team_keyid_unq UNIQUE (ca_uuid, keyid) DEFERRABLE;

ALTER TABLE smart.paws_configuration ADD FOREIGN KEY(ca_uuid) REFERENCES smart.conservation_area (uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE smart.paws_run ADD FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area (uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE smart.paws_service ADD FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area (uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE smart.paws_parameter ADD FOREIGN KEY (config_uuid) REFERENCES smart.paws_configuration (uuid) ON UPDATE RESTRICT ON DELETE CASCADE  DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE smart.paws_run ADD FOREIGN KEY (config_uuid) REFERENCES smart.paws_configuration (uuid) ON UPDATE RESTRICT ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE smart.paws_query_class ADD FOREIGN KEY (config_uuid) REFERENCES smart.paws_configuration (uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE smart.paws_simple_class ADD FOREIGN KEY (config_uuid) REFERENCES smart.paws_configuration (uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;


CREATE INDEX connect_change_log_ca_uuid_idx ON connect.change_log USING btree (ca_uuid);
CREATE INDEX connect_change_log_uuid_idx ON connect.change_log USING btree (uuid);

CREATE TRIGGER dq_last_modified_trigger BEFORE UPDATE ON connect.data_queue FOR EACH ROW EXECUTE PROCEDURE connect.dq_update_modified_column();
CREATE TRIGGER trg_connect_account_after AFTER INSERT ON connect.change_log FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_after();
CREATE TRIGGER trg_connect_account_before BEFORE INSERT ON connect.change_log FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_before();
CREATE TRIGGER web_roles_mgr AFTER INSERT ON connect.users FOR EACH ROW EXECUTE PROCEDURE public.manage_user_roles();
CREATE TRIGGER trg_conservation_area_property AFTER INSERT OR UPDATE OR DELETE ON smart.conservation_area_property FOR EACH ROW execute procedure connect.trg_changelog_common();
CREATE TRIGGER trg_agency AFTER INSERT OR DELETE OR UPDATE ON smart.agency FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_area_geometries AFTER INSERT OR DELETE OR UPDATE ON smart.area_geometries FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_asset AFTER INSERT OR DELETE OR UPDATE ON smart.asset FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_asset_attribute AFTER INSERT OR DELETE OR UPDATE ON smart.asset_attribute FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_asset_deployment_disruption AFTER INSERT OR UPDATE OR DELETE ON smart.asset_deployment_disruption FOR EACH ROW execute procedure connect.trg_asset_deployment_disruption();
CREATE TRIGGER trg_asset_attribute_list_item AFTER INSERT OR DELETE OR UPDATE ON smart.asset_attribute_list_item FOR EACH ROW EXECUTE PROCEDURE connect.trg_asset_attribute_list_item();
CREATE TRIGGER trg_asset_attribute_value AFTER INSERT OR DELETE OR UPDATE ON smart.asset_attribute_value FOR EACH ROW EXECUTE PROCEDURE connect.trg_asset_attribute_value();
CREATE TRIGGER trg_asset_deployment AFTER INSERT OR DELETE OR UPDATE ON smart.asset_deployment FOR EACH ROW EXECUTE PROCEDURE connect.trg_asset_deployment();
CREATE TRIGGER trg_asset_deployment_attribute_value AFTER INSERT OR DELETE OR UPDATE ON smart.asset_deployment_attribute_value FOR EACH ROW EXECUTE PROCEDURE connect.trg_asset_deployment_attribute_value();
CREATE TRIGGER trg_asset_history_record AFTER INSERT OR DELETE OR UPDATE ON smart.asset_history_record FOR EACH ROW EXECUTE PROCEDURE connect.trg_asset_history_record();
CREATE TRIGGER trg_asset_map_style AFTER INSERT OR DELETE OR UPDATE ON smart.asset_map_style FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_asset_metadata_mapping AFTER INSERT OR DELETE OR UPDATE ON smart.asset_metadata_mapping FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_asset_module_settings AFTER INSERT OR DELETE OR UPDATE ON smart.asset_module_settings FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_asset_observation_query AFTER INSERT OR DELETE OR UPDATE ON smart.asset_observation_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_asset_station AFTER INSERT OR DELETE OR UPDATE ON smart.asset_station FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_asset_station_attribute AFTER INSERT OR DELETE OR UPDATE ON smart.asset_station_attribute FOR EACH ROW EXECUTE PROCEDURE connect.trg_asset_station_attribute();
CREATE TRIGGER trg_asset_station_attribute_value AFTER INSERT OR DELETE OR UPDATE ON smart.asset_station_attribute_value FOR EACH ROW EXECUTE PROCEDURE connect.trg_asset_station_attribute_value();
CREATE TRIGGER trg_asset_station_location AFTER INSERT OR DELETE OR UPDATE ON smart.asset_station_location FOR EACH ROW EXECUTE PROCEDURE connect.trg_asset_station_location();
CREATE TRIGGER trg_asset_station_location_attribute AFTER INSERT OR DELETE OR UPDATE ON smart.asset_station_location_attribute FOR EACH ROW EXECUTE PROCEDURE connect.trg_asset_station_location_attribute();
CREATE TRIGGER trg_asset_station_location_attribute_value AFTER INSERT OR DELETE OR UPDATE ON smart.asset_station_location_attribute_value FOR EACH ROW EXECUTE PROCEDURE connect.trg_asset_station_location_attribute_value();
CREATE TRIGGER trg_asset_station_location_history AFTER INSERT OR DELETE OR UPDATE ON smart.asset_station_location_history FOR EACH ROW EXECUTE PROCEDURE connect.trg_asset_station_location_history();
CREATE TRIGGER trg_asset_summary_query AFTER INSERT OR DELETE OR UPDATE ON smart.asset_summary_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_asset_type AFTER INSERT OR DELETE OR UPDATE ON smart.asset_type FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_asset_type_attribute AFTER INSERT OR DELETE OR UPDATE ON smart.asset_type_attribute FOR EACH ROW EXECUTE PROCEDURE connect.trg_asset_type_attribute();
CREATE TRIGGER trg_asset_type_deployment_attribute AFTER INSERT OR DELETE OR UPDATE ON smart.asset_type_deployment_attribute FOR EACH ROW EXECUTE PROCEDURE connect.trg_asset_type_attribute();
CREATE TRIGGER trg_asset_waypoint AFTER INSERT OR DELETE OR UPDATE ON smart.asset_waypoint FOR EACH ROW EXECUTE PROCEDURE connect.trg_asset_waypoint();
CREATE TRIGGER trg_asset_waypoint_attachment AFTER INSERT OR DELETE OR UPDATE ON smart.asset_waypoint_attachment FOR EACH ROW EXECUTE PROCEDURE connect.trg_asset_waypoint_attachment();
CREATE TRIGGER trg_asset_waypoint_query AFTER INSERT OR DELETE OR UPDATE ON smart.asset_waypoint_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_ca_projection AFTER INSERT OR DELETE OR UPDATE ON smart.ca_projection FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_cm_attribute AFTER INSERT OR DELETE OR UPDATE ON smart.cm_attribute FOR EACH ROW EXECUTE PROCEDURE connect.trg_cm_attribute();
CREATE TRIGGER trg_cm_attribute_config AFTER INSERT OR DELETE OR UPDATE ON smart.cm_attribute_config FOR EACH ROW EXECUTE PROCEDURE connect.trg_cm_attribute_config();
CREATE TRIGGER trg_cm_attribute_list AFTER INSERT OR DELETE OR UPDATE ON smart.cm_attribute_list FOR EACH ROW EXECUTE PROCEDURE connect.trg_cm_attribute_list();
CREATE TRIGGER trg_cm_attribute_option AFTER INSERT OR DELETE OR UPDATE ON smart.cm_attribute_option FOR EACH ROW EXECUTE PROCEDURE connect.trg_cm_attribute_option();
CREATE TRIGGER trg_cm_attribute_tree_node AFTER INSERT OR DELETE OR UPDATE ON smart.cm_attribute_tree_node FOR EACH ROW EXECUTE PROCEDURE connect.trg_cm_attribute_tree_node();
CREATE TRIGGER trg_cm_ct_properties_profile AFTER INSERT OR DELETE OR UPDATE ON smart.cm_ct_properties_profile FOR EACH ROW EXECUTE PROCEDURE connect.trg_cm_ct_properties_profile();
CREATE TRIGGER trg_cm_node AFTER INSERT OR DELETE OR UPDATE ON smart.cm_node FOR EACH ROW EXECUTE PROCEDURE connect.trg_cm_node();
CREATE TRIGGER trg_compound_query AFTER INSERT OR DELETE OR UPDATE ON smart.compound_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_compound_query_layer AFTER INSERT OR DELETE OR UPDATE ON smart.compound_query_layer FOR EACH ROW EXECUTE PROCEDURE connect.trg_compound_query_layer();
CREATE TRIGGER trg_configurable_model AFTER INSERT OR DELETE OR UPDATE ON smart.configurable_model FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_connect_account AFTER INSERT OR DELETE OR UPDATE ON smart.connect_account FOR EACH ROW EXECUTE PROCEDURE connect.trg_connect_account();
CREATE TRIGGER trg_connect_alert AFTER INSERT OR DELETE OR UPDATE ON smart.connect_alert FOR EACH ROW EXECUTE PROCEDURE connect.trg_connect_alert();
CREATE TRIGGER trg_connect_ct_properties AFTER INSERT OR DELETE OR UPDATE ON smart.connect_ct_properties FOR EACH ROW EXECUTE PROCEDURE connect.trg_connect_ct_properties();
CREATE TRIGGER trg_conservation_area AFTER INSERT OR DELETE OR UPDATE ON smart.conservation_area FOR EACH ROW EXECUTE PROCEDURE connect.trg_conservation_area();
CREATE TRIGGER trg_ct_incident_link AFTER INSERT OR DELETE OR UPDATE ON smart.ct_incident_link FOR EACH ROW EXECUTE PROCEDURE connect.trg_ct_incident_link();
CREATE TRIGGER trg_ct_metadata_value AFTER INSERT OR DELETE OR UPDATE ON smart.ct_metadata_value FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_ct_metadata_value_uuid AFTER INSERT OR DELETE OR UPDATE ON smart.ct_metadata_value_uuid FOR EACH ROW EXECUTE PROCEDURE connect.trg_ct_metadata_value_uuid();
CREATE TRIGGER trg_ct_mission_link AFTER INSERT OR DELETE OR UPDATE ON smart.ct_mission_link FOR EACH ROW EXECUTE PROCEDURE connect.trg_ct_mission_link();
CREATE TRIGGER trg_ct_mission_wplink AFTER INSERT OR DELETE OR UPDATE ON smart.ct_mission_wplink FOR EACH ROW EXECUTE PROCEDURE connect.trg_ct_mission_wplink();
CREATE TRIGGER trg_ct_navigation_layer AFTER INSERT OR DELETE OR UPDATE ON smart.ct_navigation_layer FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_ct_patrol_link AFTER INSERT OR DELETE OR UPDATE ON smart.ct_patrol_link FOR EACH ROW EXECUTE PROCEDURE connect.trg_ct_patrol_link();
CREATE TRIGGER trg_ct_patrol_package AFTER INSERT OR DELETE OR UPDATE ON smart.ct_patrol_package FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_ct_patrol_wplink AFTER INSERT OR DELETE OR UPDATE ON smart.ct_patrol_wplink FOR EACH ROW EXECUTE PROCEDURE connect.trg_ct_patrol_wplink();
CREATE TRIGGER trg_ct_properties_option AFTER INSERT OR DELETE OR UPDATE ON smart.ct_properties_option FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_ct_properties_profile AFTER INSERT OR DELETE OR UPDATE ON smart.ct_properties_profile FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_ct_properties_profile_option AFTER INSERT OR DELETE OR UPDATE ON smart.ct_properties_profile_option FOR EACH ROW EXECUTE PROCEDURE connect.trg_ct_properties_profile_option();
CREATE TRIGGER trg_ct_survey_package AFTER INSERT OR DELETE OR UPDATE ON smart.ct_survey_package FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_dm_att_agg_map AFTER INSERT OR DELETE OR UPDATE ON smart.dm_att_agg_map FOR EACH ROW EXECUTE PROCEDURE connect.trg_dm_att_agg_map();
CREATE TRIGGER trg_dm_attribute AFTER INSERT OR DELETE OR UPDATE ON smart.dm_attribute FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_dm_attribute_list AFTER INSERT OR DELETE OR UPDATE ON smart.dm_attribute_list FOR EACH ROW EXECUTE PROCEDURE connect.trg_dm_attribute_list();
CREATE TRIGGER trg_dm_attribute_tree AFTER INSERT OR DELETE OR UPDATE ON smart.dm_attribute_tree FOR EACH ROW EXECUTE PROCEDURE connect.trg_dm_attribute_tree();
CREATE TRIGGER trg_dm_cat_att_map AFTER INSERT OR DELETE OR UPDATE ON smart.dm_cat_att_map FOR EACH ROW EXECUTE PROCEDURE connect.trg_dm_cat_att_map();
CREATE TRIGGER trg_dm_category AFTER INSERT OR DELETE OR UPDATE ON smart.dm_category FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_e_action AFTER INSERT OR DELETE OR UPDATE ON smart.e_action FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_e_action_parameter_value AFTER INSERT OR DELETE OR UPDATE ON smart.e_action_parameter_value FOR EACH ROW EXECUTE PROCEDURE connect.trg_e_action_parameter_value();
CREATE TRIGGER trg_e_event_action AFTER INSERT OR DELETE OR UPDATE ON smart.e_event_action FOR EACH ROW EXECUTE PROCEDURE connect.trg_e_event_action();
CREATE TRIGGER trg_e_event_filter AFTER INSERT OR DELETE OR UPDATE ON smart.e_event_filter FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_employee AFTER INSERT OR DELETE OR UPDATE ON smart.employee FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_employee_team AFTER INSERT OR DELETE OR UPDATE ON smart.employee_team FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_employee_team_member AFTER INSERT OR DELETE OR UPDATE ON smart.employee_team_member FOR EACH ROW EXECUTE PROCEDURE connect.trg_employee_team_member();
CREATE TRIGGER trg_entity AFTER INSERT OR DELETE OR UPDATE ON smart.entity FOR EACH ROW EXECUTE PROCEDURE connect.trg_entity();
CREATE TRIGGER trg_entity_attribute AFTER INSERT OR DELETE OR UPDATE ON smart.entity_attribute FOR EACH ROW EXECUTE PROCEDURE connect.trg_entity_attribute();
CREATE TRIGGER trg_entity_attribute_value AFTER INSERT OR DELETE OR UPDATE ON smart.entity_attribute_value FOR EACH ROW EXECUTE PROCEDURE connect.trg_entity_attribute_value();
CREATE TRIGGER trg_entity_gridded_query AFTER INSERT OR DELETE OR UPDATE ON smart.entity_gridded_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_entity_observation_query AFTER INSERT OR DELETE OR UPDATE ON smart.entity_observation_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_entity_summary_query AFTER INSERT OR DELETE OR UPDATE ON smart.entity_summary_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_entity_type AFTER INSERT OR DELETE OR UPDATE ON smart.entity_type FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_entity_waypoint_query AFTER INSERT OR DELETE OR UPDATE ON smart.entity_waypoint_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_gridded_query AFTER INSERT OR DELETE OR UPDATE ON smart.gridded_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_i18n_label AFTER INSERT OR DELETE OR UPDATE ON smart.i18n_label FOR EACH ROW EXECUTE PROCEDURE connect.trg_i18n_label();
CREATE TRIGGER trg_i_attachment AFTER INSERT OR DELETE OR UPDATE ON smart.i_attachment FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_i_attribute AFTER INSERT OR DELETE OR UPDATE ON smart.i_attribute FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_i_attribute_list_item AFTER INSERT OR DELETE OR UPDATE ON smart.i_attribute_list_item FOR EACH ROW EXECUTE PROCEDURE connect.trg_i_attribute_list_item();
CREATE TRIGGER trg_i_config_option AFTER INSERT OR DELETE OR UPDATE ON smart.i_config_option FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_i_diagram_entity_type_style AFTER INSERT OR DELETE OR UPDATE ON smart.i_diagram_entity_type_style FOR EACH ROW EXECUTE PROCEDURE connect.trg_i_diagram_entity_type_style();
CREATE TRIGGER trg_i_diagram_relationship_type_style AFTER INSERT OR DELETE OR UPDATE ON smart.i_diagram_relationship_type_style FOR EACH ROW EXECUTE PROCEDURE connect.trg_i_diagram_relationship_type_style();
CREATE TRIGGER trg_i_diagram_style AFTER INSERT OR DELETE OR UPDATE ON smart.i_diagram_style FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_i_entity AFTER INSERT OR DELETE OR UPDATE ON smart.i_entity FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_i_entity_attachment AFTER INSERT OR DELETE OR UPDATE ON smart.i_entity_attachment FOR EACH ROW EXECUTE PROCEDURE connect.trg_i_entity_attachment();
CREATE TRIGGER trg_i_entity_attribute_value AFTER INSERT OR DELETE OR UPDATE ON smart.i_entity_attribute_value FOR EACH ROW EXECUTE PROCEDURE connect.trg_i_entity_attribute_value();
CREATE TRIGGER trg_i_entity_location AFTER INSERT OR DELETE OR UPDATE ON smart.i_entity_location FOR EACH ROW EXECUTE PROCEDURE connect.trg_i_entity_location();
CREATE TRIGGER trg_i_entity_record AFTER INSERT OR DELETE OR UPDATE ON smart.i_entity_record FOR EACH ROW EXECUTE PROCEDURE connect.trg_i_entity_record();
CREATE TRIGGER trg_i_entity_record_query AFTER INSERT OR DELETE OR UPDATE ON smart.i_entity_record_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_i_entity_relationship AFTER INSERT OR DELETE OR UPDATE ON smart.i_entity_relationship FOR EACH ROW EXECUTE PROCEDURE connect.trg_i_entity_relationship();
CREATE TRIGGER trg_i_entity_relationship_attribute_value AFTER INSERT OR DELETE OR UPDATE ON smart.i_entity_relationship_attribute_value FOR EACH ROW EXECUTE PROCEDURE connect.trg_i_entity_relationship_attribute_value();
CREATE TRIGGER trg_i_entity_search AFTER INSERT OR DELETE OR UPDATE ON smart.i_entity_search FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_i_entity_summary_query AFTER INSERT OR DELETE OR UPDATE ON smart.i_entity_summary_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_i_entity_type AFTER INSERT OR DELETE OR UPDATE ON smart.i_entity_type FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_i_entity_type_attribute AFTER INSERT OR DELETE OR UPDATE ON smart.i_entity_type_attribute FOR EACH ROW EXECUTE PROCEDURE connect.trg_i_entity_type_attribute();
CREATE TRIGGER trg_i_entity_type_attribute_group AFTER INSERT OR DELETE OR UPDATE ON smart.i_entity_type_attribute_group FOR EACH ROW EXECUTE PROCEDURE connect.trg_i_entity_type_attribute_group();
CREATE TRIGGER trg_i_location AFTER INSERT OR DELETE OR UPDATE ON smart.i_location FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_i_observation AFTER INSERT OR DELETE OR UPDATE ON smart.i_observation FOR EACH ROW EXECUTE PROCEDURE connect.trg_i_observation();
CREATE TRIGGER trg_i_observation_attribute AFTER INSERT OR DELETE OR UPDATE ON smart.i_observation_attribute FOR EACH ROW EXECUTE PROCEDURE connect.trg_i_observation_attribute();
CREATE TRIGGER trg_i_observation_attribute_list AFTER INSERT OR DELETE OR UPDATE ON smart.i_observation_attribute_list FOR EACH ROW EXECUTE PROCEDURE connect.trg_i_observation_attribute_list();

CREATE TRIGGER trg_i_permission AFTER INSERT OR DELETE OR UPDATE ON smart.i_permission FOR EACH ROW EXECUTE PROCEDURE connect.trg_i_permission();
CREATE TRIGGER trg_i_profile_config AFTER INSERT OR DELETE OR UPDATE ON smart.i_profile_config FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_i_profile_entity_type AFTER INSERT OR DELETE OR UPDATE ON smart.i_profile_entity_type FOR EACH ROW EXECUTE PROCEDURE connect.i_profile_entity_type();
CREATE TRIGGER trg_i_profile_record_source AFTER INSERT OR DELETE OR UPDATE ON smart.i_profile_record_source FOR EACH ROW EXECUTE PROCEDURE connect.i_profile_record_source();
CREATE TRIGGER trg_i_record AFTER INSERT OR DELETE OR UPDATE ON smart.i_record FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_i_record_attachment AFTER INSERT OR DELETE OR UPDATE ON smart.i_record_attachment FOR EACH ROW EXECUTE PROCEDURE connect.trg_i_record_attachment();
CREATE TRIGGER trg_i_record_attribute_value AFTER INSERT OR DELETE OR UPDATE ON smart.i_record_attribute_value FOR EACH ROW EXECUTE PROCEDURE connect.trg_i_record_attribute_value();
CREATE TRIGGER trg_i_record_attribute_value_list AFTER INSERT OR DELETE OR UPDATE ON smart.i_record_attribute_value_list FOR EACH ROW EXECUTE PROCEDURE connect.trg_i_record_attribute_value_list();
CREATE TRIGGER trg_i_record_obs_query AFTER INSERT OR DELETE OR UPDATE ON smart.i_record_obs_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_i_record_query AFTER INSERT OR DELETE OR UPDATE ON smart.i_record_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_i_record_summary_query AFTER INSERT OR DELETE OR UPDATE ON smart.i_record_summary_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_i_recordsource AFTER INSERT OR DELETE OR UPDATE ON smart.i_recordsource FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_i_recordsource_attribute AFTER INSERT OR DELETE OR UPDATE ON smart.i_recordsource_attribute FOR EACH ROW EXECUTE PROCEDURE connect.trg_i_recordsource_attribute();
CREATE TRIGGER trg_i_relationship_group AFTER INSERT OR DELETE OR UPDATE ON smart.i_relationship_group FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_i_relationship_type AFTER INSERT OR DELETE OR UPDATE ON smart.i_relationship_type FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_i_relationship_type_attribute AFTER INSERT OR DELETE OR UPDATE ON smart.i_relationship_type_attribute FOR EACH ROW EXECUTE PROCEDURE connect.trg_i_relationship_type_attribute();
CREATE TRIGGER trg_i_working_set AFTER INSERT OR DELETE OR UPDATE ON smart.i_working_set FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_i_working_set_entity AFTER INSERT OR DELETE OR UPDATE ON smart.i_working_set_entity FOR EACH ROW EXECUTE PROCEDURE connect.trg_i_working_set_entity();
CREATE TRIGGER trg_i_working_set_query AFTER INSERT OR DELETE OR UPDATE ON smart.i_working_set_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_i_working_set_query();
CREATE TRIGGER trg_i_working_set_record AFTER INSERT OR DELETE OR UPDATE ON smart.i_working_set_record FOR EACH ROW EXECUTE PROCEDURE connect.trg_i_working_set_record();
CREATE TRIGGER trg_icon AFTER INSERT OR DELETE OR UPDATE ON smart.icon FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_iconfile AFTER INSERT OR DELETE OR UPDATE ON smart.iconfile FOR EACH ROW EXECUTE PROCEDURE connect.trg_iconfile();
CREATE TRIGGER trg_iconset AFTER INSERT OR DELETE OR UPDATE ON smart.iconset FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
--CREATE TRIGGER trg_informant AFTER INSERT OR DELETE OR UPDATE ON smart.informant FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
--CREATE TRIGGER trg_intel_record_query AFTER INSERT OR DELETE OR UPDATE ON smart.intel_record_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
--CREATE TRIGGER trg_intel_summary_query AFTER INSERT OR DELETE OR UPDATE ON smart.intel_summary_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
--CREATE TRIGGER trg_intelligence AFTER INSERT OR DELETE OR UPDATE ON smart.intelligence FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
--CREATE TRIGGER trg_intelligence_attachment AFTER INSERT OR DELETE OR UPDATE ON smart.intelligence_attachment FOR EACH ROW EXECUTE PROCEDURE connect.trg_intelligence_attachment();
--CREATE TRIGGER trg_intelligence_point AFTER INSERT OR DELETE OR UPDATE ON smart.intelligence_point FOR EACH ROW EXECUTE PROCEDURE connect.trg_intelligence_point();
--CREATE TRIGGER trg_intelligence_source AFTER INSERT OR DELETE OR UPDATE ON smart.intelligence_source FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_language AFTER INSERT OR DELETE OR UPDATE ON smart.language FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_map_styles AFTER INSERT OR DELETE OR UPDATE ON smart.map_styles FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_mission AFTER INSERT OR DELETE OR UPDATE ON smart.mission FOR EACH ROW EXECUTE PROCEDURE connect.trg_mission();
CREATE TRIGGER trg_mission_attribute AFTER INSERT OR DELETE OR UPDATE ON smart.mission_attribute FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_mission_attribute_list AFTER INSERT OR DELETE OR UPDATE ON smart.mission_attribute_list FOR EACH ROW EXECUTE PROCEDURE connect.trg_mission_attribute_list();
CREATE TRIGGER trg_mission_day AFTER INSERT OR DELETE OR UPDATE ON smart.mission_day FOR EACH ROW EXECUTE PROCEDURE connect.trg_mission_day();
CREATE TRIGGER trg_mission_member AFTER INSERT OR DELETE OR UPDATE ON smart.mission_member FOR EACH ROW EXECUTE PROCEDURE connect.trg_mission_member();
CREATE TRIGGER trg_mission_property AFTER INSERT OR DELETE OR UPDATE ON smart.mission_property FOR EACH ROW EXECUTE PROCEDURE connect.trg_mission_property();
CREATE TRIGGER trg_mission_property_value AFTER INSERT OR DELETE OR UPDATE ON smart.mission_property_value FOR EACH ROW EXECUTE PROCEDURE connect.trg_mission_property_value();
CREATE TRIGGER trg_mission_track AFTER INSERT OR DELETE OR UPDATE ON smart.mission_track FOR EACH ROW EXECUTE PROCEDURE connect.trg_mission_track();
CREATE TRIGGER trg_obs_gridded_query AFTER INSERT OR DELETE OR UPDATE ON smart.obs_gridded_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_obs_observation_query AFTER INSERT OR DELETE OR UPDATE ON smart.obs_observation_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_obs_summary_query AFTER INSERT OR DELETE OR UPDATE ON smart.obs_summary_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_obs_waypoint_query AFTER INSERT OR DELETE OR UPDATE ON smart.obs_waypoint_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_observation_attachment AFTER INSERT OR DELETE OR UPDATE ON smart.observation_attachment FOR EACH ROW EXECUTE PROCEDURE connect.trg_observation_attachment();
CREATE TRIGGER trg_observation_options AFTER INSERT OR DELETE OR UPDATE ON smart.observation_options FOR EACH ROW EXECUTE PROCEDURE connect.trg_observation_options();
CREATE TRIGGER trg_observation_query AFTER INSERT OR DELETE OR UPDATE ON smart.observation_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_patrol AFTER INSERT OR DELETE OR UPDATE ON smart.patrol FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_patrol_attribute AFTER INSERT OR DELETE OR UPDATE ON smart.patrol_attribute FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_patrol_attribute_list AFTER INSERT OR DELETE OR UPDATE ON smart.patrol_attribute_list FOR EACH ROW EXECUTE PROCEDURE connect.trg_patrol_attribute_list();
CREATE TRIGGER trg_patrol_attribute_value AFTER INSERT OR DELETE OR UPDATE ON smart.patrol_attribute_value FOR EACH ROW EXECUTE PROCEDURE connect.trg_patrol_attribute_value();
CREATE TRIGGER trg_patrol_folder AFTER INSERT OR DELETE OR UPDATE ON smart.patrol_folder FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_patrol_leg AFTER INSERT OR DELETE OR UPDATE ON smart.patrol_leg FOR EACH ROW EXECUTE PROCEDURE connect.trg_patrol_leg();
CREATE TRIGGER trg_patrol_leg_day AFTER INSERT OR DELETE OR UPDATE ON smart.patrol_leg_day FOR EACH ROW EXECUTE PROCEDURE connect.trg_patrol_leg_day();
CREATE TRIGGER trg_patrol_leg_members AFTER INSERT OR DELETE OR UPDATE ON smart.patrol_leg_members FOR EACH ROW EXECUTE PROCEDURE connect.trg_patrol_leg_members();
CREATE TRIGGER trg_patrol_mandate AFTER INSERT OR DELETE OR UPDATE ON smart.patrol_mandate FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_patrol_plan AFTER INSERT OR DELETE OR UPDATE ON smart.patrol_plan FOR EACH ROW EXECUTE PROCEDURE connect.trg_patrol_plan();
CREATE TRIGGER trg_patrol_query AFTER INSERT OR DELETE OR UPDATE ON smart.patrol_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_patrol_transport AFTER INSERT OR DELETE OR UPDATE ON smart.patrol_transport FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_patrol_type AFTER INSERT OR DELETE OR UPDATE ON smart.patrol_type FOR EACH ROW EXECUTE PROCEDURE connect.trg_patrol_type();
CREATE TRIGGER trg_patrol_waypoint AFTER INSERT OR DELETE OR UPDATE ON smart.patrol_waypoint FOR EACH ROW EXECUTE PROCEDURE connect.trg_patrol_waypoint();
CREATE TRIGGER trg_plan AFTER INSERT OR DELETE OR UPDATE ON smart.plan FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_plan_target AFTER INSERT OR DELETE OR UPDATE ON smart.plan_target FOR EACH ROW EXECUTE PROCEDURE connect.trg_plan_target();
CREATE TRIGGER trg_plan_target_point AFTER INSERT OR DELETE OR UPDATE ON smart.plan_target_point FOR EACH ROW EXECUTE PROCEDURE connect.trg_plan_target_point();
CREATE TRIGGER trg_qa_error AFTER INSERT OR DELETE OR UPDATE ON smart.qa_error FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_qa_routine AFTER INSERT OR DELETE OR UPDATE ON smart.qa_routine FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_qa_routine AFTER INSERT OR DELETE OR UPDATE ON smart.r_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_qa_routine AFTER INSERT OR DELETE OR UPDATE ON smart.r_script FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_qa_routine_parameter AFTER INSERT OR DELETE OR UPDATE ON smart.qa_routine_parameter FOR EACH ROW EXECUTE PROCEDURE connect.trg_qa_routine_parameter();
CREATE TRIGGER trg_query_folder AFTER INSERT OR DELETE OR UPDATE ON smart.query_folder FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_rank AFTER INSERT OR DELETE OR UPDATE ON smart.rank FOR EACH ROW EXECUTE PROCEDURE connect.trg_rank();
CREATE TRIGGER trg_report AFTER INSERT OR DELETE OR UPDATE ON smart.report FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_report_folder AFTER INSERT OR DELETE OR UPDATE ON smart.report_folder FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_report_query AFTER INSERT OR DELETE OR UPDATE ON smart.report_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_report_query();
CREATE TRIGGER trg_sampling_unit AFTER INSERT OR DELETE OR UPDATE ON smart.sampling_unit FOR EACH ROW EXECUTE PROCEDURE connect.trg_sampling_unit();
CREATE TRIGGER trg_sampling_unit_attribute AFTER INSERT OR DELETE OR UPDATE ON smart.sampling_unit_attribute FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_sampling_unit_attribute_list AFTER INSERT OR DELETE OR UPDATE ON smart.sampling_unit_attribute_list FOR EACH ROW EXECUTE PROCEDURE connect.trg_sampling_unit_attribute_list();
CREATE TRIGGER trg_sampling_unit_attribute_value AFTER INSERT OR DELETE OR UPDATE ON smart.sampling_unit_attribute_value FOR EACH ROW EXECUTE PROCEDURE connect.trg_sampling_unit_attribute_value();
CREATE TRIGGER trg_saved_maps AFTER INSERT OR DELETE OR UPDATE ON smart.saved_maps FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_screen_option AFTER INSERT OR DELETE OR UPDATE ON smart.screen_option FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_screen_option_uuid AFTER INSERT OR DELETE OR UPDATE ON smart.screen_option_uuid FOR EACH ROW EXECUTE PROCEDURE connect.trg_screen_option_uuid();
CREATE TRIGGER trg_station AFTER INSERT OR DELETE OR UPDATE ON smart.station FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_summary_query AFTER INSERT OR DELETE OR UPDATE ON smart.summary_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_survey AFTER INSERT OR DELETE OR UPDATE ON smart.survey FOR EACH ROW EXECUTE PROCEDURE connect.trg_survey();
CREATE TRIGGER trg_survey_design AFTER INSERT OR DELETE OR UPDATE ON smart.survey_design FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_survey_design_property AFTER INSERT OR DELETE OR UPDATE ON smart.survey_design_property FOR EACH ROW EXECUTE PROCEDURE connect.trg_survey_design_property();
CREATE TRIGGER trg_survey_design_sampling_unit AFTER INSERT OR DELETE OR UPDATE ON smart.survey_design_sampling_unit FOR EACH ROW EXECUTE PROCEDURE connect.trg_survey_design_sampling_unit();
CREATE TRIGGER trg_survey_gridded_query AFTER INSERT OR DELETE OR UPDATE ON smart.survey_gridded_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_survey_mission_query AFTER INSERT OR DELETE OR UPDATE ON smart.survey_mission_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_survey_mission_track_query AFTER INSERT OR DELETE OR UPDATE ON smart.survey_mission_track_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_survey_observation_query AFTER INSERT OR DELETE OR UPDATE ON smart.survey_observation_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_survey_summary_query AFTER INSERT OR DELETE OR UPDATE ON smart.survey_summary_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_survey_waypoint AFTER INSERT OR DELETE OR UPDATE ON smart.survey_waypoint FOR EACH ROW EXECUTE PROCEDURE connect.trg_survey_waypoint();
CREATE TRIGGER trg_survey_waypoint_query AFTER INSERT OR DELETE OR UPDATE ON smart.survey_waypoint_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_team AFTER INSERT OR DELETE OR UPDATE ON smart.team FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_track AFTER INSERT OR DELETE OR UPDATE ON smart.track FOR EACH ROW EXECUTE PROCEDURE connect.trg_track();
CREATE TRIGGER trg_waypoint AFTER INSERT OR DELETE OR UPDATE ON smart.waypoint FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_waypoint_query AFTER INSERT OR DELETE OR UPDATE ON smart.waypoint_query FOR EACH ROW EXECUTE PROCEDURE connect.trg_changelog_common();
CREATE TRIGGER trg_wp_attachments AFTER INSERT OR DELETE OR UPDATE ON smart.wp_attachments FOR EACH ROW EXECUTE PROCEDURE connect.trg_wp_attachments();
CREATE TRIGGER trg_wp_group_observation AFTER INSERT OR DELETE OR UPDATE ON smart.wp_observation_group FOR EACH ROW EXECUTE PROCEDURE connect.trg_wp_group_observation();
CREATE TRIGGER trg_wp_observation AFTER INSERT OR DELETE OR UPDATE ON smart.wp_observation FOR EACH ROW EXECUTE PROCEDURE connect.trg_wp_observation();
CREATE TRIGGER trg_wp_observation_attributes AFTER INSERT OR DELETE OR UPDATE ON smart.wp_observation_attributes FOR EACH ROW EXECUTE PROCEDURE connect.trg_wp_observation_attributes();
CREATE TRIGGER trg_wp_observation_attributes_list AFTER INSERT OR DELETE OR UPDATE ON smart.wp_observation_attributes_list FOR EACH ROW EXECUTE PROCEDURE connect.trg_wp_observation_attributes_list();
CREATE TRIGGER ct_incident_package AFTER INSERT OR UPDATE OR DELETE ON  smart.ct_incident_package FOR EACH ROW execute procedure connect.trg_changelog_common();
CREATE TRIGGER trg_signature_type AFTER INSERT OR UPDATE OR DELETE ON smart.signature_type FOR EACH ROW execute procedure connect.trg_changelog_common();			
CREATE TRIGGER trg_data_link_type AFTER INSERT OR UPDATE OR DELETE ON smart.data_link FOR EACH ROW execute procedure connect.trg_changelog_common();			


ALTER TABLE ONLY connect.alerts ADD CONSTRAINT alerts_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES connect.ca_info(ca_uuid) ON UPDATE RESTRICT ON DELETE CASCADE;
ALTER TABLE ONLY connect.alerts ADD CONSTRAINT alerts_creator_uuid_fkey FOREIGN KEY (creator_uuid) REFERENCES connect.users(uuid) ON UPDATE RESTRICT;
ALTER TABLE ONLY connect.alerts ADD CONSTRAINT alerts_type_uuid_fkey FOREIGN KEY (type_uuid) REFERENCES connect.alert_types(uuid) ON UPDATE RESTRICT;
ALTER TABLE ONLY connect.ca_plugin_version ADD CONSTRAINT ca_plugin_version_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES connect.ca_info(ca_uuid) ON UPDATE RESTRICT ON DELETE CASCADE;
ALTER TABLE ONLY connect.change_log ADD CONSTRAINT connect_changelog_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES connect.ca_info(ca_uuid) ON UPDATE RESTRICT ON DELETE CASCADE;
ALTER TABLE ONLY connect.change_log_history ADD CONSTRAINT connect_changelog_history_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES connect.ca_info(ca_uuid) ON UPDATE RESTRICT ON DELETE CASCADE;
ALTER TABLE ONLY connect.shared_links ADD CONSTRAINT connect_shared_link_owner_uuid_fk FOREIGN KEY (owner_uuid) REFERENCES connect.users(uuid) ON UPDATE RESTRICT ON DELETE CASCADE;
ALTER TABLE ONLY connect.ct_api_key ADD CONSTRAINT ct_api_key_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES connect.ca_info(ca_uuid) ON UPDATE RESTRICT ON DELETE CASCADE;
ALTER TABLE ONLY connect.ct_navigation_layer ADD CONSTRAINT ct_navigation_layer_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES connect.ca_info(ca_uuid) ON UPDATE RESTRICT ON DELETE CASCADE;
ALTER TABLE ONLY connect.ct_package ADD CONSTRAINT ct_package_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES connect.ca_info(ca_uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY connect.data_queue ADD CONSTRAINT data_queue_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES connect.ca_info(ca_uuid) ON UPDATE RESTRICT ON DELETE CASCADE;
ALTER TABLE ONLY connect.users_default_dashboard ADD CONSTRAINT default_dashboard_dashboard_fk FOREIGN KEY (dashboard_uuid) REFERENCES connect.dashboards(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY connect.users_default_dashboard ADD CONSTRAINT default_dashboard_user_fk FOREIGN KEY (user_uuid) REFERENCES connect.users(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY connect.quicklinks ADD CONSTRAINT quicklink_user_fk FOREIGN KEY (created_by_user_uuid) REFERENCES connect.users(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY connect.user_quicklinks ADD CONSTRAINT quicklink_user_fk FOREIGN KEY (user_uuid) REFERENCES connect.users(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY connect.role_actions ADD CONSTRAINT role_actions_role_id_fkey FOREIGN KEY (role_id) REFERENCES connect.roles(role_id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY connect.shared_links ADD CONSTRAINT shared_links_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES connect.ca_info(ca_uuid) ON UPDATE RESTRICT ON DELETE CASCADE;
ALTER TABLE ONLY connect.shared_links ADD CONSTRAINT shared_links_permissionuser_uuid_fkey FOREIGN KEY (permissionuser_uuid) REFERENCES connect.users(uuid) ON DELETE CASCADE;
ALTER TABLE ONLY connect.user_actions ADD CONSTRAINT user_actions_username_fkey FOREIGN KEY (username) REFERENCES connect.users(username) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY connect.user_roles ADD CONSTRAINT user_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES connect.roles(role_id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY connect.user_roles ADD CONSTRAINT user_roles_username_fkey FOREIGN KEY (username) REFERENCES connect.users(username) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY connect.user_quicklinks ADD CONSTRAINT userquicklink_quicklink_fk FOREIGN KEY (quicklink_uuid) REFERENCES connect.quicklinks(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY connect.work_item ADD CONSTRAINT work_item_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES connect.ca_info(ca_uuid) ON UPDATE RESTRICT ON DELETE CASCADE;
ALTER TABLE ONLY smart.agency ADD CONSTRAINT agency_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.area_geometries ADD CONSTRAINT area_geometries_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.asset ADD CONSTRAINT asset_asset_type_uuid_fkey FOREIGN KEY (asset_type_uuid) REFERENCES smart.asset_type(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_attribute ADD CONSTRAINT asset_attribute_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_attribute_list_item ADD CONSTRAINT asset_attribute_list_item_attribute_uuid_fkey FOREIGN KEY (attribute_uuid) REFERENCES smart.asset_attribute(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_attribute_value ADD CONSTRAINT asset_attribute_value_asset_uuid_fkey FOREIGN KEY (asset_uuid) REFERENCES smart.asset(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_attribute_value ADD CONSTRAINT asset_attribute_value_asset_uuid_fkey1 FOREIGN KEY (asset_uuid) REFERENCES smart.asset(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_attribute_value ADD CONSTRAINT asset_attribute_value_attribute_uuid_fkey FOREIGN KEY (attribute_uuid) REFERENCES smart.asset_attribute(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_attribute_value ADD CONSTRAINT asset_attribute_value_list_item_uuid_fkey FOREIGN KEY (list_item_uuid) REFERENCES smart.asset_attribute_list_item(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset ADD CONSTRAINT asset_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_deployment ADD CONSTRAINT asset_deployment_asset_uuid_fkey FOREIGN KEY (asset_uuid) REFERENCES smart.asset(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_deployment ADD CONSTRAINT asset_deployment_asset_uuid_fkey1 FOREIGN KEY (asset_uuid) REFERENCES smart.asset(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE smart.asset_deployment_disruption ADD FOREIGN KEY (asset_deployment_uuid) REFERENCES smart.asset_deployment (uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_deployment_attribute_value ADD CONSTRAINT asset_deployment_attribute_value_asset_deployment_uuid_fkey FOREIGN KEY (asset_deployment_uuid) REFERENCES smart.asset_deployment(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_deployment_attribute_value ADD CONSTRAINT asset_deployment_attribute_value_attribute_uuid_fkey FOREIGN KEY (attribute_uuid) REFERENCES smart.asset_attribute(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_deployment_attribute_value ADD CONSTRAINT asset_deployment_attribute_value_list_item_uuid_fkey FOREIGN KEY (list_item_uuid) REFERENCES smart.asset_attribute_list_item(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_deployment ADD CONSTRAINT asset_deployment_station_location_uuid_fkey FOREIGN KEY (station_location_uuid) REFERENCES smart.asset_station_location(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_history_record ADD CONSTRAINT asset_history_record_asset_uuid_fkey FOREIGN KEY (asset_uuid) REFERENCES smart.asset(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_map_style ADD CONSTRAINT asset_map_style_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_metadata_mapping ADD CONSTRAINT asset_metadata_mapping_attribute_list_item_uuid_fkey FOREIGN KEY (attribute_list_item_uuid) REFERENCES smart.dm_attribute_list(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_metadata_mapping ADD CONSTRAINT asset_metadata_mapping_attribute_tree_node_uuid_fkey FOREIGN KEY (attribute_tree_node_uuid) REFERENCES smart.dm_attribute_tree(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_metadata_mapping ADD CONSTRAINT asset_metadata_mapping_attribute_uuid_fkey FOREIGN KEY (attribute_uuid) REFERENCES smart.dm_attribute(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_metadata_mapping ADD CONSTRAINT asset_metadata_mapping_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_metadata_mapping ADD CONSTRAINT asset_metadata_mapping_category_uuid_fkey FOREIGN KEY (category_uuid) REFERENCES smart.dm_category(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_module_settings ADD CONSTRAINT asset_module_settings_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_observation_query ADD CONSTRAINT asset_observation_query_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_observation_query ADD CONSTRAINT asset_observation_query_creator_uuid_fkey FOREIGN KEY (creator_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_observation_query ADD CONSTRAINT asset_observation_query_folder_uuid_fkey FOREIGN KEY (folder_uuid) REFERENCES smart.query_folder(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_station_attribute ADD CONSTRAINT asset_station_attribute_attribute_uuid_fkey FOREIGN KEY (attribute_uuid) REFERENCES smart.asset_attribute(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_station_attribute_value ADD CONSTRAINT asset_station_attribute_value_attribute_uuid_fkey FOREIGN KEY (attribute_uuid) REFERENCES smart.asset_attribute(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_station_attribute_value ADD CONSTRAINT asset_station_attribute_value_list_item_uuid_fkey FOREIGN KEY (list_item_uuid) REFERENCES smart.asset_attribute_list_item(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_station_attribute_value ADD CONSTRAINT asset_station_attribute_value_station_uuid_fkey FOREIGN KEY (station_uuid) REFERENCES smart.asset_station(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_station ADD CONSTRAINT asset_station_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_station_location_attribute ADD CONSTRAINT asset_station_location_attribute_attribute_uuid_fkey FOREIGN KEY (attribute_uuid) REFERENCES smart.asset_attribute(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_station_location_attribute_value ADD CONSTRAINT asset_station_location_attribute_val_station_location_uuid_fkey FOREIGN KEY (station_location_uuid) REFERENCES smart.asset_station_location(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_station_location_attribute_value ADD CONSTRAINT asset_station_location_attribute_value_attribute_uuid_fkey FOREIGN KEY (attribute_uuid) REFERENCES smart.asset_attribute(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_station_location_history ADD CONSTRAINT asset_station_location_history_station_location_uuid_fkey FOREIGN KEY (station_location_uuid) REFERENCES smart.asset_station_location(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_station_location ADD CONSTRAINT asset_station_location_station_uuid_fkey FOREIGN KEY (station_uuid) REFERENCES smart.asset_station(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_summary_query ADD CONSTRAINT asset_summary_query_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_summary_query ADD CONSTRAINT asset_summary_query_creator_uuid_fkey FOREIGN KEY (creator_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_summary_query ADD CONSTRAINT asset_summary_query_folder_uuid_fkey FOREIGN KEY (folder_uuid) REFERENCES smart.query_folder(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_type_attribute ADD CONSTRAINT asset_type_attribute_asset_type_uuid_fkey FOREIGN KEY (asset_type_uuid) REFERENCES smart.asset_type(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_type_attribute ADD CONSTRAINT asset_type_attribute_attribute_uuid_fkey FOREIGN KEY (attribute_uuid) REFERENCES smart.asset_attribute(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_type ADD CONSTRAINT asset_type_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_type_deployment_attribute ADD CONSTRAINT asset_type_deployment_attribute_asset_type_uuid_fkey FOREIGN KEY (asset_type_uuid) REFERENCES smart.asset_type(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_type_deployment_attribute ADD CONSTRAINT asset_type_deployment_attribute_attribute_uuid_fkey FOREIGN KEY (attribute_uuid) REFERENCES smart.asset_attribute(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_waypoint ADD CONSTRAINT asset_waypoint_asset_deployment_uuid_fkey FOREIGN KEY (asset_deployment_uuid) REFERENCES smart.asset_deployment(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_waypoint_attachment ADD CONSTRAINT asset_waypoint_attachment_asset_waypoint_uuid_fkey FOREIGN KEY (asset_waypoint_uuid) REFERENCES smart.asset_waypoint(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_waypoint_attachment ADD CONSTRAINT asset_waypoint_attachment_wp_attachment_uuid_fkey FOREIGN KEY (wp_attachment_uuid) REFERENCES smart.wp_attachments(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_waypoint_query ADD CONSTRAINT asset_waypoint_query_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_waypoint_query ADD CONSTRAINT asset_waypoint_query_creator_uuid_fkey FOREIGN KEY (creator_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_waypoint_query ADD CONSTRAINT asset_waypoint_query_folder_uuid_fkey FOREIGN KEY (folder_uuid) REFERENCES smart.query_folder(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.asset_waypoint ADD CONSTRAINT asset_waypoint_wp_uuid_fkey FOREIGN KEY (wp_uuid) REFERENCES smart.waypoint(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.ca_projection ADD CONSTRAINT ca_projection_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.cm_attribute ADD CONSTRAINT cm_attribute_attribute_uuid_fk FOREIGN KEY (attribute_uuid) REFERENCES smart.dm_attribute(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.cm_attribute_config ADD CONSTRAINT cm_attribute_config_cm_uuid_fkey FOREIGN KEY (cm_uuid) REFERENCES smart.configurable_model(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.cm_attribute_config ADD CONSTRAINT cm_attribute_config_dm_attribute_uuid_fkey FOREIGN KEY (dm_attribute_uuid) REFERENCES smart.dm_attribute(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.cm_attribute ADD CONSTRAINT cm_attribute_config_uuid_fkey FOREIGN KEY (config_uuid) REFERENCES smart.cm_attribute_config(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.cm_attribute_list ADD CONSTRAINT cm_attribute_list_config_uuid_fkey FOREIGN KEY (config_uuid) REFERENCES smart.cm_attribute_config(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.cm_attribute_list ADD CONSTRAINT cm_attribute_list_list_element_uuid_fk FOREIGN KEY (list_element_uuid) REFERENCES smart.dm_attribute_list(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.cm_attribute ADD CONSTRAINT cm_attribute_node_uuid_fk FOREIGN KEY (node_uuid) REFERENCES smart.cm_node(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.cm_attribute_option ADD CONSTRAINT cm_attribute_option_cm_attribute_uuid_fk FOREIGN KEY (cm_attribute_uuid) REFERENCES smart.cm_attribute(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.cm_attribute_tree_node ADD CONSTRAINT cm_attribute_tree_node_config_uuid_fkey FOREIGN KEY (config_uuid) REFERENCES smart.cm_attribute_config(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.cm_attribute_tree_node ADD CONSTRAINT cm_attribute_tree_node_parent_uuid_fk FOREIGN KEY (parent_uuid) REFERENCES smart.cm_attribute_tree_node(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.cm_attribute_tree_node ADD CONSTRAINT cm_attribute_tree_node_tree_node_uuid_fk FOREIGN KEY (dm_tree_node_uuid) REFERENCES smart.dm_attribute_tree(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.cm_ct_properties_profile ADD CONSTRAINT cm_ct_properties_profile_cm_uuid_fk FOREIGN KEY (cm_uuid) REFERENCES smart.configurable_model(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.cm_ct_properties_profile ADD CONSTRAINT cm_ct_properties_profile_profile_uuid_fk FOREIGN KEY (profile_uuid) REFERENCES smart.ct_properties_profile(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.cm_node ADD CONSTRAINT cm_node_category_uuid_fk FOREIGN KEY (category_uuid) REFERENCES smart.dm_category(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.cm_node ADD CONSTRAINT cm_node_cm_uuid_fk FOREIGN KEY (cm_uuid) REFERENCES smart.configurable_model(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.connect_server_option ADD CONSTRAINT cnt_svr_opt_server_fk FOREIGN KEY (server_uuid) REFERENCES smart.connect_server(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.compound_query ADD CONSTRAINT compoundquery_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.compound_query ADD CONSTRAINT compoundquery_creator_uuid_fk FOREIGN KEY (creator_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.compound_query ADD CONSTRAINT compoundquery_folder_uuid_fk FOREIGN KEY (folder_uuid) REFERENCES smart.query_folder(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.compound_query_layer ADD CONSTRAINT compoundquerylayer_parent_uuid_fk FOREIGN KEY (compound_query_uuid) REFERENCES smart.compound_query(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.configurable_model ADD CONSTRAINT configurable_model_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.configurable_model ADD CONSTRAINT configurable_model_iconset_uuid_fkey FOREIGN KEY (iconset_uuid) REFERENCES smart.iconset(uuid) ON UPDATE RESTRICT ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.survey_design ADD CONSTRAINT configurable_model_uuid_fk FOREIGN KEY (configurable_model_uuid) REFERENCES smart.configurable_model(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.connect_alert ADD CONSTRAINT connect_alert_cm_attribute_uuid_fk FOREIGN KEY (cm_attribute_uuid) REFERENCES smart.cm_attribute(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.connect_alert ADD CONSTRAINT connect_alert_cm_uuid_fk FOREIGN KEY (cm_uuid) REFERENCES smart.configurable_model(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.connect_ct_properties ADD CONSTRAINT connect_ct_properties_cm_uuid_fk FOREIGN KEY (cm_uuid) REFERENCES smart.configurable_model(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.connect_data_queue ADD CONSTRAINT connect_data_queue_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.connect_account ADD CONSTRAINT connect_employee_uuid_fk FOREIGN KEY (employee_uuid) REFERENCES smart.employee(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.ct_incident_link ADD CONSTRAINT ct_incident_link_wp_uuid_fkey FOREIGN KEY (wp_uuid) REFERENCES smart.waypoint(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.ct_incident_link ADD CONSTRAINT ct_incident_link_wp_uuid_fkey1 FOREIGN KEY (wp_uuid) REFERENCES smart.waypoint(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.ct_metadata_value ADD CONSTRAINT ct_metadata_value_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.ct_metadata_value_uuid ADD CONSTRAINT ct_metadata_value_uuid_field_uuid_fkey FOREIGN KEY (field_uuid) REFERENCES smart.ct_metadata_value(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.ct_mission_wplink ADD CONSTRAINT ct_mission_wplink_ct_mission_link_uuid_fkey FOREIGN KEY (ct_mission_link_uuid) REFERENCES smart.ct_mission_link(ct_uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.ct_navigation_layer ADD CONSTRAINT ct_navigation_layer_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.ct_navigation_layer ADD CONSTRAINT ct_navigation_layer_last_modified_by_fkey FOREIGN KEY (last_modified_by) REFERENCES smart.employee(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.ct_patrol_package ADD CONSTRAINT ct_patrol_package_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.ct_patrol_package ADD CONSTRAINT ct_patrol_package_cm_uuid_fkey FOREIGN KEY (cm_uuid) REFERENCES smart.configurable_model(uuid) ON UPDATE RESTRICT ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.ct_patrol_package ADD CONSTRAINT ct_patrol_package_ctprofile_uuid_fkey FOREIGN KEY (ctprofile_uuid) REFERENCES smart.ct_properties_profile(uuid) ON UPDATE RESTRICT ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.ct_patrol_package ADD CONSTRAINT ct_patrol_package_incident_uuid_fkey FOREIGN KEY (incident_uuid) REFERENCES smart.configurable_model(uuid) ON UPDATE RESTRICT ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.ct_patrol_wplink ADD CONSTRAINT ct_patrol_wplink_ct_patrol_link_uuid_fkey FOREIGN KEY (ct_patrol_link_uuid) REFERENCES smart.ct_patrol_link(ct_uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.ct_properties_option ADD CONSTRAINT ct_properties_option_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.ct_properties_profile ADD CONSTRAINT ct_properties_profile_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.ct_properties_profile_option ADD CONSTRAINT ct_properties_profile_option_profile_uuid_fk FOREIGN KEY (profile_uuid) REFERENCES smart.ct_properties_profile(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.ct_survey_package ADD CONSTRAINT ct_survey_package_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.ct_survey_package ADD CONSTRAINT ct_survey_package_ctprofile_uuid_fkey FOREIGN KEY (ctprofile_uuid) REFERENCES smart.ct_properties_profile(uuid) ON UPDATE RESTRICT ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.ct_survey_package ADD CONSTRAINT ct_survey_package_incident_uuid_fkey FOREIGN KEY (incident_uuid) REFERENCES smart.configurable_model(uuid) ON UPDATE RESTRICT ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.ct_survey_package ADD CONSTRAINT ct_survey_package_sd_uuid_fkey FOREIGN KEY (sd_uuid) REFERENCES smart.survey_design(uuid) ON UPDATE RESTRICT ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.connect_data_queue_option ADD CONSTRAINT data_queue_option_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.dm_aggregation_i18n ADD CONSTRAINT dm_aggregation_i18n_fk FOREIGN KEY (name) REFERENCES smart.dm_aggregation(name) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.dm_att_agg_map ADD CONSTRAINT dm_att_agg_map_agg_name_fk FOREIGN KEY (agg_name) REFERENCES smart.dm_aggregation(name) DEFERRABLE;
ALTER TABLE ONLY smart.dm_att_agg_map ADD CONSTRAINT dm_att_agg_map_attribute_uuid_fk FOREIGN KEY (attribute_uuid) REFERENCES smart.dm_attribute(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.dm_attribute_tree ADD CONSTRAINT dm_attribut_tree_parent_uuid_fk FOREIGN KEY (parent_uuid) REFERENCES smart.dm_attribute_tree(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.dm_attribute_tree ADD CONSTRAINT dm_attribut_uuid_fk FOREIGN KEY (attribute_uuid) REFERENCES smart.dm_attribute(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.dm_attribute ADD CONSTRAINT dm_attribute_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.dm_attribute ADD CONSTRAINT dm_attribute_icon_uuid_fkey FOREIGN KEY (icon_uuid) REFERENCES smart.icon(uuid) ON UPDATE RESTRICT ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.dm_attribute_list ADD CONSTRAINT dm_attribute_list_attribute_uuid_fk FOREIGN KEY (attribute_uuid) REFERENCES smart.dm_attribute(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.dm_attribute_list ADD CONSTRAINT dm_attribute_list_icon_uuid_fkey FOREIGN KEY (icon_uuid) REFERENCES smart.icon(uuid) ON UPDATE RESTRICT ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.dm_attribute_tree ADD CONSTRAINT dm_attribute_tree_icon_uuid_fkey FOREIGN KEY (icon_uuid) REFERENCES smart.icon(uuid) ON UPDATE RESTRICT ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.dm_cat_att_map ADD CONSTRAINT dm_cat_att_map_attribute_uuid_fk FOREIGN KEY (attribute_uuid) REFERENCES smart.dm_attribute(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.dm_cat_att_map ADD CONSTRAINT dm_cat_att_map_category_uuid_fk FOREIGN KEY (category_uuid) REFERENCES smart.dm_category(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.dm_category ADD CONSTRAINT dm_category_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.dm_category ADD CONSTRAINT dm_category_icon_uuid_fkey FOREIGN KEY (icon_uuid) REFERENCES smart.icon(uuid) ON UPDATE RESTRICT ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.dm_category ADD CONSTRAINT dm_category_parent_category_uuid_fk FOREIGN KEY (parent_category_uuid) REFERENCES smart.dm_category(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.e_action ADD CONSTRAINT e_action_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.e_action_parameter_value ADD CONSTRAINT e_action_parameter_value_action_uuid_fkey FOREIGN KEY (action_uuid) REFERENCES smart.e_action(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.e_event_action ADD CONSTRAINT e_event_action_action_uuid_fkey FOREIGN KEY (action_uuid) REFERENCES smart.e_action(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.e_event_action ADD CONSTRAINT e_event_action_filter_uuid_fkey FOREIGN KEY (filter_uuid) REFERENCES smart.e_event_filter(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.e_event_filter ADD CONSTRAINT e_event_filter_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.employee ADD CONSTRAINT employee_agency_uuid_fk FOREIGN KEY (agency_uuid) REFERENCES smart.agency(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.employee ADD CONSTRAINT employee_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.employee ADD CONSTRAINT employee_rank_uuid_fk FOREIGN KEY (rank_uuid) REFERENCES smart.rank(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.employee_team ADD CONSTRAINT employee_team_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.employee_team_member ADD CONSTRAINT employee_team_member_employee_uuid_fkey FOREIGN KEY (employee_uuid) REFERENCES smart.employee(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.employee_team_member ADD CONSTRAINT employee_team_member_team_uuid_fkey FOREIGN KEY (team_uuid) REFERENCES smart.employee_team(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.entity_attribute ADD CONSTRAINT entity_attribute_dm_attribute_fk FOREIGN KEY (dm_attribute_uuid) REFERENCES smart.dm_attribute(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.entity ADD CONSTRAINT entity_attribute_list_item_uuid_fk FOREIGN KEY (attribute_list_item_uuid) REFERENCES smart.dm_attribute_list(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.entity_attribute ADD CONSTRAINT entity_attribute_type_uuid_fk FOREIGN KEY (entity_type_uuid) REFERENCES smart.entity_type(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.entity_attribute_value ADD CONSTRAINT entity_attribute_value_attribute_fk FOREIGN KEY (entity_attribute_uuid) REFERENCES smart.entity_attribute(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.entity_attribute_value ADD CONSTRAINT entity_attribute_value_entity_fk FOREIGN KEY (entity_uuid) REFERENCES smart.entity(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.entity_attribute_value ADD CONSTRAINT entity_attribute_value_listelement_fk FOREIGN KEY (list_element_uuid) REFERENCES smart.dm_attribute_list(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.entity_attribute_value ADD CONSTRAINT entity_attribute_value_treenode_fk FOREIGN KEY (tree_node_uuid) REFERENCES smart.dm_attribute_tree(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.entity_gridded_query ADD CONSTRAINT entity_gridded_query_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.entity_gridded_query ADD CONSTRAINT entity_gridded_query_creator_uuid_fk FOREIGN KEY (creator_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.entity_gridded_query ADD CONSTRAINT entity_gridded_query_folder_uuid_fk FOREIGN KEY (folder_uuid) REFERENCES smart.query_folder(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.entity_observation_query ADD CONSTRAINT entity_observation_query_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.entity_observation_query ADD CONSTRAINT entity_observation_query_folder_uuid_fk FOREIGN KEY (folder_uuid) REFERENCES smart.query_folder(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.entity_summary_query ADD CONSTRAINT entity_summary_query_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.entity_summary_query ADD CONSTRAINT entity_summary_query_creator_uuid_fk FOREIGN KEY (creator_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.entity_summary_query ADD CONSTRAINT entity_summary_query_folder_uuid_fk FOREIGN KEY (folder_uuid) REFERENCES smart.query_folder(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.entity_type ADD CONSTRAINT entity_type_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.entity_type ADD CONSTRAINT entity_type_dm_attribute_fk FOREIGN KEY (dm_attribute_uuid) REFERENCES smart.dm_attribute(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.entity ADD CONSTRAINT entity_type_uuid_fk FOREIGN KEY (entity_type_uuid) REFERENCES smart.entity_type(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.entity_waypoint_query ADD CONSTRAINT entity_waypoint_query_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.entity_waypoint_query ADD CONSTRAINT entity_waypoint_query_folder_uuid_fk FOREIGN KEY (folder_uuid) REFERENCES smart.query_folder(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.entity_observation_query ADD CONSTRAINT entityobservation_query_creator_uuid_fk FOREIGN KEY (creator_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.entity_waypoint_query ADD CONSTRAINT entitywaypoint_query_creator_uuid_fk FOREIGN KEY (creator_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.gridded_query ADD CONSTRAINT gridded_query_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.gridded_query ADD CONSTRAINT gridded_query_creator_uuid_fk FOREIGN KEY (creator_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.gridded_query ADD CONSTRAINT gridded_query_folder_uuid_fk FOREIGN KEY (folder_uuid) REFERENCES smart.query_folder(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_config_option ADD CONSTRAINT i_config_option_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_diagram_entity_type_style ADD CONSTRAINT i_diagram_entity_type_style_entity_type_uuid_fkey FOREIGN KEY (entity_type_uuid) REFERENCES smart.i_entity_type(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_diagram_entity_type_style ADD CONSTRAINT i_diagram_entity_type_style_style_uuid_fkey FOREIGN KEY (style_uuid) REFERENCES smart.i_diagram_style(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_diagram_relationship_type_style ADD CONSTRAINT i_diagram_relationship_type_style_relationship_type_uuid_fkey FOREIGN KEY (relationship_type_uuid) REFERENCES smart.i_relationship_type(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_diagram_relationship_type_style ADD CONSTRAINT i_diagram_relationship_type_style_style_uuid_fkey FOREIGN KEY (style_uuid) REFERENCES smart.i_diagram_style(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_diagram_style ADD CONSTRAINT i_diagram_style_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_entity_attribute_value ADD CONSTRAINT i_entity_attribute_value_employee_uuid_fkey FOREIGN KEY (employee_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_entity ADD CONSTRAINT i_entity_profile_uuid_fkey FOREIGN KEY (profile_uuid) REFERENCES smart.i_profile_config(uuid) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_entity ADD FOREIGN KEY (dm_list_item_uuid) REFERENCES smart.dm_attribute_list(uuid) ON UPDATE RESTRICT ON DELETE NO ACTION DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_entity_record_query ADD CONSTRAINT i_entity_record_query_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_entity_record_query ADD CONSTRAINT i_entity_record_query_created_by_fkey FOREIGN KEY (created_by) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_entity_record_query ADD CONSTRAINT i_entity_record_query_last_modified_by_fkey FOREIGN KEY (last_modified_by) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_entity_relationship_attribute_value ADD CONSTRAINT i_entity_relationship_attribute_value_employee_uuid_fkey FOREIGN KEY (employee_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_entity_summary_query ADD CONSTRAINT i_entity_summary_query_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_entity_summary_query ADD CONSTRAINT i_entity_summary_query_created_by_fkey FOREIGN KEY (created_by) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_entity_summary_query ADD CONSTRAINT i_entity_summary_query_last_modified_by_fkey FOREIGN KEY (last_modified_by) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_permission ADD CONSTRAINT i_permission_employee_uuid_fkey FOREIGN KEY (employee_uuid) REFERENCES smart.employee(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_permission ADD CONSTRAINT i_permission_profile_uuid_fkey FOREIGN KEY (profile_uuid) REFERENCES smart.i_profile_config(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_profile_config ADD CONSTRAINT i_profile_config_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_profile_entity_type ADD CONSTRAINT i_profile_entity_type_entity_type_uuid_fkey FOREIGN KEY (entity_type_uuid) REFERENCES smart.i_entity_type(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_profile_entity_type ADD CONSTRAINT i_profile_entity_type_profile_uuid_fkey FOREIGN KEY (profile_uuid) REFERENCES smart.i_profile_config(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_profile_record_source ADD CONSTRAINT i_profile_record_source_profile_uuid_fkey FOREIGN KEY (profile_uuid) REFERENCES smart.i_profile_config(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_profile_record_source ADD CONSTRAINT i_profile_record_source_record_source_uuid_fkey FOREIGN KEY (record_source_uuid) REFERENCES smart.i_recordsource(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_record ADD CONSTRAINT i_record_profile_uuid_fkey FOREIGN KEY (profile_uuid) REFERENCES smart.i_profile_config(uuid) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_record_query ADD CONSTRAINT i_record_query_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_record_query ADD CONSTRAINT i_record_query_created_by_fkey FOREIGN KEY (created_by) REFERENCES smart.employee(uuid) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_record_query ADD CONSTRAINT i_record_query_last_modified_by_fkey FOREIGN KEY (last_modified_by) REFERENCES smart.employee(uuid) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_record_summary_query ADD CONSTRAINT i_record_summary_query_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_record_summary_query ADD CONSTRAINT i_record_summary_query_created_by_fkey FOREIGN KEY (created_by) REFERENCES smart.employee(uuid) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_record_summary_query ADD CONSTRAINT i_record_summary_query_last_modified_by_fkey FOREIGN KEY (last_modified_by) REFERENCES smart.employee(uuid) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_record_attribute_value_list ADD CONSTRAINT i_recordattributelist_valueuuid_fk FOREIGN KEY (value_uuid) REFERENCES smart.i_record_attribute_value(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_relationship_type ADD CONSTRAINT i_relationship_type_src_profile_uuid_fkey FOREIGN KEY (src_profile_uuid) REFERENCES smart.i_profile_config(uuid) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_relationship_type ADD CONSTRAINT i_relationship_type_src_type_fk FOREIGN KEY (src_entity_type) REFERENCES smart.i_entity_type(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_relationship_type ADD CONSTRAINT i_relationship_type_target_profile_uuid_fkey FOREIGN KEY (target_profile_uuid) REFERENCES smart.i_profile_config(uuid) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_relationship_type ADD CONSTRAINT i_relationship_type_trg_type_fk FOREIGN KEY (target_entity_type) REFERENCES smart.i_entity_type(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_attachment ADD CONSTRAINT iattachment_cauuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_attachment ADD CONSTRAINT iattachment_createdby_fk FOREIGN KEY (created_by) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_attribute ADD CONSTRAINT iattribute_cauuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_entity_type_attribute ADD CONSTRAINT iattributegroupuuid_fk FOREIGN KEY (attribute_group_uuid) REFERENCES smart.i_entity_type_attribute_group(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_attribute_list_item ADD CONSTRAINT iattributelist_attribute_fk FOREIGN KEY (attribute_uuid) REFERENCES smart.i_attribute(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.icon ADD CONSTRAINT icon_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.iconfile ADD CONSTRAINT iconfile_icon_uuid_fkey FOREIGN KEY (icon_uuid) REFERENCES smart.icon(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.iconfile ADD CONSTRAINT iconfile_iconset_uuid_fkey FOREIGN KEY (iconset_uuid) REFERENCES smart.iconset(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.iconset ADD CONSTRAINT iconset_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_entity ADD CONSTRAINT ientity_cauuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_entity ADD CONSTRAINT ientity_createdby_fk FOREIGN KEY (created_by) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_entity ADD CONSTRAINT ientity_entitytype_fk FOREIGN KEY (entity_type_uuid) REFERENCES smart.i_entity_type(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_entity ADD CONSTRAINT ientity_lastmodifiedby_fk FOREIGN KEY (last_modified_by) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_entity_attachment ADD CONSTRAINT ientityattachment_attchment_fk FOREIGN KEY (attachment_uuid) REFERENCES smart.i_attachment(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_entity_attachment ADD CONSTRAINT ientityattachment_entity_fk FOREIGN KEY (entity_uuid) REFERENCES smart.i_entity(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_entity_attribute_value ADD CONSTRAINT ientityattribute_attribute_fk FOREIGN KEY (attribute_uuid) REFERENCES smart.i_attribute(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_entity_attribute_value ADD CONSTRAINT ientityattributevalue_entity_fk FOREIGN KEY (entity_uuid) REFERENCES smart.i_entity(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_entity_attribute_value ADD CONSTRAINT ientityattributevalue_list_fk FOREIGN KEY (list_item_uuid) REFERENCES smart.i_attribute_list_item(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_entity_location ADD CONSTRAINT ientitylocation_entity_fk FOREIGN KEY (entity_uuid) REFERENCES smart.i_entity(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_entity_location ADD CONSTRAINT ientitylocation_location_fk FOREIGN KEY (location_uuid) REFERENCES smart.i_location(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_entity_record ADD CONSTRAINT ientityrecord_entity_fk FOREIGN KEY (entity_uuid) REFERENCES smart.i_entity(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_entity_record ADD CONSTRAINT ientityrecord_record_fk FOREIGN KEY (record_uuid) REFERENCES smart.i_record(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_entity_relationship ADD CONSTRAINT ientityrelationship_srcentity_fk FOREIGN KEY (src_entity_uuid) REFERENCES smart.i_entity(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_entity_relationship ADD CONSTRAINT ientityrelationship_targetentity_fk FOREIGN KEY (target_entity_uuid) REFERENCES smart.i_entity(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_entity_relationship ADD CONSTRAINT ientityrelationship_type_fk FOREIGN KEY (relationship_type_uuid) REFERENCES smart.i_relationship_type(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_entity_relationship_attribute_value ADD CONSTRAINT ientityrelationshipattribute_attribute_fk FOREIGN KEY (attribute_uuid) REFERENCES smart.i_attribute(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_entity_relationship_attribute_value ADD CONSTRAINT ientityrelationshipattribute_entityrelationship_fk FOREIGN KEY (entity_relationship_uuid) REFERENCES smart.i_entity_relationship(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_entity_relationship_attribute_value ADD CONSTRAINT ientityrelationshipattribute_list_fk FOREIGN KEY (list_item_uuid) REFERENCES smart.i_attribute_list_item(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_entity_search ADD CONSTRAINT ientitysearch_cauuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_entity_type ADD CONSTRAINT ientitytype_cauuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_entity_type ADD CONSTRAINT ientitytype_idattributeuuid_fk FOREIGN KEY (id_attribute_uuid) REFERENCES smart.i_attribute(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_entity_type ADD FOREIGN KEY (dm_attribute_uuid) REFERENCES smart.dm_attribute(uuid) ON UPDATE RESTRICT ON DELETE NO ACTION DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.i_entity_type_attribute ADD CONSTRAINT ientitytypeattribute_attribute_fk FOREIGN KEY (attribute_uuid) REFERENCES smart.i_attribute(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_entity_type_attribute ADD CONSTRAINT ientitytypeattribute_entitytype_fk FOREIGN KEY (entity_type_uuid) REFERENCES smart.i_entity_type(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_entity_type_attribute_group ADD CONSTRAINT ientitytypeattributegroupentitytypeuuid_fk FOREIGN KEY (entity_type_uuid) REFERENCES smart.i_entity_type(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_location ADD CONSTRAINT ilocation_cauuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
--ALTER TABLE ONLY smart.informant ADD CONSTRAINT informant_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
--ALTER TABLE ONLY smart.intel_record_query ADD CONSTRAINT intel_record_query_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
--ALTER TABLE ONLY smart.intel_record_query ADD CONSTRAINT intel_record_query_creator_uuid_fk FOREIGN KEY (creator_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
--ALTER TABLE ONLY smart.intel_record_query ADD CONSTRAINT intel_record_query_folder_uuid_fk FOREIGN KEY (folder_uuid) REFERENCES smart.query_folder(uuid) ON DELETE CASCADE DEFERRABLE;
--ALTER TABLE ONLY smart.intel_summary_query ADD CONSTRAINT intel_summary_query_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
--ALTER TABLE ONLY smart.intel_summary_query ADD CONSTRAINT intel_summary_query_creator_uuid_fk FOREIGN KEY (creator_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
--ALTER TABLE ONLY smart.intel_summary_query ADD CONSTRAINT intel_summary_query_folder_uuid_fk FOREIGN KEY (folder_uuid) REFERENCES smart.query_folder(uuid) ON DELETE CASCADE DEFERRABLE;
--ALTER TABLE ONLY smart.intelligence_attachment ADD CONSTRAINT intelligence_attachment_intelligence_uuid_fk FOREIGN KEY (intelligence_uuid) REFERENCES smart.intelligence(uuid) ON DELETE CASCADE DEFERRABLE;
--ALTER TABLE ONLY smart.intelligence ADD CONSTRAINT intelligence_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
--ALTER TABLE ONLY smart.intelligence ADD CONSTRAINT intelligence_creator_uuid_fk FOREIGN KEY (creator_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
--ALTER TABLE ONLY smart.intelligence ADD CONSTRAINT intelligence_informant_uuid_fk FOREIGN KEY (informant_uuid) REFERENCES smart.informant(uuid) ON DELETE CASCADE DEFERRABLE;
--ALTER TABLE ONLY smart.intelligence ADD CONSTRAINT intelligence_patrol_uuid_fk FOREIGN KEY (patrol_uuid) REFERENCES smart.patrol(uuid) ON DELETE CASCADE DEFERRABLE;
--ALTER TABLE ONLY smart.intelligence_point ADD CONSTRAINT intelligence_point_intelligence_uuid_fk FOREIGN KEY (intelligence_uuid) REFERENCES smart.intelligence(uuid) ON DELETE CASCADE DEFERRABLE;
--ALTER TABLE ONLY smart.intelligence_source ADD CONSTRAINT intelligence_source_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
--ALTER TABLE ONLY smart.intelligence ADD CONSTRAINT intelligence_source_uuid_fk FOREIGN KEY (source_uuid) REFERENCES smart.intelligence_source(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_observation ADD CONSTRAINT iobservation_category_fk FOREIGN KEY (category_uuid) REFERENCES smart.dm_category(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_observation ADD CONSTRAINT iobservation_location_fk FOREIGN KEY (location_uuid) REFERENCES smart.i_location(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_observation_attribute ADD CONSTRAINT iobservationattribute_attributeuuid_fk FOREIGN KEY (attribute_uuid) REFERENCES smart.dm_attribute(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_observation_attribute ADD CONSTRAINT iobservationattribute_list_fk FOREIGN KEY (list_element_uuid) REFERENCES smart.dm_attribute_list(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_observation_attribute ADD CONSTRAINT iobservationattribute_observation_fk FOREIGN KEY (observation_uuid) REFERENCES smart.i_observation(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_observation_attribute ADD CONSTRAINT iobservationattribute_tree_fk FOREIGN KEY (tree_node_uuid) REFERENCES smart.dm_attribute_tree(uuid) ON DELETE CASCADE DEFERRABLE;
alter table smart.i_observation_attribute_list ADD FOREIGN KEY (observation_attribute_uuid) REFERENCES smart.i_observation_attribute(uuid) on DELETE CASCADE ON UPDATE RESTRICT DEFERRABLE INITIALLY DEFERRED;
alter table smart.i_observation_attribute_list ADD FOREIGN KEY (list_element_uuid) REFERENCES smart.dm_attribute_list(uuid) ON DELETE CASCADE ON UPDATE RESTRICT DEFERRABLE INITIALLY DEFERRED;
	
ALTER TABLE ONLY smart.i_record ADD CONSTRAINT irecord_cauuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_record ADD CONSTRAINT irecord_createdby_fk FOREIGN KEY (created_by) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_record ADD CONSTRAINT irecord_modifiedby_fk FOREIGN KEY (last_modified_by) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_record ADD CONSTRAINT irecord_sourceuuid_fk FOREIGN KEY (source_uuid) REFERENCES smart.i_recordsource(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_record_attachment ADD CONSTRAINT irecordattachment_attchment_fk FOREIGN KEY (attachment_uuid) REFERENCES smart.i_attachment(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_record_attachment ADD CONSTRAINT irecordattachment_record_fk FOREIGN KEY (record_uuid) REFERENCES smart.i_record(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_record_attribute_value ADD CONSTRAINT irecordattvalue_attributeuuid_fk FOREIGN KEY (attribute_uuid) REFERENCES smart.i_recordsource_attribute(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_record_attribute_value ADD CONSTRAINT irecordattvalue_sourceuuid_fk FOREIGN KEY (record_uuid) REFERENCES smart.i_record(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_record_obs_query ADD CONSTRAINT irecordquery_cauuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_record_obs_query ADD CONSTRAINT irecordquery_createdby_fk FOREIGN KEY (created_by) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_record_obs_query ADD CONSTRAINT irecordquery_modifiedby_fk FOREIGN KEY (last_modified_by) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_recordsource ADD CONSTRAINT irecordsource_cauuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_recordsource_attribute ADD CONSTRAINT irecordsourceattribute_attributeuuid_fk FOREIGN KEY (attribute_uuid) REFERENCES smart.i_attribute(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_recordsource_attribute ADD CONSTRAINT irecordsourceattribute_entitytypeuuid_fk FOREIGN KEY (entity_type_uuid) REFERENCES smart.i_entity_type(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_recordsource_attribute ADD CONSTRAINT irecordsourceattribute_sourceuuid_fk FOREIGN KEY (source_uuid) REFERENCES smart.i_recordsource(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_relationship_type_attribute ADD CONSTRAINT irelationshipattribute_attribute_fk FOREIGN KEY (attribute_uuid) REFERENCES smart.i_attribute(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_relationship_type_attribute ADD CONSTRAINT irelationshipattribute_type_fk FOREIGN KEY (relationship_type_uuid) REFERENCES smart.i_relationship_type(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_relationship_type ADD CONSTRAINT irelationshiptype_cauuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_relationship_type ADD CONSTRAINT irelationshiptype_group_fk FOREIGN KEY (relationship_group_uuid) REFERENCES smart.i_relationship_group(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_working_set_entity ADD CONSTRAINT iworkginsetentity_workingset_fk FOREIGN KEY (working_set_uuid) REFERENCES smart.i_working_set(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_working_set ADD CONSTRAINT iworkingset_cauuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_working_set ADD CONSTRAINT iworkingset_createdby_fk FOREIGN KEY (created_by) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_working_set ADD CONSTRAINT iworkingset_lastmodifiedby_fk FOREIGN KEY (last_modified_by) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_working_set_entity ADD CONSTRAINT iworkingsetentity_entity_fk FOREIGN KEY (entity_uuid) REFERENCES smart.i_entity(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_working_set_query ADD CONSTRAINT iworkingsetquery_workingset_fk FOREIGN KEY (working_set_uuid) REFERENCES smart.i_working_set(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_working_set_record ADD CONSTRAINT iworkingsetrecord_record_fk FOREIGN KEY (record_uuid) REFERENCES smart.i_record(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_working_set_record ADD CONSTRAINT iworkingsetrecord_workingset_fk FOREIGN KEY (working_set_uuid) REFERENCES smart.i_working_set(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.language ADD CONSTRAINT language_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i18n_label ADD CONSTRAINT languages_ca_uuid_fk FOREIGN KEY (language_uuid) REFERENCES smart.language(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.patrol_leg_members ADD CONSTRAINT leg_members_employee_uuid_fk FOREIGN KEY (employee_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.patrol_leg_members ADD CONSTRAINT leg_members_patrol_leg_uuid_fk FOREIGN KEY (patrol_leg_uuid) REFERENCES smart.patrol_leg(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_location ADD CONSTRAINT location_recorduuid_fk FOREIGN KEY (record_uuid) REFERENCES smart.i_record(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.patrol_leg ADD CONSTRAINT mandate_uuid_fk FOREIGN KEY (mandate_uuid) REFERENCES smart.patrol_mandate(uuid) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.map_styles ADD CONSTRAINT mapstyle_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.mission_attribute ADD CONSTRAINT mission_att_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.mission_attribute_list ADD CONSTRAINT mission_att_list_mission_att_uuid_fk FOREIGN KEY (mission_attribute_uuid) REFERENCES smart.mission_attribute(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.mission_day ADD CONSTRAINT mission_day_mission_uuid_fk FOREIGN KEY (mission_uuid) REFERENCES smart.mission(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.ct_mission_link ADD CONSTRAINT mission_link_su_uuid_fk FOREIGN KEY (su_uuid) REFERENCES smart.sampling_unit(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.mission_member ADD CONSTRAINT mission_member_mission_uuid_fk FOREIGN KEY (mission_uuid) REFERENCES smart.mission(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.mission_property ADD CONSTRAINT mission_prop_mission_att_uuid_fk FOREIGN KEY (mission_attribute_uuid) REFERENCES smart.mission_attribute(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.mission_property ADD CONSTRAINT mission_prop_survey_dsg_uuid FOREIGN KEY (survey_design_uuid) REFERENCES smart.survey_design(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.mission_property_value ADD CONSTRAINT mission_prop_value_listelement_uuid FOREIGN KEY (list_element_uuid) REFERENCES smart.mission_attribute_list(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.mission_property_value ADD CONSTRAINT mission_prop_value_mission_att_uuid FOREIGN KEY (mission_attribute_uuid) REFERENCES smart.mission_attribute(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.mission_property_value ADD CONSTRAINT mission_prop_value_mission_uuid FOREIGN KEY (mission_uuid) REFERENCES smart.mission(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.mission ADD CONSTRAINT mission_survey_uuid FOREIGN KEY (survey_uuid) REFERENCES smart.survey(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.mission_track ADD CONSTRAINT mission_track FOREIGN KEY (sampling_unit_uuid) REFERENCES smart.sampling_unit(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.mission_track ADD CONSTRAINT mission_track_missionday_uuid FOREIGN KEY (mission_day_uuid) REFERENCES smart.mission_day(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.ct_mission_link ADD CONSTRAINT mission_uuid_fk FOREIGN KEY (mission_uuid) REFERENCES smart.mission(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.wp_observation_attributes ADD CONSTRAINT obs_attribute_obs_uuid_fk FOREIGN KEY (observation_uuid) REFERENCES smart.wp_observation(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.wp_observation ADD CONSTRAINT obs_employee_uuid_fk FOREIGN KEY (employee_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.obs_gridded_query ADD CONSTRAINT obs_gridded_query_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.obs_gridded_query ADD CONSTRAINT obs_gridded_query_creator_uuid_fk FOREIGN KEY (creator_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.obs_gridded_query ADD CONSTRAINT obs_gridded_query_folder_uuid_fk FOREIGN KEY (folder_uuid) REFERENCES smart.query_folder(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.obs_observation_query ADD CONSTRAINT obs_observation_query_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.obs_observation_query ADD CONSTRAINT obs_observation_query_folder_uuid_fk FOREIGN KEY (folder_uuid) REFERENCES smart.query_folder(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.obs_summary_query ADD CONSTRAINT obs_summary_query_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.obs_summary_query ADD CONSTRAINT obs_summary_query_creator_uuid_fk FOREIGN KEY (creator_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.obs_summary_query ADD CONSTRAINT obs_summary_query_folder_uuid_fk FOREIGN KEY (folder_uuid) REFERENCES smart.query_folder(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.obs_waypoint_query ADD CONSTRAINT obs_waypoint_query_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.obs_waypoint_query ADD CONSTRAINT obs_waypoint_query_folder_uuid_fk FOREIGN KEY (folder_uuid) REFERENCES smart.query_folder(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.observation_attachment ADD CONSTRAINT observation_attachment_obs_uuid_fk FOREIGN KEY (obs_uuid) REFERENCES smart.wp_observation(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.wp_observation_attributes ADD CONSTRAINT observation_attribute_att_list_uuid_fk FOREIGN KEY (list_element_uuid) REFERENCES smart.dm_attribute_list(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.wp_observation_attributes ADD CONSTRAINT observation_attribute_att_tree_uuid_fk FOREIGN KEY (tree_node_uuid) REFERENCES smart.dm_attribute_tree(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.wp_observation_attributes ADD CONSTRAINT observation_attribute_att_uuid_fk FOREIGN KEY (attribute_uuid) REFERENCES smart.dm_attribute(uuid) ON DELETE CASCADE DEFERRABLE;
alter table smart.wp_observation_attributes_list ADD FOREIGN KEY (observation_attribute_uuid) REFERENCES smart.wp_observation_attributes(uuid) on DELETE CASCADE ON UPDATE RESTRICT DEFERRABLE INITIALLY DEFERRED;
alter table smart.wp_observation_attributes_list ADD FOREIGN KEY (list_element_uuid) REFERENCES smart.dm_attribute_list(uuid) ON DELETE CASCADE ON UPDATE RESTRICT DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.wp_observation ADD CONSTRAINT observation_category_uuid_fk FOREIGN KEY (category_uuid) REFERENCES smart.dm_category(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.observation_query ADD CONSTRAINT observation_query_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.observation_query ADD CONSTRAINT observation_query_creator_uuid_fk FOREIGN KEY (creator_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.observation_query ADD CONSTRAINT observation_query_folder_uuid_fk FOREIGN KEY (folder_uuid) REFERENCES smart.query_folder(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.obs_observation_query ADD CONSTRAINT obsobservation_query_creator_uuid_fk FOREIGN KEY (creator_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.obs_waypoint_query ADD CONSTRAINT obswaypoint_query_creator_uuid_fk FOREIGN KEY (creator_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.patrol_attribute ADD CONSTRAINT patrol_attribute_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.patrol_attribute_list ADD CONSTRAINT patrol_attribute_list_patrol_attribute_uuid_fkey FOREIGN KEY (patrol_attribute_uuid) REFERENCES smart.patrol_attribute(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.patrol_attribute_value ADD CONSTRAINT patrol_attribute_value_list_item_uuid_fkey FOREIGN KEY (list_item_uuid) REFERENCES smart.patrol_attribute_list(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.patrol_attribute_value ADD CONSTRAINT patrol_attribute_value_patrol_attribute_uuid_fkey FOREIGN KEY (patrol_attribute_uuid) REFERENCES smart.patrol_attribute(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.patrol_attribute_value ADD CONSTRAINT patrol_attribute_value_patrol_uuid_fkey FOREIGN KEY (patrol_uuid) REFERENCES smart.patrol(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.patrol ADD CONSTRAINT patrol_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.patrol_folder ADD CONSTRAINT patrol_folder_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.patrol_folder ADD CONSTRAINT patrol_folder_parent_uuid_fkey FOREIGN KEY (parent_uuid) REFERENCES smart.patrol_folder(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.patrol ADD CONSTRAINT patrol_folder_uuid_fkey FOREIGN KEY (folder_uuid) REFERENCES smart.patrol_folder(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
--ALTER TABLE ONLY smart.patrol_intelligence ADD CONSTRAINT patrol_intelligence_intelligence_uuid_fk FOREIGN KEY (intelligence_uuid) REFERENCES smart.intelligence(uuid) ON DELETE CASCADE DEFERRABLE;
--ALTER TABLE ONLY smart.patrol_intelligence ADD CONSTRAINT patrol_intelligence_patrol_uuid_fk FOREIGN KEY (patrol_uuid) REFERENCES smart.patrol(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.ct_patrol_link ADD CONSTRAINT patrol_key_uuid_fk FOREIGN KEY (patrol_leg_uuid) REFERENCES smart.patrol_leg(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.patrol_leg_day ADD CONSTRAINT patrol_leg_day_leg_uuid_fk FOREIGN KEY (patrol_leg_uuid) REFERENCES smart.patrol_leg(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.patrol_leg ADD CONSTRAINT patrol_leg_patrol_uuid_fk FOREIGN KEY (patrol_uuid) REFERENCES smart.patrol(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.patrol_leg ADD CONSTRAINT patrol_leg_transport_uuid_fk FOREIGN KEY (transport_uuid) REFERENCES smart.patrol_transport(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.patrol_mandate ADD CONSTRAINT patrol_mandate_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.observation_options ADD CONSTRAINT patrol_options_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.patrol_plan ADD CONSTRAINT patrol_plan_patrol_uuid_fk FOREIGN KEY (patrol_uuid) REFERENCES smart.patrol(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.patrol_plan ADD CONSTRAINT patrol_plan_plan_uuid_fk FOREIGN KEY (plan_uuid) REFERENCES smart.plan(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.patrol_query ADD CONSTRAINT patrol_query_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.patrol_query ADD CONSTRAINT patrol_query_creator_uuid_fk FOREIGN KEY (creator_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.patrol_query ADD CONSTRAINT patrol_query_folder_uuid_fk FOREIGN KEY (folder_uuid) REFERENCES smart.query_folder(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.patrol ADD CONSTRAINT patrol_station_uuid_fk FOREIGN KEY (station_uuid) REFERENCES smart.station(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.patrol ADD CONSTRAINT patrol_team_uuid_fk FOREIGN KEY (team_uuid) REFERENCES smart.team(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.patrol_transport ADD CONSTRAINT patrol_transport_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.patrol_type ADD CONSTRAINT patrol_type_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.patrol_waypoint ADD CONSTRAINT patrol_waypoint_leg_day_uuid_fk FOREIGN KEY (leg_day_uuid) REFERENCES smart.patrol_leg_day(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.patrol_waypoint ADD CONSTRAINT patrol_waypoint_wp_uuid_fk FOREIGN KEY (wp_uuid) REFERENCES smart.waypoint(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.plan ADD CONSTRAINT plan_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.plan ADD CONSTRAINT plan_creator_uuid_fk FOREIGN KEY (creator_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.plan ADD CONSTRAINT plan_parent_uuid_fk FOREIGN KEY (parent_uuid) REFERENCES smart.plan(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.plan ADD CONSTRAINT plan_station_uuid_fk FOREIGN KEY (station_uuid) REFERENCES smart.station(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.plan_target_point ADD CONSTRAINT plan_target_point_plan_target_uuid_fk FOREIGN KEY (plan_target_uuid) REFERENCES smart.plan_target(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.plan ADD CONSTRAINT plan_team_uuid_fk FOREIGN KEY (team_uuid) REFERENCES smart.team(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.qa_error ADD CONSTRAINT qa_error_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.qa_error ADD CONSTRAINT qa_error_qa_routine_uuid_fkey FOREIGN KEY (qa_routine_uuid) REFERENCES smart.qa_routine(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.qa_routine ADD CONSTRAINT qa_routine_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.qa_routine_parameter ADD CONSTRAINT qa_routine_parameter_qa_routine_uuid_fkey FOREIGN KEY (qa_routine_uuid) REFERENCES smart.qa_routine(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.query_folder ADD CONSTRAINT query_folder_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.query_folder ADD CONSTRAINT query_folder_employee_uuid_fk FOREIGN KEY (employee_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.query_folder ADD CONSTRAINT query_folder_parent_uuid_fk FOREIGN KEY (parent_uuid) REFERENCES smart.query_folder(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.r_query ADD CONSTRAINT r_query_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.r_query ADD CONSTRAINT r_query_script_uuid_fkey FOREIGN KEY (script_uuid) REFERENCES smart.r_script(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.r_script ADD CONSTRAINT r_script_ca_uuid_fkey FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.r_script ADD CONSTRAINT r_script_creator_uuid_fkey FOREIGN KEY (creator_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.rank ADD CONSTRAINT rank_agency_uuid_fk FOREIGN KEY (agency_uuid) REFERENCES smart.agency(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.i_relationship_group ADD CONSTRAINT relationshipgroup_cauuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.report ADD CONSTRAINT report_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.report ADD CONSTRAINT report_creator_uuid_fk FOREIGN KEY (creator_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.report_folder ADD CONSTRAINT report_employee_uuid_fk FOREIGN KEY (employee_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.report_folder ADD CONSTRAINT report_folder_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.report_folder ADD CONSTRAINT report_folder_parent_uuid_fk FOREIGN KEY (parent_uuid) REFERENCES smart.report_folder(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.report ADD CONSTRAINT report_folder_uuid_fk FOREIGN KEY (folder_uuid) REFERENCES smart.report_folder(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.report_query ADD CONSTRAINT report_query_report_uuid_fk FOREIGN KEY (report_uuid) REFERENCES smart.report(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.sampling_unit ADD CONSTRAINT sampling_unit_survey_dsg_uuid FOREIGN KEY (survey_design_uuid) REFERENCES smart.survey_design(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.saved_maps ADD CONSTRAINT saved_maps_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.screen_option ADD CONSTRAINT screen_option_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.screen_option_uuid ADD CONSTRAINT screen_option_uuid_option_uuid_fk FOREIGN KEY (option_uuid) REFERENCES smart.screen_option(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.survey_design ADD CONSTRAINT sd_cal_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.survey_design_sampling_unit ADD CONSTRAINT sd_su_su_attribute_uuid FOREIGN KEY (su_attribute_uuid) REFERENCES smart.sampling_unit_attribute(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.survey_design_sampling_unit ADD CONSTRAINT sd_su_survey_design_uuid FOREIGN KEY (survey_design_uuid) REFERENCES smart.survey_design(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.connect_server ADD CONSTRAINT server_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.station ADD CONSTRAINT station_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.sampling_unit_attribute_list ADD CONSTRAINT su_att_list_mission_att_uuid_fk FOREIGN KEY (sampling_unit_attribute_uuid) REFERENCES smart.sampling_unit_attribute(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.sampling_unit_attribute ADD CONSTRAINT su_attribute_ca_uuid FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.sampling_unit_attribute_value ADD CONSTRAINT su_su_attribute_uuid FOREIGN KEY (su_attribute_uuid) REFERENCES smart.sampling_unit_attribute(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.sampling_unit_attribute_value ADD CONSTRAINT su_su_list_element_uuid FOREIGN KEY (list_element_uuid) REFERENCES smart.sampling_unit_attribute_list(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.sampling_unit_attribute_value ADD CONSTRAINT su_su_uuid FOREIGN KEY (su_uuid) REFERENCES smart.sampling_unit(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.summary_query ADD CONSTRAINT summary_query_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.summary_query ADD CONSTRAINT summary_query_creator_uuid_fk FOREIGN KEY (creator_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.summary_query ADD CONSTRAINT summary_query_folder_uuid_fk FOREIGN KEY (folder_uuid) REFERENCES smart.query_folder(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.survey_design_property ADD CONSTRAINT survey_dsg_prop_survey_dsg_uuid FOREIGN KEY (survey_design_uuid) REFERENCES smart.survey_design(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.survey ADD CONSTRAINT survey_survey_dsg_uuid FOREIGN KEY (survey_design_uuid) REFERENCES smart.survey_design(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.survey_waypoint ADD CONSTRAINT survey_wp_mission_trk_uuid FOREIGN KEY (mission_track_uuid) REFERENCES smart.mission_track(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.survey_waypoint ADD CONSTRAINT survey_wp_missionday_uuid FOREIGN KEY (mission_day_uuid) REFERENCES smart.mission_day(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.survey_waypoint ADD CONSTRAINT survey_wp_sampling_unit_uuid FOREIGN KEY (sampling_unit_uuid) REFERENCES smart.sampling_unit(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.survey_gridded_query ADD CONSTRAINT svy_gridded_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.survey_gridded_query ADD CONSTRAINT svy_gridded_creator_uuid_fk FOREIGN KEY (creator_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.survey_gridded_query ADD CONSTRAINT svy_gridded_folder_uuid_fk FOREIGN KEY (folder_uuid) REFERENCES smart.query_folder(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.survey_mission_query ADD CONSTRAINT svy_mission_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.survey_mission_query ADD CONSTRAINT svy_mission_creator_uuid_fk FOREIGN KEY (creator_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.survey_mission_query ADD CONSTRAINT svy_mission_folder_uuid_fk FOREIGN KEY (folder_uuid) REFERENCES smart.query_folder(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.survey_mission_track_query ADD CONSTRAINT svy_mission_track_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.survey_mission_track_query ADD CONSTRAINT svy_mission_track_creator_uuid_fk FOREIGN KEY (creator_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.survey_mission_track_query ADD CONSTRAINT svy_mission_track_folder_uuid_fk FOREIGN KEY (folder_uuid) REFERENCES smart.query_folder(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.survey_observation_query ADD CONSTRAINT svy_observation_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.survey_observation_query ADD CONSTRAINT svy_observation_creator_uuid_fk FOREIGN KEY (creator_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.survey_observation_query ADD CONSTRAINT svy_observation_folder_uuid_fk FOREIGN KEY (folder_uuid) REFERENCES smart.query_folder(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.survey_summary_query ADD CONSTRAINT svy_summary_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.survey_summary_query ADD CONSTRAINT svy_summary_creator_uuid_fk FOREIGN KEY (creator_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.survey_summary_query ADD CONSTRAINT svy_summary_folder_uuid_fk FOREIGN KEY (folder_uuid) REFERENCES smart.query_folder(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.survey_waypoint_query ADD CONSTRAINT svy_waypoint_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.survey_waypoint_query ADD CONSTRAINT svy_waypoint_creator_uuid_fk FOREIGN KEY (creator_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.survey_waypoint_query ADD CONSTRAINT svy_waypoint_folder_uuid_fk FOREIGN KEY (folder_uuid) REFERENCES smart.query_folder(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.plan_target ADD CONSTRAINT target_plan_uuid_fk FOREIGN KEY (plan_uuid) REFERENCES smart.plan(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.team ADD CONSTRAINT team_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.team ADD CONSTRAINT team_patrol_mandate_uuid_fk FOREIGN KEY (patrol_mandate_uuid) REFERENCES smart.patrol_mandate(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.track ADD CONSTRAINT track_leg_day_uuid_fk FOREIGN KEY (patrol_leg_day_uuid) REFERENCES smart.patrol_leg_day(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.waypoint ADD CONSTRAINT waypoint_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.waypoint_query ADD CONSTRAINT waypoint_query_ca_uuid_fk FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.waypoint_query ADD CONSTRAINT waypoint_query_creator_uuid_fk FOREIGN KEY (creator_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.waypoint_query ADD CONSTRAINT waypoint_query_folder_uuid_fk FOREIGN KEY (folder_uuid) REFERENCES smart.query_folder(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE ONLY smart.wp_attachments ADD CONSTRAINT wp_attachments_wp_uuid_fk FOREIGN KEY (wp_uuid) REFERENCES smart.waypoint(uuid) ON DELETE CASCADE DEFERRABLE;
ALTER TABLE smart.WP_ATTACHMENTS ADD FOREIGN KEY (signature_type_uuid) REFERENCES smart.signature_type(uuid) ON DELETE SET NULL ON UPDATE RESTRICT DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE smart.signature_type ADD FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE ON UPDATE RESTRICT DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.wp_observation_group ADD CONSTRAINT wp_observation_group_wp_uuid_fkey FOREIGN KEY (wp_uuid) REFERENCES smart.waypoint(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY smart.wp_observation ADD CONSTRAINT wp_observation_wp_group_uuid_fkey FOREIGN KEY (wp_group_uuid) REFERENCES smart.wp_observation_group(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE smart.smartcollect_waypoint ADD FOREIGN KEY (wp_uuid) REFERENCES smart.waypoint(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE smart.smartcollect_package ADD FOREIGN KEY (CA_UUID) REFERENCES smart.conservation_area(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE smart.smartcollect_package ADD FOREIGN KEY (CM_UUID) REFERENCES smart.configurable_model(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE smart.smartcollect_package ADD FOREIGN KEY (ctprofile_uuid) REFERENCES smart.ct_properties_profile(uuid) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE SMART.ct_incident_package ADD CONSTRAINT ct_incident_package_ca_uuid_fk FOREIGN KEY (CA_UUID) REFERENCES smart.conservation_area(UUID) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE SMART.ct_incident_package ADD CONSTRAINT ct_incident_package_cm_uuid_fk FOREIGN KEY (CM_UUID) REFERENCES smart.configurable_model(UUID) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE SMART.ct_incident_package ADD CONSTRAINT ct_incident_package_ctprofile_uuid_fk FOREIGN KEY (ctprofile_uuid) REFERENCES smart.ct_properties_profile(UUID) ON UPDATE RESTRICT ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE smart.data_link ADD FOREIGN KEY (ca_uuid) REFERENCES smart.conservation_area(uuid) ON DELETE CASCADE ON UPDATE RESTRICT DEFERRABLE INITIALLY DEFERRED;


CREATE TRIGGER trg_smartcollect_package AFTER INSERT OR UPDATE OR DELETE ON smart.smartcollect_package FOR EACH ROW execute procedure connect.trg_changelog_common();
CREATE OR REPLACE FUNCTION connect.smartcollect_waypoint() RETURNS trigger AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
 	INSERT INTO connect.change_log 
 		(uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid) 
 		SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'wp_uuid', ROW.wp_uuid, null, null, null, wp.ca_uuid 
 		FROM smart.waypoint wp WHERE wp.uuid = row.wp_uuid;
RETURN ROW; END$$ LANGUAGE 'plpgsql';
CREATE TRIGGER trg_smartcollect_waypoint AFTER INSERT OR UPDATE OR DELETE ON smart.smartcollect_waypoint FOR EACH ROW execute procedure connect.smartcollect_waypoint();


--PAWS TRIGGERS
CREATE OR REPLACE FUNCTION connect.trg_paws_config_join() RETURNS trigger AS $$
	DECLARE
	ROW RECORD;
BEGIN
	IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN	
 	ROW = NEW;
 	ELSIF (TG_OP = 'DELETE') THEN
 		ROW = OLD;
 	END IF;
 
 	INSERT INTO connect.change_log 
 		(uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid) 
 		SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'uuid', ROW.uuid, null, null, null, c.CA_UUID 
 		FROM smart.paws_configuration c WHERE c.uuid = ROW.config_uuid;
 RETURN ROW;
END$$ LANGUAGE 'plpgsql';

CREATE TRIGGER trg_paws_configuration AFTER INSERT OR UPDATE OR DELETE ON smart.paws_configuration FOR EACH ROW execute procedure connect.trg_changelog_common();
CREATE TRIGGER trg_paws_run AFTER INSERT OR UPDATE OR DELETE ON smart.paws_run FOR EACH ROW execute procedure connect.trg_changelog_common();
CREATE TRIGGER trg_paws_service AFTER INSERT OR UPDATE OR DELETE ON smart.paws_service FOR EACH ROW execute procedure connect.trg_changelog_common();
CREATE TRIGGER trg_paws_simple_class AFTER INSERT OR UPDATE OR DELETE ON smart.paws_simple_class FOR EACH ROW execute procedure connect.trg_paws_config_join();
CREATE TRIGGER trg_paws_query_class AFTER INSERT OR UPDATE OR DELETE ON smart.paws_query_class FOR EACH ROW execute procedure connect.trg_paws_config_join();
CREATE TRIGGER trg_paws_parameter AFTER INSERT OR UPDATE OR DELETE ON smart.paws_parameter FOR EACH ROW execute procedure connect.trg_paws_config_join();


-- tile cache --

CREATE TABLE connect.tile_cache(
  uuid UUID NOT NULL,
  map_uuid UUID NOT NULL,
  z int,
  x int,
  y int,
  data bytea,
  last_accessed timestamp,
  primary key (uuid),
  unique(map_uuid,x,y,z)
);
ALTER TABLE connect.tile_cache ADD FOREIGN KEY (map_uuid) REFERENCES smart.saved_maps(uuid) ON DELETE CASCADE ON UPDATE RESTRICT DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE connect.tile_cache_bounds(
  map_uuid UUID NOT NULL,
  x_min double precision,
  x_max double precision,
  y_min double precision,
  y_max double precision,
  primary key (map_uuid)
);
ALTER TABLE connect.tile_cache_bounds ADD FOREIGN KEY (map_uuid) REFERENCES smart.saved_maps(uuid) ON DELETE CASCADE ON UPDATE RESTRICT DEFERRABLE INITIALLY DEFERRED;


CREATE OR REPLACE FUNCTION connect.tile_cache_cleanup() RETURNS trigger LANGUAGE PLPGSQL AS $$
BEGIN 
  DELETE FROM connect.tile_cache where map_uuid = NEW.uuid;
  DELETE FROM connect.tile_cache_bounds where map_uuid = NEW.uuid; 
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_tile_cache AFTER UPDATE OF map_def ON smart.saved_maps FOR EACH ROW execute procedure connect.tile_cache_cleanup();

-- function for accessing files that also update the last_accessed field of the table
CREATE FUNCTION connect.find_tile(uuid, int, int, int) RETURNS bytea LANGUAGE PLPGSQL AS $$
DECLARE
  r RECORD;
BEGIN
  SELECT * INTO r FROM connect.tile_cache where map_uuid = $1 and x = $3 and y = $4 and z = $2;
  IF r IS NULL THEN
  	RETURN NULL;
  END IF;
  UPDATE connect.tile_cache set last_accessed = now() where uuid = r.uuid;
  RETURN r.data; 
END;
$$;



insert into smart.dm_aggregation(name) values ('sum');
insert into smart.dm_aggregation(name) values ('avg');
insert into smart.dm_aggregation(name) values ('min');
insert into smart.dm_aggregation(name) values ('max');
insert into smart.dm_aggregation(name) values ('stddev_samp');
insert into smart.dm_aggregation(name) values ('var_samp');

insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('avg', 'en', 'average');
insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('max', 'en', 'maximum');
insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('min', 'en', 'minimum');
insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('stddev_samp', 'en', 'standard deviation (samp.)');
insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('sum', 'en', 'sum');
insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('var_samp', 'en', 'variance (samp.)');

insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('avg', 'es', 'promedio');
insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('max', 'es', 'máximo');
insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('min', 'es', 'mínimo');
insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('stddev_samp', 'es', 'Desviación estándar');
insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('sum', 'es', 'total');
insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('var_samp', 'es', 'Varianza');

insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('avg', 'fr', 'moyenne');
insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('max', 'fr', 'maximum');
insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('min', 'fr', 'minimum');
insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('stddev_samp', 'fr', 'Ecart type');
insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('sum', 'fr', 'total');
insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('var_samp', 'fr', 'Variance');

insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('avg', 'in', 'rata-rata');
insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('max', 'in', 'maksimum');
insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('min', 'in', 'minimum');
insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('stddev_samp', 'in', 'Standar Deviasi');
insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('sum', 'in', 'jumlah');
insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('var_samp', 'in', 'Varians');

insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('min', 'ru', 'минимальный');
insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('sum', 'ru', 'итога');
insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('max', 'ru', 'максимальный');
insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('avg', 'ru', 'средний');

insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('avg','th','ค่าเฉลี่ย');
insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('max','th','ค่าสูงสุด');
insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('min','th','ค่าต่ำสุด');
insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('sum','th','ผลรวม');

insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('var_samp', 'vi', 'Phương sai');
insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('stddev_samp', 'vi', 'Độ lệch chuẩn');

insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('avg', 'zh', '平均');
insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('max', 'zh', '最大');
insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('min', 'zh', '最小');
insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('stddev_samp', 'zh', '标准差');
insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('sum', 'zh', '合计');
insert into smart.dm_aggregation_i18n (name, lang_code, gui_name) values ('var_samp', 'zh', '方差');


INSERT INTO connect.roles (role_id, rolename, is_system) VALUES ('smart', 'SYSTEM ROLE', true);

INSERT INTO connect.connect_version (version, last_updated, filestore_version) VALUES ('7.0.0', now(), '7.0.0');

--INSERT INTO connect.connect_plugin_version (plugin_id, version) VALUES ('org.wcs.smart.intelligence','4.0');
--INSERT INTO connect.connect_plugin_version (plugin_id, version) VALUES ('org.wcs.smart.intelligence.query','2.0');
INSERT INTO connect.connect_plugin_version (plugin_id, version) VALUES ('org.wcs.smart.plan','4.0');
INSERT INTO connect.connect_plugin_version (plugin_id, version) VALUES ('org.wcs.smart.entity','3.0');
INSERT INTO connect.connect_plugin_version (plugin_id, version) VALUES ('org.wcs.smart.er','3.0');
INSERT INTO connect.connect_plugin_version (plugin_id, version) VALUES ('org.wcs.smart.connect','1.0');
INSERT INTO connect.connect_plugin_version (plugin_id, version) VALUES ('org.wcs.smart.connect.cybertracker','2.0');
INSERT INTO connect.connect_plugin_version (plugin_id, version) VALUES ('org.wcs.smart.entity.query','4.0');
INSERT INTO connect.connect_plugin_version (plugin_id, version) VALUES ('org.wcs.smart.er.query','4.0');
INSERT INTO connect.connect_plugin_version (plugin_id, version) VALUES ('org.wcs.smart.qa','1.0');
INSERT INTO connect.connect_plugin_version (plugin_id, version) VALUES ('org.wcs.smart.event','2.0');
INSERT INTO connect.connect_plugin_version (plugin_id, version) VALUES ('org.wcs.smart.connect.dataqueue','3.0');
INSERT INTO connect.connect_plugin_version (plugin_id, version) VALUES ('org.wcs.smart.asset','2.0');
INSERT INTO connect.connect_plugin_version (plugin_id, version) VALUES ('org.wcs.smart.asset.query','2.0');
INSERT INTO connect.connect_plugin_version (plugin_id, version) VALUES ('org.wcs.smart.r','1.0');
INSERT INTO connect.connect_plugin_version (plugin_id, version) VALUES ('org.wcs.smart.cybertracker.patrol','2.0');
INSERT INTO connect.connect_plugin_version (plugin_id, version) VALUES ('org.wcs.smart.cybertracker.survey','2.0');
INSERT INTO connect.connect_plugin_version (plugin_id, version) VALUES ('org.wcs.smart.paws','1.0');
INSERT INTO connect.connect_plugin_version (plugin_id, version) VALUES ('org.wcs.smart','7.0.0');
INSERT INTO connect.connect_plugin_version (plugin_id, version) VALUES ('org.wcs.smart.cybertracker','7.0');
INSERT INTO connect.connect_plugin_version (plugin_id, version) VALUES ('org.wcs.smart.i2','5.0');
insert into connect.connect_plugin_version (plugin_id, version) values ('org.wcs.smart.smartcollect', '1.0');
insert into connect.connect_plugin_version (version, plugin_id) values ('2.0', 'org.wcs.smart.cybertracker.incident');



CREATE OR REPLACE FUNCTION connect.trg_survey_waypoint() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    ROW RECORD;
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
     ROW = NEW;
     ELSIF (TG_OP = 'DELETE') THEN
         ROW = OLD;
     END IF;

     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'wp_uuid', ROW.wp_uuid, null, null, null, wp.CA_UUID
         FROM smart.waypoint wp
         WHERE wp.uuid = ROW.wp_uuid;
     RETURN ROW;
END$$;

--update connect.connect_plugin_version set version = '4.0' where plugin_id = 'org.wcs.smart.er';
--update connect.ca_plugin_version set version = '4.0' where plugin_id = 'org.wcs.smart.er';

--update connect.connect_version set version = '7.3.0', last_updated = now();



--disable change tracking 
SET session_replication_role = replica;
update smart.WAYPOINT set last_modified_by = null where last_modified_by not in (select uuid from smart.employee);
ALTER TABLE smart.employee_team_member ADD FOREIGN KEY (employee_uuid) REFERENCES smart.employee(uuid) ON DELETE CASCADE ON UPDATE RESTRICT DEFERRABLE INITIALLY DEFERRED;
SET session_replication_role = DEFAULT;

--update connect.connect_plugin_version set version = '7.4.1' where plugin_id = 'org.wcs.smart';
--update connect.ca_plugin_version set version = '7.4.1' where plugin_id = 'org.wcs.smart';
--update connect.connect_version set version = '7.4.1', last_updated = now();


-- SMART Connect 7.5.0

-- new org.wcs.smart.i2.patrol plugin
CREATE TABLE smart.i_patrol_record_motivation(
  patrol_uuid uuid NOT NULL, 
  i_record_uuid uuid NOT NULL, 
  PRIMARY KEY (i_record_uuid, patrol_uuid)
);

ALTER TABLE smart.i_patrol_record_motivation ADD CONSTRAINT i_patrol_record_motivation_patrol_fk FOREIGN KEY (patrol_uuid) REFERENCES smart.patrol(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE smart.i_patrol_record_motivation ADD CONSTRAINT i_patrol_record_motivation_record_fk FOREIGN KEY (i_record_uuid) REFERENCES smart.i_record(uuid) ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE;

CREATE OR REPLACE FUNCTION connect.trg_patrol_record_motivation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE ROW RECORD; BEGIN IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN ROW = NEW; ELSIF (TG_OP = 'DELETE') THEN ROW = OLD; END IF;
     INSERT INTO connect.change_log
         (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
         SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'patrol_uuid', ROW.patrol_uuid, 'i_record_uuid', ROW.i_record_uuid, null, p.CA_UUID
         FROM smart.patrol p WHERE p.uuid = ROW.patrol_uuid; 
RETURN ROW; END$$;

CREATE TRIGGER trg_patrol_record_motivation AFTER INSERT OR DELETE OR UPDATE ON smart.i_patrol_record_motivation FOR EACH ROW EXECUTE PROCEDURE connect.trg_patrol_record_motivation();

INSERT INTO connect.connect_plugin_version(plugin_id, version) 
VALUES('org.wcs.smart.i2.patrol', '1.0');

INSERT INTO connect.ca_plugin_version(ca_uuid, plugin_id, version) 
SELECT ca_uuid, 'org.wcs.smart.i2.patrol', '1.0'
FROM connect.ca_plugin_version 
WHERE plugin_id = 'org.wcs.smart.i2';

--remove labels from configurable models that match data model 
DELETE FROM smart.i18n_label 
WHERE (element_uuid, language_uuid) IN 
(
SELECT va.element_uuid, va.language_uuid
FROM smart.cm_node a, smart.i18n_label va, smart.i18n_label ca 
WHERE a.category_uuid is not null AND 
ca.element_uuid = a.category_uuid AND 
va.element_uuid = a.uuid AND 
va.language_uuid = ca.language_uuid AND 
va.value = ca.value 
);

DELETE FROM smart.i18n_label 
WHERE (element_uuid, language_uuid) IN 
(
SELECT va.element_uuid, va.language_uuid
FROM smart.cm_attribute a, smart.i18n_label va, smart.i18n_label ca 
WHERE a.attribute_uuid is not null AND 
ca.element_uuid = a.attribute_uuid AND 
va.element_uuid = a.uuid AND 
va.language_uuid = ca.language_uuid AND 
va.value = ca.value 
);

-- signatures added to observation attachment tables
alter table smart.OBSERVATION_ATTACHMENT add column signature_type_uuid uuid;
alter table smart.observation_attachment ADD CONSTRAINT observation_attachment_sig_fk foreign key (signature_type_uuid)  references smart.signature_type(uuid) ON DELETE SET NULL ON UPDATE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;

-- typo
update smart.i18n_label set value = 'Hyaena Brown' WHERE  value = 'Hyaena rown' and element_uuid in (select uuid from smart.icon where keyid = 'hyaena_rown');


--update versions
--update connect.connect_plugin_version set version = '7.5.0' where plugin_id = 'org.wcs.smart';
--update connect.ca_plugin_version set version = '7.5.0' where plugin_id = 'org.wcs.smart';
--update connect.connect_version set version = '7.5.0', last_updated = now();

CREATE OR REPLACE FUNCTION connect.trg_survey_waypoint() RETURNS trigger
   LANGUAGE plpgsql
   AS $$
   DECLARE
   ROW RECORD;
BEGIN
   IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
    ROW = NEW;
    ELSIF (TG_OP = 'DELETE') THEN
        ROW = OLD;
    END IF;
    INSERT INTO connect.change_log
        (uuid, action, tablename, key1_fieldname, key1, key2_fieldname, key2_uuid, key2_str, ca_uuid)
        SELECT uuid_generate_v4(), TG_OP, TG_TABLE_SCHEMA::TEXT || '.' || TG_TABLE_NAME::TEXT, 'wp_uuid', ROW.wp_uuid, null, null, null, wp.CA_UUID
        FROM smart.waypoint wp
        WHERE wp.uuid = ROW.wp_uuid;
    RETURN ROW;
END$$;
update connect.connect_plugin_version set version = '4.0' where plugin_id = 'org.wcs.smart.er';
update connect.ca_plugin_version set version = '4.0' where plugin_id = 'org.wcs.smart.er';


update smart.iconfile set filename = 'platform:/plugin/org.wcs.smart/images/datamodel/color/Rocks_and_minerals_icon.svg' where filename = 'platform:/plugin/org.wcs.smart/images/datamodel/color/Rocks & minerals_icon.svg';

update smart.iconfile set filename = 'platform:/plugin/org.wcs.smart/images/datamodel/line/Rocks_and_minerals_icon.svg' where filename = 'platform:/plugin/org.wcs.smart/images/datamodel/line/Rocks & minerals_icon.svg';

update smart.iconfile set filename = 'platform:/plugin/org.wcs.smart/images/datamodel/black/Rocks_and_minerals_icon.svg' where filename = 'platform:/plugin/org.wcs.smart/images/datamodel/black/Rocks & minerals_icon.svg';

update smart.iconfile set filename = 'platform:/plugin/org.wcs.smart/images/datamodel/color/Infrastructure_and_roads_icon.svg' where filename = 'platform:/plugin/org.wcs.smart/images/datamodel/color/Infrastructure & roads_icon.svg';

update smart.iconfile set filename = 'platform:/plugin/org.wcs.smart/images/datamodel/line/Infrastructure_and_roads_icon.svg' where filename = 'platform:/plugin/org.wcs.smart/images/datamodel/line/Infrastructure & roads_icon.svg';

update smart.iconfile set filename = 'platform:/plugin/org.wcs.smart/images/datamodel/black/Infrastructure_and_roads_icon.svg' where filename = 'platform:/plugin/org.wcs.smart/images/datamodel/black/Infrastructure & roads_icon.svg';

update smart.iconfile set filename = 'platform:/plugin/org.wcs.smart/images/datamodel/color/Weapons_and_Gear_seized_icon.svg' where filename = 'platform:/plugin/org.wcs.smart/images/datamodel/color/Weapons & Gear_seized_icon.svg';

update smart.iconfile set filename = 'platform:/plugin/org.wcs.smart/images/datamodel/line/Weapons_and_Gear_seized_icon.svg' where filename = 'platform:/plugin/org.wcs.smart/images/datamodel/line/Weapons & Gear_seized_icon.svg';

update smart.iconfile set filename = 'platform:/plugin/org.wcs.smart/images/datamodel/black/Weapons_and_Gear_seized_icon.svg' where filename = 'platform:/plugin/org.wcs.smart/images/datamodel/black/Weapons & Gear_seized_icon.svg';

alter table smart.icon add constraint icon_key_unq unique (ca_uuid, keyid);

--update versions
--update connect.connect_plugin_version set version = '7.5.1' where plugin_id = 'org.wcs.smart';
--update connect.ca_plugin_version set version = '7.5.1' where plugin_id = 'org.wcs.smart';
--update connect.connect_version set version = '7.5.1', last_updated = now(), filestore_version = '7.5.1';

-- 7.5.3
alter table smart.data_link drop constraint "data_link_provider_id_key";

alter table smart.data_link add constraint data_link_provider_id_unq unique(provider_id, data_type);
alter table smart.data_link add constraint data_link_smart_id_unq unique(smart_id);



CREATE OR REPLACE FUNCTION connect.trg_changelog_after() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
    PERFORM pg_advisory_unlock_shared(a.lock_key) FROM connect.ca_info a WHERE a.ca_uuid = NEW.ca_uuid;
RETURN NEW; END$$;


CREATE OR REPLACE FUNCTION connect.trg_changelog_before() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  canlock boolean;
BEGIN
    --check if we should log this ca
    IF (NOT connect.dolog(NEW.ca_uuid)) THEN RETURN NULL; END IF;
    SELECT pg_try_advisory_lock_shared(a.lock_key) into canlock FROM connect.ca_info a WHERE a.ca_uuid = NEW.ca_uuid;
    IF (canlock) THEN return NEW; ELSE RAISE EXCEPTION 'Database Locked to Editing'; END IF;
END$$;

-- 7.5.4
ALTER TABLE smart.survey_waypoint ADD CONSTRAINT survey_waypoint_wp_uuid_fk FOREIGN KEY (wp_uuid) REFERENCES smart.waypoint(uuid) ON DELETE CASCADE DEFERRABLE;

--update versions
update connect.connect_plugin_version set version = '5.0' where plugin_id = 'org.wcs.smart.er';
update connect.ca_plugin_version set version = '5.0' where plugin_id = 'org.wcs.smart.er';

update connect.connect_plugin_version set version = '7.5.4' where plugin_id = 'org.wcs.smart';
update connect.ca_plugin_version set version = '7.5.4' where plugin_id = 'org.wcs.smart';

--don't update the version as we are not deploying a new jar file
--update connect.connect_version set version = '7.5.4', last_updated = now();
update connect.connect_version set version = '7.5.3', filestore_version = '7.5.2', last_updated = now();
