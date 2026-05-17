# TextField

Single-line text input.

## Content Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `properties.placeholder` | string | | Placeholder text |
| `properties.bindVariable` | string | | Variable for two-way binding |
| `properties.keyboardType` | KeyboardType | `default` | Keyboard type |
| `properties.textContentType` | TextContentType | | Autofill hint |
| `properties.returnKeyType` | ReturnKeyType | `default` | Return key label |
| `properties.isSecure` | boolean | false | Password field |
| `properties.autocapitalization` | Autocap | `sentences` | Auto-capitalization |
| `properties.autocorrection` | boolean | true | Auto-correction |
| `properties.maxLength` | number | | Max character count |
| `hidden` | boolean/expression | | Hide component |

## KeyboardType Values

| Value | Description |
|-------|-------------|
| `default` | Standard keyboard |
| `asciiCapable` | ASCII only |
| `numbersAndPunctuation` | Numbers and punctuation |
| `URL` | URL keyboard |
| `numberPad` | Number pad |
| `phonePad` | Phone number pad |
| `namePhonePad` | Name and phone pad |
| `emailAddress` | Email keyboard |
| `decimalPad` | Decimal number pad |
| `twitter` | Twitter keyboard |
| `webSearch` | Web search keyboard |
| `asciiCapableNumberPad` | ASCII number pad |

## TextContentType Values (Autofill)

| Value | Autofill |
|-------|----------|
| `name` | Full name |
| `namePrefix` | Name prefix (Mr., Dr., etc.) |
| `givenName` | First name |
| `middleName` | Middle name |
| `familyName` | Last name |
| `nameSuffix` | Name suffix (Jr., III, etc.) |
| `nickname` | Nickname |
| `jobTitle` | Job title |
| `organizationName` | Organization |
| `location` | Location |
| `fullStreetAddress` | Full street address |
| `streetAddressLine1` | Street address line 1 |
| `streetAddressLine2` | Street address line 2 |
| `addressCity` | City |
| `addressState` | State |
| `addressCityAndState` | City and state |
| `sublocality` | Sublocality |
| `countryName` | Country |
| `postalCode` | Postal code |
| `telephoneNumber` | Phone |
| `emailAddress` | Email |
| `URL` | URL |
| `creditCardNumber` | Credit card |
| `username` | Username |
| `password` | Password |
| `newPassword` | New password |
| `oneTimeCode` | OTP/verification code |

## Autocapitalization Values

| Value | Description |
|-------|-------------|
| `none` | No auto-capitalization |
| `words` | Capitalize first letter of each word |
| `sentences` | Capitalize first letter of each sentence |
| `allCharacters` | Capitalize all characters |

## ReturnKeyType Values

`default`, `go`, `google`, `join`, `next`, `route`, `search`, `send`, `yahoo`, `done`, `emergencyCall`, `continue`

## Style: TextFieldStyle

| Property | Type | Description |
|----------|------|-------------|
| `text` | TextModel | Input text styling |
| `placeholder` | TextModel | Placeholder styling |
| `tintColor` | Color | Cursor/selection color |
| `padding` | EdgeInsets | Content padding |
| `material` | Material | Background |

## Triggers

| Trigger | When |
|---------|------|
| `focus` | Field gains focus |
| `blur` | Field loses focus |

## Example

<!-- @dsl-skip: component example with complex style -->
```json
{
  "type": "textField",
  "id": "emailField",
  "content": {
    "properties": {
      "placeholder": "Email address",
      "bindVariable": "email",
      "keyboardType": "emailAddress",
      "textContentType": "emailAddress",
      "returnKeyType": "next",
      "autocapitalization": "none",
      "autocorrection": false
    },
    "style": {
      "material": [
        { "fill": { "solid": "#F5F5F5" } },
        { "corner": { "radius": 8 } }
      ],
      "text": { "fontSize": 16, "color": "#333333" },
      "placeholder": { "fontSize": 16, "color": "#999999" },
      "padding": { "left": 12, "right": 12 }
    },
    "layout": {
      "leading": 20,
      "trailing": 20,
      "height": 50
    },
    "triggers": {
      "focus": "focused",
      "blur": "normal"
    },
    "states": {
      "normal": {
        "style": { "material": [{ "outline": { "lineWidth": 0 } }] }
      },
      "focused": {
        "style": { "material": [{ "outline": { "lineWidth": 2, "fill": { "solid": "#007AFF" } } }] }
      }
    }
  }
}
```
