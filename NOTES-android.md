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
