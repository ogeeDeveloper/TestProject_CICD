pipeline {
    agent any

    environment {
        VERSION = '0.1.0'
        RELEASE_VERSION = 'R.2'
        SONAR_HOST_URL = 'http://174.138.63.154:9000'
        SCANNER_HOME = tool name: 'SonarQubeScanner', type: 'hudson.plugins.sonar.SonarRunnerInstallation'
        DIGITALOCEAN_TOKEN = credentials('digitalocean_token')
        DIGITALOCEAN_REGION = credentials('digitalocean_region')
        DOCKER_COMPOSE = '/usr/local/bin/docker-compose'
        DOCKER = '/usr/bin/docker'
    }

    tools {
        maven 'Maven'
        git 'Default'
    }

    stages {
        stage('Prepare') {
            steps {
                checkout scm
                echo "Checkout complete."
            }
        }

        stage('Audit Tools') {
            steps {
                dir('java-tomcat-sample') {
                    sh 'java -version'
                    sh 'mvn -version'
                    sh 'printenv'
                    sh 'ls -l'
                    echo "Audit tools completed successfully."
                }
            }
        }

        stage('Unit Test') {
            steps {
                dir('java-tomcat-sample') {
                    sh 'mvn test'
                    echo "Unit tests completed."
                }
            }
        }

        stage('SonarQube Analysis') {
            steps {
                dir('java-tomcat-sample') {
                    script {
                        withSonarQubeEnv('SonarQubeScanner') {
                            sh 'mvn clean verify sonar:sonar -Dsonar.ws.timeout=600'
                            echo "SonarQube analysis completed."
                        }
                    }
                }
            }
        }

        stage('Build and Package') {
            steps {
                dir('java-tomcat-sample') {
                    sh 'mvn clean package'
                    echo "Build and packaging completed."
                }
            }
        }

        stage('Deploy') {
            steps {
                sh "${DOCKER_COMPOSE} -f ${WORKSPACE}/docker-compose.yml up -d"
                echo "Deployment completed."
            }
        }

       stage('OWASP ZAP Scan') {
            steps {
                script {
                    sh '''
                    ${DOCKER} run -d --name zap -u zap -p 8082:8080 -v ${WORKSPACE}:/zap/wrk/:rw owasp/zap2docker-stable:latest zap.sh -daemon -port 8080 -config api.disablekey=true
                    sleep 15
                    ${DOCKER} exec zap zap-cli status -t 120
                    ${DOCKER} exec zap zap-cli open-url http://174.138.63.154:8081/your-app
                    ${DOCKER} exec zap zap-cli spider http://174.138.63.154:8081/your-app
                    ${DOCKER} exec zap zap-cli active-scan --scanners all http://174.138.63.154:8081/your-app
                    ${DOCKER} exec zap zap-cli report -o /zap/wrk/zap_report.html -f html
                    ${DOCKER} stop zap
                    ${DOCKER} rm zap
                    '''
                }
                echo "OWASP ZAP scan completed."
            }
        }

        stage('IaC Validation') {
            steps {
                sh '''
                cd terraform
                terraform init
                terraform validate
                '''
                echo "Terraform validation completed."
            }
        }

        stage('Terraform Apply') {
            steps {
                withCredentials([string(credentialsId: 'digitalocean_token', variable: 'DO_TOKEN'),
                                 string(credentialsId: 'digitalocean_region', variable: 'DO_REGION')]) {
                    sh '''
                    cd terraform
                    terraform apply -var "digitalocean_token=${DO_TOKEN}" -var "region=${DO_REGION}" -auto-approve
                    '''
                    echo "Terraform apply completed."
                }
            }
        }
    }

    post {
        always {
            echo 'Cleaning up workspace'
            script {
                if (fileExists("${WORKSPACE}/docker-compose.yml")) {
                    sh "${DOCKER_COMPOSE} -f ${WORKSPACE}/docker-compose.yml down"
                }
            }
            cleanWs(patterns: [[pattern: 'target/**/*', type: 'INCLUDE']]) 
        }
        success {
            echo "SUCCESS: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' was successful. \nCheck it out at ${env.BUILD_URL}"
        }
        failure {
            echo "FAILURE: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' failed. \nCheck it out at ${env.BUILD_URL}"
        }
    }
}
