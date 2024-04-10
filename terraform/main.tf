terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">5.0.0"
    }
  }
}

provider "google" {
  # credentials = file("iacvpc-df8e76bed914.json")

  project = var.project_id
  region  = var.region
  zone    = var.zone
}

resource "google_service_account" "mywebapp_service_account" {
  account_id                   = var.account_id
  display_name                 = " MyWebapp Service Account"
  project                      = var.project_id
  create_ignore_already_exists = true
}

resource "google_service_account" "cloud_function_service_account" {
  account_id                   = "cloudfunction-service-account"
  display_name                 = "My Cloud Function Service Account"
  project                      = var.project_id
  create_ignore_already_exists = true
}

#creating a vpc
resource "google_compute_network" "vpc_network" {
  name                            = var.my_personal_vpc_network
  auto_create_subnetworks         = var.auto_create_subnets
  routing_mode                    = var.routing_mode
  delete_default_routes_on_create = var.delete_default_routes

}

#creating a subnet "webapp"
resource "google_compute_subnetwork" "webapp" {
  name          = var.webapp_subnet
  ip_cidr_range = var.webapp_cidr
  network       = google_compute_network.vpc_network.self_link
  region        = var.region

}

#creating a subnet "db"
resource "google_compute_subnetwork" "db" {
  name          = var.db_subnet
  ip_cidr_range = var.db_cidr
  network       = google_compute_network.vpc_network.self_link
  region        = var.region

}


#creating a subnet for load balancer
resource "google_compute_subnetwork" "load_balancer_subnet" {
  name          = "lb-subnet"
  ip_cidr_range = "10.3.0.0/24"
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
  network       = google_compute_network.vpc_network.self_link
  region        = var.region
}


#adding route to "webapp"
resource "google_compute_route" "route" {
  name             = var.web_app_route
  dest_range       = var.webapp_route_dest_range
  network          = google_compute_network.vpc_network.self_link
  depends_on       = [google_compute_subnetwork.webapp]
  next_hop_gateway = var.next_hop_gateway
  priority         = 100
}

