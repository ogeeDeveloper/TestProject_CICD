# Appendix

## Terraform Configuration

```hcl
terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

provider "digitalocean" {
  token = var.do_token
}

data "digitalocean_droplet" "existing" {
  name = "app-server"
}

resource "digitalocean_droplet" "app_server" {
  count = data.digitalocean_droplet.existing.id == "" ? 1 : 0
  image    = "ubuntu-20-04-x64"
  name     = "app-server"
  region   = "nyc3"
  size     = "s-1vcpu-1gb"
  ssh_keys = [var.ssh_key_id]

  provisioner "remote-exec" {
    inline = [
      "apt-get update && apt-get upgrade -y",
      "apt-get install -y sshpass",
      "useradd -m -s /bin/bash deployer",
      "echo 'deployer ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers",
      "mkdir -p /home/deployer/.ssh",
      "echo '${var.ssh_public_key}' > /home/deployer/.ssh/authorized_keys",
      "chown -R deployer:deployer /home/deployer/.ssh",
      "chmod 700 /home/deployer/.ssh",
      "chmod 600 /home/deployer/.ssh/authorized_keys"
    ]

    connection {
      type        = "ssh"
      user        = "root"
      private_key = file(var.ssh_private_key)
      host        = self.ipv4_address
    }
  }

  provisioner "local-exec" {
    command = <<EOF
      ssh-keyscan -H ${self.ipv4_address} >> ~/.ssh/known_hosts
    EOF
  }
}

output "app_server_ip" {
  value = coalesce(
    data.digitalocean_droplet.existing.ipv4_address,
    try(digitalocean_droplet.app_server[0].ipv4_address, null)
  )
}

```

## Ansible Playbook

```hcl
- hosts: localhost
  become: yes
  vars:
    ansible_user: "deployer"
    ssh_key_path: "/root/.ssh/id_rsa"
  tasks:
    - name: Update apt cache
      apt:
        update_cache: yes

    - name: Install Docker
      apt:
        name: docker.io
        state: present

    - name: Install Docker Compose
      shell: curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

    - name: Set permissions for Docker Compose
      file:
        path: /usr/local/bin/docker-compose
        mode: "0755"

    - name: Start Docker service
      service:
        name: docker
        state: started
        enabled: yes

    - name: Create directories for tools
      file:
        path: "{{ item }}"
        state: directory
        mode: "0755"
      with_items:
        - /opt/jenkins
        - /opt/sonarqube/data
        - /opt/grafana/data
        - /opt/grafana/provisioning/datasources
        - /opt/prometheus/data

    - name: Ensure the Docker network exists
      shell: |
        if ! docker network ls | grep -q cicd_network; then
          docker network create cicd_network
        fi

    - name: Create Prometheus configuration file
      copy:
        dest: /opt/prometheus/prometheus.yml
        content: |
          global:
            scrape_interval: 15s

          scrape_configs:
            - job_name: 'jenkins'
              static_configs:
                - targets: ['jenkins:8080']

    - name: Create Grafana provisioning file for Prometheus
      copy:
        dest: /opt/grafana/provisioning/datasources/prometheus.yml
        content: |
          apiVersion: 1
          datasources:
            - name: Prometheus
              type: prometheus
              access: proxy
              url: http://prometheus:9090
              isDefault: true

    - name: Run Jenkins container with required settings
      shell: |
        docker stop jenkins || true
        docker rm jenkins || true
        docker run -d -u root --privileged=true \
          --network cicd_network \
          --volume /opt/jenkins/jenkins_home:/var/jenkins_home \
          -v /var/run/docker.sock:/var/run/docker.sock \
          -v "{{ ssh_key_path }}:/root/.ssh/id_rsa" \
          -p 8080:8080 -p 50000:50000 --name jenkins jenkins/jenkins:lts

    - name: Install Terraform in Jenkins container
      shell: |
        docker exec -u root jenkins bash -c "apt-get update && apt-get install -y wget unzip && \
        wget https://releases.hashicorp.com/terraform/1.1.5/terraform_1.1.5_linux_amd64.zip && \
        unzip terraform_1.1.5_linux_amd64.zip && mv terraform /usr/local/bin/ && \
        rm terraform_1.1.5_linux_amd64.zip"

    - name: Create Docker Compose file for SonarQube
      copy:
        dest: /opt/sonarqube/docker-compose.yml
        content: |
          version: '3'
          services:
            sonarqube:
              image: sonarqube
              container_name: sonarqube
              ports:
                - "0.0.0.0:9000:9000"
              networks:
                - cicd_network
              volumes:
                - /opt/sonarqube/data/sonarqube-data:/opt/sonarqube/data
          networks:
            cicd_network:
              external: true

    - name: Create Docker Compose file for Grafana
      copy:
        dest: /opt/grafana/docker-compose.yml
        content: |
          version: '3'
          services:
            grafana:
              image: grafana/grafana
              container_name: grafana
              ports:
                - "0.0.0.0:3000:3000"
              networks:
                - cicd_network
              volumes:
                - /opt/grafana/data:/var/lib/grafana
                - /opt/grafana/provisioning:/etc/grafana/provisioning
          networks:
            cicd_network:
              external: true

    - name: Create Docker Compose file for Prometheus
      copy:
        dest: /opt/prometheus/docker-compose.yml
        content: |
          version: '3'
          services:
            prometheus:
              image: prom/prometheus
              container_name: prometheus
              ports:
                - "0.0.0.0:9090:9090"
              networks:
                - cicd_network
              volumes:
                - /opt/prometheus/data:/prometheus
                - /opt/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
          networks:
            cicd_network:
              external: true

    - name: Start SonarQube
      command: docker-compose up -d
      args:
        chdir: /opt/sonarqube

    - name: Start Grafana
      command: docker-compose up -d
      args:
        chdir: /opt/grafana

    - name: Start Prometheus
      command: docker-compose up -d
      args:
        chdir: /opt/prometheus

    - name: Restart Jenkins
      shell: docker restart jenkins

```

