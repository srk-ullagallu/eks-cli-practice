#!/bin/bash

set -e
print_message() {
    echo "*****$1*****"
}

print_message "Define all required variables"
CLUSTER_NAME="eks-cli-prac"
NODE_ROLE="eks-cli-prac-nodegroup-ng1"
EBS_CSI_POLICY="arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
IAM_POLICY="AWSLoadBalancerControllerIAMPolicy"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
ALB_INGRESS_POLICY="arn:aws:iam::$AWS_ACCOUNT_ID:policy/$IAM_POLICY"
REGION="ap-south-1"
IAM_POLICY_NAME="AWSLoadBalancerControllerIAMPolicy"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
ALB_INGRESS_POLICY="arn:aws:iam::$AWS_ACCOUNT_ID:policy/$IAM_POLICY_NAME"

print_message "Checking if Metrics Server is already installed..."
if ! kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; then
    print_message "Applying the Metrics Server manifest file..."
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
else
    print_message "Metrics Server is already installed. Skipping apply."
fi


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

#!/bin/bash

set -e

print_message() {
    echo "***** $1 *****"
}

CLUSTER_NAME="eks-cli-prac"
REGION="ap-south-1"
AWS_ACCOUNT_ID=522814728660
IAM_POLICY_NAME="AWSLoadBalancerControllerIAMPolicy"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
ALB_INGRESS_POLICY="arn:aws:iam::$AWS_ACCOUNT_ID:policy/$IAM_POLICY_NAME"

# 1. Add Helm Repo if not exists
print_message "Checking if Helm repository 'eks' is already added..."
if ! helm repo list | grep -q "eks"; then
    helm repo add eks https://aws.github.io/eks-charts
    helm repo update
else
    print_message "Helm repository 'eks' already exists. Skipping add."
fi

# 2. Check if AWS Load Balancer Controller is installed
print_message "Checking if AWS Load Balancer Controller is installed..."
if helm list -n kube-system --filter "^aws-load-balancer-controller$" | grep -q "aws-load-balancer-controller"; then
    print_message "AWS Load Balancer Controller is already installed. Skipping installation."
else
    print_message "Installing AWS Load Balancer Controller..."
    helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
        --set clusterName=$CLUSTER_NAME \
        -n kube-system \
        --set serviceAccount.create=false \
        --set serviceAccount.name=aws-load-balancer-controller
fi

# 3. Check if IAM policy exists before creating it
print_message "Checking if IAM policy '$IAM_POLICY_NAME' exists..."
EXISTING_POLICY_ARN=$(aws iam list-policies --scope Local --query "Policies[?PolicyName=='$IAM_POLICY_NAME'].Arn" --output text)

if [ -z "$EXISTING_POLICY_ARN" ] || [ "$EXISTING_POLICY_ARN" == "None" ]; then
    print_message "Creating IAM policy '$IAM_POLICY_NAME'..."
    curl -o iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
    aws iam create-policy --policy-name "$IAM_POLICY_NAME" --policy-document file://iam-policy.json
else
    print_message "IAM policy '$IAM_POLICY_NAME' already exists. Skipping creation."
fi

# 4. Create IAM Service Account if not exists
print_message "Checking if IAM Service Account for AWS Load Balancer Controller exists..."
if eksctl get iamserviceaccount --cluster=$CLUSTER_NAME --name=aws-load-balancer-controller --namespace=kube-system >/dev/null 2>&1; then
    print_message "IAM Service Account already exists. Skipping creation."
else
    print_message "Creating IAM Service Account for AWS Load Balancer Controller..."
    eksctl create iamserviceaccount \
        --cluster=$CLUSTER_NAME \
        --namespace=kube-system \
        --name=aws-load-balancer-controller \
        --attach-policy-arn=$ALB_INGRESS_POLICY \
        --approve
fi
print_message "Script execution completed successfully."
