##############################################################################
# Account Variables
# Copyright 2020 IBM
##############################################################################

# Uncomment this variable if running locally
# variable ibmcloud_api_key {
#   description = "The IBM Cloud platform API key needed to deploy IAM enabled resources"
#   type        = string
#   sensitive   = true
# }

# Comment out if not running in schematics
variable TF_VERSION {
 default     = "1.0"
 description = "The version of the Terraform engine that's used in the Schematics workspace."
}

variable prefix {
    description = "A unique identifier need to provision resources. Must begin with a letter"
    type        = string
    default     = "mvp"

    validation  {
      error_message = "Unique ID must begin and end with a letter and contain only letters, numbers, and - characters."
      condition     = can(regex("^([a-z]|[a-z][-a-z0-9]*[a-z0-9])$", var.prefix))
    }
}

variable region {
  description = "Region where VPC will be created"
  type        = string
  default     = "eu-gb"
}

variable resource_group {
    description = "Name of resource group where all infrastructure will be provisioned"
    type        = string
    default     = "multizone-power-vpc"

    validation  {
      error_message = "Unique ID must begin and end with a letter and contain only letters, numbers, and - characters."
      condition     = can(regex("^([a-z]|[a-z][-a-z0-9]*[a-z0-9])$", var.resource_group))
    }
}

##############################################################################


##############################################################################
# VPC Variables
##############################################################################

variable classic_access {
  description = "Enable VPC Classic Access. Note: only one VPC per region can have classic access"
  type        = bool
  default     = false
}

variable subnets {
  description = "List of subnets for the vpc. For each item in each array, a subnet will be created."
  type        = object({
    zone-1 = list(object({
      name           = string
      cidr           = string
      public_gateway = optional(bool)
    }))
    zone-2 = list(object({
      name           = string
      cidr           = string
      public_gateway = optional(bool)
    }))
    zone-3 = list(object({
      name           = string
      cidr           = string
      public_gateway = optional(bool)
    }))
  })
  default = {
    zone-1 = [
      {
        name           = "zone1-mnmgt"
        cidr           = "10.10.10.0/24"
        public_gateway = false
      },
      {
        name           = "zone1-pri"
        cidr           = "10.10.20.0/24"
        public_gateway = false
      },
      {
        name           = "zone1-pub"
        cidr           = "10.10.30.0/24"
        public_gateway = false
      }
    ],
    zone-2 = [
      {
        name           = "zone2-redund"
        cidr           = "10.20.10.0/24"
        public_gateway = false
      }
    ],
    zone-3 = [
      {
        name           = "zone3-mgmgt"
        cidr           = "10.30.10.0/24"
        public_gateway = false
      },
      {
        name           = "zone3-pri"
        cidr           = "10.30.20.0/24"
        public_gateway = false
      },
      {
        name           = "zone3-pub"
        cidr           = "10.30.30.0/24"
        public_gateway = false
      }
    ]
  }

  validation {
      error_message = "Keys for `subnets` must be in the order `zone-1`, `zone-2`, `zone-3`."
      condition     = keys(var.subnets)[0] == "zone-1" && keys(var.subnets)[1] == "zone-2" && keys(var.subnets)[2] == "zone-3"
  }
}

variable use_public_gateways {
  description = "Create a public gateway in any of the three zones with `true`."
  type        = object({
    zone-1 = optional(bool)
    zone-2 = optional(bool)
    zone-3 = optional(bool)
  })
  default     = {
    zone-1 = false
    zone-2 = false
    zone-3 = false
  }

  validation {
      error_message = "Keys for `use_public_gateways` must be in the order `zone-1`, `zone-2`, `zone-3`."
      condition     = keys(var.use_public_gateways)[0] == "zone-1" && keys(var.use_public_gateways)[1] == "zone-2" && keys(var.use_public_gateways)[2] == "zone-3"
  }
}

