#!/bin/bash

# Variables
CLUSTER_NAME="eks-cli-prac"
PROFILE="default"

# Delete EKS cluster
echo "Deleting EKS cluster..."
eksctl delete cluster --name=$CLUSTER_NAME --profile=$PROFILE
