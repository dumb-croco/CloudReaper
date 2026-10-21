import json
import logging
import os
import urllib.request
from datetime import datetime, timezone

import boto3

logger = logging.getLogger("cloudreaper")
logger.setLevel(logging.INFO)

GITHUB_OWNER = os.environ["GITHUB_OWNER"]
GITHUB_REPO = os.environ["GITHUB_REPO"]
GITHUB_SECRET_ARN = os.environ["GITHUB_SECRET_ARN"]
DISPATCH_EVENT_TYPE = "cloudreaper-destroy"


def handler(event, context):
    """Entry point invoked by EventBridge every 5 minutes."""
    logger.info("CloudReaper scan started")

    tagging_client = boto3.client("resourcegroupstaggingapi")
    now = datetime.now(timezone.utc)
    expired_projects = set()

    paginator = tagging_client.get_paginator("get_resources")
    page_iterator = paginator.paginate(
        TagFilters=[
            {
                "Key": "expiry_time",
                "Values": [],  # empty = match any value
            }
        ]
    )

    for page in page_iterator:
        for resource in page["ResourceTagMappingList"]:
            tags = {t["Key"]: t["Value"] for t in resource["Tags"]}

            expiry_str = tags.get("expiry_time")
            project = tags.get("project")

            if not expiry_str or not project:
                continue

            try:
                expiry_time = datetime.fromisoformat(expiry_str.replace("Z", "+00:00"))
            except (ValueError, AttributeError):
                logger.warning(
                    "Skipping resource %s — cannot parse expiry_time '%s'",
                    resource["ResourceARN"],
                    expiry_str,
                )
                continue

            if expiry_time <= now:
                expired_projects.add(project)
                logger.info(
                    "Expired resource found: %s (project=%s, expiry=%s)",
                    resource["ResourceARN"],
                    project,
                    expiry_str,
                )

    if not expired_projects:
        logger.info("No expired projects found — all clear")
        return {"statusCode": 200, "body": "No expired projects"}

    github_token = get_github_token()
    if not github_token:
        return {"statusCode": 500, "body": "Cannot retrieve GitHub token"}

    results = []
    for project in expired_projects:
        logger.info("Triggering destroy for project: %s", project)
        result = trigger_github_dispatch(project, github_token)
        results.append({"project": project, "status": result})

    return {
        "statusCode": 200,
        "body": json.dumps(results),
    }


def get_github_token():
    """Fetch the GitHub PAT from Secrets Manager."""
    try:
        sm = boto3.client("secretsmanager")
        resp = sm.get_secret_value(SecretId=GITHUB_SECRET_ARN)
        secret_string = resp["SecretString"]
        try:
            secret_dict = json.loads(secret_string)
            # Key-value secret — extract the first value
            return next(iter(secret_dict.values()))
        except (json.JSONDecodeError, StopIteration):
            # Plain string secret — return as-is
            return secret_string
    except Exception as exc:
        logger.error("Failed to retrieve GitHub token from Secrets Manager: %s", exc)
        return None


def trigger_github_dispatch(project, github_token):
    """Fire a repository_dispatch event on GitHub to trigger terraform destroy."""
    url = f"https://api.github.com/repos/{GITHUB_OWNER}/{GITHUB_REPO}/dispatches"
    payload = json.dumps({
        "event_type": DISPATCH_EVENT_TYPE,
        "client_payload": {"project": project},
    }).encode("utf-8")

    req = urllib.request.Request(
        url,
        data=payload,
        headers={
            "Authorization": f"token {github_token}",
            "Accept": "application/vnd.github.v3+json",
            "Content-Type": "application/json",
            "User-Agent": "CloudReaper-Scanner",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req) as resp:
            status = resp.status
            logger.info(
                "GitHub dispatch sent for project=%s — HTTP %s",
                project,
                status,
            )
            return f"ok: {status}"
    except urllib.error.HTTPError as exc:
        body = exc.read().decode() if exc.fp else ""
        logger.error(
            "GitHub dispatch failed for project=%s — HTTP %s: %s",
            project,
            exc.code,
            body,
        )
        return f"error: {exc.code}"
    except Exception as exc:
        logger.error("GitHub dispatch failed for project=%s — %s", project, exc)
        return f"error: {exc}"
