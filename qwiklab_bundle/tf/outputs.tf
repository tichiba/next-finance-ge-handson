# Qwiklabs Terraform Outputs

output "project_id" {
  description = "Provisioned GCP Project ID"
  value       = var.gcp_project_id
}

output "gcs_bucket_url" {
  description = "GCS Bucket containing Hands-on PDFs and BigQuery CSVs"
  value       = "gs://${var.gcp_project_id}-next-finance-handson"
}
