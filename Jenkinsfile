pipeline {
    agent any

    environment {
        AWS_REGION      = 'eu-north-1'
        ECR_REGISTRY    = '016605188495.dkr.ecr.eu-north-1.amazonaws.com'
        ECR_REPO        = 'my-app'
        APP_EC2_IP      = '10.0.1.68'
        ALB_DNS         = 'my-app-alb-2033694162.eu-north-1.elb.amazonaws.com'
        IMAGE_TAG       = "${env.GIT_COMMIT?.take(7) ?: 'latest'}"
        FULL_IMAGE      = "${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}"
    }

    options {
        timeout(time: 20, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10'))
        disableConcurrentBuilds()
    }

    stages {

        // ── 1. CHECKOUT ──────────────────────────────────────────────────────
        stage('Checkout') {
            steps {
                checkout scm
                echo "Building commit ${IMAGE_TAG} on branch ${env.BRANCH_NAME}"
            }
        }

        // ── 2. BUILD & TEST ──────────────────────────────────────────────────
        stage('Build & Test') {
            steps {
                dir('.') {
                    sh 'npm ci --prefer-offline'
                    sh '''
                        node -e "
                          const app = require('./app');
                          const http = require('http');
                          const server = app.listen(3999, () => {
                            http.get('http://localhost:3999/check', (res) => {
                              if (res.statusCode !== 200) {
                                server.close();
                                process.exit(1);
                              }
                              console.log('Smoke test passed — /check returned 200');
                              server.close();
                            }).on('error', (e) => { server.close(); console.error(e); process.exit(1); });
                          });
                        "
                    '''
                }
            }
        }

        // ── 3. DOCKER BUILD ──────────────────────────────────────────────────
        stage('Docker Build') {
            steps {
                dir('.') {
                    sh "docker build -t ${FULL_IMAGE} -t ${ECR_REGISTRY}/${ECR_REPO}:latest ."
                }
            }
        }

        // ── 4. ECR PUSH ──────────────────────────────────────────────────────
        stage('ECR Push') {
            steps {
                sh """
                    aws ecr get-login-password --region ${AWS_REGION} \
                      | docker login --username AWS --password-stdin ${ECR_REGISTRY}
                    docker push ${FULL_IMAGE}
                    docker push ${ECR_REGISTRY}/${ECR_REPO}:latest
                """
            }
        }

        // ── 5. DEPLOY ─────────────────────────────────────────────────────────
        stage('Deploy') {
            steps {
                sshagent(credentials: ['ec2-ssh-key']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 ubuntu@${APP_EC2_IP} '
                            set -e

                            # Authenticate with ECR
                            aws ecr get-login-password --region ${AWS_REGION} \
                              | docker login --username AWS --password-stdin ${ECR_REGISTRY}

                            # Pull the new image
                            docker pull ${FULL_IMAGE}

                            # Graceful replacement: start new, stop old
                            docker stop my-app 2>/dev/null || true
                            docker rm   my-app 2>/dev/null || true

                            docker run -d \
                                --name my-app \
                                --restart unless-stopped \
                                -p 3000:3000 \
                                -e NODE_ENV=production \
                                ${FULL_IMAGE}

                            echo "Container started — waiting for health check..."
                            sleep 5
                            docker inspect --format="{{.State.Health.Status}}" my-app
                        '
                    """
                }
            }
        }

        // ── 6. VERIFY ────────────────────────────────────────────────────────
        stage('Verify') {
            steps {
                sh """
                    echo "Polling ALB health check..."
                    for i in \$(seq 1 12); do
                        STATUS=\$(curl -s -o /dev/null -w "%{http_code}" \
                            http://${ALB_DNS}/check --max-time 5 || echo "000")
                        echo "Attempt \$i: HTTP \$STATUS"
                        if [ "\$STATUS" = "200" ]; then
                            echo "Deployment verified — app is live."
                            exit 0
                        fi
                        sleep 5
                    done
                    echo "ERROR: App did not become healthy after 60s"
                    exit 1
                """
            }
        }
    }

    // ── POST ──────────────────────────────────────────────────────────────────
    post {
        success {
            withCredentials([string(credentialsId: 'slack-webhook-url', variable: 'SLACK_URL')]) {
                sh """
                    curl -s -X POST \$SLACK_URL \
                        -H 'Content-type: application/json' \
                        -d '{
                            "text": ":white_check_mark: *Deploy succeeded* — `${ECR_REPO}` @ `${IMAGE_TAG}`",
                            "attachments": [{
                                "color": "#36a64f",
                                "fields": [
                                    {"title": "Branch",  "value": "${env.BRANCH_NAME}", "short": true},
                                    {"title": "Build",   "value": "#${env.BUILD_NUMBER}", "short": true},
                                    {"title": "App URL", "value": "http://${ALB_DNS}",   "short": false}
                                ]
                            }]
                        }'
                """
            }
        }

        failure {
            // Attempt rollback to previous :latest before this build pushed a new one
            sshagent(credentials: ['ec2-ssh-key']) {
                sh """
                    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 ubuntu@${APP_EC2_IP} '
                        PREV=\$(docker images ${ECR_REGISTRY}/${ECR_REPO} \
                                    --format "{{.Tag}} {{.CreatedAt}}" \
                                    | sort -k2 -r | awk "NR==2{print \$1}")
                        if [ -n "\$PREV" ]; then
                            echo "Rolling back to tag: \$PREV"
                            docker stop my-app 2>/dev/null || true
                            docker rm   my-app 2>/dev/null || true
                            docker run -d \
                                --name my-app \
                                --restart unless-stopped \
                                -p 3000:3000 \
                                -e NODE_ENV=production \
                                ${ECR_REGISTRY}/${ECR_REPO}:\$PREV
                        else
                            echo "No previous image found — skipping rollback"
                        fi
                    ' || true
                """
            }

            withCredentials([string(credentialsId: 'slack-webhook-url', variable: 'SLACK_URL')]) {
                sh """
                    curl -s -X POST \$SLACK_URL \
                        -H 'Content-type: application/json' \
                        -d '{
                            "text": ":x: *Deploy FAILED* — `${ECR_REPO}` @ `${IMAGE_TAG}` — rollback attempted",
                            "attachments": [{
                                "color": "#e01e5a",
                                "fields": [
                                    {"title": "Branch",   "value": "${env.BRANCH_NAME}",  "short": true},
                                    {"title": "Build",    "value": "#${env.BUILD_NUMBER}", "short": true},
                                    {"title": "Logs",     "value": "${env.BUILD_URL}console", "short": false}
                                ]
                            }]
                        }'
                """
            }
        }

        always {
            // Clean up local Docker images to save Jenkins disk space
            sh "docker image prune -f --filter 'until=24h' || true"
            cleanWs()
        }
    }
}