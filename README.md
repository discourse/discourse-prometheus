# Official Prometheus Exporter Plugin for Discourse

The Discourse Prometheus plugin collects key metrics from Discourse and exposes them in the `/metrics` path so prometheus can consume them.

## Adding custom global collectors

The global reporter can pick custom metrics added by other Discourse plugins. The metric needs to define a collect method, and the `name`, `labels`, `description`, `value`, and `type` attributes. See an example [here](https://github.com/discourse/discourse-antivirus/pull/15).

For more information, please see: https://meta.discourse.org/t/prometheus-exporter-plugin-for-discourse/72666

## YJIT web worker metrics

On Ruby 3.4 and Ruby 4, web workers report these metrics with the existing
`type="web"` and `pid` labels. Collection uses ordinary YJIT statistics and does
not enable YJIT or require `--yjit-stats`.

| Metric | Type | Meaning |
| :--- | :--- | :--- |
| `discourse_yjit_enabled` | Gauge | 1 when YJIT is enabled, 0 when disabled or unavailable |
| `discourse_yjit_code_region_size_bytes` | Gauge | Memory mapped for compiled code |
| `discourse_yjit_alloc_size_bytes` | Gauge | Memory allocated on the YJIT Rust heap |
| `discourse_yjit_compilation_failure_total` | Counter | Failed compilations since process start, including causes other than memory pressure |

Memory and failure samples are omitted when YJIT is disabled. Statistics that
are unavailable are omitted rather than reported as zero. Sidekiq processes do
not report YJIT samples.

The sum of code region bytes and allocation bytes is the usage tracked by
`--yjit-mem-size`, whose default is 128 MiB in both versions. This is a soft
limit, so usage can exceed it. The plugin does not export a configured limit
because these runtimes provide no supported getter for it.

For example, compilation failures appearing while combined usage approaches
128 MiB on a worker using defaults warrant investigating a larger budget.
Failures alone do not prove memory exhaustion, and high usage alone does not
prove that more memory will help. Compare request p50 and p95 latency before
and after a controlled budget change under comparable traffic. A failure count
can stop rising after YJIT runs out of space, so a zero failure rate does not
prove that memory is sufficient.

See the [Ruby 3.4 YJIT documentation](https://docs.ruby-lang.org/en/3.4/yjit/yjit_md.html)
and [Ruby 4 YJIT documentation](https://docs.ruby-lang.org/en/4.0/yjit/yjit_md.html)
for memory budget behavior.