resource "google_compute_firewall" "allow_application_traffic" {
  name    = var.firewall
  network = google_compute_network.vpc_network.name

  allow {
    protocol = var.protocol
    ports    = ["5000", "22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server", "https-server"]

}

# resource "google_compute_firewall" "deny_ssh" {
#   name    = "deny-ssh"
#   network = google_compute_network.vpc_network.name

#   deny {
#     protocol = var.protocol
#     ports    = ["22"]
#   }

#   source_ranges = ["0.0.0.0/0"] 
#   target_tags   = ["http-server", "https-server"]
# }








# compute region instance 
resource "google_compute_region_instance_template" "webapp_template" {
  name_prefix  = "webapp-region-instance-template"
  machine_type = var.instancemachinetype
  region       = var.region

  depends_on = [google_compute_subnetwork.webapp,
    google_sql_database_instance.db_instance,
    google_sql_database.database,
    google_sql_user.users,
    google_service_account.mywebapp_service_account
  ]

  metadata = {
    startup-script = <<-EOT
#!/bin/bash
echo -e "DB_HOST=${length(google_sql_database_instance.db_instance.ip_address) > 0 ? google_sql_database_instance.db_instance.ip_address[0].ip_address : null}\nUSERNAME=${google_sql_user.users.name}\nPASSWORD=${random_password.password.result}\nDBNAME=${google_sql_database.database.name}" > /tmp/.env
sudo su
sudo mv -f /tmp/.env /home/csye6225/webapp-main/.env
sudo chown -R csye6225:csye6225 /home/csye6225/webapp-main
sudo systemctl restart webapp
EOT
  }

  disk {
    source_image = var.srcimage
    auto_delete  = var.auto_delete
    boot         = true
    disk_size_gb = var.instancesize
    disk_type    = var.instancetype
    disk_encryption_key {
      kms_key_self_link = google_kms_crypto_key.vm_key.id
    }
  }

  network_interface {
    network    = google_compute_network.vpc_network.id
    subnetwork = google_compute_subnetwork.webapp.id
    access_config {
      network_tier = var.instancenetworktier
    }
  }


  service_account {
    email  = google_service_account.mywebapp_service_account.email
    scopes = ["cloud-platform"]
  }

  tags = ["http-server", "https-server"]

}


#service account update
resource "google_kms_crypto_key_iam_binding" "vm_key" {
  provider      = google-beta
  crypto_key_id = google_kms_crypto_key.vm_key.id
  role          = "roles/owner"

  members = [
    "serviceAccount:service-892626759105@compute-system.iam.gserviceaccount.com",
  ]
}


# Compute Health Check
resource "google_compute_health_check" "webapp_health_check" {
  name                = "webapp-health-check"
  check_interval_sec  = var.check_intervalsec
  timeout_sec         = var.timeoutsec
  healthy_threshold   = var.healthythreshold
  unhealthy_threshold = var.unhealthythreshold

  http_health_check {
    port         = "5000"
    request_path = "/healthz"
  }
}

# Compute Autoscaler
resource "google_compute_region_autoscaler" "webapp_autoscaler" {
  name   = "webapp-autoscaler"
  region = var.region
  target = google_compute_region_instance_group_manager.webapp_instance_group_manager.self_link
  autoscaling_policy {
    min_replicas         = var.minreplicas
    max_replicas         = var.maxreplicas
    cooldown_period = var.cooldownperiod
    cpu_utilization {
      target = var.cputarget
    }
  }
}

# Compute Instance Group Manager
resource "google_compute_region_instance_group_manager" "webapp_instance_group_manager" {
  name = "webapp-instance-group-manager"
  version {
    name              = "instance_manager_version"
    instance_template = google_compute_region_instance_template.webapp_template.self_link
  }
  named_port {
    name = "http"
    port = "5000"
  }
  distribution_policy_zones = ["us-central1-b", "us-central1-c"]
  region                   = var.region
  base_instance_name       = "webapp"

  auto_healing_policies {
    health_check      = google_compute_health_check.webapp_health_check.self_link
    initial_delay_sec = 300
  }
}

resource "google_compute_managed_ssl_certificate" "default" {
  name     = "webapp-google-managed-ssl-certificate"
  provider = google-beta
  project  = var.project_id
  managed {
    domains = [var.domainname]
  }
}

# Firewall Rule - Allow Load Balancer Access
resource "google_compute_firewall" "default" {
  name          = "allow-lb-access"
  direction     = "INGRESS"
  network       = google_compute_network.vpc_network.id
  source_ranges = var.sourceranges


  allow {
    protocol = var.protocol
    ports    = ["5000"]
  }

  source_tags = ["http-server", "https-server"] # Google Load Balancer IP ranges
}

# Load Balancer
resource "google_compute_global_forwarding_rule" "lb_forwarding_rule" {
  name                  = "webapp-lb-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  target                = google_compute_target_https_proxy.default.id
  port_range            = "443"
}



resource "google_compute_target_https_proxy" "default" {
  name             = "webapp-lb-proxy"
  url_map          = google_compute_url_map.default.id
  ssl_certificates = [google_compute_managed_ssl_certificate.default.id]
  depends_on       = [google_compute_managed_ssl_certificate.default]
}

resource "google_compute_url_map" "default" {
  name            = "webapp-lb-url-map"
  default_service = google_compute_backend_service.default.id
}

resource "google_compute_backend_service" "default" {
  name                  = "webapp-lb-backend-service"
  project               = var.project_id
  provider              = google-beta
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  locality_lb_policy    = "ROUND_ROBIN"
  timeout_sec           = 30
  enable_cdn            = false
  health_checks         = [google_compute_health_check.webapp_health_check.id]
  backend {
    group           = google_compute_region_instance_group_manager.webapp_instance_group_manager.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
    max_utilization = 0.05
  }
  log_config {
    enable = true
  }
  depends_on = [google_compute_health_check.webapp_health_check, google_compute_region_instance_group_manager.webapp_instance_group_manager]
}

# DNS Record Update
resource "google_dns_record_set" "a_record" {
  name         = var.domainname
  type         = "A"
  ttl          = 300
  managed_zone = var.dnszone
  rrdatas      = [google_compute_global_forwarding_rule.lb_forwarding_rule.ip_address]
}
































































# resource "google_compute_instance" "webapp_instance" {
#   boot_disk {
#     auto_delete = var.auto_delete

#     initialize_params {
#       image = "projects/iacvpc/global/images/my-custom-image-20240319065110"
#       size  = var.instancesize
#       type  = var.instancetype
#     }

#     mode = var.instancemode
#   }
#   metadata = {
#     startup-script = <<-EOT
# #!/bin/bash
# echo -e "DB_HOST=${length(google_sql_database_instance.db_instance.ip_address) > 0 ? google_sql_database_instance.db_instance.ip_address[0].ip_address : null}\nUSERNAME=${google_sql_user.users.name}\nPASSWORD=${random_password.password.result}\nDBNAME=${google_sql_database.database.name}" > /tmp/.env
# sudo su
# sudo mv -f /tmp/.env /home/csye6225/webapp-main/.env
# sudo chown -R csye6225:csye6225 /home/csye6225/webapp-main
# sudo systemctl restart webapp
# EOT
#   } 
#   machine_type = var.instancemachinetype
#   name         = var.instancename
#   tags   = ["http-server", "https-server"]
#   depends_on = [
#     google_compute_network.vpc_network, google_compute_subnetwork.webapp, google_sql_database_instance.db_instance
#   ]
#    service_account {
#     email  = google_service_account.mywebapp_service_account.email
#     scopes = ["cloud-platform"]  
#   }


#   network_interface {
#     access_config {
#       network_tier = var.instancenetworktier
#     }

#     subnetwork = google_compute_subnetwork.webapp.self_link
#   }
# }
resource "google_compute_global_address" "private_ip" {
  project       = var.project_id
  name          = "my-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc_network.self_link
}

resource "google_service_networking_connection" "private_vpc_connection" {

  network                 = google_compute_network.vpc_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip.name]
  depends_on = [
    google_compute_network.vpc_network,
    google_project_service.service_networking,
    google_compute_global_address.private_ip
  ]
}

