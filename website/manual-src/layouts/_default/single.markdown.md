{{- /* Plain-Markdown rendering of a page for agents and tools (see hugo.toml
       outputFormats.markdown). Site-relative links become absolute, and the
       few shortcodes used in content are flattened so nothing Hugo-specific
       leaks into the output. */ -}}
{{- $base := "https://carrierwave.app/manual" -}}
{{- $body := .RawContent -}}
{{- $body = replaceRE `\]\(/([^)]*)\)` (printf "](%s/$1)" $base) $body -}}
{{- $body = replaceRE `\{\{<\s*term\s+"([^"]+)"\s*>\}\}` "$1" $body -}}
{{- $body = replaceRE `\{\{<\s*callout\s+"[^"]*"\s+"([^"]*)"\s*>\}\}` "> **$1**\n>" $body -}}
{{- $body = replaceRE `\{\{<\s*callout[^>]*>\}\}` ">" $body -}}
{{- $body = replaceRE `\{\{<\s*/callout\s*>\}\}` "" $body -}}
{{- $body = replaceRE `\{\{<[^>]*>\}\}` "" $body -}}
# {{ .Title }}

{{ with .Description }}{{ . }}

{{ end -}}
Source: {{ .Permalink }} (HTML) · this file: {{ with .OutputFormats.Get "markdown" }}{{ .Permalink }}{{ end }}
Site: https://carrierwave.app · Index of machine-readable pages: https://carrierwave.app/llms.txt
Last built: {{ now.Format "2006-01-02" }}

{{ $body }}
