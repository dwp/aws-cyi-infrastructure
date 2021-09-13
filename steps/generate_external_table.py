import boto3
from zipfile import ZipFile
import gzip
import os
from datetime import date, timedelta, datetime
from io import BytesIO
from pyspark.sql import SparkSession
from steps.logger import setup_logging


class S3Decompressor:
    def __init__(self, s3_object, s3_key):
        self.decompressed_dict = self._unzip_s3_object(self, s3_object, s3_key)

    decompressed_dict = {}

    def _unzip_s3_object(self, s3_object, s3_key):
        """
        Description -- unzips given compressed s3 objects to dict
        :param s3_object: The object returned from boto3.resource('s3').Object(...) call
        :param s3_key: S3 key of object (String - "<s3_prefix>/<s3_object_name>")
        :return: Dict of all files in compressed file {file_name: file_body_byte_array}
        """
        file_type = s3_key.split('.')[-1]

        if file_type == "zip":
            return self._use_zip(s3_object, s3_key)
        elif file_type == "gzip":
            return self._use_gzip(s3_object, s3_key)
        else:
            print(f".{file_type} is an unsupported file compression type")
            print("Supported file types are: .zip and .gzip")

    def _use_zip(s3_object):
        """
        Description -- unzips .zip files from s3
        :param s3_object: The object returned from boto3.resource('s3').Object(...) call
        :return: Dict of all files in compressed file {file_name: file_body_byte_array}
        """
        buffer = BytesIO(s3_object.get()["Body"].read())
        zip_obj = ZipFile(buffer)

        return {file_name: zip_obj.open(file_name).read() for file_name in zip_obj.namelist()}

    def _use_gzip(s3_object, s3_key):
        """
        Description -- unzips .gz files from s3
        :param s3_object: The object returned from boto3.resource('s3').Object(...) call
        :param s3_key: S3 key of object (String - "<s3_prefix>/<s3_object_name>")
        :return: Dict of {file_name: file_body_byte_array}
        """
        s3_file_name = '.'.join(s3_key.split('/')[-1].split('.')[:2])

        with gzip.GzipFile(fileobj=s3_object.get()["Body"]) as gzipfile:
            body = gzipfile.read()

        return {s3_file_name: body}


class AwsCommunicator:
    def __init__(self):
        self.s3_resource = boto3.resource('s3')
        self.s3_client = boto3.client('s3')
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
            Body=file_body,
            Bucket=s3_bucket_name,
            Key=f'{s3_prefix}/{file_name}'
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

    def set_up_table_from_files(self, database_name, hive_table_name, file_location, correlation_id):
        """Sets up table external if it doesn't exist in given DB in a file location
        Keyword arguments:
        database_name -- the DB name for the table to sit in in hive
        hive_table_name -- the table name in hive
        file_location -- the location to hold the table data
        args --
        """

        src_hive_table = database_name + "." + hive_table_name
        src_hive_create_query = f"""CREATE EXTERNAL TABLE IF NOT EXISTS {src_hive_table}(val STRING) STORED AS TEXTFILE LOCATION "{file_location}" """

        the_logger.info(
            f"Creating table : {src_hive_table}" +
            f" for correlation id : {correlation_id}" if correlation_id else ""
        )
        try:
            self.spark_session.sql(src_hive_create_query)
            the_logger.info(
                f"Created table : {src_hive_table}" +
                f" for correlation id : {correlation_id}" if correlation_id else ""
            )
        except Exception as e:
            the_logger.info(
                f"Failed to create table : {src_hive_table}" +
                f" for correlation id : {correlation_id}" if correlation_id else ""
            )
            the_logger.error(e)


    # TODO: Sort this func. Example code from analytical env
    def set_up_temp_table_with_partition(self, spark, table_prefix, date, verified_database_name):
        # TODO: Create table such that it is unique for date, ie cyi_20210910

        date_underscore = date.strftime("%m_%d_%Y")
        table_name = table_prefix + date_underscore

        the_logger.info(f"Attempting to create temporary table '{table_name}'")

        src_managed_hive_create_query = f"""CREATE TABLE IF NOT EXISTS {table_name}(val STRING) PARTITIONED BY (date_str STRING) STORED AS orc TBLPROPERTIES ('orc.compress'='ZLIB')"""
        self.spark_session.sql(src_managed_hive_create_query)

        src_external_table = f'{args.database_name}_{date_underscore}'
        src_external_hive_table = verified_database_name + "." + src_external_table
        src_external_hive_create_query = f"""CREATE EXTERNAL TABLE {src_external_hive_table}(val STRING) PARTITIONED BY (date_str STRING) STORED AS TEXTFILE LOCATION "{collection_json_location}" """

        the_logger.info("hive create query %s", src_external_hive_create_query)
        src_external_hive_alter_query = f"""ALTER TABLE {src_external_hive_table} ADD IF NOT EXISTS PARTITION(date_str='{date_hyphen}') LOCATION '{collection_json_location}'"""
        src_external_hive_insert_query = f"""INSERT OVERWRITE TABLE {src_managed_hive_table} SELECT * FROM {src_external_hive_table}"""
        src_external_hive_drop_query = f"""DROP TABLE IF EXISTS {src_external_hive_table}"""

        self.spark_session(src_external_hive_create_query)
        self.spark_session(src_external_hive_alter_query)
        self.spark_session(src_external_hive_insert_query)
        self.spark_session(src_external_hive_drop_query)

        return table_name

    def merge_temp_table_with_main(self, temp_tbl, main_tbl):
        merge_temp_to_main = f"MERGE {main_tbl} AS TARGET USING {temp_tbl} AS SOURCE ON (TARGET.Date = SOURCE.Date)"

        try:
            self.spark_session.sql(merge_temp_to_main)
            the_logger.info(
                f"Merged table '{temp_tbl}' into '{main_tbl}' successfully"
            )
        except Exception as e:
            the_logger.error(
                f"Failed to merge table '{temp_tbl}' into '{main_tbl}'"
            )

    def cleanup_table(self, table_name):
        query = f"""DROP TABLE {table_name}"""

        self.spark_session.sql(query)


