pipeline {
    agent any

    environment {
        AWS_REGION      = 'eu-north-1'
        ECR_REGISTRY    = '016605188495.dkr.ecr.eu-north-1.amazonaws.com'
        ECR_REPO        = 'my-app'
        ASG_NAME        = 'my-app-asg'
        ALB_DNS         = 'my-app-alb-1649148263.eu-north-1.elb.amazonaws.com'
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
        sh """
            # Update deployment tag in SSM
            aws ssm put-parameter \
              --name /myapp/deploy/image-tag \
              --value ${IMAGE_TAG} \
              --type String \
              --overwrite \
              --region ${AWS_REGION}

            echo "SSM updated: ${IMAGE_TAG}"

            # Check if refresh already running
            CURRENT_STATUS=\$(aws autoscaling describe-instance-refreshes \
              --auto-scaling-group-name ${ASG_NAME} \
              --region ${AWS_REGION} \
              --query 'InstanceRefreshes[0].Status' \
              --output text 2>/dev/null || echo "None")

            echo "Current refresh status: \$CURRENT_STATUS"

            if [ "\$CURRENT_STATUS" = "InProgress" ] || \
               [ "\$CURRENT_STATUS" = "Pending" ]; then
                echo "Refresh already running. Waiting for completion..."
                REFRESH_ID=\$(aws autoscaling describe-instance-refreshes \
                  --auto-scaling-group-name ${ASG_NAME} \
                  --region ${AWS_REGION} \
                  --query 'InstanceRefreshes[0].InstanceRefreshId' \
                  --output text)
            else
                REFRESH_ID=\$(aws autoscaling start-instance-refresh \
                  --auto-scaling-group-name ${ASG_NAME} \
                  --preferences '{"MinHealthyPercentage":50,"InstanceWarmup":120}' \
                  --region ${AWS_REGION} \
                  --query InstanceRefreshId \
                  --output text)

                echo "Started refresh: \$REFRESH_ID"
            fi

            echo "Waiting for refresh completion..."

            for i in \$(seq 1 60); do
                STATUS=\$(aws autoscaling describe-instance-refreshes \
                  --auto-scaling-group-name ${ASG_NAME} \
                  --instance-refresh-ids \$REFRESH_ID \
                  --region ${AWS_REGION} \
                  --query 'InstanceRefreshes[0].Status' \
                  --output text)

                echo "Attempt \$i/60 - Status: \$STATUS"

                if [ "\$STATUS" = "Successful" ]; then
                    echo "Refresh completed successfully"
                    exit 0
                fi

                if [ "\$STATUS" = "Failed" ] || \
                   [ "\$STATUS" = "Cancelled" ]; then
                    echo "Refresh failed: \$STATUS"
                    exit 1
                fi

                sleep 15
            done

            echo "Timeout waiting for refresh"
            exit 1
        """
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
            sh """
                # Rollback: write previous tag to SSM and trigger another refresh
                # For now, cancel any in-progress refresh
                aws autoscaling cancel-instance-refresh \
                  --auto-scaling-group-name ${ASG_NAME} \
                  --region ${AWS_REGION} || true

                echo "Rollback: to roll back manually, re-run the previous successful build"
            """

            withCredentials([string(credentialsId: 'slack-webhook-url', variable: 'SLACK_URL')]) {
                sh """
                    curl -s -X POST \$SLACK_URL \
                        -H 'Content-type: application/json' \
                        -d '{
                            "text": ":x: *Deploy FAILED* — `${ECR_REPO}` @ `${IMAGE_TAG}` — check console for details",
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