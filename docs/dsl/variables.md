# Variables & Expressions

Variables hold dynamic data. Expressions evaluate to values at runtime.

## Variable Definition

```json
{
  "variables": {
    "variableName": {
      "type": "string",
      "initialValue": "default",
      "computed": "{{expression}}"
    }
  }
}
```

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `type` | VariableType | Yes | Data type |
| `initialValue` | any | No | Initial value |
| `computed` | string | No | Expression for computed variables |
| `source` | string | No | Datasource path to load value from (e.g. `"datasources/listings"`) |
| `schema` | string | No | Datasource path documenting the expected object shape for nav params |
| `preview` | VariablePreview | No | Sample value used only during standalone `renderScreen()` — never in production flows |

---

## Variable Types

| Type | Swift Equivalent | Example Values |
|------|-----------------|----------------|
| `string` | String | `"hello"`, `""` |
| `number` | NSNumber/Int/Double | `42`, `3.14`, `-10` |
| `boolean` | Bool | `true`, `false` |
| `array` | [Any] | `[1, 2, 3]`, `["a", "b"]` |
| `object` | [String: Any] | `{ "key": "value" }` |

### Examples

```json
{
  "variables": {
    "userName": { "type": "string", "initialValue": "" },
    "count": { "type": "number", "initialValue": 0 },
    "isLoggedIn": { "type": "boolean", "initialValue": false },
    "items": { "type": "array", "initialValue": [] },
    "user": { "type": "object", "initialValue": {} }
  }
}
```

---

## Variable Scopes

Variables exist in three scopes, searched from innermost to outermost.

### App Scope

Defined in `app.variables`. Available everywhere.

```json
{
  "app": {
    "variables": {
      "currentUser": { "type": "object", "initialValue": null },
      "isAuthenticated": { "type": "boolean", "initialValue": false }
    }
  }
}
```

### Screen Scope

Defined in `screen.content.variables`. Available within that screen.

```json
{
  "type": "screen",
  "content": {
    "variables": {
      "searchQuery": { "type": "string", "initialValue": "" },
      "results": { "type": "array", "initialValue": [] }
    }
  }
}
```

### Component Scope

Defined within a component. Local to that component.

### Scope Lookup Order

```
component → screen → app
```

When referencing `{{userName}}`, the system looks in:
1. Component's local variables
2. Screen's variables
3. App's variables

---

## Expression Syntax

Expressions use `{{...}}` syntax.

### Variable Reference

```json
"text": "{{userName}}"
```

### Nested Property Access

```json
"text": "{{user.profile.name}}"
"text": "{{config.settings.theme}}"
```

### Array Indexing

```json
"text": "{{items[0].title}}"
"text": "{{users[selectedIndex].name}}"
```

---

## Operators

### Arithmetic

| Operator | Description | Example |
|----------|-------------|---------|
| `+` | Addition | `{{count + 1}}` |
| `-` | Subtraction | `{{total - discount}}` |
| `*` | Multiplication | `{{price * quantity}}` |
| `/` | Division | `{{total / count}}` |
| `%` | Modulo | `{{index % 2}}` |

```json
"value": "{{count + 1}}"
"width": "{{baseWidth * 2 - padding}}"
"isEven": "{{index % 2 == 0}}"
```

### Comparison

| Operator | Description | Example |
|----------|-------------|---------|
| `==` | Equal (loose — `5 == '5'` is true) | `{{status == 'active'}}` |
| `!=` | Not equal (loose) | `{{type != 'hidden'}}` |
| `===` | Strictly equal (same type **and** value) | `{{count === 0}}` |
| `!==` | Strictly not equal | `{{value !== null}}` |
| `<` | Less than | `{{count < 10}}` |
| `>` | Greater than | `{{count > 0}}` |
| `<=` | Less or equal | `{{age <= 18}}` |
| `>=` | Greater or equal | `{{score >= 50}}` |

> **Loose vs. strict**: `==` coerces types before comparing (`5 == "5"` → true), which is convenient for values that arrive as strings. `===` requires the same underlying type (`5 === "5"` → false). Reach for `===`/`!==` when a type distinction is meaningful.

