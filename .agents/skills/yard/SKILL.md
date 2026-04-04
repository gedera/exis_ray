---
name: yard
description: Experto en documentación YARD para Ruby. Consultame para escribir documentación correcta con tags, tipos, directivas, duck types y patrones avanzados. Úsala SIEMPRE que necesites documentar código Ruby con YARD o auditar documentación existente.
---

# YARD Expert

Skill de conocimiento completo sobre YARD (Yet Another Ruby Document). Consultame para escribir documentación correcta, auditar cobertura o resolver dudas sobre tags, tipos y directivas.

## Glosario

**Tag** — Metadato prefijado con `@` que describe un aspecto del código (ej: `@param`, `@return`).

**Directiva** — Instrucción prefijada con `@!` que modifica el contexto de parsing (ej: `@!method`, `@!attribute`).

**Type specifier list** — Lista de tipos entre corchetes `[Type]` usada en tags como `@param` y `@return`.

**Duck type** — Tipo definido por interfaz, no por clase. Se escribe como `#method_name`.

**Reference tag** — Sintaxis `(see OBJECT)` que copia tags de otro objeto.

## Anatomía de una documentación YARD

```ruby
# Descripción breve del método (primera línea).
#
# Descripción extendida opcional. Puede tener múltiples párrafos,
# listas y ejemplos en markdown.
#
# @param name [Type] descripción del parámetro
# @return [Type] descripción del retorno
# @raise [ExceptionClass] cuándo se lanza
# @example Título del ejemplo
#   resultado = mi_metodo("valor")
#   # => "esperado"
def mi_metodo(name)
end
```

**Reglas clave:**
- Primera línea: descripción breve, sin punto final si es corta.
- Línea vacía entre descripción y tags.
- Tags multilínea: indentar 2 espacios las líneas siguientes.
- Orden recomendado de tags: `@param` → `@option` → `@yield` → `@yieldparam` → `@yieldreturn` → `@return` → `@raise` → `@example`.

## Sistema de Tipos

Ver catálogo completo en [references/tipos.md](references/tipos.md).

### Tipos básicos
```ruby
# @param name [String] un string
# @param count [Integer] un entero
# @param flag [Boolean] true o false (convención YARD, no existe en Ruby)
# @return [void] sin valor de retorno significativo
# @return [nil] retorna nil explícitamente
# @return [self] retorna self (métodos encadenables)
```

### Union types
```ruby
# @param input [String, Symbol] acepta string o symbol
# @return [String, nil] puede retornar nil
```

### Generics (parametrized types)
```ruby
# @param items [Array<String>] array de strings
# @param map [Hash<Symbol, Integer>] hash con keys symbol y values integer
# @return [Set<User>] set de usuarios
```

### Hashes con estructura
```ruby
# @param opts [Hash{Symbol => String}] opciones con keys symbol
# @param data [Hash{String => Array<Integer>}] hash complejo
```

### Duck types
```ruby
# @param io [#read] cualquier objeto que responda a #read
# @param callable [#call] cualquier objeto callable
# @param io [#read, #close] debe responder a ambos
```

### Order-dependent lists
```ruby
# @return [Array(String, Integer, Hash)] exactamente 3 elementos en ese orden
```

### Literals
```ruby
# @return [true] siempre retorna true
# @return [false, nil] retorna false o nil
```

## Tags principales

### @param
```ruby
# @param name [String] el nombre del usuario
# @param age [Integer] la edad (debe ser > 0)
def create(name, age); end
```

### @option (para hashes de opciones)
```ruby
# @param opts [Hash] opciones de configuración
# @option opts [String] :host ("localhost") el hostname
# @option opts [Integer] :port (3000) el puerto
# @option opts [Boolean] :ssl (false) usar SSL
def connect(opts = {}); end
```

### @return
```ruby
# @return [String] la representación en texto
# @return [void] no usar el valor de retorno
def to_s; end
```

