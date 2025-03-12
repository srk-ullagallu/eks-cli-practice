#!/bin/bash

# Variables
CLUSTER_NAME="eks-cli-prac"
PROFILE="default"

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

# Delete EKS cluster
echo "Deleting EKS cluster..."
eksctl delete cluster --name=$CLUSTER_NAME --profile=$PROFILE

# End timer
end_time=$(date +%s)

# Calculate and print total elapsed time
echo "Total time taken to delete the cluster:"
elapsed_time $start_time $end_time
