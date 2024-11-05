# Kubernetes Chart

Kubernetes can be used to deploy the full polytope stack. The supported method of deployment is via Helm, and this Helm Chart.



## Prerequisites

* Docker ≥ 18.x
* Helm ≥ 3.0.2
* Skaffold ≥ 1.13.2
* kubectl configured to point to a Kubernetes cluster
* `docker login <registry>`
* `helm dependency build`

## Build

In the future we will provide public images so you don't have to build them yourself.

Skaffold orchestrates the building of all the docker images. In the polytope-server directory, run:

```
skaffold build
```
You will need to provide a skaffold.env file. See the `skaffold.yaml` file for the required environment variables.


## Deploy

As per a usual Helm deployment, you can install the polytope chart with:

```
helm dependency build
helm install polytope . -f ../path/to/config.yaml
```

For developers, if the source has changed without changing image tags, you can force a redeploy with:

```
helm upgrade polytope .  -f ../path/to/config.yaml --force
```