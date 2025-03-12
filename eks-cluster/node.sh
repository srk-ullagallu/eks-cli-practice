#!/bin/bash

# Variables
CLUSTER_NAME="ullagallu-bapatlas-site"
REGION="ap-south-1"
NODEGROUP_NAME="ng1"
NODE_TYPE="t3a.medium"
NODES=6
NODES_MIN=1
NODES_MAX=8
NODE_VOLUME_SIZE=20
SSH_PUBLIC_KEY="~/.ssh/id_rsa.pub"
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

# Create nodegroup
eksctl create nodegroup --cluster=$CLUSTER_NAME \
                       --region=$REGION \
                       --name=$NODEGROUP_NAME \
                       --node-type=$NODE_TYPE \
                       --nodes=$NODES \
                       --nodes-min=$NODES_MIN \
                       --nodes-max=$NODES_MAX \
                       --node-volume-size=$NODE_VOLUME_SIZE \
                       --ssh-access \
                       --ssh-public-key=$SSH_PUBLIC_KEY \
                       --profile $PROFILE \
                       --managed \
                       --asg-access \
                       --external-dns-access \
                       --spot
if [ $? -ne 0 ]; then
    echo "Error: Failed to create nodegroup."
    exit 1
fi

# End timer
end_time=$(date +%s)

# Calculate and print elapsed time
elapsed_time $start_time $end_time