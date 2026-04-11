#!/bin/bash
set -e

echo "=========================================="
echo "AWS Load Balancer Controller Setup"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to install eksctl
install_eksctl() {
    echo -e "${YELLOW}Installing eksctl...${NC}"
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
            brew tap weaveworks/tap
            brew install weaveworks/tap/eksctl
        else
            echo -e "${RED}Homebrew not found. Installing eksctl manually...${NC}"
            curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Darwin_amd64.tar.gz"
            tar -xzf eksctl_Darwin_amd64.tar.gz -C /tmp
            sudo mv /tmp/eksctl /usr/local/bin
            rm eksctl_Darwin_amd64.tar.gz
        fi
    else
        # Linux
        ARCH=$(uname -m)
        if [ "$ARCH" = "x86_64" ]; then
            ARCH="amd64"
        elif [ "$ARCH" = "aarch64" ]; then
            ARCH="arm64"
        fi
        curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_${ARCH}.tar.gz"
        tar -xzf "eksctl_Linux_${ARCH}.tar.gz" -C /tmp
        sudo mv /tmp/eksctl /usr/local/bin
        rm "eksctl_Linux_${ARCH}.tar.gz"
    fi
    
    if command -v eksctl &> /dev/null; then
        echo -e "${GREEN}eksctl installed successfully: $(eksctl version)${NC}"
    else
        echo -e "${RED}Failed to install eksctl${NC}"
        exit 1
    fi
}

# Function to install jq
install_jq() {
    echo -e "${YELLOW}Installing jq...${NC}"
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &> /dev/null; then
            brew install jq
        else
            echo -e "${RED}Please install jq manually: https://stedolan.github.io/jq/download/${NC}"
            exit 1
        fi
    else
        # Linux - try common package managers
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y jq
        elif command -v yum &> /dev/null; then
            sudo yum install -y jq
        elif command -v apk &> /dev/null; then
            sudo apk add jq
        else
            echo -e "${RED}Please install jq manually: https://stedolan.github.io/jq/download/${NC}"
            exit 1
        fi
    fi
    
    if command -v jq &> /dev/null; then
        echo -e "${GREEN}jq installed successfully${NC}"
    else
        echo -e "${RED}Failed to install jq${NC}"
        exit 1
    fi
}

# Check prerequisites
echo -e "\n${YELLOW}Checking prerequisites...${NC}"

# Required tools that must be pre-installed
for cmd in aws kubectl; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}$cmd is not installed. Please install it first.${NC}"
        exit 1
    fi
done

# Tools we can auto-install
if ! command -v eksctl &> /dev/null; then
    echo -e "${YELLOW}eksctl not found.${NC}"
    install_eksctl
fi

if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}jq not found.${NC}"
    install_jq
fi

echo -e "${GREEN}Prerequisites OK${NC}"

# Auto-detect cluster info
echo -e "\n${YELLOW}Detecting cluster information...${NC}"

# Get cluster name from current context
CURRENT_CONTEXT=$(kubectl config current-context)
echo "Current kubectl context: $CURRENT_CONTEXT"

# Try to extract cluster name and region from the context
# EKS contexts are usually in format: arn:aws:eks:REGION:ACCOUNT:cluster/CLUSTER_NAME
if [[ "$CURRENT_CONTEXT" == arn:aws:eks:* ]]; then
    CLUSTER_NAME=$(echo "$CURRENT_CONTEXT" | awk -F'/' '{print $NF}')
    DETECTED_REGION=$(echo "$CURRENT_CONTEXT" | cut -d: -f4)
else
    # Try simpler format or custom context name
    CLUSTER_NAME=$(echo "$CURRENT_CONTEXT" | sed 's/.*\///' | sed 's/@.*//')
fi

echo "Detected cluster name: $CLUSTER_NAME"

# Determine region (priority: detected from context > AWS_REGION env > AWS CLI config)
if [ -n "$DETECTED_REGION" ]; then
    REGION="$DETECTED_REGION"
    echo "Region from context: $REGION"
elif [ -n "$AWS_REGION" ]; then
    REGION="$AWS_REGION"
    echo "Region from AWS_REGION env: $REGION"
elif [ -n "$AWS_DEFAULT_REGION" ]; then
    REGION="$AWS_DEFAULT_REGION"
    echo "Region from AWS_DEFAULT_REGION env: $REGION"
else
    REGION=$(aws configure get region 2>/dev/null || echo "")
    if [ -z "$REGION" ]; then
        echo -e "${RED}Could not determine AWS region.${NC}"
        echo "Please set AWS_REGION environment variable or configure AWS CLI region."
        echo "Example: export AWS_REGION=eu-west-1"
        exit 1
    fi
    echo "Region from AWS CLI config: $REGION"
fi

