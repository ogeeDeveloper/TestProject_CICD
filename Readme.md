# Installation and Setup Guide

## Overview

This guide provides detailed steps to:

1. Provision and configure the primary host for Jenkins, SonarQube, Grafana, and Prometheus.
2. Set up Jenkins with the necessary plugins.
3. Create and configure a Jenkins pipeline for building, testing, provisioning infrastructure, and deploying a Java application.

## Prerequisites

- A DigitalOcean account with API access.
- SSH key added to your DigitalOcean account.
- Ansible installed on your local machine.

# Step 1: Provision and Configure the Primary Host

## Terraform Configuration for Primary Host

Create a directory for your Terraform configuration files and add the following files:

`main.tf`

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

data "digitalocean_droplet" "existing_droplet" {
  name   = "app-server"
  count  = 0
}

resource "digitalocean_droplet" "app_server" {
  count     = length(data.digitalocean_droplet.existing_droplet) == 0 ? 1 : 0
  image     = "ubuntu-20-04-x64"
  name      = "app-server"
  region    = "nyc3"
  size      = "s-1vcpu-1gb"
  monitoring = true
  ssh_keys  = [var.ssh_key_id]
}

locals {
  existing_droplet_count = length(data.digitalocean_droplet.existing_droplet)
  existing_droplet_ids   = data.digitalocean_droplet.existing_droplet.*.id
  existing_droplet_ip    = length(data.digitalocean_droplet.existing_droplet) > 0 ? data.digitalocean_droplet.existing_droplet[0].ipv4_address : ""
}

output "app_server_ip" {
  value = local.existing_droplet_count > 0 ? local.existing_droplet_ip : digitalocean_droplet.app_server[0].ipv4_address
}

```

![alt text](image.png)

**_Explanation_**:

- This file contains the main Terraform configuration. It sets up a DigitalOcean droplet if one does not already exist. If a droplet already exists, it retrieves its details instead of creating a new one.
- The locals block determines whether to use an existing droplet's IP address or the newly created one.
- The output block provides the IP address of the app server.

`variables.tf`

```hcl
variable "do_token" {
  description = "DigitalOcean API token"
  type        = string
}

variable "ssh_key_id" {
  description = "DigitalOcean SSH key ID"
  type        = string
}
```

**_Explanation_**:

- This file defines the variables required for the Terraform configuration, including the DigitalOcean API token and SSH key ID.

![alt text](image-1.png)

`terraform.tfvars`

```hcl
do_token = "your_digitalocean_api_token"
ssh_key_id = "your_ssh_key_id"
```

![alt text](image-2.png)
![alt text](image-3.png)

## Step-by-Step Guide to Determine and Set ansible_user

**_Step 1: Create the User (if not already created)_**
Log in to your DigitalOcean droplet and create the user:

```sh
sudo adduser deployer
```

![alt text](image-5.png)

**_Step 2: Add SSH Key for the User_**
Add your public SSH key to the `~/.ssh/authorized_keys` file of the deployer user:

```sh
sudo mkdir /home/deployer/.ssh
sudo nano /home/deployer/.ssh/authorized_keys
# Paste your public SSH key into the file
sudo chown -R deployer:deployer /home/deployer/.ssh
sudo chmod 700 /home/deployer/.ssh
sudo chmod 600 /home/deployer/.ssh/authorized_keys

```

## Ansible Playbook for Setting Up Tools

Create an Ansible playbook file named `setup_tools.yml`:

```yml
- hosts: localhost
  become: yes
  vars:
    ansible_user: "deployer" # Replace with the actual user
  tasks:
    - name: Update apt cache
      apt: update_cache=yes

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
        - /opt/sonarqube
        - /opt/grafana
        - /opt/prometheus

    - name: Create Docker Compose file for Jenkins
      copy:
        dest: /opt/jenkins/docker-compose.yml
        content: |
          version: '3'
          services:
            jenkins:
              image: jenkins/jenkins:lts
              container_name: jenkins
              ports:
                - "8080:8080"
                - "50000:50000"
              volumes:
                - /opt/jenkins/jenkins_home:/var/jenkins_home
                - /var/run/docker.sock:/var/run/docker.sock

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
                - "9000:9000"
              volumes:
                - /opt/sonarqube/data:/opt/sonarqube/data

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
                - "3000:3000"
              volumes:
                - /opt/grafana/data:/var/lib/grafana

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
                - "9090:9090"
              volumes:
                - /opt/prometheus/data:/prometheus

    - name: Start Jenkins
      command: docker-compose up -d
      args:
        chdir: /opt/jenkins

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
```

- Run the ansible: `ansible-playbook -i localhost, -c local -u deployer --become --private-key /root/.ssh/id_rsa /root/cicd/setup_tools.yml`
-
- Install `sshpass` on the Jenkins Container to use the 'ssh' connection type with passwords:

  ```bash
  docker exec -it jenkins bash
  apt-get update
  apt-get install -y sshpass

  ```

![alt text](image-7.png)

![alt text](image-4.png)

- Run the following commands to set the correct permissions on the directories:

  ```bash
    # Ensure the directories exist
    sudo mkdir -p /opt/jenkins/jenkins_home
    sudo mkdir -p /opt/sonarqube/data
    sudo mkdir -p /opt/grafana/data
    sudo mkdir -p /opt/prometheus/data

    # Set the correct permissions
    sudo chown -R 1000:1000 /opt/jenkins/jenkins_home
    sudo chown -R 1000:1000 /opt/sonarqube/data
    sudo chown -R 472:472 /opt/grafana/data
    sudo chown -R 65534:65534 /opt/prometheus/data
  ```

  ![alt text](image-8.png)

- After fixing the permissions, restart the Docker containers:

  ```bash
    docker start jenkins
    docker start sonarqube
    docker start grafana
    docker start prometheus

  ```

  ![alt text](image-9.png)

# Configure Digital SSH

You need to authenticate doctl with your DigitalOcean API token. Here’s how:

1. **_Obtain DigitalOcean API Token:_**

   - Go to your DigitalOcean Control Panel.
   - Generate a new personal access token if you don’t have one already. Copy the token.

2. **_Authenticate `doctl`:_**
   - Run the following command and paste your API token when prompted:
     ```bash
     doctl auth init
     ```
     ![alt text](image-22.png)
3. **_List SSH Keys_**
   - After authenticating, you can list your SSH keys to get the SSH key ID:
     ```bash
     doctl compute ssh-key list
     ```
     ![alt text](image-23.png)

# Configure Jenkins

1. Access Jenkins Dashboard:

   - Navigate to `http://<your-jenkins-server-ip>:8080`.

