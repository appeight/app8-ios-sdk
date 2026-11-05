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
