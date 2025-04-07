Make sure you are located in the terraform `infra` directory and you have applied successfully applied the manifest to your infra. 

# Preparation
After the Terraform execution,you can log in to the created cluster with the following code snippet: 

```bash
oc login -u cluster-admin \
         -p $(terraform output -raw cluster_admin_password) \
         $(terraform output -raw cluster_api_url)
```

If not created, make sure that the project for the demo is available. The value could be fetched from the `demo_namespace` output variable in terraform.

```bash
oc new-project $(terraform output -raw demo_namespace)
```

Make sure that the Demo service account is created in the demo namespace. This service account will be used by the workloads in those examples to assume the rol which hosts all the needed permissions:

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

We must first create the database user that will connect the database through a temporary token generation. For this, we need to connect first as a master user, create the user, grant permission to the target database to connect and add the rds_iam role to the user. 

To cononect to the pod by master user (postgres) and password (retrieved from terraform manifests):

```bash
oc rsh awscli-postgres
```

Once inside the pod, we connect to the postgres instance by using the environment variables for simplicity: 

```bash
PGUSER=postgres PGPASSWORD=$MASTER_PWD psql
```

Once logged in the database, we create the user and grant the proper permissions: 

```
CREATE USER rds_iam_user WITH LOGIN;
GRANT CONNECT ON DATABASE dbschematest TO rds_iam_user;
GRANT rds_iam TO rds_iam_user;
```

For exiting from the database session, simply issue `\q` or `quit` or `exit`

For accessing the database with the new user, we need first to generate a temporary token with the AWS CLI or AWS SDK. In our case, we can use the AWS CLI. This token is valid for 15 minutes, therefore, connect to the database right after getting it. In the pod session, simply issue the following command to fetch the token and store it in the environment variable TOKEN

```bash 
TOKEN=$(aws rds generate-db-auth-token \
  --hostname $PGHOST \
  --port 5432 \
  --region $AWS_REGION \
  --username rds_iam_user)
```

For connecting to the database, as the environment variable PGUSER is set to `rds_iam_user` simply issue the following command: 

```bash
PGPASSWORD=$TOKEN psql
```

If everything is setup correctly, a new database session with the user will start. Here an example of the output: 

```
sh-5.2# PGPASSWORD=$TOKEN psql
psql (17.4, server 17.2)
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, compression: off, ALPN: postgresql)
Type "help" for help.

dbschematest=> SELECT CURRENT_USER;
 current_user 
--------------
 rds_iam_user
(1 row)

dbschematest=> SELECT VERSION();
                                      version                                       
------------------------------------------------------------------------------------
 PostgreSQL 17.2 on aarch64-unknown-linux-gnu, compiled by gcc (GCC) 12.4.0, 64-bit
(1 row)

dbschematest=> 
```

# DynamoDB

```bash
curl -X POST https://$(oc get route -n openshift-console console -ojsonpath='{.spec.host}')/item \
     -H "Content-Type: application/json" \
     -d    '{"id": "23", "data": "This is another test item"}'
```