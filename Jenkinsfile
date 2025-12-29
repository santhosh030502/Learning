pipeline {
    agent any

    stages {
        stage('Run Elasticsearch Setup Script') {
            steps {
                sh '''
                chmod +x setup_elasticsearch.sh
                ./setup_elasticsearch.sh
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