resource "google_compute_network_peering_routes_config" "default" {
  peering = google_service_networking_connection.private_vpc_connection.peering
  network = google_compute_network.vpc_network.name

  import_custom_routes = true
  export_custom_routes = true

  depends_on = [
    google_compute_network.vpc_network,
    google_service_networking_connection.private_vpc_connection
  ]
}


resource "google_project_service" "service_networking" {
  service            = "servicenetworking.googleapis.com"
  disable_on_destroy = true
}

resource "random_id" "db_name_suffix" {
  byte_length = 4
}


resource "google_project_service_identity" "gcp_sa_cloud_sql" {
  project  = var.project_id
  provider = google-beta
  service  = "sqladmin.googleapis.com"
}



resource "google_kms_crypto_key_iam_binding" "crypto_key" {
  provider      = google-beta
  crypto_key_id = google_kms_crypto_key.cloudsql_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  members = [
    "serviceAccount:${google_project_service_identity.gcp_sa_cloud_sql.email}",
  ]
}
resource "google_sql_database_instance" "db_instance" {
  project             = var.project_id
  name                = "webappsdb-6"
  region              = var.region
  database_version    = "MYSQL_8_0"
  deletion_protection = false

  depends_on = [google_service_networking_connection.private_vpc_connection]
  settings {
    tier              = "db-n1-standard-4"
    availability_type = "REGIONAL"
    disk_type         = "pd_ssd"
    disk_size         = 100

    backup_configuration {
      enabled            = true
      binary_log_enabled = true
      start_time         = "03:00"
      location           = "us-central1"
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc_network.id
    }

  }

  encryption_key_name = google_kms_crypto_key.cloudsql_key.id

}


