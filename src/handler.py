"""Lambda handler: forwards a prompt to Amazon Bedrock via the Converse API."""

import base64
import json
import logging
import os

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

MODEL_ID = os.environ["MODEL_ID"]
MAX_TOKENS = int(os.environ.get("MAX_TOKENS", "512"))
MAX_PROMPT_CHARS = int(os.environ.get("MAX_PROMPT_CHARS", "4000"))

# Created once per execution environment and reused across invocations.
# BEDROCK_REGION lets the function call Bedrock outside its own Region.
bedrock = boto3.client("bedrock-runtime", region_name=os.environ.get("BEDROCK_REGION"))


def _response(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def _parse_body(event):
    raw = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw).decode("utf-8")
    return json.loads(raw)


def lambda_handler(event, context):
    try:
        payload = _parse_body(event)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return _response(400, {"error": "Request body must be valid JSON."})

    prompt = payload.get("prompt")
    if not isinstance(prompt, str) or not prompt.strip():
        return _response(400, {"error": "Field 'prompt' is required."})
    if len(prompt) > MAX_PROMPT_CHARS:
        return _response(
            400, {"error": f"Prompt is longer than {MAX_PROMPT_CHARS} characters."}
        )

    try:
        result = bedrock.converse(
            modelId=MODEL_ID,
            messages=[{"role": "user", "content": [{"text": prompt}]}],
            inferenceConfig={"maxTokens": MAX_TOKENS, "temperature": 0.5},
        )
    except ClientError as err:
        code = err.response["Error"]["Code"]
        logger.error("Bedrock call failed: %s", code)
        status = 429 if code == "ThrottlingException" else 502
        return _response(status, {"error": "Model request failed.", "code": code})

    text = "".join(
        block.get("text", "") for block in result["output"]["message"]["content"]
    )
    usage = result.get("usage", {})
    logger.info(
        "model=%s inputTokens=%s outputTokens=%s",
        MODEL_ID,
        usage.get("inputTokens"),
        usage.get("outputTokens"),
    )

    return _response(
        200,
        {
            "response": text,
            "model": MODEL_ID,
            "stopReason": result.get("stopReason"),
            "usage": usage,
        },
    )
