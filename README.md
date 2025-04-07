# 🔧 IRSA + ROSA Demo: Preparation Steps

Ensure you are inside the `infra` directory where the Terraform configuration is located, and that the infrastructure has been successfully applied.

---

## 1. Log in to the ROSA Cluster

Use the credentials and API URL output by Terraform to log in as `cluster-admin`:

```bash
oc login -u cluster-admin \
         -p $(terraform output -raw cluster_admin_password) \
         $(terraform output -raw cluster_api_url)
```

---

## 2. Create or Use the Demo Namespace

If it hasn’t been created yet, create the namespace that will host the demo workloads. You can retrieve the namespace name from the `demo_namespace` Terraform output:

```bash
oc new-project $(terraform output -raw demo_namespace)
```

---

## 3. Create the Service Account

This service account will be used by the workloads to assume the IAM role configured with the required AWS permissions:

```bash
oc create sa $(terraform output -raw demo_service_account)
```

---

## 4. Annotate the Service Account with the IAM Role

Link the service account to the correct IAM role using an annotation. This enables IAM Roles for Service Accounts (IRSA):

```bash
oc annotate serviceaccount \
   -n $(terraform output -raw demo_namespace) \
   $(terraform output -raw demo_service_account) \
   eks.amazonaws.com/role-arn=$(terraform output -raw demo_role_arn)
```

# 🪣 S3 Access from a Pod using IRSA

This example demonstrates how to access **Amazon S3** from within a Pod using **AWS IAM Roles for Service Accounts (IRSA)** on **OpenShift ROSA**.

You'll deploy a simple `aws-cli` Pod and use the AWS SDK via CLI to list S3 buckets. Ensure you're running these commands from the Terraform `infra` directory to access the required output variables.

---

## 🚀 Deploy a Pod with AWS CLI

The following command deploys a Pod running the official AWS CLI container image. It uses the service account configured with IRSA to assume the IAM role with S3 access:

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
      serviceAccountName: $(terraform output -raw demo_service_account)
      containers:
        - name: awscli-s3
          image: amazon/aws-cli:latest
          command: ["/bin/sh", "-c", "while true; do sleep 10; done"]
          env:
            - name: HOME
              value: /tmp
EOF
```

---

## 🧑‍💻 Access the Pod Shell

Once the Pod is running, open an interactive shell inside it:

```bash
oc rsh $(oc get pod -o name -l app=awscli-s3)
```

---

## 📂 Interact with S3

From within the Pod, you can now use the AWS CLI authenticated via IRSA. For example, list your S3 buckets:

```bash
aws s3 ls
```

✅ If your IAM role is correctly configured, you should see the list of accessible S3 buckets.

# 🛢️ RDS (PostgreSQL) Access using IRSA

In this demo, we’ll show how to **connect to an RDS PostgreSQL database** using a **temporary IAM authentication token** from within an OpenShift pod. This pod uses the AWS CLI and the PostgreSQL `psql` client.

Make sure you're executing this from the Terraform `infra` directory, so that the output variables are correctly resolved.

---

## 🚀 Deploy a Pod with AWS CLI and PostgreSQL Client

This pod will install the necessary tools and use the IAM role assigned via IRSA to authenticate securely.

```bash
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: awscli-postgres
spec:
  serviceAccountName: $(terraform output -raw demo_service_account)
  containers:
    - name: aws-cli
      image: amazonlinux:latest
      command: ["/bin/sh", "-c", "yum install -y postgresql17 aws-cli; while true; do sleep 30; done"]
      env:
        - name: AWS_REGION
          value: $(aws configure get region)
        - name: PGHOST
          value: $(terraform output -raw rds_database_address)
        - name: PGDATABASE
          value: dbschematest
        - name: PGUSER
          value: rds_iam_user
        - name: PGPORT
          value: "5432"
        - name: PGSSLMODE
          value: require
        - name: MASTER_PWD
          value: $(terraform output -raw rds_database_password)
  restartPolicy: Never
