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