2. Unlock Jenkins:

   - During the first time accessing Jenkins, you will be asked to unlock it using an initial admin password. This password is stored in the `/var/jenkins_home/secrets/initialAdminPassword` file.
     ![alt text](image-10.png)

   - Retrieve the password by running the following command on your server: `sudo cat /opt/jenkins/jenkins_home/secrets/initialAdminPassword`
     ![alt text](image-11.png)
   - Enter this password in the Jenkins web interface.

3. Install Suggested Plugins:

   - Follow the prompts to install the suggested plugins. Jenkins will install the default set of plugins necessary for most CI/CD tasks.
     ![alt text](image-12.png)
     ![alt text](image-13.png)

4. Create Admin User:

   - After the plugins are installed, you will be prompted to create an admin user. Fill in the required details and save.

5. Configure Jenkins URL:
   - Set the Jenkins URL to http://<your-jenkins-server-ip>:8080 when prompted.
     ![alt text](image-14.png)

# Step 3: Install Additional Plugins

1. Manage Jenkins:

   - Go to `Manage Jenkins` > `Manage Plugins`.

2. Available Tab:

   - Search for and install the following plugins:
     - Git Plugin
     - Maven Integration Plugin
     - Terraform Plugin
     - Ansible Plugin
     - SonarQube Scanner Plugin
     - Checkmarx Plugin

   ![alt text](image-15.png)

   ![alt text](image-16.png)

# Step 4: Configure Global Tools

1. Maven Integration Plugin:

   - Go to Manage Jenkins > Tools.
   - Under Maven, click Add Maven.
   - Provide a name (e.g., Maven 3.6.3) and specify the Maven installation method (automatic installation from Apache).

   ![alt text](image-17.png)

2. Ansible Plugin:

   - Go to Manage Jenkins > Tools.
   - Under Ansible, click Add Ansible.
   - Provide a name (e.g., Ansible 2.9.10) and specify the Ansible installation method (automatic installation from Ansible Galaxy).

   ![alt text](image-18.png)

3. SonarQube Scanner Plugin:

   - Go to Manage Jenkins > System.
   - Under SonarQube servers, add a new SonarQube server.
   - Provide a name (e.g., SonarQube), the server URL (e.g., `http://<your-sonarqube-server-ip>:9000`), and an authentication token.
   - Save the configuration.

   ![alt text](image-20.png)
   ![alt text](image-21.png)

4. Checkmarx Plugin:
   - Go to Manage Jenkins > System.
   - Under Checkmarx, add a new Checkmarx server configuration.
   - Provide the necessary Checkmarx server details and credentials.
   - Save the configuration.

# Step 5: Create Jenkins Pipeline

1. Create a New Pipeline Job:

   - Go to the Jenkins dashboard.
   - Click on New Item.
   - Enter an item name (e.g., CI/CD Pipeline).
   - Select Pipeline and click OK.

