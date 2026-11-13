# Bugfixes on maps and streaks

**✅ DONE**

* Map view
  * The date range selector on the map pane's "from" date shows "Dec 31, 1". It should be the earliest QSO date
  * Switching band filters in the map view doesn't automatically update the counts of QSOs on the map--it needs to
  * The map view should show active filters next to QSOs and grids, as well as states and DXCC entities
  * "solar" and "weather" are not modes that should show in map. filter them out
  * "Show Arcs" should be "show paths", but it should make an arc between points, not a straight
line
* Streaks
  * Make no differentiation between timezones on streaks--use UTC time for everything
  * Add an end date to the tracked best streaks
  * Only show "10+ QSOs required for valid activation" when viewing POTA streaks"
  * Split POTA Activations into "successful" and "attempted", where successful counts the more restrictive "10+" and attempted counts the less restrictive "got at least one QSO"
