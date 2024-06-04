pipeline {
    agent any

    environment {
        GIT_REPO = 'https://github.com/ogeeDeveloper/TestProject_CICD.git'
        MAVEN_PROJECT_DIR = 'java-tomcat-sample'
        TERRAFORM_DIR = 'terraform'
        ANSIBLE_PLAYBOOK = 'deploy.yml'
        ANSIBLE_INVENTORY = 'inventory.ini'
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
                            sh 'mvn sonar:sonar'
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
                        sh 'terraform init'
                        sh 'terraform apply -auto-approve'
                    }
                }
            }
        }
        stage('Deploy Application') {
            steps {
                script {
                    // Retrieve the IP address of the provisioned server from Terraform
                    def server_ip = sh(script: "cd ${env.TERRAFORM_DIR} && terraform output -raw app_server_ip", returnStdout: true).trim()
                    
                    // Write the dynamic inventory to a file
                    writeFile file: 'inventory.ini', text: "[app_servers]\n${server_ip} ansible_user=deployer ansible_ssh_private_key_file=/path/to/your/private/key\n[all:vars]\nansible_python_interpreter=/usr/bin/python3"
                    
                    // Use Ansible to deploy the application to the server
                    ansiblePlaybook playbook: env.ANSIBLE_PLAYBOOK, inventory: 'inventory.ini', extraVars: [
                        "ansible_user": "deployer",
                        "ansible_password": "your_ansible_password",  // replace with your actual password if using password instead of key
                        "server_ip": server_ip,
                        "workspace": "${env.WORKSPACE}"
                    ]
                    
                    // Save the application URL for later stages
                    env.APP_URL = "http://${server_ip}:8080"  // Adjust the port if necessary
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
                    ansiblePlaybook playbook: 'deploy_prod.yml', inventory: 'inventory.ini', extraVars: [
                        "ansible_user": "deployer",
                        "ansible_password": "your_ansible_password",  // replace with your actual password if using password instead of key
                        "server_ip": server_ip,
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
            // Send email notification on successful build
            emailext to: 'team@example.com', subject: 'Build Successful', body: 'The build was successful!'
        }
        failure {
            // Send email notification on failed build
            emailext to: 'team@example.com', subject: 'Build Failed', body: 'The build failed. Please check Jenkins for details.'
        }
    }
}
