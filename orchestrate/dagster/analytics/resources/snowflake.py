from dagster_snowflake import SnowflakeResource
import dagster as dg

snowflake_resource = SnowflakeResource(
    account=dg.EnvVar("SNOWFLAKE_ACCOUNT"),
    user=dg.EnvVar("SNOWFLAKE_USERNAME"),
    password=dg.EnvVar("SNOWFLAKE_PASSWORD"),
    warehouse="COMPUTE_WH",
    database="raw",
    schema="datacenters",
    role="ACCOUNTADMIN",
)