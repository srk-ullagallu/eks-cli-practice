#!/bin/bash

set -e
print_message() {
    echo "*****$1*****"
}

print_message "Define all required variables"
AWS_ACCOUNT_ID="522814728660"
CLUSTER_NAME="eks-cli-prac"
NODE_ROLE="eks-cli-prac-nodegroup-ng1"
EBS_CSI_POLICY="arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
IAM_POLICY="AWSLoadBalancerControllerIAMPolicy"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
ALB_INGRESS_POLICY="arn:aws:iam::$AWS_ACCOUNT_ID:policy/$IAM_POLICY"
REGION="ap-south-1"

print_message "Create namespaces if not exist"
for ns in expense-yaml instana-yaml; do
    kubectl get ns "$ns" &>/dev/null || kubectl create ns "$ns"
done

print_message "Checking storage classes existence"
for sc in expense instana; do
    kubectl get sc "$sc" &>/dev/null || echo "StorageClass $sc does not exist. Proceeding..."
done

print_message "Checking volumes folder and applying storage classes"
if [ -d "../volumes" ]; then
    kubectl apply -f ../volumes
else
    echo "Error: Directory '../volumes' not found!" >&2
    exit 1
fi

print_message "Checking for Helm release: aws-ebs-csi-driver"
if ! helm list -n kube-system --filter "^aws-ebs-csi-driver$" | grep -q "aws-ebs-csi-driver"; then
    print_message "Installing EBS CSI driver..."
    helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
    helm repo update
    helm upgrade --install aws-ebs-csi-driver \
        --namespace kube-system \
        aws-ebs-csi-driver/aws-ebs-csi-driver
else
    print_message "EBS CSI driver is already installed."
fi

print_message "Querying for node instance role"
NODE_ROLE_PREFIX=$(aws iam list-roles --query "Roles[?contains(RoleName, '$NODE_ROLE')].RoleName" --output text)

print_message "Checking if Node Role exists"
if [ -z "$NODE_ROLE_PREFIX" ] || [ "$NODE_ROLE_PREFIX" == "None" ]; then
    print_message "No IAM role found with prefix $NODE_ROLE_PREFIX. Exiting."
    exit 1
fi

print_message "Ensuring EBS CSI Driver policy is attached to IAM Role"
if ! aws iam list-attached-role-policies --role-name "$NODE_ROLE_PREFIX" --query "AttachedPolicies[?PolicyArn=='$EBS_CSI_POLICY']" --output text | grep -q "$EBS_CSI_POLICY"; then
    aws iam attach-role-policy --role-name "$NODE_ROLE_PREFIX" --policy-arn "$EBS_CSI_POLICY"
else
    print_message "EBS CSI Driver policy already attached. Skipping."
fi

print_message "Installing/Upgrading AWS Load Balancer Controller"
if ! helm repo list | grep -q "eks"; then
    helm repo add eks https://aws.github.io/eks-charts
fi
helm repo update

if helm list -n kube-system --filter "^aws-load-balancer-controller$" | grep -q "aws-load-balancer-controller"; then
    print_message "AWS Load Balancer Controller is already installed. Upgrading..."
else
    print_message "AWS Load Balancer Controller is not installed. Installing..."
fi

print_message "Ensuring AWS Load Balancer Controller IAM policy exists..."
EXISTING_POLICY_ARN=$(aws iam list-policies --scope Local --query "Policies[?PolicyName=='$IAM_POLICY'].Arn" --output text)

if [ -z "$EXISTING_POLICY_ARN" ] || [ "$EXISTING_POLICY_ARN" == "None" ]; then
    print_message "Creating IAM policy..."
    curl -o iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
    aws iam create-policy --policy-name "$IAM_POLICY" --policy-document file://iam-policy.json
else
    print_message "IAM policy already exists. Skipping."
fi

print_message "Creating IAM Service Account for AWS Load Balancer Controller..."
eksctl get iamserviceaccount --cluster=$CLUSTER_NAME --name=aws-load-balancer-controller --namespace=kube-system &>/dev/null ||
eksctl create iamserviceaccount \
    --cluster=$CLUSTER_NAME \
    --region=$REGION \
    --namespace=kube-system \
    --name=aws-load-balancer-controller \
    --attach-policy-arn=$ALB_INGRESS_POLICY \
    --approve

print_message "Waiting for Service Account to be available in Kubernetes..."
sleep 20  # Add delay to allow time for Service Account to propagate

print_message "Verifying Service Account in Kubernetes..."
kubectl get sa aws-load-balancer-controller -n kube-system || {
    echo "ERROR: Service Account not found! Exiting..."
    exit 1
}

print_message "Installing/Upgrading AWS Load Balancer Controller..."
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
    --set clusterName=$CLUSTER_NAME \
    --namespace kube-system \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-load-balancer-controller


print_message "Script execution completed successfully."
