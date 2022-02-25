##############################################################################
# IBM Cloud Provider
##############################################################################

provider ibm {
  # Uncomment if running locally
  # ibmcloud_api_key      = var.ibmcloud_api_key
  region                = var.region
  ibmcloud_timeout      = 60
}

##############################################################################


##############################################################################
# Resource Group where VPC will be created
##############################################################################

data ibm_resource_group resource_group {
  name = var.resource_group
}

##############################################################################


##############################################################################
# Create a VPC
##############################################################################

resource ibm_is_vpc vpc {
  name           = "${var.prefix}-vpc"
  resource_group = data.ibm_resource_group.resource_group.id
  classic_access = var.classic_access
}

##############################################################################


##############################################################################
# Update default security group
##############################################################################

locals {
  # Convert to object
  security_group_rule_object = {
    for rule in var.security_group_rules:
    rule.name => rule
  }
}

resource ibm_is_security_group_rule default_vpc_rule {
  for_each  = local.security_group_rule_object
  group     = ibm_is_vpc.vpc.default_security_group
  direction = each.value.direction
  remote    = each.value.remote

  dynamic tcp { 
    for_each = each.value.tcp == null ? [] : [each.value]
    content {
      port_min = each.value.tcp.port_min
      port_max = each.value.tcp.port_max
    }
  }

  dynamic udp { 
    for_each = each.value.udp == null ? [] : [each.value]
    content {
      port_min = each.value.udp.port_min
      port_max = each.value.udp.port_max
    }
  } 

  dynamic icmp { 
    for_each = each.value.icmp == null ? [] : [each.value]
    content {
      type = each.value.icmp.type
      code = each.value.icmp.code
    }
  } 
}

##############################################################################


##############################################################################
# Public Gateways (Optional)
##############################################################################

locals {
  # create object that only contains gateways that will be created
  gateway_object = {
    for zone in keys(var.use_public_gateways):
      zone => "${var.region}-${index(keys(var.use_public_gateways), zone) + 1}" if var.use_public_gateways[zone]
  }
}

resource ibm_is_public_gateway gateway {
  for_each       = local.gateway_object
  name           = "${var.prefix}-public-gateway-${each.key}"
  vpc            = ibm_is_vpc.vpc.id
  resource_group = data.ibm_resource_group.resource_group.id
  zone           = each.value
}

##############################################################################


##############################################################################
# Multizone subnets
##############################################################################

locals {
  # Object to reference gateways
  public_gateways = {
    for zone in ["zone-1", "zone-2", "zone-3"]:
    # If gateway is created, set to id, otherwise set to empty string
    zone => contains(keys(local.gateway_object), zone) ? ibm_is_public_gateway.gateway[zone].id : ""
  }
}

module subnets {
  source            = "./subnet" 
  region            = var.region 
  prefix            = var.prefix                  
  acl_id            = ibm_is_network_acl.multizone_acl.id
  subnets           = var.subnets
  vpc_id            = ibm_is_vpc.vpc.id
  resource_group_id = data.ibm_resource_group.resource_group.id
  public_gateways   = local.public_gateways
}

##############################################################################


##############################################################################
# VSIs
##############################################################################

resource "ibm_is_ssh_key" "vsrx" {
  name       = "example-ssh"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCKVmnMOlHKcZK8tpt3MP1lqOLAcqcJzhsvJcjscgVERRN7/9484SOBJ3HSKxxNG5JN8owAjy5f9yYwcUg+JaUVuytn5Pv3aeYROHGGg+5G346xaq3DAwX6Y5ykr2fvjObgncQBnuU5KHWCECO/4h8uWuwh/kfniXPVjFToc+gnkqA+3RKpAecZhFXwfalQ9mMuYGFxn+fwn8cYEApsJbsEmb0iJwPiZ5hjFC8wREuiTlhPHDgkBLOiycd20op2nXzDbHfCHInquEe/gYxEitALONxm0swBOwJZwlTDOB7C6y2dzlrtxr1L59m7pCkWI4EtTRLvleehBoj3u7jB4usR"
}

resource "ibm_is_instance" "vsrx" {
  name    = "vsrx-zone1"
  image   = "r018-256b93dd-1733-4365-85cc-6c29ba3852ac"
  profile = "bx2-2x8"
  keys = ibm_is_ssh_key.vsrx.id

  primary_network_interface {
    subnet = "0787-e9346161-53a8-483e-8919-378469b39065"
    allow_ip_spoofing = false
  }

  network_interfaces = [
    {
    name   = "eth0"
    subnet = module.subnets.ids[1]
    allow_ip_spoofing = false
    }
    {
    name   = "eth1"
    subnet = module.subnets.ids[2]
    allow_ip_spoofing = false
    }
    {
    name   = "eth2"
    subnet = module.subnets.ids[3]
    allow_ip_spoofing = false
    }
  ]
  vpc  = "r018-99ab97ed-cec9-41d6-a94d-8fa486ff6eab"
  zone = "eu-gb-1"

}

/*   network_interfaces = [
    {
    name   = "eth0"
    subnet = keys(var.subnets)[0]
    security_groups = "triangle-authentic-paparazzi-facility"
    allow_ip_spoofing = false
    },
    {
    name   = "eth1"
    subnet = keys(var.subnets)[1]
    security_groups = "triangle-authentic-paparazzi-facility"
    allow_ip_spoofing = true
    },
    {
    name   = "eth2"
    subnet = keys(var.subnets)[2]
    security_groups = "triangle-authentic-paparazzi-facility"
    allow_ip_spoofing = true
    } */
