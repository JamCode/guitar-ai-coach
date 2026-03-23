# -*- coding: utf-8 -*-
import json


def handler(event, context):
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json; charset=utf-8"},
        "isBase64Encoded": False,
        "body": json.dumps({"message": "hello world"}),
    }
