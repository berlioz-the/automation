# Berlioz Automation Helpers
Automation scripts for Berlioz

## Initializing GCP Project for Berlioz
The script does following:
1. Login to GCP account
2. Create service account **berlioz-robot**
3. Create necessary iam roles
4. Assign roles to service account **berlioz-robot**
5. Creates and downloads a key for service account **berlioz-robot**. **NOTE:** any existing key would be deleted.

Run using:

```bash
bash -c "$(curl -sL https://raw.githubusercontent.com/berlioz-the/automation/master/gcp/project/init.sh)"
```

or

```bash
bash -c "$(wget -qO- https://raw.githubusercontent.com/berlioz-the/automation/master/gcp/project/init.sh)"
```

## Creating new GCP Project 
The script does following:
1. Login to GCP account
2. Creates a new GCP projecect
2. Create service account **cicd-robot**
4. Assigns Owner role to service account **cicd-robot**
5. Creates and downloads a key for service account **cicd-robot**. **NOTE:** any existing key would be deleted.

Run using:

```bash
bash -c "$(curl -sL https://raw.githubusercontent.com/berlioz-the/automation/master/gcp/project/create.sh)"
```

or

```bash
bash -c "$(wget -qO- https://raw.githubusercontent.com/berlioz-the/automation/master/gcp/project/create.sh)"
```

