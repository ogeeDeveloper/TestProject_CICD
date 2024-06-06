pipeline {
    agent any
    environment {
        MAVEN_PROJECT_DIR = 'java-tomcat-sample'
        TERRAFORM_DIR = 'terraform'
        ANSIBLE_PLAYBOOK = 'deploy.yml'
        ANSIBLE_INVENTORY = 'inventory.ini'
        SONAR_TOKEN = credentials('SonarQubeServerToken')
        TERRAFORM_BIN = '/usr/local/bin/terraform'
        ANSIBLE_NAME = 'Ansible' // Reference to the Ansible tool configured in Jenkins
    }
    stages {
        stage('Cleanup Workspace') {
            steps {
                deleteDir()
            }
        }
        stage('Checkout SCM') {
            steps {
                checkout([$class: 'GitSCM', branches: [[name: '*/dev']],
                          doGenerateSubmoduleConfigurations: false,
                          extensions: [[$class: 'CleanBeforeCheckout']], // Clean workspace before checkout
                          submoduleCfg: [],
                          userRemoteConfigs: [[url: 'https://github.com/ogeeDeveloper/TestProject_CICD.git', credentialsId: 'your-git-credentials-id']]])
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
                        string(credentialsId: 'ssh_key_id', variable: 'SSH_KEY_ID')
                    ]) {
                        script {
                            // Initialize Terraform
                            sh "${TERRAFORM_BIN} init"

                            // Plan Terraform changes
                            def planOutput = sh(script: "${TERRAFORM_BIN} plan -var do_token=${DO_TOKEN} -var ssh_key_id=${SSH_KEY_ID}", returnStdout: true).trim()

                            if (planOutput.contains("No changes")) {
                                // Capture Terraform output for the existing server
                                def output = sh(script: "${TERRAFORM_BIN} output -json", returnStdout: true).trim()
                                def jsonOutput = readJSON text: output
                                env.SERVER_IP = jsonOutput.app_server_ip.value
                            } else {
                                // Apply Terraform changes if necessary
                                sh "${TERRAFORM_BIN} apply -auto-approve -var do_token=${DO_TOKEN} -var ssh_key_id=${SSH_KEY_ID}"
                                // Capture Terraform output
                                def output = sh(script: "${TERRAFORM_BIN} output -json", returnStdout: true).trim()
                                def jsonOutput = readJSON text: output
                                env.SERVER_IP = jsonOutput.app_server_ip.value
                            }
                        }
                    }
                }
            }
        }
        stage('Update Inventory') {
            steps {
                script {
                    writeFile file: "${ANSIBLE_INVENTORY}", text: """
                        [app_servers]
                        ${SERVER_IP} ansible_user=deployer ansible_ssh_private_key_file=/root/.ssh/id_rsa

                        [all:vars]
                        ansible_python_interpreter=/usr/bin/python3
                    """
                }
            }
        }
        stage('Deploy Application') {
            steps {
                withCredentials([
                    string(credentialsId: 'ansible_password', variable: 'ANSIBLE_PASSWORD'),
                    sshUserPrivateKey(credentialsId: 'ansible_ssh_key', keyFileVariable: 'SSH_KEY_FILE', passphraseVariable: '', usernameVariable: 'ANSIBLE_USER')
                ]) {
                    script {
                        def ansibleHome = tool name: "${ANSIBLE_NAME}"
                        sh "export PATH=${ansibleHome}/bin:\$PATH"
                        sh "echo 'Ansible Home: ${ansibleHome}'"
                        sh "ls -l ${ansibleHome}/bin"
                        sh "${ansibleHome}/bin/ansible-playbook ${ANSIBLE_PLAYBOOK} -i ${ANSIBLE_INVENTORY} -e ansible_user=${ANSIBLE_USER} -e ansible_password=${ANSIBLE_PASSWORD} -e server_ip=${SERVER_IP} -e workspace=${WORKSPACE}"
                    }
                }
            }
        }
        /* Commenting out DAST with OWASP ZAP for now
        stage('DAST with OWASP ZAP') {
            steps {
                script {
                    zapAttack target: 'http://test-environment-url'
                }
            }
        }
        */
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