resource "google_sql_database" "database" {
  name     = "webapp"
  instance = google_sql_database_instance.db_instance.name
}

resource "google_sql_user" "users" {
  name     = "webapp"
  instance = google_sql_database_instance.db_instance.name
  password = random_password.password.result
}

resource "random_password" "password" {
  length  = 16
  special = false
}


provider "google-beta" {
  region = var.region
  zone   = var.zone
}



resource "google_project_iam_binding" "logging_admin_binding" {
  project = var.project_id
  role    = "roles/logging.admin"
  members = [
    "serviceAccount:${google_service_account.mywebapp_service_account.email}",
  ]
}

resource "google_project_iam_binding" "monitoring_metric_writer_binding" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  members = [
    "serviceAccount:${google_service_account.mywebapp_service_account.email}",
  ]
}

resource "google_vpc_access_connector" "connector" {
  name          = "vpc-connector"
  ip_cidr_range = "10.8.0.0/28"
  network       = google_compute_network.vpc_network.self_link
  machine_type  = "f1-micro"
  min_instances = 2
  max_instances = 3
  depends_on    = [google_compute_network.vpc_network]
}

resource "google_compute_network_peering_routes_config" "peering_primary_routes" {
  peering              = google_service_networking_connection.private_vpc_connection.peering
  network              = google_compute_network.vpc_network.name
  import_custom_routes = true
  export_custom_routes = true
  depends_on           = [google_service_networking_connection.private_vpc_connection, google_compute_network.vpc_network]
}

resource "google_pubsub_topic" "verify_emailtopic" {
  name                       = "verify_email"
  message_retention_duration = "604800s"

}

resource "google_pubsub_subscription" "verify_email_subscription" {
  name  = "verify_emailsubscription"
  topic = google_pubsub_topic.verify_emailtopic.name

  message_retention_duration = "604800s" # 7 days in seconds
  ack_deadline_seconds       = 10

}



resource "google_project_iam_binding" "pubsub" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  members = [
    "serviceAccount:${google_service_account.mywebapp_service_account.email}"
  ]
}

resource "google_project_iam_member" "pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.mywebapp_service_account.email}"
}

resource "google_project_iam_member" "vpc_access_admin_1" {
  project = var.project_id
  role    = "roles/vpcaccess.admin"
  member  = "serviceAccount:${google_service_account.mywebapp_service_account.email}"
}




resource "google_project_iam_member" "pubsub_admin" {
  project = var.project_id
  role    = "roles/pubsub.admin"
  member  = "serviceAccount:${google_service_account.mywebapp_service_account.email}"
}



# Assign VPC Access Admin role to the service account
resource "google_project_iam_member" "vpc_access_admin_2" {
  project = var.project_id
  role    = "roles/vpcaccess.admin"
  member  = "serviceAccount:${google_service_account.mywebapp_service_account.email}"
}


resource "google_project_iam_member" "cloud_function_developer_role" {
  project = var.project_id
  role    = "roles/cloudfunctions.viewer"
  member  = "serviceAccount:${google_service_account.mywebapp_service_account.email}"
}

resource "google_project_iam_member" "cloud_function_developer" {
  project = var.project_id
  role    = "roles/cloudfunctions.developer"
  member  = "serviceAccount:${google_service_account.mywebapp_service_account.email}"
}

resource "google_project_iam_member" "eventarc_developer" {
  project = var.project_id
  role    = "roles/eventarc.developer"
  member  = "serviceAccount:${google_service_account.mywebapp_service_account.email}"
}

