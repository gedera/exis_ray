---
name: rubocop-omakase
description: This skill should be used when writing or reviewing Ruby code in this gem to ensure it follows RuboCop Rails Omakase conventions. Activates when writing new methods, refactoring existing code, or when the user mentions "rubocop", "style", "convention", "cop", or "omakase".
version: 1.0.0
---

# RuboCop Rails Omakase — ExisRay

Todo código nuevo o modificado debe seguir las convenciones de `rubocop-rails-omakase`. Solo aplicar a código que se está escribiendo o modificando — nunca sugerir fixes en código existente no tocado.

## Reglas Principales

**Strings:**
```ruby
# Frozen string literal obligatorio en todos los archivos
# frozen_string_literal: true

# Comillas dobles para strings
"hola mundo"   # correcto
'hola mundo'   # incorrecto
```

**Métodos:**
```ruby
# Sin paréntesis en definición si no hay argumentos
def reset
  # ...
end

# Con paréntesis cuando hay argumentos
def hydrate(trace_id:, source:)
  # ...
end
```

**Bloques:**
```ruby
# { } para bloques de una línea
[1, 2].map { |n| n * 2 }

# do/end para bloques multilínea
[1, 2].each do |n|
  puts n
  puts n * 2
end
```

**Condicionales:**
```ruby
# Guard clauses para retornos tempranos
def process(value)
  return unless value.present?
  return "[FILTERED]" if sensitive?(value)

  do_something(value)
end

# Ternario solo cuando es genuinamente simple
result = condition ? "yes" : "no"
```

**Espaciado:**
```ruby
# Línea en blanco después de definición de clase/módulo
class MyClass
  # línea en blanco aquí si hay métodos

  def my_method
  end
end
```

**Hash:**
```ruby
# Ruby 3.1+ shorthand cuando key == variable
{ name:, value: }  # en lugar de { name: name, value: value }

# Rocket syntax solo para keys no-símbolo
{ "string-key" => value }
{ symbol_key: value }
```

## Patterns Comunes en ExisRay

```ruby
# Módulos con solo métodos de clase — usar module_function o class << self
module ExisRay
  module TaskMonitor
    class << self
      def run(task_name)
        # ...
      end
    end
  end
end

# Rescue en métodos que no deben interrumpir el flujo
def setup_context
  do_risky_thing
rescue StandardError
  # silenciar
end

# Lambdas con -> para bloques cortos
transformer = ->(value) { value.to_s.downcase }
```

## Verificación

Antes de proponer código, mentalmente verificar:
1. `# frozen_string_literal: true` presente
2. Strings con comillas dobles
3. Guard clauses en lugar de if anidados
4. `rescue StandardError` en operaciones de logging/tracing