# Verify cluster exists and get info from AWS
echo "Looking for EKS cluster '$CLUSTER_NAME' in region '$REGION'..."
CLUSTER_INFO=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" 2>&1) || {
    echo -e "${RED}Could not find EKS cluster: $CLUSTER_NAME in region: $REGION${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Verify cluster exists: aws eks list-clusters --region $REGION"
    echo "  2. Try different region: AWS_REGION=<region> $0"
    echo "  3. Check AWS credentials: aws sts get-caller-identity"
    echo ""
    echo "AWS error: $CLUSTER_INFO"
    exit 1
}

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
VPC_ID=$(echo "$CLUSTER_INFO" | jq -r '.cluster.resourcesVpcConfig.vpcId')
OIDC_ISSUER=$(echo "$CLUSTER_INFO" | jq -r '.cluster.identity.oidc.issuer' | sed 's|https://||')

echo -e "${GREEN}Cluster Name: $CLUSTER_NAME${NC}"
echo -e "${GREEN}Account ID:   $ACCOUNT_ID${NC}"
echo -e "${GREEN}Region:       $REGION${NC}"
echo -e "${GREEN}VPC ID:       $VPC_ID${NC}"
echo -e "${GREEN}OIDC Issuer:  $OIDC_ISSUER${NC}"

# Step 1: Create OIDC provider if not exists
echo -e "\n${YELLOW}Step 1: Setting up IAM OIDC provider...${NC}"

OIDC_PROVIDER_ARN=$(aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?ends_with(Arn, '${OIDC_ISSUER}')].Arn" --output text)

if [ -z "$OIDC_PROVIDER_ARN" ] || [ "$OIDC_PROVIDER_ARN" == "None" ]; then
    echo "Creating OIDC provider..."
    eksctl utils associate-iam-oidc-provider \
        --cluster "$CLUSTER_NAME" \
        --region "$REGION" \
        --approve
    echo -e "${GREEN}OIDC provider created${NC}"
else
    echo -e "${GREEN}OIDC provider already exists${NC}"
fi

# Step 2: Create IAM policy if not exists
echo -e "\n${YELLOW}Step 2: Creating IAM policy...${NC}"

POLICY_NAME="AWSLoadBalancerControllerIAMPolicy"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

if aws iam get-policy --policy-arn "$POLICY_ARN" &>/dev/null; then
    echo -e "${GREEN}IAM policy already exists${NC}"
else
    echo "Downloading IAM policy document..."
    curl -sS -o /tmp/iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.1/docs/install/iam_policy.json
    
    echo "Creating IAM policy..."
    aws iam create-policy \
        --policy-name "$POLICY_NAME" \
        --policy-document file:///tmp/iam-policy.json \
        --description "IAM policy for AWS Load Balancer Controller"
    
    rm /tmp/iam-policy.json
    echo -e "${GREEN}IAM policy created${NC}"
fi

# Step 3: Create IAM role and service account
echo -e "\n${YELLOW}Step 3: Creating IAM role and service account...${NC}"

ROLE_NAME="AWSLoadBalancerControllerRole"

# Check if the service account already exists with the correct annotation
SA_ANNOTATION=$(kubectl get sa aws-load-balancer-controller -n kube-system -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || echo "")

if [ -n "$SA_ANNOTATION" ]; then
    echo -e "${GREEN}Service account already exists with IAM role${NC}"
else
    echo "Creating IAM role and service account..."
    eksctl create iamserviceaccount \
        --cluster="$CLUSTER_NAME" \
        --region="$REGION" \
        --namespace=kube-system \
        --name=aws-load-balancer-controller \
        --role-name="$ROLE_NAME" \
        --attach-policy-arn="$POLICY_ARN" \
        --override-existing-serviceaccounts \
        --approve
    echo -e "${GREEN}IAM role and service account created${NC}"
fi

# Step 4: Update the ArgoCD application file
echo -e "\n${YELLOW}Step 4: Updating ArgoCD application configuration...${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_FILE="$SCRIPT_DIR/../k8s/argocd-apps/applications/aws-load-balancer-controller.yaml"

if [ -f "$APP_FILE" ]; then
    # Use sed to replace placeholders
    sed -i.bak \
        -e "s/YOUR_CLUSTER_NAME/$CLUSTER_NAME/g" \
        -e "s/YOUR_ACCOUNT_ID/$ACCOUNT_ID/g" \
        -e "s/YOUR_REGION/$REGION/g" \
        -e "s/YOUR_VPC_ID/$VPC_ID/g" \
        "$APP_FILE"
    rm -f "${APP_FILE}.bak"
    echo -e "${GREEN}Application file updated${NC}"
else
    echo -e "${RED}Application file not found: $APP_FILE${NC}"
    exit 1
fi

echo -e "\n${GREEN}=========================================="
echo "AWS Load Balancer Controller setup complete!"
echo "==========================================${NC}"

echo -e "\n${YELLOW}Next steps:${NC}"
echo "1. Commit the updated aws-load-balancer-controller.yaml"
echo "2. Run: ./scripts/bootstrap.sh"
echo "   Or if ArgoCD is already running:"
echo "   kubectl apply --server-side --force-conflicts -k k8s/argocd-apps/"

echo -e "\n${YELLOW}Configuration applied:${NC}"
echo "  Cluster:    $CLUSTER_NAME"
echo "  Account:    $ACCOUNT_ID"
echo "  Region:     $REGION"
echo "  VPC:        $VPC_ID"
echo "  IAM Role:   arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
