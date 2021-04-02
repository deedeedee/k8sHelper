#
# 1. Install 'kubectl'
#
 
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client
 
#
# 2. Install 'eksctl' which is an AWS officially supported open source tool and makes the job easy
#
 
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
eksctl version
 
#
# 3. Install 'helm'
#
 
export VERIFY_CHECKSUM=false
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
chmod 700 get_helm.sh
 ./get_helm.sh
 
#
# 4. init variable
$

unique_string=$RANDOM
cluster_name=cluster-for-accelerator-$unique_string
aws_region=eu-west-1
node_count=1

#
# 5. start a k8s cluster using command eksctl
#

eksctl create cluster --name $cluster_name --nodes $node_count --region $aws_region


################### Create a service account in the cluster


#
# 1. init
#

SERVICE_ACCOUNT_NAME="accelerator-webapp-account"
CLUSTER_ROLE_NAME="accelerator-webapp-access-role"
CLUSTER_ROLE_BINDING_NAME=$SERVICE_ACCOUNT_NAME:$CLUSTER_ROLE_NAME

#
# 2. Create a service account
#

kubectl create serviceaccount $SERVICE_ACCOUNT_NAME

#
# 3. Create ClusterRole
# Role for the service account that will be used to access k8s via. REST API
# you can also put following content in yaml instead of applying inline. 
#

kubectl apply -f - <<!
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: $CLUSTER_ROLE_NAME
rules:
# For role escalation problem. the REST API should be able to grant permission to the service account service-update so make sure these permissions below > permission setting in REST call
- apiGroups: ["apps", ""] 
  resources: ["pods", "services", "deployments", ]
  verbs: ["get", "watch", "list", "create", "update", "patch", "delete" ]
# Required to create role and rolebinding to enable K8s discovery for TIBCO Streaming. 
- apiGroups: ["rbac.authorization.k8s.io"] 
  resources: ["clusterroles", "clusterrolebindings"]
  verbs: ["get", "list", "watch", "create", "update", "delete"]
# Allow to deploy configmaps for storing resources and configuration for TIBCO Streaming
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "watch", "list", "create", "update", "delete"]
# Allow to deploy stateful set of pods for TIBCO Streaming
- apiGroups: ["apps"]
  resources: ["statefulsets"]
  verbs: ["get", "watch", "list", "create", "update", "delete"]
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "create", "delete"]
!


#
# 4. ClusterRoleBinding , can also do using k8s yaml
#

kubectl create clusterrolebinding $CLUSTER_ROLE_BINDING_NAME --clusterrole $CLUSTER_ROLE_NAME --serviceaccount default:$SERVICE_ACCOUNT_NAME


################### Fetch credentials for the service account 


#
# init
#

SERVICE_ACCOUNT=accelerator-webapp-account
NAMESPACE=default

#
# server
#

API_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

#
# secret for service account(a secret(with token and certificate) is by default created for every service account you create in k8s)
#

SECRET_NAME=$(kubectl get serviceaccount $SERVICE_ACCOUNT -n $NAMESPACE -o jsonpath='{.secrets[0].name}')

#
# token for service account
#

TOKEN_FOR_SERVICE_ACCOUNT=$(kubectl get secret $SECRET_NAME  -n $NAMESPACE -o jsonpath='{.data.token}' | base64 --decode)

#
# ca certificate to a file
#

kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.ca\.crt}' | base64 --decode > /tmp/ca.crt

#
# apiserver and token to a file
#

echo $'API_SERVER=$API_SERVER\nTOKEN_FOR_SERVICE_ACCOUNT=$TOKEN_FOR_SERVICE_ACCOUNT' > '/tmp/k8s_access_config'

#
# test: to call K8s API server; you need server URL for API-server, TOKEN and certificate
#

curl $API_SERVER/api --header "Authorization: Bearer $TOKEN_FOR_SERVICE_ACCOUNT" --cacert '/tmp/ca.crt'




