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

  project = "iacvpc"
  region  = "us-central1"
  zone    = "us-central1-c"
}
#creating a vpc
resource "google_compute_network" "vpc_network" {
  name                    = "my-vpc-network"
  auto_create_subnetworks = false
  routing_mode = "REGIONAL"
  delete_default_routes_on_create = true  

}

#creating a subnet "webapp"
resource "google_compute_subnetwork" "webapp" {
  name          = "my-subnet-webapp"
  ip_cidr_range = "10.0.1.0/24"
  network       = google_compute_network.vpc_network.self_link
  region        = "us-central1"

}

#creating a subnet "db"
resource "google_compute_subnetwork" "db" {
  name          = "my-subnet-db"
  ip_cidr_range = "10.0.0.0/24"
  network       = google_compute_network.vpc_network.self_link
  region        = "us-central1"

}

#adding route to "webapp"
resource "google_compute_route" "route" {
  name             = "my-webapp-route"
  dest_range       = "0.0.0.0/0"
  network          = google_compute_network.vpc_network.self_link
  depends_on       = [google_compute_subnetwork.webapp]
  next_hop_gateway = "default-internet-gateway"
  priority         = 100
}

# run using  terraform plan -var-file="tera.tfvars" 
#terraform apply -var-file="tera.tfvars" 