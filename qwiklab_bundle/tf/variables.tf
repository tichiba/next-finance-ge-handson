# Qwiklabs Mandatory Values

variable "gcp_project_id" {
  type        = string
  description = "The GCP project ID to apply this config to."
}

variable "gcp_region" {
  type        = string
  description = "The GCP region to apply this config to."
  default     = "us-central1"
}

variable "gcp_zone" {
  type        = string
  description = "The GCP zone to apply this config to."
  default     = "us-central1-a"
}

variable "service_account_key_file" {
  type        = string
  description = "Service account key file location."
  default     = ""
}

variable "primary_user_email" {
  type        = string
  description = "Primary facilitator user email (user_1)."
  default     = ""
}
