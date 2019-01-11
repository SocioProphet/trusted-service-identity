# Trusted Identity (TI)

Detailed description of the TI demo is available [here](examples/README.md)

## Prerequisites

1. Make sure you have an IBM Cloud (formerly Bluemix) account and you have the [IBM Cloud CLI](https://console.bluemix.net/docs/cli/reference/bluemix_cli/get_started.html#getting-started) installed
2. Make sure you have a running kubernetes cluster, e.g.
[IBM Container service](https://console.bluemix.net/docs/containers/container_index.html#container_index) or [minikube](https://github.com/kubernetes/minikube) and that kubectl is configured to access that cluster. Test the access with
```console
kubectl get pods --all-namespaces
```

## Build and Install
Clone this project in a local directory, in your GOPATH

```console
cd $GOPATH
mkdir -p $GOPATH/src/github.ibm.com/kompass/
cd src/github.ibm.com/kompass/
git clone git@github.ibm.com:kompass/TI-KeyRelease.git
cd TI-KeyRelease
```
If you cannot clone the project with the git ssh protocol, make sure [you add your
ssh public key to your IBM GitHub Enterprise Account](https://help.github.com/enterprise/2.13/user/articles/adding-a-new-ssh-key-to-your-github-account/).

Execute `dep` to manage GoLang dependencies for this project.

On MacOS you can install or upgrade to the latest released version with Homebrew:

```console
brew install dep
brew upgrade dep
```

On other platforms you can use the install.sh script:

```
curl https://raw.githubusercontent.com/golang/dep/master/install.sh | sh
```

It will install into your $GOPATH/bin directory by default or any other directory you specify using the INSTALL_DIRECTORY environment variable.

To compile and build the image, get and test the dependencies:

```console
make dep get-deps test-deps
```
This might take some time to execute as it scans and installs the dependencies.
Once the dependencies are installed, execute the build.

Regenerating deep copy

Deep copy helpers are required for the data schema. A data copy helper (of the form zz_generated.deepcopy.go) already exists for this app under pkg/apis/cti/v1, however if change the schema you will need to regenerate it.

To regenerate, simply run the following script from the root of this project:

```
hack/update-codegen.sh
```

this will update the pkg/client directory. If everything OK, following message appears:

```
diffing hack/../pkg against freshly generated codegen
hack/../pkg up to date.
```

```console
make build
```

Now you can create a docker image:

```console
make docker
```

In order to push the image to public Artifactory registry, you need to obtain an
access and create an [API key](https://pages.github.ibm.com/TAAS/tools_guide/artifactory/authentication/#authenticating-using-an-api-key). The repository name is `res-kompass-kompass-docker-local.artifactory.swg-devops.com`

Execute the docker login and push the image:

```console
docker login res-kompass-kompass-docker-local.artifactory.swg-devops.com
Username: <your-user-id>
Password: <API-key>

make docker-push
# or simply do it all at once:
make all
make docker-push
```

Compile and create images for other sub-components

```console
make all -C components/gen-vault-cert/
make all -C components/revoker/
make all -C components/jwt-sidecar/
make all -C components/vtpm-server/
```

To deploy manually:

```console
./deploy.sh
```

Compile and build examples (JWT server and client)

```console
make all -C examples/jwt-client/
make all -C examples/jwt-server/
```

## Install and initialize Helm environment
This project requires Helm v2.10.0 or higher.

Install [Helm](https://github.com/kubernetes/helm/blob/master/docs/install.md). On Mac OS X you can use brew to install helm:
```bash
  brew install kubernetes-helm
  # or to upgrade the existing helm
  brew upgrade kubernetes-helm
  # then initialize (assuming your KUBECONFIG for the current cluster is already setup)
  helm init
```

## Host Setup - one time  initialization
All the worker hosts are required to be initialized with private keys and root CA
(to be replaced by TPM in the future). This operation needs to be executed only once.

### Build TI Setup helm charts

Package the helm chart:
```console
cd TI-KeyRelease
helm package charts/ti-setup
```

### Deploy TI Setup

Get the default chart values and replace them with your private keys and certs.
Replace X.X.X with proper version numbers

```console
helm inspect values charts/ti-setup-X.X.X.tgz > config.yaml
# modify config.yaml with your own values
helm install charts/ti-setup-X.X.X.tgz --values=config.yaml --debug --name ti-setup
```

Once the `ti-setup` is successfully deployed, remove it.
```console
helm delete --purge ti-setup
```

To validate and inspect the values assigned by the setup chart, run the daemonset to access all the hosts:

```console
kubectl create -f examples/inspect-daemonset.yaml
kubectl get pods
# select the node that you like to inspect and get inside:
kubectl exec -it <pod_id> /bin/bash
# review /host/ti/secrets, /etc/machineid, /keys/
```

To remove/reset all the values setup by the `ti-setup` chart, run the following:

```console
kubectl create -f examples/cleanup-daemonset.yaml
kubectl delete -f examples/cleanup-daemonset.yaml
```

## TI Key Release Helm Deployment
The deployment is done in `trusted-identity` namespace. If you are testing or developing
the code and execute the deployment several time, it is a good idea to cleanup the namespace before executing another deployment. Run cleanup first, then init to initialize the namespace.
This would remove all the components and artifacts, then recreate a new, empty namespace:

```console
./cleanup.sh
./init-namespace.sh
```

Currently the images for Trusted Identity project are stored in Artifactory. In order to
use them, user has to be authenticated. You must obtain the [API key](https://pages.github.ibm.com/TAAS/tools_guide/artifactory/authentication/#authenticating-using-an-api-key)
as described above.

Create a secret that contains your Artifactory user id (e.g. user@ibm.com) and API key.
(This needs to be done every-time the new namespace is created)

```console
kubectl -n trusted-identity create secret docker-registry regcred \ --docker-server=res-kompass-kompass-docker-local.artifactory.swg-devops.com
--docker-username=user@ibm.com \
--docker-password=${API_KEY} \
--docker-email=user@ibm.com

# to check your secret:
kubectl -n trusted-identity get secret regcred --output="jsonpath={.data.\.dockerconfigjson}" | base64 --decode
```

### Build Helm Charts
Currently there are 2 charts to deploy TI KeyRelease: ti-key-release-1 and ti-key-rel
-2
Package the helm charts:
```console
cd TI-KeyRelease
helm package charts/ti-key-release-1
# update helm dependencies
helm dep update charts/ti-key-release-2
helm package --dependency-update charts/ti-key-release-2
```

### Deploy Helm charts

The helm charts are ready to deploy. Replace X.X.X with proper version numbers

```console
helm install ti-key-release-2-X.X.X.tgz --debug --name ti-test \
--set ti-key-release-1.cluster.name=mycluster-name \
--set ti-key-release-1.cluster.region=dal01
```

Complete list of values can be obtained as follow:
```console
helm inspect values ti-key-release-2-X.X.X.tgz > config.yaml
# modify config.yaml
helm install -i --values=config.yaml ti-test ti-key-release-2-X.X.X.tgz
# or upgrade existing deployment
helm upgrade -i --values=config.yaml ti-test ti-key-release-2-X.X.X.tgz
```

### Testing Deployment
Once environment deployed, execute a test by deploying the following file:
```console
kubectl -n trusted-identity create -f examples/myubuntu_inject.yaml
```
The main container `myubuntu` should have a new key and certificate in `/vault-certs` directory
for accessing the Vault and JWT token in `/jwt-tokens`


# Trusted Identity with Istio
In this demo we will start a web service with Istio Envoy, enable Istio policy
to require JWT tokens to communicate with this service, then start a container with
corresponding sidecar to manage creation of JWT tokens. Only the tokens created by
a sidecar will be accepted by the Envoy. All other requests will be rejected.

For simplicity, we will use the same namespace for all the transactions.

## Start a web service with Istio Envoy
Use provided [examples/web-service.yaml] service for deployment with a sidecar:

```console
kubectl apply -n trusted-identity -f <(./istioctl kube-inject -f examples/web-service.yaml)
```

## Enable the JWT policy for Istio
In order to use the JWT tokens to authenticate the end-user, enable Istio policy
referencing prebuilt public key from [here](https://raw.githubusercontent.com/mrsabath/jwks-test/master/jwks.json)
To use your own set of keys, see instructions at the bottom of this page

```yaml
apiVersion: "authentication.istio.io/v1alpha1"
kind: "Policy"
metadata:
  name: "jwt-example"
spec:
  targets:
  - name: web-service
  origins:
  - jwt:
      issuer: "wsched@us.ibm.com"
      jwksUri: "https://raw.githubusercontent.com/mrsabath/jwks-test/master/jwks.json"
  principalBinding: USE_ORIGIN
```

Install the policy [examples/jwt-policy-example.yaml](./examples/jwt-policy-example.yaml)

```console
kubectl create -f examples/jwt-policy-example.yaml -n trusted-identity
```

## Testing the JWT token created by the sidecar
Every container created in `trusted-identity` namespace that conforms to [this
policy](./charts/ti-key-release-1/templates/cti-policy-example.yaml) gets a sidecar
that is creating JWT tokens as defined by `execute-get-key.sh` in [here](./charts/ti-key-release-1/templates/configmap/jwt-configmap.yaml)
This newly created token is available to the main container via shared mount (`/jwt-tokens/token`)

For testing purposes the sidecar creates a token valid 25 seconds and the refresh
rate is 30 seconds, so if the main container uses the token, every 25 seconds
the authentication should fail for 5 seconds.

If you don't have the container running from previous steps, start it now:
```
console
kubectl -n trusted-identity create -f examples/myubuntu_inject.yaml
```

Login to this container and try to execute a connection to the web service.

```console
kubectl -n trusted-identity get pods
kubectl -n trusted-identity exec -it <my_ubuntu_pod_id> -c myubuntu /bin/bash

root@myubuntu-767584864-b76f8:/# curl web-service
Origin authentication failed.
root@myubuntu-767584864-b76f8:/#
```

Since we enabled the Istio policy, the web service's Envoy requires valid JWT token
to be provided in order to grant access to the server, so now let's try to connect
with newly created JWT token:

```console
# run endless loop to test the connection
while true; do curl --header "Authorization: Bearer $(cat /jwt-tokens/token)" web-service -s -w "%{http_code}\n";sleep 5; done
```
Now you should be getting valid web service responses
You can copy the JWT token from /jwt-tokens/token and inspect it (e.g. [https://jwt.io/](https://jwt.io/))

Sample JWT payload:

```json
{
  "cluster-name": "mycluster",
  "cluster-region": "dal01",
  "exp": 1541014498,
  "iat": 1541014468,
  "images": "res-kompass-kompass-docker-local.artifactory.swg-devops.com/myubuntu:latest",
  "iss": "wsched@us.ibm.com",
  "machineid": "266c2075dace453da02500b328c9e325",
  "pod": "myubuntu-767584864-2dkdg",
  "sub": "wsched@us.ibm.com",
  "trusted-identity": "id-res-kompass-kompass-docker-local.artifactory.swg-devops.com"
}
```
## Cleanup
Remove all the resources created for Trusted Identity
```console
./cleanup.sh
```
Make sure to run `./init.sh` again after the cleanup to start the fresh deployment


## Create your own private key and public JSON Web Key Set (JWKS)
Before enabling the JWT policy in Istio, you need to first create a private key
and JWKS. The following steps are based on [this doc](https://github.com/istio/istio/blob/release-1.0/security/tools/jwt/samples/README.md)
This can be done from inside the sidecar container:

```console
kubectl -n trusted-identity exec -it <my_ubuntu_pod_id> -c jwt-sidecar /bin/bash
# generate private key using openssl
openssl genrsa -out key.pem 2048
# run gen-jwt.py with --jkws to create new public key set (JWKS) and sample JWT
python gen-jwt.py key.pem -jwks=./jwks.json --expire=60 --claims=foo:bar > demo.jwt
```

Preserve the newly created `key.pem` and `jwks.json`. Put the public JWKS to publicly accessible place e.g.
https://raw.githubusercontent.com/mrsabath/jwks-test/master/jwks.json in public GITHUB: https://github.com/mrsabath/jwks-test/blob/master/jwks.json

Put the private key to [./charts/ti-key-release-2/values.yaml](./charts/ti-key-release-2/values.yaml)

```yaml

ti-key-release-1:
  jwtkey: |-
    -----BEGIN RSA PRIVATE KEY-----
    MIIEogIBAAKCAQEAtRcoFKRhV5+1w3r9ZrDeT4XKaREaher2dAfg0i82Te2QG1B5
    . . . .
         ***** MY KEY *****
    . . . .
    Au57AoGALTlcO/AMzyj/UjE+/6wP0nYuw90FitYq9h9q9jSYIMyxwQWJa4qWwkp9
    0vuUNDqsbzFeqqG55f0FZp3bfmNExNs0igdcTzwfqt6Q4LGkZVFYicbshIxHDC0a
    fn3/DuZcMg+chQ970y+XF5JtUwgVbYfaMiP1zrF0J6Fh4rHk3Cw=
    -----END RSA PRIVATE KEY-----
```
Then redeploy the charts and your container.

## Sample JWT claims

```json
{
  "cluster-name": "EUcluster",
  "cluster-region": "eu-de",
  "exp": 1547224830,
  "iat": 1547224800,
  "images": "res-kompass-kompass-docker-local.artifactory.swg-devops.com/myubuntu:latest@sha256:5b224e11f0e8daf35deb9aebc86218f1c444d2b88f89c57420a61b1b3c24584c",
  "iss": "wsched@us.ibm.com",
  "machineid": "266c2075dace453da02500b328c9e325",
  "namespace": "trusted-identity",
  "pod": "myubuntu-698b749889-m9xz9",
  "sub": "wsched@us.ibm.com"
}
```
