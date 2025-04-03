#!/bin/bash

EBS_CSI_POLICY_ARN="arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
ECR_POLICY_ARN="arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"

echo  "Verifying Node Role existence..."
NODE_ROLE=$(aws iam list-roles --query "Roles[?contains(RoleName, 'eksctl-eks-cli-prac-nodegroup-ng1-NodeInstanceRole')].RoleName" --output text)

if [ -z "$NODE_ROLE" ] || [ "$NODE_ROLE" == "None" ]; then
    echo  "No IAM role found matching the pattern. Exiting."
else
    echo "Node Role found: $NODE_ROLE. Attaching policy..."
    aws iam attach-role-policy --role-name "$NODE_ROLE" --policy-arn "$EBS_CSI_POLICY_ARN"
    aws iam attach-role-policy --role-name "$NODE_ROLE" --policy-arn "$ECR_POLICY_ARN"
    echo "Policys attached successfully."
fi