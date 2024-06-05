pipeline {
    agent any
    environment {
        MAVEN_PROJECT_DIR = 'java-tomcat-sample'
        TERRAFORM_DIR = 'terraform'
        ANSIBLE_PLAYBOOK = 'deploy.yml'
        ANSIBLE_INVENTORY = 'inventory.ini'
        SONAR_TOKEN = credentials('SonarQubeServerToken')
    }
    stages {
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
                                -Dsonar.login=${env.SONAR_TOKEN}
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
                        string(credentialsId: 'ssh_key_id', variable: 'SSH_KEY_ID')
                    ]) {
                        script {
                            sh 'echo $PATH'  // Debugging step to print PATH
                            sh 'export PATH=/snap/bin:$PATH && terraform init'
                            sh 'export PATH=/snap/bin:$PATH && terraform apply -auto-approve -var do_token=${DO_TOKEN} -var ssh_key_id=${SSH_KEY_ID}'
                        }
                    }
                }
            }
        }
        stage('Deploy Application') {
            steps {
                ansiblePlaybook playbook: "${ANSIBLE_PLAYBOOK}", inventory: "${ANSIBLE_INVENTORY}", extraVars: [
                    "ansible_user": "deployer",
                    "ansible_password": "${ANSIBLE_PASSWORD}",
                    "server_ip": "${SERVER_IP}",
                    "workspace": "${env.WORKSPACE}"
                ]
            }
        }
        stage('DAST with OWASP ZAP') {
            steps {
                script {
                    zapAttack target: 'http://test-environment-url'
                }
            }
        }
        stage('Deploy to Production') {
            steps {
                script {
                    echo 'Deploying to production...'
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
