terraform {
  required_providers {
    openstack = {
      source = "terraform-provider-openstack/openstack"
    }
    external = {
      source = "hashicorp/external"
      version = "2.3.4"
    }
    coder = {
      source = "coder/coder"
      version = "1.0.4"
    }
  }
}

data "coder_workspace_owner" "me" {}

data "coder_workspace" "kube" {
}

provider "openstack" {
  application_credential_id = data.coder_parameter.application_credential_id.value
  application_credential_name = data.coder_parameter.application_credential_name.value
  application_credential_secret = data.coder_parameter.application_credential_secret.value
  tenant_id = data.coder_parameter.project_id.value
  auth_url    = data.coder_parameter.openstack_identity_provider.value
  region      = data.coder_parameter.openstack_region.value
  allow_reauth = true
}

data "openstack_images_image_v2" "nodes_image" {
  name = "ubuntu-jammy-x86_64"
}


resource "openstack_compute_keypair_v2" "kubernetes" {
  name = "tf kubernetes keypair-3"
}


module "kubernetes_infra" {

  #  source = "./../../kubernetes-infra"
  source = "git::https://gitlab.ics.muni.cz/485555/kubernetes-infra.git?ref=v4.0.5"
  coder_user_data = local.user_data
  coder_agent_token = try(coder_agent.main.token, "")
  # Example of variable override
  infra_name = "infra-name-2"
  ssh_public_key = "dynamic"
  ssh_public_key_value = openstack_compute_keypair_v2.kubernetes.public_key
  control_nodes_count       = data.coder_parameter.control_nodes_count.value
  control_nodes_volume_size = 30
  control_nodes_flavor      = "e1.4core-16ram"
  bastion_flavor = "e1.medium"
  public_external_network = "external-ipv4-general-public"
  worker_nodes = [
    {
      name        = "worker"
      flavor      = "e1.medium"
      volume_size = 30
      count       = data.coder_parameter.worker_nodes_count.value
    }
  ]
  custom_security_group_rules = {
    nodeport = {
      description      = "Allow NodePorts for OOD instance ."
      direction        = "ingress"
      ethertype        = "IPv4"
      protocol         = "tcp"
      port_range_min   = 30000
      port_range_max   = 32767
      remote_ip_prefix = "78.128.247.103/32"
    },
    ood = {
      description      = "Kubeconfig port for OOD instance."
      direction        = "ingress"
      ethertype        = "IPv4"
      protocol         = "tcp"
      port_range_min   = 8080
      port_range_max   = 8080
      remote_ip_prefix = "78.128.247.103/32"
    }
  
  }

}


locals {

  # User data is used to stop/start AWS instances. See:
  # https://github.com/hashicorp/terraform-provider-aws/issues/22

  user_data = <<EOT
Content-Type: multipart/mixed; boundary="//"
MIME-Version: 1.0
--//
Content-Type: text/cloud-config; charset="us-ascii"
MIME-Version: 1.0
Content-Transfer-Encoding: 7bit
Content-Disposition: attachment; filename="cloud-config.txt"
#cloud-config
cloud_final_modules:
- [scripts-user, always]
hostname: ${lower(data.coder_workspace.me.name)}
--//
Content-Type: text/x-shellscript; charset="us-ascii"
MIME-Version: 1.0
Content-Transfer-Encoding: 7bit
Content-Disposition: attachment; filename="userdata.txt"
#!/bin/bash

set -eux pipefail

apt-get update
apt-get install -y jq

sudo CODER_AGENT_TOKEN=$(curl -s http://169.254.169.254/openstack/latest/meta_data.json | jq -r .meta.coder_agent_token) -u ubuntu sh -c '${try(coder_agent.main.init_script, "")}'
--//--
EOT

}

data "coder_provisioner" "me" {}

data "coder_workspace" "me" {}

resource "coder_agent_instance" "dev" {
  agent_id    = coder_agent.main.id
  instance_id = module.kubernetes_infra.bastion_id
}

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = data.coder_provisioner.me.os
  order = 1
  metadata {
  display_name = "admin_conf"
  key          = "admin_conf"
  script       = "[ -e ~/kubernetes-infra-example/ansible/artifacts/admin.conf ] && cat ~/kubernetes-infra-example/ansible/artifacts/admin.conf || echo 'wait for the kubeconfig' "
  interval     = 60 
  order        = 1
  }
}

data "local_file" "k8s_inventory" {
  depends_on = [module.kubernetes_infra]
  filename = "../ansible/ansible_inventory"
}

data "local_file" "openstack_vars" {
  depends_on = [module.kubernetes_infra]
  filename = "../ansible/group_vars/all/openstack_vars.yaml"
}


