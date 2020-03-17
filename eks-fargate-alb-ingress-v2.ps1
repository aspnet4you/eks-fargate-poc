#https://docs.aws.amazon.com/codebuild/latest/userguide/cloudformation-vpc-template.html
#Create a VPC using the stack sample above

$AWS_REGION = 'us-east-1'
$CLUSTER_NAME = 'eks-fargate-alb-ingress-demo'

#Cluster provisioning
#The first step is to create an Amazon EKS cluster using eksctl. 
eksctl create cluster --name $CLUSTER_NAME --region $AWS_REGION --fargate

#Once the cluster creation is completed, you can validate that everything went well by running the following command
#Change the path to kubectl
kubectl get svc


#Setup the OIDC ID provider (IdP) in AWS. 
#This step is needed to give IAM permissions to a Fargate pod running in the cluster using the IAM for Service Accounts feature. 
eksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME --approve

#The next step is to create the IAM policy that will be used by the ALB Ingress Controller deployment. 
#This policy will be later associated to the Kubernetes service account and will allow the ALB Ingress Controller pods to create and manage the ALB’s resources in your AWS account for you.
wget -O alb-ingress-iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/master/docs/examples/iam-policy.json
aws iam create-policy --policy-name ALBIngressControllerIAMPolicy --policy-document file://alb-ingress-iam-policy.json


#Create a cluster role, role binding, and a Kubernetes service account
$STACK_NAME ="eksctl-$CLUSTER_NAME-cluster"
$VPC_ID =$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" | jq -r '[.Stacks[0].Outputs[] | {key: .OutputKey, value: .OutputValue}] | from_entries' | jq -r '.VPC')
$AWS_ACCOUNT_ID =$(aws sts get-caller-identity | jq -r '.Account')

kubectl apply -f rbac-role.yaml

#And finally create the Kubernetes Service Account
eksctl create iamserviceaccount --name alb-ingress-controller --namespace kube-system --cluster $CLUSTER_NAME --attach-policy-arn "arn:aws:iam::$($AWS_ACCOUNT_ID):policy/ALBIngressControllerIAMPolicy" --approve --override-existing-serviceaccounts

#Check service account
kubectl get serviceaccounts -n kube-system

#Deploy the ALB Ingress Controller
#Hard coded the vpc id, cluster name and aws region (didn't know how to parameterized!)
kubectl apply -f alb-ingress-controller.yaml

#Deploy sample application to the cluster
#Don't want nginx as sample. Used another ready to go container image @https://hub.docker.com/_/microsoft-dotnet-core-aspnet/
kubectl apply -f aspnetapp-deployment.yaml
kubectl apply -f nginx-deployment.yaml

#Create a service so we can expose the aspnetapp pods
kubectl apply -f aspnetapp-service.yaml
kubectl apply -f nginx-service.yaml

#Finally, let’s create our ingress resource
kubectl apply -f aspnetapp-ingress-resource.yaml


#Once everything is done, you will be able to get the ALB URL by running the following command
kubectl get ingress aspnetapp-ingress
kubectl describe ingress aspnetapp-ingress

#Check all the running pods in default namespace in farget computes
kubectl get pods -o wide

#Deploy the dashboard, I am going to use an older version.
#Recommendaed or latest version deployed the dashboard in kubernetes-dashboard namespace. It didn't work. I think it was due to farget profile not configured for this namespace!
kubectl kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v1.10.1/src/deploy/recommended/kubernetes-dashboard.yaml
kubectl apply -f eks-admin-service-account.yaml

#Get the token to be used to login to dashboard
aws eks get-token --cluster-name $CLUSTER_NAME

#Run the dashboard, it works!
kubectl proxy
http://localhost:8001/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/#!/login
