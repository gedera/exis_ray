# YARD — Catálogo completo de Type Specifications

Los tipos se especifican entre corchetes `[Type]` en tags como `@param`, `@return`, `@yield`, etc.

## Tipos básicos

| Tipo | Descripción |
|---|---|
| `String` | Clase Ruby estándar |
| `Integer` | Clase Ruby estándar |
| `Float` | Clase Ruby estándar |
| `Symbol` | Clase Ruby estándar |
| `Boolean` | Convención YARD: `TrueClass` o `FalseClass` |
| `nil` | Valor nil literal |
| `void` | Sin valor de retorno significativo |
| `self` | Retorna self (métodos encadenables) |
| `true` | Literal true |
| `false` | Literal false |

## Union types (múltiples tipos)

Separados por comas dentro de los corchetes:

```
[String, Symbol]           → String o Symbol
[Integer, nil]             → Integer o nil
[String, Symbol, nil]      → cualquiera de los tres
[Boolean, nil]             → true, false o nil
```

## Parametrized types (generics)

Sintaxis: `Collection<ElementType>`

```
[Array<String>]                    → array de strings
[Array<String, Symbol>]            → array de strings y/o symbols
[Set<Integer>]                     → set de integers
[Hash<Symbol, String>]             → hash con keys symbol, values string
[Hash<Symbol, Array<Integer>>]     → hash con values que son arrays de integers
[Enumerator<User>]                 → enumerator de users
```

## Hash con estructura explícita

Sintaxis: `Hash{KeyType => ValueType}`

```
[Hash{Symbol => String}]           → hash con keys symbol, values string
[Hash{String => Object}]           → hash con keys string, values cualquiera
[Hash{Symbol => Array<String>}]    → hash con values que son arrays de strings
[Hash{String, Symbol => Integer}]  → keys string o symbol, values integer
```

## Duck types

Prefijo `#` indica que el objeto responde a ese método:

```
[#read]                → cualquier objeto con método #read
[#call]                → cualquier callable (Proc, Lambda, etc.)
[#to_s]                → cualquier objeto convertible a string
[#read, #close]        → debe responder a ambos métodos
[#each]                → cualquier enumerable
```

## Order-dependent lists

Sintaxis: `Collection(Type1, Type2, ...)` — exactamente esos tipos en ese orden:

```
[Array(String, Integer)]           → array de exactamente 2 elementos: [string, integer]
[Array(String, Integer, Hash)]     → array de exactamente 3 elementos en ese orden
```

## Combinaciones comunes

```
[String, nil]                      → string nullable
[Array<String>]                    → array de strings
[Hash{Symbol => Object}]           → options hash
[Boolean]                          → true/false
[void]                             → sin retorno
[self]                             → chainable
[#read, #write]                    → IO-like
[Integer, Float]                   → numeric
[String, Symbol]                   → string-like identifier
[Array<Hash{Symbol => String}>]    → array de hashes
[Hash{Symbol => String, nil}]      → hash con values nullable
```

## Patrones por contexto

### Métodos de búsqueda
```ruby
# @return [User, nil] el usuario o nil si no existe
def find(id); end

# @return [User] el usuario
# @raise [RecordNotFound] si no existe
def find!(id); end
```

### Métodos booleanos
```ruby
# @return [Boolean] true si el usuario es admin
def admin?; end
```

### Métodos de mutación
```ruby
# @return [void]
def save!; end

# @return [self] para encadenar
def where(conditions); end
```

### Métodos de colección
```ruby
# @return [Array<User>] lista de usuarios
def all; end

# @yield [user] itera sobre cada usuario
# @yieldparam user [User]
# @return [Enumerator<User>] si no se pasa bloque
def each(&block); end
```

### Métodos con opciones
```ruby
# @param opts [Hash{Symbol => Object}] opciones
# @option opts [Integer] :limit (10) máximo de resultados
# @option opts [Integer] :offset (0) desde dónde empezar
# @option opts [Symbol] :order (:asc) dirección del ordenamiento
def search(query, **opts); end
```

### Callbacks y Procs
```ruby
# @param callback [Proc, #call] bloque a ejecutar
# @param filter [Proc<User, Boolean>] filtro que recibe user y retorna boolean
def on_create(callback); end
```
