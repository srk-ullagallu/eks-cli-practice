#!/bin/bash

print_message() { 
    echo "--> $1"
    echo -e "\e[32m--->$1-->\e[0m"
}

package_installation() { 
    echo -e "\e[32m*******$1*******\e[0m"
}

package_installation "Defining required variables..."
CLUSTER_NAME="eks-cli-prac"
NODE_ROLE="eksctl-eks-cli-prac-nodegroup-ng1-NodeInstanceRole"
EBS_CSI_POLICY_ARN="arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
ALB_INGRESS_POLICY_ARN="arn:aws:iam::522814728660:policy/AWSLoadBalancerControllerIAMPolicy"
DNS_POLICY_ARN="arn:aws:iam::522814728660:policy/ExternalDNSPolicy"
REGION="ap-south-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
ECR_ARN="arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"


package_installation Check if IAM aws-load-balancer-controller service accounts exist before creating them
if ! eksctl get iamserviceaccount --cluster=$CLUSTER_NAME --namespace=kube-system --name=aws-load-balancer-controller >/dev/null 2>&1; then
  eksctl create iamserviceaccount \
    --cluster=$CLUSTER_NAME \
    --namespace=kube-system \
    --name=aws-load-balancer-controller \
    --attach-policy-arn=$ALB_INGRESS_POLICY_ARN \
    --approve
fi

package_installation Install or upgrade AWS Load Balancer Controller only if not installed
if ! helm status aws-load-balancer-controller -n kube-system >/dev/null 2>&1; then
  helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
    --set clusterName=$CLUSTER_NAME \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-load-balancer-controller \
    -n kube-system
else
  helm upgrade aws-load-balancer-controller eks/aws-load-balancer-controller \
    --set clusterName=$CLUSTER_NAME \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-load-balancer-controller \
    -n kube-system
fi

package_installation "Checking if Metrics Server is already installed..."
if ! kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; then
    print_message "Applying the Metrics Server manifest..."
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml || { print_message "Failed to apply Metrics Server manifest"; exit 1; }
else
    print_message "Metrics Server is already installed. Skipping."
fi

package_installation "Creating required namespaces if they don't exist..."
for ns in expense-yaml instana-yaml; do
    kubectl get ns "$ns" &>/dev/null || kubectl create ns "$ns" || { print_message "Failed to create namespace $ns"; exit 1; }
done

package_installation "Checking StorageClass existence..."
for sc in expense instana; do
    if ! kubectl get sc "$sc" &>/dev/null; then
        print_message "StorageClass $sc does not exist. Please create it if necessary."
    fi
done

package_installation "Applying storage classes from volumes directory..."
if [ -d "../volumes" ]; then
    kubectl apply -f ../volumes || { print_message "Failed to apply storage classes"; exit 1; }
else
    print_message "Error: Directory '../volumes' not found!" >&2
    exit 1
fi

package_installation "Checking and installing AWS EBS CSI Driver via Helm..."
if ! helm list -n kube-system --filter "^aws-ebs-csi-driver$" | grep -q "aws-ebs-csi-driver"; then
    helm upgrade --install aws-ebs-csi-driver --namespace kube-system aws-ebs-csi-driver/aws-ebs-csi-driver || { print_message "Failed to install EBS CSI driver"; exit 1; }
else
    print_message "EBS CSI driver is already installed."
fi

package_installation "Verifying Node Role existence..."
NODE_ROLE=$(aws iam list-roles --query "Roles[?contains(RoleName, 'eksctl-eks-cli-prac-nodegroup-ng1-NodeInstanceRole')].RoleName" --output text)

if [ -z "$NODE_ROLE" ] || [ "$NODE_ROLE" == "None" ]; then
    print_message "No IAM role found matching the pattern. Exiting."
    exit 1
else
    print_message "Node Role found: $NODE_ROLE. Attaching policy..."
    aws iam attach-role-policy --role-name "$NODE_ROLE" --policy-arn "$EBS_CSI_POLICY_ARN" || { print_message "Failed to attach policy"; exit 1; }
    aws iam attach-role-policy --role-name "$NODE_ROLE" --policy-arn "$ECR_ARN" || { print_message "Failed to attach policy"; exit 1; }
    print_message "Policys attached successfully."
fi


package_installation package_installation Check if IAM external-dns service accounts exist before creating them
if ! eksctl get iamserviceaccount --cluster=$CLUSTER_NAME --namespace=kube-system --name=external-dns >/dev/null 2>&1; then
  eksctl create iamserviceaccount \
    --cluster=$CLUSTER_NAME \
    --namespace=kube-system \
    --name=external-dns \
    --attach-policy-arn=$DNS_POLICY_ARN \
    --approve
fi

package_installation Install or upgrade External DNS only if not installed
if ! helm status external-dns -n kube-system >/dev/null 2>&1; then
  helm install external-dns external-dns/external-dns \
    --set serviceAccount.create=false \
    --set serviceAccount.name=external-dns \
    -n kube-system
else
  helm upgrade external-dns external-dns/external-dns \
    --set serviceAccount.create=false \
    --set serviceAccount.name=external-dns \
    -n kube-system
fi


