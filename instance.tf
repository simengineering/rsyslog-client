

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

# Defines the number of instances to deploy
variable "num_instances" {
  default = "1"
}

# Defines the number of volumes to create and attach to each instance
# NOTE: Changing this value after applying it could result in re-attaching existing volumes to different instances.
# This is a result of using 'count' variables to specify the volume and instance IDs for the volume attachment resource.
variable "num_iscsi_volumes_per_instance" {
  default = "0"
}

variable "num_paravirtualized_volumes_per_instance" {
  default = "2"
}

variable "instance_shape" {
  default = var.instance_shape
}

variable "instance_ocpus" {
  default = 1
}

variable "instance_shape_config_memory_in_gbs" {
  default = 4
}

variable "instance_image_ocid" {
  type = string


}

variable "flex_instance_image_ocid" {
  type = string
}

variable "db_size" {
  default = "50" # size in GBs
}

variable "tag_namespace_description" {
  default = "Rsyslog Receiver Instance OCI"
}

variable "tag_namespace_name" {
  default = "rsyslog-namespace"
}

resource "oci_core_instance" "rsyslog_instance" {
  count               = var.num_instances
  availability_domain = data.oci_identity_availability_domain.ad.name
  compartment_id      = var.compartment_ocid
  display_name        = "RsyslogInstance${count.index}"
  shape               = var.instance_shape
  
  metadata = {
    ssh_authorized_keys = "${file(var.ssh_public_key_file)}"
    user_date = "#{base64encode(data.template_file.cloud-config.rendered)}"
  
  shape_config {
    ocpus = var.instance_ocpus
    memory_in_gbs = var.instance_shape_config_memory_in_gbs
  }

  create_vnic_details {
    subnet_id                 = oci_core_subnet.terraformSUBNET.id
    display_name              = "Primaryvnic"
    assign_public_ip          = true
    assign_private_dns_record = true
    hostname_label            = "rsyslog${count.index}"
  }

  source_details {
    source_type = "image"
    source_id = var.instance_image_ocid[var.region]
    # Apply this to set the size of the boot volume that is created for this instance.
    # Otherwise, the default boot volume size of the image is used.
    # This should only be specified when source_type is set to "image".
    #boot_volume_size_in_gbs = "60"
  }

  # Apply the following flag only if you wish to preserve the attached boot volume upon destroying this instance
  # Setting this and destroying the instance will result in a boot volume that should be managed outside of this config.
  # When changing this value, make sure to run 'terraform apply' so that it takes effect before the resource is destroyed.
  #preserve_boot_volume = true

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(file("./bootstrap.sh"))
  }
  defined_tags = {
    "${oci_identity_tag_namespace.tag-namespace1.name}.${oci_identity_tag.tag2.name}" = "awesome-app-server"
  }

  freeform_tags = {
    "freeformkey${count.index}" = "freeformvalue${count.index}"
  }

  preemptible_instance_config {
    preemption_action {
      type = "TERMINATE"
      preserve_boot_volume = false
    }
  }

  timeouts {
    create = "60m"
  }
}

# Define the volumes that are attached to the compute instances.

resource "oci_core_volume" "test_block_volume" {
  count               = var.num_instances * var.num_iscsi_volumes_per_instance
  availability_domain = data.oci_identity_availability_domain.ad.name
  compartment_id      = var.compartment_ocid
  display_name        = "TestBlock${count.index}"
  size_in_gbs         = var.db_size
}

resource "oci_core_volume_attachment" "test_block_attach" {
  count           = var.num_instances * var.num_iscsi_volumes_per_instance
  attachment_type = "iscsi"
  instance_id     = oci_core_instance.test_instance[floor(count.index / var.num_iscsi_volumes_per_instance)].id
  volume_id       = oci_core_volume.test_block_volume[count.index].id
  device          = count.index == 0 ? "/dev/oracleoci/oraclevdb" : ""

}

