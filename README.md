# Berlioz Automation Helpers
Automation scripts for Berlioz


## Initializing GCP Project for Berlioz
The script does following:
1. Login to GCP account
2. Create service account **berlioz-robot**
3. Create necessary iam roles
4. Assign roles to service account **berlioz-robot**
5. Creates and downloads a key for service account **berlioz-robot**

Running:

```bash
# curl -sL https://docs.berlioz.cloud/scripts/gcp/init | bash -
```
or

```bash
# wget -qO- https://docs.berlioz.cloud/scripts/gcp/init | bash -
```