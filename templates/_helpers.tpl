{{- define "polytope-server.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
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

{{- define "polytope-server.pdEndpoint" -}}
{{- printf "pd.%s.svc:2379" .Release.Namespace }}
{{- end }}

{{- define "polytope-server.brokerUrl" -}}
{{- printf "http://frontend.%s.svc:%d" .Release.Namespace (.Values.frontend.brokerPort | int) }}
{{- end }}

{{- define "polytope-server.workerBrokerUrl" -}}
{{- $baseUrl := include "polytope-server.brokerUrl" .root -}}
{{- printf "%s/%s" $baseUrl .pool -}}
{{- end }}

{{- define "polytope-server.pollBaseUrl" -}}
{{- printf "http://frontend.%s.svc:%d" .Release.Namespace (.Values.frontend.port | int) }}
{{- end }}

{{- define "polytope-server.ingressHost" -}}
{{- printf "%s.%s" .Values.ingress.hostPrefix .Values.ingress.domain }}
{{- end }}