resource "google_project_iam_member" "service_account_user" {
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.mywebapp_service_account.email}"
}

resource "google_project_iam_member" "eventarc_event_receiver" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${google_service_account.mywebapp_service_account.email}"
}

resource "google_project_iam_member" "service_account_token_creator" {
  project = var.project_id
  role    = "roles/iam.serviceAccountTokenCreator"
  member  = "serviceAccount:${google_service_account.mywebapp_service_account.email}"
}

resource "google_project_iam_member" "log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.mywebapp_service_account.email}"
}

resource "google_project_iam_member" "artifact_registry_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.createOnPushWriter"
  member  = "serviceAccount:${google_service_account.mywebapp_service_account.email}"
}

resource "google_project_iam_member" "storage_object_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.mywebapp_service_account.email}"
}

resource "google_project_iam_member" "run_admin" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.mywebapp_service_account.email}"
}

resource "google_project_iam_member" "appengine_app_admin" {
  project = var.project_id
  role    = "roles/appengine.appAdmin"
  member  = "serviceAccount:${google_service_account.mywebapp_service_account.email}"
}

resource "google_project_iam_member" "compute_instance_admin_v1" {
  project = var.project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:${google_service_account.mywebapp_service_account.email}"
}

resource "google_project_iam_member" "cloudbuild_worker_pool_user" {
  project = var.project_id
  role    = "roles/cloudbuild.workerPoolUser"
  member  = "serviceAccount:${google_service_account.mywebapp_service_account.email}"
}

resource "google_project_iam_member" "cloudbuild_worker_pool_user1" {
  project = var.project_id
  role    = "roles/cloudfunctions.admin"
  member  = "serviceAccount:${google_service_account.mywebapp_service_account.email}"
}






resource "google_kms_crypto_key_iam_binding" "bucket_key" {
  provider      = google-beta
  crypto_key_id = google_kms_crypto_key.bucket_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  # Replace the service account email below with the correct one
  members = [
    "serviceAccount:service-892626759105@gs-project-accounts.iam.gserviceaccount.com",
  ]

  depends_on = [
    google_kms_crypto_key.bucket_key
  ]
}




data "google_storage_bucket" "bucket" {
  name = "mridula-storagebucket"
  location                    = "US-CENTRAL1"
  uniform_bucket_level_access = true
  encryption {
    default_kms_key_name = google_kms_crypto_key.bucket_key.id
  }

  depends_on = [
    google_kms_crypto_key_iam_binding.bucket_key
  ]
}


data "google_storage_bucket_object" "object" {
  name   = "Serverless_object.zip"
  bucket = google_storage_bucket.bucket.name
  source = "Serverless_object.zip"

  depends_on = [
    google_storage_bucket.bucket
  ]
}


resource "google_cloudfunctions2_function" "cloud_functions2" {
  name        = "my-cloudfunctionv2"
  description = "Sends mail to user"
  project     = var.project_id
  location    = var.region
  depends_on = [
    google_service_account.mywebapp_service_account,
    google_vpc_access_connector.connector,
    google_pubsub_topic.verify_emailtopic,
    google_project_iam_member.cloud_function_developer_role,
    google_project_iam_member.cloud_function_developer
  ]

  build_config {
    runtime     = "python312"
    entry_point = "hello_pubsub" # entry point
    source {
      storage_source {
        bucket = google_storage_bucket.bucket.name
        object = google_storage_bucket_object.object.name
      }
    }
  }

  service_config {
    max_instance_count            = 3
    min_instance_count            = 1
    available_memory              = "256Mi"
    timeout_seconds               = 60
    vpc_connector                 = google_vpc_access_connector.connector.name
    vpc_connector_egress_settings = "PRIVATE_RANGES_ONLY"

    environment_variables = {
      MAILGUN_DOMAIN  = "mridulaprabhakar.me"
      MAILGUN_API_KEY = var.api_key
      DATABASE_URL    = "mysql+pymysql://${google_sql_user.users.name}:${random_password.password.result}@${length(google_sql_database_instance.db_instance.ip_address) > 0 ? google_sql_database_instance.db_instance.ip_address[0].ip_address : null}/${google_sql_database.database.name}"
      # email             = "prabhakar.m@northeastern.edu"
    }
    ingress_settings      = "ALLOW_INTERNAL_ONLY"
    service_account_email = google_service_account.mywebapp_service_account.email
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.verify_emailtopic.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }
}



