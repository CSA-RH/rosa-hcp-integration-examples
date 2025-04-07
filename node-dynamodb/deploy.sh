#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SOURCES_DIR=$SCRIPT_DIR/src

echo CURRENT NAMESPACE=$(oc project -q)
# Function to check if a resource exists
check_openshift_resource_exists() {
    local resource_type="$1"
    local resource_name="$2"    

    if oc get $resource_type $resource_name >/dev/null 2>&1; then
        return 0  # True: resource exists
    else
        return 1  # False: resource does not exist
    fi
}

# Create ImageStream for Observability Demo Client API (NodeJS)
cat <<EOF | oc apply -f -
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  name: rosa-dynamodb-demo
spec:
  lookupPolicy:
    local: true
EOF
# Create BuildConfig for Observability Demo Client API 
cat <<EOF | oc apply -f - 
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  labels:
    build: rosa-dynamodb-demo
  name: rosa-dynamodb-demo
spec:
  output:
    to:
      kind: ImageStreamTag
      name: rosa-dynamodb-demo:latest
  source:
    binary: {}
    type: Binary
  strategy:
    dockerStrategy: 
      dockerfilePath: Dockerfile
    type: Docker
EOF
# Resources cleanup
rm -rf build node_modules package-lock.json .env
# Remove previous build objects
oc delete build --selector build=rosa-dynamodb-demo > /dev/null 
# Start build for rosa-dynamodb-demo
oc start-build rosa-dynamodb-demo --from-file $SOURCES_DIR
# Follow the logs until completion 
oc logs $(oc get build --selector build=rosa-dynamodb-demo -oNAME) -f
# Check if a deployment already exists
if check_openshift_resource_exists Deployment rosa-dynamodb-demo; then
  # update deployment
  echo "Updating deployment..."
  oc set image \
    deployment/rosa-dynamodb-demo \
    rosa-dynamodb-demo=$(oc get istag rosa-dynamodb-demo:latest -o jsonpath='{.image.dockerImageReference}')
else
  echo "Creating deployment, service and route..."
  # Create deployment
  oc create deploy rosa-dynamodb-demo --image=rosa-dynamodb-demo:latest 
  # Create service
  oc expose deploy/rosa-dynamodb-demo --port 3000  
  # Create route
  cat <<EOF | oc apply -f - 
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  labels:
    app: rosa-dynamodb-demo
  name: rosa-dynamodb-demo
spec:
  port:
    targetPort: 3000
  to:
    kind: Service
    name: rosa-dynamodb-demo
  tls: 
    termination: edge
EOF
fi