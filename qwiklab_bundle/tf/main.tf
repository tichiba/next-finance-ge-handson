module "cli" {
  source  = "terraform-google-modules/gcloud/google"
  version = "~> 3.0.1"

  platform              = "linux"
  additional_components = ["bq", "gsutil", "alpha", "beta"]

  create_cmd_entrypoint    = "chmod +x ${path.module}/scripts/setup.sh ${path.module}/scripts/finish_setup.sh ${path.module}/scripts/cleanup.sh; ${path.module}/scripts/setup.sh"
  create_cmd_body          = "${var.gcp_project_id} ${var.gcp_region} ${var.gcp_zone} ${var.primary_user_email}"
  destroy_cmd_entrypoint   = "chmod +x ${path.module}/scripts/cleanup.sh; ${path.module}/scripts/cleanup.sh"
  destroy_cmd_body         = "${var.gcp_project_id}"
  skip_download            = false
  upgrade                  = false
  gcloud_sdk_version       = "468.0.0"
  service_account_key_file = var.service_account_key_file
}
