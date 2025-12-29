pipeline {
    agent any

    stages {

        stage('Checkout Code') {
            steps {
                echo 'Cloning repository from GitHub'
                git 'git@github.com:santhosh030502/Learning.git'
            }
        }

        stage('Run Elasticsearch Setup Script') {
            steps {
                echo 'Running Elasticsearch onboarding script'
                sh '''
                    chmod +x scripts/setup_elasticsearch.sh
                    bash scripts/setup_elasticsearch.sh
                '''
            }
        }
    }

    post {
        success {
            echo '✅ Elasticsearch setup completed successfully'
        }
        failure {
            echo '❌ Elasticsearch setup failed'
        }
    }
}

