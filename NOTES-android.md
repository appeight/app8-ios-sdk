# Android port notes — behavior changes from `fix/port-findings`

Each section is one iOS commit. Port the behavior exactly; tests referenced are in
`Tests/App8EngineTests/`.

## 1. datePicker stores the time in `time` / `dateAndTime` modes

- Bound-variable write format now depends on `datePickerMode`:
  - `date` (default): `yyyy-MM-dd` (local calendar date) — unchanged.
  - `time`, `dateAndTime`, `countdownTimer`: ISO8601 **local** date-time with the
    device UTC offset, pattern `yyyy-MM-dd'T'HH:mm:ssXXXXX`
    (e.g. `2026-03-04T14:30:00+01:00`). Formatter uses `en_US_POSIX` locale and
    Gregorian calendar; seconds are written, fractional seconds are not.
- Reading (`selectedDate`, bound value, min/max) is unchanged: ISO8601
  internet date-time first, then `yyyy-MM-dd` (local).
- Test: `PortFindingsTests.testDatePicker*`.

## 2. textView fires `onTextChange`

- On every user edit, textView now dispatches the `onTextChange` trigger exactly
  like textField: actions run against the component's variable store with a
  `$value` overlay = the new full text, and dispatch goes through the analytics
  path (`dispatchTrigger`), so author-declared `analytics` for `onTextChange` fire.
- Fires on each change (not debounced), after the two-way binding is notified.
- Shared helper on iOS: `CBaseViewModel.dispatchTextChange(_:)`.
- Test: `PortFindingsTests.testTextViewFiresOnTextChange`.

## 3. `resetVariables` restores initial values (never deletes)

- Each variable snapshots its "initial value" at definition time, *after*
  resolution (evaluated `{{…}}` initialValue, resolved datasource, injected
  navigation param, or type default). Computed variables have no snapshot.
