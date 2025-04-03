#!/bin/bash

# Variables
CLUSTER_NAME="eks-cli-prac"
REGION="ap-south-1"
PROFILE="default"
ZONES="ap-south-1a,ap-south-1b"

# Create EKS cluster"
eksctl create cluster --name $CLUSTER_NAME \
                      --region $REGION \
                      --zones $ZONES \
                      --profile $PROFILE \
                      --without-nodegroup \
                      --version 1.31

# Associate IAM OIDC provider
echo "Associating IAM OIDC provider..."
eksctl utils associate-iam-oidc-provider \
    --region $REGION \
    --cluster $CLUSTER_NAME \
    --profile $PROFILE \
    --approve
