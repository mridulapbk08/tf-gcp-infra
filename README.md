# tf-gcp-infra

# README.md

## Infrastructure as Code with Terraform

This repository contains Terraform configurations to set up networking infrastructure on Google Cloud Platform (GCP). The configuration includes creating a Virtual Private Cloud (VPC) with specified subnets and routes.

### Status Check for Terraform Templates

To ensure the integrity of Terraform templates, a status check has been added to validate them when a pull request is raised. This ensures that any proposed changes adhere to the defined infrastructure standards.

### Google Cloud Platform Setup

Before using the Terraform templates, make sure to follow these steps to enable required services on Google Cloud Platform:

1. **Enable GCP Service APIs:**
   - Enable only the necessary services (APIs) for your project. Refer to the Google Cloud Console for instructions.
   - Do not enable all APIs; only enable those explicitly needed for your application.

2. **Google Cloud Platform Networking Setup:**
   - Create a Virtual Private Cloud (VPC) with the following configurations:
     - Auto-create subnets should be disabled.
     - Routing mode should be set to regional.
     - No default routes should be created.
   - Create subnets in your VPC:
     - Create two subnets named 'webapp' and 'db' with a /24 CIDR address range.
     - Add a route to 0.0.0.0/0 with the next hop to the Internet Gateway and attach it to your VPC.

### Infrastructure as Code with Terraform

Follow these steps to set up networking resources using Terraform:

1. **Install and Set Up GCP CLI and Terraform:**
   - Install the Google Cloud SDK CLI and Terraform on your local machine.

2. **Terraform Configuration File:**
   - Create a Terraform configuration file (e.g., `main.tf`) with the provided content.
   - Avoid hard-coding values; use variables for flexibility.
   - Ensure that the same Terraform configuration files can be used in the same GCP project and region to create multiple VPCs.

```hcl
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.51.0"
    }
  }
}

provider "google" {
  credentials = file("iacvpc-698253216ddf.json")
  project     = "iacvpc"
  region      = "us-central1"
  zone        = "us-central1-c"
}

# ... (rest of the Terraform configuration)
```

3. **Run Terraform Commands:**
   - Run the following Terraform commands to plan and apply the infrastructure changes:

   ```bash
   terraform plan -var-file="tera.tfvars"
   terraform apply -var-file="tera.tfvars"
   ```

   Replace `"tera.tfvars"` with your variable file if needed.

Now, with the Terraform configurations in place, you can manage and deploy your networking infrastructure on GCP. The status check will automatically validate your Terraform templates during pull requests for improved code review and consistency.