#!/bin/bash

set -e
print_message() {
    echo "*****$1*****"
}

print_message "Define all required variable"
CLUSTER_NAME="eks-cli-prac"
NODE_ROLE="eks-cli-prac-nodegroup-ng1"
EBS_CSI_POLICY="arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
ALB_INGRESS_POLICY="arn:aws:iam::522814728660:policy/AWSLoadBalancerControllerIAMPolicy"
IAM_POLICY="AWSLoadBalancerControllerIAMPolicy"

print_message "Create namespaces if not exist"
for ns in expense-yaml instana-yaml; do
    if kubectl get ns "$ns" &>/dev/null; then
        echo "Namespace $ns already exists."
    else
        kubectl create ns "$ns"
        echo "Namespace $ns created successfully."
    fi
done


print_message "Checking storage classes existed or not"
for sc in expense instana; do
    if kubectl get sc "$sc" &>/dev/null; then
        echo "StorageClass $sc already exists. Skipping creation."
    fi
done

print_message "Checking volumes folder existence and create storage classes"
if [ -d "../volumes" ]; then
    echo "Applying StorageClass manifests from ../volumes..."
    kubectl apply -f ../volumes
    echo "StorageClass manifests applied successfully."
else
    echo "Error: Directory '../volumes' not found!" >&2
    exit 1
fi

print_message "Check for helm release for ebs-csi-driver installed if not create it."
if helm list -n kube-system --filter "^aws-ebs-csi-driver$" | grep -q "aws-ebs-csi-driver"; then
    echo "EBS CSI driver is already installed."
else
    echo "Installing EBS CSI driver..."
    helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
    helm repo update
    helm upgrade --install aws-ebs-csi-driver \
        --namespace kube-system \
        aws-ebs-csi-driver/aws-ebs-csi-driver
    echo "EBS CSI driver installed successfully."
fi

print_message "Querying for node instance role"
NODE_ROLE_PREFIX=$(aws iam list-roles --query "Roles[?contains(RoleName, '$NODE_ROLE')].RoleName" --output text)


print_message "Checking Node Existed or empty"
if [ -z "$NODE_ROLE_PREFIX" ] || [ "$NODE_ROLE_PREFIX" == "None" ]; then
    print_message "No IAM role found with the prefix $NODE_ROLE_PREFIX. Exiting."
    exit 1
fi


print_message "Ensuring EBS CSI Driver policy is attached to IAM Role $NODE_ROLE_PREFIX..."
if ! aws iam list-attached-role-policies --role-name "$NODE_ROLE_PREFIX" --query "AttachedPolicies[?PolicyArn=='$EBS_CSI_POLICY']" --output text | grep -q "$EBS_CSI_POLICY"; then
    aws iam attach-role-policy --role-name "$NODE_ROLE_PREFIX" --policy-arn "$EBS_CSI_POLICY"
else
    print_message "EBS CSI Driver policy already attached. Skipping."
fi


print_message "----Installing/Upgrading AWS Load Balancer Controller----"

# Add the EKS Helm repo if not already added
if ! helm repo list | grep -q "eks"; then
    helm repo add eks https://aws.github.io/eks-charts
fi
helm repo update

# Check if the AWS Load Balancer Controller is already installed
if helm list -n kube-system --filter "^aws-load-balancer-controller$" | grep -q "aws-load-balancer-controller"; then
    print_message "AWS Load Balancer Controller is already installed. Upgrading..."
else
    print_message "AWS Load Balancer Controller is not installed. Installing..."
fi

# Install or upgrade the Helm release
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
    --set clusterName=$CLUSTER_NAME \
    --namespace kube-system \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-load-balancer-controller

print_message "----AWS Load Balancer Controller installation/upgrade complete.----"


print_message "Ensuring AWS Load Balancer Controller IAM policy exists..."
if ! aws iam get-policy --policy-arn $ALB_INGRESS_POLICY/$IAM_POLICY >/dev/null 2>&1; then
    curl -o iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
    aws iam create-policy --policy-name $IAM_POLICY --policy-document file://iam-policy.json
else
    print_message "AWS Load Balancer Controller IAM policy already exists. Skipping."
fi


print_message "Creating IAM Service Account for AWS Load Balancer Controller..."
eksctl create iamserviceaccount \
    --cluster=$CLUSTER_NAME \
    --region=$REGION \
    --namespace=kube-system \
    --name=aws-load-balancer-controller \
    --attach-policy-arn=$ALB_INGRESS_POLICY/$IAM_POLICY \
    --approve || true