- `resetVariables` sets every non-computed variable in the target stores back to
  that snapshot (emitting change notifications), then recomputes computed
  dependents. Variables are never removed (old behavior: `store.reset()` deleted
  all variables of the acting component's store).
- Scope resolution from the acting component's store chain
  `[own, parent, …, root]` (root = store without parent = app store):
  - `component` → `[own]`
  - `screen` (**default when `scope` is omitted**) → chain minus root
    (if the chain has a single store, that store)
  - `app` → `[root]`
  - `all` → whole chain
  Reset root-first (outermost first).
- Tests: `PortFindingsTests.testResetVariables*`, `VariableActionHandlerTests.testResetVariables`.

## 4. `setMultipleValues` can't wedge the store in batch mode

- Unknown variable names are validated **before** any write: the whole batch is
  rejected (`undefinedVariable`) and nothing is applied. In scoped stores the
  check covers local + parent-chain names before writing either.
- If a write still throws midway (e.g. type mismatch), the store leaves batch
  mode (`isUpdating = false`), recomputes dependents of the variables already
  written (errors swallowed), then rethrows.
- On success, batch mode is cleared *before* dependents are recomputed, so a
  throwing computed expression also can't leave the flag set.
- Invariant to port: after `setMultipleValues` returns or throws, a later
  `setValue` always recomputes dependents.
- Tests: `PortFindingsTests.testSetMultipleValues*`.

## 5. Array literals keep non-literal elements

- Parser: `[a, b, …]` where every element is a literal → literal array (as
  before). Otherwise → new node `arrayLiteral(elements: [Node])` keeping **all**
  element nodes in order (old code silently dropped non-literals:
  `[1, x, 3]` → `[1, 3]`).
- Evaluator: evaluate each element in order; a `nil` result becomes `NSNull`
  (null) so indices are preserved. Nested arrays work recursively.
- Dependency extraction walks every element (so `{{[1, x]}}` as a computed
  variable recomputes when `x` changes).
- Tests: `PortFindingsTests.testArrayLiteral*`, `testComputedArrayLiteralRecomputes`.

## 6. `toString()` of arrays / objects returns compact JSON

- `toString(x)`: string → itself; bool → `true`/`false`; Int → digits; Double →
  unchanged (Swift `String(Double)`, e.g. `2.5`, `2.0`); nil/null → `""`.
- **Arrays and objects** → compact JSON, keys sorted, no spaces, slashes not
  escaped (JS `JSON.stringify` shape with sorted keys): `toString([1,'a',true])`
  → `[1,"a",true]`; `{b:1,a:"x"}` → `{"a":"x","b":1}`. Nested nil → `null`,
  booleans stay `true`/`false`. (Old: `Optional([1, "a", true])`.) Android's
  current `"Optional(" + describe + ")"` must be replaced.
- Fallback for anything non-JSON-encodable: platform description.
- Test: `PortFindingsTests.testToStringOfCollectionsIsJSON`.

## 7. Docs example test: type tables derived from the engine (test-only)

- No runtime change. The iOS docs test now accepts any action type the engine's
  `Action.Type` enum decodes (previously a hand table missing `complete`,
  `incrementArrayItem`, `emit`) and any component `CType.Key` plus the doc
  aliases `scroll`, `stack`, `spacer`, `pager` (previously missing e.g.
  `datePicker`, `toggle`, `slider`, `picker`, `video`, `tableView`, `shimmer`).
- If Android has an equivalent docs/conformance validator with a hard-coded
  type list, derive it from the engine enums the same way.

## 8. stackView `cornerRadius` rounds and clips children

- `properties.cornerRadius` (> 0) on a stackView now clips the arranged
  children to the rounded rect (continuous corner curve), matching the docs
  ("clips children to rounded bounds"). Before, only the optional
  `backgroundColor` layer was rounded, so a child with its own background (e.g.
  the header in `TestExamples/screens/StackViewProfileCard`) painted square
  corners over it.
- Applies whether or not `backgroundColor` is set; radius ≤ 0/absent → no clip.
- iOS clips an inner content container, not the component root, so a material
  `shadow` on the stack still renders outside the bounds. Android: clip the
  children container (e.g. `Modifier.clip(RoundedCornerShape(r))` on the inner
  layout), keep shadow on the outer node.
- Tests: `PortFindingsTests.testStackViewCornerRadius*`.

## 9. `prominentGlass` title colour — no iOS change (not fixed)

- No behavior change shipped. Investigation: on iOS 26.2 the configuration
  already ends with a white `baseForegroundColor`/title-attributes colour when
  forced, and `titleLabel.textColor` reads white, yet UIKit's prominent-glass
  compositing still draws the title light cyan on a blue tint. Overriding
  `baseForegroundColor`, the title-attributes transformer and `tintColor` all
  had no visible effect, so the iOS fix needs a different approach (e.g. not
  using `.prominentGlass()` for tinted buttons, or a custom title view).
- Android: keep the current white default for `prominentGlass`; it is the
  intended look.

## 10. Spec drift: shadow `opacity` / `isHollow`, outline `position` optional

Decision: make the decoders lenient with the **documented** defaults (styles.md
unchanged). Safe because a scan of every DSL JSON under ~/dev/app8 (TestExamples,
conformance envelopes, shoppu, a2ui, …) found 202 shadow layers, all specifying
both `isHollow` (144 true / 58 false) and `opacity`, and 254 outlines, only one
lacking `position` (StringConcat `whiteOutline`, which also lacks `fill` and
still fails). So no existing app changes rendering.

- Shadow layer: `opacity` optional, default `1.0`; `isHollow` optional,
  default `false` (non-hollow: the shadow layer gets a background of the shadow
  colour). `color`, `radius`, `offset` remain required. Before, a layer missing
  either field failed to decode and was silently dropped from `layers`.
- Outline: `position` optional, default `inside`. `lineWidth`, `fill` required.
- Programmatic (non-JSON) Swift initialisers keep `isHollow: true` as their
  parameter default — irrelevant for the DSL.
- Tests: `PortFindingsTests.testShadowLayer*`, `testShadowWithoutOptionalFieldsIsNotDropped`,
  `testOutlinePositionDefaultsToInside`.

## 11. facetheory shop "hang" = crash in `navigationBar.search.fillsBar`

- Root cause (iOS only): the iOS preview host never wrote its ready sentinel
  because the app **crashed**: `fillsBar` + `placement: integrated` put
  `navigationItem.searchBarPlacementBarButtonItem` into `leftBarButtonItems`
  in `viewWillAppear`; UIKit raises NSInvalidArgumentException ("only supported
  in UIToolbar") on iPhone/iOS 26.2. Nested collections / datasources were not
  involved (the screen renders in ~0.6 s once fixed).
- Fix: never relocate the search item; it stays in its integrated slot and is
  widened in place by the existing width constraint (bar width − 44pt, − 72pt
  while focused on phone). Visual result: field spans the bar from the leading
  margin (verified render of demo__facetheory-shop).
- Android: no equivalent UIKit constraint. Contract to keep: `fillsBar: true`
  with `integrated` → search field spans the bar width (minus trailing room for
  the ✕ while focused). Affects facetheory shop/cart/account.
- Tests: `SearchFillsBarTests` (tab-hosted and plain screen).
