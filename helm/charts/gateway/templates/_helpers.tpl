{{/* Stessi namespace ammessi su ogni listener: routeNamespaces in values.yaml. */}}
{{- define "gateway.allowedRoutes" -}}
namespaces:
  from: Selector
  selector:
    matchExpressions:
      - key: kubernetes.io/metadata.name
        operator: In
        values:
          {{- toYaml .Values.routeNamespaces | nindent 10 }}
{{- end }}
