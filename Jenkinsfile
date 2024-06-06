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
                            def start = System.currentTimeMillis()
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
                            def end = System.currentTimeMillis()
                            echo "Provisioning time: ${(end - start) / 1000} seconds"
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
                        def start = System.currentTimeMillis()
                        def ansibleHome = tool name: "${ANSIBLE_NAME}"
                        sh "export PATH=${ansibleHome}/bin:\$PATH"
                        sh "echo 'Ansible Home: ${ansibleHome}'"
                        sh "echo '[app_servers]\n${SERVER_IP}' > dynamic_inventory.ini"
                        sh "${ansibleHome}/bin/ansible-playbook ${ANSIBLE_PLAYBOOK} -i dynamic_inventory.ini -e ansible_user=${ANSIBLE_USER} -e ansible_password=${ANSIBLE_PASSWORD} -e server_ip=${SERVER_IP} -e workspace=${WORKSPACE}"
                        def end = System.currentTimeMillis()
                        echo "Deployment time: ${(end - start) / 1000} seconds"

                    }
                }
            }
        }
         stage('Expose Prometheus Metrics') {
            steps {
                script {
                    sh 'curl -X POST http://164.90.138.210:8080/prometheus/metrics'
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
