import argparse
import datetime as dt
import gzip
import json
import logging
import os
import sys

import boto3
import findspark

findspark.init()

from zipfile import ZipFile
from datetime import timedelta, datetime
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
    def __init__(self, file_name, file_body):
        self.decompressed_pair_list = self._unzip_s3_object(file_name, file_body)

    decompressed_pair_list = {}

    def _unzip_s3_object(self, file_name, file_body):
        file_type = file_name.split(".")[-1]

        if file_type == "zip":
            return self._use_zip(file_body=file_body)
        elif file_type == "gz":
            return self._use_gzip(file_name=file_name, file_body=file_body)
        else:
            print(f".{file_type} is an unsupported file compression type")
            print("Supported file types are: .zip, .gzip or .gz")

    def _use_zip(self, file_body):
        """
        Description -- unzips .zip files from s3
        :param s3_object: The object returned from boto3.resource('s3').Object(...) call
        :return: list of pairs for all files in compressed file [(file_name, file_body_byte_array) ...]
        """
        buffer = BytesIO(file_body.read())
        zip_obj = ZipFile(buffer)

        return [
            (decompressed_file_name, zip_obj.open(decompressed_file_name).read())
            for decompressed_file_name in zip_obj.namelist()
        ]

    def _use_gzip(self, file_body, file_name):
        """
        Description -- unzips .gz files from s3
        :param file_body: The streaming body object returned from boto3.client('s3').get_object(...) call
        :param file_name: S3 key of object without prefix
        :return: Dict of {file_name: file_body_byte_array}
        """
        with gzip.GzipFile(fileobj=file_body) as gzipfile:
            content = gzipfile.read()

        decompressed_file_name = file_name.replace('.gz', '')
        return [(decompressed_file_name, content)]


class AwsCommunicator:
    def __init__(self):
        self.s3_client = boto3.client("s3")
        self.sns_client = boto3.client("sns")

    s3_client = None
    s3_bucket = None
    sns_client = None

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
            "Looking for files in bucket : %s with prefix : %s",
            s3_bucket,
            s3_prefix,
        )
        keys = []
        paginator = self.s3_client.get_paginator("list_objects_v2")
        pages = paginator.paginate(Bucket=s3_bucket, Prefix=s3_prefix)
        for page in pages:
            if "Contents" in page:
                for obj in page["Contents"]:
                    key = obj["Key"]
                    if s3_prefix != key:
                        keys.append(key)
        the_logger.info(
            "Keys found : %s",
            keys
        )
        return keys

    def get_name_mapped_to_streaming_body_from_keys(self, s3_bucket, key_list):
        """ Gets names mapped to streaming body for list of keys
        :param s3_bucket: the bucket holding the objects described in the key_list
        :param key_list: list of keys in s3_bucket the get ["prefix/object.example", ...]
        :return: map of file name to streaming body of object
        """
        return {key.split('/')[-1]: self.get_body_for_key(s3_bucket, key) for key in key_list}

    def get_body_for_key(self, s3_bucket, key):
        """ Gets the body of the given s3 key
        :param s3_bucket: the bucket holding the object described in the key
        :param key: key in s3_bucket the get ["prefix/object.example", ...]
        :return: streaming body of object
        """
        return self.s3_client.get_object(Bucket=s3_bucket, Key=key)["Body"]

    def delete_existing_s3_files(self, s3_bucket, s3_prefix):
        """Deletes files if exists in the given bucket and prefix
        Keyword arguments:
        s3_bucket -- the S3 bucket name
        s3_prefix -- the key to look for, could be a file path and key or simply a path
        """
        the_logger.info("Deleting files in bucket '%s' for prefix '%s'")
        keys = self.get_list_keys_for_prefix(s3_bucket, s3_prefix)
        the_logger.info(
            "Retrieved '%s' keys to delete from prefix '%s'",
            str(len(keys)),
            s3_prefix,
        )

        waiter = self.s3_client.get_waiter("object_not_exists")
        for key in keys:
            self.s3_client.delete_object(Bucket=s3_bucket, Key=key)
            waiter.wait(
                Bucket=s3_bucket, Key=key, WaiterConfig={"Delay": 1, "MaxAttempts": 10}
            )

    def send_slack_alert(
            self,
            alert_arn,
            message,
            severity="High",
            notification_type="Warning"
    ):
        if not self.sns_client:
            self.sns_client = boto3.client("sns")
            alert_message = json.dumps(
                {
                    "severity": severity,
                    "notification_type": notification_type,
                    "title_text": message,
                }
            )
            self.sns_client.publish(
                TargetArn=alert_arn,
                Message=alert_message,
            )

