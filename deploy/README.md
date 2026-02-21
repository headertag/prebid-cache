# Deploy Prebid Cache to Google Cloud Run

This guide walks through deploying Prebid Cache as a cost-optimized serverless service on Google Cloud Run with Upstash Redis for storage.

**Estimated cost:** $0–15/month (scales to zero when idle)

## Architecture

```
Internet → Cloud Run (free managed SSL) → prebid-cache container
                                              ↓
                                        Upstash Redis (serverless)
```

| Component | Monthly Cost | Notes |
|-----------|-------------|-------|
| Cloud Run | $0–5 | min-instances=0, scales to zero |
| Upstash Redis | $0–10 | Serverless pay-per-request |
| SSL Certificate | $0 | Google-managed, auto-renewing |
| Artifact Registry | $0 | 0.5GB free tier |
| **Total** | **$0–15** | |

## Prerequisites

1. **Google Cloud account** with billing enabled
2. **gcloud CLI** installed and authenticated (`gcloud auth login`)
3. **Docker** installed locally
4. **Upstash account** (free tier available at [upstash.com](https://upstash.com))

## Step 1: Set Up Upstash Redis

1. Sign up or log in at [console.upstash.com](https://console.upstash.com)
2. Click **Create Database**
3. Choose a name and select the region closest to your Cloud Run region (e.g., `us-central1` → US-East-1)
4. Select the **Free** plan to start
5. From the database details page, note:
   - **Endpoint** (e.g., `us1-example-12345.upstash.io`)
   - **Port** (typically `6379`)
   - **Password**

## Step 2: Set Up GCP Project

```bash
# Set your project
gcloud config set project YOUR_PROJECT_ID

# Enable required APIs
gcloud services enable run.googleapis.com artifactregistry.googleapis.com

# Create an Artifact Registry repository
gcloud artifacts repositories create prebid-cache \
  --repository-format=docker \
  --location=us-central1
```

## Step 3: Build & Deploy

### Option A: Using the deployment script (recommended)

```bash
cd prebid-cache

export GCP_PROJECT_ID=your-project-id
export REDIS_HOST=your-upstash-endpoint
export REDIS_PORT=6379
export REDIS_PASSWORD=your-upstash-password

# Optional: set a custom domain
export CUSTOM_DOMAIN=your-domain.com

./deploy/deploy.sh
```

### Option B: Manual deployment

```bash
cd prebid-cache

# Build the Docker image
docker build --build-arg TEST=false \
  -t us-central1-docker.pkg.dev/YOUR_PROJECT_ID/prebid-cache/prebid-cache:latest .

# Configure Docker for Artifact Registry
gcloud auth configure-docker us-central1-docker.pkg.dev

# Push the image
docker push us-central1-docker.pkg.dev/YOUR_PROJECT_ID/prebid-cache/prebid-cache:latest

# Deploy to Cloud Run
gcloud run deploy prebid-cache \
  --image us-central1-docker.pkg.dev/YOUR_PROJECT_ID/prebid-cache/prebid-cache:latest \
  --region us-central1 \
  --port 2424 \
  --memory 256Mi \
  --cpu 1 \
  --min-instances 0 \
  --max-instances 5 \
  --allow-unauthenticated \
  --set-env-vars "\
PBC_BACKEND_TYPE=redis,\
PBC_BACKEND_REDIS_HOST=YOUR_UPSTASH_HOST,\
PBC_BACKEND_REDIS_PORT=6379,\
PBC_BACKEND_REDIS_PASSWORD=YOUR_UPSTASH_PASSWORD,\
PBC_BACKEND_REDIS_TLS_ENABLED=true,\
PBC_REQUEST_LIMITS_MAX_TTL_SECONDS=10800"
```

## Step 4: Map a Custom Domain (Optional)

```bash
gcloud run domain-mappings create \
  --service prebid-cache \
  --domain your-domain.com \
  --region us-central1
```

The command will output DNS records to add at your domain registrar:

- For apex domains: Add the `A` and `AAAA` records shown
- For subdomains: Add the `CNAME` record shown

**SSL is automatic.** Cloud Run provisions a free Google-managed SSL certificate once DNS is verified. No Let's Encrypt setup is needed.

## Step 5: Verify

```bash
# Check the homepage
curl https://YOUR_SERVICE_URL/

# Store a test value
curl -X POST https://YOUR_SERVICE_URL/cache \
  -H "Content-Type: application/json" \
  -d '{"puts":[{"type":"json","value":{"test":true}}]}'

# Retrieve it
curl https://YOUR_SERVICE_URL/cache?uuid=RETURNED_UUID
```

## Configuration

Prebid Cache reads from `config.yaml` and environment variables prefixed with `PBC_`. Environment variables override config file values. The Cloud Run deployment uses `deploy/config-cloudrun.yaml` as the base config, with Redis credentials set via environment variables for security.

### Key environment variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PBC_BACKEND_TYPE` | Storage backend (`memory`, `redis`, etc.) | `memory` |
| `PBC_BACKEND_REDIS_HOST` | Redis hostname | — |
| `PBC_BACKEND_REDIS_PORT` | Redis port | `0` |
| `PBC_BACKEND_REDIS_PASSWORD` | Redis password | — |
| `PBC_BACKEND_REDIS_TLS_ENABLED` | Enable TLS for Redis | `false` |
| `PBC_REQUEST_LIMITS_MAX_TTL_SECONDS` | Maximum TTL for cached values | `3600` |

## Cost Monitoring

Set up a billing alert to avoid surprises:

```bash
# Create a budget alert (e.g., $20/month)
gcloud billing budgets create \
  --billing-account=YOUR_BILLING_ACCOUNT_ID \
  --display-name="Prebid Cache Budget" \
  --budget-amount=20 \
  --threshold-rule=percent=80 \
  --threshold-rule=percent=100
```

You can also monitor usage in the [Cloud Run console](https://console.cloud.google.com/run).

## Updating the Service

To deploy a new version:

```bash
# Rebuild and push
docker build --build-arg TEST=false -t IMAGE_URL .
docker push IMAGE_URL

# Redeploy (Cloud Run will do a rolling update)
gcloud run deploy prebid-cache \
  --image IMAGE_URL \
  --region us-central1
```

Cloud Run keeps the previous revision available for instant rollback:

```bash
gcloud run services update-traffic prebid-cache \
  --to-revisions=PREVIOUS_REVISION=100 \
  --region us-central1
```

## Scaling Configuration

The default settings (`--min-instances 0 --max-instances 5 --memory 256Mi`) are optimized for low-cost operation. Adjust based on your traffic:

| Traffic Level | min-instances | max-instances | Memory |
|---------------|--------------|---------------|--------|
| Low / Testing | 0 | 5 | 256Mi |
| Medium | 1 | 10 | 256Mi |
| High | 2 | 50 | 512Mi |

Setting `min-instances` to 1+ eliminates cold start latency but incurs a constant cost.
