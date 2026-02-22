#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Deploy Prebid Cache to Google Cloud Run
# ============================================================================
#
# Prerequisites:
#   - gcloud CLI installed and authenticated
#   - An Upstash Redis database created
#
# Usage:
#   export GCP_PROJECT_ID=your-project-id
#   export REDIS_HOST=your-upstash-host
#   export REDIS_PORT=6379
#   export REDIS_PASSWORD=your-upstash-password
#   ./deploy/deploy.sh
#
# Optional environment variables:
#   REGION          - GCP region (default: us-central1)
#   SERVICE_NAME    - Cloud Run service name (default: prebid-cache)
#   MAX_INSTANCES   - Maximum Cloud Run instances (default: 5)
#   MEMORY          - Memory per instance (default: 256Mi)
#   CUSTOM_DOMAIN   - Custom domain to map (optional)
# ============================================================================

# Required variables
: "${GCP_PROJECT_ID:?Error: GCP_PROJECT_ID must be set}"
: "${REDIS_HOST:?Error: REDIS_HOST must be set}"
: "${REDIS_PORT:=6379}"
: "${REDIS_PASSWORD:?Error: REDIS_PASSWORD must be set}"

# Optional variables with defaults
REGION="${REGION:-us-central1}"
SERVICE_NAME="${SERVICE_NAME:-prebid-cache}"
MAX_INSTANCES="${MAX_INSTANCES:-5}"
MEMORY="${MEMORY:-256Mi}"
REPO_NAME="prebid-cache"

IMAGE="$REGION-docker.pkg.dev/$GCP_PROJECT_ID/$REPO_NAME/$SERVICE_NAME:latest"

echo "=== Prebid Cache Cloud Run Deployment ==="
echo "Project:    $GCP_PROJECT_ID"
echo "Region:     $REGION"
echo "Service:    $SERVICE_NAME"
echo "Image:      $IMAGE"
echo "Redis Host: $REDIS_HOST"
echo ""

# Step 1: Configure gcloud
echo "--- Configuring gcloud project ---"
gcloud config set project "$GCP_PROJECT_ID"

# Step 2: Enable required APIs
echo "--- Enabling required APIs ---"
gcloud services enable run.googleapis.com artifactregistry.googleapis.com cloudbuild.googleapis.com

# Step 3: Create Artifact Registry repo (ignore if exists)
echo "--- Ensuring Artifact Registry repository exists ---"
gcloud artifacts repositories create "$REPO_NAME" \
  --repository-format=docker \
  --location="$REGION" \
  2>/dev/null || echo "Repository already exists, continuing..."

# Step 4: Build image remotely with Cloud Build and push to Artifact Registry
echo "--- Building image with Cloud Build ---"
gcloud builds submit \
  --config=deploy/cloudbuild.yaml \
  --substitutions="_IMAGE=$IMAGE"

# Step 5: Deploy to Cloud Run
echo "--- Deploying to Cloud Run ---"
gcloud run deploy "$SERVICE_NAME" \
  --image "$IMAGE" \
  --region "$REGION" \
  --port 2424 \
  --memory "$MEMORY" \
  --cpu 1 \
  --min-instances 0 \
  --max-instances "$MAX_INSTANCES" \
  --allow-unauthenticated \
  --set-env-vars "\
PBC_BACKEND_TYPE=redis,\
PBC_BACKEND_REDIS_HOST=$REDIS_HOST,\
PBC_BACKEND_REDIS_PORT=$REDIS_PORT,\
PBC_BACKEND_REDIS_PASSWORD=$REDIS_PASSWORD,\
PBC_BACKEND_REDIS_TLS_ENABLED=true,\
PBC_REQUEST_LIMITS_MAX_TTL_SECONDS=10800,\
PBC_REQUEST_LIMITS_MAX_SIZE_BYTES=102400"

# Step 6: Get the service URL
SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" --region "$REGION" --format='value(status.url)')
echo ""
echo "=== Deployment complete ==="
echo "Service URL: $SERVICE_URL"

# Step 7: Map custom domain (optional)
if [ -n "${CUSTOM_DOMAIN:-}" ]; then
  echo ""
  echo "--- Mapping custom domain: $CUSTOM_DOMAIN ---"
  gcloud run domain-mappings create \
    --service "$SERVICE_NAME" \
    --domain "$CUSTOM_DOMAIN" \
    --region "$REGION" \
    2>/dev/null || echo "Domain mapping already exists or requires DNS verification."
  echo ""
  echo "Add the DNS records shown above to your domain registrar."
  echo "Cloud Run will automatically provision a Google-managed SSL certificate."
fi

echo ""
echo "=== Verify deployment ==="
echo "  curl $SERVICE_URL"
echo "  curl -X POST $SERVICE_URL/cache -H 'Content-Type: application/json' -d '{\"puts\":[{\"type\":\"json\",\"value\":{\"test\":true}}]}'"
