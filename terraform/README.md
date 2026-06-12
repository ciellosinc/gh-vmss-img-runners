# Terraform Configuration for GitHub VMSS Runners

This directory contains Terraform configurations for deploying GitHub self-hosted runners infrastructure on Azure using Virtual Machine Scale Sets (VMSS).

## Directory Structure

```
terraform/
├── modules/
│   ├── foundation/           # Foundation infrastructure
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── managed-identity.tf
│   │   ├── networking.tf
│   │   ├── compute-gallery.tf
│   │   ├── storage.tf
│   │   └── log-analytics.tf
│   │
│   ├── runtime/              # Runtime infrastructure
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── vmss.tf
│   │   ├── function-app.tf
│   │   ├── monitoring.tf
│   │   └── role-assignments.tf
│   │
│   └── shared/               # Shared naming conventions
│       ├── naming.tf
│       ├── variables.tf
│       └── outputs.tf
│
├── environments/
│   ├── dev/                  # Development environment
│   │   ├── main.tf
│   │   ├── backend.tf
│   │   └── terraform.tfvars
│   ├── test/                 # Test environment
│   │   ├── main.tf
│   │   ├── backend.tf
│   │   └── terraform.tfvars
│   └── prod/                 # Production environment
│       ├── main.tf
│       ├── backend.tf
│       └── terraform.tfvars
│
├── versions.tf               # Provider version constraints
├── providers.tf              # Provider configuration
├── variables.tf              # Root variable definitions
├── defaults.tf               # Centralized defaults
└── README.md
```

## Architecture

### Foundation Module
Creates base infrastructure:
- **Managed Identities** (0-3 based on environment)
- **Virtual Network** with subnet
- **Network Security Group** with outbound rules
- **Load Balancer** (internal, Standard SKU)
- **Compute Gallery** with image definition
- **Storage Accounts** (2x for function apps)
- **Log Analytics Workspace**

### Runtime Module
Creates runtime components (depends on foundation):
- **Application Insights** (2x for monitoring)
- **Role Assignments** (18 RBAC assignments)
- **Virtual Machine Scale Set** (Windows, scale-to-zero)
- **Function Apps** (ScaleOut + ScaleIn)

## Quick Start

### Prerequisites

1. **Terraform** v1.5.0+
   ```bash
   choco install terraform
   ```

2. **Azure CLI** authenticated
   ```bash
   az login
   az account set --subscription "Your-Subscription"
   ```

3. **Image in Compute Gallery** (build with Packer first)

### Deploy Development Environment

```bash
cd terraform/environments/dev

# Initialize Terraform
terraform init

# Plan deployment
terraform plan -var="vmss_admin_password=YourSecurePassword123!" -var="image_version=1.0.0"

# Apply
terraform apply -var="vmss_admin_password=YourSecurePassword123!" -var="image_version=1.0.0"
```

### Deploy Production Environment

```bash
cd terraform/environments/prod

# Initialize with remote backend
terraform init

# Plan with all required variables
terraform plan \
  -var="vmss_admin_password=YourSecurePassword123!" \
  -var="image_version=1.0.0" \
  -var="github_app_id=123456" \
  -var="github_installation_id=12345678" \
  -var="github_private_key=$(cat github-app.pem)" \
  -var="github_organization=your-org"

# Apply
terraform apply -var-file=secrets.tfvars
```

## Environment Differences

| Configuration | Dev | Test | Prod |
|--------------|-----|------|------|
| VM Size | Standard_B4ms | Standard_B4ms | Standard_D4s_v3 |
| Max Capacity | 10 | 10 | 20 |
| OS Disk Type | Standard_LRS | StandardSSD_LRS | Premium_LRS |
| Storage Replication | LRS | LRS | ZRS |
| Hyper-V Generation | V1 | V1 | V2 |
| Managed Identities | System-assigned | 1 shared | 3 dedicated |
| Log Retention | 30 days | 30 days | 730 days |
| RG Protection | No | No | Yes |

## Variables

### Required Variables

| Variable | Description |
|----------|-------------|
| `vmss_admin_password` | Admin password for VMSS instances (sensitive) |
| `image_version` | Image version from compute gallery |

### GitHub Configuration

| Variable | Description |
|----------|-------------|
| `github_auth_strategy` | `GitHubApp` or `PAT` |
| `github_app_id` | GitHub App ID |
| `github_installation_id` | GitHub App Installation ID |
| `github_private_key` | GitHub App private key (sensitive) |
| `github_pat` | Personal Access Token (sensitive) |
| `github_organization` | GitHub organization name |

### Deployment Control

| Variable | Default | Description |
|----------|---------|-------------|
| `deploy_vmss` | `true` | Deploy VMSS |
| `deploy_functions` | `true` | Deploy Function Apps |

## Remote State Configuration

Uncomment and configure `backend.tf` in each environment:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "stterraformstate"
    container_name       = "tfstate"
    key                  = "ghrunners/dev/terraform.tfstate"
  }
}
```

## Outputs

| Output | Description |
|--------|-------------|
| `resource_group_name` | Name of the resource group |
| `vmss_name` | Name of the VMSS |
| `func_scaleout_hostname` | ScaleOut function hostname |
| `func_scalein_hostname` | ScaleIn function hostname |

## Deployment Order

1. **Build Image** (Packer) - Creates VM image in gallery
2. **Deploy Foundation** - Creates base infrastructure
3. **Deploy Runtime** - Creates VMSS and functions

The Terraform configuration handles foundation and runtime as a single deployment, with proper dependencies.

## Cost Optimization

This configuration implements several cost optimizations:

- **Scale-to-Zero**: Initial capacity is 0, VMs only created when needed
- **Environment-Specific Sizing**: Dev uses burstable VMs, prod uses consistent performance VMs
- **Consumption Functions**: Y1 plan, pay only for execution
- **Storage Tiering**: Standard for dev, Premium for prod

**Estimated Annual Savings: $4,840/year**

## Security Features

- **Managed Identities Only**: No storage keys or secrets in config
- **Least Privilege RBAC**: 18 targeted role assignments
- **Disabled Shared Key Access**: Storage accounts use MI only
- **TLS 1.2 Minimum**: All storage accounts require TLS 1.2
- **NSG Outbound Rules**: Only allow required traffic

## Troubleshooting

### Common Issues

**1. Image not found**
```
Error: Image version not found
```
Build the image with Packer first, or set `deploy_vmss = false`.

**2. Storage account name conflict**
```
Error: Storage account name already taken
```
The name includes a random suffix. If still conflicting, destroy and recreate.

**3. Role assignment already exists**
```
Error: Role assignment already exists
```
This can happen if previous deployment failed. Import or delete the existing assignment.

### Validate Configuration

```bash
terraform validate
terraform plan -detailed-exitcode
```

## Integration with Packer

After building an image with Packer, update the `image_version` variable:

```bash
# Get latest image version
az sig image-version list \
  --resource-group rg-ghrunners-dev-cus \
  --gallery-name gh_runner_images_dev \
  --gallery-image-definition 2022-Datacenter-Def \
  --query "[].name" -o tsv | sort -V | tail -1

# Deploy with new version
terraform apply -var="image_version=1.0.1" -var="vmss_admin_password=..."
```

## Related Documentation

- [Migration Plan](../Docs/TERRAFORM_MIGRATION_PLAN.md)
- [Packer Configuration](../packer/README.md)
- [BankFabric Patterns](../../.claude/06-BANKFABRIC-PATTERNS.md)