### @yield y @yieldparam
```ruby
# @yield [user, index] itera sobre cada usuario
# @yieldparam user [User] el usuario actual
# @yieldparam index [Integer] la posición en la lista
# @yieldreturn [Boolean] true para continuar, false para detener
def each_user(&block); end
```

### @raise
```ruby
# @raise [ArgumentError] si el nombre está vacío
# @raise [ActiveRecord::RecordNotFound] si no existe el registro
def find!(name); end
```

### @example
```ruby
# @example Uso básico
#   user = User.find("john")
#   user.name #=> "john"
#
# @example Con opciones
#   user = User.find("john", include: :posts)
def find(name, **opts); end
```

### @see
```ruby
# @see User#destroy método relacionado
# @see https://api.example.com/docs documentación externa
```

### @deprecated
```ruby
# @deprecated Usar {#new_method} en su lugar desde v2.0.
def old_method; end
```

### @abstract
```ruby
# @abstract Subclases deben implementar {#execute}.
class BaseCommand; end
```

### @note y @todo
```ruby
# @note Este método no es thread-safe.
# @todo Agregar soporte para paginación.
def fetch_all; end
```

### @since y @api
```ruby
# @since 1.5.0
# @api private
def internal_method; end
```

## Directivas

### @!method (documentar métodos dinámicos)
```ruby
class User
  # @!method name
  #   @return [String] el nombre del usuario
  # @!method name=(value)
  #   @param value [String] el nuevo nombre
  attr_accessor :name
end
```

### @!attribute
```ruby
# @!attribute [r] count
#   @return [Integer] el conteo actual
# @!attribute [rw] name
#   @return [String] el nombre
```

### @!macro (evitar repetición)
```ruby
# @!macro [attach] property
#   @!method $1
#   @return [$2] el valor de $1
property :name, String
property :age, Integer
```

### @!group / @!endgroup
```ruby
# @!group Validaciones

def validate_name; end
def validate_age; end

# @!endgroup
```

### @!scope y @!visibility
```ruby
# @!scope class
# @!visibility private
```

## Reference tags
```ruby
# @param user [String] el usuario
# @param host [String] el host
def clean(user, host); end

# @param (see #clean)
def activate(user, host); end
```

## Antipatrones

**Documentar lo obvio** — No repitas el nombre del método en la descripción.
```ruby
# MAL:
# Gets the name.
# @return [String] the name
def name; end

# BIEN:
# @return [String] nombre completo del usuario (nombre + apellido)
def name; end
```

**Omitir tipos** — Siempre especificá tipos en `@param` y `@return`.
```ruby
# MAL:
# @param name el nombre

# BIEN:
# @param name [String] el nombre
```

**Usar Boolean sin aclarar** — Ruby no tiene clase Boolean. Es una convención YARD.
```ruby
# MAL:
# @return [TrueClass, FalseClass]

# BIEN:
# @return [Boolean] true si el usuario es admin
```

**@return void sin explicar** — Usá void cuando el retorno no importa, no cuando no sabés.
```ruby
# BIEN: método que muta estado, el retorno no importa
# @return [void]
def save!; end

# MAL: el retorno SÍ importa, no uses void
# @return [void]
def valid?; end
```

## FAQ

### ¿Cómo documento un método que acepta **kwargs?
```ruby
# @param name [String] el nombre
# @param opts [Hash] opciones adicionales
# @option opts [Integer] :timeout (30) segundos de espera
# @option opts [Boolean] :retry (true) reintentar en fallo
def fetch(name, **opts); end
```

### ¿Cómo documento un método con splat?
```ruby
# @param args [Array<String>] lista variable de nombres
def process(*args); end
```

### ¿Cómo verifico la cobertura?
```bash
bundle exec yard stats --list-undoc
```

### ¿Cómo genero la documentación?
```bash
bundle exec yard doc
# Servidor local:
bundle exec yard server --reload
```

## Referencias

- [Tipos completos](references/tipos.md) — Catálogo exhaustivo de type specifications