```json
"isEnabled": "{{count > 0}}"
"isMatch": "{{status == 'active'}}"
```

### Logical

| Operator | Description | Example |
|----------|-------------|---------|
| `&&` | And | `{{a && b}}` |
| `\|\|` | Or | `{{a \|\| b}}` |
| `!` | Not | `{{!isHidden}}` |

```json
"hidden": "{{!isVisible}}"
"canSubmit": "{{hasEmail && hasPassword}}"
"showWarning": "{{hasError || isExpired}}"
```

### Ternary

```json
"icon": "{{isLiked ? 'heart.fill' : 'heart'}}"
"color": "{{isError ? '#FF0000' : '#00FF00'}}"
"text": "{{count == 1 ? 'item' : 'items'}}"
```

### String Concatenation

```json
"label": "{{'Count: ' + count}}"
"greeting": "{{'Hello, ' + userName + '!'}}"
```

---

## Built-in Functions

### String Functions

| Function | Description | Example | Result |
|----------|-------------|---------|--------|
| `length` | String length (property form) | `{{name.length}}` | `5` |
| `uppercase(s)` | Uppercase | `{{uppercase(name)}}` | `"ADA"` |
| `lowercase(s)` | Lowercase | `{{lowercase(name)}}` | `"ada"` |
| `trim(s)` | Strip leading/trailing whitespace | `{{trim(input)}}` | `"hi"` |
| `replace(s, from, to)` | Replace all occurrences | `{{replace(phone, '-', '')}}` | `"5551234"` |
| `split(s, sep)` | Split into an array (empty `sep` → characters) | `{{split(csv, ',')}}` | `["a","b"]` |
| `substring(s, start)` | Substring from `start` to end | `{{substring(code, 2)}}` | |
| `substring(s, start, len)` | Substring of length `len` | `{{substring(code, 0, 4)}}` | |
| `startsWith(s, prefix)` | Prefix test | `{{startsWith(url, 'https')}}` | `true` |
| `endsWith(s, suffix)` | Suffix test | `{{endsWith(file, '.png')}}` | `true` |
| `includes(s, search)` | Substring test (empty `search` → true) | `{{includes(name, query)}}` | `true` |
| `match(s, pattern)` | Regex test (returns boolean) | `{{match(email, '^[^@]+@[^@]+$')}}` | `true` |

```json
"isEmpty": "{{email.length == 0}}"
"display": "{{uppercase(name)}}"
"clean": "{{trim(replace(phone, '-', ''))}}"
"isImage": "{{endsWith(lowercase(fileName), '.png')}}"
```

> **Function form only**: case conversion is `uppercase(name)` / `lowercase(name)` — the JavaScript-style method forms `name.toUpperCase()` / `name.toLowerCase()` are **not** supported. (`.length` is the one property-style accessor.)

> **Live search**: `includes(name, query)` returns `true` when `query` is empty, so a filter expression like `{{filter(items, includes(lowercase(item.name), lowercase(query)))}}` shows everything until the user starts typing.

> **`match()` & regex safety**: `match` returns a boolean (not the matched text). Patterns are bounded in length and screened for catastrophic-backtracking shapes (e.g. `(a+)+`) — a rejected or non-matching pattern simply returns `false`.

### Array Functions

