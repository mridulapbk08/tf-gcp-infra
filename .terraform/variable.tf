variable "project_id" {
  description = "The unique identifier for the Google Cloud Platform (GCP) project."
  type        = string
}

variable "region" {
  description = "The geographic region where resources will be provisioned within GCP."
  type        = string
}

variable "zone" {
  description = "The specific zone within the chosen region where resources will be deployed."
  type        = string
}

variable "my_personal_vpc_network" {
  description = "The name of the Virtual Private Cloud (VPC) network."
  type        = string
}

variable "webapp_subnet" {
  description = "The name of the subnet for the web application servers."
  type        = string
}

variable "db_subnet" {
  description = "The name of the subnet for the database servers."
  type        = string
}

variable "web_app_route" {
  description = "The name of the route for directing traffic to the web application subnet."
  type        = string
}

variable "webapp_cidr" {
  description = "The Classless Inter-Domain Routing (CIDR) block for the web application subnet."
  type        = string
}

variable "db_cidr" {
  description = "The CIDR block for the database subnet."
  type        = string
}

variable "webapp_route_dest_range" {
  description = "The CIDR block for the route directing traffic to the web application subnet."
  type        = string
}

variable "auto_create_subnets" {
  description = "Set to true to automatically create subnets, false otherwise."
  type        = bool
}

variable "delete_default_routes" {
  description = "Set to true to delete default routes, false otherwise."
  type        = bool
}

variable "routing_mode" {
  description = "The routing mode for the VPC, e.g., 'GLOBAL' or 'REGIONAL'."
  type        = string
}

variable "private_ip_google_access" {
  description = "Enable or disable access to Google services using private IP addresses."
  type        = bool
}

variable "next_hop_gateway" {
  description = "The next hop gateway used for routing traffic."
  type        = string
}

variable "firewall" {
  description = "The next hop gateway used for routing traffic."
  type        = string
}
 
 
variable "protocol" {
  description = "The next hop gateway used for routing traffic."
  type        = string
}
 
 
 
variable "instancesize" {
  description = "The next hop gateway used for routing traffic."
  type        = number
}
 
 
variable "instancetype" {
  description = "The next hop gateway used for routing traffic."
  type        = string
}
 
 
variable "instancemode" {
  description = "The next hop gateway used for routing traffic."
  type        = string
}
 
 
variable "instancemachinetype" {
  description = "The next hop gateway used for routing traffic."
  type        = string
}
 
 
variable "instancename" {
  description = "The next hop gateway used for routing traffic."
  type        = string
}
 
 
variable "instancenetworktier" {
  description = "The next hop gateway used for routing traffic."
  type        = string
}
 
 
 
variable "auto_delete" {
  description = "The next hop gateway used for routing traffic."
  type        = bool
}