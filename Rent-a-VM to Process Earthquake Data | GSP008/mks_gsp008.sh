gcloud auth list

export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")

export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

export PROJECT_ID=$(gcloud config get-value project)

gcloud config set compute/zone "$ZONE"
gcloud config set compute/region "$REGION"

gcloud compute instances --project="$DEVSHELL_PROJECT_ID" create instance-1 --zone="$ZONE" --machine-type=e2-medium --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=default --metadata=enable-oslogin=true --maintenance-policy=MIGRATE --provisioning-model=STANDARD --scopes=https://www.googleapis.com/auth/cloud-platform --create-disk=auto-delete=yes,boot=yes,device-name=instance-1,image-family=debian-11,image-project=debian-cloud,mode=rw,size=10,type=projects/$DEVSHELL_PROJECT_ID/zones/$ZONE/diskTypes/pd-balanced --no-shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring --labels=goog-ec-src=vm_add-gcloud --reservation-affinity=any

gcloud storage buckets create gs://$PROJECT_ID --project=$DEVSHELL_PROJECT_ID --location=$REGION --uniform-bucket-level-access

cat > cp_disk.sh <<'EOF_CP'

cat /proc/cpuinfo

sudo apt-get update

sudo apt-get -y -qq install git

echo "Y" | sudo apt-get install python-mpltoolkits.basemap

sudo apt install python3-pip -y

pip install --upgrade basemap basemap-data basemap-data-hires pyproj

pip install matplotlib==3.3.4  numpy==1.23.5

git --version

git clone https://github.com/GoogleCloudPlatform/training-data-analyst

cd training-data-analyst/CPB100/lab2b

bash ingest.sh

bash install_missing.sh

python3 transform.py

ls -l


PROJECT_ID=$(gcloud config get-value project)
for file in earthquakes.*; do
  gsutil cp "$file" gs://${PROJECT_ID}/earthquakes/
done

EOF_CP

gcloud compute scp cp_disk.sh instance-1:/tmp --project=$DEVSHELL_PROJECT_ID --zone=$ZONE --quiet

gcloud compute ssh instance-1 --project=$DEVSHELL_PROJECT_ID --zone=$ZONE --quiet --command="bash /tmp/cp_disk.sh"
