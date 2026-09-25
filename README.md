# Official Prometheus Exporter Plugin for Discourse

The Discourse Prometheus plugin collects key metrics from Discourse and exposes them in the `/metrics` path so prometheus can consume them.

## Adding custom global collectors

The global reporter can pick custom metrics added by other Discourse plugins. The metric needs to define a collect method, and the `name`, `labels`, `description`, `value`, and `type` attributes. See an example [here](https://github.com/discourse/discourse-antivirus/pull/15).

## Worker timeouts

`discourse_pitchfork_worker_timeouts_total` counts Pitchfork soft worker timeout events. It is exposed after the first event and resets when the collector restarts. Reporting is best effort, with a one-second budget before the worker exits. Hard kills that bypass the soft timeout callback are not counted.

This metric requires a Discourse version that emits the `web_worker_timeout` event. For example, `rate(discourse_pitchfork_worker_timeouts_total[5m])` shows timeouts per second over five minutes.

For more information, please see: https://meta.discourse.org/t/prometheus-exporter-plugin-for-discourse/72666
