---
name: yard
description: This skill should be used when writing or reviewing Ruby documentation in this gem. Activates when adding new methods, classes, or modules, or when the user mentions "yard", "documentation", "docstring", "@param", "@return", "@example", or asks how to document something.
version: 1.0.0
---

# YARD Documentation — ExisRay Style

Toda clase, módulo y método público de ExisRay debe estar documentado con YARD. Los métodos privados solo se documentan si la lógica no es autoevidente.

## Estructura de una Clase/Módulo

```ruby
# Descripción en una línea.
#
# Párrafo de contexto opcional explicando el propósito y comportamiento general.
# Mencionar dependencias importantes o patrones de uso.
#
# @example Uso básico
#   ExisRay::Tracer.hydrate(trace_id: header, source: 'http')
class ExisRay::Tracer < ActiveSupport::CurrentAttributes
```

## Métodos de Clase

```ruby
# Descripción concisa del método en una línea.
#
# Párrafo opcional con detalles de comportamiento, casos edge, o efectos secundarios.
#
# @param trace_id [String] El header de traza entrante (formato AWS X-Ray).
# @param source [String] El entrypoint de ejecución ('http', 'sidekiq', 'task', 'system').
# @return [void]
def self.hydrate(trace_id:, source:)
```

## Tipos Comunes en ExisRay

| Tipo YARD | Cuándo usarlo |
|:----------|:-------------|
| `[String]` | Strings simples |
| `[String, nil]` | Puede ser nil |
| `[Boolean]` | true/false |
| `[Hash]` | Hash genérico |
| `[Hash{Symbol => Object}]` | Hash con tipos de keys/values |
| `[Class, nil]` | Clase o nil (para current_class, reporter_class) |
| `[void]` | Métodos sin valor de retorno significativo |
| `[Float]` | Duraciones en segundos |
| `[Integer]` | Duraciones en ms, counts |

## Atributos con attr_accessor

```ruby
# @!attribute [rw] trace_header
#   @return [String] La key del header HTTP (formato Rack) para el Trace ID entrante.
#   Por defecto es 'HTTP_X_AMZN_TRACE_ID'.
attr_accessor :trace_header
```

## Métodos Privados

Solo documentar si la lógica no es obvia:
```ruby
# Limpia el Request ID para cumplir con los 24 caracteres hex de AWS X-Ray.
#
# @api private
# @return [String]
def self.clean_request_id
```

## Reglas

- Primera línea: siempre una oración completa terminada en punto
- `@example` cuando el uso no es obvio desde la firma
- `@api private` para métodos que usan `private_class_method`
- No documentar código que no fue modificado
- No agregar `@author` ni `@since` — no es el estilo del proyecto