| Function | Description | Example |
|----------|-------------|---------|
| `length(array)` | Array length | `{{length(items)}}` |
| `array.length` | Array length (property form) | `{{items.length}}` |
| `array.includes(value)` | Contains value | `{{items.includes('apple')}}` |
| `filter(array, predicate)` | Filter by predicate | `{{filter(items, item.active == true)}}` |
| `map(array, expression)` | Transform each element | `{{map(items, item.name)}}` |
| `find(array, predicate)` | First match or nil | `{{find(items, item.id == selectedId)}}` |
| `first(array)` | First element or nil | `{{first(items)}}` |
| `first(array, predicate)` | First matching element or nil | `{{first(items, item.done == false)}}` |
| `last(array)` | Last element or nil | `{{last(items)}}` |
| `last(array, predicate)` | Last matching element or nil | `{{last(items, item.done == false)}}` |
| `sort(array)` | Sorted ascending (numbers numerically, strings lexically) | `{{sort(scores)}}` |
| `sort(array, ascending)` | Sorted; pass `false` for descending | `{{sort(scores, false)}}` |
| `reverse(array)` | Reversed copy | `{{reverse(items)}}` |
| `slice(array, start)` | Sub-array from `start` to end | `{{slice(items, 1)}}` |
| `slice(array, start, end)` | Sub-array `[start, end)` | `{{slice(items, 0, 3)}}` |
| `concat(a, b, …)` | Concatenate two or more arrays | `{{concat(pinned, others)}}` |
| `join(array, separator)` | Join elements into a string | `{{join(tags, ', ')}}` |

```json
"count": "{{items.length}}"
"hasItem": "{{selectedIds.includes(item.id)}}"
"topThree": "{{slice(sort(scores, false), 0, 3)}}"
"tagLine": "{{join(item.tags, ' · ')}}"
```

> **Non-mutating**: `sort`, `reverse`, `slice`, and `concat` return new arrays — they never modify the source variable. Use them freely inside computed variables and `data` bindings.

### Higher-Order Array Functions

`filter`, `map`, `find`, and `first` accept a predicate/expression as the second argument. The loop variable is always named `item`.

```json
"data": "{{filter(products, item.price <= maxPrice)}}"
"data": "{{filter(tasks, item.done == false)}}"
"text": "{{first(tasks, item.priority == 'high').title}}"
"names": "{{map(users, item.name)}}"
"match": "{{find(items, item.id == selectedId)}}"
```

The predicate is a normal expression — it can reference outer variables alongside `item`:

```json
"data": "{{filter(items, item.categoryId == selectedCategory.id)}}"
"data": "{{filter(items, item.price > minPrice && item.price < maxPrice)}}"
```

Combine with other functions:

```json
"text": "{{length(filter(tasks, item.done == false))}} active"
"text": "Next: {{first(tasks, item.done == false && item.priority == 'high').title}}"
```

> **Note**: `item` is a synthetic loop variable — it only exists inside the predicate. Do not declare a screen variable named `item`.

> **Nil safety**: `find` and `first` return nil when no match is found. Property access on nil (e.g. `{{first(items, ...).title}}`) returns an empty string rather than crashing.

### Type Functions

| Function | Description | Example |
|----------|-------------|---------|
| `parseInt(string)` | Parse integer | `{{parseInt(input)}}` |
| `parseFloat(string)` | Parse float | `{{parseFloat(input)}}` |
| `toString(value)` | Convert to string | `{{toString(count)}}` |
| `isArray(value)` | Check if array | `{{isArray(data)}}` |

### Object Functions

| Function | Description | Example |
|----------|-------------|---------|
| `keys(object)` | Get keys | `{{keys(user)}}` |
| `values(object)` | Get values | `{{values(user)}}` |

### Math Functions

| Function | Description | Example |
|----------|-------------|---------|
| `round(n)` | Round to integer | `{{round(price)}}` |
| `round(n, decimals)` | Round to decimal places | `{{round(ratio, 2)}}` |
| `floor(n)` | Floor | `{{floor(ratio)}}` |
| `ceil(n)` | Ceiling | `{{ceil(ratio)}}` |
| `abs(n)` | Absolute value | `{{abs(diff)}}` |
| `min(a, b)` | Minimum | `{{min(x, y)}}` |
| `max(a, b)` | Maximum | `{{max(x, y)}}` |

### Formatting Functions

Use these to convert raw data values into human-readable display strings.

#### Date & Time

