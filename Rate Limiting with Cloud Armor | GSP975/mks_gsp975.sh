echo "Set the correct environment: "
read -p "Enter the REGION_1: " REGION_1
read -p "Enter the REGION_2: " REGION_2
read -p "Enter the ZONE_3: " ZONE_3

gcloud auth list

gcloud services enable osconfig.googleapis.com

export REGION_3="${ZONE_3%-*}"

export PROJECT_ID=`gcloud config get-value project`

export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")

gcloud compute --project=$PROJECT_ID firewall-rules create default-allow-http --direction=INGRESS --priority=1000 --network=default --action=ALLOW --rules=tcp:80 --source-ranges=0.0.0.0/0 --target-tags=http-server

gcloud compute --project=$PROJECT_ID firewall-rules create default-allow-health-check --direction=INGRESS --priority=1000 --network=default --action=ALLOW --rules=tcp:80 --source-ranges=130.211.0.0/22,35.191.0.0/16 --target-tags=http-server

gcloud compute instance-templates create $REGION_1-template --project=$PROJECT_ID --machine-type=e2-medium --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=default --metadata=startup-script-url=gs://cloud-training/gcpnet/httplb/startup.sh,enable-oslogin=true --maintenance-policy=MIGRATE --provisioning-model=STANDARD --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/trace.append --region=$REGION_1 --tags=http-server --create-disk=auto-delete=yes,boot=yes,device-name=$REGION_1-template,image=projects/debian-cloud/global/images/debian-12-bookworm-v20250311,mode=rw,size=10,type=pd-balanced --no-shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring --reservation-affinity=any

gcloud compute instance-templates create $REGION_2-template --project=$PROJECT_ID --machine-type=e2-medium --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=default --metadata=startup-script-url=gs://cloud-training/gcpnet/httplb/startup.sh,enable-oslogin=true --maintenance-policy=MIGRATE --provisioning-model=STANDARD --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/trace.append --region=$REGION_2 --tags=http-server --create-disk=auto-delete=yes,boot=yes,device-name=$REGION_2-template,image=projects/debian-cloud/global/images/debian-12-bookworm-v20250311,mode=rw,size=10,type=pd-balanced --no-shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring --reservation-affinity=any

gcloud beta compute instance-groups managed create $REGION_1-mig --project=$PROJECT_ID --base-instance-name=$REGION_1-mig --template=projects/$PROJECT_ID/global/instanceTemplates/$REGION_1-template --size=1 --region=$REGION_1 --target-distribution-shape=EVEN --instance-redistribution-type=proactive --default-action-on-vm-failure=repair --no-force-update-on-repair --standby-policy-mode=manual --list-managed-instances-results=pageless && gcloud beta compute instance-groups managed set-autoscaling $REGION_1-mig --project=$PROJECT_ID --region=$REGION_1 --mode=on --min-num-replicas=1 --max-num-replicas=5 --target-cpu-utilization=0.8 --cpu-utilization-predictive-method=none --cool-down-period=45

gcloud beta compute instance-groups managed create $REGION_2-mig --project=$PROJECT_ID --base-instance-name=$REGION_2-mig --template=projects/$PROJECT_ID/global/instanceTemplates/$REGION_2-template --size=1 --region=$REGION_2 --target-distribution-shape=EVEN --instance-redistribution-type=proactive --default-action-on-vm-failure=repair --no-force-update-on-repair --standby-policy-mode=manual --list-managed-instances-results=pageless && gcloud beta compute instance-groups managed set-autoscaling $REGION_2-mig --project=$PROJECT_ID --region=$REGION_2 --mode=on --min-num-replicas=1 --max-num-replicas=5 --target-cpu-utilization=0.8 --cpu-utilization-predictive-method=none --cool-down-period=45
token=$(gcloud auth application-default print-access-token)
project_id=$(gcloud config get-value project)

curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $token" \
  -d '{
    "checkIntervalSec": 5,
    "description": "",
    "healthyThreshold": 2,
    "logConfig": {"enable": false},
    "name": "http-health-check",
    "tcpHealthCheck": {"port": 80, "proxyHeader": "NONE"},
    "timeoutSec": 5,
    "type": "TCP",
    "unhealthyThreshold": 2
  }' \
  "https://compute.googleapis.com/compute/beta/projects/$project_id/global/healthChecks"

sleep 10

curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $token" \
  -d '{
    "description": "Default security policy for: http-backend",
    "name": "default-security-policy-for-backend-service-http-backend",
    "rules": [
      {
        "action": "allow",
        "match": {"config": {"srcIpRanges": ["*"]}, "versionedExpr": "SRC_IPS_V1"},
        "priority": 2147483647
      },
      {
        "action": "throttle",
        "description": "Default rate limiting rule",
        "match": {"config": {"srcIpRanges": ["*"]}, "versionedExpr": "SRC_IPS_V1"},
        "priority": 2147483646,
        "rateLimitOptions": {"conformAction": "allow", "enforceOnKey": "IP", "exceedAction": "deny(403)", "rateLimitThreshold": {"count": 500, "intervalSec": 60}}
      }
    ]
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$project_id/global/securityPolicies"

sleep 10

curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $token" \
  -d '{
    "backends": [
      {"balancingMode": "RATE", "capacityScaler": 1, "group": "projects/'"$project_id"'/regions/'"$REGION_1"'/instanceGroups/'"$REGION_1"'-mig", "maxRatePerInstance": 50},
      {"balancingMode": "UTILIZATION", "capacityScaler": 1, "group": "projects/'"$project_id"'/regions/'"$REGION_2"'/instanceGroups/'"$REGION_2"'-mig", "maxRatePerInstance": 100, "maxUtilization": 0.8}
    ],
    "enableCDN": true,
    "healthChecks": ["projects/'"$project_id"'/global/healthChecks/http-health-check"],
    "loadBalancingScheme": "EXTERNAL_MANAGED",
    "name": "http-backend",
    "portName": "http",
    "protocol": "HTTP",
    "securityPolicy": "projects/'"$project_id"'/global/securityPolicies/default-security-policy-for-backend-service-http-backend",
    "sessionAffinity": "NONE",
    "timeoutSec": 30
  }' \
  "https://compute.googleapis.com/compute/beta/projects/$project_id/global/backendServices"

sleep 30

curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $token" \
  -d '{
    "defaultService": "projects/'"$project_id"'/global/backendServices/http-backend",
    "name": "http-lb"
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$project_id/global/urlMaps"

sleep 30

curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $token" \
  -d '{
    "name": "http-lb-target-proxy",
    "urlMap": "projects/'"$project_id"'/global/urlMaps/http-lb"
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$project_id/global/targetHttpProxies"

curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $token" \
  -d '{
    "name": "http-lb-target-proxy-2",
    "urlMap": "projects/'"$project_id"'/global/urlMaps/http-lb"
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$project_id/global/targetHttpProxies"

sleep 15

curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $token" \
  -d '{
    "IPProtocol": "TCP",
    "ipVersion": "IPV4",
    "loadBalancingScheme": "EXTERNAL_MANAGED",
    "name": "http-lb-forwarding-rule",
    "networkTier": "PREMIUM",
    "portRange": "80",
    "target": "projects/'"$project_id"'/global/targetHttpProxies/http-lb-target-proxy"
  }' \
  "https://compute.googleapis.com/compute/beta/projects/$project_id/global/forwardingRules"

sleep 10

curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $token" \
  -d '{
    "IPProtocol": "TCP",
    "ipVersion": "IPV6",
    "loadBalancingScheme": "EXTERNAL_MANAGED",
    "name": "http-lb-forwarding-rule-2",
    "networkTier": "PREMIUM",
    "portRange": "80",
    "target": "projects/'"$project_id"'/global/targetHttpProxies/http-lb-target-proxy-2"
  }' \
  "https://compute.googleapis.com/compute/beta/projects/$project_id/global/forwardingRules"

sleep 10

curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $token" \
  -d '{"namedPorts": [{"name": "http", "port": 80}]}' \
  "https://compute.googleapis.com/compute/beta/projects/$project_id/regions/$REGION_1/instanceGroups/$REGION_1-mig/setNamedPorts"

curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $token" \
  -d '{"namedPorts": [{"name": "http", "port": 80}]}' \
  "https://compute.googleapis.com/compute/beta/projects/$project_id/regions/$REGION_2/instanceGroups/$REGION_2-mig/setNamedPorts"

gcloud compute instances create siege-vm --project=$PROJECT_ID --zone=$ZONE_3 --machine-type=e2-medium --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=default --metadata=enable-osconfig=TRUE,enable-oslogin=true --maintenance-policy=MIGRATE --provisioning-model=STANDARD --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/trace.append --create-disk=auto-delete=yes,boot=yes,device-name=siege-vm,image=projects/debian-cloud/global/images/debian-12-bookworm-v20250311,mode=rw,size=10,type=pd-balanced --no-shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring --labels=goog-ops-agent-policy=v2-x86-template-1-4-0,goog-ec-src=vm_add-gcloud --reservation-affinity=any && printf 'agentsRule:\n  packageState: installed\n  version: latest\ninstanceFilter:\n  inclusionLabels:\n  - labels:\n      goog-ops-agent-policy: v2-x86-template-1-4-0\n' > config.yaml && gcloud compute instances ops-agents policies create goog-ops-agent-v2-x86-template-1-4-0-$ZONE_3 --project=$PROJECT_ID --zone=$ZONE_3 --file=config.yaml && gcloud compute resource-policies create snapshot-schedule default-schedule-1 --project=$PROJECT_ID --region=$REGION_3 --max-retention-days=14 --on-source-disk-delete=keep-auto-snapshots --daily-schedule --start-time=16:00 && gcloud compute disks add-resource-policies siege-vm --project=$PROJECT_ID --zone=$ZONE_3 --resource-policies=projects/$PROJECT_ID/regions/$REGION_3/resourcePolicies/default-schedule-1

sleep 10 

gcloud compute ssh --zone "$ZONE_3" "siege-vm" --project "$PROJECT_ID" --command "sudo apt-get -y install siege" --quiet

gcloud compute security-policies create rate-limit-siege \
    --description "policy for rate limiting"

gcloud beta compute security-policies rules create 100 \
    --security-policy=rate-limit-siege     \
    --expression="true" \
    --action=rate-based-ban                   \
    --rate-limit-threshold-count=50           \
    --rate-limit-threshold-interval-sec=120   \
    --ban-duration-sec=300           \
    --conform-action=allow           \
    --exceed-action=deny-404         \
    --enforce-on-key=IP

gcloud compute backend-services update http-backend \
    --security-policy rate-limit-siege --global