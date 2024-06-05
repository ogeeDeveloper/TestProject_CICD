pipeline {
    agent any

    environment {
        GIT_REPO = 'https://github.com/ogeeDeveloper/TestProject_CICD.git'
        MAVEN_PROJECT_DIR = 'java-tomcat-sample'
        TERRAFORM_DIR = 'terraform'
        ANSIBLE_PLAYBOOK = 'deploy.yml'
        ANSIBLE_INVENTORY = 'inventory.ini'
        SSH_PRIVATE_KEY_PATH = '/root/.ssh/id_rsa'
        APP_SERVER_IP = ''
        MAVEN_HOME = tool name: 'Maven 3.9.7'  // Ensure this matches your Maven installation name
        PATH = "${env.MAVEN_HOME}/bin:${env.PATH}"
        SONARQUBE_SCANNER = tool name: 'SonarQube'  // Ensure this matches your SonarQube Scanner installation name
    }

    stages {
        stage('Checkout') {
            steps {
                // Clone the repository from GitHub
                git url: env.GIT_REPO
            }
        }
        stage('Build') {
            steps {
                // Navigate to the Maven project directory and build the project
                dir(env.MAVEN_PROJECT_DIR) {
                    sh 'mvn clean install'
                }
            }
        }
        stage('Static Code Analysis') {
            steps {
                script {
                    // Perform SonarQube analysis
                    withSonarQubeEnv('SonarQube') {
                        dir(env.MAVEN_PROJECT_DIR) {
                            sh "${env.SONARQUBE_SCANNER}/bin/sonar-scanner"
                        }
                    }
                    // Perform Checkmarx analysis
                    checkmarxScan failBuildOnError: true
                }
            }
        }
        stage('Infrastructure Provisioning') {
            steps {
                script {
                    // Navigate to the Terraform directory and provision infrastructure
                    dir(env.TERRAFORM_DIR) {
                        // Initialize Terraform
                        sh 'terraform init'
                        // Check if the droplet exists
                        def result = sh(script: "terraform output -raw app_server_ip || echo ''", returnStdout: true).trim()
                        if (result == '') {
                            // Provision a new droplet if it doesn't exist
                            sh 'terraform apply -auto-approve'
                            // Retrieve the new IP address
                            env.APP_SERVER_IP = sh(script: "terraform output -raw app_server_ip", returnStdout: true).trim()
                        } else {
                            // Use the existing IP address
                            env.APP_SERVER_IP = result
                        }
                    }
                }
            }
        }
        stage('Deploy Application') {
            steps {
                script {
                    // Write the dynamic inventory to a file
                    writeFile file: env.ANSIBLE_INVENTORY, text: "[app_servers]\n${env.APP_SERVER_IP} ansible_user=deployer ansible_ssh_private_key_file=${env.SSH_PRIVATE_KEY_PATH}\n[all:vars]\nansible_python_interpreter=/usr/bin/python3"
                    
                    // Use Ansible to deploy the application to the server
                    ansiblePlaybook playbook: env.ANSIBLE_PLAYBOOK, inventory: env.ANSIBLE_INVENTORY, extraVars: [
                        "ansible_user": "deployer",
                        "ansible_password": "Mypassword",  // replace with your actual password if using password instead of key
                        "server_ip": env.APP_SERVER_IP,
                        "workspace": "${env.WORKSPACE}"
                    ]
                    
                    // Save the application URL for later stages
                    env.APP_URL = "http://${env.APP_SERVER_IP}:8080"  // Adjust the port if necessary
                }
            }
        }
        stage('DAST with OWASP ZAP') {
            steps {
                script {
                    // Perform dynamic application security testing with OWASP ZAP
                    zapAttack target: env.APP_URL
                }
            }
        }
        stage('Deploy to Production') {
            steps {
                script {
                    // Deploy the application to the production environment using Terraform and Ansible
                    dir(env.TERRAFORM_DIR) {
                        sh 'terraform apply -var="env=prod" -auto-approve'
                    }
                    ansiblePlaybook playbook: 'deploy_prod.yml', inventory: env.ANSIBLE_INVENTORY, extraVars: [
                        "ansible_user": "deployer",
                        "ansible_password": "Mypassword",  // replace with your actual password if using password instead of key
                        "server_ip": env.APP_SERVER_IP,
                        "workspace": "${env.WORKSPACE}"
                    ]
                }
            }
        }
    }
    post {
        always {
            // Archive test results and build artifacts
            junit 'target/surefire-reports/*.xml'
            archiveArtifacts artifacts: '**/target/*.jar', fingerprint: true
        }
        success {
            script {
                echo "Build and deployment successful!"
            }
        }
        failure {
            script {
                echo "Build failed. Please check Jenkins for details."
            }
        }
    }
}
