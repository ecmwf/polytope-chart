{{- define "polytope-server.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Resolve and validate the ingress controller flavour. Reads from
`.Values.global.ingress.controller` (authoritative, also visible to the BOBS
subchart). Returns the string. Fails with a clear message when the value
is not one of the supported options.
*/}}
{{- define "polytope-server.ingressController" -}}
{{- $c := (((.Values.global).ingress).controller) | default "nginx-inc" -}}
{{- $supported := list "nginx-inc" "nginx-community" -}}
{{- if not (has $c $supported) -}}
{{- fail (printf "global.ingress.controller=%q is not supported. Supported values: %v" $c $supported) -}}
{{- end -}}
{{- $c -}}
{{- end }}

{{- define "polytope-server.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "polytope-server.labels" -}}
helm.sh/chart: {{ include "polytope-server.chart" . }}
{{ include "polytope-server.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "polytope-server.selectorLabels" -}}
app.kubernetes.io/name: {{ include "polytope-server.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "polytope-server.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "polytope-server.natsUrl" -}}
{{- printf "nats://%s-nats:4222" .Release.Name }}
{{- end }}

{{- define "polytope-server.brokerUrl" -}}
{{- printf "http://%s-frontend.%s.svc:%d" (include "polytope-server.fullname" .) .Release.Namespace (.Values.frontend.brokerPort | int) }}
{{- end }}

{{- define "polytope-server.workerBrokerUrl" -}}
{{- $baseUrl := include "polytope-server.brokerUrl" .root -}}
{{- printf "%s/%s" $baseUrl .pool -}}
{{- end }}

{{- define "polytope-server.pollBaseUrl" -}}
{{- printf "http://%s-frontend.%s.svc:%d/internal/poll" (include "polytope-server.fullname" .) .Release.Namespace (.Values.frontend.internalPollPort | int) }}
{{- end }}

{{- define "polytope-server.validateFrontendServiceExposure" -}}
{{- $serviceType := "ClusterIP" -}}
{{- if and .Values.frontend (hasKey .Values.frontend "serviceType") -}}
{{- $serviceType = .Values.frontend.serviceType -}}
{{- end -}}
{{- if and .Values.frontend (hasKey .Values.frontend "service") (hasKey .Values.frontend.service "type") -}}
{{- $serviceType = .Values.frontend.service.type -}}
{{- end -}}
{{- if ne $serviceType "ClusterIP" -}}
{{- fail (printf "frontend Service must remain ClusterIP while exposing internal-poll; got %s" $serviceType) -}}
{{- end -}}
{{- end }}

{{- define "polytope-server.ingressBackendPortName" -}}
{{- $backendPort := (.Values.ingress.backendPortName | default "http") -}}
{{- $backendPortString := toString $backendPort -}}
{{- if or (eq $backendPortString "internal-poll") (eq $backendPortString (toString (.Values.frontend.internalPollPort | int))) (eq $backendPortString "broker") (eq $backendPortString (toString (.Values.frontend.brokerPort | int))) -}}
{{- fail (printf "ingress backend must use public service port name http, not %s" $backendPortString) -}}
{{- end -}}
{{- if ne $backendPortString "http" -}}
{{- fail (printf "ingress backend must use public service port name http, not %s" $backendPortString) -}}
{{- end -}}
{{- $backendPortString -}}
{{- end }}

{{- define "polytope-server.bobsUrl" -}}
{{- printf "http://%s-bobs:%v" .Release.Name (.Values.bobs.service.port | default 3000) }}
{{- end }}

{{/*
Collect imagePullSecrets from global + local values, and auto-append the
chart-managed secret when imageCredentials is provided.
*/}}
{{- define "polytope-server.imagePullSecrets" -}}
{{- $secrets := list -}}
{{- if .Values.global -}}
  {{- range .Values.global.imagePullSecrets | default list -}}
    {{- $secrets = append $secrets . -}}
  {{- end -}}
{{- end -}}
{{- range .Values.imagePullSecrets | default list -}}
  {{- $secrets = append $secrets . -}}
{{- end -}}
{{- if (.Values.global).imageCredentials -}}
  {{- $secrets = append $secrets (dict "name" (printf "%s-registry-cred" (include "polytope-server.fullname" .))) -}}
{{- end -}}
{{- if $secrets }}
imagePullSecrets:
  {{- toYaml $secrets | nindent 2 }}
{{- end -}}
{{- end }}

{{- define "polytope-server.ingressHost" -}}
{{- printf "%s.%s" .Values.ingress.hostPrefix .Values.ingress.domain }}
{{- end }}

{{/*
Return the image reference for a component.
Usage:
  {{ include "polytope-server.image" (dict "imageRoot" .Values.frontend.image "global" .Values.global "chart" .Chart) }}
*/}}
{{- define "polytope-server.image" -}}
{{- $registryName := default .imageRoot.registry ((.global).imageRegistry) -}}
{{- $repositoryName := .imageRoot.repository -}}
{{- $tag := .imageRoot.tag | toString -}}
{{- if not .imageRoot.tag }}
  {{- if .chart }}
    {{- $tag = .chart.AppVersion | toString -}}
  {{- end }}
{{- end }}
{{- if $registryName }}
  {{- printf "%s/%s:%s" $registryName $repositoryName $tag -}}
{{- else }}
  {{- printf "%s:%s" $repositoryName $tag -}}
{{- end }}
{{- end -}}
