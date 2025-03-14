#!/bin/bash


print_message() { 
    echo  $1; }
package_installtion() { 
    echo "*******$1******";
}

package_installtion "Defining required variables..."
CLUSTER_NAME="eks-cli-prac"
NODE_ROLE="eksctl-eks-cli-prac-nodegroup-ng1-NodeInstanceRole"
EBS_CSI_POLICY_ARN="arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
EBS_POLICY_NAME="AWSLoadBalancerControllerIAMPolicy"
REGION="ap-south-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
ALB_INGRESS_POLICY_ARN="arn:aws:iam::522814728660:policy/AWSLoadBalancerControllerIAMPolicy"
DNS_POLICY_ARN="arn:aws:iam::522814728660:policy/ExternalDNSPolicy"
PROFILE="default"

package_installtion "Checking if Metrics Server is already installed..."
if ! kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; then
    print_message "Applying the Metrics Server manifest..."
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
else
    print_message "Metrics Server is already installed. Skipping."
fi

package_installtion "Creating required namespaces if they don't exist..."
for ns in expense-yaml instana-yaml; do
    kubectl get ns "$ns" &>/dev/null || kubectl create ns "$ns"
done

package_installtion "Checking StorageClass existence..."
for sc in expense instana; do
    if ! kubectl get sc "$sc" &>/dev/null; then
        print_message "StorageClass $sc does not exist. Please create it if necessary."
    fi
done

package_installtion "Applying storage classes from volumes directory..."
if [ -d "../volumes" ]; then
    kubectl apply -f ../volumes
else
    print_message "Error: Directory '../volumes' not found!" >&2
    exit 1
fi

package_installtion "Checking and installing AWS EBS CSI Driver via Helm..."
if ! helm list -n kube-system --filter "^aws-ebs-csi-driver$" | grep -q "aws-ebs-csi-driver"; then
    helm upgrade --install aws-ebs-csi-driver --namespace kube-system aws-ebs-csi-driver/aws-ebs-csi-driver
else
    print_message "EBS CSI driver is already installed."
fi

package_installtion "Verifying Node Role existence..."

# Fetch the exact role name dynamically
NODE_ROLE=$(aws iam list-roles --query "Roles[?contains(RoleName, 'eksctl-eks-cli-prac-nodegroup-ng1-NodeInstanceRole')].RoleName" --output text)

if [ -z "$NODE_ROLE" ] || [ "$NODE_ROLE" == "None" ]; then
    print_message "No IAM role found matching the pattern. Exiting."
else
    print_message "Node Role found: $NODE_ROLE. Attaching policy..."
    aws iam attach-role-policy --role-name "$NODE_ROLE" --policy-arn "$EBS_CSI_POLICY_ARN"
    
    if [ $? -eq 0 ]; then
        print_message "Policy attached successfully."
    else
        print_message "Failed to attach policy."
    fi
fi

package_installtion "Checking IAM Service Account for AWS Load Balancer Controller..."
if eksctl get iamserviceaccount --cluster=$CLUSTER_NAME --name=aws-load-balancer-controller --namespace=kube-system >/dev/null 2>&1; then
    print_message "IAM Service Account already exists. Skipping."
else
    print_message "Creating IAM Service Account for AWS Load Balancer Controller..."
    eksctl create iamserviceaccount \
    --cluster=$CLUSTER_NAME \
    --namespace=kube-system \
    --name=aws-load-balancer-controller \
    --attach-policy-arn=$ALB_INGRESS_POLICY_ARN \
    --approve \
    --override-existing-serviceaccounts
fi

package_installtion "Installing or updating AWS Load Balancer Controller..."
if helm status aws-load-balancer-controller -n kube-system >/dev/null 2>&1; then
    print_message "AWS Load Balancer Controller is already installed. Skipping."
else
    helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
        --set clusterName=$CLUSTER_NAME \
        --namespace kube-system\
        --set serviceAccount.create=false \
        --set serviceAccount.name=aws-load-balancer-controller
    sleep 10  # Wait for webhook initialization
fi

package_installtion "Checking and creating ExternalDNS IAM Service Account..."
if eksctl get iamserviceaccount --cluster=$CLUSTER_NAME --name=external-dns --namespace=kube-system >/dev/null 2>&1; then
    print_message "IAM Service Account for ExternalDNS already exists. Skipping."
else
    eksctl create iamserviceaccount \
        --name=external-dns \
        --namespace=kube-system \
        --cluster=$CLUSTER_NAME \
        --attach-policy-arn=$DNS_POLICY_ARN \
        --approve \
        --override-existing-serviceaccounts
fi

print_message "Installing or upgrading ExternalDNS via Helm..."
helm upgrade --install external-dns external-dns/external-dns \
  --namespace kube-system \
  --set serviceAccount.name=external-dns \
  --set serviceAccount.create=false

print_message "Script execution completed successfully."