| Function | Description | Example output |
|----------|-------------|----------------|
| `formatDate(isoString, style)` | Format ISO date string | `"Jan 12, 2026"` |
| `formatTime(isoString)` | Format time, 12-hour | `"2:30 PM"` |
| `formatTime(isoString, '24h')` | Format time, 24-hour | `"14:30"` |
| `formatDuration(seconds)` | Seconds → stopwatch string | `"1:30"`, `"1:01:01"` |
| `formatMinutes(minutes)` | Minutes → compact duration | `"15 min"`, `"1h 30min"` |
| `ageInYears(isoDateString)` | Age in whole years | `35` |
| `daysBetween(startIso, endIso)` | Days between two dates (absolute) | `5` |
| `timeAgo(isoString)` | Relative time string | `"2 hours ago"` |
| `daysUntil(isoDateString)` | Days until date (negative = overdue) | `16`, `-2` |

**`formatDate` style values:**

| Style | Output |
|-------|--------|
| `"short"` | `"Jan 12"` |
| `"medium"` | `"Jan 12, 2026"` |
| `"long"` | `"January 12, 2026"` |
| `"weekday"` | `"Monday, Jan 12"` |
| `"weekdayShort"` | `"Mon"` |
| any `DateFormatter` pattern | pass-through |

**`timeAgo` output:**

| Elapsed | Output |
|---------|--------|
| < 1 min | `"just now"` |
| < 60 min | `"N minutes ago"` |
| < 24 h | `"N hours ago"` |
| 1 day | `"yesterday"` |
| 2+ days | `"N days ago"` |

**Examples:**

```json
"text": "{{formatDate(trip.startDate, 'medium')}}"
"text": "{{formatDate(appointment.date, 'weekday')}}"
"text": "{{formatTime(appointment.scheduledAt)}}"
"text": "{{formatDuration(elapsedSeconds)}}"
"text": "{{formatMinutes(recipe.prepTime + recipe.cookTime)}}"
"text": "{{ageInYears(dog.dateOfBirth)}} yrs"
"text": "{{daysBetween(trip.startDate, trip.endDate)}} days"
"text": "{{timeAgo(post.createdAt)}}"
```

**`daysUntil` for conditional display:**

```json
"text": "{{daysUntil(vaccination.nextDueDate) < 0 ? 'Overdue' : daysUntil(vaccination.nextDueDate) < 30 ? 'Due soon' : 'Up to date'}}"
```

#### Number & Currency

| Function | Description | Example output |
|----------|-------------|----------------|
| `formatCurrency(amount)` | Locale currency | `"$24.99"` |
| `formatCurrency(amount, 'EUR')` | Currency with code | `"€24.99"` |
| `formatNumber(number)` | Thousands separator | `"6,250"` |
| `formatNumber(number, 'percent')` | Percentage | `"86%"` |

**Examples:**

```json
"text": "{{formatCurrency(listing.price)}}"
"text": "{{formatNumber(stats.totalVolume)}} lbs"
"text": "{{formatNumber(accuracy, 'percent')}} accuracy"
```

#### String

| Function | Description | Example output |
|----------|-------------|----------------|
| `plural(count, singular, plural)` | Pluralize with count | `"1 glass"`, `"5 glasses"` |

**Examples:**

```json
"text": "{{plural(glassesConsumed, 'glass', 'glasses')}} of {{dailyGoal}}"
"text": "{{plural(cartItems.length, 'item', 'items')}}"
"text": "{{plural(remaining, 'card left', 'cards left')}}"
```

#### Translation

| Function | Description | Example |
|----------|-------------|---------|
| `i18n(key)` | Look up a translation for the active locale | `{{i18n('cart.title')}}` |

`i18n(key)` resolves `key` against the loaded translation bundle for the current locale, returning the key itself on a miss. Use it when translated text is computed or combined with variables. For static translatable text, prefer the `{"$i18n": "key"}` marker. Both are covered in [localization.md](localization.md).

```json
"text": "{{i18n(item.statusKey)}}"
"text": "{{count}} {{i18n(count == 1 ? 'unit.item' : 'unit.items')}}"
```

> Date, number, and currency formatters (`formatDate`, `formatCurrency`, `formatNumber`) also follow the active locale automatically — see [localization.md](localization.md).

---

## Computed Variables

Computed variables automatically recalculate when dependencies change.

