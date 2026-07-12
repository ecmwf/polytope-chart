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
Return the image reference for a component. A digest takes precedence over a
tag so production can consume an immutable release while Chart.AppVersion remains
informational only.
*/}}
{{- define "polytope-server.image" -}}
{{- $registryName := default .imageRoot.registry ((.global).imageRegistry) -}}
{{- $repositoryName := required "image.repository is required" .imageRoot.repository -}}
{{- $image := $repositoryName -}}
{{- if $registryName -}}
  {{- $image = printf "%s/%s" $registryName $repositoryName -}}
{{- end -}}
{{- $digest := .imageRoot.digest | default "" -}}
{{- $tag := .imageRoot.tag | default "" | toString -}}
{{- if $digest -}}
  {{- printf "%s@%s" $image $digest -}}
{{- else if $tag -}}
  {{- printf "%s:%s" $image $tag -}}
{{- else -}}
  {{- fail "image.tag or image.digest is required; Chart.AppVersion is not an image fallback" -}}
{{- end -}}
{{- end -}}

{{/*
Resolve schedule.enabled. Explicit booleans are authoritative. An omitted or null
value preserves the legacy behaviour in which a non-empty schedule map is enabled.
Required source fields are checked only when the integration is enabled.
*/}}
{{- define "polytope-server.scheduleEnabled" -}}
{{- $schedule := .Values.schedule -}}
{{- if empty $schedule -}}
false
{{- else if not (kindIs "map" $schedule) -}}
{{- fail "schedule must be a map or null" -}}
{{- else -}}
  {{- $enabled := true -}}
  {{- if hasKey $schedule "enabled" -}}
    {{- $configured := get $schedule "enabled" -}}
    {{- if ne $configured nil -}}
      {{- if not (kindIs "bool" $configured) -}}
        {{- fail "schedule.enabled must be true, false, or null" -}}
      {{- end -}}
      {{- $enabled = $configured -}}
    {{- end -}}
  {{- end -}}
  {{- if $enabled -}}
    {{- $_ := required "schedule.repo is required when schedule is enabled" (get $schedule "repo") -}}
    {{- $_ := required "schedule.path is required when schedule is enabled" (get $schedule "path") -}}
    {{- $_ := required "schedule.sshSecretName is required when schedule is enabled" (get $schedule "sshSecretName") -}}
true
  {{- else -}}
false
  {{- end -}}
{{- end -}}
{{- end -}}

{{/*
Validate one worker-pool entry and return true when it should render. A fragment
without a pool is accepted only when explicitly marked overrideOnly: true.
Image tags are mandatory for all rendered workers.
*/}}
{{- define "polytope-server.workerPoolEnabled" -}}
{{- $name := .name -}}
{{- $pool := .pool -}}
{{- if not (kindIs "map" $pool) -}}
  {{- fail (printf "workerPools.%s must be a map" $name) -}}
{{- end -}}
{{- $hasPool := and (hasKey $pool "pool") (not (empty (get $pool "pool"))) -}}
{{- if not $hasPool -}}
  {{- if hasKey $pool "overrideOnly" -}}
    {{- $overrideOnly := get $pool "overrideOnly" -}}
    {{- if not (kindIs "bool" $overrideOnly) -}}
      {{- fail (printf "workerPools.%s.overrideOnly must be a boolean" $name) -}}
    {{- end -}}
    {{- if $overrideOnly -}}
false
    {{- else -}}
      {{- fail (printf "workerPools.%s.pool is required unless overrideOnly is true" $name) -}}
    {{- end -}}
  {{- else -}}
    {{- fail (printf "workerPools.%s.pool is required unless overrideOnly is true" $name) -}}
  {{- end -}}
{{- else -}}
  {{- $image := get $pool "image" | default dict -}}
  {{- if and (empty (get $image "tag")) (empty (get $image "digest")) -}}
    {{- fail (printf "workerPools.%s.image.tag or image.digest is required for a rendered worker" $name) -}}
  {{- end -}}
true
{{- end -}}
{{- end -}}

{{/*
Resolve and validate a worker cache. `cache` defaults to a bounded 10Gi emptyDir;
cache.hostPath and cache.emptyDir are mutually exclusive. Legacy cacheDir maps to
a hostPath mounted at /tmp/cache for one release.
*/}}
{{- define "polytope-server.workerCache" -}}
{{- $name := .name -}}
{{- $pool := .pool -}}
{{- $hasCache := hasKey $pool "cache" -}}
{{- $hasLegacy := and (hasKey $pool "cacheDir") (not (empty (get $pool "cacheDir"))) -}}
{{- if and $hasCache $hasLegacy -}}
  {{- fail (printf "workerPools.%s.cache and deprecated cacheDir cannot both be set" $name) -}}
{{- end -}}
{{- if $hasLegacy -}}
enabled: true
mountPath: /tmp/cache
backend: hostPath
path: {{ get $pool "cacheDir" | quote }}
type: DirectoryOrCreate
{{- else if $hasCache -}}
  {{- $cache := get $pool "cache" -}}
  {{- if not (kindIs "map" $cache) -}}
    {{- fail (printf "workerPools.%s.cache must be a map" $name) -}}
  {{- end -}}
  {{- $hasHostPath := hasKey $cache "hostPath" -}}
  {{- $hasEmptyDir := hasKey $cache "emptyDir" -}}
  {{- if and $hasHostPath $hasEmptyDir -}}
    {{- fail (printf "workerPools.%s.cache must configure exactly one of hostPath or emptyDir" $name) -}}
  {{- end -}}
enabled: true
mountPath: {{ get $cache "mountPath" | default "/tmp/cache" | quote }}
{{ if $hasHostPath }}
  {{- $hostPath := get $cache "hostPath" -}}
  {{- if not (kindIs "map" $hostPath) -}}
    {{- fail (printf "workerPools.%s.cache.hostPath must be a map" $name) -}}
  {{- end }}
backend: hostPath
path: {{ required (printf "workerPools.%s.cache.hostPath.path is required" $name) (get $hostPath "path") | quote }}
type: {{ get $hostPath "type" | default "DirectoryOrCreate" }}
{{ else }}
  {{- $emptyDir := get $cache "emptyDir" | default dict -}}
  {{- if not (kindIs "map" $emptyDir) -}}
    {{- fail (printf "workerPools.%s.cache.emptyDir must be a map" $name) -}}
  {{- end }}
backend: emptyDir
sizeLimit: {{ get $emptyDir "sizeLimit" | default "10Gi" | quote }}
{{ end }}
{{- else -}}
enabled: false
{{- end -}}
{{- end -}}
