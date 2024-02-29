project_id               = "iacvpc"
region                   = "us-central1"
zone                     = "us-central1-c"
my_personal_vpc_network  = "my-vpc-network"
webapp_subnet            = "my-subnet-webapp"
db_subnet                = "my-subnet-db"
web_app_route            = "my-webapp-route"
webapp_cidr              = "192.168.1.0/24"
db_cidr                  = "192.168.0.0/24"
webapp_route_dest_range  = "0.0.0.0/0"
auto_create_subnets      = false
delete_default_routes    = true
routing_mode             = "REGIONAL"
private_ip_google_access = true
next_hop_gateway         = "default-internet-gateway"
firewall            = "allow-application-traffic"
protocol                 = "tcp"
auto_delete              = true
instancesize            = 100   
instancetype            = "pd-balanced"
instancemode            = "READ_WRITE"
instancemachinetype    = "e2-medium"
instancename            = "my-webappinstance"
instancenetworktier    = "PREMIUM"