class PysparkJobRunner:
    def __init__(self):
        self.spark_session = (
            SparkSession.builder.master("yarn")
            .config("spark.executor.heartbeatInterval", "300000")
            .config("spark.storage.blockManagerSlaveTimeoutMs", "500000")
            .config("spark.network.timeout", "500000")
            .config("spark.hadoop.fs.s3.maxRetries", "20")
            .config("spark.rpc.numRetries", "10")
            .config("spark.task.maxFailures", "10")
            .config("spark.scheduler.mode", "FAIR")
            .config("spark.sql.files.minPartitionNum", "1")
            .config("spark.hadoop.mapreduce.fileoutputcommitter.algorithm.version", "2")
            .appName("spike")
            .enableHiveSupport()
            .getOrCreate()
        )


    def create_database(
        self,
        database_name,
    ):
        """Creates the database if not exists"""

        create_db_query = f"CREATE DATABASE IF NOT EXISTS {database_name}"

        the_logger.info(
            f"Creating database"
        )
        try:
            self.spark_session.sql(create_db_query)
            the_logger.info(
                f"Created database"
            )
        except Exception as e:
            the_logger.info(
                f"Failed to create database"
            )
            the_logger.error(e)
            sys.exit(-1)


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
            sys.exit(-1)


    def set_up_temp_table_with_partition(
        self, table_name, date_hyphen, database_name, collection_json_location
    ):
        temporary_table_name = database_name + "." + table_name

        the_logger.info(
            f"Attempting to create temporary table '{temporary_table_name}'"
        )
        external_hive_create_query = f'CREATE EXTERNAL TABLE {temporary_table_name}(val STRING) PARTITIONED BY (date_str STRING) STORED AS TEXTFILE LOCATION "{collection_json_location}"'
        the_logger.info(f"Hive create query '{external_hive_create_query}'")
        external_hive_alter_query = f"""ALTER TABLE {temporary_table_name} ADD IF NOT EXISTS PARTITION(date_str='{date_hyphen}') LOCATION '{collection_json_location}'"""
        the_logger.info(f"Hive alter query '{external_hive_alter_query}'")

        self.spark_session.sql(external_hive_create_query)
        self.spark_session.sql(external_hive_alter_query)

    def merge_temp_table_with_main(self, temp_tbl, main_database, main_database_tbl):
        """Merges temporary table into main table, ensures main table is partitioned based on date and concatenates partition files so that its 1 file per partition.
            Keyword arguments:
            temp_tbl -- the name of the temp table
            main_database -- the database name
            main_database_tbl -- the table name
        """

        try:
            insert_query = f"""INSERT OVERWRITE TABLE {main_database}.{main_database_tbl} SELECT * FROM {main_database}.{temp_tbl} DISTRIBUTE BY date_str, FLOOR(RAND()*100.0)%3;"""
            self.spark_session.sql(insert_query)

            the_logger.info(
                f"Merged table '{temp_tbl}' into '{main_database_tbl}' successfully"
            )

        except Exception as e:
            the_logger.error(
                f"Failed to merge table '{temp_tbl}' into '{main_database_tbl}' with error '{e}'"
            )
            sys.exit(-1)

    def cleanup_table(self, main_database, table_name):
        table_full_name = f"{main_database}.{table_name}"
        the_logger.info(f"Dropping table '{table_full_name}'")
        drop_query = f"""DROP TABLE IF EXISTS {table_full_name}"""
        self.spark_session.sql(drop_query)
        the_logger.info(f"Dropped table '{table_full_name}' successfully")


