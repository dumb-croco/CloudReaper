# CloudReaper

**Self-cleaning cloud infrastructure.** Deploy test environments with a time-to-live, and CloudReaper automatically destroys them when they expire — even if you forget.

---

## How It Works

```
Developer deploys with TTL tag
        |
        v
  Lambda scans every 5 min
  (EventBridge schedule)
        |
        v
  Finds expired resources
  (reads expiry_time tag)
        |
        v
  Fires GitHub repository_dispatch
        |
        v
  GitHub Actions runs
  terraform destroy
```

**One sentence:** EventBridge wakes Lambda every 5 minutes, Lambda scans AWS for tagged resources and checks if their expiry time has passed, and if expired, Lambda triggers a GitHub Actions workflow that runs `terraform destroy`.

---

## Why CloudReaper

CloudReaper is a **reusable control plane**. Deploy it once, and any number of projects can use it — just drop your Terraform code into a folder and go.

- **No code changes needed** to add new infrastructure — just create a new folder under `workloads/`
- **Independent state files** — each project gets its own Terraform state (isolated via unique S3 backend keys in the same bucket), so multiple projects run simultaneously without conflicts
- **Zero maintenance** — the control plane (Lambda + EventBridge) runs continuously and never needs updating
- **Works with any Terraform config** — EC2, RDS, VPC, EKS, whatever you need. If Terraform can create it and it has tags, CloudReaper can manage its lifecycle

### How to add your infrastructure

1. Create a new folder under `workloads/` (e.g., `workloads/my-api/`)
2. Add a `backend.tf` with a unique S3 key:
   ```hcl
   backend "s3" {
     bucket = "cloudreaper-state"
     key    = "cloudreaper/my-api/terraform.tfstate"
     region = "ap-south-1"
   }
   ```
3. Tag all resources with `project`, `expiry_time`, and `managed-by = "cloudreaper"`
4. Add the folder name to `deploy-workload.yml` choices
5. Deploy — Lambda will automatically detect and manage it

---

## Architecture

### Control Plane (deploy once)

| Resource | Purpose |
|---|---|
| `cloudreaper-lambda` | Python 3.12 Lambda that scans for expired resources |
| `cloudreaper-schedule` | EventBridge rule firing every 5 minutes |
| `cloudreaper-lambda-role` | IAM role — `tagging:GetResources` + `secretsmanager:GetSecretValue` + CloudWatch Logs |

### Workloads (deploy/destroy repeatedly, one folder per project)

Each project lives in its own folder under `workloads/` with its own Terraform state. Resources are tagged with:

- `project = "<folder-name>"` — tells Lambda which project to destroy
- `expiry_time = "<ISO 8601 UTC>"` — the source of truth for when to destroy
- `managed-by = "cloudreaper"` — discoverability tag

### State Isolation

Multiple projects share one S3 bucket but each gets a unique state key:

```
cloudreaper-state (one bucket)
├── cloudreaper/control-plane/terraform.tfstate
├── cloudreaper/test1-infra/terraform.tfstate
├── cloudreaper/test2-infra/terraform.tfstate
└── cloudreaper/my-api/terraform.tfstate
```

No cross-project interference. Each project can be deployed, updated, and destroyed independently.

### GitHub Actions Pipelines

| Pipeline | Trigger | What it does |
|---|---|---|
| `setup-control-plane.yml` | Manual, run once | Deploys Lambda + EventBridge |
| `deploy-workload.yml` | Manual (`workflow_dispatch`) | Computes expiry, runs `terraform apply` |
| `destroy-workload.yml` | Automatic (`repository_dispatch`) | Runs `terraform destroy` on expired project |

---

## Quick Start

### Prerequisites

- GitHub repository with these secrets:
  - `AWS_ACCESS_KEY_ID`
  - `AWS_SECRET_ACCESS_KEY`
- A GitHub PAT with `repo` scope, stored in AWS Secrets Manager
- An S3 bucket named `cloudreaper-state` (for Terraform state)
- Terraform 1.10+ (installed by the workflows)

### 1. Store the GitHub PAT in Secrets Manager

```bash
aws secretsmanager create-secret \
  --name cloudreaper/github-pat \
  --secret-string "ghp_your_token_here"
```

Note the ARN from the output.

### 2. Deploy the Control Plane

Set a GitHub **Variable** (not Secret) `CLOUDREAPER_SECRET_ARN` with the Secrets Manager ARN, then go to **Actions > CloudReaper — Setup Control Plane > Run workflow**, type `yes`, and run it.

### 3. Deploy a Workload

Go to **Actions > CloudReaper — Deploy Workload > Run workflow**, pick a project and a TTL, and run it.

### 4. Watch It Work

Lambda runs every 5 minutes. When resources expire, `destroy-workload.yml` triggers automatically.

---

## Why Lambda Triggers Terraform Instead of Deleting Directly

Real infrastructure has dependencies (EC2 inside a subnet inside a VPC). Deleting out of order fails. Terraform already solves dependency-ordered teardown via its state graph. Lambda's only job is *deciding when*, not *how*.

---

## Known Limitations

- **State drift:** If resources are deleted outside this pipeline (manually in the console), Terraform state can drift. A production version would add periodic `terraform refresh` reconciliation.
- **GitHub token expiry:** The PAT used for `repository_dispatch` must remain valid. Consider using a GitHub App for long-term use.

---

## Project Structure

```
CloudReaper/
├── README.md
├── control-plane/
│   ├── main.tf              # Lambda + EventBridge + IAM
│   ├── variables.tf         # github_secret_arn, github_owner, github_repo
│   ├── backend.tf           # S3 state: cloudreaper/control-plane/
│   └── lambda/
│       └── scanner.py       # Tag scanning + GitHub dispatch logic
├── workloads/
│   ├── test1-infra/
│   │   ├── main.tf          # EC2 with expiry tags
│   │   ├── variables.tf     # expiry_time, ttl_hours, project_name
│   │   ├── outputs.tf
│   │   └── backend.tf       # S3 state: cloudreaper/test1-infra/
│   └── test2-infra/
│       ├── main.tf          # EC2 with expiry tags
│       ├── variables.tf     # expiry_time, ttl_hours, project_name
│       ├── outputs.tf
│       └── backend.tf       # S3 state: cloudreaper/test2-infra/
└── .github/
    └── workflows/
        ├── setup-control-plane.yml
        ├── deploy-workload.yml
        └── destroy-workload.yml
```