def get_dates_in_range(start_date, export_date) -> List[datetime]:
    start_date = datetime(start_date)
    export_date = datetime(export_date)

    days_difference = datetime(export_date) - datetime(start_date)
    days = days_difference.days

    dates = []
    for day in days:
        days - 1
        dates.append(export_date - timedelta(days = day))

    return dates


def create_metastore_db(
        spark,
        published_database_name,
        args,
):
    verified_database_name = published_database_name
    # Check to create database only if the backend is Aurora as Glue database is created through terraform
    if args.hive_metastore_backend == "aurora":
        try:
            the_logger.info(
                "Creating metastore db with name of %s while processing correlation_id %s",
                verified_database_name,
                args.correlation_id,
            )

            create_db_query = f"CREATE DATABASE IF NOT EXISTS {verified_database_name}"
            spark.sql(create_db_query)
        except BaseException as ex:
            the_logger.error(
                "Error occurred creating hive metastore backend %s",
                repr(ex),
            )
            raise BaseException(ex)

    return verified_database_name

def get_parameters():
    """Define and parse command line args."""
    parser = argparse.ArgumentParser(
        description="Receive args provided to spark submit job"
    )
    # Parse command line inputs and set defaults
    parser.add_argument("--correlation_id", default="NOT_SET")
    parser.add_argument("--s3_prefix", default="NOT_SET")
    parser.add_argument("--s3_bucket", default="NOT_SET")
    parser.add_argument("--export_date", default=date.today())
    parser.add_argument("--start_date", default="")
    parser.add_argument("--correlation_id", default="NOT_SET")

    # Terraform template values
    parser.add_argument("--database_name", default="${database_name}")
    parser.add_argument("--log_level", default="${log_level}")
    args.log_level = os.environ['LOG_LEVEL'].upper() if 'LOG_LEVEL' in os.environ else "${log_level}"
    parser.add_argument("--log_path", default="${log_path}")

    args.hive_metastore_backend = "${hive_metastore_backend}"
    args.hive_table_name = "${hive_table_name}"
    args.file_location = "${file_location}"
    args.published_bucket = "${published_bucket}"
    args.published_prefix = "${published_prefix}"
    args.published_s3_dir = "${published_s3_dir}"
    args.src_bucket = "${src_bucket}"

    return args


if __name__ == '__main__':
    args = get_parameters()

    the_logger = setup_logging(
        log_level=args.log_level.upper(),
        log_path=args.log_path
    )

    spark = PysparkJobRunner(args.database_name)
    aws = AwsCommunicator()

    spark.set_up_table_from_files(args.database_name, args.hive_table_name, args.file_location, args.correlation_id)
    aws.delete_existing_s3_files(args.published_bucket, args.published_prefix)

    if args.start_date:
        date_range = get_dates_in_range(args.start_date, args.export_date)
    else:
        date_range = [datetime(args.export_date)]

    verified_database_name = create_metastore_db(
        spark,
        args.database_name,
        args,
    )

    for date in date_range:
        date_str = datetime.strftime(date)
        s3_keys = aws.get_list_keys_for_prefix(args.src_bucket, f"{args.published_prefix}/{date_str}")

        for s3_key in s3_keys:
            decompressed_dict = S3Decompressor(args.src_bucket, s3_key).decompressed_dict

            for file_name in decompressed_dict:
                aws.upload_to_bucket(
                    file_name,
                    decompressed_dict[file_name],
                    args.published_bucket,
                    f"{args.published_s3_dir}/{args.database_name}/{date_str}"
                )

                temp_tbl = PysparkJobRunner.set_up_temp_table_with_partition(spark,
                                                                             table_prefix,
                                                                             args.export_date,
                                                                             verified_database_name)

                PysparkJobRunner.merge_temp_table_with_main(temp_tbl, args.database_name)

                PysparkJobRunner.clean_up_table(temp_tbl)

    the_logger.info(f"Completed import for export date '{args.export_date}'")
#   TODO: Make export of particular date in S3 fetch - Allow an export range. `start_date`
