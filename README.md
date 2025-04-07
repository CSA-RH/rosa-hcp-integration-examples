Make sure you are located in the terraform directory in order to retrieve output variables. 

# Preparation
Once logged in the created cluster with the following code snippet: 

```bash
oc login -u cluster-admin \
         -p $(terraform output -raw cluster_admin_password) \
         $(terraform output -raw cluster_api_url)
```

If not created, make sure that the project for the demo is available. The value could be fetched from the `demo_namespace` output variable in terraform.

```bash
oc new-project $(terraform output -raw demo_namespace)
```

Make sure that the Demo service account is created in the demo namespace:

```bash
oc create sa $(terraform output -raw demo_service_account)
```

Annotate the service account with the IAM role for the demo. 

```bash
oc annotate serviceaccount \
   -n $(terraform output -raw demo_namespace) \
   $(terraform output -raw demo_service_account) \
   eks.amazonaws.com/role-arn=$(terraform output -raw demo_role_arn)
```

# S3

In this example, we will show how to retrieve and interact with S3 with the CLI inside a Pod by using IRSA. We create the pod with SDK to access S3. The example must be executed in the terraform script directory to retrieve state variables. 

```bash
cat <<EOF | oc create -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  namespace: $(terraform output -raw demo_namespace)
  name: awscli-s3
  labels:
    app: awscli-s3
spec:
  replicas: 1
  selector:
    matchLabels:
      app: awscli-s3
  template:
    metadata:
      labels:
        app: awscli-s3
    spec:
      containers:
        - image: amazon/aws-cli:latest
          name: awscli-s3
          command:
            - /bin/sh
            - "-c"
            - while true; do sleep 10; done
          env:
            - name: HOME
              value: /tmp
      serviceAccount: $(terraform output -raw demo_service_account)
EOF
```

Get inside the pod 

```bash
oc rsh $(oc get pod -oNAME --selector app=awscli-s3)
```

Once logged in the pod, execute, for instance, the listing of all s3 buckets with the CLI

```bash
aws s3 ls
```

# RDS

In this example, we will show how to connect to the RDS postgres database created by the Terraform manifests by means of a temporary token retrieved by the application. We make use of a pod with the `psql` tool and the AWS SDK installed.

```bash 
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: awscli-postgres   
spec:
  serviceAccountName: $APP_SERVICE_ACCOUNT_NAME
  containers:
  - name: aws-cli
    image: amazonlinux:latest
    command: ["/bin/sh", "-c", "yum install -y postgresql17 aws-cli; while true; do sleep 30; done"]
    env:
      - name: PGHOST
        value: $(terraform output -raw rds_database_address)
      - name: AWS_REGION
        value: $(aws configure get region)
      - name: PGDATABASE
        value: dbschematest
      - name: PGUSER
        value: myiamuser
      - name: PGPORT
        value: "5432"
      - name: PGSSLMODE
        value: require
      - name: MASTER_PWD
        value: "mYm4st4rDb!yj"
  restartPolicy: Never
EOF

```

# DynamoDB

```bash
curl -X POST https://$(oc get route -n openshift-console console -ojsonpath='{.spec.host}')/item \
     -H "Content-Type: application/json" \
     -d    '{"id": "23", "data": "This is another test item"}'
```