### Explanation

- Update apt cache: Updates the apt package cache.
- Install Docker: Installs Docker.
- Install Docker Compose: Installs Docker Compose.
- Set permissions for Docker Compose: Sets the permissions for Docker Compose.
- Start Docker service: Starts and enables the Docker service.
- Create directories for tools: Creates the necessary directories for Jenkins, SonarQube, Grafana, and Prometheus.
- Create a common Docker network: Creates a common Docker network for the containers.
- Create Prometheus configuration file: Creates the configuration file for Prometheus.
- Create Grafana provisioning file for Prometheus: Creates the provisioning file for Grafana to use Prometheus.
- Ensure the Docker network exists: This block checks if the Docker network cicd_network exists before attempting to create it, avoiding errors due to the network already existing.
- Run Jenkins container with required settings: Runs the Jenkins container with the specified settings.
- Install Terraform in Jenkins container: Installs Terraform within the Jenkins container to ensure it persists across restarts.
- Create Docker Compose file for SonarQube: Creates the Docker Compose file for SonarQube.
- Create Docker Compose file for Grafana: Creates the Docker Compose file for Grafana.
- Create Docker Compose file for Prometheus: Creates the Docker Compose file for Prometheus.
- Start SonarQube: Starts the SonarQube container.
- Start Grafana: Starts the Grafana container.
- Start Prometheus: Starts the Prometheus container.
- Restart Jenkins: Restarts the Jenkins container to apply any changes.

## Jenkins Pipeline Script