resource "oci_core_volume" "test_block_volume_paravirtualized" {
  count               = var.num_instances * var.num_paravirtualized_volumes_per_instance
  availability_domain = data.oci_identity_availability_domain.ad.name
  compartment_id      = var.compartment_ocid
  display_name        = "TestBlockParavirtualized${count.index}"
  size_in_gbs         = var.db_size
}

resource "oci_core_volume_attachment" "test_block_volume_attach_paravirtualized" {
  count           = var.num_instances * var.num_paravirtualized_volumes_per_instance
  attachment_type = "paravirtualized"
  instance_id     = oci_core_instance.test_instance[floor(count.index / var.num_paravirtualized_volumes_per_instance)].id
  volume_id       = oci_core_volume.test_block_volume_paravirtualized[count.index].id
  # Set this to attach the volume as read-only.
  #is_read_only = true
}


resource "null_resource" "remote-exec" {
  depends_on = [
    oci_core_instance.test_instance,
    oci_core_volume_attachment.test_block_attach,
  ]
  count = var.num_instances * var.num_iscsi_volumes_per_instance

  provisioner "remote-exec" {
    connection {
      agent       = false
      timeout     = "30m"
      host        = oci_core_instance.test_instance[count.index % var.num_instances].public_ip
      user        = "opc"
      private_key = var.ssh_private_key
    }

    inline = [
      "touch /home/oci/matt_is_awesome.txt",
    ]
  }
}

/*
# Gets the boot volume attachments for each instance
data "oci_core_boot_volume_attachments" "test_boot_volume_attachments" {
  depends_on          = [oci_core_instance.test_instance]
  count               = var.num_instances
  availability_domain = oci_core_instance.test_instance[count.index].availability_domain
  compartment_id      = var.compartment_ocid

  instance_id = oci_core_instance.test_instance[count.index].id
}
*/

data "oci_core_instance_devices" "test_instance_devices" {
  count       = var.num_instances
  instance_id = oci_core_instance.test_instance[count.index].id
}


# Output the private and public IPs of the instance

output "instance_private_ips" {
  value = [oci_core_instance.test_instance.*.private_ip]
}

output "instance_public_ips" {
  value = [oci_core_instance.test_instance.*.public_ip]
}

# Output the boot volume IDs of the instance
output "boot_volume_ids" {
  value = [oci_core_instance.test_instance.*.boot_volume_id]
}

# Output all the devices for all instances
output "instance_devices" {
  value = [data.oci_core_instance_devices.test_instance_devices.*.devices]
}


/*
output "attachment_instance_id" {
  value = data.oci_core_boot_volume_attachments.test_boot_volume_attachments.*.instance_id
}
*/

resource "oci_core_vcn" "terraformVCN" {
  cidr_block     = "10.0.0.0/16"
  compartment_id = var.compartment_ocid
  display_name   = "terraformVCN"
  dns_label      = "terraformVCN"
}

resource "oci_core_internet_gateway" "test_internet_gateway" {
  compartment_id = var.compartment_ocid
  display_name   = "TestInternetGateway"
  vcn_id         = oci_core_vcn.terraformVCN.id
}

resource "oci_core_default_route_table" "default_route_table" {
  manage_default_resource_id = oci_core_vcn.terraformVCN.default_route_table_id
  display_name               = "DefaultRouteTable"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.test_internet_gateway.id
  }
}

resource "oci_core_subnet" "terraformSUBNET" {
  availability_domain = data.oci_identity_availability_domain.ad.name
  cidr_block          = "10.0.0.0/24"
  display_name        = "terraformSUBNET"
  dns_label           = "terraformSUBNET"
  security_list_ids   = [oci_core_vcn.terraformVCN.default_security_list_id]
  compartment_id      = var.compartment_ocid
  vcn_id              = oci_core_vcn.terraformVCN.id
  route_table_id      = oci_core_vcn.terraformVCN.default_route_table_id
  dhcp_options_id     = oci_core_vcn.terraformVCN.default_dhcp_options_id
}

data "oci_identity_availability_domain" "ad" {
  compartment_id = var.tenancy_ocid
  ad_number      = 1
}

