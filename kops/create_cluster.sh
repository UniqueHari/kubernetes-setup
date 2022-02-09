#!/bin/bash

export PREFIX=test
export URL="k8s.local"
export AWS_REGION="us-east-1"

printf " Please specify a cluster name\n"
read CLUSTER_NAME
export KOPS_CONFIG_BUCKET=${PREFIX}.kops-${CLUSTER_NAME}.config
export K8_CONFIG_BUCKET=${PREFIX}.k8-${CLUSTER_NAME}.config

#Generate SSH key for cluster
ssh-keygen -t rsa -f ${PREFIX}-${CLUSTER_NAME}
export PUBLIC_SSH_KEY=./${PREFIX}-${CLUSTER_NAME}.pub


#Create S3 Buckets to store versions of configs
printf "Create S3 buckets for kops and kubernetes config\n"
aws s3 ls | grep $KOPS_CONFIG_BUCKET > /dev/null
if [ $? -eq 0 ]
then
  printf "Bucket already exists\n\n"
else
  chronic aws s3api create-bucket \
    --bucket $KOPS_CONFIG_BUCKET

  chronic aws s3api put-bucket-versioning \
    --bucket $KOPS_CONFIG_BUCKET \
    --versioning-configuration Status=Enabled
  printf "done creating $KOPS_CONFIG_BUCKET\n"
fi

printf "Creating S3 bucket for kubernetes config…"
aws s3 ls | grep $K8_CONFIG_BUCKET > /dev/null
if [ $? -eq 0 ]
then
  printf "Bucket already exists\n\n"
else
  chronic aws s3api create-bucket \
    --bucket $K8_CONFIG_BUCKET 

  chronic aws s3api put-bucket-versioning \
    --bucket $K8_CONFIG_BUCKET \
    --versioning-configuration Status=Enabled
  printf "done creating $K8_CONFIG_BUCKET \n"
fi

# Create IAM Resources
printf "\n Create IAM user and group for kops\n"
aws iam list-groups | grep kops > /dev/null
if [ $? -eq 0 ]
then
  printf "IAM group 'kops' already exists\n"
else
  chronic aws iam create-group --group-name kops
  printf "done creating IAM group kops\n"
fi

printf "Attaching IAM policies to kops usergroup…"
export policies="
AmazonEC2FullAccess
AmazonRoute53FullAccess
AmazonS3FullAccess
IAMFullAccess
AmazonVPCFullAccess
AmazonSQSFullAccess
AmazonEventBridgeFullAccess"

should_create_policy=false
for policy in $policies; do
  check_arn=$(aws iam list-attached-group-policies --group-name kops | jq --arg policy $policy '.AttachedPolicies[] | select(.PolicyName == $policy) | .PolicyName' > /dev/null)
  if [ "$check_arn" = "null" ]
  then
    $should_create_policy=true
    aws iam attach-group-policy --policy-arn "arn:aws:iam::aws:policy/$policy" --group-name kops;
  fi
done
if [ "$should_create_policy" = true ]
then
  printf "Created policiesl\n"
else
  printf "Policies already exist\n"
fi

aws iam list-users | grep kops > /dev/null
if [ $? -eq 0 ]
then
  printf "  IAM user 'kops' already exists\n"
else
  aws iam create-user --user-name kops
  aws iam add-user-to-group --user-name kops --group-name kops
  aws iam create-access-key --user-name kops
  printf "Done creating kops user and attached all required policies\n"
fi

# Create kops cluster #
printf "\n3️⃣  Create new kops cluster\n"
kops create cluster \
  --state s3://${KOPS_CONFIG_BUCKET} \
  --ssh-public-key $PUBLIC_SSH_KEY \
  --cloud aws \
  --zones ${AWS_REGION}a \
  --topology private \
  --networking calico \
  --master-size t2.micro \
  --node-size t2.micro \
  --node-count "3" \
  --master-count "3" \
  --yes \
  k8-${CLUSTER_NAME}.${URL}
printf " Successfully kicked off cluster creation, it can take some time until it is fully functional\n"