def get_dates_in_range(start_date, export_date) -> List[datetime]:
    start_date_dt = datetime.strptime(start_date, "%Y-%m-%d")
    export_date_dt = datetime.strptime(export_date, "%Y-%m-%d")

    difference = export_date_dt - start_date_dt
    days = difference.days

    return [start_date_dt + timedelta(days=i) for i in range(days + 1)]


def get_parameters():
    """Define and parse command line args."""
    parser = argparse.ArgumentParser(
        description="Receive args provided to spark submit job"
    )
    # Parse command line inputs and set defaults
    parser.add_argument("--correlation_id", default="NOT_SET")
    parser.add_argument("--export_date", default=datetime.today().strftime("%Y-%m-%d"))
    parser.add_argument("--start_date", default="")

    # Terraform template values
    parser.add_argument("--database_name", default="${database_name}")
    parser.add_argument("--managed_table_name", default="${managed_table_name}")
    parser.add_argument("--log_level", default="${log_level}")

    args, unrecognized_args = parser.parse_known_args()

    if len(unrecognized_args) > 0:
        the_logger.warning(
            "Unrecognized args %s found",
            unrecognized_args,
        )

    args.external_table_name = "${external_table_name}"
    args.published_bucket = "${published_bucket}"
    args.src_bucket = "${src_bucket}"
    args.src_s3_prefix = "${src_s3_prefix}"
    args.table_prefix = "${table_prefix}"
    args.slack_alert_arn = "${slack_alert_arn}"

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

    the_logger.info(
        f"Args created : '{args}'"
    )

    spark = PysparkJobRunner()
    aws = AwsCommunicator()

    spark.create_database(args.database_name)

    spark.set_up_table_from_files(
        args.database_name, args.managed_table_name, args.correlation_id
    )

    if args.start_date:
        date_range = get_dates_in_range(args.start_date, args.export_date)
    else:
        date_range = [datetime.strptime(args.export_date, "%Y-%m-%d")]

    dates_processed = []
    dates_skipped = []
    for date in date_range:
        date_str = date.strftime("%Y-%m-%d")
        destination_prefix = (
            f"{args.database_name}/external/{date_str}"
        )

        aws.delete_existing_s3_files(args.published_bucket, destination_prefix)
        s3_keys = aws.get_list_keys_for_prefix(
            args.src_bucket, f"{args.src_s3_prefix}/{date_str}"
        )

        if not s3_keys:
            the_logger.warning(
                "No keys found to process in bucket : '%s', prefix : '%s'",
                args.src_bucket,
                args.src_s3_prefix,
            )
            dates_skipped.append(date_str)
            aws.send_slack_alert(
                alert_arn=args.slack_alert_arn,
                message=f"CYI Found no data for prefix: {date_str}"
            )
            continue

        s3_objects_map = aws.get_name_mapped_to_streaming_body_from_keys(
            key_list=s3_keys, s3_bucket=args.src_bucket
        )

        decompressed_pair_list = []
        for file_name in s3_objects_map.keys():
            decompressed_pair_list.extend(
                S3Decompressor(
                    file_name=file_name,
                    file_body=s3_objects_map[file_name]
                ).decompressed_pair_list
            )

        for pair in decompressed_pair_list:
            aws.upload_to_bucket(
                pair[0],
                pair[1],
                args.published_bucket,
                destination_prefix,
            )

        date_hyphen = date.strftime("%Y-%m-%d")
        temp_tbl = args.table_prefix + "_external_" + date_hyphen.replace('-', '_')

        spark.cleanup_table(args.database_name, temp_tbl)

        spark.set_up_temp_table_with_partition(
            temp_tbl, date_hyphen, args.database_name, f"s3://{args.published_bucket}/{destination_prefix}"
        )

        spark.merge_temp_table_with_main(
            temp_tbl, args.database_name, args.managed_table_name
        )

        spark.cleanup_table(args.database_name, temp_tbl)
        dates_processed.append(date_str)

    the_logger.info(f"Completed import for date(s): {', '.join(dates_processed)}")
    the_logger.info(
        f"Date(s) skipped (no files found): {', '.join(dates_skipped)}"
        if dates_skipped else "No dates skipped"
    )
