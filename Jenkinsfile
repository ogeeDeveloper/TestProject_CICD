pipeline {
    agent any

    environment {
        SONARQUBE_ENV = 'SonarQubeServer'
        SCANNER_HOME = '/opt/sonar-scanner'
        DIGITALOCEAN_TOKEN = credentials('digitalocean_token')
        DIGITALOCEAN_REGION = credentials('digitalocean_region')
    }

    stages {
        stage('Checkout') {
            steps {
                git url: 'https://github.com/ogeeDeveloper/Jenkins_Upgradev3.git', branch: 'master' // or 'main' depending on your repository's default branch
            }
        }

        stage('Build') {
            steps {
                withMaven(maven: 'Maven') {
                    sh 'mvn clean install'
                }
            }
        }

        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('SonarQubeServer') {
                    sh "${SCANNER_HOME}/bin/sonar-scanner -Dsonar.projectKey=java-tomcat-sample -Dsonar.sources=src -Dsonar.host.url=${SONARQUBE_ENV} -Dsonar.login=${SONARQUBE_LOGIN}"
                }
            }
        }

        stage('IaC Validation') {
            steps {
                sh '''
                cd terraform
                terraform init
                terraform validate
                '''
            }
        }

        stage('OWASP ZAP Scan') {
            steps {
                sh 'echo "Running OWASP ZAP scan"'
                // Add your OWASP ZAP scan commands here
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
                }
            }
        }

        stage('Deploy') {
            steps {
                sh 'docker-compose up -d'
            }
        }
    }

    post {
        always {
            echo 'Cleaning up...'
            sh 'docker-compose down'
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