resource "google_project_iam_binding" "pubsub_publisher_binding" {
  project = var.project_id
  role    = "roles/pubsub.publisher"

  members = [
    "serviceAccount:${google_service_account.mywebapp_service_account.email}",
  ]
}

resource "google_project_iam_binding" "cloud_function_invoker_binding" {
  project = var.project_id
  role    = "roles/cloudfunctions.invoker"

  members = [
    "serviceAccount:${google_service_account.mywebapp_service_account.email}",
  ]
}



resource "google_kms_key_ring" "keyring" {
  name     = "my-keyring-${random_id.db_name_suffix.hex}"
  location = var.region
}

# Key for Virtual Machines
resource "google_kms_crypto_key" "vm_key" {
  name            = "vm-key-${random_id.db_name_suffix.hex}"
  key_ring        = google_kms_key_ring.key_ring.id
  rotation_period = var.rotation_period

  version_template {
    algorithm = "GOOGLE_SYMMETRIC_ENCRYPTION"
  }
}


# Key for CloudSQL Instances
resource "google_kms_crypto_key" "cloudsql_key" {
  name            = "cloudsql_key-${random_id.db_name_suffix.hex}"
  key_ring        = google_kms_key_ring.key_ring.id
  rotation_period = var.rotation_period

  version_template {
    algorithm = "GOOGLE_SYMMETRIC_ENCRYPTION"
  }
}


# Key for Cloud Storage Buckets
resource "google_kms_crypto_key" "bucket_key" {
  name            = "bucket_key-${random_id.db_name_suffix.hex}"
  key_ring        = google_kms_key_ring.key_ring.id
  rotation_period = var.rotation_period

  version_template {
    algorithm = "GOOGLE_SYMMETRIC_ENCRYPTION"
  }
}


resource "google_secret_manager_secret" "default" {
  for_each  = local.secrets
  project   = var.project_id
  secret_id = each.key


  replication {
    auto {}
  }
}


resource "google_secret_manager_secret_version" "default" {
  for_each = local.secrets
  secret   = google_secret_manager_secret.default[each.key].id

  secret_data = each.value
  depends_on = [
    google_secret_manager_secret.default
  ]
}

locals {
  secrets = {
    "instance_template_name" : "webapp-template20240410094113195800000001-20240410-094927"
    "project_id" : "infra-0646"
    "region" : "us-east1"
    "machine_type" : "e2-medium"
    "subnet" : "webapp-subnet"
    "service_account_email" : "webapp-service-account@infra-0646.iam.gserviceaccount.com"
    "group_manager_identifier" : "webapp-manager"
    "startup-script" : "#!/bin/bash\necho -e \"DB_HOST=${length(google_sql_database_instance.db_instance.ip_address) > 0 ? google_sql_database_instance.db_instance.ip_address[0].ip_address : null}\nUSERNAME=${google_sql_user.users.name}\nPASSWORD=${random_password.password.result}\nDBNAME=${google_sql_database.database.name}\" > /tmp/.env \nsudo su\nsudo mv -f /tmp/.env /home/csye6225/webapp-main/.env\nsudo chown -R csye6225:csye6225 /home/csye6225/webapp-main\nsudo systemctl restart webapp"
    "crypto_key" = google_kms_crypto_key.vm_key.id
  }
}