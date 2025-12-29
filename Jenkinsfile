pipeline {
    agent any

    stages {
        stage('Run Elasticsearch Setup Script') {
            steps {
                sh '''
                chmod +x scripts/setup_elasticsearch.sh
                scripts/setup_elasticsearch.sh
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

