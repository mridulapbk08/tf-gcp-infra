terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.51.0"
    }
  }
}

provider "google" {
  credentials = file("iacvpc-df8e76bed914.json")

  project = var.project_id
  region  = var.region
  zone    = var.zone
}

resource "google_service_account" "mywebapp_service_account" {
  account_id   = var.account_id
  display_name = " MyWebapp Service Account"
  project = var.project_id
}

#creating a vpc
resource "google_compute_network" "vpc_network" {
  name                    = var.my_personal_vpc_network
  auto_create_subnetworks = var.auto_create_subnets
  routing_mode = var.routing_mode
  delete_default_routes_on_create = var.delete_default_routes  

}

#creating a subnet "webapp"
resource "google_compute_subnetwork" "webapp" {
  name          =  var.webapp_subnet
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
    ports    = ["5000","22"] 
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
 
 
resource "google_compute_instance" "webapp_instance" {
  boot_disk {
    auto_delete = var.auto_delete
 
    initialize_params {
      image = "projects/iacvpc/global/images/my-custom-image-20240319065110"
      size  = var.instancesize
      type  = var.instancetype
    }
 
    mode = var.instancemode
  }
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

   service_account {
    email  = google_service_account.mywebapp_service_account.email
    scopes = ["cloud-platform"]  
  }
 
  machine_type = var.instancemachinetype
  name         = var.instancename
  tags   = ["http-server", "https-server"]
  depends_on = [
    google_compute_network.vpc_network, google_compute_subnetwork.webapp, google_sql_database_instance.db_instance
  ]
  network_interface {
    access_config {
      network_tier = var.instancenetworktier
    }
 
    subnetwork = google_compute_subnetwork.webapp.self_link
  }
}
resource "google_compute_global_address" "private_ip" {
    project = var.project_id
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
 
 
resource "google_project_service" "service_networking" {
  service = "servicenetworking.googleapis.com"
  disable_on_destroy = true
}
 
 

 
resource "google_sql_database_instance" "db_instance" {
  project = var.project_id
  name                 = "webappsdb-6"
  region               = var.region
  database_version     = "MYSQL_8_0" 
  deletion_protection  = false
 
  depends_on = [google_service_networking_connection.private_vpc_connection] 
  settings {
    tier = "db-f1-micro"
    availability_type   = "REGIONAL"
    disk_type           = "pd_ssd"
    disk_size           = 100
 
    backup_configuration {
      enabled            = true
      binary_log_enabled = true
    }
 
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc_network.id
    }
 
  }
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
  length           = 16
  special          = false
}
 
 
provider "google-beta" {
  region = var.region
  zone   = var.zone
}

resource "google_dns_record_set" "a_record" {
  name         = var.domainname
  type         = "A"
  ttl          = 300
  managed_zone = var.dnszone   
  rrdatas      = [google_compute_instance.webapp_instance.network_interface.0.access_config.0.nat_ip]
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




 



