import boto3
import gzip
import os
import logging
import sys
import argparse
import datetime as dt

from zipfile import ZipFile
from datetime import date, timedelta, datetime
from io import BytesIO
from pyspark.sql import SparkSession
from typing import List

the_logger = None


class CustomLogFormatter(logging.Formatter):
    converter = dt.datetime.fromtimestamp

    def formatTime(self, record, datefmt=None):
        ct = self.converter(record.created)
        if datefmt:
            s = ct.strftime(datefmt)
        else:
            t = ct.strftime("%Y-%m-%d %H:%M:%S")
            s = "%s.%03d" % (t, record.msecs)
        return s


class S3Decompressor:
    def __init__(self, s3_object, s3_key):
        self.decompressed_dict = self._unzip_s3_object(s3_object, s3_key)

    decompressed_dict = {}

    def _unzip_s3_object(self, s3_object, s3_key):
        """
        Description -- unzips given compressed s3 objects to dict
        :param s3_object: The object returned from boto3.resource('s3').Object(...) call
        :param s3_key: S3 key of object (String - "<s3_prefix>/<s3_object_name>")
        :return: Dict of all files in compressed file {file_name: file_body_byte_array}
        """
        file_type = s3_key.split(".")[-1]

        if file_type == "zip":
            return self._use_zip(s3_object)
        elif file_type == "gzip":
            return self._use_gzip(s3_object, s3_key)
        else:
            print(f".{file_type} is an unsupported file compression type")
            print("Supported file types are: .zip and .gzip")

    def _use_zip(self, s3_object):
        """
        Description -- unzips .zip files from s3
        :param s3_object: The object returned from boto3.resource('s3').Object(...) call
        :return: Dict of all files in compressed file {file_name: file_body_byte_array}
        """
        buffer = BytesIO(s3_object.get()["Body"].read())
        zip_obj = ZipFile(buffer)

        return {
            file_name: zip_obj.open(file_name).read()
            for file_name in zip_obj.namelist()
        }

    def _use_gzip(self, s3_object, s3_key):
        """
        Description -- unzips .gz files from s3
        :param s3_object: The object returned from boto3.resource('s3').Object(...) call
        :param s3_key: S3 key of object (String - "<s3_prefix>/<s3_object_name>")
        :return: Dict of {file_name: file_body_byte_array}
        """
        s3_file_name = ".".join(s3_key.split("/")[-1].split(".")[:2])

        with gzip.GzipFile(fileobj=s3_object.get()["Body"]) as gzipfile:
            body = gzipfile.read()

        return {s3_file_name: body}


class AwsCommunicator:
    def __init__(self):
        self.s3_resource = boto3.resource("s3")
        self.s3_client = boto3.client("s3")
        self.s3_bucket = None

    def _set_s3_bucket(self, s3_bucket_name):
        self.s3_bucket = self.s3_resource.Bucket(s3_bucket_name)

    def get_s3_object(self, s3_bucket_name, s3_key):
        if self.s3_bucket is None:
            self._set_s3_bucket(s3_bucket_name)

        return self.s3_resource.Object(bucket_name=s3_bucket_name, key=s3_key)

    def upload_to_bucket(self, file_name, file_body, s3_bucket_name, s3_prefix):
        """
        :param file_name: name of file to upload (key minus prefix in s3)
        :param file_body: body of file to upload
        :param s3_bucket_name: name of bucket to upload to
        :param s3_prefix: location in bucket to upload to
        :return: put_object response
        """
        return self.s3_client.put_object(
            Body=file_body, Bucket=s3_bucket_name, Key=f"{s3_prefix}/{file_name}"
        )

    def get_list_keys_for_prefix(self, s3_bucket, s3_prefix):
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
        paginator = self.s3_client.get_paginator("list_objects_v2")
        pages = paginator.paginate(Bucket=s3_bucket, Prefix=s3_prefix)
        for page in pages:
            if "Contents" in page:
                for obj in page["Contents"]:
                    keys.append(obj["Key"])
        if s3_prefix in keys:
            keys.remove(s3_prefix)
        return keys

    def delete_existing_s3_files(self, s3_bucket, s3_prefix):
        """Deletes files if exists in the given bucket and prefix
        Keyword arguments:
        s3_bucket -- the S3 bucket name
        s3_prefix -- the key to look for, could be a file path and key or simply a path
        """
        keys = self.get_list_keys_for_prefix(s3_bucket, s3_prefix)
        the_logger.info(
            "Retrieved '%s' keys from prefix '%s'",
            str(len(keys)),
            s3_prefix,
        )

        waiter = self.s3_client.get_waiter("object_not_exists")
        for key in keys:
            self.s3_client.delete_object(Bucket=s3_bucket, Key=key)
            waiter.wait(
                Bucket=s3_bucket, Key=key, WaiterConfig={"Delay": 1, "MaxAttempts": 10}
            )


