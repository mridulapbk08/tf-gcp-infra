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

  project = var.project_id
  region  = var.region
  zone    = var.zone
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
    ports    = ["5000","22"] // Replace "your-application-port" with the actual port number
  }
 
  source_ranges = ["0.0.0.0/0"] // Allows traffic from any IP
  target_tags   = ["http-server", "https-server"]
 
}
 
resource "google_compute_firewall" "deny_ssh" {
  name    = "deny-ssh"
  network = google_compute_network.vpc_network.name
 
  deny {
    protocol = var.protocol
    ports    = ["22"]
  }
 
  source_ranges = ["0.0.0.0/0"] // Applies the rule to all incoming traffic
  target_tags   = ["http-server", "https-server"]
}
 
 
resource "google_compute_instance" "webapp_instance" {
  boot_disk {
    auto_delete = var.auto_delete
 
    initialize_params {
      image = "projects/iacvpc/global/images/my-custom-image-20240225010320"
      size  = var.instancesize
      type  = var.instancetype
    }
 
    mode = var.instancemode
  }
 
 
  machine_type = var.instancemachinetype
  name         = var.instancename
 
  network_interface {
    access_config {
      network_tier = var.instancenetworktier
    }
 
    subnetwork = google_compute_subnetwork.webapp.self_link
  }
 
 
  zone = var.zone
  tags = ["http-server", "https-server"]
}

