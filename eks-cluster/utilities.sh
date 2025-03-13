#!/bin/bash
print_message() { echo "***** $1 *****"; }

print_message "Defining required variables..."
CLUSTER_NAME="eks-cli-prac"
NODE_ROLE="eksctl-eks-cli-prac-nodegroup-ng1-NodeInstanceRole"
EBS_CSI_POLICY="arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
IAM_POLICY_NAME="AWSLoadBalancerControllerIAMPolicy"
REGION="ap-south-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
ALB_INGRESS_POLICY="arn:aws:iam::$AWS_ACCOUNT_ID:policy/$IAM_POLICY_NAME"

print_message "Checking if Metrics Server is already installed..."
if ! kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; then
    print_message "Applying the Metrics Server manifest..."
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
else
    print_message "Metrics Server is already installed. Skipping."
fi

print_message "Creating required namespaces if they don't exist..."
for ns in expense-yaml instana-yaml; do
    kubectl get ns "$ns" &>/dev/null || kubectl create ns "$ns"
done

print_message "Checking StorageClass existence..."
for sc in expense instana; do
    if ! kubectl get sc "$sc" &>/dev/null; then
        print_message "StorageClass $sc does not exist. Please create it if necessary."
    fi
done

print_message "Applying storage classes from volumes directory..."
if [ -d "../volumes" ]; then
    kubectl apply -f ../volumes
else
    print_message "Error: Directory '../volumes' not found!" >&2
    exit 1
fi

print_message "Checking and installing AWS EBS CSI Driver via Helm..."
if ! helm list -n kube-system --filter "^aws-ebs-csi-driver$" | grep -q "aws-ebs-csi-driver"; then
    helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
    helm repo update
    helm upgrade --install aws-ebs-csi-driver --namespace kube-system aws-ebs-csi-driver/aws-ebs-csi-driver
else
    print_message "EBS CSI driver is already installed."
fi

print_message "Verifying Node Role existence..."
NODE_ROLE_PREFIX=$(aws iam list-roles --query "Roles[?starts_with(RoleName, '$NODE_ROLE')].RoleName" --output text)
if [ -z "$NODE_ROLE_PREFIX" ] || [ "$NODE_ROLE_PREFIX" == "None" ]; then
    print_message "No IAM role found with name $NODE_ROLE. Exiting."
    exit 1
fi

print_message "Checking and adding Helm repository 'eks'..."
if ! helm repo list | grep -q "eks"; then
    helm repo add eks https://aws.github.io/eks-charts
    helm repo update
else
    print_message "Helm repository 'eks' already exists."
fi

print_message "Installing or updating AWS Load Balancer Controller..."
if helm list -n kube-system --filter "^aws-load-balancer-controller$" | grep -q "aws-load-balancer-controller"; then
    print_message "AWS Load Balancer Controller is already installed. Skipping."
else
    helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
        --set clusterName=$CLUSTER_NAME \
        -n kube-system \
        --set serviceAccount.create=false \
        --set serviceAccount.name=aws-load-balancer-controller
fi

print_message "Checking IAM policy existence: $IAM_POLICY_NAME..."
EXISTING_POLICY_ARN=$(aws iam list-policies --scope Local --query "Policies[?PolicyName=='$IAM_POLICY_NAME'].Arn" --output text)
if [ -z "$EXISTING_POLICY_ARN" ] || [ "$EXISTING_POLICY_ARN" == "None" ]; then
    print_message "Creating IAM policy: $IAM_POLICY_NAME..."
    POLICY_FILE="iam-policy.json"
    if [ ! -f "$POLICY_FILE" ]; then
        curl -o "$POLICY_FILE" https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
    fi
    aws iam create-policy --policy-name "$IAM_POLICY_NAME" --policy-document file://"$POLICY_FILE"
    rm -f "$POLICY_FILE"
else
    print_message "IAM policy $IAM_POLICY_NAME already exists."
fi

print_message "Checking IAM Service Account for AWS Load Balancer Controller..."
if eksctl get iamserviceaccount --cluster=$CLUSTER_NAME --name=aws-load-balancer-controller --namespace=kube-system >/dev/null 2>&1; then
    print_message "IAM Service Account already exists. Skipping."
else
    print_message "Creating IAM Service Account for AWS Load Balancer Controller..."
    eksctl create iamserviceaccount \
        --cluster=$CLUSTER_NAME \
        --namespace=kube-system \
        --name=aws-load-balancer-controller \
        --attach-policy-arn=$ALB_INGRESS_POLICY \
        --approve
fi

print_message "Setting up ExternalDNS IAM policy and Helm deployment..."
DNS_POLICY_NAME="ExternalDNSPolicy"
DNS_POLICY_ARN="arn:aws:iam::$AWS_ACCOUNT_ID:policy/$DNS_POLICY_NAME"

if aws iam list-policies --scope Local --query "Policies[?PolicyName=='$DNS_POLICY_NAME'].Arn" --output text | grep -q "$DNS_POLICY_NAME"; then
    print_message "IAM Policy $DNS_POLICY_NAME already exists."
else
    print_message "Creating IAM Policy $DNS_POLICY_NAME..."
    curl -o dns-policy.json https://raw.githubusercontent.com/kubernetes-sigs/external-dns/master/docs/tutorials/aws-iam-policy.json
    aws iam create-policy --policy-name $DNS_POLICY_NAME --policy-document file://dns-policy.json
    rm -f dns-policy.json
fi

print_message "Checking and creating ExternalDNS IAM Service Account..."
if eksctl get iamserviceaccount --cluster=$CLUSTER_NAME --name=external-dns --namespace=kube-system >/dev/null 2>&1; then
    print_message "IAM Service Account for ExternalDNS already exists. Skipping."
else
    eksctl create iamserviceaccount \
        --name external-dns \
        --namespace kube-system \
        --cluster $CLUSTER_NAME \
        --attach-policy-arn $DNS_POLICY_ARN \
        --approve
fi

print_message "Installing or upgrading ExternalDNS via Helm..."
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm repo update
helm upgrade --install external-dns external-dns/external-dns \
  --namespace kube-system \
  --set serviceAccount.name=external-dns \
  --set serviceAccount.create=false

print_message "Script execution completed successfully."
