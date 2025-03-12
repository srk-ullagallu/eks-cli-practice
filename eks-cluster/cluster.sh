#!/bin/bash

# Variables
CLUSTER_NAME="ullagallu-bapatlas-site"
REGION="ap-south-1"
ZONES="ap-south-1a,ap-south-1b"
LOG_FILE="/tmp/eks_cluster_$(date +"%d-%m-%Y").log"

# Function to calculate elapsed time
elapsed_time() {
    local start=$1
    local end=$2
    local elapsed=$(( end - start ))
    local minutes=$(( elapsed / 60 ))
    local seconds=$(( elapsed % 60 ))
    printf "Elapsed time: %d minutes and %d seconds\n" $minutes $seconds | tee -a "$LOG_FILE"
}

# Start timer
start_time=$(date +%s)

# Create EKS cluster
echo "Creating EKS cluster..." | tee -a "$LOG_FILE"
eksctl create cluster --name $CLUSTER_NAME \
                      --region $REGION \
                      --zones $ZONES \
                      --profile $PROFILE \
                      --without-nodegroup &>>"$LOG_FILE"
if [ $? -ne 0 ]; then
    echo "Error: Failed to create EKS cluster." | tee -a "$LOG_FILE"
    exit 1
fi

# Associate IAM OIDC provider
echo "Associating IAM OIDC provider..." | tee -a "$LOG_FILE"
eksctl utils associate-iam-oidc-provider \
    --region $REGION \
    --cluster $CLUSTER_NAME \
    --profile $PROFILE \
    --approve &>>"$LOG_FILE"
if [ $? -ne 0 ]; then
    echo "Error: Failed to associate IAM OIDC provider." | tee -a "$LOG_FILE"
    exit 1
fi

# End timer
end_time=$(date +%s)

# Calculate and print elapsed time
elapsed_time $start_time $end_time
