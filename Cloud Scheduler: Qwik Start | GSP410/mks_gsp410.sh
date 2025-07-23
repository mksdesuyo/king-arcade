gcloud auth list

export REGION=$(gcloud compute project-info describe \
--format="value(commonInstanceMetadata.items[google-compute-default-region])")

gcloud config set compute/region $REGION

gcloud services enable cloudscheduler.googleapis.com --project=$DEVSHELL_PROJECT_ID
gcloud pubsub topics create cron-topic
gcloud pubsub subscriptions create cron-sub --topic cron-topic
