#!/bin/bash

# Variables
CLUSTER_NAME="eks-cli-prac"
REGION="ap-south-1"
PROFILE="default"
ZONES="ap-south-1a,ap-south-1b"

# Function to calculate elapsed time
elapsed_time() {
    local start=$1
    local end=$2
    local elapsed=$(( end - start ))
    local minutes=$(( elapsed / 60 ))
    local seconds=$(( elapsed % 60 ))
    printf "Elapsed time: %d minutes and %d seconds\n" $minutes $seconds
}

# Start timer
start_time=$(date +%s)

# Create EKS cluster"
eksctl create cluster --name $CLUSTER_NAME \
                      --region $REGION \
                      --zones $ZONES \
                      --profile $PROFILE \
                      --without-nodegroup \
                      --version 1.31
if [ $? -ne 0 ]; then
    echo "Error: Failed to create EKS cluster." 
    exit 1
fi

# Associate IAM OIDC provider
echo "Associating IAM OIDC provider..."
eksctl utils associate-iam-oidc-provider \
    --region $REGION \
    --cluster $CLUSTER_NAME \
    --profile $PROFILE \
    --approve
if [ $? -ne 0 ]; then
    echo "Error: Failed to associate IAM OIDC provider."
    exit 1
fi

# End timer
end_time=$(date +%s)

# Calculate and print elapsed time
elapsed_time $start_time $end_time