2. Configure the Pipeline:
   - In the Pipeline configuration, scroll down to the Pipeline section.
   - Set the Definition to Pipeline script from SCM.
   - Set SCM to Git.
   - Provide the repository URL (e.g., https://github.com/ogeeDeveloper/TestProject_CICD.git).
   - Set the Script Path to Jenkinsfile.

## Repository Files Explanation

### Jenkinsfile

```Groovy
pipeline {
    agent any
    environment {
        MAVEN_PROJECT_DIR = 'java-tomcat-sample'
        TERRAFORM_DIR = 'terraform'
        ANSIBLE_PLAYBOOK = 'deploy.yml'
        SONAR_TOKEN = credentials('SonarQubeServerToken')
        TERRAFORM_BIN = '/usr/local/bin/terraform'
        ANSIBLE_NAME = 'Ansible'
    }
    stages {
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
            junit '**/target/surefire-reports/*.xml'
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
```

**_Explanation:_**

- This is the Jenkins pipeline script that defines the CI/CD process. It includes stages for cleaning up the workspace, checking out the source code, building the application, performing SonarQube analysis, provisioning infrastructure with Terraform, and deploying the application using Ansible.

### deploy.yml

```yml
- hosts: app_servers
  become: yes
  vars:
    ansible_user: "deployer"
    server_ip: "{{ server_ip }}"
  tasks:
    - name: Ensure the system is updated
      apt:
        update_cache: yes

    - name: Wait for dpkg lock to be released
      shell: |
        while fuser /var/lib/dpkg/lock >/dev/null 2>&1; do
          echo "Waiting for dpkg lock to be released..."
          sleep 5
        done
      become: yes

    - name: Ensure Java is installed
      apt:
        name: openjdk-11-jdk
        state: present
      retries: 5
      delay: 10
      register: result
      until: result is succeeded
      become: yes

    - name: Copy application WAR to server
      copy:
        src: "{{ workspace }}/java-tomcat-sample/target/java-tomcat-sample-0.0.1.war"
        dest: /home/{{ ansible_user }}/java-tomcat-sample.war
      become: yes

    - name: Create a script to run the application
      copy:
        dest: /home/{{ ansible_user }}/run_app.sh
        content: |
          #!/bin/bash
          nohup java -jar /home/{{ ansible_user }}/java-tomcat-sample.war > /home/{{ ansible_user }}/app.log 2>&1 &
        mode: "0755"
      become: yes

    - name: Run the application
      shell: /home/{{ ansible_user }}/run_app.sh
      become: yes

    - name: Wait for the application to start
      pause:
        minutes: 1

    - name: Check if the application is running
      shell: pgrep -f "java -jar /home/{{ ansible_user }}/java-tomcat-sample.war"
      register: app_status
      failed_when: app_status.rc != 0
      become: yes

    - name: Print application logs
      shell: cat /home/{{ ansible_user }}/app.log
      register: app_log
      become: yes

    - debug:
        var: app_log.stdout_lines

    - name: Verify application deployment
      uri:
        url: "http://{{ server_ip }}:8080/"
        return_content: yes
      register: response
      retries: 5
      delay: 15

    - name: Check if application responded successfully
      assert:
        that:
          - response.status == 200
        fail_msg: "Application is not running or not accessible"
```

**_Explanation:_**

- This is the Ansible playbook that installs Java on the target server, copies the application JAR file, creates a script to run the application, runs the application, and verifies the deployment.

# Results and Analysis of CI/CD Pipeline Execution

1. Pipeline Execution Steps:

   - Provision resources using Terraform.
   - Build the Java application with Maven.
   - Run SonarQube analysis for code quality.
   - Deploy the application using Ansible.

2. Screenshots of Successful Runs:
   ![alt text](image-24.png)
   ![alt text](image-25.png)

3. Build Logs:
   ```bash
   Started by user admin
   Checking out git https://github.com/ogeeDeveloper/TestProject_CICD.git into /var/jenkins_home/workspace/TestImplementation@script/011548f96e290499de454e5f4104b27b0ef2698b5067cc550b1279c091fb4d38 to read Jenkinsfile
   Selected Git installation does not exist. Using Default
   The recommended git tool is: NONE
   No credentials specified
   > git rev-parse --resolve-git-dir /var/jenkins_home/workspace/TestImplementation@script/011548f96e290499de454e5f4104b27b0ef2698b5067cc550b1279c091fb4d38/.git # timeout=10
   Fetching changes from the remote Git repository
   > git config remote.origin.url https://github.com/ogeeDeveloper/TestProject_CICD.git # timeout=10
   Fetching upstream changes from https://github.com/ogeeDeveloper/TestProject_CICD.git
   > git --version # timeout=10
   > git --version # 'git version 2.39.2'
   > git fetch --tags --force --progress -- https://github.com/ogeeDeveloper/TestProject_CICD.git +refs/heads/*:refs/remotes/origin/* # timeout=10
   > git rev-parse refs/remotes/origin/dev^{commit} # timeout=10
   Checking out Revision f766bf0c178725f6520413f92ca08ef996135624 (refs/remotes/origin/dev)
   > git config core.sparsecheckout # timeout=10
   > git checkout -f f766bf0c178725f6520413f92ca08ef996135624 # timeout=10
   Commit message: "Retry Logic for Package Installation: Added retry logic to the task that ensures Java is installed. This will retry the task up to 5 times with a 10-second delay between retries if it fails due to the lock being held."
   > git rev-list --no-walk 396fa379b8c66486a5267dfa48f8213a69bad871 # timeout=10
   [Pipeline] Start of Pipeline
   [Pipeline] node
   Running on Jenkins in /var/jenkins_home/workspace/TestImplementation
   [Pipeline] {
   [Pipeline] stage
   [Pipeline] { (Declarative: Checkout SCM)
   [Pipeline] checkout
   Selected Git installation does not exist. Using Default
   The recommended git tool is: NONE
   No credentials specified
   > git rev-parse --resolve-git-dir /var/jenkins_home/workspace/TestImplementation/.git # timeout=10
   Fetching changes from the remote Git repository
   > git config remote.origin.url https://github.com/ogeeDeveloper/TestProject_CICD.git # timeout=10
   Fetching upstream changes from https://github.com/ogeeDeveloper/TestProject_CICD.git
   > git --version # timeout=10
   > git --version # 'git version 2.39.2'
   > git fetch --tags --force --progress -- https://github.com/ogeeDeveloper/TestProject_CICD.git +refs/heads/*:refs/remotes/origin/* # timeout=10
   > git rev-parse refs/remotes/origin/dev^{commit} # timeout=10
   Checking out Revision f766bf0c178725f6520413f92ca08ef996135624 (refs/remotes/origin/dev)
   > git config core.sparsecheckout # timeout=10
   > git checkout -f f766bf0c178725f6520413f92ca08ef996135624 # timeout=10
   Commit message: "Retry Logic for Package Installation: Added retry logic to the task that ensures Java is installed. This will retry the task up to 5 times with a 10-second delay between retries if it fails due to the lock being held."
   [Pipeline] }
   [Pipeline] // stage
   [Pipeline] withEnv
   [Pipeline] {
   [Pipeline] withCredentials
   Masking supported pattern matches of $SONAR_TOKEN
   [Pipeline] {
   [Pipeline] withEnv
   [Pipeline] {
   [Pipeline] stage
   [Pipeline] { (Cleanup)
   [Pipeline] deleteDir
   [Pipeline] }
   [Pipeline] // stage
   [Pipeline] stage
   [Pipeline] { (Checkout SCM)
   [Pipeline] git
   Selected Git installation does not exist. Using Default
   The recommended git tool is: NONE
   No credentials specified
   Cloning the remote Git repository
   Cloning repository https://github.com/ogeeDeveloper/TestProject_CICD.git
   > git init /var/jenkins_home/workspace/TestImplementation # timeout=10
   Fetching upstream changes from https://github.com/ogeeDeveloper/TestProject_CICD.git
   > git --version # timeout=10
   > git --version # 'git version 2.39.2'
   > git fetch --tags --force --progress -- https://github.com/ogeeDeveloper/TestProject_CICD.git +refs/heads/*:refs/remotes/origin/* # timeout=10
   > git config remote.origin.url https://github.com/ogeeDeveloper/TestProject_CICD.git # timeout=10
   > git config --add remote.origin.fetch +refs/heads/*:refs/remotes/origin/* # timeout=10
   Avoid second fetch
   > git rev-parse refs/remotes/origin/dev^{commit} # timeout=10
   Checking out Revision f766bf0c178725f6520413f92ca08ef996135624 (refs/remotes/origin/dev)
   > git config core.sparsecheckout # timeout=10
   > git checkout -f f766bf0c178725f6520413f92ca08ef996135624 # timeout=10
   > git branch -a -v --no-abbrev # timeout=10
   > git checkout -b dev f766bf0c178725f6520413f92ca08ef996135624 # timeout=10
   Commit message: "Retry Logic for Package Installation: Added retry logic to the task that ensures Java is installed. This will retry the task up to 5 times with a 10-second delay between retries if it fails due to the lock being held."
   [Pipeline] }
   [Pipeline] // stage
   [Pipeline] stage
   [Pipeline] { (Build)
   [Pipeline] dir
   Running in /var/jenkins_home/workspace/TestImplementation/java-tomcat-sample
   [Pipeline] {
   [Pipeline] script
   [Pipeline] {
   [Pipeline] tool
   [Pipeline] sh
   ```

- /var/jenkins_home/tools/hudson.tasks.Maven_MavenInstallation/Maven_3.9.7/bin/mvn clean package
  [INFO] Scanning for projects...
  [INFO]
  [INFO] -------------------< com.example:java-tomcat-sample >-------------------
  [INFO] Building hello Maven Webapp 0.0.1
  [INFO] from pom.xml
  [INFO] --------------------------------[ war ]---------------------------------
  [WARNING] Parameter 'version' is unknown for plugin 'maven-war-plugin:3.2.3:war (default-war)'
  [INFO]
  [INFO] --- clean:3.2.0:clean (default-clean) @ java-tomcat-sample ---
  [INFO]
  [INFO] --- resources:3.3.1:resources (default-resources) @ java-tomcat-sample ---
  [WARNING] Using platform encoding (UTF-8 actually) to copy filtered resources, i.e. build is platform dependent!
  [INFO] skip non existing resourceDirectory /var/jenkins_home/workspace/TestImplementation/java-tomcat-sample/src/main/resources
  [INFO]
  [INFO] --- compiler:3.13.0:compile (default-compile) @ java-tomcat-sample ---
  [INFO] No sources to compile
  [INFO]
  [INFO] --- resources:3.3.1:testResources (default-testResources) @ java-tomcat-sample ---
  [WARNING] Using platform encoding (UTF-8 actually) to copy filtered resources, i.e. build is platform dependent!
  [INFO] skip non existing resourceDirectory /var/jenkins_home/workspace/TestImplementation/java-tomcat-sample/src/test/resources
  [INFO]
  [INFO] --- compiler:3.13.0:testCompile (default-testCompile) @ java-tomcat-sample ---
  [INFO] No sources to compile
  [INFO]
  [INFO] --- surefire:2.22.2:test (default-test) @ java-tomcat-sample ---
  [INFO] No tests to run.
  [INFO]
  [INFO] --- war:3.2.3:war (default-war) @ java-tomcat-sample ---
  [INFO] Packaging webapp
  [INFO] Assembling webapp [java-tomcat-sample] in [/var/jenkins_home/workspace/TestImplementation/java-tomcat-sample/target/java-tomcat-sample-0.0.1]
  [INFO] Processing war project
  [INFO] Copying webapp resources [/var/jenkins_home/workspace/TestImplementation/java-tomcat-sample/src/main/webapp]
  [INFO] Webapp assembled in [84 msecs]
  [INFO] Building war: /var/jenkins_home/workspace/TestImplementation/java-tomcat-sample/target/java-tomcat-sample-0.0.1.war
  [INFO]
  [INFO] --- dependency:2.3:copy (default) @ java-tomcat-sample ---
  [INFO] Configured Artifact: com.github.jsimone:webapp-runner:8.5.11.3:jar
  [INFO] Copying webapp-runner-8.5.11.3.jar to /var/jenkins_home/workspace/TestImplementation/java-tomcat-sample/target/dependency/webapp-runner.jar
  [INFO] ------------------------------------------------------------------------
  [INFO] BUILD SUCCESS
  [INFO] ------------------------------------------------------------------------
  [INFO] Total time: 8.856 s
  [INFO] Finished at: 2024-06-06T17:45:34Z
  [INFO] ------------------------------------------------------------------------
  [Pipeline] }
  [Pipeline] // script
  [Pipeline] }
  [Pipeline] // dir
  [Pipeline] }
  [Pipeline] // stage
  [Pipeline] stage
  [Pipeline] { (SonarQube Analysis)
  [Pipeline] withSonarQubeEnv
  Injecting SonarQube environment variables using the configuration: SonarQube
  [Pipeline] {
  [Pipeline] dir
  Running in /var/jenkins_home/workspace/TestImplementation/java-tomcat-sample
  [Pipeline] {
  [Pipeline] script
  [Pipeline] {
  [Pipeline] tool
  [Pipeline] sh
  Warning: A secret was passed to "sh" using Groovy String interpolation, which is insecure.
  Affected argument(s) used the following variable(s): [SONAR_TOKEN]
  See https://jenkins.io/redirect/groovy-string-interpolation for details.
- /var/jenkins_home/tools/hudson.plugins.sonar.SonarRunnerInstallation/SonarQubeScanner/bin/sonar-scanner -Dsonar.projectKey=TestProjectCiCd -Dsonar.projectName=TestProject_CICD -Dsonar.projectVersion=1.0 -Dsonar.sources=src -Dsonar.java.binaries=target/classes -Dsonar.host.url=http://164.90.138.210:9000 -Dsonar.login=**\*\***
  17:45:35.861 INFO Scanner configuration file: /var/jenkins_home/tools/hudson.plugins.sonar.SonarRunnerInstallation/SonarQubeScanner/conf/sonar-scanner.properties
  17:45:35.874 INFO Project root configuration file: /var/jenkins_home/workspace/TestImplementation/java-tomcat-sample/sonar-project.properties
  17:45:35.941 INFO SonarScanner CLI 6.0.0.4432
  17:45:35.945 INFO Java 17.0.11 Eclipse Adoptium (64-bit)
  17:45:35.946 INFO Linux 6.8.0-35-generic amd64
  17:45:36.032 INFO User cache: /root/.sonar/cache
  17:45:37.670 INFO Communicating with SonarQube Server 10.5.1.90531
  17:45:39.716 INFO Load global settings
  17:45:39.964 INFO Load global settings (done) | time=251ms
  17:45:40.018 INFO Server id: 147B411E-AY_kpLK82Aurd9SWj9AS
  17:45:40.025 INFO User cache: /root/.sonar/cache
  17:45:40.047 INFO Loading required plugins
  17:45:40.048 INFO Load plugins index
  17:45:40.179 INFO Load plugins index (done) | time=131ms
  17:45:40.180 INFO Load/download plugins
  17:45:40.312 INFO Load/download plugins (done) | time=132ms
  17:45:41.114 INFO Process project properties
  17:45:41.132 INFO Process project properties (done) | time=17ms
  17:45:41.148 INFO Project key: TestProjectCiCd
  17:45:41.148 INFO Base dir: /var/jenkins_home/workspace/TestImplementation/java-tomcat-sample
  17:45:41.148 INFO Working dir: /var/jenkins_home/workspace/TestImplementation/java-tomcat-sample/.scannerwork
  17:45:41.185 INFO Load project settings for component key: 'TestProjectCiCd'
  17:45:41.271 INFO Load project settings for component key: 'TestProjectCiCd' (done) | time=86ms
  17:45:41.442 INFO Load quality profiles
  17:45:41.822 INFO Load quality profiles (done) | time=380ms
  17:45:41.886 INFO Auto-configuring with CI 'Jenkins'
  17:45:41.994 INFO Load active rules
  17:46:05.761 INFO Load active rules (done) | time=23767ms
  17:46:05.780 INFO Load analysis cache
  17:46:05.797 INFO Load analysis cache (404) | time=17ms
  17:46:05.939 WARN The property 'sonar.login' is deprecated and will be removed in the future. Please use the 'sonar.token' property instead when passing a token.
  17:46:05.984 INFO Preprocessing files...
  17:46:06.393 INFO 2 languages detected in 2 preprocessed files
  17:46:06.393 INFO 0 files ignored because of scm ignore settings
  17:46:06.397 INFO Loading plugins for detected languages
  17:46:06.398 INFO Load/download plugins
  17:46:06.406 INFO Load/download plugins (done) | time=8ms
  17:46:06.594 INFO Inconsistent constructor declaration on bean with name 'org.sonarsource.scanner.lib.internal.IsolatedClassloader@2374d36a-org.sonar.scanner.issue.IssueFilters': single autowire-marked constructor flagged as optional - this constructor is effectively required since there is no default constructor to fall back to: public org.sonar.scanner.issue.IssueFilters(org.sonar.api.batch.fs.internal.DefaultInputProject)
  17:46:06.661 INFO Load project repositories
  17:46:06.705 INFO Load project repositories (done) | time=44ms
  17:46:06.764 INFO Indexing files...
  17:46:06.770 INFO Project configuration:
  17:46:06.838 INFO 2 files indexed
  17:46:06.844 INFO Quality profile for jsp: Sonar way
  17:46:06.845 INFO Quality profile for xml: Sonar way
  17:46:06.845 INFO ------------- Run sensors on module TestProject_CICD
  17:46:06.970 INFO Load metrics repository
  17:46:07.084 INFO Load metrics repository (done) | time=114ms
  17:46:08.748 INFO Sensor HTML [web]
  17:46:08.944 INFO Sensor HTML [web] (done) | time=197ms
  17:46:08.945 INFO Sensor XML Sensor [xml]
  17:46:08.967 INFO 1 source file to be analyzed
  17:46:09.462 INFO 1/1 source file has been analyzed
  17:46:09.462 INFO Sensor XML Sensor [xml] (done) | time=517ms
  17:46:09.462 INFO Sensor JaCoCo XML Report Importer [jacoco]
  17:46:09.466 INFO 'sonar.coverage.jacoco.xmlReportPaths' is not defined. Using default locations: target/site/jacoco/jacoco.xml,target/site/jacoco-it/jacoco.xml,build/reports/jacoco/test/jacocoTestReport.xml
  17:46:09.468 INFO No report imported, no coverage information will be imported by JaCoCo XML Report Importer
  17:46:09.468 INFO Sensor JaCoCo XML Report Importer [jacoco] (done) | time=6ms
  17:46:09.468 INFO Sensor IaC Docker Sensor [iac]
  17:46:09.477 INFO 0 source files to be analyzed
  17:46:09.708 INFO 0/0 source files have been analyzed
  17:46:09.708 INFO Sensor IaC Docker Sensor [iac] (done) | time=240ms
  17:46:09.709 INFO Sensor TextAndSecretsSensor [text]
  17:46:09.709 INFO Available processors: 2
  17:46:09.709 INFO Using 2 threads for analysis.
  17:46:11.081 INFO 2 source files to be analyzed
  17:46:11.129 INFO 2/2 source files have been analyzed
  17:46:11.130 INFO Sensor TextAndSecretsSensor [text] (done) | time=1421ms
  17:46:11.144 INFO ------------- Run sensors on project
  17:46:11.269 INFO Sensor Zero Coverage Sensor
  17:46:11.270 INFO Sensor Zero Coverage Sensor (done) | time=1ms
  17:46:11.289 INFO CPD Executor 1 file had no CPD blocks
  17:46:11.289 INFO CPD Executor Calculating CPD for 0 files
  17:46:11.290 INFO CPD Executor CPD calculation finished (done) | time=0ms
  17:46:11.299 INFO SCM revision ID 'f766bf0c178725f6520413f92ca08ef996135624'
  17:46:11.589 INFO Analysis report generated in 254ms, dir size=194.8 kB
  17:46:11.628 INFO Analysis report compressed in 38ms, zip size=20.9 kB
  17:46:11.729 INFO Analysis report uploaded in 93ms
  17:46:11.737 INFO ANALYSIS SUCCESSFUL, you can find the results at: http://164.90.138.210:9000/dashboard?id=TestProjectCiCd
  17:46:11.737 INFO Note that you will be able to access the updated dashboard once the server has processed the submitted analysis report
  17:46:11.737 INFO More about the report processing at http://164.90.138.210:9000/api/ce/task?id=6b127d16-91b3-40df-976e-a655f254a109
  17:46:11.790 INFO Analysis total time: 31.355 s
  17:46:11.793 INFO EXECUTION SUCCESS
  17:46:11.797 INFO Total time: 36.017s
  Exception in thread "Thread-0" java.lang.NoClassDefFoundError: ch/qos/logback/classic/spi/ThrowableProxy
  at ch.qos.logback.classic.spi.LoggingEvent.<init>(LoggingEvent.java:145)
  at ch.qos.logback.classic.Logger.buildLoggingEventAndAppend(Logger.java:424)
  at ch.qos.logback.classic.Logger.filterAndLog_0_Or3Plus(Logger.java:386)
  at ch.qos.logback.classic.Logger.error(Logger.java:543)
  at org.eclipse.jgit.internal.util.ShutdownHook.cleanup(ShutdownHook.java:87)
  at java.base/java.lang.Thread.run(Unknown Source)
  Caused by: java.lang.ClassNotFoundException: ch.qos.logback.classic.spi.ThrowableProxy
  at java.base/java.net.URLClassLoader.findClass(Unknown Source)
  at org.sonarsource.scanner.lib.internal.IsolatedClassloader.loadClass(IsolatedClassloader.java:82)
  at java.base/java.lang.ClassLoader.loadClass(Unknown Source)
  ... 6 more
  [Pipeline] }
  [Pipeline] // script
  [Pipeline] }
  [Pipeline] // dir
  [Pipeline] }
  [Pipeline] // withSonarQubeEnv
  [Pipeline] }
  [Pipeline] // stage
  [Pipeline] stage
  [Pipeline] { (Infrastructure Provisioning)
  [Pipeline] dir
  Running in /var/jenkins_home/workspace/TestImplementation/terraform
  [Pipeline] {
  [Pipeline] withCredentials
  Masking supported pattern matches of $DO_TOKEN or $SSH_KEY_ID or $SSH_PRIVATE_KEY_PATH or $SSH_PUBLIC_KEY
  [Pipeline] {
  [Pipeline] script
  [Pipeline] {
  [Pipeline] sh
- /usr/local/bin/terraform init

[0m[1mInitializing the backend...[0m

[0m[1mInitializing provider plugins...[0m

- Finding digitalocean/digitalocean versions matching "~> 2.0"...
- Installing digitalocean/digitalocean v2.39.2...
- Installed digitalocean/digitalocean v2.39.2 (signed by a HashiCorp partner, key ID [0m[1mF82037E524B9C0E8[0m[0m)

Partner and community providers are signed by their developers.
If you'd like to know more about provider signing, you can read about it here:
https://www.terraform.io/docs/cli/plugins/signing.html

Terraform has created a lock file [1m.terraform.lock.hcl[0m to record the provider
selections it made above. Include this file in your version control repository
so that Terraform can guarantee to make the same selections by default when
you run "terraform init" in the future.[0m

[0m[1m[32mTerraform has been successfully initialized![0m[32m[0m
[0m[32m
You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.

If you ever set or change modules or backend configuration for Terraform,
rerun this command to reinitialize your working directory. If you forget, other
commands will detect it and remind you to do so if necessary.[0m
[Pipeline] sh
Warning: A secret was passed to "sh" using Groovy String interpolation, which is insecure.
Affected argument(s) used the following variable(s): [SSH_KEY_ID, DO_TOKEN, SSH_PUBLIC_KEY, SSH_PRIVATE_KEY_PATH]
See https://jenkins.io/redirect/groovy-string-interpolation for details.

- /usr/local/bin/terraform plan -var do_token=\***\* -var ssh_key_id=\*\*** -var ssh_private_key=\***\* -var ssh_public_key=\*\***

Terraform used the selected providers to generate the following execution
plan. Resource actions are indicated with the following symbols:
[32m+[0m create
[0m
Terraform will perform the following actions:

[1m # digitalocean_droplet.app_server[0m will be created[0m[0m
[0m [32m+[0m[0m resource "digitalocean_droplet" "app_server" {
[32m+[0m [0m[1m[0mbackups[0m[0m = false
[32m+[0m [0m[1m[0mcreated_at[0m[0m = (known after apply)
[32m+[0m [0m[1m[0mdisk[0m[0m = (known after apply)
[32m+[0m [0m[1m[0mgraceful_shutdown[0m[0m = false
[32m+[0m [0m[1m[0mid[0m[0m = (known after apply)
[32m+[0m [0m[1m[0mimage[0m[0m = "ubuntu-20-04-x64"
[32m+[0m [0m[1m[0mipv4_address[0m[0m = (known after apply)
[32m+[0m [0m[1m[0mipv4_address_private[0m[0m = (known after apply)
[32m+[0m [0m[1m[0mipv6[0m[0m = false
[32m+[0m [0m[1m[0mipv6_address[0m[0m = (known after apply)
[32m+[0m [0m[1m[0mlocked[0m[0m = (known after apply)
[32m+[0m [0m[1m[0mmemory[0m[0m = (known after apply)
[32m+[0m [0m[1m[0mmonitoring[0m[0m = false
[32m+[0m [0m[1m[0mname[0m[0m = "app-server"
[32m+[0m [0m[1m[0mprice_hourly[0m[0m = (known after apply)
[32m+[0m [0m[1m[0mprice_monthly[0m[0m = (known after apply)
[32m+[0m [0m[1m[0mprivate_networking[0m[0m = (known after apply)
[32m+[0m [0m[1m[0mregion[0m[0m = "nyc3"
[32m+[0m [0m[1m[0mresize_disk[0m[0m = true
[32m+[0m [0m[1m[0msize[0m[0m = "s-1vcpu-1gb"
[32m+[0m [0m[1m[0mssh_keys[0m[0m = [
[32m+[0m [0m"****",
]
[32m+[0m [0m[1m[0mstatus[0m[0m = (known after apply)
[32m+[0m [0m[1m[0murn[0m[0m = (known after apply)
[32m+[0m [0m[1m[0mvcpus[0m[0m = (known after apply)
[32m+[0m [0m[1m[0mvolume_ids[0m[0m = (known after apply)
[32m+[0m [0m[1m[0mvpc_uuid[0m[0m = (known after apply)
}

[0m[1mPlan:[0m 1 to add, 0 to change, 0 to destroy.
[0m[0m
[1mChanges to Outputs:[0m[0m
[32m+[0m [0m[1m[0mapp_server_ip[0m[0m = (known after apply)
[90m
─────────────────────────────────────────────────────────────────────────────[0m

Note: You didn't use the -out option to save this plan, so Terraform can't
guarantee to take exactly these actions if you run "terraform apply" now.
[Pipeline] sh
Warning: A secret was passed to "sh" using Groovy String interpolation, which is insecure.
Affected argument(s) used the following variable(s): [SSH_KEY_ID, DO_TOKEN, SSH_PUBLIC_KEY, SSH_PRIVATE_KEY_PATH]
See https://jenkins.io/redirect/groovy-string-interpolation for details.

- /usr/local/bin/terraform apply -auto-approve -var do_token=\***\* -var ssh_key_id=\*\*** -var ssh_private_key=\***\* -var ssh_public_key=\*\***

Terraform used the selected providers to generate the following execution
plan. Resource actions are indicated with the following symbols:
[32m+[0m create
[0m
Terraform will perform the following actions:

[1m # digitalocean_droplet.app_server[0m will be created[0m[0m
[0m [32m+[0m[0m resource "digitalocean_droplet" "app_server" {
[32m+[0m [0m[1m[0mbackups[0m[0m = false
[32m+[0m [0m[1m[0mcreated_at[0m[0m = (known after apply)
[32m+[0m [0m[1m[0mdisk[0m[0m = (known after apply)
[32m+[0m [0m[1m[0mgraceful_shutdown[0m[0m = false
[32m+[0m [0m[1m[0mid[0m[0m = (known after apply)
[32m+[0m [0m[1m[0mimage[0m[0m = "ubuntu-20-04-x64"
[32m+[0m [0m[1m[0mipv4_address[0m[0m = (known after apply)
[32m+[0m [0m[1m[0mipv4_address_private[0m[0m = (known after apply)
[32m+[0m [0m[1m[0mipv6[0m[0m = false
[32m+[0m [0m[1m[0mipv6_address[0m[0m = (known after apply)
[32m+[0m [0m[1m[0mlocked[0m[0m = (known after apply)
[32m+[0m [0m[1m[0mmemory[0m[0m = (known after apply)
[32m+[0m [0m[1m[0mmonitoring[0m[0m = false
[32m+[0m [0m[1m[0mname[0m[0m = "app-server"
[32m+[0m [0m[1m[0mprice_hourly[0m[0m = (known after apply)
[32m+[0m [0m[1m[0mprice_monthly[0m[0m = (known after apply)
[32m+[0m [0m[1m[0mprivate_networking[0m[0m = (known after apply)
[32m+[0m [0m[1m[0mregion[0m[0m = "nyc3"
[32m+[0m [0m[1m[0mresize_disk[0m[0m = true
[32m+[0m [0m[1m[0msize[0m[0m = "s-1vcpu-1gb"
[32m+[0m [0m[1m[0mssh_keys[0m[0m = [
[32m+[0m [0m"****",
]
[32m+[0m [0m[1m[0mstatus[0m[0m = (known after apply)
[32m+[0m [0m[1m[0murn[0m[0m = (known after apply)
[32m+[0m [0m[1m[0mvcpus[0m[0m = (known after apply)
[32m+[0m [0m[1m[0mvolume_ids[0m[0m = (known after apply)
[32m+[0m [0m[1m[0mvpc_uuid[0m[0m = (known after apply)
}

[0m[1mPlan:[0m 1 to add, 0 to change, 0 to destroy.
[0m[0m
[1mChanges to Outputs:[0m[0m
[32m+[0m [0m[1m[0mapp_server_ip[0m[0m = (known after apply)
[0m[1mdigitalocean_droplet.app_server: Creating...[0m[0m
[0m[1mdigitalocean_droplet.app_server: Still creating... [10s elapsed][0m[0m
[0m[1mdigitalocean_droplet.app_server: Still creating... [20s elapsed][0m[0m
[0m[1mdigitalocean_droplet.app_server: Still creating... [30s elapsed][0m[0m
[0m[1mdigitalocean_droplet.app_server: Provisioning with 'remote-exec'...[0m[0m
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0mConnecting to remote host via SSH...
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m Host: 159.65.174.94
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m User: root
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m Password: false
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m Private key: true
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m Certificate: false
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m SSH Agent: false
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m Checking Host Key: false
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m Target Platform: unix
[0m[1mdigitalocean_droplet.app_server: Still creating... [40s elapsed][0m[0m
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0mConnecting to remote host via SSH...
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m Host: 159.65.174.94
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m User: root
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m Password: false
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m Private key: true
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m Certificate: false
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m SSH Agent: false
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m Checking Host Key: false
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m Target Platform: unix
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0mConnecting to remote host via SSH...
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m Host: 159.65.174.94
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m User: root
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m Password: false
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m Private key: true
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m Certificate: false
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m SSH Agent: false
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m Checking Host Key: false
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m Target Platform: unix
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0mConnecting to remote host via SSH...
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m Host: 159.65.174.94
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m User: root
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m Password: false
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m Private key: true
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m Certificate: false
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m SSH Agent: false
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m Checking Host Key: false
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m Target Platform: unix
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0mConnected!
[0m[1mdigitalocean_droplet.app_server: Still creating... [50s elapsed][0m[0m
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m0% [Working]
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0mGet:1 http://security.ubuntu.com/ubuntu focal-security InRelease [128 kB]
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m0% [Connected to archive.ubuntu.com (91
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0mHit:2 http://archive.ubuntu.com/ubuntu focal InRelease
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m0% [Waiting for headers] [1 InRelease 1
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0mGet:3 http://archive.ubuntu.com/ubuntu focal-updates InRelease [128 kB]
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0mGet:4 http://archive.ubuntu.com/ubuntu focal-backports InRelease [128 kB]
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m0% [Working]
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m0% [Working]
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m0% [Working]
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m0% [Working]
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m0% [Working]
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0mGet:5 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 Packages [3337 kB]
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m0% [5 Packages 298 kB/3337 kB 9%]
...
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0mGet:16 http://archive.ubuntu.com/ubuntu focal-updates/multiverse amd64 c-n-f Metadata [620 B]
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m0% [5 Packages store 0 B] [16 Commands-
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m0% [5 Packages store 0 B]
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m0% [5 Packages store 0 B]
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0mGet:17 http://archive.ubuntu.com/ubuntu focal-backports/main amd64 Packages [45.7 kB]
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m0% [5 Packages store 0 B]
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0mGet:18 http://archive.ubuntu.com/ubuntu focal-backports/main Translation-en [16.3 kB]
...
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m93% [5 Packages store 0 B]
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0mGet:32 http://security.ubuntu.com/ubuntu focal-security/multiverse amd64 Packages [24.0 kB]
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m93% [5 Packages store 0 B] [32 Packages
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m93% [5 Packages store 0 B]
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0mGet:33 http://security.ubuntu.com/ubuntu focal-security/multiverse Translation-en [5904 B]
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m93% [5 Packages store 0 B] [33 Translat
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m93% [5 Packages store 0 B]
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0mGet:34 http://security.ubuntu.com/ubuntu focal-security/multiverse amd64 c-n-f Metadata [548 B]
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0m93% [5 Packages store 0 B] [34 Commands
...
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0mFetched 17.2 MB in 11s (1627 kB/s)
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0mReading package lists... 0%
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0mReading package lists... 0%
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0mReading package lists... 0%
...
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0mReading package lists... 99%
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0mReading package lists... Done
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0mE: Could not get lock /var/lib/dpkg/lock-frontend. It is held by process 1659 (apt-get)
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0mN: Be aware that removing the lock file is not a solution and may break your system.
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0mE: Unable to acquire the dpkg frontend lock (/var/lib/dpkg/lock-frontend), is another process using it?
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0mE: Could not get lock /var/lib/dpkg/lock-frontend. It is held by process 1659 (apt-get)
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0mN: Be aware that removing the lock file is not a solution and may break your system.
[0m[1mdigitalocean_droplet.app_server (remote-exec):[0m [0mE: Unable to acquire the dpkg frontend lock (/var/lib/dpkg/lock-frontend), is another process using it?
[0m[1mdigitalocean_droplet.app_server: Provisioning with 'local-exec'...[0m[0m
[0m[1mdigitalocean_droplet.app_server (local-exec):[0m [0mExecuting: ["/bin/sh" "-c" " ssh-keyscan -H 159.65.174.94 >> ~/.ssh/known_hosts\n"]
[0m[1mdigitalocean_droplet.app_server (local-exec):[0m [0m# 159.65.174.94:22 SSH-2.0-OpenSSH_8.2p1 Ubuntu-4ubuntu0.5
[0m[1mdigitalocean_droplet.app_server (local-exec):[0m [0m# 159.65.174.94:22 SSH-2.0-OpenSSH_8.2p1 Ubuntu-4ubuntu0.5
[0m[1mdigitalocean_droplet.app_server (local-exec):[0m [0m# 159.65.174.94:22 SSH-2.0-OpenSSH_8.2p1 Ubuntu-4ubuntu0.5
[0m[1mdigitalocean_droplet.app_server (local-exec):[0m [0m# 159.65.174.94:22 SSH-2.0-OpenSSH_8.2p1 Ubuntu-4ubuntu0.5
[0m[1mdigitalocean_droplet.app_server (local-exec):[0m [0m# 159.65.174.94:22 SSH-2.0-OpenSSH_8.2p1 Ubuntu-4ubuntu0.5
[0m[1mdigitalocean_droplet.app_server: Creation complete after 1m11s [id=423883970][0m
[0m[1m[32m
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
[0m[0m[1m[32m
Outputs:

[0mapp_server_ip = "159.65.174.94"
[Pipeline] sh

- /usr/local/bin/terraform output -json
  [Pipeline] readJSON
  [Pipeline] }
  [Pipeline] // script
  [Pipeline] }
  [Pipeline] // withCredentials
  [Pipeline] }
  [Pipeline] // dir
  [Pipeline] }
  [Pipeline] // stage
  [Pipeline] stage
  [Pipeline] { (Deploy Application)
  [Pipeline] withCredentials
  Masking supported pattern matches of $ANSIBLE_PASSWORD or $SSH_KEY_FILE
  [Pipeline] {
  [Pipeline] script
  [Pipeline] {
  [Pipeline] tool
  [Pipeline] sh
- export PATH=/bin:/opt/java/openjdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
  [Pipeline] sh
- echo Ansible Home:
  Ansible Home:
  [Pipeline] sh
- echo [app_servers]
  159.65.174.94
  [Pipeline] sh
  Warning: A secret was passed to "sh" using Groovy String interpolation, which is insecure.
  Affected argument(s) used the following variable(s): [ANSIBLE_PASSWORD]
  See https://jenkins.io/redirect/groovy-string-interpolation for details.
- /bin/ansible-playbook deploy.yml -i dynamic_inventory.ini -e ansible_user=deployer -e ansible_password=\*\*\*\* -e server_ip=159.65.174.94 -e workspace=/var/jenkins_home/workspace/TestImplementation

PLAY [app_servers] ******\*\*******\*\*******\*\*******\*******\*\*******\*\*******\*\*******

TASK [Gathering Facts] ****\*\*\*\*****\*\*\*\*****\*\*\*\*****\*****\*\*\*\*****\*\*\*\*****\*\*\*\*****
ok: [159.65.174.94]

TASK [Ensure the system is updated] **\*\*\*\***\*\*\*\***\*\*\*\***\*\*\*\***\*\*\*\***\*\*\*\***\*\*\*\***
changed: [159.65.174.94]

TASK [Wait for dpkg lock to be released] **\*\*\*\***\*\***\*\*\*\***\*\*\***\*\*\*\***\*\***\*\*\*\***
changed: [159.65.174.94]

TASK [Ensure Java is installed] ****\*\*****\*\*****\*\*****\*\*\*\*****\*\*****\*\*****\*\*****
changed: [159.65.174.94]

TASK [Copy application WAR to server] **\*\*\*\***\*\*\*\***\*\*\*\***\*\***\*\*\*\***\*\*\*\***\*\*\*\***
changed: [159.65.174.94]

TASK [Run the application] ****\*\*\*\*****\*\*****\*\*\*\*****\*****\*\*\*\*****\*\*****\*\*\*\*****
changed: [159.65.174.94]

PLAY RECAP ******\*\*\*\*******\*\*******\*\*\*\*******\*******\*\*\*\*******\*\*******\*\*\*\*******
159.65.174.94 : ok=6 changed=5 unreachable=0 failed=0 skipped=0 rescued=0 ignored=0

[Pipeline] }
[Pipeline] // script
[Pipeline] }
[Pipeline] // withCredentials
[Pipeline] }
[Pipeline] // stage
[Pipeline] stage
[Pipeline] { (Declarative: Post Actions)
[Pipeline] junit
[Pipeline] }
[Pipeline] // stage
[Pipeline] }
[Pipeline] // withEnv
[Pipeline] }
[Pipeline] // withCredentials
[Pipeline] }
[Pipeline] // withEnv
[Pipeline] }
[Pipeline] // node
[Pipeline] End of Pipeline

```

```
