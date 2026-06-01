A Data Engineering Bootcamp project on datacenters and electricity metrics. You can follow step by step below!

# Batch Data

![batch-data-architecture.png](pics/architecture.png)

![batch-dataflow.png](pics/database_organization.png)


### Data Center Atlas (simulated as live data within a database)

IM3 Open Source Data Center Atlas:
- [Data documentation](https://data.msdlive.org/records/p147s-4h760)
- [Data dashboard](https://immm-sfa.github.io/datacenter-atlas/)

1. Set up parameter group for CDC
    - Navigate to RDS, and click on Parameter Groups
    - Create a new parameter group <cdc_parameter_group>, and set rds.logical_replication to 1
2. Set up RDS database
    - Create an AWS account and navigate to RDS
    - It is recommended to set your region to a nearby location when you use AWS services
    - Create Database > Full Configuration
    - Configuration: 
        - Choose a database configuration method: Full Configuration
        - Engine option: PostgreSQL
        - DB Instance Identifier: <rds_db_instance_name> (e.g. 'im3')
        - Credentials Management: manage in AWS Secrets manager
        - Storage > Additional Storage Configuration: deselect 'Enable storage autoscaling'
        - Connectivity > Public access: Yes
        - Additional configuration > DB parameter group: <cdc_parameter_group>
    - Create database...once successfully created, 'View Connection details' to get the database Endpoint url
3. Allow inbound traffic
    - Once the database has been created, go to 'Connectivity and security'
    - Select the default VPC security group
    - Select 'Edit inbound rules'
    - Select 'Add rule'
        - Select "All TCP"
        - Select 'Anywhere-IPv4'
        - Select 'Save rules'
4. Retrieve database connection info
    - Navigate to Secrets Manager and select the newly generated secret
    - Select 'Retrieve secret value' to get the username and password of the database
5. PgAdmin4
    - Install PgAdmin4 
    - Right click on 'Servers' > Register > Server:
        - General > Name: set a <pdadmin_server_name> (e.g. 'aws-rds')
        - Connection > Host name: <endpoint_from_rds>
        - Connection > Port: 5432
        - Connection > Password: <password_from_Secret_Manager>
        - Select "Save"
    - Under the newly created server, right click on 'Databases' > Create > Database, and provide a <database_name> (e.g. 'im3')
    - Right click on the newly created database to select Query Tool
        - Run the SQL within im3_setup.sql
5. Enable CDC
    - For any table we want to replicate with CDC, we need to create a logical replication slot that will track changes
    - In PgAdmin4 run the SQL within `enable_cdc.sql` to enable CDC


### Snowflake

1. 
    - Create Snowflake Account
    - Go to Compute > Warehouse and create a <snowflake_warehouse> (e.g. 'COMPUTE_WH') of desired compute size
    - Select your account at the bottom left, then Account > View Account Details > Account/Server URL to get the <snowflake_host_url>
    - Run the following lines in Snowflake by selecting the plus then Create > SQL File:
        ```sql
        use role accountadmin;
        use warehouse <snowflake_warehouse>;

        create database raw;
        create schema raw.datacenters;
        create schema raw.scd_datacenters;

        create database staging;
        create schema staging.datacenters;
        create schema staging.scd_datacenters;
        create schema staging.electricity;

        create database marts;
        create schema composite;
        create schema factdim;
        ```

### Airbyte 

1. Create an Airbyte cloud account
    - Log into Airbyte ETL
    - We will create a new connection...

2. Create a new airbyte source of type Postgres
    - Name: "RDS-datacenters-1"
    - Host: <endpoint_from_rds>
    - Port: 5432
    - Database Name: <database_name> (e.g. 'im3')
    - Schemas: public
    - Username: postgres
    - Password: <password_from_Secret_Manager>
    - Update Method: Read Changes using Write-Ahead Log (CDC)
    - Replication Slot: 'airbyte_slot_deduped'
    - Publication: 'airbyte_publication'
    - Advanced > Update Method > Optional Fields > Initial Waiting Time in Seconds: 120 
        - (the minimum allowed, otherwise airbyte will continue polling)
    <!-- - Advanced > Update Method > Optional Fields > Debezium Heartbeat Query (advanced): `INSERT INTO airbyte_heartbeat (text) VALUES ('heartbeat')`
        - (refer to [(Advanced) Resolving sync failures due to WAL disk corruption](https://docs.airbyte.com/integrations/sources/postgres/postgres-troubleshooting#advanced-wal-disk-consumption-and-heartbeat-action-query)) -->
    <!-- - Advanced > Update Method > Optional Fields > Invalid CDC position behavior: Re-sync data -->

3. Follow the steps of 2, with these changes (this will connect to the same table, but a different replication slot):
    - Name: "RDS-datacenters-2"
    - Replication Slot: 'airbyte_slot_append'

4. Create a new airbyte destination of type Snowflake
    - Name: "Snowflake-1"
    - Host: <snowflake_host_url>
    - Role: accountadmin
    - Warehouse: <snowflake_warehouse> (e.g. "COMPUTE_WH")
    - Database Name: "raw"
    - Default Schema: "datacenters"
    - Username: <snowflake_login_name>
    - Authorization Method: Username and Password
    - Password: <snowflake_password>
    - Sync Behavior > CDC Deletion Mode: Hard delete

5. Follow the steps of 3, with these changes:
    - Name: "Snowflake-2"
    - Default Schema: "scd_datacenters"
    - Sync Behavior > CDC Deletion Mode: Soft delete

4. Create connections with the newly configured source and destination
    - Connection 1:
        - Source: "RDS-datacenters-1"
        - Destination: "Snowflake-1"
        - Select Sync Mode: Replicate Source
        - Sync Mode: Incremental Append + deduped
        - Connection Name: e.g. "RDS-datacenters-1 → Snowflake"
        - Schedule Type: Manual
        - Destination Namespace > Destination-defined
    - Connection 2 (we will add this so we can model a Slowly Changing Dimension):
        - Source: RDS-datacenters-1
        - Destination: "Snowflake-2"
        - Select Sync Mode: Append Historical Changes
            - Append New Rows and Updates Only
        - Sync Mode: Incremental Append
        - Connection Name: e.g. "RDS-datacenters-2 → Snowflake-2"
        - Schedule Type: Manual
        - Destination Namespace > Destination-defined
        - Stream Prefix: "scd_"


### State Electricity Data (through API)

U.S. Energy Information Administration:
- [API documentation](https://www.eia.gov/opendata/)
- [API dashboard](https://immm-sfa.github.io/datacenter-atlas/)


1. Register for an API key from the links above

2. Create a custom Airbyte source through the Builder > Start from Scratch > Skip and start manually
    - At top left, rename the connector from "Untitled" (e.g. to "eia API")
    - Name the stream (e.g. "state_electricity_profiles")
    - API Endpoint URL: https://api.eia.gov/v2/electricity/state-electricity-profiles/summary/data/?frequency=annual&data[0]=average-retail-price&data[1]=average-retail-price-rank&data[2]=direct-use&data[3]=direct-use-rank&sort[0][column]=period&sort[0][direction]=asc
    - Inputs > Add New User input
        - Input Name: "API Key"
        - Field ID: "api_key"
        - Required Field: enabled
        - Secret Field: enabled
        - Hidden Field: enabled
        - Save changes, then put your actual <api_key> into the input area
    - In the stream, turn on Authenticator
        - Inject API Key Into Outgoing HTTP Request: enable
        - Inject Into: Query Parameter
        - Parameter Name: api_key
    - Add the following Query Parameters as Key/Value string pairs
        - offset : 0
        - length : 5000
    - Turn on Incremental Sync, if desired (for demonstration of custom connector capability; there is not much practical use in this case)
        - Cursor Field: period
        - Cursor Datetime Formats: %Y
        - Start Datetime
            - Datetime: 2008
            - Datetime Format: %Y
        - Turn on Inject Start Time into Outgoing HTTP Request
            - Inject Into: Query Parameter
            - Parameter Name: start
        - Outgoing Datetime Format: %Y
    - Publish as "eia API"
    - Set up new Source, selecting the new connector under Custom
        - Provide the <api_key>

3. Create a new Airbyte connection  
    - In Sources, select the new custom source and enter the <api_key>
    - Choose the Snowflake destination
    - If you enabled Incremental Sync in step 2...
        - Add `period` and `stateID` as primary keys
        - Sync Mode: Incremental | Append + Deduped
        - Schedule Type: Manual
        - Destination Namespace > Custom Format: "electricity"
    - If you did not enable Incremental Sync in step 2...
        - Select Sync Mode: Replicate Source
        - Sync Mode: Full Refresh Overwrite
        - Schedule Type: Manual
        - Destination Namespace > Custom Format: "electricity"


### DBT

1. DBT will need information to connect to Snowflake
    - In Snowflake, elect your username at the bottom left, then Account > View Account Details > Account Identifier to get the <snowflake_account>
    - If you want to run dbt locally, you need to export these as environment variables in terminal:
        ```powershell
        # Example: PowerShell
        $env:SNOWFLAKE_USERNAME="<snowflake_login_name>"
        $env:SNOWFLAKE_PASSWORD="<snowflake_password>"
        $env:SNOWFLAKE_ACCOUNT="<snowflake_account>"
        ```
    - As DBT works it will also run our data quality tests
    - After DBT is done, these are all of our tables:
        ```sql
        -- raw
        select * from raw.datacenters.data_center_atlas;
        select * from raw.scd_datacenters.scd_data_center_atlas;
        select * from raw.electricity.state_electricity_profiles;

        -- staging
        select * from staging.datacenters.data_center_atlas;
        select * from staging.scd_datacenters.scd_data_center_atlas;
        select * from staging.scd_datacenters.operator_history;
        select * from staging.electricity.state_electricity_profiles;

        --marts
        select * from marts.composite.data_center_atlas_obt;
        select * from marts.composite.state_electricity_profiles_obt;
        select * from marts.composite.data_center_atlas_obt;
        select * from marts.factdim.dim_date;
        select * from marts.factdim.dim_state;
        select * from marts.factdim.dim_operator_scd; -- unfinished...unfortunately
        select * from marts.factdim.fact_new_datacenters;
        select * from marts.factdim.fact_new_datacenters_snapshot;
        ```

![dbt_lineage.png](pics/dbt_lineage.png)

![fact-dim-model.png](pics/fact-dim-model.png)


### Dagster

1. There is a template.env file in the repo that you will need to turn it into a .env file and supply info to
    - Airbyte client info can be found at...
        - Airbyte Cloud > User > Setting > Applications > Create an Application, then after entering a name you can retrieve Client Id and Client Secret
        - Airbyte Cloud > Workspace Settings to get the Workspace ID at the top right
2. Navigate to the dagster folder and run `dagster dev`
    - click on the link that pops up for local host


### Preset

1. If you want to create your own dashboard, you can create a new account with a free trial
2. Log in then go to Settings > Database Creation > +Database > Snowflake 
    - Fill in remaining info, and get to work~

![batch-Preset.png](pics/preset_dashboard.png)


### LLM AI
1. With Snowflake Cloud you can create a Semantic View with Cortex Analyst, but if you try to deploy an agent you will hit a paywall.


# Streaming Data

![stream-data-architecture.png](pics/stream-architecture.png)

![stream-dataflow.png](pics/stream-dataflow.png)


### Realistic Fleet Telemetry Data

TDengine Free Public MQTT Data Feed:
- [Data source documentation](https://tdengine.com/free-public-mqtt-data-feed-real-time-solar-fleet-simulation-now-available/?utm_source=chatgpt.com)


### Confluent

1. Sign up for a Confluent Cloud account
2. Navigate to Environments > Default > Clusters > Add new cluster
    - Name: "cluster_solar"
    - Cluster type: Basic
    - Provider: aws
3. Under our cluster Overview, grab the <bootstrap_server> url
4. In the cluster, go to Topics > Create Topic
    - Topic Name: "solar"
    - Partitions: 1 (can scale up)
    - Advanced Settings > Retention Time: 1 Day
    - after creating topic, skip data contract
5. Go to Connectors > Add Connector > MQTT Source
    - Choose the newly created topic ("solar")
    - Generate and download the <connector_api_key> and <connector_api_secret>
    - Authentication
        - List of Server URIs: "tcp://mqtt.tdengine.com:1883"
        - MQTT Topics: "sites, grid" <!-- sites,inverters,strings,weather,grid -->
    - Continue through the settings until the connector is launched
    - Under our "solar" topic, we should now be able to see data coming through under Messages


### Flink

1. Sign up for an Apache Flink account
2. In Confluent, go to SQL Workspaces > Create New Workspace
3. Refer to the repo file `integrate\source\tdengine_flink.sql`
    - Put the following SQL statements into their own code chunks within Flink, and run in order; the `INSERT` and `CREATE TABLE AS` statements will continue to run, whereas the `CREATE TABLE` statements will simply run and end
    - Note: we can see the status of our Flink statements under Environments > default > Flink
4. Head back to Environments > default > Schema Registry > Overview
    - Retrieve the <public_endpoint>
5. Go to API Keys > Add an API Key
    - Select Account: My account
    - Select Key Scope: Schema Registry
    - Environment: default
    - Create and download the <schema_registry_api_key> and <schema_registry_api_secret>


### ClickHouse

1. Sign up for a ClickHouse account
2. Configure a cloud service
    Database: ClickHouse
    - Service Name:
    - Cloud provider: AWS
3. To ingest data from the Kafka topic on Confluent Cloud, go to Data Sources > Add Data Source > Create ClickPipe
    - Source: Confluent Cloud
    - ClickPipe Name: "sites_clickpipe"
    - Broker: <bootstrap_server> from Confluent cluster
    - API Key: <connector_api_key>
    - API Secret: <connector_api_secret> 
    - Schema Registry: enable
        - Schema URL: <schema_registry_public_endpoint>
        - API Key: <schema_registry_api_key>
        - API Secret: <schema_registry_api_secret>
    - Topic: sites_parsed
    - Offset Selection: From Timestamp or From Latest
    - Schema Format: AvroConfluent
    - With the schema parsed we will want to upload data to new table:
        - Disable the Nullable trigger for the Source Fields "ts" and "site_id"
        - Sorting Key: "ts"
        - Partition By: "site_id"
    - Permissions: Full Access
4. Follow step 3 again, with the following changes
    - ClickPipe Name: "grid_clickpipe"
    - Topic: grid_parsed
    - Partition By: "meter_id"
5. Follow step 3 again, with the following changes
    - ClickPipe Name: "sites_1min_agg_clickpipe"
    - Offset Selection: From Timestamp or From Latest
    - Topic: sites_1min_agg
    - Sorting Key: "window_start"
5. We can create materialized views by running code in the SQL Console, e.g.
    ```sql
    CREATE MATERIALIZED VIEW site_power_leaders_1min
    ENGINE = MergeTree
    ORDER BY window_start
    AS
    SELECT
        window_start,
        window_end,
        argMax(site_id, avg_ac_power_mw) AS max_actual_site_id, -- site with highest actual production
        argMax(site_id, avg_expected_power_mw) AS max_expected_site_id, -- site with highest expected production
        max(avg_ac_power_mw) AS max_avg_ac_power_mw, -- highest actual power during the minute
        max(avg_expected_power_mw) AS max_avg_expected_power_mw, -- highest expected power during the minute
        max(avg_expected_power_mw) - max(avg_ac_power_mw) AS power_gap_mw, -- difference between expected and actual top power
        if( 
            argMax(site_id, avg_ac_power_mw)
            != argMax(site_id, avg_expected_power_mw),
            1, -- expected top producer differs from actual top producer
            0
        ) AS mismatch_flag
    FROM sites_1min_agg
    GROUP BY
        window_start,
        window_end;
    ```


### Preset

1. If you want to create your own dashboard, you can create a new account with a free trial
2. Log in then go to Settings > Database Creation > +Database > Clickhouse, where we need to configure the following SQL Alchemy URI: clickhousedb://<username>:<password>@<hostname>:<port>/<database>
    - In ClickHouse homepage choose Connect, which will display:
        - the <username> (e.g. "default")
        - the <hostname>:<port> (i.e. the https string, stripped of "https://")
        - the database user <password>, via the option to reset password
    - Go to the SQL Console and look at the database selector at the top to get the <database>
3. Now under Datasetes > +Datasets, we can select our ClickHouse data
    - Fill in remaining info, and get to work~
    
![stream-Preset.png](pics/preset_dashboard.png)