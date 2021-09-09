import argparse
import os
import datetime
from pyspark.sql import SparkSession
from steps.logger import setup_logging
import gzip
from io import BytesIO
import boto3
import threading

the_logger = setup_logging(
    log_level=os.environ["${log_level}"].upper() # TODO: pass in template arg
    if "${log_level}" in os.environ
    else "INFO",
    log_path="${log_path}", # TODO: pass in template arg
)


def get_parameters():
    """Define and parse command line args."""
    parser = argparse.ArgumentParser(
        description="Receive args provided to spark submit job"
    )
    # Parse command line inputs and set defaults
    parser.add_argument("--correlation_id", default="0")
    parser.add_argument("--s3_prefix", default="${s3_prefix}")
    parser.add_argument("--monitoring_topic_arn", default="${monitoring_topic_arn}")
    parser.add_argument("--export_date", default=datetime.now().strftime("%Y-%m-%d"))
    args = parser.parse_args()

    return args


def get_spark_session():
    spark = (
        SparkSession.builder.master("yarn")
            .config("spark.metrics.conf", "/opt/emr/metrics/metrics.properties")
            .config("spark.metrics.namespace", "${data_name}")  # TODO: pass in template arg
            .config("spark.executor.heartbeatInterval", "300000")
            .config("spark.storage.blockManagerSlaveTimeoutMs", "500000")
            .config("spark.network.timeout", "500000")
            .config("spark.hadoop.fs.s3.maxRetries", "20")
            .config("spark.rpc.numRetries", "10")
            .config("spark.task.maxFailures", "10")
            .config("spark.scheduler.mode", "FAIR")
            .config("spark.hadoop.mapreduce.fileoutputcommitter.algorithm.version", "2")
            .appName("spike")
            .enableHiveSupport()
            .getOrCreate()
    )
    return spark


def set_up_table_from_files(spark, database_name, hive_table_name, file_location, args):
    """Sets up table external if it doesn't exist in given DB in a file location
    Keyword arguments:
    spark -- the spark connection
    database_name -- the DB name for the table to sit in in hive
    hive_table_name -- the table name in hive
    file_location -- the location to hold the table data
    args --
    """
    src_hive_table = database_name + "." + hive_table_name
    src_hive_create_query = f"""CREATE EXTERNAL TABLE IF NOT EXISTS {src_hive_table}(val STRING) STORED AS TEXTFILE LOCATION "{file_location}" """

    the_logger.info(
        f"Creating table : {src_hive_table}" +
        f" for correlation id : {args.get('correlation_id')}" if args.get('correlation_id') else ""
    )
    try:
        spark.sql(src_hive_create_query)
        the_logger.info(
            f"Created table : {src_hive_table}" +
            f" for correlation id : {args.get('correlation_id')}" if args.get('correlation_id') else ""
        )
    except Exception as e:
        the_logger.info(
            f"Failed to create table : {src_hive_table}" +
            f" for correlation id : {args.get('correlation_id')}" if args.get('correlation_id') else ""
        )
        the_logger.error(e)


def get_list_keys_for_prefix(s3_client, s3_bucket, s3_prefix):
    """Returns a list of keys within the given prefix in the given S3 bucket
    Keyword arguments:
    s3_client -- S3 client
    s3_bucket -- the S3 bucket name
    s3_prefix -- the key to look for, could be a file path and key or simply a path
    """
    the_logger.info(
        "Looking for files to process in bucket : %s with prefix : %s",
        s3_bucket,
        s3_prefix,
    )
    keys = []
    paginator = s3_client.get_paginator("list_objects_v2")
    pages = paginator.paginate(Bucket=s3_bucket, Prefix=s3_prefix)
    for page in pages:
        if "Contents" in page:
            for obj in page["Contents"]:
                keys.append(obj["Key"])
    if s3_prefix in keys:
        keys.remove(s3_prefix)
    return keys


def delete_existing_s3_files(s3_bucket, s3_prefix, s3_client):
    """Deletes files if exists in the given bucket and prefix
    Keyword arguments:
    s3_bucket -- the S3 bucket name
    s3_prefix -- the key to look for, could be a file path and key or simply a path
    s3_client -- S3 client
    """
    keys = get_list_keys_for_prefix(s3_client, s3_bucket, s3_prefix)
    the_logger.info(
        "Retrieved '%s' keys from prefix '%s'",
        str(len(keys)),
        s3_prefix,
    )

    waiter = s3_client.get_waiter("object_not_exists")
    for key in keys:
        s3_client.delete_object(Bucket=s3_bucket, Key=key)
        waiter.wait(
            Bucket=s3_bucket, Key=key, WaiterConfig={"Delay": 1, "MaxAttempts": 10}
        )

def unzip_and_move_file(src_bucket, src_prefix, src_key, dest_bucket, dest_prefix):
    """ Moves file landed in S3 location and unzips it to new S3 location
    Keyword arguments:
    src_bucket -- the S3 bucket the zipped data is in
    src_prefix -- the S3 prefix in the src_bucket that the zipped data is in
    src_key -- the key of the object in the s3 prefix to target
    dest_bucket -- the S3 bucket the zipped data needs to land in unzipped
    dest_prefix -- the S3 prefix in the dest_bucket that the unzipped data needs to land in
    """
    s3_client=boto3.client('s3')

    waiter = s3_client.get_waiter("object_not_exists")

    s3_client.upload_fileobj(
        Fileobj=gzip.GzipFile(
            None,
            'rb',
            fileobj=BytesIO(
                s3_client.get_object(Bucket=src_bucket, Key=src_key)['Body'].read())
        ),
        Bucket=dest_bucket,
        Prefix=dest_prefix,
        Key=src_key
    )
    waiter.wait(
        Bucket=dest_bucket, Prefix=dest_prefix, Key=src_key, WaiterConfig={"Delay": 1, "MaxAttempts": 10}
    )


def threaded_unzip_and_move_files(s3_client, src_bucket, src_prefix, dest_bucket, dest_prefix):
    """ Moves all files landed within S3 prefix location and unzips them to new S3 location
    Keyword arguments:
    s3_client -- the s3 client to use for getting keys
    src_bucket -- the S3 bucket the zipped data is in
    src_prefix -- the S3 prefix in the src_bucket that the zipped data is in
    dest_bucket -- the S3 bucket the zipped data needs to land in unzipped
    dest_prefix -- the S3 prefix in the dest_bucket that the unzipped data needs to land in
    """
    s3_prefix_keys = get_list_keys_for_prefix(s3_client, src_bucket, src_prefix)

    for key in s3_prefix_keys:
        threading.Thread(target = unzip_and_move_file, args=(src_bucket, src_prefix, key, dest_bucket, dest_prefix)).start()


# Todo: work out how unzipping the files will work - are there multiple files in a zip, if so, should they be unzipped locally then uploaded to s3?
# Todo: find out if gzip is correct
# Todo: Set up main to run "Create external hive table" -> "Delete existing S3 files in published bucket" -> "unzip files" -> "upload to published bucket/date prefix" -> "Create a temp table for today's date"
# Todo: work out if s3_bucket/prefix/key is correct OR s3_bucket/key (key contains prefix?)
