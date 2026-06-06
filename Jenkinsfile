pipeline {
    agent any

    environment {
        AWS_REGION      = 'eu-north-1'
        ECR_REGISTRY    = '016605188495.dkr.ecr.eu-north-1.amazonaws.com'
        ECR_REPO        = 'my-app'
        IMAGE_TAG       = "${env.GIT_COMMIT?.take(7) ?: 'latest'}"
        FULL_IMAGE      = "${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}"
        ALB_DNS         = 'my-app-alb-1649148263.eu-north-1.elb.amazonaws.com'

        // ASG names for each slot
        BLUE_ASG        = 'my-app-asg-blue'
        GREEN_ASG       = 'my-app-asg-green'

        // SSM paths
        SSM_ACTIVE_SLOT = '/myapp/deploy/active-slot'
        SSM_IMAGE_TAG   = '/myapp/deploy/image-tag'
        SSM_LISTENER    = '/myapp/infra/listener-arn'
        SSM_TEST_LIST   = '/myapp/infra/test-listener-arn'
        SSM_BLUE_TG     = '/myapp/infra/tg-blue-arn'
        SSM_GREEN_TG    = '/myapp/infra/tg-green-arn'
    }

    options {
        timeout(time: 30, unit: 'MINUTES')
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
                              console.log('Smoke test passed');
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
                sh "docker build -t ${FULL_IMAGE} -t ${ECR_REGISTRY}/${ECR_REPO}:latest ."
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

        // ── 5. DETERMINE SLOTS ───────────────────────────────────────────────
        stage('Determine Slots') {
            steps {
                script {
                    // Read which slot is currently LIVE
                    env.ACTIVE_SLOT = sh(
                        script: """aws ssm get-parameter \
                            --name ${SSM_ACTIVE_SLOT} \
                            --region ${AWS_REGION} \
                            --query Parameter.Value \
                            --output text""",
                        returnStdout: true
                    ).trim()

                    // The IDLE slot is where we deploy the new version
                    env.IDLE_SLOT = (env.ACTIVE_SLOT == 'blue') ? 'green' : 'blue'

                    env.IDLE_ASG  = (env.IDLE_SLOT  == 'blue') ? "${BLUE_ASG}"  : "${GREEN_ASG}"
                    env.LIVE_ASG  = (env.ACTIVE_SLOT == 'blue') ? "${BLUE_ASG}"  : "${GREEN_ASG}"

                    echo "Active (LIVE) slot: ${env.ACTIVE_SLOT} → ASG: ${env.LIVE_ASG}"
                    echo "Idle  (NEXT) slot: ${env.IDLE_SLOT}  → ASG: ${env.IDLE_ASG}"
                }
            }
        }

        // ── 6. SCALE UP IDLE SLOT ────────────────────────────────────────────
        stage('Scale Up Idle Slot') {
            steps {
                sh """
                    # Store the new image tag in SSM
                    aws ssm put-parameter \
                      --name ${SSM_IMAGE_TAG} \
                      --value ${IMAGE_TAG} \
                      --type String \
                      --overwrite \
                      --region ${AWS_REGION}

                    # Get current live ASG size and match it in idle slot
                    LIVE_SIZE=\$(aws autoscaling describe-auto-scaling-groups \
                      --auto-scaling-group-names ${env.LIVE_ASG} \
                      --region ${AWS_REGION} \
                      --query 'AutoScalingGroups[0].DesiredCapacity' \
                      --output text)

                    echo "Scaling idle ASG (${env.IDLE_ASG}) to \$LIVE_SIZE instances..."

                    aws autoscaling update-auto-scaling-group \
                      --auto-scaling-group-name ${env.IDLE_ASG} \
                      --desired-capacity \$LIVE_SIZE \
                      --min-size 1 \
                      --region ${AWS_REGION}

                    echo "Waiting for idle instances to become healthy in test TG..."

                    # Wait up to 5 min for desired count to reach InService
                    for i in \$(seq 1 30); do
                        HEALTHY=\$(aws autoscaling describe-auto-scaling-groups \
                          --auto-scaling-group-names ${env.IDLE_ASG} \
                          --region ${AWS_REGION} \
                          --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`] | length(@)' \
                          --output text)

                        echo "Attempt \$i/30 — InService: \$HEALTHY / \$LIVE_SIZE"

                        if [ "\$HEALTHY" -ge "\$LIVE_SIZE" ]; then
                            echo "Idle slot is healthy!"
                            break
                        fi

                        if [ "\$i" -eq "30" ]; then
                            echo "Timeout: idle slot did not become healthy"
                            exit 1
                        fi

                        sleep 10
                    done
                """
            }
        }

        // ── 7. SMOKE TEST IDLE SLOT (via test listener on port 8080) ─────────
        stage('Smoke Test Idle Slot') {
            steps {
                sh """
                    # Flip the TEST listener to point to the idle slot first
                    IDLE_TG_ARN=\$(aws ssm get-parameter \
                      --name /myapp/infra/tg-${env.IDLE_SLOT}-arn \
                      --region ${AWS_REGION} \
                      --query Parameter.Value \
                      --output text)

                    TEST_LISTENER_ARN=\$(aws ssm get-parameter \
                      --name ${SSM_TEST_LIST} \
                      --region ${AWS_REGION} \
                      --query Parameter.Value \
                      --output text)

                    aws elbv2 modify-listener \
                      --listener-arn \$TEST_LISTENER_ARN \
                      --default-actions Type=forward,TargetGroupArn=\$IDLE_TG_ARN \
                      --region ${AWS_REGION}

                    echo "Smoke-testing new version via port 8080..."
                    for i in \$(seq 1 12); do
                        STATUS=\$(curl -s -o /dev/null -w "%{http_code}" \
                            http://${ALB_DNS}:8080/check --max-time 5 || echo "000")
                        echo "Attempt \$i: HTTP \$STATUS"
                        if [ "\$STATUS" = "200" ]; then
                            echo "Smoke test passed — new version is healthy."
                            exit 0
                        fi
                        sleep 5
                    done
                    echo "ERROR: New version did not pass smoke test on port 8080"
                    exit 1
                """
            }
        }

        // ── 8. CUTOVER — flip production listener to idle slot ────────────────
        stage('Cutover') {
            steps {
                sh """
                    IDLE_TG_ARN=\$(aws ssm get-parameter \
                      --name /myapp/infra/tg-${env.IDLE_SLOT}-arn \
                      --region ${AWS_REGION} \
                      --query Parameter.Value \
                      --output text)

                    PROD_LISTENER_ARN=\$(aws ssm get-parameter \
                      --name ${SSM_LISTENER} \
                      --region ${AWS_REGION} \
                      --query Parameter.Value \
                      --output text)

                    echo "Switching PRODUCTION traffic to ${env.IDLE_SLOT} slot..."

                    aws elbv2 modify-listener \
                      --listener-arn \$PROD_LISTENER_ARN \
                      --default-actions Type=forward,TargetGroupArn=\$IDLE_TG_ARN \
                      --region ${AWS_REGION}

                    echo "Traffic now on: ${env.IDLE_SLOT}"

                    # Persist new active slot to SSM
                    aws ssm put-parameter \
                      --name ${SSM_ACTIVE_SLOT} \
                      --value ${env.IDLE_SLOT} \
                      --type String \
                      --overwrite \
                      --region ${AWS_REGION}
                """
            }
        }

        // ── 9. POST-CUTOVER VERIFY ────────────────────────────────────────────
        stage('Verify') {
            steps {
                sh """
                    echo "Verifying production is serving the new version..."
                    for i in \$(seq 1 12); do
                        STATUS=\$(curl -s -o /dev/null -w "%{http_code}" \
                            http://${ALB_DNS}/check --max-time 5 || echo "000")
                        echo "Attempt \$i: HTTP \$STATUS"
                        if [ "\$STATUS" = "200" ]; then
                            echo "Production verified — deployment complete."
                            exit 0
                        fi
                        sleep 5
                    done
                    echo "ERROR: Production health check failed after cutover"
                    exit 1
                """
            }
        }

        // ── 10. SCALE DOWN OLD ACTIVE SLOT ───────────────────────────────────
        stage('Drain Old Slot') {
            steps {
                sh """
                    echo "Draining old ${env.ACTIVE_SLOT} slot (${env.LIVE_ASG})..."

                    # Give connections time to drain (ALB deregistration delay is 30s by default)
                    sleep 40

                    aws autoscaling update-auto-scaling-group \
                      --auto-scaling-group-name ${env.LIVE_ASG} \
                      --desired-capacity 0 \
                      --min-size 0 \
                      --region ${AWS_REGION}

                    echo "Old slot scaled to 0. Ready for next deploy."
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
                            "text": ":large_green_circle: *Deploy succeeded* — \`${ECR_REPO}\` @ \`${IMAGE_TAG}\` → *${env.IDLE_SLOT ?: 'new'}* slot",
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
            script {
                // Rollback: if cutover already happened, flip listener back to the original active slot
                sh """
                    CURRENT_SLOT=\$(aws ssm get-parameter \
                      --name ${SSM_ACTIVE_SLOT} \
                      --region ${AWS_REGION} \
                      --query Parameter.Value \
                      --output text 2>/dev/null || echo "${env.ACTIVE_SLOT ?: 'blue'}")

                    ROLLBACK_SLOT=\$([ "\$CURRENT_SLOT" = "blue" ] && echo "green" || echo "blue")

                    # Only flip back if we already cut over (i.e. CURRENT_SLOT changed)
                    if [ "\$CURRENT_SLOT" != "${env.ACTIVE_SLOT ?: 'blue'}" ]; then
                        echo "Rolling back: switching listener back to \$ROLLBACK_SLOT..."

                        ROLLBACK_TG=\$(aws ssm get-parameter \
                          --name /myapp/infra/tg-\$ROLLBACK_SLOT-arn \
                          --region ${AWS_REGION} \
                          --query Parameter.Value \
                          --output text)

                        PROD_LISTENER_ARN=\$(aws ssm get-parameter \
                          --name ${SSM_LISTENER} \
                          --region ${AWS_REGION} \
                          --query Parameter.Value \
                          --output text)

                        aws elbv2 modify-listener \
                          --listener-arn \$PROD_LISTENER_ARN \
                          --default-actions Type=forward,TargetGroupArn=\$ROLLBACK_TG \
                          --region ${AWS_REGION}

                        aws ssm put-parameter \
                          --name ${SSM_ACTIVE_SLOT} \
                          --value \$ROLLBACK_SLOT \
                          --type String \
                          --overwrite \
                          --region ${AWS_REGION}

                        echo "Rolled back to \$ROLLBACK_SLOT."
                    else
                        echo "Cutover never happened — no listener rollback needed."
                        # Scale idle slot back to 0 to avoid cost
                        aws autoscaling update-auto-scaling-group \
                          --auto-scaling-group-name ${env.IDLE_ASG ?: GREEN_ASG} \
                          --desired-capacity 0 \
                          --min-size 0 \
                          --region ${AWS_REGION} || true
                    fi
                """
            }

            withCredentials([string(credentialsId: 'slack-webhook-url', variable: 'SLACK_URL')]) {
                sh """
                    curl -s -X POST \$SLACK_URL \
                        -H 'Content-type: application/json' \
                        -d '{
                            "text": ":x: *Deploy FAILED* — \`${ECR_REPO}\` @ \`${IMAGE_TAG}\` — rollback triggered",
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
            sh "docker image prune -f --filter 'until=24h' || true"
            cleanWs()
        }
    }
}