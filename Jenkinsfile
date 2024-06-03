pipeline {
    agent any  // Use any available agent

    environment {
        VERSION = '0.1.0'
        RELEASE_VERSION = 'R.2'
        SONAR_HOST_URL = 'http://http://174.138.63.154/:9000'  // Using Docker service name as hostname
        // Ensure the following paths are correct for your environment
        SCANNER_HOME = tool name: 'SonarQubeScanner', type: 'hudson.plugins.sonar.SonarRunnerInstallation'
        DIGITALOCEAN_TOKEN = credentials('digitalocean_token')
        DIGITALOCEAN_REGION = credentials('digitalocean_region')
        DOCKER_COMPOSE = '/usr/local/bin/docker-compose' // Full path to docker-compose
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
                    sh 'mvn test -X'  // Enable Maven debug output
                    echo "Unit tests completed."
                }
            }
        }

        stage('SonarQube Analysis') {
            steps {
                dir('java-tomcat-sample') {
                    script {
                        withSonarQubeEnv('SonarQubeServer') {
                            // Using 'mvn -X' for verbose output
                            sh 'mvn clean verify sonar:sonar -X'
                            echo "SonarQube analysis completed."
                        }
                    }
                }
            }
        }

        stage('Build and Package') {
            steps {
                dir('java-tomcat-sample') {
                    sh 'mvn clean package'  // Enable Maven debug output
                    echo "Build and packaging completed."
                }
            }
        }

        stage('OWASP ZAP Scan') {
            steps {
                sh '''
                docker run -d --name zap -u zap -p 8081:8080 -v $(pwd):/zap/wrk/:rw owasp/zap2docker-stable zap.sh -daemon -port 8080 -config api.disablekey=true
                sleep 15
                docker exec zap zap-cli status -t 120
                docker exec zap zap-cli open-url http://your-application-url
                docker exec zap zap-cli spider http://your-application-url
                docker exec zap zap-cli active-scan --scanners all http://your-application-url
                docker exec zap zap-cli report -o /zap/wrk/zap_report.html -f html
                docker stop zap
                docker rm zap
                '''
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

        stage('Deploy') {
            steps {
                sh "${DOCKER_COMPOSE} -f ${WORKSPACE}/docker-compose.yml up -d" // Use docker-compose from the repository
                echo "Deployment completed."
            }
        }
    }

    post {
        always {
            echo 'Cleaning up workspace'
            sh "${DOCKER_COMPOSE} -f ${WORKSPACE}/docker-compose.yml down" // Use docker-compose from the repository
            deleteDir()
        }
        success {
            emailext subject: "SUCCESS: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]'",
                    body: "Great news! The job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' was successful. \nCheck it out at ${env.BUILD_URL}",
                    to: 'your_email@example.com'
        }
        failure {
            emailext subject: "FAILURE: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]'",
                    body: "Unfortunately, the job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' failed. \nCheck it out at ${env.BUILD_URL}",
                    to: 'your_email@example.com'
        }
    }
}
