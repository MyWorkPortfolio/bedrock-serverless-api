#!/usr/bin/env bash
# probe-account.sh
# Finds out which regions and services this AWS account is allowed to use.
# It creates tiny test resources (an HTTP API, a Lambda function, an IAM role),
# deletes them straight away, and makes one very small Bedrock call per region.
# Cost: a fraction of a cent.
#
# Usage:  bash probe-account.sh                      (tests the default regions)
#         bash probe-account.sh eu-north-1 eu-west-1 (tests the regions you list)

set -u

REGIONS="${*:-us-east-1 us-west-2 eu-west-1 eu-central-1 eu-north-1}"
SUFFIX="$RANDOM"
ROLE_NAME="probe-lambda-role-$SUFFIX"
WORK="$(mktemp -d)"
ERR="$WORK/err"

reason() {
  if grep -qi "service control policy" "$ERR"; then
    echo "BLOCKED by organization SCP"
  elif grep -qi "AccessDenied" "$ERR"; then
    echo "DENIED (IAM permissions)"
  else
    echo "FAILED: $(tr '\n' ' ' < "$ERR" | cut -c1-160)"
  fi
}

cleanup() {
  aws iam delete-role --role-name "$ROLE_NAME" >/dev/null 2>&1
  rm -rf "$WORK"
}
trap cleanup EXIT

echo "Checking credentials..."
ACCOUNT="$(aws sts get-caller-identity --query Account --output text 2>"$ERR")" || {
  echo "Could not read credentials: $(cat "$ERR")"; exit 1; }
echo "Account: $ACCOUNT"
echo

# A throwaway role for the Lambda test (IAM is global).
cat > "$WORK/trust.json" <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}
EOF
ROLE_ARN="$(aws iam create-role --role-name "$ROLE_NAME" \
  --assume-role-policy-document "file://$WORK/trust.json" \
  --query Role.Arn --output text 2>"$ERR")"
if [ -n "$ROLE_ARN" ]; then
  echo "IAM create role ............ OK"
else
  echo "IAM create role ............ $(reason)"
fi

# A tiny function package, built with Python so 'zip' isn't required.
printf 'def handler(event, context):\n    return "ok"\n' > "$WORK/probe.py"
python3 -c "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1],'w'); z.write(sys.argv[2],'probe.py'); z.close()" \
  "$WORK/probe.zip" "$WORK/probe.py"

# Give IAM a few seconds so Lambda can assume the new role.
[ -n "$ROLE_ARN" ] && sleep 10

try_lambda() {  # $1 region, $2 "tags" or "none"
  local name="probe-$SUFFIX-$2" tagargs=()
  [ "$2" = "tags" ] && tagargs=(--tags Project=probe)
  for attempt in 1 2 3; do
    if aws lambda create-function --function-name "$name" --runtime python3.13 \
        --handler probe.handler --role "$ROLE_ARN" --zip-file "fileb://$WORK/probe.zip" \
        "${tagargs[@]}" --region "$1" >/dev/null 2>"$ERR"; then
      aws lambda delete-function --function-name "$name" --region "$1" >/dev/null 2>&1
      echo "OK"; return
    fi
    grep -qi "cannot be assumed" "$ERR" && { sleep 10; continue; }
    break
  done
  reason
}

try_api() {  # $1 region, $2 "tags" or "none"
  local id tagargs=()
  [ "$2" = "tags" ] && tagargs=(--tags Project=probe)
  id="$(aws apigatewayv2 create-api --name "probe-$SUFFIX" --protocol-type HTTP \
        "${tagargs[@]}" --region "$1" --query ApiId --output text 2>"$ERR")"
  if [ -n "$id" ]; then
    aws apigatewayv2 delete-api --api-id "$id" --region "$1" >/dev/null 2>&1
    echo "OK"
  else
    reason
  fi
}

try_bedrock() {  # $1 region
  local geo
  case "$1" in
    us-*) geo="us" ;;
    eu-*) geo="eu" ;;
    *)    geo="global" ;;
  esac
  if aws bedrock-runtime converse --model-id "$geo.amazon.nova-2-lite-v1:0" \
      --messages '[{"role":"user","content":[{"text":"Reply with OK"}]}]' \
      --inference-config '{"maxTokens":5}' \
      --region "$1" >/dev/null 2>"$ERR"; then
    echo "OK ($geo profile)"
  else
    reason
  fi
}

for r in $REGIONS; do
  echo
  echo "=== $r ==="
  echo "Bedrock (Nova 2 Lite) ....... $(try_bedrock "$r")"
  echo "API Gateway, no tags ........ $(try_api "$r" none)"
  echo "API Gateway, with tags ...... $(try_api "$r" tags)"
  if [ -n "$ROLE_ARN" ]; then
    echo "Lambda, no tags ............. $(try_lambda "$r" none)"
    echo "Lambda, with tags ........... $(try_lambda "$r" tags)"
  else
    echo "Lambda ...................... skipped (no IAM role)"
  fi
done

echo
echo "Done. Test resources have been deleted. Copy everything above and send it back."
