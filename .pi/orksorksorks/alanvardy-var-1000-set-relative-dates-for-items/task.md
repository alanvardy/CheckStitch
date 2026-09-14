# Task

CheckStitch items gain an optional relative date: an integer offset where 0
means today, 1 means tomorrow, and so on. An item with no number has no date;
times are not supported. The offset is edited per item in the checklist detail
view, must round-trip persistence and iCloud/watch sync in the versioned
`checklists.v1` wire format, and when a checklist is run the reminder created
for an item must carry a date-only due date (today + offset, local calendar)
instead of the current always-no-date behavior.