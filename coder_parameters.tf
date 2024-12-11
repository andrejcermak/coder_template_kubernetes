data "coder_parameter" "project_id" {
  name        = "project_id"
  description = "Project id"
  type        = "string"
  mutable     = false
}
data "coder_parameter" "application_credential_name" {
  name        = "application_credential_name"
  description = "application_credential_name"
  type        = "string"
  mutable     = false
}
data "coder_parameter" "application_credential_id" {
  name        = "application_credential_id"
  description = "application_credential_id"
  type        = "string"
  mutable     = false
}
data "coder_parameter" "application_credential_secret" {
  name        = "application_credential_secret"
  description = "application_credential_secret"
  type        = "string"
  mutable     = false
}

data "coder_parameter" "control_nodes_count"{
  name        = "control_nodes_count"
  description = "control_nodes_count"
  type        = "number"
  mutable     = false
  default     = 1
}

data "coder_parameter" "worker_nodes_count"{
  name        = "worker_nodes"
  description = "worker_nodes"
  type        = "number"
  mutable     = false
  default     = 1
}


data "coder_parameter" "openstack_region"{
  name        = "openstack_region"
  description = "openstack_region"
  type        = "string"
  mutable     = false
  default     = "Brno1"
}
data "coder_parameter" "openstack_identity_provider"{
  name        = "openstack_identity_provider"
  description = "openstack_identity_provider"
  type        = "string"
  mutable     = false
  default     = "https://identity.brno.openstack.cloud.e-infra.cz/v3"
}