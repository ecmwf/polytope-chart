# polytope-chart

Helm chart for the Polytope data retrieval server backed by the BITS routing engine.

## Schedule check

The `schedule_released` check fetches the ECMWF pgen schedule XML from GitHub
at pod startup and caches it in memory for the lifetime of the process. It
needs a GitHub Personal Access Token (PAT) to authenticate.

The PAT is read from the `SCHEDULE_TOKEN` environment variable. The chart can
populate that variable from a Kubernetes Secret in two ways: manually created,
or provisioned automatically via the HashiCorp Vault Secrets Operator.

### Option 1 — Manual Secret

Create the Secret in your namespace:

```bash
kubectl create secret generic <secret-name> \
  --from-literal=schedule-token=ghp_YOUR_PAT \
  -n <namespace>
```

Then reference it in your values:

```yaml
schedule:
  url: "https://raw.githubusercontent.com/ecmwf/pgen/develop/share/pgen/schedule.xml"
  secretName: <secret-name>
  secretKey: schedule-token
```

### Option 2 — Vault Secrets Operator

Store the PAT in Vault at `k8s_clusters/<cluster>/<namespace>` under a key
(e.g. `schedule-token`). Then enable the VSO integration:

```yaml
schedule:
  url: "https://raw.githubusercontent.com/ecmwf/pgen/develop/share/pgen/schedule.xml"
  secretName: <secret-name>
  secretKey: schedule-token
  vault:
    enabled: true
    path: <cluster>/<namespace>   # e.g. k8s-applications-test/polytope-dev
```

The chart creates a `VaultStaticSecret` CRD that syncs the Vault key into the
Kubernetes Secret given by `secretName`. The deployment then mounts it as the
`SCHEDULE_TOKEN` env var — identical to the manual flow.

### Values reference

| Key | Default | Description |
|-----|---------|-------------|
| `schedule.url` | `""` | Raw URL to the schedule XML |
| `schedule.token` | `""` | Plaintext PAT fallback (prefer a Secret) |
| `schedule.secretName` | `""` | K8s Secret that holds the PAT |
| `schedule.secretKey` | `schedule-token` | Key inside the Secret |
| `schedule.vault.enabled` | `false` | Create a VaultStaticSecret CRD |
| `schedule.vault.path` | `""` | Vault path (`<cluster>/<namespace>`) |
| `schedule.vault.refreshAfter` | `"60s"` | How often VSO re-syncs |