```json
{
  "variables": {
    "firstName": { "type": "string", "initialValue": "" },
    "lastName": { "type": "string", "initialValue": "" },
    "fullName": {
      "type": "string",
      "computed": "{{firstName + ' ' + lastName}}"
    }
  }
}
```

### Definition Order

**You don't need to order variables manually.** The engine resolves dependencies and initializes variables in the correct order automatically, regardless of how they appear in the JSON object. A computed variable that references sibling variables will always be initialized after them, even if it's listed first in the definition.

```json
{
  "variables": {
    "displayedTasks": {
      "type": "array",
      "computed": "{{currentFilter == 'all' ? tasks : filter(tasks, item.done == false)}}"
    },
    "currentFilter": { "type": "string", "initialValue": "all" },
    "tasks": { "type": "array", "initialValue": [] }
  }
}
```

In this example, `displayedTasks` is listed first but depends on `currentFilter` and `tasks`. The engine detects this and initializes `currentFilter` and `tasks` first.

### Form Validation Example

```json
{
  "variables": {
    "email": { "type": "string", "initialValue": "" },
    "password": { "type": "string", "initialValue": "" },
    "isEmailValid": {
      "type": "boolean",
      "computed": "{{email.length > 0}}"
    },
    "isPasswordValid": {
      "type": "boolean",
      "computed": "{{password.length >= 8}}"
    },
    "isFormValid": {
      "type": "boolean",
      "computed": "{{isEmailValid && isPasswordValid}}"
    }
  }
}
```

> **Note**: Computed variables cannot be modified directly via actions.

---

## Object Variables with Schema

When a screen accepts an object via navigation params, use `schema` to document its expected shape. This links the variable to a datasource definition so tooling and the engine know what fields to expect.

```json
"variables": {
  "listing": {
    "type": "object",
    "schema": "datasources/listings"
  }
}
```

The `schema` field is informational — it doesn't validate or populate the variable at runtime. Values arrive via navigation params as usual.

---

## Preview Hints

`preview` provides a sample value for standalone rendering (e.g. opening a detail screen directly without navigating from a list). It is **only used during `renderScreen()` calls** — normal navigation always injects real params first, so preview never fires in production flows.

Two forms are supported:

### Literal value

```json
"city": {
  "type": "object",
  "schema": "datasources/cities",
  "preview": {
    "value": { "cityName": "San Francisco", "cityId": "sf", "population": "874,961", "country": "USA" }
  }
}
```

### Datasource item

Picks the item at `index` from a datasource's `data` array (defaults to `0`):

```json
"listing": {
  "type": "object",
  "schema": "datasources/listings",
  "preview": { "source": "datasources/listings", "index": 0 }
}
```

| Property | Type | Description |
|----------|------|-------------|
| `value` | any | Literal sample value to inject |
| `source` | string | Datasource path to pick an item from |
| `index` | number | Index into the datasource array (default: `0`) |

> **Note**: `value` takes priority if both `value` and `source` are set.

---

## Input Parameters

Screens can accept input parameters from navigation.

### Defining Parameters

```json
{
  "type": "screen",
  "content": {
    "inputParameters": {
      "userId": { "type": "string", "required": true },
      "showHeader": { "type": "boolean", "required": false }
    }
  }
}
```

### Passing Parameters

```json
{
  "type": "navigation",
  "nextScreen": "userProfile",
  "params": {
    "userId": "{{selectedUserId}}",
    "showHeader": true
  }
}
```

### Using Parameters

Parameters are available as regular variables:

```json
"text": "{{userId}}"
"hidden": "{{!showHeader}}"
```

---

## Variable Binding

**Binding** creates a two-way reactive link between a UI input component and a named variable. When the user types, the variable updates. When the variable changes via an action, the field updates.

### `bindVariable` (input components)

`bindVariable` works the same way across every input component — [textField](components/text-field.md), [textView](components/text-view.md), [toggle](components/toggle.md), [slider](components/slider.md), [picker](components/picker.md), [datePicker](components/date-picker.md), and [pageControl](components/page-control.md). Each binds its natural type (string, boolean, number, or ISO-date string). See [forms.md](forms.md) for putting them together.

