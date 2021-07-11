# see: https://meta.discourse.org/t/prometheus-exporter-plugin-for-discourse/72666

## Adding custom global collectors

The global reporter can pick custom metrics added by other Discourse plugins. The metric needs to define a collect method, and the `name`, `labels`, `description`, `value`, and `type` attributes. See an example [here](https://github.com/discourse/discourse-antivirus/pull/15).
