{{/*
Expand the name of the chart.
*/}}
{{- define "aiex.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "aiex.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "aiex.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "aiex.labels" -}}
helm.sh/chart: {{ include "aiex.chart" . }}
{{ include "aiex.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: aiex-platform
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "aiex.selectorLabels" -}}
app.kubernetes.io/name: {{ include "aiex.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "aiex.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "aiex.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the name of the secret to use
*/}}
{{- define "aiex.secretName" -}}
{{- printf "%s-secrets" (include "aiex.fullname" .) }}
{{- end }}

{{/*
Create the name of the configmap to use
*/}}
{{- define "aiex.configMapName" -}}
{{- printf "%s-config" (include "aiex.fullname" .) }}
{{- end }}

{{/*
Generate the image name
*/}}
{{- define "aiex.image" -}}
{{- $registry := .Values.global.imageRegistry | default .Values.image.registry -}}
{{- $repository := .Values.image.repository -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- printf "%s/%s:%s" $registry $repository $tag -}}
{{- end }}

{{/*
Storage class name
*/}}
{{- define "aiex.storageClassName" -}}
{{- .Values.global.storageClass | default .Values.persistence.storageClass -}}
{{- end }}

{{/*
Logs storage class name
*/}}
{{- define "aiex.logsStorageClassName" -}}
{{- .Values.global.storageClass | default .Values.logs.persistence.storageClass -}}
{{- end }}