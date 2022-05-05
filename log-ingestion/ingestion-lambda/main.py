import os
import io
import gzip
import json
import re
import hashlib
import datetime
import boto3
from requests_aws4auth import AWS4Auth
from elasticsearch import Elasticsearch, RequestsHttpConnection
from elasticsearch import helpers as es_helpers

OPENSEARCH_ENDPOINT = os.environ["OPENSEARCH_ENDPOINT"]
ES_BULK_BATCH_SIZE = 1000

s3_client = boto3.client("s3")


def lambda_handler(event, context):
    print(f"INPUT: {json.dumps(event)}")

    es = create_es_client()

    for bucket_event in get_bucket_events(event):
        aws_region = bucket_event["aws_region"]
        bucket_name = bucket_event["bucket_name"]
        object_key = bucket_event["object_key"]

        if not re.search(r"/j-[\w]+/steps/s-[\w]+/std(out|err).gz", object_key):
            continue

        file_timestamp = get_file_timestamp(bucket_name, object_key)
        raw_logs = download_logs(bucket_name, object_key)
        total_count = len(raw_logs)
        print(f"Number of entries in the log: {total_count}")

        batch = []
        batch_number = 1
        skipped_entries_count = 0

        for line_number, line in enumerate(raw_logs, start=1):
            if not line.strip():
                skipped_entries_count += 1
            else:
                log_entry = transform_log(
                    line,
                    line_number,
                    file_timestamp,
                    object_key,
                    bucket_name,
                    aws_region,
                )
                batch.append(log_entry)

            if len(batch) >= ES_BULK_BATCH_SIZE or line_number == total_count:
                print(f"Saving batch {batch_number} containing {len(batch)} entries...")
                store_logs(batch, es)
                batch = []
                batch_number += 1

        if skipped_entries_count > 0:
            print(f"Skipped {skipped_entries_count} entries")


def get_bucket_events(event):
    for sqs_event in event["Records"]:
        if sqs_event.get("eventSource") == "aws:sqs":
            sqs_event_body = json.loads(sqs_event["body"])
            if (sqs_event_body.get("Event") != "s3:TestEvent") and ("Records" in sqs_event_body):
                for s3_event in sqs_event_body["Records"]:
                    if s3_event.get("eventSource") == "aws:s3":
                        yield {
                            "event_time": s3_event["eventTime"],
                            "aws_region": s3_event["awsRegion"],
                            "bucket_name": s3_event["s3"]["bucket"]["name"],
                            "object_key": s3_event["s3"]["object"]["key"],
                        }


def get_file_timestamp(bucket_name, object_key):
    response = s3_client.head_object(
        Bucket=bucket_name,
        Key=object_key,
    )

    return response["LastModified"]


def download_logs(bucket_name, object_key):
    # Download the *.gz file
    gz_file = io.BytesIO()
    s3_client.download_fileobj(bucket_name, object_key, gz_file)

    # Decompress
    gz_file.seek(0)
    log_file = gzip.GzipFile(fileobj=gz_file)

    # Decode into text
    log_content = log_file.read().decode("UTF-8")

    return log_content.splitlines()


def transform_log(raw_log, line_number, file_timestamp, object_key, bucket_name, aws_region):
    log_entry = {
        "raw_log": raw_log,
    }

    log_entry["log_file_line_number"] = line_number
    log_entry["log_file"] = f"s3://{bucket_name}/{object_key}"
    log_entry["log_file_timestamp"] = file_timestamp.isoformat()
    log_entry["aws_region"] = aws_region

    enrich_log(log_entry)

    return log_entry


def enrich_log(log_entry):
    # Extract EMR cluster/step ID from the file path
    re_match = re.search(f"/(j-[\w]+)/steps/(s-[\w]+)/", log_entry["log_file"])
    if re_match:
        log_entry["emr_cluster_id"] = re_match.group(1)
        log_entry["emr_step_id"] = re_match.group(2)
    else:
        re_match = re.search(f"/(j-[\w]+)/", log_entry["log_file"])
        if re_match:
            log_entry["emr_cluster_id"] = re_match.group(1)


def store_logs(logs, es_client):
    bulk_logs = [
        {
            "_index": f"emr-logs-{datetime.datetime.utcnow().date().isoformat()}",
            "_type": "emr_log",
            "_id": create_log_id(l),
            "_source": l,
        }
        for l in logs
    ]

    response = es_helpers.bulk(es_client, bulk_logs)
    print(f"RESPONSE: {response}")


def create_log_id(log_entry):
    raw_id = "{}|{}".format(log_entry["log_file"], log_entry["log_file_line_number"])
    return hashlib.sha256(bytes(raw_id.encode("utf-8"))).hexdigest()


def create_es_client():
    region = os.environ["AWS_REGION"]
    service = "es"
    credentials = boto3.Session().get_credentials()
    awsauth = AWS4Auth(
        credentials.access_key,
        credentials.secret_key,
        region,
        service,
        session_token=credentials.token,
    )

    return Elasticsearch(
        hosts=[{"host": OPENSEARCH_ENDPOINT, "port": 443}],
        http_auth=awsauth,
        use_ssl=True,
        verify_certs=True,
        connection_class=RequestsHttpConnection,
    )
