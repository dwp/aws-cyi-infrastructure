import unittest
from unittest.mock import patch
from steps import generate_external_table
from io import BytesIO

contents = [{"Contents": [{"Key": "Key1"},{"Key": "Key2"}]}]
no_contents = [{"NoContents": [{"Key": "Key1"},{"Key": "Key2"}]}]

class MockPaginator():
    def __init__(self, return_val):
        self.ret_val = return_val

    def paginate(self):
        return self.ret_val

class TestS3Decompressor(unittest.TestCase):

    def test_constructor_gz(self):
        bin = BytesIO(b'\x1f\x8b\x08\x08gz@a\x02\xffcyi_input.json\x00\xabV*I-.\x89\xcfN\xad4T\xb2R\x80p\xca\x12sJS\r\x95j\xb9\xaa\xe1\x92F\xa8\x92F@I\x00Ob\x9a\x8b:\x00\x00\x00')
        constructed_class = generate_external_table.S3Decompressor("test.gz", bin)
        self.assertEqual(constructed_class.decompressed_pair_list[0][0], 'test.gz')
        self.assertEqual(constructed_class.decompressed_pair_list[0][1], b'{"test_key1": "test_value1"}\n{"test_key2": "test_value2"}\n')

    def test_constructor_zip(self):
        bin = BytesIO(b'PK\x03\x04\x14\x00\x00\x00\x08\x00g{.SOb\x9a\x8b#\x00\x00\x00:\x00\x00\x00\x08\x00\x1c\x00test.txtUT\t\x00\x03A\xb1@aA\xb1@aux\x0b\x00\x01\x04\xf5\x01\x00\x00\x04\x14\x00\x00\x00\xabV*I-.\x89\xcfN\xad4T\xb2R\x80p\xca\x12sJS\r\x95j\xb9\xaa\xe1\x92F\xa8\x92F@I\x00PK\x01\x02\x1e\x03\x14\x00\x00\x00\x08\x00g{.SOb\x9a\x8b#\x00\x00\x00:\x00\x00\x00\x08\x00\x18\x00\x00\x00\x00\x00\x01\x00\x00\x00\xa4\x81\x00\x00\x00\x00test.txtUT\x05\x00\x03A\xb1@aux\x0b\x00\x01\x04\xf5\x01\x00\x00\x04\x14\x00\x00\x00PK\x05\x06\x00\x00\x00\x00\x01\x00\x01\x00N\x00\x00\x00e\x00\x00\x00\x00\x00')
        constructed_class = generate_external_table.S3Decompressor("test.zip", bin)
        self.assertEqual(constructed_class.decompressed_pair_list[0][0], 'test.txt')
        self.assertEqual(constructed_class.decompressed_pair_list[0][1], b'{"test_key1": "test_value1"}\n{"test_key2": "test_value2"}\n')


class TestAwsCommunicator(unittest.TestCase):

    @patch('steps.generate_external_table.boto3')
    def test_init(self, mock_boto):
        mock_boto.client.return_value= "s3_client"
        constructed_class = generate_external_table.AwsCommunicator()

        self.assertEqual(constructed_class.s3_client, "s3_client")
        self.assertEqual(constructed_class.s3_bucket, None)

    @patch('steps.generate_external_table.boto3')
    @patch('steps.generate_external_table.the_logger')
    @patch('steps.generate_external_table.AwsCommunicator.s3_client')
    def test_get_list_keys_for_prefix(self, mock_s3_client, mock_the_logger, mock_boto):
        mock_boto.return_value= None
        mock_the_logger.return_value= None
        mock_s3_client.get_paginator.return_value = MockPaginator(contents)
        constructed_class = generate_external_table.AwsCommunicator()
        keys = constructed_class.get_list_keys_for_prefix("test_s3", "test/prefix/")

        self.assertEqual(["Key1", "Key2"], keys)


if __name__ == '__main__':
    unittest.main()