resource "coder_script" "startup_script" {
  agent_id           = coder_agent.main.id
  display_name       = "Startup Script"
  script             = <<-EOF
    #!/bin/sh
        #!/bin/sh
    whoami

    echo ${data.local_file.k8s_inventory.content}
    echo 'inventory -----------------------------------------'
    echo ${data.local_file.openstack_vars.content}
    echo 'variables -----------------------------------------'

    git clone https://gitlab.ics.muni.cz/485555/kubernetes-infra-example.git
    cd ./kubernetes-infra-example
    cd ./ansible/01-playbook
    sudo apt update > /dev/null 
    sudo apt install -y nginx build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev libsqlite3-dev wget libbz2-dev > /dev/null 
    wget https://www.python.org/ftp/python/3.10.0/Python-3.10.0.tgz  > /dev/null 
    tar -xvf Python-3.10.0.tgz > /dev/null 
    cd Python-3.10.0
    sudo ./configure --enable-optimizations > /dev/null 

    sudo make -j 2 > /dev/null 
    sudo make altinstall > /dev/null 
    cd ..
    sudo apt install -y pipx python3.8-venv > /dev/null 
    pipx ensurepath > /dev/null 
    pipx install --include-deps ansible > /dev/null 

    echo 'external_openstack_application_credential_name: ${data.coder_parameter.application_credential_name.value}' >> ../group_vars/all/openstack.yml
    echo 'external_openstack_application_credential_id: ${data.coder_parameter.application_credential_id.value}' >> ../group_vars/all/openstack.yml
    echo  'external_openstack_application_credential_secret : ${data.coder_parameter.application_credential_secret.value}' >> ../group_vars/all/openstack.yml

    echo 'external_openstack_auth_url : ${data.coder_parameter.openstack_identity_provider.value}' >> ../group_vars/all/openstack.yml
    echo 'external_openstack_region : ${data.coder_parameter.openstack_region.value}' >> ../group_vars/all/openstack.yml

    echo 'cinder_application_credential_name: ${data.coder_parameter.application_credential_name.value}' >> ../group_vars/all/openstack.yml
    echo 'cinder_application_credential_id: ${data.coder_parameter.application_credential_id.value}' >> ../group_vars/all/openstack.yml
    echo  'cinder_application_credential_secret : ${data.coder_parameter.application_credential_secret.value}' >> ../group_vars/all/openstack.yml

    echo 'cinder_auth_url : ${data.coder_parameter.openstack_identity_provider.value}' >> ../group_vars/all/openstack.yml
    echo 'cinder_region : ${data.coder_parameter.openstack_region.value}' >> ../group_vars/all/openstack.yml

    echo '${data.local_file.k8s_inventory.content}' > ../ansible_inventory
    echo '${data.local_file.openstack_vars.content}' > ../group_vars/all/openstack_vars.yaml

    echo '${openstack_compute_keypair_v2.kubernetes.private_key}' > ~/.ssh/id_rsa
    chmod 600 ~/.ssh/id_rsa

    python3.10 -m pip install -r requirements.txt > /dev/null 
    /home/ubuntu/.local/bin/ansible-galaxy install -r requirements.yml
    /home/ubuntu/.local/bin/ansible-playbook -i ../ansible_inventory --user=ubuntu --become --become-user=root play.yml

    
    sudo mkdir -p /var/www/html/kubernetes-infra-example/ansible/artifacts
    sudo cp ~/kubernetes-infra-example/ansible/artifacts/admin.conf /var/www/html/kubernetes-infra-example/ansible/artifacts/
    sudo chown -R www-data:www-data /var/www/html/kubernetes-infra-example
    sudo chmod -R 755 /var/www/html/kubernetes-infra-example

    sudo bash -c "cat > $NGINX_CONF" <<EOL
    server {
      listen 8080 default_server;
      listen [::]:8080 default_server;

      root /var/www/html;
      index index.html index.htm;

      server_name _;

      location / {
          try_files \$uri \$uri/ =404;
      }

      location /kubeconfig {
          alias /var/www/html/kubernetes-infra-example/ansible/artifacts/admin.conf;
      }
    }
    EOL
    sudo systemctl restart nginx
  EOF
  run_on_start       = true
  start_blocks_login = true
}



resource "null_resource" "coder_output" {
  depends_on = [
    module.kubernetes_infra
  ]
}

resource "coder_metadata" "admin-conf" {
  resource_id = null_resource.coder_output.id
  item {
    key   = "floating_ip"
    value = module.kubernetes_infra.bastion_external_ip
  }
}