Set `bindVariable` to the **variable name** — no `{{}}` braces.

```json
{
  "type": "textField",
  "content": {
    "properties": {
      "placeholder": "Email",
      "bindVariable": "email"
    }
  }
}
```

The variable must be declared at the screen level:

```json
"variables": {
  "email": { "type": "string", "initialValue": "" }
}
```

Any label that references `{{email}}` updates live as the user types.

### Map Output Bindings

Map components write their runtime state into target variables. These are **write-only** — the map pushes values into the variable; use the variable name wrapped in `{{}}`.

| Property | Description |
|----------|-------------|
| `regionBinding` | Writes current visible map region into the variable |
| `selectedAnnotationBinding` | Writes the tapped annotation ID into the variable |
| `userLocationBinding` | Writes the user's current coordinate into the variable |

```json
"properties": {
  "regionBinding": "{{mapRegion}}",
  "selectedAnnotationBinding": "{{selectedId}}",
  "userLocationBinding": "{{userCoord}}"
}
```

### Full Example — Live Bound Input

```json
{
  "type": "screen",
  "content": {
    "variables": {
      "name": { "type": "string", "initialValue": "" }
    },
    "children": [
      {
        "id": "nameField",
        "type": "textField",
        "content": {
          "properties": { "placeholder": "Your name", "bindVariable": "name" },
          "layout": { "height": 48, "constraints": [
            { "type": "leading", "target": "superview", "constant": 24 },
            { "type": "trailing", "target": "superview", "constant": -24 },
            { "type": "top", "target": "superview", "constant": 120 }
          ]}
        }
      },
      {
        "id": "greeting",
        "type": "label",
        "content": {
          "properties": { "text": "Hello, {{name}}!" },
          "layout": { "constraints": [
            { "type": "top", "target": "nameField", "attribute": "bottom", "constant": 16 },
            { "type": "centerX", "target": "superview" }
          ]}
        }
      }
    ]
  }
}
```

---

## Collection Item Variables

Inside collection templates, special variables are available.

| Variable | Description |
|----------|-------------|
| `{{item}}` | Current item data |
| `{{item.$index}}` | 0-based item index |
| `{{$parent}}` | Parent scope (screen variables) |
| `{{$parent.$parent}}` | Grandparent scope |

### Example

```json
{
  "type": "collection",
  "content": {
    "properties": { "data": "{{users}}" },
    "template": {
      "type": "view",
      "content": {
        "children": [
          {
            "type": "label",
            "content": {
              "properties": {
                "text": "{{item.$index + 1}}. {{item.name}}"
              }
            }
          },
          {
            "type": "button",
            "content": {
              "properties": {
                "icon": "{{$parent.likedIds.includes(item.id) ? 'heart.fill' : 'heart'}}"
              },
              "actions": {
                "tap": {
                  "type": "toggleArrayValue",
                  "variableName": "$parent.likedIds",
                  "value": "{{item.id}}"
                }
              }
            }
          }
        ]
      }
    }
  }
}
```

### Accessing Screen Variables from Template

Use `$parent` to access screen-level variables:

```json
"hidden": "{{!$parent.showDetails}}"
"text": "{{$parent.currency}} {{item.price}}"
```

---

## Expression Examples

### Conditional Display

```json
"hidden": "{{!isLoggedIn}}"
"alpha": "{{isEnabled ? 1.0 : 0.5}}"
```

### Dynamic Text

```json
"text": "{{items.length}} {{items.length == 1 ? 'item' : 'items'}}"
"text": "{{isLoading ? 'Loading...' : 'Submit'}}"
```

### Dynamic Styles

```json
"style": {
  "tintColor": "{{isSelected ? '#007AFF' : '#999999'}}"
}
```

### Form Validation

```json
"isEnabled": "{{email.length > 0 && password.length >= 6}}"
```

### List Position

```json
"text": "{{item.$index + 1}} of {{$parent.items.length}}"
```
