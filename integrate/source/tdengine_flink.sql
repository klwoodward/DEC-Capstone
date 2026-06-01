---------------------------------
-- statement 1 (create new table for sites)
---------------------------------

CREATE TABLE `default`.`cluster_solar`.`sites_parsed` (
  ts TIMESTAMP(3), -- precision can only go to millisecond, though our data has microsecond precision
  site_id STRING,
  fleet STRING,
  --location STRING,
  latitude DOUBLE,
  longitude DOUBLE,
  mwdc DOUBLE,
  mwac DOUBLE,
  poa_irradiance_wm2 DOUBLE,
  ac_power_mw DOUBLE,
  expected_power_mw DOUBLE,
  performance_ratio DOUBLE,
  availability_pct DOUBLE,
  curtailment_pct DOUBLE,
  energy_today_mwh DOUBLE,
  soiling_index DOUBLE,
  active_alarms INT,
  alarm_messages STRING,
  WATERMARK FOR ts AS ts - INTERVAL '5' SECOND -- treat ts as event time and allow records to arrive up to 5 seconds late (watermark is required to use ts for flink window functions like TUMBLE, HOP, SESSION)
)
WITH (
  'changelog.mode' = 'append'
);

---------------------------------
-- statement 2 (read in data to sites_parsed)
---------------------------------

INSERT INTO `default`.`cluster_solar`.`sites_parsed`
SELECT
  TO_TIMESTAMP(JSON_VALUE(json_val, '$.ts'), 'yyyy-MM-dd''T''HH:mm:ss.SSSSSSXXX'),
  JSON_VALUE(json_val, '$.Site_ID'),
  JSON_VALUE(json_val, '$.Fleet'),
  --JSON_VALUE(json_val, '$.Location'),
  CAST(SPLIT_INDEX(JSON_VALUE(json_val, '$.Location'), ',', 0) AS DOUBLE),
  CAST(SPLIT_INDEX(JSON_VALUE(json_val, '$.Location'), ',', 1) AS DOUBLE),
  CAST(JSON_VALUE(json_val, '$.MWdc') AS DOUBLE),
  CAST(JSON_VALUE(json_val, '$.MWac') AS DOUBLE),
  CAST(JSON_VALUE(json_val, '$.POA_Irradiance_Wm2') AS DOUBLE),
  CAST(JSON_VALUE(json_val, '$.AC_Power_MW') AS DOUBLE),
  CAST(JSON_VALUE(json_val, '$.Expected_Power_MW') AS DOUBLE),
  CAST(JSON_VALUE(json_val, '$.Performance_Ratio') AS DOUBLE),
  CAST(JSON_VALUE(json_val, '$.Availability_%') AS DOUBLE),
  CAST(JSON_VALUE(json_val, '$.Curtailment_%') AS DOUBLE),
  CAST(JSON_VALUE(json_val, '$.Energy_Today_MWh') AS DOUBLE),
  CAST(JSON_VALUE(json_val, '$.Soiling_Index') AS DOUBLE),
  CAST(JSON_VALUE(json_val, '$.Active_Alarms') AS INT),
  JSON_QUERY(json_val, '$.Alarm_Messages')
FROM (
  SELECT CAST(`val` AS STRING) AS json_val
  FROM `default`.`cluster_solar`.`solar`
  WHERE CAST(`key` AS STRING) = 'sites'
);

---------------------------------
-- statement 3 (create new table for grid_parsed)
---------------------------------

CREATE TABLE `default`.`cluster_solar`.`grid_parsed` (
  ts TIMESTAMP(3), -- precision can only go to millisecond, though our data has microsecond precision
  meter_id STRING,
  site_id STRING,
  fleet STRING,
  --location STRING,
  latitude DOUBLE,
  longitude DOUBLE,
  active_power_mw DOUBLE,
  reactive_power_mvar DOUBLE,
  voltage_kv DOUBLE,
  frequency_hz DOUBLE,
  setpoint_mw DOUBLE,
  curtailment_mw DOUBLE,
  curtailment_pct DOUBLE,
  status STRING,
  energy_today_mwh DOUBLE,
  WATERMARK FOR ts AS ts - INTERVAL '5' SECOND -- treat ts as event time and allow records to arrive up to 5 seconds late (watermark is required to use ts for flink window functions like TUMBLE, HOP, SESSION)
)
WITH (
  'changelog.mode' = 'append'
);

---------------------------------
-- statement 4 (read in data to grid_parsed)
---------------------------------

INSERT INTO `default`.`cluster_solar`.`grid_parsed`
SELECT
  TO_TIMESTAMP(JSON_VALUE(json_val, '$.ts'),'yyyy-MM-dd''T''HH:mm:ss.SSSSSSXXX'), 
  JSON_VALUE(json_val, '$.Meter_ID'),
  JSON_VALUE(json_val, '$.Site_ID'),
  JSON_VALUE(json_val, '$.Fleet'),
  --JSON_VALUE(json_val, '$.Location'),
  CAST(SPLIT_INDEX(JSON_VALUE(json_val, '$.Location'), ',', 0) AS DOUBLE),
  CAST(SPLIT_INDEX(JSON_VALUE(json_val, '$.Location'), ',', 1) AS DOUBLE),
  CAST(JSON_VALUE(json_val, '$.Active_Power_MW') AS DOUBLE),
  CAST(JSON_VALUE(json_val, '$.Reactive_Power_MVar') AS DOUBLE),
  CAST(JSON_VALUE(json_val, '$.Voltage_kV') AS DOUBLE),
  CAST(JSON_VALUE(json_val, '$.Frequency_Hz') AS DOUBLE),
  CAST(JSON_VALUE(json_val, '$.Setpoint_MW') AS DOUBLE),
  CAST(JSON_VALUE(json_val, '$.Curtailment_MW') AS DOUBLE),
  CAST(JSON_VALUE(json_val, '$.Curtailment_%') AS DOUBLE),
  JSON_VALUE(json_val, '$.Status'),
  CAST(JSON_VALUE(json_val, '$.Energy_Today_MWh') AS DOUBLE)
FROM (
  SELECT CAST(`val` AS STRING) AS json_val
  FROM `default`.`cluster_solar`.`solar`
  WHERE CAST(`key` AS STRING) = 'grid'
);

---------------------------------
-- statement 5 (create new table for sites hop table and read in data)
---------------------------------

CREATE TABLE `default`.`cluster_solar`.`sites_1min_agg`
AS
SELECT
    window_start,
    window_end,
    site_id,
    fleet,
    AVG(ac_power_mw) AS avg_ac_power_mw,
    AVG(expected_power_mw) AS avg_expected_power_mw,
    AVG(ac_power_mw) / NULLIF(AVG(expected_power_mw), 0) AS power_vs_expected_ratio,
    AVG(performance_ratio) AS avg_performance_ratio,
    AVG(poa_irradiance_wm2) AS avg_poa_irradiance_wm2,
    AVG(availability_pct) AS avg_availability_pct,
    AVG(soiling_index) AS avg_soiling_index,
    MAX(active_alarms) AS max_active_alarms,
    COUNT(*) AS record_count
FROM TABLE(
    TUMBLE(
        DATA => TABLE `default`.`cluster_solar`.`sites_parsed`,
        TIMECOL => DESCRIPTOR(ts),
        SIZE => INTERVAL '1' MINUTE
    )
)
GROUP BY
    window_start,
    window_end,
    site_id,
    fleet;

---------------------------------
-- statement 6 (create materialized view for preset)
---------------------------------