class PysparkJobRunner:
    def __init__(self, database_name):
        self.spark_session = (
            SparkSession.builder.master("yarn")
            .config("spark.metrics.conf", "/opt/emr/metrics/metrics.properties")
            .config("spark.metrics.namespace", f"{database_name}")
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

    def set_up_table_from_files(
        self, database_name, managed_table_name, correlation_id
    ):
        """Sets up table external if it doesn't exist in given DB in a file location
        Keyword arguments:
        database_name -- the DB name for the table to sit in in hive
        managed_table_name -- the table name in hive
        correlation_id -- correlation ID for the run at hand
        """

        src_hive_table = database_name + "." + managed_table_name
        src_hive_create_query = f"""CREATE TABLE IF NOT EXISTS {src_hive_table}(val STRING) PARTITIONED BY (date_str STRING) STORED AS orc TBLPROPERTIES ('orc.compress'='ZLIB')"""

        the_logger.info(
            f"Creating table : {src_hive_table}"
            + f" for correlation id : {correlation_id}"
            if correlation_id
            else ""
        )
        try:
            self.spark_session.sql(src_hive_create_query)
            the_logger.info(
                f"Created table : {src_hive_table}"
                + f" for correlation id : {correlation_id}"
                if correlation_id
                else ""
            )
        except Exception as e:
            the_logger.info(
                f"Failed to create table : {src_hive_table}"
                + f" for correlation id : {correlation_id}"
                if correlation_id
                else ""
            )
            the_logger.error(e)

    def set_up_temp_table_with_partition(
        self, table_prefix, date, database_name, collection_json_location
    ):
        date_hyphen = date.strftime("%Y-%m-%d")
        table_name = table_prefix + "_external_" + date_hyphen
        temporary_table_name = database_name + "." + table_name

        the_logger.info(
            f"Attempting to create temporary table '{temporary_table_name}'"
        )

        external_hive_create_query = f'CREATE EXTERNAL TABLE {temporary_table_name}(val STRING) STORED AS TEXTFILE LOCATION "{collection_json_location}"'
        the_logger.info(f"Hive create query '{external_hive_create_query}'")
        external_hive_alter_query = f"""ALTER TABLE {temporary_table_name} ADD IF NOT EXISTS PARTITION(date_str='{date_hyphen}') LOCATION '{collection_json_location}'"""

        self.spark_session.sql(external_hive_create_query)
        self.spark_session.sql(external_hive_alter_query)

        return table_name

    def merge_temp_table_with_main(self, temp_tbl, main_database, main_database_tbl):

        try:
            insert_query = f"""INSERT OVERWRITE TABLE {main_database}.{temp_tbl} SELECT * FROM {main_database}.{main_database_tbl}"""

            self.spark_session.sql(insert_query)

            the_logger.info(
                f"Merged table '{temp_tbl}' into '{main_database_tbl}' successfully"
            )
        except Exception as e:
            the_logger.error(
                f"Failed to merge table '{temp_tbl}' into '{main_database_tbl}' with error '{e}'"
            )

    def cleanup_table(self, main_database, table_name):
        drop_query = f"""DROP TABLE IF EXISTS {main_database}.{temp_tbl}"""
        the_logger.info(f"Dropped table '{table_name}' successfully")
        self.spark_session.sql(drop_query)


def get_dates_in_range(start_date, export_date) -> List[datetime]:
    start_date = datetime(start_date)
    export_date = datetime(export_date)

    days_difference = datetime(export_date) - datetime(start_date)
    days = days_difference.days

    return [start_date + timedelta(days=i) for i in range(days + 1)]


def get_parameters():
    """Define and parse command line args."""
    parser = argparse.ArgumentParser(
        description="Receive args provided to spark submit job"
    )
    # Parse command line inputs and set defaults
    parser.add_argument("--correlation_id", default="NOT_SET")
    parser.add_argument("--export_date", default=datetime.now())
    parser.add_argument("--start_date", default="")

    # Terraform template values
    parser.add_argument("--database_name", default="${database_name}")
    parser.add_argument("--managed_table_name", default="$(managed_table_name}")
    parser.add_argument("--log_level", default="${log_level}")

    args, unrecognized_args = parser.parse_known_args()

    if len(unrecognized_args) > 0:
        the_logger.warning(
            "Unrecognized args %s found",
            unrecognized_args,
        )

    args.external_table_name = "${external_table_name}"
    args.managed_table_name = "${managed_table_name}"
    args.published_bucket = "${published_bucket}"
    args.src_bucket = "${src_bucket}"
    args.src_s3_prefix = "${src_s3_prefix}"
    args.table_prefix = "${table_prefix}"

    return args


def setup_logging(log_level):
    logger = logging.getLogger()
    for old_handler in logger.handlers:
        logger.removeHandler(old_handler)

    handler = logging.StreamHandler(sys.stdout)

    json_format = '{ "timestamp": "%(asctime)s", "log_level": "%(levelname)s", "message": "%(message)s" }'
    handler.setFormatter(CustomLogFormatter(json_format))
    logger.addHandler(handler)
    new_level = logging.getLevelName(log_level.upper())
    logger.setLevel(new_level)

    return logger


if __name__ == "__main__":
    the_logger = setup_logging(
        log_level=os.environ["LOG_LEVEL"].upper() if "LOG_LEVEL" in os.environ else "${log_level}",
    )

    args = get_parameters()

    spark = PysparkJobRunner(args.database_name)
    aws = AwsCommunicator()

    spark.set_up_table_from_files(
        args.database_name, args.managed_table_name, args.correlation_id
    )

    if args.start_date:
        date_range = get_dates_in_range(args.start_date, args.export_date)
    else:
        date_range = [datetime(args.export_date)]

    for date in date_range:
        date_str = datetime.strftime(date, "%Y-%m-%d")
        destination_prefix = (
            f"{args.published_bucket}/{args.database_name}/external/{date_str}"
        )

        aws.delete_existing_s3_files(args.published_bucket, destination_prefix)
        s3_keys = aws.get_list_keys_for_prefix(
            args.src_bucket, f"{args.src_s3_prefix}/{date_str}"
        )

        for s3_key in s3_keys:
            decompressed_dict = S3Decompressor(
                args.src_bucket, s3_key
            ).decompressed_dict

            for file_name in decompressed_dict:
                aws.upload_to_bucket(
                    file_name,
                    decompressed_dict[file_name],
                    args.published_bucket,
                    destination_prefix,
                )

                temp_tbl = spark.set_up_temp_table_with_partition(
                    args.table_prefix, date, args.database_name, destination_prefix
                )

                spark.merge_temp_table_with_main(
                    temp_tbl, args.database_name, args.external_table_name
                )

                spark.cleanup_table(args.database_name, temp_tbl)

    the_logger.info(f"Completed import for export date '{args.export_date}'")
