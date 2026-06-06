# Forms & Inputs

A practical guide to building input-driven interfaces — sign-up flows, settings, filters, checkout — by combining the input components with reactive variables. If you're looking for one component's full reference, follow the links; this page is about wiring them together well.

## The Input Components

| Component | Captures | Binds a | Reference |
|-----------|----------|---------|-----------|
| [textField](components/text-field.md) | Single-line text | string | `bindVariable` |
| [textView](components/text-view.md) | Multi-line text | string | `bindVariable` |
| [toggle](components/toggle.md) | On/off | boolean | `bindVariable` |
| [slider](components/slider.md) | A number in a range | number | `bindVariable` |
| [picker](components/picker.md) | One choice from a set | string | `bindVariable` |
| [datePicker](components/date-picker.md) | A date / time | string (ISO) | `bindVariable` |

They all share one idea: **`bindVariable`**.

## Two-Way Binding

Set `bindVariable` to a screen variable's **name** (no `{{}}`). The engine then keeps the input and the variable in lockstep — user edits flow into the variable, and action-driven variable changes flow back into the input. Declare the variable at screen scope:

```json
"variables": {
  "email": { "type": "string", "initialValue": "" },
  "plan":  { "type": "string", "initialValue": "free" },
  "seats": { "type": "number", "initialValue": 1 },
  "agreed": { "type": "boolean", "initialValue": false }
}
```

```json
{ "type": "textField", "content": { "properties": { "placeholder": "Email", "bindVariable": "email" } } }
```

Any other component that references `{{email}}` updates live. See [variables.md → Variable Binding](variables.md#variable-binding) for the full rules.

> **`bindVariable` vs. the value prop**: `bindVariable` is the bare name; the value prop (`value`, `isOn`, `selectedValue`, `selectedDate`) takes a `{{expression}}`. For a simple bound input you only need `bindVariable`.

## Validation with Computed Variables

Derive validity from inputs using [computed variables](variables.md#computed-variables) — they recalculate automatically whenever an input changes, so the UI stays correct with no action wiring.

```json
"variables": {
  "email": { "type": "string", "initialValue": "" },
  "password": { "type": "string", "initialValue": "" },
  "agreed": { "type": "boolean", "initialValue": false },

  "emailValid":    { "type": "boolean", "computed": "{{match(email, '^[^@]+@[^@]+\\.[^@]+$')}}" },
  "passwordValid": { "type": "boolean", "computed": "{{password.length >= 8}}" },
  "canSubmit":     { "type": "boolean", "computed": "{{emailValid && passwordValid && agreed}}" }
}
```

Then drive presentation off the derived flags:

```json
// Inline error appears once the field is non-empty but invalid
{ "type": "label", "content": {
  "properties": { "text": "Enter a valid email", "hidden": "{{email.length == 0 || emailValid}}" }
} }

// Dim the submit button while the form is invalid
{ "type": "button", "content": {
  "properties": { "text": "Create account" },
  "style": { "alpha": "{{canSubmit ? 1.0 : 0.5}}" }
} }
```

The [`match()`](variables.md#string-functions) regex helper, `.length`, and the comparison/logical operators in [variables.md → Operators](variables.md#operators) cover most validation needs.

> **Gating the button**: input components ([toggle](components/toggle.md), [slider](components/slider.md), [picker](components/picker.md), [datePicker](components/date-picker.md)) honor an `isEnabled` expression today. For `button`, `isEnabled` is `[Planned]` — until it lands, dim the button with an `alpha` expression as above and **validate in the host** when the submit event arrives (next section). That keeps the form honest even if a tap slips through.

## Submitting

To run host-side logic (call an API, complete a purchase), emit an event and let the host handle it — see [events.md](events.md):

```json
"actions": {
  "tap": {
    "type": "emit",
    "name": "signup.submit",
    "payload": { "email": "{{email}}", "plan": "{{plan}}", "seats": "{{seats}}" }
  }
}
```

Re-check `canSubmit` in the payload (or host-side) so a stray tap can't submit an invalid form, and flip an `isSubmitting` flag to show progress (next section).

## Loading States

While a submit or fetch is in flight, show the user something is happening. Two tools:

- [activityIndicator](components/activity-indicator.md) — a spinner for indeterminate waits. Bind `isAnimating` to your loading flag.
- [shimmer](components/shimmer.md) — a skeleton that mirrors the shape of incoming content. Better than a spinner for lists and cards.

```json
// Button label + spinner driven by one flag
{ "type": "label", "content": { "properties": { "text": "{{isSubmitting ? 'Creating…' : 'Create account'}}" } } }
{ "type": "activityIndicator", "content": { "properties": { "isAnimating": "{{isSubmitting}}" } } }
```

Pattern: show the [shimmer skeleton](components/shimmer.md#example) while `isLoading`, hide it (`"hidden": "{{!isLoading}}"`) and reveal real content when the data arrives.

## Keyboard & Focus

For multi-field forms, move the user through fields smoothly:

- Set `returnKeyType: "next"` on each field and `"done"` on the last ([textField](components/text-field.md#returnkeytype-values)).
- Use the `focus`, `focusNext`, `focusPrevious`, and `dismissKeyboard` [actions](actions.md#focus-actions) to script focus order.
- Set `textContentType` for iOS autofill (email, OTP, new-password), and `keyboardType` to match the data.

## Putting It Together

A minimal, valid-gated form:

```json
{
  "type": "screen",
  "content": {
    "navigationBar": { "title": "Sign up" },
    "variables": {
      "email": { "type": "string", "initialValue": "" },
      "agreed": { "type": "boolean", "initialValue": false },
      "isSubmitting": { "type": "boolean", "initialValue": false },
      "emailValid": { "type": "boolean", "computed": "{{match(email, '^[^@]+@[^@]+\\.[^@]+$')}}" },
      "canSubmit": { "type": "boolean", "computed": "{{emailValid && agreed && !isSubmitting}}" }
    },
    "children": [
      {
        "type": "textField",
        "content": {
          "properties": { "placeholder": "Email", "bindVariable": "email", "keyboardType": "emailAddress", "textContentType": "emailAddress" },
          "layout": { "leading": 20, "trailing": 20, "top": 24, "height": 48 }
        }
      },
      {
        "type": "toggle",
        "content": {
          "properties": { "bindVariable": "agreed" },
          "layout": { "leading": 20, "top": 88 }
        }
      },
      {
        "type": "button",
        "content": {
          "properties": { "text": "Create account" },
          "style": { "alpha": "{{canSubmit ? 1.0 : 0.5}}" },
          "actions": { "tap": { "type": "emit", "name": "signup.submit", "payload": { "email": "{{email}}", "valid": "{{canSubmit}}" } } },
          "layout": { "leading": 20, "trailing": 20, "top": 140, "height": 50 }
        }
      }
    ]
  }
}
```

## See Also

- [variables.md](variables.md) — binding, computed variables, expression functions
- [actions.md](actions.md) — focus, keyboard, and emit actions
- [events.md](events.md) — handling form submissions in the host
- [states.md](states.md) — per-component focus/blur visual states