pipeline {
agent any
environment {
MAVEN_PROJECT_DIR = 'java-tomcat-sample'
TERRAFORM_DIR = 'terraform'
ANSIBLE_PLAYBOOK = 'deploy.yml'
SONAR_TOKEN = credentials('SonarQubeServerToken')
TERRAFORM_BIN = '/usr/local/bin/terraform'
ANSIBLE_NAME = 'Ansible'
ANSIBLE_HOST_KEY_CHECKING = 'False'
}
stages {
stage('Verify Environment') {
steps {
sh 'echo $PATH'
                sh 'terraform --version'
            }
        }
        stage('Cleanup') {
            steps {
                deleteDir()
            }
        }
        stage('Checkout SCM') {
            steps {
                git branch: 'dev', url: 'https://github.com/ogeeDeveloper/TestProject_CICD.git'
            }
        }
        stage('Build') {
            steps {
                dir("${MAVEN_PROJECT_DIR}") {
script {
def mvnHome = tool name: 'Maven 3.9.7', type: 'maven'
sh "${mvnHome}/bin/mvn clean package"
                    }
                }
            }
        }
        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('SonarQube') {
                    dir("${MAVEN_PROJECT_DIR}") {
script {
def scannerHome = tool name: 'SonarQubeScanner', type: 'hudson.plugins.sonar.SonarRunnerInstallation'
sh """
${scannerHome}/bin/sonar-scanner \
                                -Dsonar.projectKey=TestProjectCiCd \
                                -Dsonar.projectName=TestProject_CICD \
                                -Dsonar.projectVersion=1.0 \
                                -Dsonar.sources=src \
                                -Dsonar.java.binaries=target/classes \
                                -Dsonar.host.url=http://164.90.138.210:9000 \
                                -Dsonar.login=${SONAR_TOKEN}
"""
}
}
}
}
}
stage('Infrastructure Provisioning') {
steps {
dir("${TERRAFORM_DIR}") {
                    withCredentials([
                        string(credentialsId: 'do_token', variable: 'DO_TOKEN'),
                        string(credentialsId: 'ssh_key_id', variable: 'SSH_KEY_ID'),
                        sshUserPrivateKey(credentialsId: 'ssh_private_key', keyFileVariable: 'SSH_PRIVATE_KEY_PATH', usernameVariable: 'SSH_USER'),
                        string(credentialsId: 'ssh_public_key', variable: 'SSH_PUBLIC_KEY')
                    ]) {
                        script {
                            // Initialize Terraform
                            sh "${TERRAFORM_BIN} init"

                            // Plan Terraform changes
                            sh "${TERRAFORM_BIN} plan -var 'do_token=${DO_TOKEN}' -var 'ssh_key_id=${SSH_KEY_ID}' -var 'ssh_private_key=${SSH_PRIVATE_KEY_PATH}' -var 'ssh_public_key=${SSH_PUBLIC_KEY}'"

                            // Apply Terraform changes
                            sh "${TERRAFORM_BIN} apply -auto-approve -var 'do_token=${DO_TOKEN}' -var 'ssh_key_id=${SSH_KEY_ID}' -var 'ssh_private_key=${SSH_PRIVATE_KEY_PATH}' -var 'ssh_public_key=${SSH_PUBLIC_KEY}'"

                            // Capture Terraform output
                            def output = sh(script: "${TERRAFORM_BIN} output -json", returnStdout: true).trim()
                            def jsonOutput = readJSON text: output
                            env.SERVER_IP = jsonOutput.app_server_ip.value
                        }
                    }
                }
            }
        }
        stage('Deploy Application') {
            steps {
                withCredentials([
                    string(credentialsId: 'ansible_password', variable: 'ANSIBLE_PASSWORD'),
                    sshUserPrivateKey(credentialsId: 'ssh_private_key', keyFileVariable: 'SSH_KEY_FILE', passphraseVariable: '', usernameVariable: 'ANSIBLE_USER')
                ]) {
                    script {
                        def ansibleHome = tool name: "${ANSIBLE_NAME}"
                        sh "export PATH=${ansibleHome}/bin:\$PATH"
                        sh "echo 'Ansible Home: ${ansibleHome}'"
                        sh "echo '[app_servers]\n${SERVER_IP}' > dynamic_inventory.ini"
                        sh "${ansibleHome}/bin/ansible-playbook ${ANSIBLE_PLAYBOOK} -i dynamic_inventory.ini -e ansible_user=${ANSIBLE_USER} -e ansible_password=${ANSIBLE_PASSWORD} -e server_ip=${SERVER_IP} -e workspace=${WORKSPACE}"
                    }
                }
            }
        }
    }
    post {
        always {
            // junit '**/target/surefire-reports/*.xml'
            script {
                if (currentBuild.currentResult == 'SUCCESS') {
                    echo 'Build succeeded!'
                } else {
                    echo 'Build failed. Please check Jenkins for details.'
                }
            }
        }
    }

}