variable acl_rules {
  description = "Access control list rule set"
  type        = list(
    object({
      name        = string
      action      = string
      destination = string
      direction   = string
      source      = string
      tcp         = optional(
        object({
          port_max        = optional(number)
          port_min        = optional(number)
          source_port_max = optional(number)
          source_port_min = optional(number)
        })
      )
      udp         = optional(
        object({
          port_max        = optional(number)
          port_min        = optional(number)
          source_port_max = optional(number)
          source_port_min = optional(number)
        })
      )
      icmp        = optional(
        object({
          type = optional(number)
          code = optional(number)
        })
      )
    })
  )
  
  default     = [
    {
      name        = "allow-all-inbound"
      action      = "allow"
      direction   = "inbound"
      destination = "0.0.0.0/0"
      source      = "0.0.0.0/0"
    },
    {
      name        = "allow-all-outbound"
      action      = "allow"
      direction   = "outbound"
      destination = "0.0.0.0/0"
      source      = "0.0.0.0/0"
    }
  ]

  validation {
    error_message = "ACL rules can only have one of `icmp`, `udp`, or `tcp`."
    condition     = length(distinct(
      # Get flat list of results
      flatten([
        # Check through rules
        for rule in var.acl_rules:
        # Return true if there is more than one of `icmp`, `udp`, or `tcp`
        true if length(
          [
            for type in ["tcp", "udp", "icmp"]:
            true if rule[type] != null
          ]
        ) > 1
      ])
    )) == 0 # Checks for length. If all fields all correct, array will be empty
  }

  validation {
    error_message = "ACL rule actions can only be `allow` or `deny`."
    condition     = length(distinct(
      flatten([
        # Check through rules
        for rule in var.acl_rules:
        # Return false action is not valid
        false if !contains(["allow", "deny"], rule.action)
      ])
    )) == 0
  }

  validation {
    error_message = "ACL rule direction can only be `inbound` or `outbound`."
    condition     = length(distinct(
      flatten([
        # Check through rules
        for rule in var.acl_rules:
        # Return false if direction is not valid
        false if !contains(["inbound", "outbound"], rule.direction)
      ])
    )) == 0
  }

  validation {
    error_message = "ACL rule names must match the regex pattern ^([a-z]|[a-z][-a-z0-9]*[a-z0-9])$."
    condition     = length(distinct(
      flatten([
        # Check through rules
        for rule in var.acl_rules:
        # Return false if direction is not valid
        false if !can(regex("^([a-z]|[a-z][-a-z0-9]*[a-z0-9])$", rule.name))
      ])
    )) == 0
  }

}

variable security_group_rules {
  description = "A list of security group rules to be added to the default vpc security group"
  type        = list(
    object({
      name        = string
      direction   = string
      remote      = string
      tcp         = optional(
        object({
          port_max = optional(number)
          port_min = optional(number)
        })
      )
      udp         = optional(
        object({
          port_max = optional(number)
          port_min = optional(number)
        })
      )
      icmp        = optional(
        object({
          type = optional(number)
          code = optional(number)
        })
      )
    })
  )

  default = [
    {
      name      = "allow-inbound-ping"
      direction = "inbound"
      remote    = "0.0.0.0/0"
      icmp      = {
        type = 8
      }
    },
    {
      name      = "allow-inbound-ssh"
      direction = "inbound"
      remote    = "0.0.0.0/0"
      tcp       = {
        port_min = 22
        port_max = 22
      }
    },
  ]

  validation {
    error_message = "Security group rules can only have one of `icmp`, `udp`, or `tcp`."
    condition     = length(distinct(
      # Get flat list of results
      flatten([
        # Check through rules
        for rule in var.security_group_rules:
        # Return true if there is more than one of `icmp`, `udp`, or `tcp`
        true if length(
          [
            for type in ["tcp", "udp", "icmp"]:
            true if rule[type] != null
          ]
        ) > 1
      ])
    )) == 0 # Checks for length. If all fields all correct, array will be empty
  }  

  validation {
    error_message = "Security group rule direction can only be `inbound` or `outbound`."
    condition     = length(distinct(
      flatten([
        # Check through rules
        for rule in var.security_group_rules:
        # Return false if direction is not valid
        false if !contains(["inbound", "outbound"], rule.direction)
      ])
    )) == 0
  }

  validation {
    error_message = "Security group rule names must match the regex pattern ^([a-z]|[a-z][-a-z0-9]*[a-z0-9])$."
    condition     = length(distinct(
      flatten([
        # Check through rules
        for rule in var.security_group_rules:
        # Return false if direction is not valid
        false if !can(regex("^([a-z]|[a-z][-a-z0-9]*[a-z0-9])$", rule.name))
      ])
    )) == 0
  }
}


##############################################################################


##############################################################################
# VSI Variables
##############################################################################

variable vsi_name {
    description = "Name of VSI instance to be provisioned"
    type        = string
    default     = "vsrx"

    validation  {
      error_message = "Unique ID must begin and end with a letter and contain only letters, numbers, and - characters."
      condition     = can(regex("^([a-z]|[a-z][-a-z0-9]*[a-z0-9])$", var.vsi_name))
    }
}

variable image {
    description = "Name of VSI image to be used"
    type        = string
    default     = "r006-fe4460a2-aa88-421a-963a-a84ffa2c5592"
}

variable profile {
    description = "Name of VSI profile to be used"
    type        = string
    default     = "bx2-2x8"
}

variable zone1 {
    description = "Name of first zone to be used"
    type        = string
    default     = "eu-gb-1"
}

##############################################################################