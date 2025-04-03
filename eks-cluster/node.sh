#!/bin/bash

# Variables
CLUSTER_NAME="eks-cli-prac"
REGION="ap-south-1"
NODEGROUP_NAME="ng1"
NODE_TYPE="t3a.medium"
NODES=2
NODES_MIN=1
NODES_MAX=2
NODE_VOLUME_SIZE=20
SSH_PUBLIC_KEY="~/.ssh/id_rsa.pub"
PROFILE="default"


# Function to calculate elapsed time


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
                       --managed