EOF
```

---

## 👤 Create the IAM-Authenticated PostgreSQL User

Before connecting with an IAM token, we need to create the database user and assign the necessary permissions. This is done using the master user (`postgres`) and password provisioned by Terraform.

1. **Enter the pod:**

```bash
oc rsh awscli-postgres
```

2. **Connect to the database as the master user:**

```bash
PGUSER=postgres PGPASSWORD=$MASTER_PWD psql
```

3. **Inside the `psql` session, create the IAM user and grant permissions:**

```sql
CREATE USER rds_iam_user WITH LOGIN;
GRANT CONNECT ON DATABASE dbschematest TO rds_iam_user;
GRANT rds_iam TO rds_iam_user;
```

4. **Exit the session:**

```sql
\q
```

---

## 🔐 Generate a Temporary IAM Authentication Token

Now that the user is ready, use the AWS CLI to generate a **temporary authentication token** (valid for 15 minutes):

```bash
TOKEN=$(aws rds generate-db-auth-token \
  --hostname $PGHOST \
  --port 5432 \
  --region $AWS_REGION \
  --username rds_iam_user)
```

---

## 🧪 Connect Using the IAM Token

With the `PGUSER` environment variable already set to `rds_iam_user`, you can now authenticate using the generated token:

```bash
PGPASSWORD=$TOKEN psql
```

If successful, you should be able to get a session like the following:

```
psql (17.4, server 17.2)
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, compression: off, ALPN: postgresql)
Type "help" for help.

dbschematest=> SELECT CURRENT_USER;
 current_user 
--------------
 rds_iam_user
(1 row)

dbschematest=> SELECT version();
                                      version                                       
------------------------------------------------------------------------------------
 PostgreSQL 17.2 on aarch64-unknown-linux-gnu, compiled by gcc (GCC) 12.4.0, 64-bit
(1 row)
```

✅ You're now securely connected to RDS via IAM authentication from within your OpenShift cluster.

# DynamoDB
This demo deploys a simple Node.js application that exposes a `POST` endpoint at `/item`. The endpoint accepts a JSON payload with the following structure:

```json
{
  "id": "1",
  "data": "my data"
}
```

On successful request, the application stores a new item in the `Items` DynamoDB table (in the cluster's AWS region), including:
- The `id` and `data` fields from the request
- A `timestamp` field added by the application

---

## Deployment Instructions

The application is deployed in the same namespace as the rest of the demo. To deploy it:

1. Navigate to the `node-dynamodbp` directory (at the root of the repository).
2. Run the deployment script:

```bash
chmod +x deploy.sh  # Only if needed
./deploy.sh
```

---

## First Run: Expected Failure

By default, the deployment uses the `default` service account, which lacks permission to access DynamoDB. So, the first request will fail with a credentials error in the pod logs.

Try sending a sample request:

```bash
curl -i -X POST "https://$(oc get route rosa-dynamodb-demo -ojsonpath='{.spec.host}')/item" \
     -H "Content-Type: application/json" \
     -d '{"id": "1", "data": "Wrong Service Account"}'
```

---

## Fix: Patch the Deployment with the Correct Service Account

To grant proper access, patch the deployment to use the service account configured with IAM permissions for DynamoDB:

```bash
#Note the -chdir command to retrieve the output from the correct infra directory
# -- This assumes that you are in the node-dynamodb directory or an equivalent one 
#    in the path hierarchy. 
SERVICE_ACCOUNT_NAME=$(terraform -chdir=../infra output -raw demo_service_account)

oc patch deployment rosa-dynamodb-demo \
  -p "{\"spec\": {\"template\": {\"spec\": {\"serviceAccountName\": \"${SERVICE_ACCOUNT_NAME}\"}}}}"
```

This service account has IRSA annotations and the correct IAM role to perform `PutItem` operations on the `Items` table.

---

## Second Try: Success 🎉

Now, the same request will successfully write to DynamoDB:

```bash
curl -i -X POST "https://$(oc get route rosa-dynamodb-demo -ojsonpath='{.spec.host}')/item" \
     -H "Content-Type: application/json" \
     -d '{"id": "1", "data": "Works!"}'
```

You should see a response confirming the item was added in the DynamoDB resource page at the menu *Explore Items*.